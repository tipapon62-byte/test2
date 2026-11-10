-- EggService: the whole egg lifecycle, server authoritative.
--   Nest  -> (grab)  -> Carried -> (deliver in own base) -> incubator pad / egg shelf -> hatch
--                     Carried -> (tagged / trapped / hazard / drop / leave) -> Dropped -> anyone grabs
--                     Dropped -> (nobody grabs in time) -> flies back to its nest
-- The client never decides ownership: prompts are triggered on the server, distances and
-- states are re-checked here, and only delivery into the carrier's own base makes an egg owned.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local ModelFactory = require(Shared:WaitForChild("ModelFactory"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local S = GameConfig.Settings
local R = GameConfig.Rarities
local E = GameConfig.Economy

local EggService = {}
local Services

local EGG_SHELF_CAP = 8

type WorldEgg = {
	Data: any,            -- EggData
	Model: Model,
	State: string,        -- "Nest" | "Carried" | "Dropped"
	Nest: BasePart?,
	ZoneIndex: number,
	Carrier: Player?,
	Weld: WeldConstraint?,
	DroppedAt: number,
	DroppedBy: number?,   -- UserId of the last carrier when it hit the ground
	PickedAt: number,
	ExpiresAt: number?,   -- special spawns vanish after this (os.clock)
}

local eggs: { [string]: WorldEgg } = {}
local carrying: { [Player]: WorldEgg } = {}
local nestState: { [BasePart]: { Egg: WorldEgg?, RespawnAt: number, Zone: number } } = {}
local padModels: { [Player]: { [number]: Model } } = {}
local fullWarned: { [Player]: number } = {}
local eggFolder: Instance

-- ===== Rolls =====

local function rollSize(): string
	local w = {}
	for id, s in pairs(R.Sizes) do
		w[id] = s.Weight
	end
	return Util.WeightedPick(w, R.SizeOrder) or "Normal"
end

local function rollMutation(boost: number, allowEvent: string?): string?
	for _, id in ipairs(R.MutationOrder) do
		local m = R.Mutations[id]
		if (not m.EventOnly or id == allowEvent) and math.random() < m.Chance * boost then
			return id
		end
	end
	return nil
end

local function rollRarity(biome, rarityBoost: number): string
	local w = {}
	for rarity, weight in pairs(biome.EggWeights) do
		-- boost scales everything above Common so rarer eggs become more likely
		w[rarity] = if R.ById[rarity].Index > 1 then weight * rarityBoost else weight
	end
	return Util.WeightedPick(w, R.Order) or "Common"
end

function EggService.BestBiome(profile)
	local best = GameConfig.Biomes[1]
	for _, b in ipairs(GameConfig.Biomes) do
		if profile.Biomes[b.Id] then
			best = b
		end
	end
	return best
end

-- ===== World egg models =====

local function setEggAttributes(egg: WorldEgg)
	local m, d = egg.Model, egg.Data
	m:SetAttribute("Uid", d.Uid)
	m:SetAttribute("Biome", d.Biome)
	m:SetAttribute("Rarity", d.Rarity)
	m:SetAttribute("Size", d.Size)
	m:SetAttribute("Mutation", d.Mutation)
	m:SetAttribute("State", egg.State)
	m:SetAttribute("CarrierId", if egg.Carrier then egg.Carrier.UserId else 0)
end

local function prompt(egg: WorldEgg): ProximityPrompt?
	local root = egg.Model.PrimaryPart
	return root and root:FindFirstChild("GrabPrompt") :: ProximityPrompt?
end

local function setPrompt(egg: WorldEgg, enabled: boolean)
	local p = prompt(egg)
	if p then
		p.Enabled = enabled
		p.ActionText = if egg.State == "Dropped" then "Pick up" else "Steal egg"
	end
end

local function buildEggModel(data): Model
	local ok, model = pcall(ModelFactory.BuildEgg, data.Biome, data.Rarity, { Size = data.Size, Mutation = data.Mutation })
	if not ok or not model then
		warn("[EggService] BuildEgg failed:", model)
		model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(2.6, 3.4, 2.6)
		root.Anchored = true
		root.CanCollide = false
		root.Color = R.ById[data.Rarity].Color
		root.Parent = model
		model.PrimaryPart = root
	end
	model.Name = "Egg_" .. data.Uid
	local root = model.PrimaryPart :: BasePart
	local p = Instance.new("ProximityPrompt")
	p.Name = "GrabPrompt"
	p.ObjectText = GameConfig.EggDisplayName(data)
	p.ActionText = "Steal egg"
	p.HoldDuration = 0.25
	p.MaxActivationDistance = S.NestGrabDistance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Style = Enum.ProximityPromptStyle.Default
	p.Parent = root
	return model
end

local function nestCFrame(nest: BasePart): CFrame
	-- map nests are cylinders lying flat (height along X)
	local h = if (nest :: any).Shape == Enum.PartType.Cylinder then nest.Size.X else nest.Size.Y
	return CFrame.new(nest.Position + Vector3.new(0, h / 2 - 0.3, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
end

local function spawnInNest(nest: BasePart, override: any?)
	local st = nestState[nest]
	local zone = Services.BiomeService.GetZone(st.Zone)
	local event = Services.EventService.GetActive()
	local data = override or {
		Uid = Util.Uid("e"),
		Biome = zone.Biome.Id,
		Rarity = rollRarity(zone.Biome, event and event.RarityBoost or 1),
		Size = rollSize(),
		Mutation = rollMutation(event and event.MutationBoost or 1, event and event.EventMutation),
	}
	local egg: WorldEgg = {
		Data = data,
		Model = buildEggModel(data),
		State = "Nest",
		Nest = nest,
		ZoneIndex = st.Zone,
		Carrier = nil,
		Weld = nil,
		DroppedAt = 0,
		DroppedBy = nil,
		PickedAt = 0,
		ExpiresAt = nil,
	}
	egg.Model:PivotTo(nestCFrame(nest))
	setEggAttributes(egg)
	CollectionService:AddTag(egg.Model, "RR_Egg")
	egg.Model.Parent = eggFolder
	eggs[data.Uid] = egg
	st.Egg = egg
	return egg
end

local function destroyEgg(egg: WorldEgg)
	eggs[egg.Data.Uid] = nil
	if egg.Nest and nestState[egg.Nest] and nestState[egg.Nest].Egg == egg then
		local st = nestState[egg.Nest]
		st.Egg = nil
		local event = Services.EventService.GetActive()
		local zone = Services.BiomeService.GetZone(st.Zone)
		st.RespawnAt = os.clock() + zone.Biome.NestRespawn * (event and event.NestRespawnMult or 1)
	end
	egg.Model:Destroy()
end

local function clearCarrier(player: Player)
	carrying[player] = nil
	player:SetAttribute("CarryingEgg", "")
	player:SetAttribute("CarryingRarity", "")
	Services.SpeedService.SetModifier(player, "Carry", nil)
end

-- Puts the egg back in its nest (or removes it if the nest already regrew).
local function returnToNest(egg: WorldEgg)
	if egg.Carrier then
		clearCarrier(egg.Carrier)
		egg.Carrier = nil
	end
	if egg.Weld then
		egg.Weld:Destroy()
		egg.Weld = nil
	end
	local st = egg.Nest and nestState[egg.Nest]
	if egg.Nest and st and (st.Egg == egg or st.Egg == nil) then
		local root = egg.Model.PrimaryPart :: BasePart
		root.Anchored = true
		egg.State = "Nest"
		egg.DroppedBy = nil
		st.Egg = egg
		egg.Model:PivotTo(nestCFrame(egg.Nest))
		setEggAttributes(egg)
		setPrompt(egg, true)
	else
		destroyEgg(egg)
	end
end

local function attach(egg: WorldEgg, player: Player)
	local character = player.Character :: Model
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local root = egg.Model.PrimaryPart :: BasePart
	local scale = egg.Model:GetScale()
	local lift = 3.4 + 0.6 * scale
	egg.Model:PivotTo(hrp.CFrame * CFrame.new(0, lift, 0))
	root.Anchored = false
	root.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = hrp
	w.Part1 = root
	w.Parent = root
	egg.Weld = w
	pcall(function()
		root:SetNetworkOwner(player)
	end)
end

-- ===== Public API =====

function EggService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function EggService.GetCarried(player: Player)
	local egg = carrying[player]
	return egg and egg.Data or nil
end

function EggService.GetCarriers(): { [Player]: any }
	local out = {}
	for p, egg in pairs(carrying) do
		out[p] = { Data = egg.Data, ZoneIndex = egg.ZoneIndex, Nest = egg.Nest }
	end
	return out
end

function EggService.Grab(player: Player, egg: WorldEgg): boolean
	if egg.State == "Carried" or carrying[player] then
		return false
	end
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or hum.Health <= 0 or not hrp then
		return false
	end
	if Services.CombatService.IsCrowdControlled(player) then
		return false
	end
	if (hrp.Position - egg.Model:GetPivot().Position).Magnitude > S.NestGrabDistance + 4 then
		return false -- distance re-check: prompts can be spoofed by exploiters
	end
	if egg.State == "Dropped" and egg.DroppedBy == player.UserId and os.clock() - egg.DroppedAt < S.DroppedEggPickupDelay then
		return false
	end
	if egg.State == "Nest" then
		local ok, reason = Services.BiomeService.CanEnter(player, egg.ZoneIndex)
		if egg.ZoneIndex > 1 and not ok then
			Services.DataService.Notify(player, reason or "You can't take this egg yet.", "warn")
			return false
		end
	end

	local fromNest = egg.State == "Nest"
	egg.State = "Carried"
	egg.Carrier = player
	egg.PickedAt = os.clock()
	carrying[player] = egg
	attach(egg, player)
	setEggAttributes(egg)
	setPrompt(egg, false)
	player:SetAttribute("CarryingEgg", GameConfig.EggDisplayName(egg.Data))
	player:SetAttribute("CarryingRarity", egg.Data.Rarity)
	local size = R.Sizes[egg.Data.Size] or R.Sizes.Normal
	Services.SpeedService.SetModifier(player, "Carry", size.Carry)
	if fromNest then
		Services.GuardianService.OnEggTaken(egg.ZoneIndex, egg.Nest, player, egg.Data)
		Services.DataService.Notify(player, "🏃 RUN HOME! The nest guardian woke up!", "warn")
	end
	return true
end

-- Drops the carried egg on the ground where the player stands.
function EggService.Drop(player: Player, reason: string?): boolean
	local egg = carrying[player]
	if not egg then
		return false
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pos = if hrp then hrp.Position else egg.Model:GetPivot().Position
	clearCarrier(player)
	egg.Carrier = nil
	if egg.Weld then
		egg.Weld:Destroy()
		egg.Weld = nil
	end
	-- an egg dropped inside a base would be unreachable for others; send it home instead
	if Services.BaseService.FindBaseAt(pos) then
		returnToNest(egg)
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { eggFolder, player.Character :: any }
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	local ground = if hit then hit.Position else pos - Vector3.new(0, 3, 0)
	local root = egg.Model.PrimaryPart :: BasePart
	root.Anchored = true
	egg.Model:PivotTo(CFrame.new(ground + Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1)))
	egg.State = "Dropped"
	egg.DroppedAt = os.clock()
	egg.DroppedBy = player.UserId
	setEggAttributes(egg)
	setPrompt(egg, true)
	if reason then
		Services.DataService.Notify(player, "Your egg dropped: " .. reason, "bad")
	end
	return true
end

-- Sends the carried egg straight back to its nest (void pits, rebirth, safety nets).
function EggService.ReturnCarriedEgg(player: Player, reason: string?)
	local egg = carrying[player]
	if egg then
		returnToNest(egg)
		if reason then
			Services.DataService.Notify(player, "Your egg flew back to its nest: " .. reason, "bad")
		end
	end
end

local function hatchCapacity(profile): number
	return E.IncubatorLevels[math.clamp(profile.IncubatorLevel, 1, #E.IncubatorLevels)].Pads
end

local function hatchingCount(profile): number
	return Util.Count(profile.Incubators)
end

function EggService.HasFreeStorage(player: Player): boolean
	local profile = Services.DataService.Get(player)
	if not profile then
		return false
	end
	if hatchingCount(profile) < hatchCapacity(profile) and Services.PetService.FreeSlot(profile) then
		return true
	end
	return #profile.EggStorage < EGG_SHELF_CAP
end

-- Eggs hatch ON an enclosure slot and turn into the pet in that same slot.
local function startOnSlot(profile, slot: number, data)
	local duration = GameConfig.HatchDuration(data.Rarity, data.Size, profile.IncubatorLevel)
	data.Duration = duration
	data.HatchAt = os.time() + duration
	profile.Incubators[tostring(slot)] = data
end

-- Moves queued eggs onto free slots while hatch capacity allows. Returns true if anything moved.
local function fillFromQueue(player: Player, profile): boolean
	local moved = false
	while #profile.EggStorage > 0 and hatchingCount(profile) < hatchCapacity(profile) do
		local slot = Services.PetService.FreeSlot(profile)
		if not slot then
			break
		end
		startOnSlot(profile, slot, table.remove(profile.EggStorage, 1))
		moved = true
	end
	if moved then
		Services.DataService.Changed(player, "Incubators", "EggStorage")
		EggService.RefreshEggs(player)
	end
	return moved
end

-- Gives an owned egg: a free slot if hatch capacity allows, otherwise the waiting queue.
function EggService.GiveEgg(player: Player, data): boolean
	local profile = Services.DataService.Get(player)
	if not profile then
		return false
	end
	local slot = hatchingCount(profile) < hatchCapacity(profile) and Services.PetService.FreeSlot(profile)
	if slot then
		startOnSlot(profile, slot, data)
		Services.DataService.Changed(player, "Incubators")
		EggService.RefreshEggs(player)
		return true
	end
	if #profile.EggStorage < EGG_SHELF_CAP then
		table.insert(profile.EggStorage, data)
		Services.DataService.Changed(player, "EggStorage")
		Services.DataService.Notify(player, "No free slot right now — the egg is waiting in line and will hatch next.", "info")
		return true
	end
	return false
end

-- Moves eggs on slots that are invalid (occupied, beyond the slot count after rebirth, or
-- from older saves that used incubator pads) back into the queue.
function EggService.Revalidate(player: Player)
	local profile = Services.DataService.Get(player)
	if not profile then
		return
	end
	local occupied = {}
	for _, pet in pairs(profile.Pets) do
		if pet.Slot then
			occupied[pet.Slot] = true
		end
	end
	local maxSlots = E.BaseLevels[math.clamp(profile.BaseLevel, 1, #E.BaseLevels)].Slots
	local changed = false
	for key, data in pairs(profile.Incubators) do
		local slot = tonumber(key)
		if not slot or slot > maxSlots or occupied[slot] then
			profile.Incubators[key] = nil
			data.HatchAt = nil
			table.insert(profile.EggStorage, 1, data)
			changed = true
		end
	end
	if changed then
		Services.DataService.Changed(player, "Incubators", "EggStorage")
	end
	fillFromQueue(player, profile)
	EggService.RefreshEggs(player)
end

local function deliver(player: Player, egg: WorldEgg)
	if not EggService.HasFreeStorage(player) then
		if os.clock() - (fullWarned[player] or 0) > 5 then
			fullWarned[player] = os.clock()
			Services.DataService.Notify(player, "Your enclosure and egg queue are full! Sell pets or upgrade your base.", "warn")
		end
		return
	end
	local profile = Services.DataService.Get(player)
	local retrieved = egg.DroppedBy ~= nil and egg.DroppedBy ~= player.UserId
	local data = egg.Data
	clearCarrier(player)
	egg.Carrier = nil
	destroyEgg(egg)
	data.Uid = Util.Uid("e") -- fresh id once owned: the world egg id can never be reused
	EggService.GiveEgg(player, data)
	profile.Stats.EggsDelivered += 1
	Services.QuestService.Track(player, "EggsDelivered", 1)
	Services.QuestService.Track(player, "Biome:" .. data.Biome, 1)
	if retrieved then
		profile.Stats.EggsRetrieved += 1
		Services.QuestService.Track(player, "EggsRetrieved", 1)
	end
	Services.DataService.Changed(player, "Stats")
	Services.DataService.Effect(player, "Coins", { Amount = 0, Text = "🥚 SECURED!" })
	Services.DataService.Notify(player, ("🥚 %s is yours! It's hatching in your enclosure."):format(GameConfig.EggDisplayName(data)), "good")
end

-- ===== Eggs hatching on slots (visuals) =====

function EggService.RefreshEggs(player: Player)
	local info = Services.BaseService.GetBase(player)
	local profile = Services.DataService.Get(player)
	local models = padModels[player] or {}
	padModels[player] = models
	for key, current in pairs(models) do
		local data = profile and profile.Incubators[key]
		if not data or current:GetAttribute("Uid") ~= data.Uid then
			current:Destroy()
			models[key] = nil
		end
	end
	if not info or not profile then
		return
	end
	local folder = info.Runtime:FindFirstChild("Eggs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Eggs"
		folder.Parent = info.Runtime
	end
	for key, data in pairs(profile.Incubators) do
		local current = models[key]
		if current then
			current:SetAttribute("HatchAt", data.HatchAt)
			continue
		end
		local cf = Services.BaseService.GetSlotCFrame(info, tonumber(key) :: number)
		local ok, m = pcall(ModelFactory.BuildEgg, data.Biome, data.Rarity, { Size = data.Size, Mutation = data.Mutation })
		if cf and ok and m then
			m.Name = "HatchingEgg"
			m:SetAttribute("Uid", data.Uid)
			m:SetAttribute("Biome", data.Biome)
			m:SetAttribute("Rarity", data.Rarity)
			m:SetAttribute("Size", data.Size)
			m:SetAttribute("Mutation", data.Mutation)
			m:SetAttribute("HatchAt", data.HatchAt)
			m:SetAttribute("Duration", data.Duration)
			m:SetAttribute("Slot", tonumber(key))
			m:SetAttribute("OwnerId", player.UserId)
			m:PivotTo(cf)
			local bb = Instance.new("BillboardGui")
			bb.Name = "Timer"
			bb.Size = UDim2.fromOffset(170, 44)
			bb.StudsOffset = Vector3.new(0, (m:GetAttribute("Height") or 4) + 1.2, 0)
			bb.MaxDistance = 60
			bb.LightInfluence = 0
			local t = Instance.new("TextLabel")
			t.Name = "Text"
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextStrokeTransparency = 0
			t.TextColor3 = R.ById[data.Rarity].Color
			t.Text = ""
			t.Parent = bb
			bb.Parent = m.PrimaryPart
			CollectionService:AddTag(m, "RR_IncubatorEgg")
			m.Parent = folder
			models[key] = m
		end
	end
end
EggService.RefreshPads = EggService.RefreshEggs

local function hatchBurst(model: Model?, color: Color3)
	if not model or not model.PrimaryPart then
		return
	end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = model:GetPivot() + Vector3.new(0, 2, 0)
	p.Parent = workspace
	game:GetService("TweenService"):Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(10, 10, 10), Transparency = 1 }):Play()
	game:GetService("Debris"):AddItem(p, 0.6)
end

local function hatch(player: Player, profile, slotKey: string)
	local data = profile.Incubators[slotKey]
	profile.Incubators[slotKey] = nil
	local model = padModels[player] and padModels[player][slotKey]
	hatchBurst(model, R.ById[data.Rarity].Color)
	local pet = Services.PetService.HatchEgg(player, data, tonumber(slotKey))
	Services.DataService.Changed(player, "Incubators")
	EggService.RefreshEggs(player)
	fillFromQueue(player, profile)
	return pet
end

local function speedUp(player: Player, slot: any, currency: any)
	local profile = Services.DataService.Get(player)
	if not profile or type(slot) ~= "number" then
		return
	end
	local data = profile.Incubators[tostring(math.floor(slot))]
	if not data or not data.HatchAt then
		return
	end
	local remaining = data.HatchAt - os.time()
	if remaining <= 0 then
		return
	end
	local biome = GameConfig.GetBiome(data.Biome) or GameConfig.Biomes[1]
	local ok
	if currency == "Shards" then
		ok = Services.DataService.Spend(player, "Shards", math.ceil(remaining / E.SpeedUpSecondsPerShard))
	else
		ok = Services.DataService.Spend(player, "Coins", math.ceil(remaining * E.SpeedUpCoinsPerSecond * biome.IncomeBase))
	end
	if not ok then
		Services.DataService.Notify(player, "Not enough currency to speed this up.", "bad")
		return
	end
	data.HatchAt = os.time()
	Services.DataService.Changed(player, "Incubators")
	EggService.RefreshEggs(player)
end

-- Special spawns (Divine eggs, events): replaces the egg of a random nest in the zone.
function EggService.SpawnSpecial(zoneIndex: number, data, lifetime: number?)
	local zone = Services.BiomeService.GetZone(zoneIndex)
	if not zone or #zone.Nests == 0 then
		return nil
	end
	local candidates = {}
	for _, nest in ipairs(zone.Nests) do
		local st = nestState[nest]
		if not st.Egg or st.Egg.State == "Nest" then
			table.insert(candidates, nest)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local nest = candidates[math.random(#candidates)]
	local st = nestState[nest]
	if st.Egg then
		local old = st.Egg
		eggs[old.Data.Uid] = nil
		old.Model:Destroy()
		st.Egg = nil
	end
	data.Uid = data.Uid or Util.Uid("e")
	data.Biome = data.Biome or zone.Biome.Id
	data.Size = data.Size or rollSize()
	local egg = spawnInNest(nest, data)
	if lifetime then
		egg.ExpiresAt = os.clock() + lifetime
	end
	return egg
end

function EggService.Init(services)
	Services = services
end

function EggService.Start()
	eggFolder = workspace:WaitForChild("RiftRun"):WaitForChild("Eggs")

	for _, zone in ipairs(Services.BiomeService.Zones()) do
		for _, nest in ipairs(zone.Nests) do
			nestState[nest] = { Egg = nil, RespawnAt = 0, Zone = zone.Index }
			spawnInNest(nest)
		end
	end

	ProximityPromptService.PromptTriggered:Connect(function(p, player)
		if p.Name ~= "GrabPrompt" then
			return
		end
		local model = p:FindFirstAncestorOfClass("Model")
		local uid = model and model:GetAttribute("Uid")
		local egg = uid and eggs[uid]
		if egg then
			EggService.Grab(player, egg)
		end
	end)

	local dropLimiter = RateLimiter.new(3, 1)
	Net.Event("DropEgg").OnServerEvent:Connect(function(player)
		if dropLimiter:Allow(player) then
			EggService.Drop(player)
		end
	end)
	local speedLimiter = RateLimiter.new(4, 1)
	Net.Event("SpeedUpHatch").OnServerEvent:Connect(function(player, pad, currency)
		if speedLimiter:Allow(player) then
			speedUp(player, pad, currency)
		end
	end)

	local function onCharacter(player: Player, character: Model)
		local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				EggService.Drop(player, "you were knocked out")
			end)
		end
	end
	local function onPlayer(player: Player)
		player:SetAttribute("CarryingEgg", "")
		player:SetAttribute("CarryingRarity", "")
		player.CharacterAdded:Connect(function(c)
			onCharacter(player, c)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		EggService.Drop(player) -- leaving players drop their egg where they stood
		for _, m in pairs(padModels[player] or {}) do
			m:Destroy()
		end
		padModels[player] = nil
		fullWarned[player] = nil
	end)
	Services.DataService.OnLoaded(function(player, profile)
		profile.EggStorage = profile.EggStorage or {}
		task.wait(1) -- after PetService has sanitized slots
		EggService.Revalidate(player)
	end)

	-- 5 Hz: deliveries, dropped-egg timeouts, carrier sanity
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local now = os.clock()
		for player, egg in pairs(carrying) do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp or not egg.Weld or not egg.Weld.Parent or now - egg.PickedAt > S.CarryMaxSeconds then
				returnToNest(egg)
			else
				local info = Services.BaseService.GetBase(player)
				if info and Services.BaseService.IsInside(info, hrp.Position) then
					deliver(player, egg)
				end
			end
		end
		for _, egg in pairs(eggs) do
			if egg.State == "Dropped" and now - egg.DroppedAt > S.DroppedEggReturnTime then
				returnToNest(egg)
			elseif egg.ExpiresAt and egg.State == "Nest" and now > egg.ExpiresAt then
				destroyEgg(egg)
			end
		end
	end)

	-- 1 Hz: nest regrowth, hatching, pad timers
	task.spawn(function()
		while true do
			task.wait(1)
			local clock = os.clock()
			for nest, st in pairs(nestState) do
				if not st.Egg and clock >= st.RespawnAt then
					spawnInNest(nest)
				end
			end
			local now = os.time()
			for player, profile in pairs(Services.DataService.All()) do
				local due = {}
				for key, data in pairs(profile.Incubators) do
					if data.HatchAt and data.HatchAt <= now then
						table.insert(due, key)
					end
				end
				for _, key in ipairs(due) do
					hatch(player, profile, key)
				end
				fillFromQueue(player, profile)
				for _, m in pairs(padModels[player] or {}) do
					local label = m.PrimaryPart and m.PrimaryPart:FindFirstChild("Timer") and (m.PrimaryPart :: any).Timer:FindFirstChild("Text")
					if label then
						label.Text = "🐣 " .. GameConfig.FormatTime((m:GetAttribute("HatchAt") or now) - now)
					end
				end
			end
		end
	end)
end

return EggService

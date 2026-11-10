-- PetService: hatching, pet inventory (enclosure slots + storage), income, selling, locking,
-- renaming (filtered), mutation potions, the collection Index, and pet models on the base.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local ModelFactory = require(Shared:WaitForChild("ModelFactory"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local R = GameConfig.Rarities
local E = GameConfig.Economy
local P = GameConfig.Progression

local PetService = {}
local Services

local incomeCache: { [Player]: number } = {}
local petModels: { [Player]: { [string]: Model } } = {}

local function slotsOf(profile): number
	return E.BaseLevels[math.clamp(profile.BaseLevel, 1, #E.BaseLevels)].Slots
end

local function freeSlot(profile): number?
	local used = {}
	for _, pet in pairs(profile.Pets) do
		if pet.Slot then
			used[pet.Slot] = true
		end
	end
	for key in pairs(profile.Incubators or {}) do
		local n = tonumber(key)
		if n then
			used[n] = true -- an egg is hatching there
		end
	end
	for i = 1, slotsOf(profile) do
		if not used[i] then
			return i
		end
	end
	return nil
end
PetService.FreeSlot = freeSlot

local function recalcIncome(player: Player)
	local profile = Services.DataService.Get(player)
	if not profile then
		incomeCache[player] = 0
		return 0
	end
	local total = 0
	for _, pet in pairs(profile.Pets) do
		if pet.Slot then
			total += GameConfig.PetIncome(pet)
		end
	end
	total *= GameConfig.IncomeMultiplier(profile.BaseLevel, profile.Rebirths)
	incomeCache[player] = math.floor(total * 10) / 10
	return incomeCache[player]
end

function PetService.GetIncome(player: Player): number
	return incomeCache[player] or recalcIncome(player)
end

local function changed(player: Player)
	recalcIncome(player)
	Services.DataService.Changed(player, "Pets")
	PetService.RefreshBase(player)
end

-- ===== Models on the base =====

local function buildPetModel(player: Player, pet): Model?
	local ok, model = pcall(ModelFactory.BuildPet, pet.Species, { Size = pet.Size, Mutation = pet.Mutation, Tier = pet.Tier })
	if not ok or not model then
		warn("[PetService] BuildPet failed:", model)
		return nil
	end
	local species = GameConfig.GetSpecies(pet.Species)
	local income = GameConfig.PetIncome(pet)
	model.Name = "Pet_" .. pet.Uid
	model:SetAttribute("Uid", pet.Uid)
	model:SetAttribute("Species", pet.Species)
	model:SetAttribute("Rarity", species and species.Rarity or "Common")
	model:SetAttribute("Size", pet.Size)
	model:SetAttribute("Mutation", pet.Mutation)
	model:SetAttribute("Tier", pet.Tier)
	model:SetAttribute("Income", income)
	model:SetAttribute("OwnerId", player.UserId)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Info"
	bb.Size = UDim2.fromOffset(200, 46)
	bb.StudsOffset = Vector3.new(0, (model:GetAttribute("Height") or 4) + 1.2, 0)
	bb.MaxDistance = 45
	bb.LightInfluence = 0
	local function line(text, color, y)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0.5, 0)
		t.Position = UDim2.fromScale(0, y)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextStrokeTransparency = 0
		t.TextColor3 = color
		t.Text = text
		t.Parent = bb
	end
	line(GameConfig.PetDisplayName(pet), R.ById[species and species.Rarity or "Common"].Color, 0)
	line("💰 " .. GameConfig.FormatNumber(income) .. "/s", Color3.fromRGB(255, 230, 110), 0.5)
	bb.Parent = model.PrimaryPart
	CollectionService:AddTag(model, "RR_Pet")
	return model
end

function PetService.RefreshBase(player: Player)
	recalcIncome(player)
	local info = Services.BaseService.GetBase(player)
	local profile = Services.DataService.Get(player)
	local models = petModels[player] or {}
	petModels[player] = models
	local wanted = {}
	if info and profile then
		for uid, pet in pairs(profile.Pets) do
			if pet.Slot then
				wanted[uid] = pet
			end
		end
	end
	for uid, model in pairs(models) do
		local pet = wanted[uid]
		local stale = not pet or model:GetAttribute("Slot") ~= pet.Slot or model:GetAttribute("Tier") ~= pet.Tier
			or model:GetAttribute("Mutation") ~= pet.Mutation or model:GetAttribute("Size") ~= pet.Size
			or model:GetAttribute("Name") ~= pet.Name
		if stale then
			model:Destroy()
			models[uid] = nil
		end
	end
	if not info then
		return
	end
	for uid, pet in pairs(wanted) do
		if not models[uid] then
			local cf = Services.BaseService.GetSlotCFrame(info, pet.Slot)
			local model = cf and buildPetModel(player, pet)
			if model and cf then
				model:SetAttribute("Slot", pet.Slot)
				model:SetAttribute("Name", pet.Name)
				if (info.Scale or 1) < 1 then
					model:ScaleTo(model:GetScale() * math.clamp((info.Scale or 1) * 1.5, 0.6, 1))
				end
				model:PivotTo(cf)
				model.Parent = info.Runtime.Pets
				models[uid] = model
			end
		end
	end
end

-- Moves pets in slots that no longer exist (after rebirth) into storage.
function PetService.StoreOverflow(player: Player)
	local profile = Services.DataService.Get(player)
	if not profile then
		return
	end
	local max = slotsOf(profile)
	for _, pet in pairs(profile.Pets) do
		if pet.Slot and pet.Slot > max then
			pet.Slot = nil
		end
	end
	changed(player)
end

-- ===== Creating pets =====

local function checkBiomeComplete(player: Player, profile, biomeId: string)
	if profile.IndexBiomesDone[biomeId] then
		return
	end
	for _, s in ipairs(GameConfig.Pets) do
		if s.Biome == biomeId and not s.EventOnly and not profile.Index[s.Id] then
			return
		end
	end
	profile.IndexBiomesDone[biomeId] = true
	Services.DataService.AddShards(player, P.IndexBiomeCompleteShards)
	local biome = GameConfig.GetBiome(biomeId)
	Services.DataService.Notify(player, ("📖 %s Index complete! +%d Rift Shards"):format(biome and biome.Name or biomeId, P.IndexBiomeCompleteShards), "good")
	Services.DataService.Changed(player, "IndexBiomesDone")
end

-- Adds a pet (placed if a slot is free). Returns (pet, isNewSpecies).
function PetService.AddPet(player: Player, pet, preferredSlot: number?): (any, boolean)
	local profile = Services.DataService.Get(player)
	local count = Util.Count(profile.Pets)
	if count >= slotsOf(profile) + E.InventoryCap then
		-- inventory full: auto-sell so nothing is silently lost
		local value = GameConfig.PetSellValue(pet)
		Services.DataService.AddCoins(player, value, true)
		Services.DataService.Notify(player, ("Character storage full — %s was sold for %s coins."):format(GameConfig.PetDisplayName(pet), GameConfig.FormatNumber(value)), "warn")
		return pet, false
	end
	pet.Slot = if preferredSlot and preferredSlot <= slotsOf(profile) then preferredSlot else freeSlot(profile)
	profile.Pets[pet.Uid] = pet
	local isNew = profile.Index[pet.Species] == nil
	local entry = profile.Index[pet.Species] or { First = os.time(), Count = 0 }
	entry.Count += 1
	profile.Index[pet.Species] = entry
	if isNew then
		local species = GameConfig.GetSpecies(pet.Species)
		local shards = R.ById[species.Rarity].IndexShards
		Services.DataService.AddShards(player, shards)
		Services.DataService.Effect(player, "Discovery", { Species = pet.Species, Shards = shards })
		Services.QuestService.SetStat(player, "IndexCount", Util.Count(profile.Index))
		checkBiomeComplete(player, profile, species.Biome)
	end
	Services.DataService.Changed(player, "Index")
	changed(player)
	return pet, isNew
end

function PetService.HatchEgg(player: Player, egg, slot: number?)
	local species = egg.Species and GameConfig.GetSpecies(egg.Species)
	if not species then
		local pool = GameConfig.GetSpeciesPool(egg.Biome, egg.Rarity)
		species = pool[math.random(math.max(#pool, 1))] or GameConfig.Pets[1]
	end
	local mutation = egg.Mutation
	if not mutation then
		local event = Services.EventService.GetActive()
		local boost = event and event.MutationBoost or 1
		for _, id in ipairs(R.MutationOrder) do
			local m = R.Mutations[id]
			if (not m.EventOnly or (event and event.EventMutation == id)) and math.random() < m.Chance * boost then
				mutation = id
				break
			end
		end
	end
	local size = R.Sizes[egg.Size] or R.Sizes.Normal
	local kg = (species.Kg[1] + math.random() * (species.Kg[2] - species.Kg[1])) * size.KgMult
	local pet = {
		Uid = Util.Uid("p"),
		Species = species.Id,
		Size = egg.Size or "Normal",
		Mutation = mutation,
		Tier = 1,
		Kg = math.floor(kg * 10) / 10,
		Obtained = os.time(),
	}
	local _, isNew = PetService.AddPet(player, pet, slot)
	local profile = Services.DataService.Get(player)
	profile.Stats.PetsHatched += 1
	Services.QuestService.Track(player, "PetsHatched", 1)
	if R.ById[species.Rarity].Index >= R.ById.Rare.Index then
		profile.Stats.RareHatches += 1
		Services.QuestService.Track(player, "RareHatches", 1)
	end
	Services.DataService.Changed(player, "Stats")
	Services.DataService.Effect(player, "Hatch", { Pet = pet, New = isNew })
	local rarity = R.ById[species.Rarity]
	if rarity.Announce or mutation == "Galaxy" then
		Services.EventService.GlobalAnnounce(("🌌 %s hatched a %s %s!"):format(player.DisplayName, species.Rarity:upper(), GameConfig.PetDisplayName(pet)), rarity.Color)
	end
	return pet
end

-- ===== Player actions =====

local function sell(player: Player, profile, uid: string): number
	local pet = profile.Pets[uid]
	if not pet or pet.Locked then
		return 0
	end
	profile.Pets[uid] = nil
	local value = GameConfig.PetSellValue(pet)
	Services.DataService.AddCoins(player, value, false)
	return value
end

local actions = {}

function actions.Place(player, profile, uids)
	for _, uid in ipairs(uids) do
		local pet = profile.Pets[uid]
		if pet and not pet.Slot then
			local slot = freeSlot(profile)
			if not slot then
				Services.DataService.Notify(player, "Your enclosure is full — upgrade it in the shop.", "warn")
				break
			end
			pet.Slot = slot
		end
	end
	changed(player)
end

function actions.Store(player, profile, uids)
	for _, uid in ipairs(uids) do
		local pet = profile.Pets[uid]
		if pet then
			pet.Slot = nil
		end
	end
	changed(player)
end

function actions.Sell(player, profile, uids)
	local total, n = 0, 0
	for _, uid in ipairs(uids) do
		local v = sell(player, profile, uid)
		if v > 0 then
			total += v
			n += 1
		end
	end
	if n > 0 then
		Services.DataService.Notify(player, ("Sold %d character(s) for %s coins."):format(n, GameConfig.FormatNumber(total)), "good")
	end
	changed(player)
end

-- Keeps the highest-income copy of every species; sells the other unlocked copies.
function actions.SellDuplicates(player, profile)
	local best = {}
	for uid, pet in pairs(profile.Pets) do
		local cur = best[pet.Species]
		if not cur or GameConfig.PetIncome(pet) > GameConfig.PetIncome(profile.Pets[cur]) then
			best[pet.Species] = uid
		end
	end
	local toSell = {}
	for uid, pet in pairs(profile.Pets) do
		if best[pet.Species] ~= uid and not pet.Locked then
			table.insert(toSell, uid)
		end
	end
	actions.Sell(player, profile, toSell)
end

function actions.Lock(player, profile, uids)
	for _, uid in ipairs(uids) do
		if profile.Pets[uid] then
			profile.Pets[uid].Locked = true
		end
	end
	Services.DataService.Changed(player, "Pets")
end

function actions.Unlock(player, profile, uids)
	for _, uid in ipairs(uids) do
		if profile.Pets[uid] then
			profile.Pets[uid].Locked = nil
		end
	end
	Services.DataService.Changed(player, "Pets")
end

function actions.Rename(player, profile, uids, name)
	local pet = profile.Pets[uids[1]]
	if not pet or type(name) ~= "string" then
		return
	end
	name = name:gsub("[%c]", ""):sub(1, 20)
	if name:match("^%s*$") then
		pet.Name = nil
		changed(player)
		return
	end
	-- Roblox requires filtering user-entered text that other players can see
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		Services.DataService.Notify(player, "Couldn't check that name right now, try again.", "bad")
		return
	end
	pet.Name = filtered
	changed(player)
end

function actions.MutationPotion(player, profile, uids)
	local pet = profile.Pets[uids[1]]
	if not pet or (profile.Items.MutationPotion or 0) <= 0 then
		return
	end
	local current = pet.Mutation and R.Mutations[pet.Mutation]
	local currentMult = current and current.IncomeMult or 1
	local weights = {}
	for _, id in ipairs(R.MutationOrder) do
		local m = R.Mutations[id]
		if not m.EventOnly and m.IncomeMult > currentMult then
			weights[id] = m.Chance
		end
	end
	local result = Util.WeightedPick(weights, R.MutationOrder)
	if not result then
		Services.DataService.Notify(player, "This character already has the best mutation!", "info")
		return
	end
	profile.Items.MutationPotion -= 1
	pet.Mutation = result
	Services.DataService.Changed(player, "Items")
	Services.DataService.Notify(player, ("✨ %s mutated to %s!"):format(GameConfig.PetDisplayName(pet), result), "good")
	changed(player)
end

function PetService.Init(services)
	Services = services
end

function PetService.Start()
	Services.DataService.RegisterDerived(function(player, _profile, d)
		d.Income = PetService.GetIncome(player)
	end)
	Services.DataService.OnLoaded(function(player, profile)
		-- sanitize pets from older saves / removed species
		local max = slotsOf(profile)
		local used = {}
		for uid, pet in pairs(profile.Pets) do
			if not GameConfig.GetSpecies(pet.Species) then
				-- removed animal species from older versions become a character of the same biome + rarity
				local legacy = GameConfig.LegacySpecies[pet.Species]
				local pool = legacy and GameConfig.GetSpeciesPool(legacy[1], legacy[2]) or {}
				if #pool > 0 then
					pet.Species = pool[math.random(#pool)].Id
					pet.Name = nil
					if pet.Slot and (pet.Slot > max or used[pet.Slot]) then
						pet.Slot = nil
					elseif pet.Slot then
						used[pet.Slot] = true
					end
				else
					profile.Pets[uid] = nil
				end
			elseif pet.Slot and (pet.Slot > max or used[pet.Slot]) then
				pet.Slot = nil
			elseif pet.Slot then
				used[pet.Slot] = true
			end
		end
		for id in pairs(profile.Index) do
			if not GameConfig.GetSpecies(id) then
				profile.Index[id] = nil
			end
		end
		for _, pet in pairs(profile.Pets) do
			if not profile.Index[pet.Species] then
				profile.Index[pet.Species] = { First = os.time(), Count = 1 }
			end
		end
		recalcIncome(player)
		task.wait(0.5)
		PetService.RefreshBase(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, m in pairs(petModels[player] or {}) do
			m:Destroy()
		end
		petModels[player] = nil
		incomeCache[player] = nil
	end)

	local limiter = RateLimiter.new(6, 2)
	Net.Event("PetAction").OnServerEvent:Connect(function(player, action, uids, arg)
		local profile = Services.DataService.Get(player)
		if not profile or type(action) ~= "string" or not actions[action] or not limiter:Allow(player) then
			return
		end
		if type(uids) ~= "table" then
			uids = {}
		end
		local clean = {}
		for i, uid in ipairs(uids) do
			if i > 100 then
				break
			end
			if type(uid) == "string" then
				table.insert(clean, uid)
			end
		end
		actions[action](player, profile, clean, arg)
	end)
end

return PetService

-- BiomeService: discovers the 8 Rift Run zones (building simple fallback zones when the place
-- lacks one), dresses them (BiomeDecor), builds hazards (HazardBuilder), enforces speed/key
-- gates, and tracks which biome every player stands in (player attribute BiomeIndex).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local World = script.Parent.Parent:WaitForChild("World")
local BiomeDecor = require(World:WaitForChild("BiomeDecor"))
local HazardBuilder = require(World:WaitForChild("HazardBuilder"))

local L = GameConfig.Layout

local BiomeService = {}
local Services

export type Zone = {
	Index: number,
	Biome: any,
	Model: Model,
	Floor: BasePart,
	Bounds: { MinX: number, MaxX: number, MinZ: number, MaxZ: number, TopY: number },
	Nests: { BasePart },
	Homes: { Vector3 },
	StartX: number,
}

local zones: { Zone } = {}
local runFolder: Instance
local lastSafe: { [Player]: CFrame } = {}
local gateWarned: { [Player]: number } = {}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

-- Minimal zone (floor, walls, nests, guardian homes) for places that don't have ZoneN yet.
local function buildFallbackZone(index: number, parent: Instance): Model
	local biome = GameConfig.Biomes[index]
	local cx = L.StartX + L.ZoneLength * (index - 0.5)
	local model = Instance.new("Model")
	model.Name = "Zone" .. index
	part({ Name = "Floor", Size = Vector3.new(L.ZoneLength, 2, L.ZoneWidth), Position = Vector3.new(cx, L.FloorTopY - 1, 0),
		Color = biome.Theme.Ground, Material = Enum.Material.Grass, Parent = model })
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Wall", Size = Vector3.new(L.ZoneLength, 18, 3), Position = Vector3.new(cx, 9, side * (L.ZoneWidth / 2 + 1.5)),
			Color = biome.Theme.Accent:Lerp(Color3.new(0, 0, 0), 0.5), Material = Enum.Material.Slate, Parent = model })
	end
	local nests = Instance.new("Folder")
	nests.Name = "Nests"
	nests.Parent = model
	local rng = Random.new(index * 31)
	for i = 1, 12 do
		local x = cx - L.ZoneLength / 2 + 60 + ((i - 1) % 6) * ((L.ZoneLength - 120) / 5) + rng:NextNumber(-12, 12)
		local z = (if i <= 6 then -1 else 1) * rng:NextNumber(55, 140)
		part({ Name = "Nest" .. i, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 9, 9),
			CFrame = CFrame.new(x, 0.7, z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(140, 100, 60),
			Material = Enum.Material.WoodPlanks, Parent = nests })
	end
	for i, name in ipairs({ "GuardianHome", "GuardianHome2" }) do
		part({ Name = name, Size = Vector3.new(2, 2, 2), Position = Vector3.new(cx + (i == 1 and -120 or 120), 1, 0),
			Transparency = 1, CanCollide = false, Parent = model })
	end
	model.Parent = parent
	return model
end

local function makeGateGui(gate: BasePart, biome)
	local old = gate:FindFirstChild("GateGui")
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "GateGui"
	bb.Size = UDim2.fromOffset(340, 120)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	bb.MaxDistance = 220
	bb.LightInfluence = 0
	local function line(text, color, y, h)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, h, 0)
		t.Position = UDim2.fromScale(0, y)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = text
		t.TextColor3 = color
		t.TextStrokeTransparency = 0
		t.Parent = bb
	end
	line(biome.Name, biome.Theme.Accent, 0, 0.42)
	line(("⚡ %s Speed  •  🔑 %s coins"):format(GameConfig.FormatNumber(biome.RequiredSpeed), GameConfig.FormatNumber(biome.UnlockPrice)), Color3.new(1, 1, 1), 0.45, 0.28)
	line(("Recommended: %s Speed"):format(GameConfig.FormatNumber(biome.RecommendedSpeed)), Color3.fromRGB(255, 230, 120), 0.75, 0.25)
	bb.Parent = gate
end

local function setupGate(zone: Zone)
	if zone.Index == 1 then
		return
	end
	local gate = zone.Model:FindFirstChild("Gate") :: BasePart?
	if not gate then
		gate = part({ Name = "Gate", Size = Vector3.new(1.2, 30, L.ZoneWidth), Position = Vector3.new(zone.StartX, 15, 0), Parent = zone.Model })
	end
	local g = gate :: BasePart
	g.CanCollide = false
	g.Material = Enum.Material.ForceField
	g.Color = zone.Biome.Theme.Accent
	g.Transparency = 0.3
	g:SetAttribute("RequiredSpeed", zone.Biome.RequiredSpeed)
	makeGateGui(g, zone.Biome)
end

local function setTitle(zone: Zone)
	local title = zone.Model:FindFirstChild("ZoneTitle") or zone.Model:FindFirstChild("StartSign")
	if title then
		local text = title:FindFirstChild("SignText") :: StringValue?
		if text then
			text.Value = zone.Biome.Name:upper()
		end
		local color = title:FindFirstChild("SignColor") :: Color3Value?
		if color then
			color.Value = zone.Biome.Theme.Accent
		end
	end
end

function BiomeService.GetZone(index: number): Zone?
	return zones[index]
end

function BiomeService.Zones(): { Zone }
	return zones
end

function BiomeService.ZoneIndexAt(pos: Vector3): number
	if pos.X < L.StartX then
		return 0
	end
	return math.clamp(math.floor((pos.X - L.StartX) / L.ZoneLength) + 1, 1, #zones)
end

-- Returns (ok, reason)
function BiomeService.CanEnter(player: Player, index: number): (boolean, string?)
	local biome = GameConfig.Biomes[index]
	local profile = Services.DataService.Get(player)
	if not biome or not profile then
		return false, "Loading..."
	end
	if not profile.Biomes[biome.Id] then
		return false, ("Buy the %s Rift Key in the shop first."):format(biome.Name)
	end
	local speed = Services.SpeedService.GetEffective(player)
	if speed < biome.RequiredSpeed then
		return false, ("%s needs %s Speed (you have %s). Train on your treadmill!"):format(
			biome.Name, GameConfig.FormatNumber(biome.RequiredSpeed), GameConfig.FormatNumber(speed))
	end
	return true, nil
end

function BiomeService.Init(services)
	Services = services
end

function BiomeService.Start()
	runFolder = workspace:FindFirstChild("RiftRun") or Instance.new("Folder")
	runFolder.Name = "RiftRun"
	runFolder.Parent = workspace
	local zonesFolder = runFolder:FindFirstChild("Zones") or Instance.new("Folder")
	zonesFolder.Name = "Zones"
	zonesFolder.Parent = runFolder
	for _, name in ipairs({ "Eggs", "Guardians", "Hazards", "Traps" }) do
		local f = runFolder:FindFirstChild(name) or Instance.new("Folder")
		f.Name = name
		f.Parent = runFolder
	end
	local oldWild = runFolder:FindFirstChild("WildEggs")
	if oldWild then
		oldWild:Destroy()
	end

	for i, biome in ipairs(GameConfig.Biomes) do
		local model = zonesFolder:FindFirstChild("Zone" .. i) :: Model?
		if not model then
			model = buildFallbackZone(i, zonesFolder)
		end
		local m = model :: Model
		local floor = m:FindFirstChild("Floor") :: BasePart
		local zone: Zone = {
			Index = i,
			Biome = biome,
			Model = m,
			Floor = floor,
			Bounds = {
				MinX = floor.Position.X - floor.Size.X / 2,
				MaxX = floor.Position.X + floor.Size.X / 2,
				MinZ = floor.Position.Z - floor.Size.Z / 2 + 4,
				MaxZ = floor.Position.Z + floor.Size.Z / 2 - 4,
				TopY = floor.Position.Y + floor.Size.Y / 2,
			},
			Nests = {},
			Homes = {},
			StartX = floor.Position.X - floor.Size.X / 2,
		}
		local nests = m:FindFirstChild("Nests")
		if nests then
			for _, n in ipairs(nests:GetChildren()) do
				if n:IsA("BasePart") then
					table.insert(zone.Nests, n)
				end
			end
		end
		for _, n in ipairs({ "GuardianHome", "GuardianHome2", "GuardianHome3", "GuardianHome4" }) do
			local h = m:FindFirstChild(n) :: BasePart?
			if h then
				table.insert(zone.Homes, h.Position)
			end
		end
		if #zone.Homes == 0 then
			table.insert(zone.Homes, floor.Position)
		end
		zones[i] = zone
		setupGate(zone)
		setTitle(zone)
	end

	-- the run lane ends after the last zone
	local endWall = runFolder:FindFirstChild("EndWall") :: BasePart?
	local last = zones[#zones]
	if endWall and last then
		local cap = runFolder:FindFirstChild("EndWallCap") :: BasePart?
		local dx = last.Bounds.MaxX + 1.5 - endWall.Position.X
		endWall.Position += Vector3.new(dx, 0, 0)
		if cap then
			cap.Position += Vector3.new(dx, 0, 0)
		end
	end

	-- dress zones + hazards (decor failures must never break the game loop)
	for _, zone in ipairs(zones) do
		local avoid = table.clone(zone.Homes)
		for _, n in ipairs(zone.Nests) do
			table.insert(avoid, n.Position)
		end
		local ok, err = pcall(BiomeDecor.Decorate, zone.Model, zone.Biome, zone.Bounds, avoid)
		if not ok then
			warn("[BiomeService] decor failed for", zone.Biome.Id, err)
		end
		local hz = Instance.new("Folder")
		hz.Name = zone.Biome.Id
		hz.Parent = runFolder:FindFirstChild("Hazards")
		ok, err = pcall(HazardBuilder.Build, zone.Model, zone.Biome, zone.Bounds, avoid, hz)
		if not ok then
			warn("[BiomeService] hazards failed for", zone.Biome.Id, err)
		end
	end
	local ctx = {
		Knockdown = function(player, dir, reason)
			Services.CombatService.Knockdown(player, dir, reason)
		end,
		SetSlow = function(player, key, mult)
			Services.SpeedService.SetModifier(player, "Hazard:" .. key, mult)
		end,
		Launch = function(player, velocity)
			Net.Event("Knockback"):FireClient(player, velocity)
			Services.AntiCheatService.Grace(player, 2)
		end,
		VoidFall = function(player, zoneIndex)
			Services.EggService.ReturnCarriedEgg(player, "fell into the void")
			local zone = zones[zoneIndex]
			if zone and player.Character then
				Services.AntiCheatService.Grace(player, 2)
				player.Character:PivotTo(CFrame.new(zone.StartX + 20, zone.Bounds.TopY + 4, 0))
			end
		end,
		SetSlippery = function(player, on)
			Services.SpeedService.SetSlippery(player, on)
		end,
		IsImmune = function(player)
			return Services.CombatService.IsCrowdControlled(player)
		end,
	}
	local ok, err = pcall(HazardBuilder.Start, ctx)
	if not ok then
		warn("[BiomeService] HazardBuilder.Start failed:", err)
	end

	Players.PlayerRemoving:Connect(function(p)
		lastSafe[p] = nil
		gateWarned[p] = nil
	end)

	-- biome tracking + gate enforcement (server authoritative)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local index = BiomeService.ZoneIndexAt(hrp.Position)
				local allowed = index <= 1 or BiomeService.CanEnter(player, index)
				if allowed then
					lastSafe[player] = hrp.CFrame
					if player:GetAttribute("BiomeIndex") ~= index then
						player:SetAttribute("BiomeIndex", index)
					end
				else
					-- bounce back in front of the gate of the zone they tried to enter
					local zone = zones[index]
					local back = CFrame.new(zone.StartX - 12, zone.Bounds.TopY + 3, math.clamp(hrp.Position.Z, -150, 150)) * CFrame.Angles(0, math.pi / 2, 0)
					Services.AntiCheatService.Grace(player, 1)
					player.Character:PivotTo(back)
					local _, reason = BiomeService.CanEnter(player, index)
					if os.clock() - (gateWarned[player] or 0) > 3 then
						gateWarned[player] = os.clock()
						Services.DataService.Notify(player, reason or "You can't enter yet.", "warn")
					end
				end
			end
		end
	end)
end

return BiomeService

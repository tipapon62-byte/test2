-- GuardianService: nest guardians. Each zone has one guardian per GuardianHome.
-- States: Patrol -> Alert ("!") -> Chase -> Attack -> Stunned -> Return -> Patrol.
-- Guardians only care about egg carriers, are clamped to their zone (so they can never reach
-- a base), and give up when the thief leaves the aggression (leash) zone or breaks sight.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ModelFactory = require(Shared:WaitForChild("ModelFactory"))
local Util = require(Shared:WaitForChild("Util"))

local S = GameConfig.Settings
local R = GameConfig.Rarities

local GuardianService = {}
local Services

type Guardian = {
	Model: Model,
	Root: BasePart,
	Zone: any,
	Cfg: any,
	Home: Vector3,
	Pos: Vector3,       -- flat position (Y ignored)
	Dir: Vector3,
	State: string,
	StateAt: number,
	Target: Player?,
	ChaseSpeed: number,
	LastSeen: number,
	StunUntil: number,
	NextAttack: number,
	Wander: Vector3?,
	WanderWait: number,
	GroundOffset: number,
}

local guardians: { Guardian } = {}
local folder: Instance
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include

local function setState(g: Guardian, state: string)
	if g.State ~= state then
		g.State = state
		g.StateAt = os.clock()
		g.Model:SetAttribute("State", state)
	end
end

local function hrpOf(player: Player?): BasePart?
	local c = player and player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function inZone(g: Guardian, pos: Vector3, margin: number): boolean
	local b = g.Zone.Bounds
	return pos.X >= b.MinX - margin and pos.X <= b.MaxX + margin and pos.Z >= b.MinZ - margin and pos.Z <= b.MaxZ + margin
end

local function canSee(g: Guardian, hrp: BasePart): boolean
	-- only solid map geometry of this zone blocks sight
	local origin = Vector3.new(g.Pos.X, g.Zone.Bounds.TopY + g.Cfg.Size * 0.7, g.Pos.Z)
	local dir = hrp.Position - origin
	local hit = workspace:Raycast(origin, dir, losParams)
	return hit == nil
end

local function buildModel(zone): (Model, number)
	local ok, model = pcall(ModelFactory.BuildGuardian, zone.Biome.Id)
	if not ok or not model then
		warn("[GuardianService] BuildGuardian failed:", model)
		model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(zone.Biome.Guardian.Size, zone.Biome.Guardian.Size, zone.Biome.Guardian.Size)
		root.Color = zone.Biome.Guardian.Colors[1]
		root.Anchored = true
		root.CanCollide = false
		root.Parent = model
		model.PrimaryPart = root
		return model, zone.Biome.Guardian.Size / 2
	end
	return model, 0
end

local function spawnGuardian(zone, home: Vector3)
	local model, groundOffset = buildModel(zone)
	model.Name = zone.Biome.Guardian.Name
	model:SetAttribute("Biome", zone.Biome.Id)
	model:SetAttribute("State", "Patrol")
	model:SetAttribute("Speed", zone.Biome.Guardian.Speed)
	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.fromOffset(220, 30)
	nameTag.StudsOffset = Vector3.new(0, (model:GetAttribute("Height") or zone.Biome.Guardian.Size) + 2, 0)
	nameTag.MaxDistance = 90
	nameTag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextColor3 = zone.Biome.Guardian.Colors[2]
	label.Text = "👹 " .. zone.Biome.Guardian.Name
	label.Parent = nameTag
	nameTag.Parent = model.PrimaryPart
	CollectionService:AddTag(model, "RR_Guardian")
	local g: Guardian = {
		Model = model,
		Root = model.PrimaryPart :: BasePart,
		Zone = zone,
		Cfg = zone.Biome.Guardian,
		Home = Util.Flat(home),
		Pos = Util.Flat(home),
		Dir = Vector3.new(-1, 0, 0),
		State = "Patrol",
		StateAt = os.clock(),
		Target = nil,
		ChaseSpeed = zone.Biome.Guardian.Speed,
		LastSeen = 0,
		StunUntil = 0,
		NextAttack = 0,
		Wander = nil,
		WanderWait = 0,
		GroundOffset = groundOffset,
	}
	model:PivotTo(CFrame.new(home.X, zone.Bounds.TopY + groundOffset, home.Z))
	model.Parent = folder
	table.insert(guardians, g)
end

local function chaseSpeedFor(g: Guardian, eggData): number
	local rarity = R.ById[eggData.Rarity] or R.ById.Common
	local event = Services.EventService.GetActive()
	local sizeBonus = if eggData.Size == "Huge" then 1.05 elseif eggData.Size == "Large" then 1.02 else 1
	return g.Cfg.Speed * rarity.GuardianSpeedMult * sizeBonus * (event and event.GuardianSpeedMult or 1)
end

local function startChase(g: Guardian, player: Player, eggData)
	if g.State == "Stunned" then
		return
	end
	g.Target = player
	g.ChaseSpeed = chaseSpeedFor(g, eggData)
	g.LastSeen = os.clock()
	g.Model:SetAttribute("Speed", g.ChaseSpeed)
	setState(g, "Alert")
end

-- Called by EggService when an egg leaves a nest: the closest guardian of that zone reacts.
function GuardianService.OnEggTaken(zoneIndex: number, nest: BasePart?, player: Player, eggData)
	local best, bestD = nil, math.huge
	local at = if nest then Util.Flat(nest.Position) else Util.Flat((hrpOf(player) :: BasePart).Position)
	for _, g in ipairs(guardians) do
		if g.Zone.Index == zoneIndex and g.State ~= "Chase" and g.State ~= "Stunned" then
			local d = (g.Pos - at).Magnitude
			if d < bestD then
				best, bestD = g, d
			end
		end
	end
	if best then
		startChase(best, player, eggData)
	end
end

local function moveToward(g: Guardian, target: Vector3, speed: number, dt: number): number
	local delta = target - g.Pos
	local dist = delta.Magnitude
	if dist > 0.05 then
		local step = math.min(dist, speed * dt)
		g.Dir = delta.Unit
		g.Pos += g.Dir * step
	end
	return dist
end

local function update(g: Guardian, now: number, dt: number)
	local cfg = g.Cfg
	local state = g.State

	if state == "Stunned" then
		if now >= g.StunUntil then
			setState(g, "Return")
		end
	elseif state == "Alert" then
		local hrp = hrpOf(g.Target)
		if hrp then
			g.Dir = Util.Flat(hrp.Position - Vector3.new(g.Pos.X, 0, g.Pos.Z)).Unit
		end
		if now - g.StateAt >= S.GuardianReactTime then
			setState(g, "Chase")
		end
	elseif state == "Chase" or state == "Attack" then
		local target = g.Target
		local hrp = hrpOf(target)
		local carriers = Services.EggService.GetCarriers()
		local carrying = target and carriers[target]
		local leash = (Util.Flat(hrp and hrp.Position or g.Pos) - g.Home).Magnitude
		if not hrp or not carrying or not inZone(g, hrp.Position, 4) or leash > cfg.LeashRadius * 2.2
			or Services.BaseService.FindBaseAt(hrp.Position) then
			g.Target = nil
			setState(g, "Return")
		else
			local tpos = Util.Flat(hrp.Position)
			if canSee(g, hrp) then
				g.LastSeen = now
			elseif now - g.LastSeen > S.GuardianLoseTime then
				g.Target = nil
				setState(g, "Return")
				return
			end
			local dist = moveToward(g, tpos, g.ChaseSpeed, dt)
			if dist <= cfg.AttackRange and now >= g.NextAttack then
				setState(g, "Attack")
				g.NextAttack = now + cfg.AttackCooldown
				local away = tpos - g.Pos
				away = if away.Magnitude > 0.1 then away.Unit else g.Dir
				local hit = Services.CombatService.Knockdown(target :: Player, away, "the " .. cfg.Name .. " caught you", cfg.Knockback)
				if hit then
					g.Target = nil
					g.StunUntil = now + S.GuardianStunAfterHit
					setState(g, "Stunned")
				end
			elseif state == "Attack" and now - g.StateAt > 0.5 then
				setState(g, "Chase")
			end
		end
	else -- Patrol / Return
		-- notice carriers that wander into the detection radius
		for player, info in pairs(Services.EggService.GetCarriers()) do
			local hrp = hrpOf(player)
			if hrp and inZone(g, hrp.Position, 0) and (Util.Flat(hrp.Position) - g.Pos).Magnitude <= cfg.DetectRadius and canSee(g, hrp) then
				startChase(g, player, info.Data)
				return
			end
		end
		if state == "Return" then
			if moveToward(g, g.Home, cfg.Speed * 0.6, dt) < 2 then
				setState(g, "Patrol")
			end
		else
			if not g.Wander or (g.Wander - g.Pos).Magnitude < 2 then
				if now >= g.WanderWait then
					local a = math.random() * math.pi * 2
					local r = math.random() * cfg.LeashRadius * 0.5
					g.Wander = g.Home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
					g.WanderWait = now + 2 + math.random() * 3
				end
			else
				moveToward(g, g.Wander, cfg.Speed * 0.3, dt)
			end
		end
	end
end

function GuardianService.Init(services)
	Services = services
end

function GuardianService.Start()
	folder = workspace:WaitForChild("RiftRun"):WaitForChild("Guardians")
	local blockers = {}
	for _, zone in ipairs(Services.BiomeService.Zones()) do
		for _, name in ipairs({ "Wall", "WallBase" }) do
			for _, p in ipairs(zone.Model:GetChildren()) do
				if p.Name == name then
					table.insert(blockers, p)
				end
			end
		end
		local decor = zone.Model:FindFirstChild("RR_Decor")
		if decor then
			table.insert(blockers, decor)
		end
		for _, home in ipairs(zone.Homes) do
			spawnGuardian(zone, home)
		end
	end
	losParams.FilterDescendantsInstances = blockers

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		-- only simulate zones that have a player in or near them
		local active = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local idx = player:GetAttribute("BiomeIndex")
			if type(idx) == "number" and idx > 0 then
				active[idx] = true
				active[idx - 1] = true
				active[idx + 1] = true
			end
		end
		for _, g in ipairs(guardians) do
			if active[g.Zone.Index] or g.State ~= "Patrol" then
				update(g, now, dt)
				local b = g.Zone.Bounds
				local half = g.Cfg.Size * 0.5
				g.Pos = Vector3.new(math.clamp(g.Pos.X, b.MinX + half, b.MaxX - half), 0, math.clamp(g.Pos.Z, b.MinZ + half, b.MaxZ - half))
				local pos = Vector3.new(g.Pos.X, b.TopY + g.GroundOffset, g.Pos.Z)
				g.Root.CFrame = CFrame.lookAt(pos, pos + g.Dir)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		for _, g in ipairs(guardians) do
			if g.Target == p then
				g.Target = nil
				setState(g, "Return")
			end
		end
	end)
end

return GuardianService

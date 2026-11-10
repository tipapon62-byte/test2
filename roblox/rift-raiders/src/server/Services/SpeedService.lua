-- SpeedService: permanent Speed stat, treadmill training, walk-speed application with
-- modifiers (carrying, hazards, crowd control), trails, and slippery surfaces.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local ModelFactory = require(Shared:WaitForChild("ModelFactory"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local S = GameConfig.Settings
local E = GameConfig.Economy

local SpeedService = {}
local Services

local modifiers: { [Player]: { [string]: number } } = {}
local activeRunning: { [Player]: boolean } = {}
local treadmillAcc: { [Player]: number } = {}

function SpeedService.Init(services)
	Services = services
end

function SpeedService.GetEffective(player: Player): number
	local p = Services.DataService.Get(player)
	if not p then
		return 0
	end
	return GameConfig.EffectiveSpeed(p.SpeedStat, p.TreadmillLevel, p.Trails.Equipped)
end

-- key examples: "Carry", "Hazard:MudPit", "Trapped" (0 = rooted). nil clears.
function SpeedService.SetModifier(player: Player, key: string, mult: number?)
	local m = modifiers[player]
	if not m then
		m = {}
		modifiers[player] = m
	end
	m[key] = mult
	SpeedService.Apply(player)
end

function SpeedService.Apply(player: Player)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local walk = GameConfig.WalkSpeedFor(SpeedService.GetEffective(player))
	for _, mult in pairs(modifiers[player] or {}) do
		walk *= mult
	end
	hum.WalkSpeed = walk
	player:SetAttribute("AllowedWalkSpeed", walk)
end

function SpeedService.SetSlippery(player: Player, on: boolean)
	local character = player.Character
	if not character then
		return
	end
	local props = if on then PhysicalProperties.new(0.7, 0, 0, 100, 1) else nil
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CustomPhysicalProperties = props
		end
	end
end

function SpeedService.ApplyTrail(player: Player)
	local character = player.Character
	local p = Services.DataService.Get(player)
	if not character or not p then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, d in ipairs(hrp:GetChildren()) do
			if d:IsA("Trail") or (d:IsA("Attachment") and d.Name:match("^Trail")) then
				d:Destroy()
			end
		end
	end
	local ok, err = pcall(ModelFactory.MakeTrail, character, p.Trails.Equipped)
	if not ok then
		warn("[SpeedService] trail failed:", err)
	end
end

function SpeedService.Start()
	Services.DataService.RegisterDerived(function(player, profile, d)
		d.EffectiveSpeed = GameConfig.EffectiveSpeed(profile.SpeedStat, profile.TreadmillLevel, profile.Trails.Equipped)
		d.WalkSpeed = GameConfig.WalkSpeedFor(d.EffectiveSpeed)
	end)

	local function onCharacter(player: Player, character: Model)
		character:WaitForChild("Humanoid", 10)
		character:WaitForChild("HumanoidRootPart", 10)
		modifiers[player] = {}
		SpeedService.Apply(player)
		SpeedService.ApplyTrail(player)
	end
	local function onPlayer(player: Player)
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
	Players.PlayerRemoving:Connect(function(p)
		modifiers[p] = nil
		activeRunning[p] = nil
		treadmillAcc[p] = nil
	end)
	Services.DataService.OnLoaded(function(player)
		SpeedService.Apply(player)
		SpeedService.ApplyTrail(player)
	end)

	local activeLimiter = RateLimiter.new(6, 3)
	Net.Event("TreadmillActive").OnServerEvent:Connect(function(player, running)
		if activeLimiter:Allow(player) then
			activeRunning[player] = running == true
		end
	end)

	local trailLimiter = RateLimiter.new(4, 1)
	Net.Event("EquipTrail").OnServerEvent:Connect(function(player, trailId)
		local p = Services.DataService.Get(player)
		if not p or type(trailId) ~= "string" or not trailLimiter:Allow(player) then
			return
		end
		if not p.Trails.Owned[trailId] or not E.Trails[trailId] then
			return
		end
		p.Trails.Equipped = trailId
		Services.DataService.Changed(player, "Trails")
		SpeedService.Apply(player)
		SpeedService.ApplyTrail(player)
	end)

	-- Treadmill training: the server checks the position itself; the client flag only picks
	-- between the AFK gain and the (higher) active-running gain.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < S.TreadmillTick then
			return
		end
		local tick = acc
		acc = 0
		for player, profile in pairs(Services.DataService.All()) do
			local info = Services.BaseService.GetBase(player)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if info and hrp and Services.BaseService.IsOnTreadmill(info, hrp.Position) and (player:GetAttribute("CarryingEgg") or "") == "" then
				local tm = E.TreadmillLevels[math.clamp(profile.TreadmillLevel, 1, #E.TreadmillLevels)]
				local gain = tm.Gain * (if activeRunning[player] then tm.Efficiency else 1)
				gain *= 1 + profile.Rebirths * E.Rebirth.TrainingBonusPerRebirth
				local before = GameConfig.WalkSpeedFor(SpeedService.GetEffective(player))
				profile.SpeedStat += gain * tick
				profile.Stats.TreadmillSeconds += tick
				treadmillAcc[player] = (treadmillAcc[player] or 0) + tick
				if treadmillAcc[player] >= 1 then
					local whole = math.floor(treadmillAcc[player])
					treadmillAcc[player] -= whole
					Services.QuestService.Track(player, "TreadmillSeconds", whole)
				end
				Services.DataService.Changed(player, "SpeedStat", "Stats")
				if GameConfig.WalkSpeedFor(SpeedService.GetEffective(player)) ~= before then
					SpeedService.Apply(player)
				end
			end
		end
	end)
end

return SpeedService

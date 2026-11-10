-- CombatService: non-lethal PvP and crowd control.
--   * Foam bat tags (server picks the target in a cone; cooldown, immunity, safe zones)
--   * Ragdoll knockdowns (used by tags, guardians and hazards) that drop the carried egg
--   * Bear traps (placement rules, decoy-egg disarm, single use, lifetime)
--   * Anti-griefing: new-player shield, per-victim steal limit, trap exclusion near bases
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local ModelFactory = require(Shared:WaitForChild("ModelFactory"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local S = GameConfig.Settings

local CombatService = {}
local Services

local immuneUntil: { [Player]: number } = {}     -- tag immunity
local trapImmuneUntil: { [Player]: number } = {}
local lastTrapPlaced: { [Player]: number } = {}
local steals: { [Player]: { [number]: { number } } } = {} -- attacker -> victimId -> timestamps
type Trap = { Model: Model, Owner: Player, Pos: Vector3, Expires: number }
local traps: { Trap } = {}
local trapFolder: Instance

local function now(): number
	return workspace:GetServerTimeNow()
end

local function hrpOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function CombatService.IsCrowdControlled(player: Player): boolean
	return player:GetAttribute("Ragdolled") == true or player:GetAttribute("Trapped") == true
end

function CombatService.IsShielded(player: Player): boolean
	return (player:GetAttribute("ShieldUntil") or 0) > now()
end

local function inSafeZone(player: Player): boolean
	local hrp = hrpOf(player)
	return hrp ~= nil and Services.BaseService.FindBaseAt(hrp.Position) ~= nil
end

-- ===== Ragdoll =====

local function setRagdoll(character: Model, on: boolean)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name ~= "RootJoint" and d.Name ~= "Root" and d.Name ~= "BatGrip" and d.Part0 and d.Part1 then
			if on then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagA0"
				a0.CFrame = d.C0
				a0.Parent = d.Part0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagA1"
				a1.CFrame = d.C1
				a1.Parent = d.Part1
				local bs = Instance.new("BallSocketConstraint")
				bs.Name = "RagSocket"
				bs.Attachment0 = a0
				bs.Attachment1 = a1
				bs.LimitsEnabled = true
				bs.TwistLimitsEnabled = true
				bs.Parent = d.Part0
				d.Enabled = false
			else
				d.Enabled = true
			end
		elseif not on and (d.Name == "RagA0" or d.Name == "RagA1" or d.Name == "RagSocket") then
			d:Destroy()
		end
	end
end

-- Knocks a player down: ragdoll + knockback + drops the carried egg.
-- byPlayer = true for player-caused knockdowns (respects the new-player shield).
function CombatService.Knockdown(player: Player, direction: Vector3, reason: string, force: number?, byPlayer: boolean?): (boolean, boolean)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not hum or hum.Health <= 0 or CombatService.IsCrowdControlled(player) then
		return false, false
	end
	local dir = Util.Flat(direction)
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, 1)
	local power = force or 55
	player:SetAttribute("Ragdolled", true)
	Services.AntiCheatService.Grace(player, S.RagdollTime + 1.5)
	setRagdoll(character, true)
	Net.Event("Ragdoll"):FireClient(player, true, S.RagdollTime)
	Net.Event("Knockback"):FireClient(player, dir * power + Vector3.new(0, power * 0.55, 0))
	local dropped = false
	if not (byPlayer and CombatService.IsShielded(player)) then
		dropped = Services.EggService.Drop(player, reason)
	end
	task.delay(S.RagdollTime, function()
		if character.Parent then
			setRagdoll(character, false)
		end
		if player.Parent then
			player:SetAttribute("Ragdolled", false)
			Net.Event("Ragdoll"):FireClient(player, false, 0)
		end
	end)
	return true, dropped
end

-- ===== Foam bat =====

local function giveBat(character: Model)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local ok, bat = pcall(ModelFactory.BuildFoamBat)
	if not ok or not bat then
		return
	end
	bat.Name = "FoamBat"
	local handle = bat:FindFirstChild("Handle", true) :: BasePart?
	if not handle then
		bat:Destroy()
		return
	end
	for _, d in ipairs(bat:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = true
		end
	end
	local grip = Instance.new("Motor6D")
	grip.Name = "BatGrip"
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	grip.Parent = hand
	bat.Parent = character
end

local function canSteal(attacker: Player, victim: Player): boolean
	local byVictim = steals[attacker] and steals[attacker][victim.UserId]
	if not byVictim then
		return true
	end
	local t = now()
	local recent = 0
	for _, at in ipairs(byVictim) do
		if t - at < S.StealWindow then
			recent += 1
		end
	end
	return recent < S.StealLimit
end

local function recordSteal(attacker: Player, victim: Player)
	steals[attacker] = steals[attacker] or {}
	local list = steals[attacker][victim.UserId] or {}
	table.insert(list, now())
	while #list > 10 do
		table.remove(list, 1)
	end
	steals[attacker][victim.UserId] = list
end

local function tag(attacker: Player)
	local t = now()
	if (attacker:GetAttribute("TagReadyAt") or 0) > t + 0.1 then
		return
	end
	local hrp = hrpOf(attacker)
	if not hrp or CombatService.IsCrowdControlled(attacker) or inSafeZone(attacker) then
		return
	end
	attacker:SetAttribute("TagReadyAt", t + S.TagCooldown)
	if CombatService.IsShielded(attacker) then
		attacker:SetAttribute("ShieldUntil", 0) -- attacking ends your own protection
	end
	local look = Util.Flat(hrp.CFrame.LookVector).Unit
	local cosLimit = math.cos(math.rad(S.TagAngle / 2))
	local best, bestD = nil, math.huge
	for _, other in ipairs(Players:GetPlayers()) do
		local ohrp = other ~= attacker and hrpOf(other)
		if ohrp then
			local delta = Util.Flat(ohrp.Position - hrp.Position)
			local d = delta.Magnitude
			local vertical = math.abs(ohrp.Position.Y - hrp.Position.Y)
			if d <= S.TagRange and vertical < 6 and (d < 2 or look:Dot(delta.Unit) >= cosLimit) and d < bestD then
				best, bestD = other, d
			end
		end
	end
	if not best then
		return
	end
	local victim = best :: Player
	if (immuneUntil[victim] or 0) > t or inSafeZone(victim) then
		return
	end
	local wasCarrying = Services.EggService.IsCarrying(victim)
	if wasCarrying and not canSteal(attacker, victim) then
		Services.DataService.Notify(attacker, ("You've raided %s enough for now — give them a break!"):format(victim.DisplayName), "warn")
		return
	end
	local ok, dropped = CombatService.Knockdown(victim, look, "tagged by " .. attacker.DisplayName, 50, true)
	if not ok then
		return
	end
	immuneUntil[victim] = t + S.TagImmunity
	if dropped then
		recordSteal(attacker, victim)
	elseif wasCarrying then
		Services.DataService.Notify(attacker, victim.DisplayName .. " has a new-player shield — their egg stayed put.", "info")
	end
	Services.DataService.Effect(victim, "Tagged", { By = attacker.DisplayName })
	local profile = Services.DataService.Get(attacker)
	if profile then
		profile.Stats.Tags += 1
		Services.DataService.Changed(attacker, "Stats")
		Services.QuestService.Track(attacker, "Tags", 1)
	end
end

-- ===== Bear traps & decoy =====

local function placeTrap(player: Player)
	local profile = Services.DataService.Get(player)
	local hrp = hrpOf(player)
	if not profile or not hrp or (profile.Items.BearTrap or 0) <= 0 or CombatService.IsCrowdControlled(player) then
		return
	end
	if os.clock() - (lastTrapPlaced[player] or 0) < S.TrapPlaceCooldown then
		return
	end
	local mine = 0
	for _, trap in ipairs(traps) do
		if trap.Owner == player then
			mine += 1
		end
	end
	if mine >= S.TrapMaxActive then
		return Services.DataService.Notify(player, ("You can only have %d traps out at once."):format(S.TrapMaxActive), "warn")
	end
	for _, info in ipairs(Services.BaseService.All()) do
		if Services.BaseService.IsNear(info, hrp.Position, S.TrapBaseExclusion) then
			return Services.DataService.Notify(player, "Traps can't be placed near bases, incubators or base exits.", "warn")
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: any, trapFolder }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -12, 0), params)
	if not hit then
		return
	end
	for _, trap in ipairs(traps) do
		if (trap.Pos - hit.Position).Magnitude < S.TrapSpacing then
			return Services.DataService.Notify(player, "Too close to another trap.", "warn")
		end
	end
	local ok, model = pcall(ModelFactory.BuildBearTrap)
	if not ok or not model then
		return
	end
	lastTrapPlaced[player] = os.clock()
	profile.Items.BearTrap -= 1
	Services.DataService.Changed(player, "Items")
	model.Name = "BearTrap"
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("Armed", true)
	model:PivotTo(CFrame.new(hit.Position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	CollectionService:AddTag(model, "RR_Trap")
	model.Parent = trapFolder
	table.insert(traps, { Model = model, Owner = player, Pos = hit.Position, Expires = os.clock() + S.TrapLifetime })
end

local function setDecoyVisual(player: Player, on: boolean)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild("DecoyEgg")
	if old then
		old:Destroy()
	end
	local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if on and hand and hand:IsA("BasePart") then
		local egg = Instance.new("Part")
		egg.Name = "DecoyEgg"
		egg.Size = Vector3.new(1, 1.3, 1)
		egg.Color = Color3.fromRGB(255, 250, 235)
		egg.CanCollide = false
		egg.Massless = true
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = egg
		egg.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - 0.4, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = hand
		w.Part1 = egg
		w.Parent = egg
		egg.Parent = character
	end
end

local function useItem(player: Player, itemId: any)
	local profile = Services.DataService.Get(player)
	if not profile then
		return
	end
	if itemId == "BearTrap" then
		placeTrap(player)
	elseif itemId == "DecoyEgg" then
		local holding = player:GetAttribute("HoldingDecoy") == true
		if not holding and (profile.Items.DecoyEgg or 0) <= 0 then
			return
		end
		player:SetAttribute("HoldingDecoy", not holding)
		setDecoyVisual(player, not holding)
	end
end

local function removeTrap(i: number)
	local trap = table.remove(traps, i)
	if trap then
		trap.Model:Destroy()
	end
end

local function updateTraps()
	local clock = os.clock()
	for i = #traps, 1, -1 do
		local trap = traps[i]
		if clock > trap.Expires or not trap.Model.Parent then
			removeTrap(i)
			continue
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local hrp = hrpOf(player)
			if hrp and player ~= trap.Owner and (trapImmuneUntil[player] or 0) < clock and not CombatService.IsCrowdControlled(player) then
				local delta = hrp.Position - trap.Pos
				if Util.Flat(delta).Magnitude < 2.6 and delta.Y < 5 and delta.Y > -1 then
					local profile = Services.DataService.Get(player)
					if player:GetAttribute("HoldingDecoy") and profile and (profile.Items.DecoyEgg or 0) > 0 then
						profile.Items.DecoyEgg -= 1
						Services.DataService.Changed(player, "Items")
						if profile.Items.DecoyEgg <= 0 then
							player:SetAttribute("HoldingDecoy", false)
							setDecoyVisual(player, false)
						end
						Services.DataService.Notify(player, "🐔 Your decoy egg disarmed a bear trap!", "good")
						removeTrap(i)
					else
						-- snap!
						pcall(ModelFactory.SetTrapClosed, trap.Model, true)
						trap.Model:SetAttribute("Armed", false)
						trap.Expires = clock + S.TrapStunTime + 0.5
						player:SetAttribute("Trapped", true)
						trapImmuneUntil[player] = clock + S.TrapStunTime + S.TrapImmunity
						Services.SpeedService.SetModifier(player, "Trapped", 0)
						local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
						if hum then
							hum.JumpHeight = 0
						end
						Services.DataService.Effect(player, "Trapped", { Duration = S.TrapStunTime })
						if trap.Owner.Parent then
							local op = Services.DataService.Get(trap.Owner)
							if op then
								op.Stats.TrapsSprung += 1
								Services.DataService.Changed(trap.Owner, "Stats")
								Services.QuestService.Track(trap.Owner, "TrapsSprung", 1)
							end
							Services.DataService.Notify(trap.Owner, ("🪤 %s stepped in your trap!"):format(player.DisplayName), "good")
						end
						task.delay(S.TrapStunTime, function()
							if player.Parent then
								player:SetAttribute("Trapped", false)
								Services.SpeedService.SetModifier(player, "Trapped", nil)
								local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
								if h then
									h.JumpHeight = 7.2
								end
							end
						end)
						trap.Pos = Vector3.new(0, -1e6, 0) -- sprung traps can't catch anyone else
					end
					break
				end
			end
		end
	end
end

function CombatService.Init(services)
	Services = services
end

function CombatService.Start()
	trapFolder = workspace:WaitForChild("RiftRun"):WaitForChild("Traps")

	local function onCharacter(player: Player, character: Model)
		player:SetAttribute("Ragdolled", false)
		player:SetAttribute("Trapped", false)
		player:SetAttribute("HoldingDecoy", false)
		giveBat(character)
	end
	local function onPlayer(player: Player)
		player:SetAttribute("ShieldUntil", now() + S.NewPlayerShield)
		player:SetAttribute("TagReadyAt", 0)
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
		immuneUntil[p] = nil
		trapImmuneUntil[p] = nil
		lastTrapPlaced[p] = nil
		steals[p] = nil
		for i = #traps, 1, -1 do
			if traps[i].Owner == p then
				removeTrap(i)
			end
		end
	end)

	local tagLimiter = RateLimiter.new(3, 1)
	Net.Event("Tag").OnServerEvent:Connect(function(player)
		if tagLimiter:Allow(player) then
			tag(player)
		end
	end)
	local itemLimiter = RateLimiter.new(4, 1)
	Net.Event("UseItem").OnServerEvent:Connect(function(player, itemId)
		if type(itemId) == "string" and itemLimiter:Allow(player) then
			useItem(player, itemId)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			updateTraps()
		end
	end)
end

return CombatService

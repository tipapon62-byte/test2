-- EffectsController: local physics/camera feedback driven by the server (knockback, ragdoll,
-- trap camera shake), the foam-bat swing pose, and the treadmill "actively running" hint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer

local EffectsController = {}

local SWING_TIME = 0.35
local TREADMILL_POLL = 0.5

local function character(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return char, hum, if root and root:IsA("BasePart") then root else nil
end

-- ===== Camera shake (Humanoid.CameraOffset, so it never fights the camera scripts) =====
local shakeUntil = 0
local shakeStrength = 0
local shakeConn: RBXScriptConnection? = nil

function EffectsController.Shake(strength: number, duration: number)
	if player:GetAttribute("LowGraphics") then
		strength *= 0.5
	end
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
	if shakeConn then
		return
	end
	shakeConn = RunService.RenderStepped:Connect(function()
		local _, hum = character()
		local left = shakeUntil - os.clock()
		if left <= 0 or not hum then
			if hum then
				hum.CameraOffset = Vector3.zero
			end
			shakeStrength = 0
			if shakeConn then
				shakeConn:Disconnect()
				shakeConn = nil
			end
			return
		end
		local s = shakeStrength * math.min(left * 3, 1)
		hum.CameraOffset = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, (math.random() - 0.5) * s * 0.5)
	end)
end

-- ===== Knockback / ragdoll =====
function EffectsController.Knockback(velocity: Vector3)
	local _, _, root = character()
	if root and typeof(velocity) == "Vector3" then
		root.AssemblyLinearVelocity = velocity
	end
end

local ragdollToken = 0

local function setRagdoll(on: boolean, duration: number?)
	local _, hum = character()
	if not hum then
		return
	end
	ragdollToken += 1
	local token = ragdollToken
	if on then
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		-- safety net in case the "off" message is lost (e.g. respawn timing)
		task.delay((duration or 2) + 1.5, function()
			if token == ragdollToken then
				setRagdoll(false)
			end
		end)
	else
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end
EffectsController.SetRagdoll = setRagdoll

-- ===== Foam bat swing =====
local swinging = false

function EffectsController.PlaySwing()
	local char = player.Character
	local grip = char and char:FindFirstChild("BatGrip", true)
	if not grip or not grip:IsA("Motor6D") or swinging then
		return
	end
	swinging = true
	local start = os.clock()
	local conn: RBXScriptConnection? = nil
	-- Stepped runs after the Animator writes joint transforms, so this pose wins for the frame.
	conn = RunService.Stepped:Connect(function()
		local t = (os.clock() - start) / SWING_TIME
		if t >= 1 or not grip.Parent then
			grip.Transform = CFrame.new()
			swinging = false
			if conn then
				conn:Disconnect()
			end
			return
		end
		local angle
		if t < 0.2 then
			angle = -50 * (t / 0.2) -- wind up
		elseif t < 0.55 then
			angle = -50 + 160 * ((t - 0.2) / 0.35) -- smack
		else
			angle = 110 * (1 - (t - 0.55) / 0.45) -- recover
		end
		grip.Transform = CFrame.Angles(math.rad(angle), 0, math.rad(angle * 0.25))
	end)
end

-- ===== Treadmill hint =====
local treadmillActive = false

local function setTreadmill(active: boolean)
	if active ~= treadmillActive then
		treadmillActive = active
		Net.Event("TreadmillActive"):FireServer(active)
	end
end

local function onOwnTreadmill(char: Model, root: BasePart): boolean
	local baseName = player:GetAttribute("BaseName")
	local bases = workspace:FindFirstChild("Bases")
	local base = type(baseName) == "string" and bases and bases:FindFirstChild(baseName)
	if not base then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
	local inst: Instance? = hit and hit.Instance
	while inst and inst ~= base do
		if inst.Name == "Treadmill" then
			return true
		end
		inst = inst.Parent
	end
	return false
end

function EffectsController.Start()
	Net.Event("Knockback").OnClientEvent:Connect(EffectsController.Knockback)
	Net.Event("Ragdoll").OnClientEvent:Connect(function(on, duration)
		setRagdoll(on == true, tonumber(duration))
	end)
	Net.Event("Effect").OnClientEvent:Connect(function(name)
		if name == "Trapped" then
			EffectsController.Shake(0.8, 0.6)
		elseif name == "Tagged" then
			EffectsController.Shake(0.5, 0.35)
		end
	end)

	player.CharacterAdded:Connect(function()
		ragdollToken += 1
		swinging = false
		setTreadmill(false)
	end)

	task.spawn(function()
		while true do
			task.wait(TREADMILL_POLL)
			local char, hum, root = character()
			local active = false
			if char and hum and root and hum.Health > 0 and hum.MoveDirection.Magnitude > 0.1 then
				active = onOwnTreadmill(char, root)
			end
			setTreadmill(active)
		end
	end)
end

return EffectsController

-- WorldFXController: client-only world polish.
--   * hub speed-lane arrows pulse in their travel direction
--   * the hub conveyor's star specks stream along the belt instead of sitting still
--   * own treadmill: while you run on it the belt moves under you (run in place), idle = still
--   * Epic+ eggs sitting in nests get a tall light beacon so they can be spotted from afar
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local player = Players.LocalPlayer
local WorldFX = {}

local arrows: { [BasePart]: number } = {}
local specks: { { Part: BasePart, BaseCF: CFrame, Offset: number } } = {}
local beltMinX, beltLen = 0, 1
local beacons: { [Model]: BasePart } = {}

local function lowGfx(): boolean
	return player:GetAttribute("LowGraphics") == true
end

local function collectHub()
	local hub = workspace:FindFirstChild("Hub")
	local lanes = hub and hub:FindFirstChild("SpeedLanes")
	if lanes then
		for _, d in ipairs(lanes:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "SpeedLaneArrow" then
				arrows[d] = if d.Parent and d.Parent.Name == "LaneMinusX" then -1 else 1
			end
		end
	end
	local conveyor = workspace:FindFirstChild("Conveyor")
	local belt = conveyor and conveyor:FindFirstChild("Belt") :: BasePart?
	if conveyor and belt then
		beltMinX = belt.Position.X - belt.Size.X / 2
		beltLen = belt.Size.X
		for _, d in ipairs(conveyor:GetChildren()) do
			if d:IsA("BasePart") and d.Name == "StarSpeck" then
				table.insert(specks, { Part = d, BaseCF = d.CFrame, Offset = d.Position.X - beltMinX })
			end
		end
	end
end

-- ===== treadmill =====
local function ownTreadmill(): (BasePart?, Vector3?)
	local baseName = player:GetAttribute("BaseName")
	local bases = workspace:FindFirstChild("Bases")
	local base = baseName and bases and bases:FindFirstChild(baseName)
	local tread = base and base:FindFirstChild("Treadmill") :: BasePart?
	if not tread then
		return nil, nil
	end
	-- the belt pushes away from the treadmill console (towards the base entrance)
	local console = base:FindFirstChild("TreadmillConsole", true) :: BasePart?
	local axis = tread.CFrame.LookVector
	if console then
		local d = (tread.Position - console.Position) * Vector3.new(1, 0, 1)
		if d.Magnitude > 0.1 then
			axis = d.Unit
		end
	end
	return tread, axis
end

local function updateTreadmill()
	local tread, push = ownTreadmill()
	if not tread or not push then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local velocity = Vector3.zero
	if hrp and hum then
		local p = tread.CFrame:PointToObjectSpace(hrp.Position)
		local on = math.abs(p.X) <= tread.Size.X / 2 + 0.5 and math.abs(p.Z) <= tread.Size.Z / 2 + 0.5 and p.Y > 0 and p.Y < 7
		-- only while running against the belt, so AFK training never pushes you off
		if on and hum.MoveDirection.Magnitude > 0.1 and hum.MoveDirection:Dot(-push) > 0.3 then
			velocity = push * hum.WalkSpeed * 0.97
		end
	end
	if tread.AssemblyLinearVelocity ~= velocity then
		tread.AssemblyLinearVelocity = velocity -- local only: affects this client's own character
	end
end

-- ===== egg beacons =====
local function beaconFor(model: Model)
	local rarity = GameConfig.Rarities.ById[model:GetAttribute("Rarity") or ""]
	local wants = rarity and rarity.Index >= 4 and model:GetAttribute("State") == "Nest" and not lowGfx()
	local existing = beacons[model]
	if wants and not existing and model.PrimaryPart then
		local beam = Instance.new("Part")
		beam.Name = "RR_Beacon"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = rarity.Color
		beam.Transparency = 0.55
		beam.Shape = Enum.PartType.Cylinder
		local h = 40 + rarity.Index * 12
		beam.Size = Vector3.new(h, 1.2 + rarity.Index * 0.15, 1.2 + rarity.Index * 0.15)
		beam.CFrame = CFrame.new(model:GetPivot().Position + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beam.Parent = workspace.CurrentCamera
		beacons[model] = beam
	elseif not wants and existing then
		existing:Destroy()
		beacons[model] = nil
	end
end

local function watchEgg(model: Instance)
	if not model:IsA("Model") then
		return
	end
	beaconFor(model)
	model:GetAttributeChangedSignal("State"):Connect(function()
		beaconFor(model)
	end)
end

function WorldFX.Start()
	collectHub()
	for _, m in ipairs(CollectionService:GetTagged("RR_Egg")) do
		watchEgg(m)
	end
	CollectionService:GetInstanceAddedSignal("RR_Egg"):Connect(watchEgg)
	CollectionService:GetInstanceRemovedSignal("RR_Egg"):Connect(function(m)
		local b = beacons[m :: Model]
		if b then
			b:Destroy()
			beacons[m :: Model] = nil
		end
	end)

	local clock, lightAcc = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		lightAcc += dt
		updateTreadmill()
		if lightAcc < 1 / 20 then
			return
		end
		lightAcc = 0
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local camPos = cam.CFrame.Position
		for part, dir in pairs(arrows) do
			if part.Parent and (part.Position - camPos).Magnitude < 200 then
				local wave = 0.5 + 0.5 * math.cos(((part.Position.X * dir - clock * 40) / 48) * math.pi * 2)
				part.LocalTransparencyModifier = 0.5 * (1 - wave)
			end
		end
		if not lowGfx() then
			local speed = GameConfig.Settings.ConveyorSpeed
			for _, s in ipairs(specks) do
				if s.Part.Parent and (s.BaseCF.Position - camPos).Magnitude < 260 then
					local x = (s.Offset + clock * speed) % beltLen
					local pos = s.BaseCF.Position
					s.Part.CFrame = s.BaseCF.Rotation + Vector3.new(beltMinX + x, pos.Y, pos.Z)
				end
			end
		end
		for model, beam in pairs(beacons) do
			beam.Transparency = 0.5 + 0.2 * math.sin(clock * 3 + model:GetPivot().Position.X)
		end
	end)
end

return WorldFX

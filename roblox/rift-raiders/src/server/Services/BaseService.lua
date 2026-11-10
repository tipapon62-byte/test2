-- BaseService: assigns one personal base per player and owns everything physical about it:
-- base frame/coordinates, owner barrier (collision groups + server push-out), visual floors,
-- incubator pads, fuse machine, shop terminal, spawn point and owner sign.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ModelFactory = require(Shared:WaitForChild("ModelFactory"))

local S = GameConfig.Settings
local E = GameConfig.Economy

local BaseService = {}

type BaseInfo = {
	Model: Model,
	Index: number,
	Floor: BasePart,
	Frame: CFrame,       -- at the front edge centre, LookVector pointing into the base
	HalfWidth: number,
	Depth: number,
	Owner: Player?,
	Floors: { [number]: Instance? },
	Pads: { Model },
	Scale: number?,
	Runtime: Folder,
	Treadmill: BasePart?,
	BarrierGroup: string,
	OwnerGroup: string,
}

local bases: { BaseInfo } = {}
local byModel: { [Model]: BaseInfo } = {}
local byPlayer: { [Player]: BaseInfo } = {}
local Services

local PLAYER_GROUP = "RR_Players"
local OWNER_COLORS = {
	Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 120, 120), Color3.fromRGB(120, 255, 150), Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(200, 130, 255), Color3.fromRGB(255, 150, 220), Color3.fromRGB(120, 255, 240), Color3.fromRGB(255, 170, 90),
}

local function safeBuild(fnName: string): Model?
	local fn = (ModelFactory :: any)[fnName]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, model = pcall(fn)
	if ok then
		return model
	end
	warn("[BaseService] ModelFactory." .. fnName .. " failed:", model)
	return nil
end

local function registerGroup(name: string)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end

local function setCharacterGroup(character: Model, group: string)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

-- World CFrame for a point given in base-local coordinates (x = sideways, depth = into the base).
function BaseService.LocalToWorld(info: BaseInfo, x: number, depth: number, y: number?): CFrame
	return info.Frame * CFrame.new(-x, y or 0, -depth)
end

-- Base-local (x, depth, height) of a world position.
function BaseService.WorldToLocal(info: BaseInfo, pos: Vector3): (number, number, number)
	local p = info.Frame:PointToObjectSpace(pos)
	return -p.X, -p.Z, p.Y
end

local function setupBase(model: Model, index: number)
	local floor = model:FindFirstChild("Floor") :: BasePart?
	local mat = model:FindFirstChild("EntranceMat") :: BasePart?
	if not floor then
		warn("[BaseService] base without Floor:", model:GetFullName())
		return
	end
	-- the entrance faces the hub's centre line (Z = 0) when no EntranceMat exists
	local inward = if mat
		then (floor.Position - mat.Position) * Vector3.new(1, 0, 1)
		else Vector3.new(0, 0, if floor.Position.Z > 0 then 1 else -1)
	inward = inward.Unit
	local depthSize = math.abs(inward.Z) > 0.5 and floor.Size.Z or floor.Size.X
	local widthSize = math.abs(inward.Z) > 0.5 and floor.Size.X or floor.Size.Z
	local top = floor.Position.Y + floor.Size.Y / 2
	local front = Vector3.new(floor.Position.X, top, floor.Position.Z) - inward * (depthSize / 2)

	-- leftovers from the previous version of the place (steal-lock and cash collectors)
	for _, name in ipairs({ "LockButton", "LockStand", "FloorStand", "FloorConsole", "FloorScreen", "Collectors", "Characters" }) do
		local old = model:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "CollectFrame" or (d.Parent and d.Parent.Name == "Collectors") then
			d:Destroy()
		end
	end

	local info: BaseInfo = {
		Model = model,
		Index = index,
		Floor = floor,
		Frame = CFrame.lookAt(front, front + inward),
		HalfWidth = widthSize / 2,
		Depth = depthSize,
		Owner = nil,
		Floors = { [2] = model:FindFirstChild("Floor2"), [3] = model:FindFirstChild("Floor3") },
		Pads = {},
		Runtime = Instance.new("Folder"),
		Treadmill = model:FindFirstChild("Treadmill") :: BasePart?,
		BarrierGroup = "RR_Barrier" .. index,
		OwnerGroup = "RR_Owner" .. index,
	}
	info.Runtime.Name = "RiftRaiders"
	info.Runtime.Parent = model
	local pets = Instance.new("Folder")
	pets.Name = "Pets"
	pets.Parent = info.Runtime
	local incubators = Instance.new("Folder")
	incubators.Name = "Incubators"
	incubators.Parent = info.Runtime

	registerGroup(info.BarrierGroup)
	registerGroup(info.OwnerGroup)
	PhysicsService:CollisionGroupSetCollidable(info.BarrierGroup, info.OwnerGroup, false)
	PhysicsService:CollisionGroupSetCollidable(info.BarrierGroup, PLAYER_GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(info.BarrierGroup, "Default", false)

	local laser = model:FindFirstChild("Laser") :: BasePart?
	if laser then
		laser.CanCollide = true
		laser.CollisionGroup = info.BarrierGroup
		laser.Material = Enum.Material.ForceField
		laser.Transparency = 0.6
	end

	-- eggs hatch directly on enclosure slots (no incubator machines); props scale with the base
	local scale = math.clamp(info.Depth / 97, 0.4, 1)
	info.Scale = scale
	local fuse = safeBuild("BuildFuseMachine")
	if fuse then
		fuse.Name = "FuseMachine"
		fuse:ScaleTo(fuse:GetScale() * math.max(scale, 0.6))
		fuse:PivotTo(BaseService.LocalToWorld(info, info.HalfWidth * 0.5, info.Depth * 0.52) * CFrame.Angles(0, -math.pi / 2, 0))
		fuse.Parent = info.Runtime
	end
	local shop = safeBuild("BuildShopTerminal")
	if shop then
		shop.Name = "ShopTerminal"
		shop:ScaleTo(shop:GetScale() * math.max(scale, 0.7))
		shop:PivotTo(BaseService.LocalToWorld(info, info.HalfWidth * 0.38, info.Depth * 0.1) * CFrame.Angles(0, math.pi, 0))
		shop.Parent = info.Runtime
	end

	table.insert(bases, info)
	byModel[model] = info
	BaseService.SetVisualFloors(info, 1)
	BaseService.RefreshSign(info)
end

function BaseService.SetVisualFloors(info: BaseInfo, n: number)
	for level, inst in pairs(info.Floors) do
		if inst then
			inst.Parent = if n >= level then info.Model else nil
		end
	end
end

function BaseService.SetPadCount(info: BaseInfo, n: number)
	for i, pad in ipairs(info.Pads) do
		pad.Parent = if i <= n then info.Runtime:FindFirstChild("Incubators") else nil
	end
end

function BaseService.RefreshSign(info: BaseInfo)
	local sign = info.Model:FindFirstChild("Sign") :: BasePart?
	if not sign then
		return
	end
	local gui = sign:FindFirstChild("OwnerGui") :: SurfaceGui?
	if not gui then
		local g = Instance.new("SurfaceGui")
		g.Name = "OwnerGui"
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 30
		g.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextStrokeTransparency = 0
		label.Parent = g
		g.Parent = sign
		gui = g
		-- the sign faces outward; flip the face if the part's front points into the base
		if sign.CFrame.LookVector:Dot(info.Frame.LookVector) > 0 then
			g.Face = Enum.NormalId.Back
		end
	end
	local label = (gui :: SurfaceGui):FindFirstChild("Label") :: TextLabel
	local color = OWNER_COLORS[(info.Index - 1) % #OWNER_COLORS + 1]
	if info.Owner then
		label.Text = info.Owner.DisplayName .. "'s Rift Base"
		label.TextColor3 = color
	else
		label.Text = "Free Rift Base"
		label.TextColor3 = Color3.fromRGB(200, 200, 210)
	end
	local laser = info.Model:FindFirstChild("Laser") :: BasePart?
	if laser then
		laser.Color = if info.Owner then color else Color3.fromRGB(150, 150, 160)
	end
end

-- ===== Queries =====

function BaseService.GetBase(player: Player): BaseInfo?
	return byPlayer[player]
end

function BaseService.GetInfo(model: Model): BaseInfo?
	return byModel[model]
end

function BaseService.All(): { BaseInfo }
	return bases
end

-- Inside the protected interior (behind the barrier line)?
function BaseService.IsInside(info: BaseInfo, pos: Vector3): boolean
	local x, depth, h = BaseService.WorldToLocal(info, pos)
	return depth > 2.5 and depth < info.Depth + 2 and math.abs(x) < info.HalfWidth + 1 and h > -6 and h < 60
end

-- Within `margin` studs of the base footprint (porch included)?
function BaseService.IsNear(info: BaseInfo, pos: Vector3, margin: number): boolean
	local x, depth = BaseService.WorldToLocal(info, pos)
	return depth > -margin and depth < info.Depth + margin and math.abs(x) < info.HalfWidth + margin
end

function BaseService.FindBaseAt(pos: Vector3): BaseInfo?
	for _, info in ipairs(bases) do
		if BaseService.IsInside(info, pos) then
			return info
		end
	end
	return nil
end

function BaseService.GetSlotPart(info: BaseInfo, slot: number): BasePart?
	return info.Model:FindFirstChild("Slot" .. slot, true) :: BasePart?
end

function BaseService.GetSlotCFrame(info: BaseInfo, slot: number): CFrame?
	local part = BaseService.GetSlotPart(info, slot)
	if not part then
		return nil
	end
	local top = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
	-- pets face the base's centre aisle
	local centre = BaseService.LocalToWorld(info, 0, select(2, BaseService.WorldToLocal(info, top))).Position
	local look = Vector3.new(centre.X, top.Y, centre.Z)
	if (look - top).Magnitude < 0.1 then
		return CFrame.new(top)
	end
	return CFrame.lookAt(top, look)
end

function BaseService.GetPad(info: BaseInfo, i: number): Model?
	return info.Pads[i]
end

function BaseService.GetSpawnCFrame(info: BaseInfo): CFrame
	return BaseService.LocalToWorld(info, 0, math.max(5, info.Depth * 0.12), 3)
end

-- Just outside the front door.
function BaseService.GetPorchCFrame(info: BaseInfo): CFrame
	return BaseService.LocalToWorld(info, 0, -10, 3) * CFrame.Angles(0, math.pi, 0)
end

function BaseService.IsOnTreadmill(info: BaseInfo, pos: Vector3): boolean
	local t = info.Treadmill
	if not t then
		return false
	end
	local p = t.CFrame:PointToObjectSpace(pos)
	return math.abs(p.X) <= t.Size.X / 2 + 1.5 and math.abs(p.Z) <= t.Size.Z / 2 + 1.5 and p.Y > -1 and p.Y < 8
end

-- Purchases need the player inside their own base or near the hub shop.
function BaseService.CanShop(player: Player): boolean
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	local info = byPlayer[player]
	if info and BaseService.IsNear(info, hrp.Position, 6) then
		return true
	end
	local hub = workspace:FindFirstChild("Hub")
	local shop = hub and hub:FindFirstChild("SpeedShop")
	if shop and shop:IsA("Model") then
		return (shop:GetPivot().Position - hrp.Position).Magnitude <= S.ShopRange
	end
	return false
end

-- ===== Ownership =====

local function applyOwnerGroup(player: Player, character: Model)
	local info = byPlayer[player]
	local group = if info then info.OwnerGroup else PLAYER_GROUP
	setCharacterGroup(character, group)
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			local cur = byPlayer[player]
			d.CollisionGroup = if cur then cur.OwnerGroup else PLAYER_GROUP
		end
	end)
end

function BaseService.Assign(player: Player): BaseInfo?
	if byPlayer[player] then
		return byPlayer[player]
	end
	for _, info in ipairs(bases) do
		if not info.Owner then
			info.Owner = player
			byPlayer[player] = info
			info.Model:SetAttribute("OwnerId", player.UserId)
			info.Model:SetAttribute("OwnerName", player.DisplayName)
			player:SetAttribute("BaseName", info.Model.Name)
			BaseService.RefreshSign(info)
			BaseService.ApplyLevels(player)
			if player.Character then
				applyOwnerGroup(player, player.Character)
			end
			return info
		end
	end
	warn("[BaseService] no free base for", player.Name)
	return nil
end

function BaseService.Release(player: Player)
	local info = byPlayer[player]
	if not info then
		return
	end
	byPlayer[player] = nil
	info.Owner = nil
	info.Model:SetAttribute("OwnerId", 0)
	info.Model:SetAttribute("OwnerName", "")
	BaseService.SetVisualFloors(info, 1)
	BaseService.RefreshSign(info)
end

-- Re-applies upgrade visuals (floors, pads, treadmill colour) from the owner's profile.
function BaseService.ApplyLevels(player: Player)
	local info = byPlayer[player]
	local profile = Services.DataService.Get(player)
	if not info or not profile then
		return
	end
	local lvl = E.BaseLevels[math.clamp(profile.BaseLevel, 1, #E.BaseLevels)]
	BaseService.SetVisualFloors(info, lvl.VisualFloors)
	local tm = E.TreadmillLevels[math.clamp(profile.TreadmillLevel, 1, #E.TreadmillLevels)]
	for _, d in ipairs(info.Model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "TreadmillGlow" then
			d.Color = tm.Color
			d.Material = Enum.Material.Neon
		end
	end
end

function BaseService.Init(services)
	Services = services
end

function BaseService.Start()
	registerGroup(PLAYER_GROUP)
	local folder = workspace:WaitForChild("Bases")
	local models = folder:GetChildren()
	table.sort(models, function(a, b)
		return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
	end)
	for i, m in ipairs(models) do
		if m:IsA("Model") then
			setupBase(m, i)
		end
	end
	if #bases < S.MaxPlayers then
		warn(("[BaseService] only %d bases for %d players"):format(#bases, S.MaxPlayers))
	end
	-- players never collide with each other, so nobody can body-block a base exit
	local groups = { PLAYER_GROUP }
	for _, info in ipairs(bases) do
		table.insert(groups, info.OwnerGroup)
	end
	for _, a in ipairs(groups) do
		for _, b in ipairs(groups) do
			PhysicsService:CollisionGroupSetCollidable(a, b, false)
		end
	end

	local function onCharacter(player: Player, character: Model)
		applyOwnerGroup(player, character)
		local info = byPlayer[player]
		if info then
			local hrp = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
			if hrp then
				task.wait() -- let the default spawn finish first
				Services.AntiCheatService.Grace(player, 2)
				character:PivotTo(BaseService.GetSpawnCFrame(info))
			end
		end
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

	Services.DataService.OnLoaded(function(player)
		local info = BaseService.Assign(player)
		if info and player.Character then
			Services.AntiCheatService.Grace(player, 2)
			player.Character:PivotTo(BaseService.GetSpawnCFrame(info))
		end
	end)
	Services.DataService.OnRemoving(function(player)
		BaseService.Release(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		BaseService.Release(player)
	end)

	-- Server-side barrier: catches no-clip exploits and anyone the collision barrier missed.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local inside = BaseService.FindBaseAt(hrp.Position)
				if inside and inside.Owner ~= player then
					Services.AntiCheatService.Grace(player, 1)
					player.Character:PivotTo(BaseService.GetPorchCFrame(inside) + inside.Frame.LookVector * -(S.BaseIntruderPush - 10))
					Services.DataService.Notify(player, "That's someone else's base — you can't go inside.", "warn")
				end
			end
		end
	end)
end

return BaseService

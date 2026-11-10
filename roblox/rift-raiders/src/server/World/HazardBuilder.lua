-- HazardBuilder: builds each biome's hazards and runs them on the server.
-- Hit detection is a ~10 Hz position sweep over players (never Touched), with per-player
-- per-hazard cooldowns. Moving parts are anchored, CanCollide=false and moved by CFrame.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local Layout = GameConfig.Layout

local HazardBuilder = {}

local TICK = 0.1
local AVOID_R = 18
local GATE_CLEAR = 34
local END_CLEAR = 20

-- instances per hazard kind (zone totals land in the 6–12 range)
local COUNTS = {
	GooPuddle = 7, MudPit = 5, RollingLog = 3, Shallows = 4, Geyser = 4, Quicksand = 4, Tumbleweed = 4,
	SwingingLog = 3, ThornBush = 5, LavaCrack = 4, EruptionVent = 4, IceSheet = 4, FallingIcicle = 4,
	VoidPit = 6, MeteorStrike = 1,
}
local SLOW = { GooPuddle = 0.75, MudPit = 0.6, Shallows = 0.7, Quicksand = 0.45, ThornBush = 0.6 }

local C = Color3.fromRGB
local TAU = math.pi * 2
local HALF_PI = math.pi / 2
local M = Enum.Material
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local UP = Vector3.yAxis

local hazards: { any } = {}
local byZone: { [number]: { any } } = {}
local states: { [Player]: any } = {}
local ctx: any = nil
local started = false
local nextId = 0

-- ===== Instance helpers =====

local function mk(parent: Instance, size: Vector3, cf: CFrame, color: Color3, opts: any?): BasePart
	local o = opts or {}
	local p = Instance.new("Part")
	if o.Shape then
		p.Shape = o.Shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = o.Material or M.SmoothPlastic
	p.Anchored = true
	p.CanCollide = o.Solid == true
	p.CanQuery = o.Solid == true
	p.CanTouch = false
	p.CastShadow = o.Shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = o.Transparency or 0
	p.Reflectance = o.Reflectance or 0
	p.Name = o.Name or "Part"
	p.Parent = parent
	return p
end

-- Flat disc; pos.Y is the floor top, yTop the disc's top above it.
local function discCF(pos: Vector3, yTop: number, thick: number): CFrame
	return CFrame.new(pos.X, pos.Y + yTop - thick / 2, pos.Z) * CFrame.Angles(0, 0, HALF_PI)
end

local function disc(parent, pos: Vector3, r: number, yTop: number, thick: number, color: Color3, opts: any?): BasePart
	local o = table.clone(opts or {})
	o.Shape = CYL
	return mk(parent, Vector3.new(thick, r * 2, r * 2), discCF(pos, yTop, thick), color, o)
end

local function ball(parent, pos: Vector3, d: number, color: Color3, opts: any?): BasePart
	local o = table.clone(opts or {})
	o.Shape = BALL
	return mk(parent, Vector3.one * d, CFrame.new(pos), color, o)
end

local function vcylCF(base: Vector3, h: number): CFrame
	return CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, HALF_PI)
end

local function vcyl(parent, base: Vector3, h: number, d: number, color: Color3, opts: any?): BasePart
	local o = table.clone(opts or {})
	o.Shape = CYL
	return mk(parent, Vector3.new(h, d, d), vcylCF(base, h), color, o)
end

local function emitter(parent: Instance, props: any): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function newModel(env, kind: string): Model
	local m = Instance.new("Model")
	m.Name = kind
	m.Parent = env.Folder
	return m
end

local function tag(part: BasePart, kind: string, zone: number, radius: number?)
	part.Name = kind
	CollectionService:AddTag(part, "RR_Hazard")
	part:SetAttribute("HazardType", kind)
	part:SetAttribute("Zone", zone)
	if radius then
		part:SetAttribute("Radius", radius)
	end
	local m = part.Parent
	if m and m:IsA("Model") then
		m.PrimaryPart = part
	end
end

local function register(env, hz)
	nextId += 1
	hz.Id = nextId
	hz.Zone = env.Zone
	hz.Top = env.Top
	hz.Reach = hz.Reach or hz.Radius or 20
	table.insert(hazards, hz)
	byZone[env.Zone] = byZone[env.Zone] or {}
	table.insert(byZone[env.Zone], hz)
	if hz.Step then
		hz.Step(hz, os.clock(), function(p, cf)
			p.CFrame = cf
		end)
	end
	return hz
end

-- ===== Player helpers =====

local function rootOf(player: Player): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function zoneOfX(x: number): number
	return math.floor((x - Layout.StartX) / Layout.ZoneLength) + 1
end

local function call(name: string, ...): any
	local fn = ctx and ctx[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, res = pcall(fn, ...)
	if not ok then
		warn("[HazardBuilder] ctx." .. name .. " failed:", res)
		return nil
	end
	return res
end

local function stateOf(player: Player)
	local st = states[player]
	if not st then
		st = { Slows = {}, Slippery = false, Cd = {} }
		states[player] = st
	end
	return st
end

local function clearEffects(player: Player)
	local st = states[player]
	if not st then
		return
	end
	for key in pairs(st.Slows) do
		call("SetSlow", player, key, nil)
	end
	table.clear(st.Slows)
	if st.Slippery then
		st.Slippery = false
		call("SetSlippery", player, false)
	end
end

-- Cooldown + immunity gate for harmful hits.
local function tryHit(player: Player, hz, cooldown: number): boolean
	local st = stateOf(player)
	local now = os.clock()
	if (st.Cd[hz.Id] or 0) > now then
		return false
	end
	if call("IsImmune", player) then
		return false
	end
	st.Cd[hz.Id] = now + cooldown
	return true
end

local function awayDir(from: Vector3, pos: Vector3): Vector3
	local d = Vector3.new(pos.X - from.X, 0, pos.Z - from.Z)
	if d.Magnitude < 0.1 then
		local a = math.random() * TAU
		return Vector3.new(math.cos(a), 0, math.sin(a))
	end
	return d.Unit
end

-- Knockdown (and optional launch) without blocking the detection loop.
local function knock(player: Player, dir: Vector3, reason: string, launch: Vector3?)
	task.spawn(function()
		if launch then
			call("Launch", player, launch)
		end
		call("Knockdown", player, (dir + UP * 0.35).Unit, reason)
	end)
end

local function horizDist2(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return dx * dx + dz * dz
end

local function inCircle(hz, pos: Vector3, r: number, maxUp: number): boolean
	return horizDist2(pos, hz.Center) <= r * r and pos.Y <= hz.Top + maxUp and pos.Y >= hz.Top - 6
end

-- Players whose root is inside a horizontal radius around `pos` (and not high above it).
local function playersNear(pos: Vector3, r: number, maxUp: number): { { Player: Player, Root: BasePart } }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		if root and horizDist2(root.Position, pos) <= r * r and root.Position.Y <= pos.Y + maxUp and root.Position.Y >= pos.Y - 6 then
			table.insert(out, { Player = p, Root = root })
		end
	end
	return out
end

-- ===== Placement =====

local function circleFree(env, x: number, z: number, r: number): boolean
	for _, a in ipairs(env.Avoid) do
		if horizDist2(a, Vector3.new(x, 0, z)) < (AVOID_R + r) ^ 2 then
			return false
		end
	end
	for _, t in ipairs(env.Taken) do
		if t.Column then
			if math.abs(t.X - x) < t.R + r then
				return false
			end
		elseif (t.X - x) ^ 2 + (t.Z - z) ^ 2 < (t.R + r + 4) ^ 2 then
			return false
		end
	end
	return true
end

-- A lane-crossing strip at X (rolling/swinging hazards): checks avoid points along its Z span.
local function columnFree(env, x: number, halfX: number, span: number): boolean
	for _, a in ipairs(env.Avoid) do
		if math.abs(a.X - x) < AVOID_R + halfX and math.abs(a.Z) < span + AVOID_R then
			return false
		end
	end
	for _, t in ipairs(env.Taken) do
		if math.abs(t.X - x) < t.R + halfX + 4 then
			return false
		end
	end
	return true
end

-- |Z| band for a circular hazard of radius r. `minEdge` is how far its edge must stay from Z = 0
-- (negative = may cover part of the lane, but always leaves |minEdge|+10 studs of it open).
local function zFor(env, r: number, minEdge: number, extra: number): number
	local lo = math.max(0, r + minEdge)
	local hi = math.max(lo, math.min(env.Edge - r, lo + extra))
	return env.Rng:NextNumber(lo, hi) * (env.Rng:NextNumber() < 0.5 and -1 or 1)
end

local function findSpot(env, seg, r: number, minEdge: number, extra: number): Vector3?
	local rng = env.Rng
	for _ = 1, 30 do
		local x = seg.A + r < seg.B - r and rng:NextNumber(seg.A + r, seg.B - r) or (seg.A + seg.B) / 2
		local z = zFor(env, r, minEdge, extra)
		if circleFree(env, x, z, r) then
			table.insert(env.Taken, { X = x, Z = z, R = r })
			return Vector3.new(x, env.Top, z)
		end
	end
	return nil
end

local function findColumn(env, seg, halfX: number, span: number): number?
	local rng = env.Rng
	for _ = 1, 30 do
		local x = rng:NextNumber(seg.A + halfX, math.max(seg.A + halfX, seg.B - halfX))
		if columnFree(env, x, halfX, span) then
			table.insert(env.Taken, { X = x, Z = 0, R = halfX, Column = true })
			return x
		end
	end
	return nil
end

local function slowRegion(env, root: BasePart, kind: string, centre: Vector3, r: number)
	tag(root, kind, env.Zone, r)
	register(env, { Kind = kind, Center = centre, Radius = r, SlowKey = kind, SlowMult = SLOW[kind] })
end

-- ===== Builders =====

local Builders = {}

function Builders.GooPuddle(env, seg)
	local r = env.Rng:NextNumber(7, 10)
	local spot = findSpot(env, seg, r, -2, 30)
	if not spot then
		return
	end
	local m = newModel(env, "GooPuddle")
	local accent = env.Theme.Accent
	local root = disc(m, spot, r, 0.14, 0.3, accent:Lerp(C(30, 50, 45), 0.4), { Transparency = 0.1 })
	disc(m, spot + Vector3.new(r * 0.15, 0, -r * 0.1), r * 0.55, 0.2, 0.3, accent, { Material = M.Neon, Transparency = 0.45 })
	for _ = 1, 4 do
		local a, d = env.Rng:NextNumber(0, TAU), env.Rng:NextNumber(0, r * 0.75)
		ball(m, spot + Vector3.new(math.cos(a) * d, 0.3, math.sin(a) * d), env.Rng:NextNumber(0.6, 1.5), accent:Lerp(Color3.new(1, 1, 1), 0.3), { Transparency = 0.25 })
	end
	slowRegion(env, root, "GooPuddle", spot, r)
end

function Builders.MudPit(env, seg)
	local r = env.Rng:NextNumber(8, 12)
	local spot = findSpot(env, seg, r, -2, 35)
	if not spot then
		return
	end
	local m = newModel(env, "MudPit")
	disc(m, spot, r + 1.3, 0.22, 0.3, C(120, 90, 60), { Material = M.Ground })
	local root = disc(m, spot, r, 0.28, 0.3, C(85, 60, 40), { Material = M.Mud })
	for _ = 1, 3 do
		local a, d = env.Rng:NextNumber(0, TAU), env.Rng:NextNumber(0, r * 0.6)
		disc(m, spot + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), env.Rng:NextNumber(1, 2.4), 0.32, 0.1, C(65, 48, 35), { Reflectance = 0.2 })
	end
	for _ = 1, 3 do
		local a, d = env.Rng:NextNumber(0, TAU), env.Rng:NextNumber(0, r * 0.7)
		ball(m, spot + Vector3.new(math.cos(a) * d, 0.35, math.sin(a) * d), env.Rng:NextNumber(0.6, 1.1), C(105, 78, 55))
	end
	slowRegion(env, root, "MudPit", spot, r)
end

function Builders.Shallows(env, seg)
	local r = env.Rng:NextNumber(13, 18)
	local spot = findSpot(env, seg, r, -2, 25)
	if not spot then
		return
	end
	local m = newModel(env, "Shallows")
	disc(m, spot, r + 1.5, 0.18, 0.3, C(215, 205, 165), { Material = M.Sand })
	local root = disc(m, spot, r, 0.4, 0.4, C(80, 185, 235), { Material = M.Glass, Transparency = 0.35, Reflectance = 0.15 })
	disc(m, spot, r * 0.6, 0.42, 0.05, C(150, 225, 255), { Material = M.Neon, Transparency = 0.8 })
	for _ = 1, 3 do
		local a, d = env.Rng:NextNumber(0, TAU), env.Rng:NextNumber(r * 0.3, r * 0.85)
		disc(m, spot + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), env.Rng:NextNumber(1.4, 2.2), 0.5, 0.15, C(80, 170, 90))
	end
	slowRegion(env, root, "Shallows", spot, r)
end

function Builders.Quicksand(env, seg)
	local r = env.Rng:NextNumber(9, 12)
	local spot = findSpot(env, seg, r, -2, 30)
	if not spot then
		return
	end
	local m = newModel(env, "Quicksand")
	local root = disc(m, spot, r, 0.2, 0.3, C(200, 160, 100), { Material = M.Sand })
	disc(m, spot, r * 0.65, 0.24, 0.3, C(165, 125, 75), { Material = M.Sand })
	disc(m, spot, r * 0.2, 0.27, 0.3, C(110, 80, 50))
	local arms = {}
	for _ = 1, 4 do
		table.insert(arms, mk(m, Vector3.new(r * 0.8, 0.08, 0.7), CFrame.new(spot), C(232, 198, 140)))
	end
	emitter(root, {
		Color = ColorSequence.new(C(230, 200, 140)), Size = NumberSequence.new(0.6, 1.2), Transparency = NumberSequence.new(0.6, 1),
		Lifetime = NumberRange.new(1, 2), Rate = 3, Speed = NumberRange.new(1, 2), EmissionDirection = Enum.NormalId.Right,
	})
	tag(root, "Quicksand", env.Zone, r)
	register(env, {
		Kind = "Quicksand", Center = spot, Radius = r, SlowKey = "Quicksand", SlowMult = SLOW.Quicksand,
		Step = function(_, now, push)
			local base = now * 0.9
			for i, arm in ipairs(arms) do
				local a = base + i * HALF_PI
				-- offset + skew gives a spiral "drain" look
				push(arm, CFrame.new(spot + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(r * 0.38, 0, 0) * CFrame.Angles(0, 0.55, 0))
			end
		end,
	})
end

function Builders.ThornBush(env, seg)
	local r = env.Rng:NextNumber(6, 8)
	local spot = findSpot(env, seg, r, -2, 35)
	if not spot then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "ThornBush")
	local root = disc(m, spot, r, 0.12, 0.2, C(60, 75, 40), { Material = M.Grass })
	for _ = 1, 3 do
		local a, d = rng:NextNumber(0, TAU), rng:NextNumber(0, r * 0.55)
		local size = rng:NextNumber(4, 6)
		local centre = spot + Vector3.new(math.cos(a) * d, size * 0.35, math.sin(a) * d)
		ball(m, centre, size, C(45, 85, 45):Lerp(C(80, 40, 60), rng:NextNumber(0, 0.3)), { Material = M.Grass })
		for _ = 1, 4 do
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 1), rng:NextNumber(-1, 1))
			if dir.Magnitude > 0.1 then
				mk(m, Vector3.new(0.3, 0.3, 1.8), CFrame.lookAt(centre, centre + dir) * CFrame.new(0, 0, -size / 2), C(205, 70, 110))
			end
		end
		ball(m, centre + Vector3.new(0, size * 0.45, 0), 0.7, C(255, 90, 140), { Material = M.Neon })
	end
	slowRegion(env, root, "ThornBush", spot, r)
end

local function pathTrack(env, m, x: number, width: number, span: number)
	local ground = env.Theme.Ground:Lerp(Color3.new(0, 0, 0), 0.3)
	mk(m, Vector3.new(width, 0.12, span * 2), CFrame.new(x, env.Top + 0.07, 0), ground, { Name = "Track" })
	for side = -1, 1, 2 do
		mk(m, Vector3.new(width + 2, 2.2, 2.2), CFrame.new(x, env.Top + 1, side * (span + 1.5)) * CFrame.Angles(0.3, 0.5, 0.2), C(110, 105, 100), { Name = "Stopper" })
	end
end

function Builders.RollingLog(env, seg)
	local L, D = 13, 5
	local span = math.min(55, env.Edge - D)
	local x = findColumn(env, seg, L / 2 + 2, span)
	if not x then
		span = 32 -- shorter run that still crosses the lane, for crowded nest areas
		x = findColumn(env, seg, L / 2 + 2, span)
	end
	if not x then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "RollingLog")
	pathTrack(env, m, x, L + 2, span + D / 2)
	local log = mk(m, Vector3.new(L, D, D), CFrame.new(x, env.Top + D / 2, 0), C(120, 82, 48), { Shape = CYL, Material = M.Wood })
	local caps = {
		mk(m, Vector3.new(0.3, D - 0.6, D - 0.6), CFrame.new(), C(215, 175, 120), { Shape = CYL }),
		mk(m, Vector3.new(0.3, D - 0.6, D - 0.6), CFrame.new(), C(215, 175, 120), { Shape = CYL }),
	}
	local moss = mk(m, Vector3.new(L * 0.6, 0.5, 1.6), CFrame.new(), C(110, 175, 70))
	local period, offset = rng:NextNumber(6.5, 8.5), rng:NextNumber(0, 10)
	local cy = env.Top + D / 2
	tag(log, "RollingLog", env.Zone, D / 2)
	register(env, {
		Kind = "RollingLog", Center = Vector3.new(x, env.Top, 0), Reach = span + 12, Pos = Vector3.new(x, cy, 0), Dir = 1,
		Step = function(hz, now, push)
			local t = ((now + offset) % period) / period
			local z = -span + 2 * span * (0.5 - 0.5 * math.cos(t * TAU)) -- eased ping-pong
			local cf = CFrame.new(x, cy, z) * CFrame.Angles(z / (D / 2), 0, 0)
			push(log, cf)
			push(caps[1], cf * CFrame.new(L / 2, 0, 0))
			push(caps[2], cf * CFrame.new(-L / 2, 0, 0))
			push(moss, cf * CFrame.new(0, D / 2, 0))
			hz.Pos = Vector3.new(x, cy, z)
			hz.Dir = math.sin(t * TAU) >= 0 and 1 or -1
		end,
		Test = function(hz, player, pos)
			local dz, dy = pos.Z - hz.Pos.Z, pos.Y - hz.Pos.Y
			if math.abs(pos.X - x) <= L / 2 + 1.5 and dz * dz + dy * dy <= (D / 2 + 1.8) ^ 2 and tryHit(player, hz, 2) then
				knock(player, Vector3.new(0, 0, hz.Dir), "RollingLog")
			end
		end,
	})
end

function Builders.Tumbleweed(env, seg)
	local D = env.Rng:NextNumber(5, 6.5)
	local span = math.min(60, env.Edge - D)
	local x = findColumn(env, seg, D / 2 + 3, span)
	if not x then
		span = 32
		x = findColumn(env, seg, D / 2 + 3, span)
	end
	if not x then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "Tumbleweed")
	local weed = mk(m, Vector3.one * D, CFrame.new(x, env.Top + D / 2, 0), C(175, 135, 80), { Shape = BALL, Material = M.Fabric, Transparency = 0.3 })
	local twigs = {}
	for i = 1, 3 do
		table.insert(twigs, { mk(m, Vector3.new(D * 0.95, 0.3, 0.3), CFrame.new(), C(120, 85, 50)), CFrame.Angles(i * 1.1, i * 2.1, i * 0.7) })
	end
	local period, offset = rng:NextNumber(5.5, 7.5), rng:NextNumber(0, 10)
	local bounces = rng:NextInteger(5, 7)
	tag(weed, "Tumbleweed", env.Zone, D / 2)
	register(env, {
		Kind = "Tumbleweed", Center = Vector3.new(x, env.Top, 0), Reach = span + 12, Pos = weed.Position, Dir = 1,
		Step = function(hz, now, push)
			local t = ((now + offset) % period) / period
			local z = -span + 2 * span * (0.5 - 0.5 * math.cos(t * TAU))
			local y = env.Top + D / 2 + 3.2 * math.abs(math.sin(t * math.pi * bounces))
			local cf = CFrame.new(x + math.sin(now * 1.7) * 1.5, y, z) * CFrame.Angles(z / (D / 2), now * 0.6, 0)
			push(weed, cf)
			for _, tw in ipairs(twigs) do
				push(tw[1], cf * tw[2])
			end
			hz.Pos = cf.Position
			hz.Dir = math.sin(t * TAU) >= 0 and 1 or -1
		end,
		Test = function(hz, player, pos)
			if (pos - hz.Pos).Magnitude <= D / 2 + 2 and tryHit(player, hz, 2) then
				knock(player, Vector3.new(0, 0, hz.Dir), "Tumbleweed")
			end
		end,
	})
end

function Builders.SwingingLog(env, seg)
	local L, D, ROPE, AMP = 11, 4.5, 25, 1.15
	local postZ = ROPE * math.sin(AMP) + 4
	local x = findColumn(env, seg, L / 2 + 3, postZ + 3)
	if not x then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "SwingingLog")
	local pivotY = env.Top + 28
	local wood, vine = C(95, 70, 45), C(60, 150, 60)
	-- gantry across the lane; posts stand outside the clear lane
	for side = -1, 1, 2 do
		vcyl(m, Vector3.new(x, env.Top, side * postZ), 30, 2.4, wood, { Solid = true, Material = M.Wood, Shadow = true })
		for k = 1, 3 do
			mk(m, Vector3.new(2.6, 0.5, 2.6), CFrame.new(x, env.Top + k * 7, side * postZ) * CFrame.Angles(0, k * 0.7, 0.3), vine)
		end
	end
	mk(m, Vector3.new(2.4, 2.4, postZ * 2 + 3), CFrame.new(x, pivotY + 1.2, 0), wood, { Material = M.Wood, Shadow = true })
	local log = mk(m, Vector3.new(L, D, D), CFrame.new(), C(110, 75, 45), { Shape = CYL, Material = M.Wood, Shadow = true })
	local ropes = {
		mk(m, Vector3.new(0.4, ROPE, 0.4), CFrame.new(), vine),
		mk(m, Vector3.new(0.4, ROPE, 0.4), CFrame.new(), vine),
	}
	local spikes = {}
	for i = -1, 1 do
		table.insert(spikes, { mk(m, Vector3.new(0.6, 0.6, 2), CFrame.new(), C(220, 210, 180)), CFrame.new(i * 3.5, 0, D / 2 + 0.6) })
		table.insert(spikes, { mk(m, Vector3.new(0.6, 0.6, 2), CFrame.new(), C(220, 210, 180)), CFrame.new(i * 3.5, 0, -D / 2 - 0.6) })
	end
	local period, offset = rng:NextNumber(3.6, 4.6), rng:NextNumber(0, 10)
	local pivot = CFrame.new(x, pivotY, 0)
	tag(log, "SwingingLog", env.Zone, D / 2)
	register(env, {
		Kind = "SwingingLog", Center = Vector3.new(x, env.Top, 0), Reach = postZ + 12, Pos = Vector3.new(x, pivotY - ROPE, 0), Dir = 1,
		Step = function(hz, now, push)
			local phase = (now + offset) / period * TAU
			local theta = AMP * math.sin(phase)
			local arm = pivot * CFrame.Angles(-theta, 0, 0) -- positive theta swings toward +Z
			local cf = arm * CFrame.new(0, -ROPE, 0)
			push(log, cf)
			push(ropes[1], arm * CFrame.new(L * 0.35, -ROPE / 2, 0))
			push(ropes[2], arm * CFrame.new(-L * 0.35, -ROPE / 2, 0))
			for _, sp in ipairs(spikes) do
				push(sp[1], cf * sp[2])
			end
			hz.Pos = cf.Position
			hz.Dir = math.cos(phase) >= 0 and 1 or -1
		end,
		Test = function(hz, player, pos)
			local dz, dy = pos.Z - hz.Pos.Z, pos.Y - hz.Pos.Y
			if math.abs(pos.X - x) <= L / 2 + 1.5 and dz * dz + dy * dy <= (D / 2 + 2) ^ 2 and tryHit(player, hz, 2) then
				knock(player, Vector3.new(0, 0, hz.Dir), "SwingingLog", Vector3.new(0, 25, hz.Dir * 55))
			end
		end,
	})
end

-- Shared cycle helper: returns "Idle" | "Warn" | "Active" for a periodic hazard.
local function cyclePhase(now: number, offset: number, period: number, warnAt: number, activeAt: number, activeEnd: number): string
	local t = (now + offset) % period
	if t >= activeAt and t < activeEnd then
		return "Active"
	elseif t >= warnAt and t < activeAt then
		return "Warn"
	end
	return "Idle"
end

function Builders.Geyser(env, seg)
	local r = 5
	local spot = findSpot(env, seg, r + 1, 1, 30)
	if not spot then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "Geyser")
	local water = C(150, 230, 255)
	for i = 1, 6 do
		local a = i * TAU / 6 + rng:NextNumber(-0.2, 0.2)
		mk(m, Vector3.new(2.6, 1.6, 2.2) * rng:NextNumber(0.8, 1.2), CFrame.new(spot + Vector3.new(math.cos(a) * (r + 0.6), 0.6, math.sin(a) * (r + 0.6))) * CFrame.Angles(0.2, a, 0.15), C(90, 110, 125))
	end
	local root = disc(m, spot, r, 0.25, 0.3, C(70, 160, 210), { Transparency = 0.25 })
	disc(m, spot, 1.6, 0.3, 0.3, C(25, 45, 60))
	local ring = disc(m, spot, r + 0.4, 0.33, 0.05, Color3.new(1, 1, 1), { Material = M.Neon, Transparency = 1 })
	local column = mk(m, Vector3.new(34, 6, 6), vcylCF(spot, 34), water, { Shape = CYL, Material = M.Neon, Transparency = 1 })
	local crest = ball(m, spot + Vector3.new(0, 34, 0), 9, water, { Transparency = 1 })
	local bubbles = emitter(root, {
		Color = ColorSequence.new(Color3.new(1, 1, 1)), Size = NumberSequence.new(0.4, 0.9), Transparency = NumberSequence.new(0.2, 1),
		Lifetime = NumberRange.new(0.5, 1), Rate = 40, Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(20, 20),
		EmissionDirection = Enum.NormalId.Right, Enabled = false,
	})
	local spray = emitter(crest, {
		Color = ColorSequence.new(water), Size = NumberSequence.new(1.5, 3), Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(0.6, 1.2), Rate = 60, Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(180, 180), Enabled = false,
	})
	local period, offset = rng:NextNumber(5.6, 6.6), rng:NextNumber(0, 10)
	tag(root, "Geyser", env.Zone, r)
	root:SetAttribute("Period", period)
	register(env, {
		Kind = "Geyser", Center = spot, Radius = r, Phase = "Idle",
		Tick = function(hz, now)
			local phase = cyclePhase(now, offset, period, period - 3, period - 1.5, period)
			if phase == hz.Phase then
				return
			end
			hz.Phase = phase
			root:SetAttribute("State", phase)
			bubbles.Enabled = phase ~= "Idle"
			ring.Transparency = phase == "Warn" and 0.45 or 1
			column.Transparency = phase == "Active" and 0.35 or 1
			crest.Transparency = phase == "Active" and 0.3 or 1
			spray.Enabled = phase == "Active"
		end,
		Test = function(hz, player, pos)
			if hz.Phase == "Active" and inCircle(hz, pos, 4.8, 36) and tryHit(player, hz, 2.5) then
				local side = awayDir(spot, pos) * 14
				task.spawn(call, "Launch", player, Vector3.new(side.X, 95, side.Z))
			end
		end,
	})
end

function Builders.LavaCrack(env, seg)
	local r = env.Rng:NextNumber(6, 9)
	local spot = findSpot(env, seg, r, 1, 30)
	if not spot then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "LavaCrack")
	local lava = C(255, 120, 30)
	local root = disc(m, spot, r, 0.12, 0.2, C(40, 28, 28), { Material = M.Basalt })
	for i = 1, 6 do
		local a = i * TAU / 6 + rng:NextNumber(-0.3, 0.3)
		local len1, len2 = rng:NextNumber(2.5, r * 0.55), rng:NextNumber(2, r * 0.4)
		local p1 = spot + Vector3.new(math.cos(a) * len1 / 2, 0.2, math.sin(a) * len1 / 2)
		mk(m, Vector3.new(len1, 0.15, rng:NextNumber(0.5, 0.9)), CFrame.new(p1) * CFrame.Angles(0, -a, 0), lava, { Material = M.Neon })
		local a2 = a + rng:NextNumber(-0.6, 0.6)
		local start = spot + Vector3.new(math.cos(a) * len1, 0, math.sin(a) * len1)
		local p2 = start + Vector3.new(math.cos(a2) * len2 / 2, 0.21, math.sin(a2) * len2 / 2)
		mk(m, Vector3.new(len2, 0.15, rng:NextNumber(0.35, 0.6)), CFrame.new(p2) * CFrame.Angles(0, -a2, 0), lava, { Material = M.Neon })
	end
	ball(m, spot + Vector3.new(0, 0.1, 0), 2.2, lava, { Material = M.Neon, Transparency = 0.2 })
	local glow = Instance.new("PointLight")
	glow.Color = lava
	glow.Range = r * 2
	glow.Brightness = 1.5
	glow.Parent = root
	emitter(root, {
		Color = ColorSequence.new(C(255, 200, 80), C(255, 60, 20)), LightEmission = 1, Size = NumberSequence.new(0.3, 0),
		Lifetime = NumberRange.new(1, 2), Rate = 8, Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Right,
	})
	tag(root, "LavaCrack", env.Zone, r)
	register(env, {
		Kind = "LavaCrack", Center = spot, Radius = r,
		Test = function(hz, player, pos)
			if inCircle(hz, pos, r * 0.85, 5) and tryHit(player, hz, 2.5) then
				local dir = awayDir(spot, pos)
				knock(player, dir, "LavaCrack", dir * 40 + UP * 55)
			end
		end,
	})
end

function Builders.EruptionVent(env, seg)
	local r = 6
	local spot = findSpot(env, seg, r + 1, 1, 30)
	if not spot then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "EruptionVent")
	local fire = C(255, 120, 30)
	vcyl(m, spot - Vector3.new(0, 0.2, 0), 1.4, 9, C(50, 40, 40), { Material = M.Basalt })
	vcyl(m, spot + Vector3.new(0, 1, 0), 1.2, 5.5, C(40, 32, 32), { Material = M.Basalt })
	local crater = disc(m, spot, 1.9, 2.25, 0.1, C(120, 45, 20), { Material = M.Neon })
	local root = disc(m, spot, r + 0.5, 0.1, 0.1, C(255, 40, 30), { Material = M.Neon, Transparency = 1 })
	local column = mk(m, Vector3.new(28, 6, 6), vcylCF(spot, 28), fire, { Shape = CYL, Material = M.Neon, Transparency = 1 })
	local flames = Instance.new("Fire")
	flames.Heat = 20
	flames.Size = 10
	flames.Color = fire
	flames.SecondaryColor = C(255, 220, 90)
	flames.Enabled = false
	flames.Parent = crater
	local smoke = Instance.new("Smoke")
	smoke.Color = C(70, 60, 60)
	smoke.Opacity = 0.08
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Parent = crater
	local period, offset = rng:NextNumber(6.5, 7.5), rng:NextNumber(0, 10)
	tag(root, "EruptionVent", env.Zone, r)
	register(env, {
		Kind = "EruptionVent", Center = spot, Radius = r, Phase = "Idle",
		Tick = function(hz, now)
			local phase = cyclePhase(now, offset, period, period - 2.9, period - 1.4, period)
			if phase == hz.Phase then
				return
			end
			hz.Phase = phase
			root:SetAttribute("State", phase)
			root.Transparency = phase == "Idle" and 1 or 0.55
			crater.Color = phase == "Idle" and C(120, 45, 20) or fire
			smoke.Opacity = phase == "Idle" and 0.08 or 0.3
			column.Transparency = phase == "Active" and 0.3 or 1
			flames.Enabled = phase == "Active"
		end,
		Test = function(hz, player, pos)
			if hz.Phase == "Active" and inCircle(hz, pos, r, 30) and tryHit(player, hz, 2.5) then
				local dir = awayDir(spot, pos)
				knock(player, dir, "EruptionVent", dir * 30 + UP * 60)
			end
		end,
	})
end

function Builders.IceSheet(env, seg)
	local r = env.Rng:NextNumber(12, 17)
	local spot = findSpot(env, seg, r, -2, 25)
	if not spot then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "IceSheet")
	disc(m, spot, r + 1, 0.15, 0.25, C(235, 245, 255), { Material = M.Snow })
	local root = disc(m, spot, r, 0.25, 0.3, C(190, 230, 255), { Material = M.Ice, Transparency = 0.15, Reflectance = 0.2 })
	for _ = 1, 4 do
		mk(m, Vector3.new(rng:NextNumber(r * 0.4, r * 1.1), 0.05, 0.2), CFrame.new(spot + Vector3.new(rng:NextNumber(-r, r) * 0.4, 0.27, rng:NextNumber(-r, r) * 0.4)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color3.new(1, 1, 1), { Transparency = 0.3 })
	end
	tag(root, "IceSheet", env.Zone, r)
	register(env, { Kind = "IceSheet", Center = spot, Radius = r, Slippery = true })
end

function Builders.FallingIcicle(env, seg)
	local AREA, HIT_R, WARN = 12, 4.5, 1.2
	local spot = findSpot(env, seg, AREA, -4, 20)
	if not spot then
		return
	end
	local rng = env.Rng
	local m = newModel(env, "FallingIcicle")
	local ice = C(200, 235, 255)
	local cloudY = env.Top + 40
	-- frozen overhang the icicles fall from (decor, high above)
	for i = 1, 3 do
		mk(m, Vector3.new(rng:NextNumber(8, 14), rng:NextNumber(3, 5), rng:NextNumber(8, 14)), CFrame.new(spot + Vector3.new(rng:NextNumber(-6, 6), 40 + i, rng:NextNumber(-6, 6))) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			C(170, 215, 245), { Material = M.Glass, Transparency = 0.2 })
	end
	for _ = 1, 5 do
		mk(m, Vector3.new(1, rng:NextNumber(3, 6), 1), CFrame.new(spot + Vector3.new(rng:NextNumber(-8, 8), 37, rng:NextNumber(-8, 8))) * CFrame.Angles(0, math.rad(45), 0), ice, { Material = M.Ice })
	end
	local root = disc(m, spot, AREA, 0.05, 0.05, C(150, 200, 240), { Transparency = 0.85 })
	local shadow = disc(m, spot, HIT_R, 0.12, 0.1, C(20, 30, 60), { Transparency = 1, Name = "Shadow" })
	local icicle = mk(m, Vector3.new(1.8, 7, 1.8), CFrame.new(spot + Vector3.new(0, 38, 0)), ice, { Material = M.Ice, Transparency = 1, Name = "Icicle" })
	tag(root, "FallingIcicle", env.Zone, AREA)
	local dropRng = Random.new(env.Zone * 1000 + seg.Index)
	register(env, {
		Kind = "FallingIcicle", Center = spot, Radius = AREA, Reach = 0,
		Run = function(hz)
			while true do
				task.wait(dropRng:NextNumber(1.2, 2.6))
				local near = playersNear(spot, 90, 60)
				if #near > 0 then
					-- aim at a player standing in the field when there is one, else a random spot
					local inField = playersNear(spot, AREA + 4, 12)
					local target
					if #inField > 0 then
						local pp = inField[dropRng:NextInteger(1, #inField)].Root.Position
						target = Vector3.new(pp.X, env.Top, pp.Z) + Vector3.new(dropRng:NextNumber(-2.5, 2.5), 0, dropRng:NextNumber(-2.5, 2.5))
					else
						local a, d = dropRng:NextNumber(0, TAU), dropRng:NextNumber(0, AREA)
						target = spot + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
					end
					shadow.Size = Vector3.new(0.1, 1, 1)
					shadow.CFrame = discCF(target, 0.12, 0.1)
					shadow.Transparency = 0.6
					TweenService:Create(shadow, TweenInfo.new(WARN, Enum.EasingStyle.Linear), { Size = Vector3.new(0.1, HIT_R * 2, HIT_R * 2), Transparency = 0.2 }):Play()
					icicle.CFrame = CFrame.new(target.X, cloudY - 3, target.Z) * CFrame.Angles(0, math.rad(45), 0)
					icicle.Transparency = 0.1
					task.wait(WARN - 0.35)
					TweenService:Create(icicle, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ CFrame = CFrame.new(target.X, env.Top + 3.5, target.Z) * CFrame.Angles(0, math.rad(45), 0) }):Play()
					task.wait(0.35)
					for _, e in ipairs(playersNear(target, HIT_R, 8)) do
						if tryHit(e.Player, hz, 1.5) then
							knock(e.Player, awayDir(target, e.Root.Position), "FallingIcicle")
						end
					end
					icicle.Transparency = 1
					shadow.Transparency = 1
					for k = 1, 4 do
						local a = k * TAU / 4 + dropRng:NextNumber(-0.4, 0.4)
						local shard = mk(m, Vector3.new(0.8, 1.6, 0.8), CFrame.new(target + Vector3.new(0, 1, 0)), ice, { Material = M.Ice })
						TweenService:Create(shard, TweenInfo.new(0.5), {
							CFrame = CFrame.new(target + Vector3.new(math.cos(a) * 4, 0.4, math.sin(a) * 4)) * CFrame.Angles(1, a, 0.5),
							Transparency = 1,
						}):Play()
						Debris:AddItem(shard, 0.6)
					end
				end
			end
		end,
	})
end

function Builders.VoidPit(env, seg)
	local r = env.Rng:NextNumber(6.5, 9)
	local spot = findSpot(env, seg, r, 4, 35)
	if not spot then
		return
	end
	local m = newModel(env, "VoidPit")
	local glow = C(170, 110, 255)
	disc(m, spot, r + 1, 0.1, 0.2, glow, { Material = M.Neon })
	local root = disc(m, spot, r, 0.16, 0.2, C(5, 0, 15))
	disc(m, spot, r * 0.45, 0.18, 0.05, C(60, 20, 120), { Material = M.Neon, Transparency = 0.6 })
	local arms = {}
	for _ = 1, 3 do
		table.insert(arms, mk(m, Vector3.new(r * 0.85, 0.06, 0.45), CFrame.new(spot), glow, { Material = M.Neon, Transparency = 0.3 }))
	end
	emitter(root, {
		Color = ColorSequence.new(glow, C(40, 10, 90)), LightEmission = 0.8, Size = NumberSequence.new(0.4, 0),
		Lifetime = NumberRange.new(1.5, 2.5), Rate = 10, Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(15, 15), EmissionDirection = Enum.NormalId.Right,
	})
	tag(root, "VoidPit", env.Zone, r)
	register(env, {
		Kind = "VoidPit", Center = spot, Radius = r,
		Step = function(_, now, push)
			for i, arm in ipairs(arms) do
				local a = -now * 1.4 + i * TAU / 3
				push(arm, CFrame.new(spot + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(r * 0.4, 0, 0) * CFrame.Angles(0, 0.6, 0))
			end
		end,
		Test = function(hz, player, pos)
			if inCircle(hz, pos, r * 0.8, 6) and tryHit(player, hz, 3) then
				local zone = hz.Zone
				task.spawn(call, "VoidFall", player, zone)
			end
		end,
	})
end

function Builders.MeteorStrike(env)
	local RADIUS, WARN = 9, 1.5
	local b = env.Bounds
	local m = newModel(env, "MeteorStrike")
	local root = mk(m, Vector3.one, CFrame.new((b.MinX + b.MaxX) / 2, env.Top + 80, 0), Color3.new(1, 0, 0), { Transparency = 1 })
	tag(root, "MeteorStrike", env.Zone, RADIUS)
	local rng = Random.new(env.Zone * 4243)
	local zone = env.Zone

	local function strike(hz, spot: Vector3)
		local warnDisc = disc(m, spot, RADIUS, 0.15, 0.1, C(255, 40, 40), { Material = M.Neon, Transparency = 0.6 })
		local fill = disc(m, spot, 0.1, 0.18, 0.1, C(255, 120, 60), { Material = M.Neon, Transparency = 0.35 })
		TweenService:Create(fill, TweenInfo.new(WARN, Enum.EasingStyle.Linear), { Size = Vector3.new(0.1, RADIUS * 2, RADIUS * 2) }):Play()
		TweenService:Create(warnDisc, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.25 }):Play()
		local from = spot + Vector3.new(-45, 140, 30)
		local rock = mk(m, Vector3.one * 6, CFrame.new(from), C(70, 45, 40), { Shape = BALL, Material = M.Basalt })
		local aura = mk(m, Vector3.one * 8, CFrame.new(from), C(255, 130, 40), { Shape = BALL, Material = M.Neon, Transparency = 0.5 })
		local flames = Instance.new("Fire")
		flames.Size = 9
		flames.Heat = 15
		flames.Color = C(255, 120, 40)
		flames.Parent = rock
		Debris:AddItem(warnDisc, WARN + 0.1)
		Debris:AddItem(fill, WARN + 0.1)
		Debris:AddItem(rock, WARN + 0.1)
		Debris:AddItem(aura, WARN + 0.1)
		task.wait(WARN - 0.7)
		local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(rock, info, { CFrame = CFrame.new(spot + Vector3.new(0, 3, 0)) }):Play()
		TweenService:Create(aura, info, { CFrame = CFrame.new(spot + Vector3.new(0, 3, 0)) }):Play()
		task.wait(0.7)
		for _, e in ipairs(playersNear(spot, RADIUS, 12)) do
			if tryHit(e.Player, hz, 1.5) then
				local dir = awayDir(spot, e.Root.Position)
				knock(e.Player, dir, "MeteorStrike", dir * 35 + UP * 40)
			end
		end
		local flash = disc(m, spot, RADIUS * 0.5, 0.25, 0.2, C(255, 170, 60), { Material = M.Neon, Transparency = 0.1 })
		TweenService:Create(flash, TweenInfo.new(0.45), { Size = Vector3.new(0.2, RADIUS * 3, RADIUS * 3), Transparency = 1 }):Play()
		Debris:AddItem(flash, 0.5)
		local scorch = disc(m, spot, RADIUS * 0.7, 0.13, 0.05, C(25, 20, 30), { Transparency = 0.2 })
		TweenService:Create(scorch, TweenInfo.new(3.5), { Transparency = 1 }):Play()
		Debris:AddItem(scorch, 3.6)
	end

	register(env, {
		Kind = "MeteorStrike", Center = root.Position, Radius = RADIUS, Reach = 0,
		Run = function(hz)
			while true do
				task.wait(rng:NextNumber(4.5, 7))
				local inZone = {}
				for _, p in ipairs(Players:GetPlayers()) do
					local r = rootOf(p)
					if r and zoneOfX(r.Position.X) == zone and r.Position.Y < env.Top + 40 then
						table.insert(inZone, r)
					end
				end
				if #inZone > 0 then
					local pp = inZone[rng:NextInteger(1, #inZone)].Position
					local a, d = rng:NextNumber(0, TAU), rng:NextNumber(0, 8)
					local spot = Vector3.new(
						math.clamp(pp.X + math.cos(a) * d, b.MinX + 6, b.MaxX - 6),
						env.Top,
						math.clamp(pp.Z + math.sin(a) * d, -env.Edge + 4, env.Edge - 4)
					)
					task.spawn(strike, hz, spot)
				end
			end
		end,
	})
end

-- ===== Public API =====

function HazardBuilder.Build(zoneModel: Model, biome, bounds, avoid: { Vector3 }, folder: Folder)
	local zone = biome.Index
	-- rebuilding a zone replaces its hazards
	if byZone[zone] then
		for i = #hazards, 1, -1 do
			if hazards[i].Zone == zone then
				table.remove(hazards, i)
			end
		end
		byZone[zone] = nil
	end
	local env = {
		Folder = folder,
		Biome = biome,
		Bounds = bounds,
		Avoid = avoid or {},
		Rng = Random.new(biome.Index * 7919 + 17),
		Zone = zone,
		Top = bounds.TopY,
		Edge = math.min(math.abs(bounds.MinZ), math.abs(bounds.MaxZ)) - 2,
		Theme = biome.Theme,
		Taken = {},
		Model = zoneModel,
	}

	-- interleave kinds along the lane so each zone alternates its hazards
	local remaining, order = {}, {}
	local total = 0
	for _, kind in ipairs(biome.Hazards or {}) do
		if Builders[kind] then
			if kind == "MeteorStrike" then
				Builders.MeteorStrike(env)
			elseif remaining[kind] == nil then
				remaining[kind] = COUNTS[kind] or 4
				total += remaining[kind]
			end
		else
			warn("[HazardBuilder] unknown hazard type", kind)
		end
	end
	while #order < total do
		for _, kind in ipairs(biome.Hazards) do
			if (remaining[kind] or 0) > 0 then
				remaining[kind] -= 1
				table.insert(order, kind)
			end
		end
	end

	local x0, x1 = bounds.MinX + GATE_CLEAR, bounds.MaxX - END_CLEAR
	local w = (x1 - x0) / math.max(total, 1)
	for i, kind in ipairs(order) do
		local seg = { A = x0 + (i - 1) * w, B = x0 + i * w, Index = i }
		local ok, err = pcall(Builders[kind], env, seg)
		if not ok then
			warn("[HazardBuilder]", kind, "failed in zone", zone, err)
		end
	end
	if started then
		for _, hz in ipairs(byZone[zone] or {}) do
			if hz.Run then
				task.spawn(hz.Run, hz)
			end
		end
	end
end

local function playerTick(player: Player, now: number)
	local st = stateOf(player)
	local root = rootOf(player)
	if not root then
		clearEffects(player)
		return
	end
	local pos = root.Position
	local zi = zoneOfX(pos.X)
	local slows = {}
	local slippery = false
	for z = zi - 1, zi + 1 do
		local list = byZone[z]
		if list then
			for _, hz in ipairs(list) do
				local reach = hz.Reach + 4
				if horizDist2(pos, hz.Center) <= reach * reach then
					if hz.SlowMult then
						if inCircle(hz, pos, hz.Radius, 6) then
							local cur = slows[hz.SlowKey]
							slows[hz.SlowKey] = cur and math.min(cur, hz.SlowMult) or hz.SlowMult
						end
					elseif hz.Slippery then
						if inCircle(hz, pos, hz.Radius, 6) then
							slippery = true
						end
					elseif hz.Test then
						hz.Test(hz, player, pos, now)
					end
				end
			end
		end
	end
	for key, mult in pairs(slows) do
		if st.Slows[key] ~= mult then
			call("SetSlow", player, key, mult)
		end
	end
	for key in pairs(st.Slows) do
		if slows[key] == nil then
			call("SetSlow", player, key, nil)
		end
	end
	st.Slows = slows
	if slippery ~= st.Slippery then
		st.Slippery = slippery
		call("SetSlippery", player, slippery)
	end
end

function HazardBuilder.Start(context)
	if started then
		return
	end
	started = true
	ctx = context or {}

	for _, hz in ipairs(hazards) do
		if hz.Run then
			task.spawn(hz.Run, hz)
		end
	end

	local function hookCharacter(player: Player)
		player.CharacterRemoving:Connect(function()
			clearEffects(player)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		hookCharacter(p)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	Players.PlayerRemoving:Connect(function(player)
		clearEffects(player)
		states[player] = nil
	end)

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local function push(p: BasePart, cf: CFrame)
		table.insert(parts, p)
		table.insert(cframes, cf)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, hz in ipairs(hazards) do
			if hz.Step then
				hz.Step(hz, now, push)
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			table.clear(parts)
			table.clear(cframes)
		end

		acc += dt
		if acc < TICK then
			return
		end
		acc = 0
		for _, hz in ipairs(hazards) do
			if hz.Tick then
				hz.Tick(hz, now)
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(playerTick, player, now)
			if not ok then
				warn("[HazardBuilder] tick failed for", player.Name, err)
			end
		end
	end)
end

return HazardBuilder

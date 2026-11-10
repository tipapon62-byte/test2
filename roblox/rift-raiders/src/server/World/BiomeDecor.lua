-- BiomeDecor: seeded, procedural scenery for one Rift Run zone (chunky-cartoon style).
-- Everything lives in zoneModel.RR_Decor and is rebuilt identically from the biome seed.
-- Props never enter the running lane (|Z| < LANE), the gate area or the avoid radii.

local BiomeDecor = {}

local LANE = 14 -- the clear running lane is |Z| <= 10; props keep a few studs more
local GATE_CLEAR = 32
local END_CLEAR = 10
local AVOID_R = 18
local MAX_LIGHTS = 16

local BUDGETS = {
	RiftLab = 150,
	Mosswood = 900,
	GlimmerLake = 150,
	Sunscorch = 900,
	Vinewild = 500,
	Emberpeak = 900,
	Frostveil = 900,
	AstralRuins = 700,
}

local FLOOR_MATERIAL = {
	Mosswood = Enum.Material.Grass,
	Sunscorch = Enum.Material.Sand,
	Emberpeak = Enum.Material.Basalt,
	Frostveil = Enum.Material.Snow,
}

local C = Color3.fromRGB
local rad = math.rad
local TAU = math.pi * 2
local HALF_PI = math.pi / 2
local M = Enum.Material
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- ===== Primitive helpers =====

local function mk(c, parent: Instance, size: Vector3, cf: CFrame, color: Color3, opts: any?): BasePart
	local o = opts or {}
	local p: BasePart
	if o.Wedge then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if o.Shape then
			part.Shape = o.Shape
		end
		p = part
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = o.Material or M.SmoothPlastic
	p.Anchored = true
	local solid = o.Solid == true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.CastShadow = solid or o.Shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.Transparency then
		p.Transparency = o.Transparency
	end
	if o.Reflectance then
		p.Reflectance = o.Reflectance
	end
	p.Parent = parent
	c.Count += 1
	return p
end

local function ellip(c, parent, cf: CFrame, size: Vector3, color: Color3, opts: any?): BasePart
	local p = mk(c, parent, size, cf, color, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function ball(c, parent, pos: Vector3, d: number, color: Color3, opts: any?): BasePart
	local o = table.clone(opts or {})
	o.Shape = BALL
	return mk(c, parent, Vector3.one * d, CFrame.new(pos), color, o)
end

-- Vertical cylinder standing on `base` (optionally tilted); returns the part and its top point.
local function vcyl(c, parent, base: Vector3, h: number, d: number, color: Color3, opts: any?, tilt: CFrame?): (BasePart, Vector3)
	local o = table.clone(opts or {})
	o.Shape = CYL
	local root = CFrame.new(base) * (tilt or CFrame.identity)
	local p = mk(c, parent, Vector3.new(h, d, d), root * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, HALF_PI), color, o)
	return p, (root * CFrame.new(0, h, 0)).Position
end

-- Horizontal cylinder whose axis follows cf's X axis.
local function hcyl(c, parent, cf: CFrame, len: number, d: number, color: Color3, opts: any?): BasePart
	local o = table.clone(opts or {})
	o.Shape = CYL
	return mk(c, parent, Vector3.new(len, d, d), cf, color, o)
end

-- Flat disc lying on the ground; `y` is the disc's top height above the floor.
local function disc(c, parent, pos: Vector3, r: number, y: number, thick: number, color: Color3, opts: any?): BasePart
	local o = table.clone(opts or {})
	o.Shape = CYL
	return mk(c, parent, Vector3.new(thick, r * 2, r * 2),
		CFrame.new(pos.X, c.Top + y - thick / 2, pos.Z) * CFrame.Angles(0, 0, HALF_PI), color, o)
end

local function light(c, part: BasePart, color: Color3, range: number, brightness: number?)
	if c.Lights >= MAX_LIGHTS then
		return
	end
	c.Lights += 1
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = part
end

local function pick(c, list: { any }): any
	return list[c.Rng:NextInteger(1, #list)]
end

local function jitter(c, color: Color3, amount: number): Color3
	local k = c.Rng:NextNumber(-amount, amount)
	return k >= 0 and color:Lerp(WHITE, k) or color:Lerp(BLACK, -k)
end

local function yaw(c): CFrame
	return CFrame.Angles(0, c.Rng:NextNumber(0, TAU), 0)
end

local function model(c, kind: string): Model
	local group = c.Groups[kind]
	if not group then
		group = Instance.new("Folder")
		group.Name = kind
		group.Parent = c.Folder
		c.Groups[kind] = group
	end
	local m = Instance.new("Model")
	m.Name = kind
	m.Parent = group
	return m
end

-- ===== Placement =====

local function fits(c, x: number, z: number, r: number, overlap: boolean?, ignoreLane: boolean?): boolean
	local b = c.B
	if not ignoreLane and math.abs(z) < LANE + r then
		return false
	end
	if math.abs(z) > c.Edge - r * 0.4 then
		return false
	end
	if x - r < b.MinX + GATE_CLEAR or x + r > b.MaxX - END_CLEAR then
		return false
	end
	for _, a in ipairs(c.Avoid) do
		local dx, dz = a.X - x, a.Z - z
		local m = AVOID_R + r
		if dx * dx + dz * dz < m * m then
			return false
		end
	end
	if not overlap then
		for _, q in ipairs(c.Placed) do
			local dx, dz = q.X - x, q.Z - z
			local m = q.R + r
			if dx * dx + dz * dz < m * m then
				return false
			end
		end
	end
	return true
end

local function claim(c, x: number, z: number, r: number)
	table.insert(c.Placed, { X = x, Z = z, R = r })
end

-- opts: Wall (bias toward side walls), Near/Spread (cluster), MinZ/MaxZ (|Z| band), Overlap, Side
local function sample(c, r: number, opts: any?): Vector3?
	local o = opts or {}
	local rng = c.Rng
	for _ = 1, 40 do
		local x, z
		if o.Near then
			local a = rng:NextNumber(0, TAU)
			local d = rng:NextNumber(0, o.Spread or 12)
			x = o.Near.X + math.cos(a) * d
			z = o.Near.Z + math.sin(a) * d
		else
			x = rng:NextNumber(c.B.MinX + GATE_CLEAR + r, math.max(c.B.MinX + GATE_CLEAR + r + 1, c.B.MaxX - END_CLEAR - r))
			local zmin = math.max(LANE + r, o.MinZ or 0)
			local zmax = math.min(c.Edge - r * 0.4, o.MaxZ or math.huge)
			if zmax <= zmin then
				return nil
			end
			local t = rng:NextNumber()
			if o.Wall then
				t = math.sqrt(t) -- linear density increase toward the walls
			end
			local side = o.Side or (rng:NextNumber() < 0.5 and -1 or 1)
			z = (zmin + (zmax - zmin) * t) * side
		end
		if fits(c, x, z, r, o.Overlap) then
			if not o.Overlap then
				claim(c, x, z, r)
			end
			return Vector3.new(x, c.Top, z)
		end
	end
	return nil
end

local function full(c, reserve: number?): boolean
	return c.Count >= c.Budget - (reserve or 14)
end

local function scatter(c, n: number, r: number, fn, opts: any?)
	local o = opts or {}
	for _ = 1, n do
		if full(c, o.Reserve) then
			return
		end
		local s = c.Rng:NextNumber(o.MinS or 0.8, o.MaxS or 1.25)
		local pos = sample(c, r * s, o)
		if pos then
			fn(c, pos, s)
		end
	end
end

local function cluster(c, groups: number, per: number, spread: number, r: number, fn, opts: any?)
	local o = opts or {}
	for _ = 1, groups do
		if full(c, o.Reserve) then
			return
		end
		local centre = sample(c, spread * 0.5, { Wall = o.Wall, Overlap = true, MinZ = o.MinZ, MaxZ = o.MaxZ })
		if centre then
			local n = c.Rng:NextInteger(math.max(1, per - 1), per + 1)
			for _ = 1, n do
				if full(c, o.Reserve) then
					return
				end
				local s = c.Rng:NextNumber(o.MinS or 0.75, o.MaxS or 1.3)
				local pos = sample(c, r * s, { Near = centre, Spread = spread, Overlap = o.Overlap })
				if pos then
					fn(c, pos, s)
				end
			end
		end
	end
end

-- Dense line of props hugging both side walls.
local function border(c, step: number, r: number, fns: { any }, depth: number?)
	local rng = c.Rng
	for side = -1, 1, 2 do
		local x = c.B.MinX + GATE_CLEAR + r
		while x < c.B.MaxX - END_CLEAR - r do
			if full(c) then
				return
			end
			local s = rng:NextNumber(0.85, 1.35)
			local px = x + rng:NextNumber(-step * 0.3, step * 0.3)
			local z = side * (c.Edge - r * s - rng:NextNumber(0, depth or 14))
			if fits(c, px, z, r * s) then
				claim(c, px, z, r * s)
				fns[rng:NextInteger(1, #fns)](c, Vector3.new(px, c.Top, z), s)
			end
			x += step * rng:NextNumber(0.8, 1.2)
		end
	end
end

-- Landmark spot: preferred position first, then jittered retries on alternating sides.
local function landmarkSpot(c, xFrac: number, zAbs: number, r: number, side: number): Vector3?
	local b = c.B
	for i = 0, 40 do
		local x = b.MinX + (b.MaxX - b.MinX) * xFrac
		if i > 0 then
			x += c.Rng:NextNumber(-170, 170)
		end
		local z = math.min(zAbs, c.Edge - r * 0.4) * (i % 2 == 0 and side or -side)
		if fits(c, x, z, r) then
			claim(c, x, z, r)
			return Vector3.new(x, c.Top, z)
		end
	end
	return nil
end

-- Long half-buried cylinder: a smooth collidable mound (dunes, snow drifts).
local function mound(c, parent, pos: Vector3, len: number, radius: number, height: number, color: Color3, material, yawAngle: number)
	hcyl(c, parent, CFrame.new(pos.X, c.Top + height - radius, pos.Z) * CFrame.Angles(0, yawAngle, 0),
		len, radius * 2, color, { Solid = true, Material = material, Shadow = true })
end

local function wallMounds(c, kind: string, colors: { Color3 }, material, count: number)
	local rng = c.Rng
	local b = c.B
	for side = -1, 1, 2 do
		local x = b.MinX + GATE_CLEAR + 30
		for _ = 1, count do
			if x > b.MaxX - END_CLEAR - 30 then
				break
			end
			local radius = rng:NextNumber(22, 40)
			local height = rng:NextNumber(5, 11)
			local half = math.sqrt(radius * radius - (radius - height) ^ 2)
			local len = rng:NextNumber(45, 85)
			local z = side * (c.Edge - half * rng:NextNumber(0.3, 0.8))
			if math.abs(z) - half > LANE + 2 then
				local ok = true
				for _, a in ipairs(c.Avoid) do
					if math.abs(a.X - x) < len / 2 + AVOID_R and math.abs(a.Z - z) < half + AVOID_R then
						ok = false
						break
					end
				end
				if ok then
					mound(c, model(c, kind), Vector3.new(x, c.Top, z), len, radius, height, pick(c, colors), material, rng:NextNumber(-0.12, 0.12))
					for k = -1, 1 do
						claim(c, x + k * len / 3, z, half * 0.8)
					end
				end
			end
			x += len * rng:NextNumber(0.7, 1.1)
		end
	end
end

-- Neon motes hovering anywhere above the zone (they may float over the lane: no collision).
local function motes(c, n: number, colors: { Color3 }, minY: number, maxY: number, size: number)
	local rng = c.Rng
	local m = model(c, "Motes")
	for _ = 1, n do
		if full(c, 2) then
			return
		end
		local x = rng:NextNumber(c.B.MinX + GATE_CLEAR, c.B.MaxX - END_CLEAR)
		local z = rng:NextNumber(-c.Edge + 4, c.Edge - 4)
		ball(c, m, Vector3.new(x, c.Top + rng:NextNumber(minY, maxY), z), size * rng:NextNumber(0.6, 1.4), pick(c, colors),
			{ Material = M.Neon, Transparency = rng:NextNumber(0, 0.35) })
	end
end

-- ===== Shared props =====

local function rock(c, pos: Vector3, s: number, colors: { Color3 }, capColor: Color3?)
	local m = model(c, "Rock")
	local rng = c.Rng
	local size = Vector3.new(7, 4.5, 5.5) * s * rng:NextNumber(0.8, 1.2)
	local cf = CFrame.new(pos + Vector3.new(0, size.Y * 0.35, 0)) * yaw(c) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	local main = mk(c, m, size, cf, pick(c, colors), { Solid = s > 0.6 })
	mk(c, m, size * 0.55, cf * CFrame.new(size.X * 0.45, -size.Y * 0.15, size.Z * 0.2) * CFrame.Angles(0.3, 0.6, 0.2), pick(c, colors), { Solid = s > 0.6 })
	if capColor then
		ellip(c, m, cf * CFrame.new(0, size.Y / 2, 0), Vector3.new(size.X * 0.85, size.Y * 0.35, size.Z * 0.8), capColor)
	end
	return main
end

local function bush(c, pos: Vector3, s: number, greens: { Color3 })
	local m = model(c, "Bush")
	local g = pick(c, greens)
	ball(c, m, pos + Vector3.new(0, 1.2 * s, 0), 5 * s, g)
	ball(c, m, pos + Vector3.new(2.2 * s, 0.6 * s, 1 * s), 3.8 * s, jitter(c, g, 0.12))
	if c.Rng:NextNumber() < 0.6 then
		ball(c, m, pos + Vector3.new(-1.8 * s, 0.5 * s, -1.4 * s), 3.4 * s, jitter(c, g, 0.12))
	end
end

-- ===== Biome 1: Rift Lab (light extras) =====

local function riftCrystals(c, pos: Vector3, s: number)
	local m = model(c, "RiftCrystal")
	local rng = c.Rng
	local base = mk(c, m, Vector3.new(5, 1.4, 5) * s, CFrame.new(pos + Vector3.new(0, 0.5 * s, 0)) * yaw(c), C(60, 70, 85))
	local cols = { C(90, 255, 200), C(255, 90, 230), C(120, 200, 255) }
	local col = pick(c, cols)
	for i = 1, 3 do
		local h = rng:NextNumber(3, 7) * s * (i == 1 and 1.4 or 1)
		local cf = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.2, 1.2) * s, h / 2, rng:NextNumber(-1.2, 1.2) * s))
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), rng:NextNumber(-0.4, 0.4))
		mk(c, m, Vector3.new(1.3 * s, h, 1.3 * s), cf * CFrame.Angles(0, rad(45), 0), col, { Material = M.Neon, Transparency = 0.15 })
	end
	light(c, base, col, 14, 1.2)
end

local function signPost(c, pos: Vector3, s: number)
	local m = model(c, "SignPost")
	local face = CFrame.lookAt(pos, Vector3.new(pos.X, pos.Y, 0)) -- board faces the lane
	vcyl(c, m, pos, 7 * s, 0.6 * s, C(150, 160, 175), { Material = M.Metal, Solid = true })
	local board = face * CFrame.new(0, 7 * s, 0)
	mk(c, m, Vector3.new(6, 2.6, 0.4) * s, board, C(35, 45, 60))
	mk(c, m, Vector3.new(5.6, 0.35, 0.45) * s, board * CFrame.new(0, -0.8 * s, 0), C(90, 255, 200), { Material = M.Neon })
	-- arrow pointing down the Rift Run (+X)
	local toward = face.RightVector.X >= 0 and 1 or -1
	for k = -1, 1, 2 do -- ">" chevron made of two bars
		mk(c, m, Vector3.new(1.3, 0.3, 0.2) * s, board * CFrame.new(toward * 1.6 * s, (0.3 + k * 0.35) * s, -0.25 * s) * CFrame.Angles(0, 0, -k * toward * rad(45)),
			C(255, 220, 90), { Material = M.Neon })
	end
end

local function labCone(c, pos: Vector3, s: number)
	local m = model(c, "Cone")
	vcyl(c, m, pos, 2.4 * s, 1.4 * s, C(255, 140, 40))
	vcyl(c, m, pos + Vector3.new(0, 1.1 * s, 0), 0.5 * s, 1.5 * s, WHITE)
end

local function buildRiftLab(c)
	cluster(c, 7, 2, 18, 3, riftCrystals, { Wall = true })
	scatter(c, 6, 2, signPost, { MaxZ = 22, MinS = 0.9, MaxS = 1.1 })
	cluster(c, 4, 3, 8, 1, labCone, { MaxZ = 30, Overlap = true })
	motes(c, 40, { C(90, 255, 200), C(170, 220, 255), C(255, 130, 240) }, 3, 24, 0.5)
end

-- ===== Biome 2: Mosswood (forest) =====

local GREENS = { C(80, 160, 60), C(100, 180, 70), C(60, 135, 55), C(130, 195, 80), C(70, 150, 90) }
local BARK = { C(110, 75, 45), C(95, 65, 40), C(125, 85, 55) }
local MOSS_ROCK = { C(115, 120, 110), C(100, 105, 100), C(130, 130, 120) }
local FLOWERS = { C(255, 120, 170), C(255, 220, 80), C(250, 250, 255), C(190, 120, 255), C(255, 150, 80) }

local function roundTree(c, pos: Vector3, s: number)
	local m = model(c, "Tree")
	local rng = c.Rng
	local tilt = CFrame.Angles(rng:NextNumber(-0.07, 0.07), 0, rng:NextNumber(-0.07, 0.07))
	local _, top = vcyl(c, m, pos - Vector3.new(0, 0.5, 0), 11 * s * rng:NextNumber(0.85, 1.2), 2.4 * s, pick(c, BARK), { Solid = true, Material = M.Wood }, tilt)
	local g = pick(c, GREENS)
	local y = yaw(c)
	ball(c, m, top + Vector3.new(0, 2.5 * s, 0), 11 * s, g, { Shadow = true })
	ball(c, m, top + y:VectorToWorldSpace(Vector3.new(4 * s, 0, 1.5 * s)), 8 * s, jitter(c, g, 0.1), { Shadow = true })
	ball(c, m, top + y:VectorToWorldSpace(Vector3.new(-3.5 * s, 0.8 * s, -2.5 * s)), 7.5 * s, jitter(c, g, 0.12), { Shadow = true })
end

local function pineTree(c, pos: Vector3, s: number)
	local m = model(c, "Pine")
	local rng = c.Rng
	local _, top = vcyl(c, m, pos - Vector3.new(0, 0.5, 0), 6 * s, 1.8 * s, pick(c, BARK), { Solid = true, Material = M.Wood })
	local g = jitter(c, C(45, 110, 60), 0.1)
	local tiers = rng:NextInteger(4, 5)
	for i = 1, tiers do
		local d = (12 - (i - 1) * (9 / tiers)) * s
		vcyl(c, m, top + Vector3.new(0, (i - 1) * 3 * s - 1.5 * s, 0), 3 * s, d, i % 2 == 0 and jitter(c, g, 0.08) or g, { Shadow = true })
	end
	ball(c, m, top + Vector3.new(0, tiers * 3 * s - 0.5 * s, 0), 2.4 * s, g)
end

local function birchTree(c, pos: Vector3, s: number)
	local m = model(c, "Birch")
	local rng = c.Rng
	local tilt = CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(-0.05, 0.05))
	local h = 19 * s * rng:NextNumber(0.85, 1.15)
	local trunk, top = vcyl(c, m, pos - Vector3.new(0, 0.5, 0), h, 1.4 * s, C(235, 230, 215), { Solid = true }, tilt)
	for _ = 1, 2 do
		local ty = rng:NextNumber(0.2, 0.7) * h
		mk(c, m, Vector3.new(0.5 * s, 0.4 * s, 1.5 * s), CFrame.new(pos) * tilt * CFrame.new(0, ty, 0) * yaw(c) * CFrame.new(0.55 * s, 0, 0), C(50, 45, 45))
	end
	local g = pick(c, { C(170, 210, 70), C(200, 220, 90), C(140, 200, 80) })
	ellip(c, m, CFrame.new(top + Vector3.new(0, 1.5 * s, 0)), Vector3.new(7, 10, 7) * s, g, { Shadow = true })
	ellip(c, m, CFrame.new(top + Vector3.new(2.2 * s, -2 * s, 1 * s)), Vector3.new(5, 7, 5) * s, jitter(c, g, 0.1), { Shadow = true })
	return trunk
end

local function mushroom(c, parent, pos: Vector3, s: number, glow: boolean)
	local _, top = vcyl(c, parent, pos, 2.6 * s, 0.9 * s, C(240, 230, 210))
	local col = glow and pick(c, { C(90, 240, 255), C(200, 120, 255), C(120, 255, 170) }) or pick(c, { C(220, 60, 60), C(235, 120, 50) })
	local cap = ellip(c, parent, CFrame.new(top), Vector3.new(4, 1.8, 4) * s, col, { Material = glow and M.Neon or M.SmoothPlastic })
	if glow then
		light(c, cap, col, 10, 1)
	else
		ball(c, parent, top + Vector3.new(0.9 * s, 0.6 * s, 0.4 * s), 0.7 * s, WHITE)
		ball(c, parent, top + Vector3.new(-0.7 * s, 0.7 * s, -0.6 * s), 0.6 * s, WHITE)
	end
end

local function mushroomPatch(c, pos: Vector3, s: number)
	local m = model(c, "Mushrooms")
	local glow = c.Rng:NextNumber() < 0.45
	for _ = 1, c.Rng:NextInteger(2, 4) do
		local off = Vector3.new(c.Rng:NextNumber(-2.5, 2.5), 0, c.Rng:NextNumber(-2.5, 2.5)) * s
		mushroom(c, m, pos + off, s * c.Rng:NextNumber(0.6, 1.3), glow)
	end
end

local function fern(c, pos: Vector3, s: number)
	local m = model(c, "Fern")
	local g = pick(c, GREENS)
	local base = CFrame.new(pos) * yaw(c)
	for i = 1, 4 do
		local cf = base * CFrame.Angles(0, i * TAU / 4, 0) * CFrame.Angles(rad(35), 0, 0) * CFrame.new(0, 0, -2.2 * s)
		ellip(c, m, cf, Vector3.new(1.3 * s, 0.25 * s, 5 * s), jitter(c, g, 0.1))
	end
end

local function fallenLog(c, pos: Vector3, s: number)
	local m = model(c, "FallenLog")
	local cf = CFrame.new(pos + Vector3.new(0, 1.2 * s, 0)) * CFrame.Angles(0, c.Rng:NextNumber(-0.5, 0.5), 0)
	hcyl(c, m, cf, 14 * s, 2.8 * s, pick(c, BARK), { Solid = true, Material = M.Wood })
	hcyl(c, m, cf * CFrame.new(7 * s, 0, 0), 0.3, 2.4 * s, C(200, 160, 110))
	ellip(c, m, cf * CFrame.new(-2 * s, 1.2 * s, 0), Vector3.new(7, 1, 2.4) * s, pick(c, GREENS))
	if c.Rng:NextNumber() < 0.5 then
		mushroom(c, m, (cf * CFrame.new(3 * s, 1.1 * s, 0.4 * s)).Position, 0.5 * s, true)
	end
end

local function flowerPatch(c, pos: Vector3, s: number)
	local m = model(c, "Flowers")
	local rng = c.Rng
	ellip(c, m, CFrame.new(pos + Vector3.new(0, 0.15, 0)), Vector3.new(6, 0.5, 5) * s, pick(c, GREENS))
	for _ = 1, rng:NextInteger(4, 7) do
		local off = Vector3.new(rng:NextNumber(-2.6, 2.6), 0.55, rng:NextNumber(-2.2, 2.2)) * s
		ball(c, m, pos + off, rng:NextNumber(0.7, 1.2) * s, pick(c, FLOWERS))
	end
end

local function fireflies(c, pos: Vector3, s: number)
	local m = model(c, "Fireflies")
	local rng = c.Rng
	local first
	for _ = 1, 5 do
		local p = ball(c, m, pos + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(2, 9), rng:NextNumber(-6, 6)) * s, 0.4, C(220, 255, 120), { Material = M.Neon })
		first = first or p
	end
	if first and rng:NextNumber() < 0.5 then
		light(c, first, C(220, 255, 120), 12, 0.8)
	end
end

local function grassTuft(c, pos: Vector3, s: number)
	local m = model(c, "Grass")
	local g = pick(c, GREENS)
	for i = 1, 3 do
		mk(c, m, Vector3.new(0.3, 2.4, 1.1) * s, CFrame.new(pos + Vector3.new(0, 1.1 * s, 0)) * CFrame.Angles(0, i * 2.1 + c.Rng:NextNumber(0, 0.5), 0) * CFrame.Angles(c.Rng:NextNumber(-0.3, 0.3), 0, 0), jitter(c, g, 0.1), { Wedge = true })
	end
end

local function hollowTree(c, pos: Vector3)
	local m = model(c, "HollowTree")
	local bark = C(105, 72, 45)
	local r, h = 9, 42
	local opening = pos.Z > 0 and 0 or math.pi -- the hollow faces the lane
	for i = 0, 9 do
		local a = i * TAU / 10
		local diff = math.abs(((a - opening + math.pi) % TAU) - math.pi)
		local segH = diff < 0.5 and h * 0.55 or h -- leave a doorway arch facing the path
		local cf = CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r)
		if diff < 0.5 then
			mk(c, m, Vector3.new(6.2, h - segH - 8, 3.2), cf * CFrame.new(0, segH + 8 + (h - segH - 8) / 2, 0), jitter(c, bark, 0.06), { Solid = true, Material = M.Wood })
		else
			mk(c, m, Vector3.new(6.2, segH, 3.2), cf * CFrame.new(0, segH / 2, 0), jitter(c, bark, 0.06), { Solid = true, Material = M.Wood })
		end
	end
	for i = 0, 4 do
		local a = i * TAU / 5 + 0.3
		mk(c, m, Vector3.new(3, 5, 9), CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, 2, -r - 4) * CFrame.Angles(rad(-25), 0, 0), bark, { Material = M.Wood, Wedge = true })
	end
	local top = pos + Vector3.new(0, h, 0)
	ball(c, m, top + Vector3.new(0, 6, 0), 34, C(70, 150, 60), { Shadow = true })
	ball(c, m, top + Vector3.new(14, 0, 6), 24, C(90, 170, 70), { Shadow = true })
	ball(c, m, top + Vector3.new(-12, 2, -8), 26, C(60, 135, 55), { Shadow = true })
	ball(c, m, top + Vector3.new(4, -2, -14), 20, C(110, 185, 75), { Shadow = true })
	disc(c, m, pos, r - 1, 0.2, 0.3, C(60, 45, 30))
	mushroom(c, m, pos + Vector3.new(2, 0, 1), 1.6, true)
	mushroom(c, m, pos + Vector3.new(-2.5, 0, -1.5), 1.1, true)
end

local function buildMosswood(c)
	local spot = landmarkSpot(c, 0.55, 120, 18, 1)
	if spot then
		hollowTree(c, spot)
	end
	border(c, 20, 6, { roundTree, pineTree, pineTree, birchTree }, 18)
	scatter(c, 26, 6, function(cc, p, s)
		local k = cc.Rng:NextInteger(1, 3)
		if k == 1 then roundTree(cc, p, s) elseif k == 2 then pineTree(cc, p, s) else birchTree(cc, p, s) end
	end, { Wall = true, MinZ = 45 })
	scatter(c, 18, 4, function(cc, p, s) rock(cc, p, s, MOSS_ROCK, C(90, 160, 70)) end, { MinS = 0.5, MaxS = 1.4 })
	scatter(c, 6, 7, fallenLog, { MinZ = 30 })
	cluster(c, 9, 2, 10, 2, mushroomPatch, {})
	scatter(c, 22, 3, function(cc, p, s) bush(cc, p, s, GREENS) end, { Wall = true })
	cluster(c, 6, 3, 14, 2, fern, { Overlap = true })
	scatter(c, 12, 3, flowerPatch, { Overlap = true })
	scatter(c, 10, 6, fireflies, { Overlap = true })
	scatter(c, 30, 1.5, grassTuft, { Overlap = true, MaxZ = 40 })
end

-- ===== Biome 3: Glimmer Lake (light extras) =====

local function lilyPad(c, pos: Vector3, s: number)
	local m = model(c, "LilyPad")
	disc(c, m, pos, 2 * s, 0.25, 0.2, pick(c, { C(70, 170, 90), C(90, 190, 100) }))
	if c.Rng:NextNumber() < 0.35 then
		ball(c, m, pos + Vector3.new(0.5 * s, 0.6, 0.3 * s), 0.9 * s, C(255, 150, 210), { Material = M.Neon })
	end
end

local function glowReeds(c, pos: Vector3, s: number)
	local m = model(c, "Reeds")
	local rng = c.Rng
	local col = pick(c, { C(120, 240, 255), C(140, 255, 200) })
	local first
	for _ = 1, 4 do
		local p = vcyl(c, m, pos + Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5)) * s, rng:NextNumber(4, 7.5) * s, 0.3 * s, col,
			{ Material = M.Neon, Transparency = 0.15 }, CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)))
		first = first or p
	end
	if first and rng:NextNumber() < 0.4 then
		light(c, first, col, 12, 1)
	end
end

local function glowShell(c, pos: Vector3, s: number)
	local m = model(c, "Shell")
	ellip(c, m, CFrame.new(pos + Vector3.new(0, 0.4 * s, 0)) * yaw(c), Vector3.new(1.6, 0.9, 1.3) * s, pick(c, { C(255, 140, 200), C(255, 210, 120), C(200, 160, 255) }), { Material = M.Neon })
end

local function buildGlimmerLake(c)
	cluster(c, 6, 3, 14, 2.5, lilyPad, { Overlap = true })
	cluster(c, 7, 2, 10, 2, glowReeds, { Wall = true, Overlap = true })
	scatter(c, 14, 1, glowShell, { Overlap = true, MaxZ = 60 })
	motes(c, 40, { C(120, 240, 255), C(200, 250, 255), C(160, 200, 255) }, 2, 30, 0.5)
end

-- ===== Biome 4: Sunscorch Dunes (desert) =====

local SAND = { C(225, 185, 115), C(232, 195, 125), C(215, 172, 105) }
local SANDSTONE = { C(215, 160, 100), C(200, 140, 85), C(225, 175, 115) }
local MESA = { C(195, 110, 70), C(180, 95, 60), C(210, 125, 80) }
local BONE = C(238, 232, 212)
local CACTUS = { C(90, 160, 75), C(75, 145, 70), C(105, 170, 80) }

local function cactus(c, pos: Vector3, s: number)
	local m = model(c, "Cactus")
	local rng = c.Rng
	local g = pick(c, CACTUS)
	local h = 10 * s * rng:NextNumber(0.85, 1.2)
	local _, top = vcyl(c, m, pos - Vector3.new(0, 0.5, 0), h, 2.3 * s, g, { Solid = true })
	ball(c, m, top, 2.3 * s, g)
	local base = rng:NextNumber(0, TAU)
	for i = 1, rng:NextInteger(1, 2) do
		local dir = CFrame.Angles(0, base + (i - 1) * math.pi, 0)
		local y = h * rng:NextNumber(0.35, 0.6)
		local elbow = CFrame.new(pos + Vector3.new(0, y, 0)) * dir
		hcyl(c, m, elbow * CFrame.new(1.8 * s, 0, 0), 3.2 * s, 1.6 * s, g)
		local _, armTop = vcyl(c, m, (elbow * CFrame.new(3.2 * s, 0, 0)).Position, rng:NextNumber(3, 4.5) * s, 1.6 * s, g)
		ball(c, m, armTop, 1.6 * s, g)
	end
	if rng:NextNumber() < 0.4 then
		ball(c, m, top + Vector3.new(0, 1.1 * s, 0), 1 * s, C(255, 110, 170), { Material = M.Neon })
	end
end

local function barrelCactus(c, pos: Vector3, s: number)
	local m = model(c, "BarrelCactus")
	ellip(c, m, CFrame.new(pos + Vector3.new(0, 1.1 * s, 0)), Vector3.new(3, 2.8, 3) * s, pick(c, CACTUS))
	ball(c, m, pos + Vector3.new(0, 2.5 * s, 0), 0.9 * s, pick(c, { C(255, 200, 70), C(255, 120, 160) }))
end

local function sandArch(c, pos: Vector3, s: number)
	local m = model(c, "Arch")
	local col = pick(c, SANDSTONE)
	local cf = CFrame.new(pos) * CFrame.Angles(0, c.Rng:NextNumber(-0.6, 0.6), 0)
	local h = 16 * s
	mk(c, m, Vector3.new(4 * s, h, 4.5 * s), cf * CFrame.new(-6.5 * s, h / 2, 0), col, { Solid = true })
	mk(c, m, Vector3.new(4 * s, h * 0.9, 4.5 * s), cf * CFrame.new(6.5 * s, h * 0.45, 0), jitter(c, col, 0.05), { Solid = true })
	mk(c, m, Vector3.new(18, 3.5, 5) * s, cf * CFrame.new(0, h + 1.2 * s, 0) * CFrame.Angles(0, 0, rad(-3)), jitter(c, col, 0.06), { Solid = true })
	mk(c, m, Vector3.new(4.5, 2.6, 2.6) * s, cf * CFrame.new(-3.2 * s, h - 1.3 * s, 0) * CFrame.Angles(0, -HALF_PI, 0) * CFrame.Angles(0, 0, 0), col, { Wedge = true })
	mk(c, m, Vector3.new(4.5, 2.6, 2.6) * s, cf * CFrame.new(3.2 * s, h - 1.3 * s, 0) * CFrame.Angles(0, HALF_PI, 0), col, { Wedge = true })
	mk(c, m, Vector3.new(3, 2, 3) * s, cf * CFrame.new(8 * s, 1, 3 * s) * CFrame.Angles(0.3, 0.7, 0.2), col)
end

local function bones(c, pos: Vector3, s: number)
	local m = model(c, "Bones")
	local cf = CFrame.new(pos + Vector3.new(0, 0.5 * s, 0)) * yaw(c)
	hcyl(c, m, cf, 13 * s, 0.9 * s, BONE)
	for i = -2, 1 do
		for side = -1, 1, 2 do
			mk(c, m, Vector3.new(0.6, 5, 0.6) * s, cf * CFrame.new(i * 2.2 * s + 1, 1.8 * s, side * 1.4 * s) * CFrame.Angles(side * rad(28), 0, 0), BONE)
		end
	end
	local skull = cf * CFrame.new(8 * s, 0.6 * s, 0)
	ellip(c, m, skull, Vector3.new(3.6, 2.4, 2.8) * s, BONE)
	mk(c, m, Vector3.new(0.8, 2.4, 0.5) * s, skull * CFrame.new(-0.5 * s, 1.6 * s, 1.2 * s) * CFrame.Angles(rad(-20), 0, 0), BONE, { Wedge = true })
	mk(c, m, Vector3.new(0.8, 2.4, 0.5) * s, skull * CFrame.new(-0.5 * s, 1.6 * s, -1.2 * s) * CFrame.Angles(rad(20), math.pi, 0), BONE, { Wedge = true })
end

local function mesa(c, pos: Vector3, s: number)
	local m = model(c, "Mesa")
	local rng = c.Rng
	local y = 0
	local w = 9 * s
	local base = yaw(c)
	for i = 1, rng:NextInteger(2, 3) do
		local h = rng:NextNumber(2.5, 4.5) * s
		mk(c, m, Vector3.new(w, h, w * rng:NextNumber(0.7, 1)), CFrame.new(pos + Vector3.new(rng:NextNumber(-0.6, 0.6), y + h / 2, rng:NextNumber(-0.6, 0.6))) * base * CFrame.Angles(0, i * 0.2, 0),
			MESA[(i - 1) % #MESA + 1], { Solid = true })
		y += h
		w *= rng:NextNumber(0.6, 0.8)
	end
end

local function pot(c, parent, pos: Vector3, s: number)
	local tilt = c.Rng:NextNumber() < 0.3 and CFrame.Angles(rad(75), c.Rng:NextNumber(0, TAU), 0) or CFrame.identity
	local col = pick(c, { C(190, 100, 60), C(170, 85, 50), C(205, 125, 75) })
	local cf = CFrame.new(pos + Vector3.new(0, 1.1 * s, 0)) * tilt
	mk(c, parent, Vector3.one * 2.2 * s, cf, col, { Shape = BALL })
	hcyl(c, parent, cf * CFrame.new(0, 1.2 * s, 0) * CFrame.Angles(0, 0, HALF_PI), 0.9 * s, 1.2 * s, jitter(c, col, 0.1))
	hcyl(c, parent, cf * CFrame.new(0, 1.65 * s, 0) * CFrame.Angles(0, 0, HALF_PI), 0.3 * s, 1.6 * s, C(240, 210, 150))
end

local function potGroup(c, pos: Vector3, s: number)
	local m = model(c, "Pots")
	for _ = 1, c.Rng:NextInteger(2, 3) do
		pot(c, m, pos + Vector3.new(c.Rng:NextNumber(-2.5, 2.5), 0, c.Rng:NextNumber(-2.5, 2.5)), s * c.Rng:NextNumber(0.7, 1.2))
	end
end

local function obelisk(c, pos: Vector3)
	local m = model(c, "Obelisk")
	local col = C(220, 170, 110)
	local glyph = C(255, 140, 60)
	local cf = CFrame.new(pos) * CFrame.Angles(0, rad(20), rad(4)) -- slightly leaning ruin
	mk(c, m, Vector3.new(16, 3, 16), CFrame.new(pos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, rad(20), 0), C(190, 140, 90), { Solid = true })
	mk(c, m, Vector3.new(9, 14, 9), cf * CFrame.new(0, 10, 0), col, { Solid = true })
	mk(c, m, Vector3.new(7.5, 12, 7.5), cf * CFrame.new(0, 23, 0), jitter(c, col, 0.04), { Solid = true })
	mk(c, m, Vector3.new(6, 9, 6), cf * CFrame.new(0, 33.5, 0), jitter(c, col, 0.04), { Solid = true })
	mk(c, m, Vector3.new(4.5, 4.5, 4.5), cf * CFrame.new(0, 39, 0) * CFrame.Angles(rad(45), 0, rad(45)), col)
	for i = 0, 3 do
		local face = cf * CFrame.Angles(0, i * HALF_PI, 0)
		mk(c, m, Vector3.new(1.2, 9, 0.3), face * CFrame.new(0, 12, -4.55), glyph, { Material = M.Neon })
		mk(c, m, Vector3.new(3.4, 0.8, 0.3), face * CFrame.new(0, 22, -3.8), glyph, { Material = M.Neon })
	end
	-- broken top piece lying in the sand
	mk(c, m, Vector3.new(5.5, 8, 5.5), CFrame.new(pos + Vector3.new(11, 2.4, 6)) * CFrame.Angles(rad(80), rad(30), 0), col, { Solid = true })
	for _ = 1, 4 do
		mk(c, m, Vector3.new(2.5, 2, 2.5) * c.Rng:NextNumber(0.6, 1.4), CFrame.new(pos + Vector3.new(c.Rng:NextNumber(-12, 12), 0.8, c.Rng:NextNumber(-12, 12))) * CFrame.Angles(c.Rng:NextNumber(0, 1), c.Rng:NextNumber(0, 3), 0), col)
	end
	local beacon = ball(c, m, (cf * CFrame.new(0, 43, 0)).Position, 1.6, glyph, { Material = M.Neon })
	light(c, beacon, glyph, 30, 2)
end

local function pebbles(c, pos: Vector3, s: number)
	local m = model(c, "Pebbles")
	for _ = 1, 3 do
		mk(c, m, Vector3.new(1.4, 0.9, 1.1) * s * c.Rng:NextNumber(0.6, 1.3), CFrame.new(pos + Vector3.new(c.Rng:NextNumber(-2, 2), 0.3, c.Rng:NextNumber(-2, 2))) * yaw(c), pick(c, MESA))
	end
end

local function buildSunscorch(c)
	wallMounds(c, "Dune", SAND, M.Sand, 8)
	local spot = landmarkSpot(c, 0.5, 105, 16, -1)
	if spot then
		obelisk(c, spot)
		potGroup(c, spot + Vector3.new(-12, 0, 10), 1.2)
	end
	scatter(c, 5, 10, sandArch, { Wall = true, MinZ = 50 })
	border(c, 26, 4, { cactus, cactus, mesa, barrelCactus }, 22)
	scatter(c, 26, 4, cactus, { MinS = 0.7, MaxS = 1.3 })
	scatter(c, 14, 6, mesa, { Wall = true, MinZ = 35 })
	scatter(c, 7, 7, bones, { MinZ = 25 })
	cluster(c, 6, 2, 12, 2.5, potGroup, { Overlap = true, MinZ = 30 })
	scatter(c, 20, 2, barrelCactus, { Overlap = true })
	scatter(c, 26, 2, pebbles, { Overlap = true, MaxZ = 50 })
	-- small decorative mounds in the open (non-colliding ellipsoids)
	scatter(c, 14, 8, function(cc, p, s)
		ellip(cc, model(cc, "SandMound"), CFrame.new(p) * yaw(cc), Vector3.new(18, 4, 11) * s, pick(cc, SAND), { Material = M.Sand })
	end, { MinZ = 35, Overlap = true })
end

-- ===== Biome 5: Vinewild Jungle (extras on top of the bamboo) =====

local JUNGLE = { C(40, 120, 50), C(55, 140, 60), C(30, 100, 45), C(70, 160, 70) }
local PETALS = { C(255, 100, 160), C(255, 150, 60), C(190, 90, 255), C(255, 80, 90) }

local function jungleTree(c, pos: Vector3, s: number)
	local m = model(c, "JungleTree")
	local rng = c.Rng
	local bark = C(100, 75, 50)
	local tilt = CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06))
	local h = 26 * s * rng:NextNumber(0.85, 1.15)
	local _, top = vcyl(c, m, pos - Vector3.new(0, 0.5, 0), h, 3 * s, bark, { Solid = true, Material = M.Wood }, tilt)
	for i = 0, 2 do
		mk(c, m, Vector3.new(1.2, 4, 4) * s, CFrame.new(pos) * CFrame.Angles(0, i * TAU / 3 + 0.4, 0) * CFrame.new(0, 2 * s, -2.6 * s) * CFrame.Angles(0, HALF_PI, 0), bark, { Wedge = true })
	end
	local g = pick(c, JUNGLE)
	ellip(c, m, CFrame.new(top + Vector3.new(0, 1.5 * s, 0)), Vector3.new(18, 5, 16) * s, g, { Shadow = true })
	ellip(c, m, CFrame.new(top + Vector3.new(5 * s, -1 * s, 3 * s)), Vector3.new(12, 4, 11) * s, jitter(c, g, 0.1), { Shadow = true })
	for _ = 1, 3 do
		local hang = top + Vector3.new(rng:NextNumber(-6, 6), -1.5, rng:NextNumber(-6, 6)) * s
		local len = rng:NextNumber(7, 15) * s
		vcyl(c, m, hang - Vector3.new(0, len, 0), len, 0.35 * s, C(60, 150, 60))
		ball(c, m, hang - Vector3.new(0, len, 0), 1.1 * s, jitter(c, g, 0.15))
	end
end

local function broadLeaf(c, pos: Vector3, s: number)
	local m = model(c, "BroadLeaf")
	local g = pick(c, JUNGLE)
	local base = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * yaw(c)
	vcyl(c, m, pos, 2.5 * s, 0.7 * s, C(70, 120, 50))
	for i = 1, 6 do
		local cf = base * CFrame.Angles(0, i * TAU / 6, 0) * CFrame.Angles(rad(c.Rng:NextNumber(22, 45)), 0, 0) * CFrame.new(0, 1.5 * s, -4 * s)
		ellip(c, m, cf, Vector3.new(3, 0.35, 8.5) * s, jitter(c, g, 0.12))
	end
end

local function giantFlower(c, pos: Vector3, s: number)
	local m = model(c, "GiantFlower")
	local _, top = vcyl(c, m, pos, 5 * s, 0.8 * s, C(60, 140, 60))
	local col = pick(c, PETALS)
	local base = CFrame.new(top) * yaw(c)
	for i = 1, 5 do
		ellip(c, m, base * CFrame.Angles(0, i * TAU / 5, 0) * CFrame.Angles(rad(15), 0, 0) * CFrame.new(0, 0, -2.4 * s), Vector3.new(2.8, 0.5, 4.6) * s, jitter(c, col, 0.08))
	end
	local centre = ball(c, m, top + Vector3.new(0, 0.4 * s, 0), 2.2 * s, C(255, 230, 80), { Material = M.Neon })
	if c.Rng:NextNumber() < 0.3 then
		light(c, centre, col, 12, 1)
	end
end

local function parrot(c, parent, perch: Vector3, s: number)
	local sets = { { C(230, 50, 50), C(255, 210, 60) }, { C(40, 110, 230), C(255, 170, 40) }, { C(60, 200, 90), C(255, 240, 90) } }
	local set = pick(c, sets)
	local cf = CFrame.new(perch) * yaw(c)
	ellip(c, parent, cf * CFrame.new(0, 1 * s, 0) * CFrame.Angles(rad(-15), 0, 0), Vector3.new(1.2, 1.9, 1.3) * s, set[1])
	ball(c, parent, (cf * CFrame.new(0, 2.2 * s, -0.25 * s)).Position, 1.1 * s, set[1])
	mk(c, parent, Vector3.new(0.4, 0.5, 0.6) * s, cf * CFrame.new(0, 2.1 * s, -0.95 * s) * CFrame.Angles(math.pi, 0, 0), set[2], { Wedge = true })
	mk(c, parent, Vector3.new(0.7, 0.15, 2.2) * s, cf * CFrame.new(0, 0.3 * s, 1.1 * s) * CFrame.Angles(rad(35), 0, 0), set[2])
end

local function stump(c, pos: Vector3, s: number)
	local m = model(c, "Stump")
	local _, top = vcyl(c, m, pos - Vector3.new(0, 0.3, 0), 3.3 * s, 6 * s, C(95, 70, 45), { Solid = true, Material = M.Wood })
	vcyl(c, m, top, 0.15, 5.2 * s, C(200, 160, 105))
	ellip(c, m, CFrame.new(top + Vector3.new(1.5 * s, 0, 0)), Vector3.new(2.5, 0.8, 2.2) * s, pick(c, JUNGLE))
	if c.Rng:NextNumber() < 0.5 then
		parrot(c, m, top + Vector3.new(-1 * s, 0, 0), 0.9)
	end
end

local function stoneHead(c, pos: Vector3)
	local m = model(c, "StoneHead")
	local stone = C(105, 115, 100)
	local face = CFrame.lookAt(pos, Vector3.new(pos.X + 0.001, pos.Y, 0)) -- faces the lane
	local cf = face * CFrame.Angles(rad(-6), 0, rad(5))
	mk(c, m, Vector3.new(16, 20, 14), cf * CFrame.new(0, 9, 0), stone, { Solid = true })
	mk(c, m, Vector3.new(17, 3, 4), cf * CFrame.new(0, 15, -6.5), jitter(c, stone, 0.06), { Solid = true }) -- brow
	mk(c, m, Vector3.new(3.5, 7, 4), cf * CFrame.new(0, 10, -8.2) * CFrame.Angles(0, math.pi, 0), jitter(c, stone, 0.05), { Wedge = true }) -- nose
	for side = -1, 1, 2 do
		mk(c, m, Vector3.new(4, 2.6, 1), cf * CFrame.new(side * 4.2, 12.5, -7.1), C(30, 35, 30))
		local eye = ball(c, m, (cf * CFrame.new(side * 4.2, 12.5, -7.5)).Position, 1.6, C(255, 100, 160), { Material = M.Neon })
		if side == 1 then
			light(c, eye, C(255, 100, 160), 18, 1.6)
		end
		mk(c, m, Vector3.new(2.5, 8, 4), cf * CFrame.new(side * 9, 9, 0), jitter(c, stone, 0.08), { Solid = true }) -- ears
	end
	mk(c, m, Vector3.new(8, 1.4, 1), cf * CFrame.new(0, 4.5, -7.1), C(30, 35, 30)) -- mouth
	ellip(c, m, cf * CFrame.new(0, 19.5, 0), Vector3.new(17, 4, 15), C(60, 140, 60))
	for i = 1, 7 do
		local x = -7 + i * 1.8
		local len = c.Rng:NextNumber(5, 14)
		mk(c, m, Vector3.new(0.5, len, 0.5), cf * CFrame.new(x, 19 - len / 2, -7.3 + math.abs(x) * 0.05), C(50, 140, 55))
	end
	for _ = 1, 4 do
		broadLeaf(c, (face * CFrame.new(c.Rng:NextNumber(-12, 12), 0, c.Rng:NextNumber(-4, 8))).Position, 0.8)
	end
end

local function buildVinewild(c)
	local spot = landmarkSpot(c, 0.62, 110, 16, -1)
	if spot then
		stoneHead(c, spot)
	end
	border(c, 34, 7, { jungleTree, broadLeaf, jungleTree }, 20)
	scatter(c, 18, 4, broadLeaf, { Wall = true })
	scatter(c, 10, 3, giantFlower, {})
	scatter(c, 7, 4, stump, { MinZ = 25 })
	scatter(c, 10, 3, function(cc, p, s) bush(cc, p, s, JUNGLE) end, {})
	scatter(c, 12, 3, flowerPatch, { Overlap = true })
end

-- ===== Biome 6: Emberpeak Caldera (volcano) =====

local BASALT = { C(55, 50, 55), C(45, 40, 45), C(68, 60, 62), C(38, 34, 38) }
local LAVA = C(255, 110, 25)
local OBSIDIAN = C(35, 20, 50)

local function basaltCluster(c, pos: Vector3, s: number)
	local m = model(c, "Basalt")
	local rng = c.Rng
	for _ = 1, rng:NextInteger(4, 7) do
		local off = Vector3.new(rng:NextNumber(-4, 4), -0.5, rng:NextNumber(-4, 4)) * s
		vcyl(c, m, pos + off, rng:NextNumber(4, 17) * s, rng:NextNumber(2.8, 4.2) * s, pick(c, BASALT), { Solid = true, Material = M.Basalt },
			CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06)))
	end
end

local function jaggedRock(c, pos: Vector3, s: number)
	local m = model(c, "JaggedRock")
	local rng = c.Rng
	for i = 1, rng:NextInteger(2, 3) do
		local size = Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(7, 12), rng:NextNumber(4, 6)) * s * (i == 1 and 1 or 0.65)
		local cf = CFrame.new(pos + Vector3.new(rng:NextNumber(-2, 2) * s, size.Y * 0.35, rng:NextNumber(-2, 2) * s)) * yaw(c) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5))
		mk(c, m, size, cf, pick(c, BASALT), { Solid = true, Material = M.Basalt })
		if i == 1 and rng:NextNumber() < 0.5 then
			mk(c, m, Vector3.new(0.3, size.Y * 0.7, 0.5), cf * CFrame.new(size.X / 2, 0, 0) * CFrame.Angles(0, 0, 0.2), LAVA, { Material = M.Neon })
		end
	end
end

local function lavaPool(c, pos: Vector3, s: number)
	local m = model(c, "LavaPool")
	local r = 7 * s
	disc(c, m, pos, r + 1.8, 0.6, 1, C(35, 28, 28), { Material = M.Basalt })
	local lava = disc(c, m, pos, r, 0.75, 1, LAVA, { Material = M.Neon })
	for _ = 1, 3 do
		mk(c, m, Vector3.new(1.6, 0.6, 1.2) * c.Rng:NextNumber(0.8, 1.6), CFrame.new(pos + Vector3.new(c.Rng:NextNumber(-r, r) * 0.6, 0.9, c.Rng:NextNumber(-r, r) * 0.6)) * yaw(c), C(40, 30, 30))
	end
	light(c, lava, LAVA, 18, 2)
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(C(255, 200, 80), C(255, 70, 20))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.25, 0)
	embers.Lifetime = NumberRange.new(1.5, 3)
	embers.Rate = 4
	embers.Speed = NumberRange.new(3, 6)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.EmissionDirection = Enum.NormalId.Right -- the disc's local +X is world up
	embers.Parent = lava
end

local function smokingVent(c, pos: Vector3, s: number)
	local m = model(c, "Vent")
	local _, t1 = vcyl(c, m, pos, 1.4 * s, 5 * s, pick(c, BASALT), { Material = M.Basalt })
	local _, t2 = vcyl(c, m, t1, 1.2 * s, 3 * s, pick(c, BASALT), { Material = M.Basalt })
	local glow = vcyl(c, m, t2 - Vector3.new(0, 0.1, 0), 0.2, 1.8 * s, LAVA, { Material = M.Neon })
	local smoke = Instance.new("Smoke")
	smoke.Color = C(80, 75, 75)
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 5
	smoke.Size = 4
	smoke.Parent = glow
end

local function obsidianShards(c, pos: Vector3, s: number)
	local m = model(c, "Obsidian")
	local rng = c.Rng
	for i = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(4, 12) * s * (i == 1 and 1.3 or 1)
		local w = rng:NextNumber(1.2, 2.2) * s
		local cf = CFrame.new(pos + Vector3.new(rng:NextNumber(-2.5, 2.5) * s, h * 0.4, rng:NextNumber(-2.5, 2.5) * s)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), rng:NextNumber(-0.4, 0.4))
		mk(c, m, Vector3.new(w, h, w), cf * CFrame.Angles(0, rad(45), 0), OBSIDIAN, { Material = M.Glass, Reflectance = 0.3, Solid = h > 8 })
	end
end

local function charredTree(c, pos: Vector3, s: number)
	local m = model(c, "CharredTree")
	local rng = c.Rng
	local col = C(35, 28, 25)
	local tilt = CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1))
	local h = 10 * s
	vcyl(c, m, pos - Vector3.new(0, 0.5, 0), h, 1.6 * s, col, { Solid = true, Material = M.Wood }, tilt)
	for _ = 1, 3 do
		local y = rng:NextNumber(0.45, 0.85) * h
		local root = CFrame.new(pos) * tilt * CFrame.new(0, y, 0) * yaw(c) * CFrame.Angles(0, 0, rad(rng:NextNumber(35, 60)))
		local _, tip = vcyl(c, m, root.Position, rng:NextNumber(3, 5) * s, 0.7 * s, col, nil, root - root.Position)
		if rng:NextNumber() < 0.35 then
			ball(c, m, tip, 0.5 * s, LAVA, { Material = M.Neon })
		end
	end
end

local function volcanoCone(c, pos: Vector3)
	local m = model(c, "Volcano")
	local tiers = { { 92, 9 }, { 76, 9 }, { 60, 9 }, { 46, 9 }, { 34, 8 }, { 26, 6 } }
	local y = -0.5
	for i, t in ipairs(tiers) do
		vcyl(c, m, pos + Vector3.new(0, y, 0), t[2] + 0.5, t[1], BASALT[(i - 1) % #BASALT + 1], { Solid = true, Material = M.Basalt })
		y += t[2]
	end
	local crater = disc(c, m, pos, 10, y + 0.3, 0.6, LAVA, { Material = M.Neon })
	light(c, crater, LAVA, 40, 3)
	local smoke = Instance.new("Smoke")
	smoke.Color = C(70, 60, 60)
	smoke.Opacity = 0.2
	smoke.RiseVelocity = 9
	smoke.Size = 14
	smoke.Parent = crater
	-- lava streams running down the slope toward the lane
	local toLane = pos.Z > 0 and 0 or math.pi
	for k = -1, 1 do
		local dir = CFrame.Angles(0, toLane + k * 0.45, 0)
		mk(c, m, Vector3.new(2.2, 0.6, 44), CFrame.new(pos) * dir * CFrame.new(0, y * 0.52, -24) * CFrame.Angles(rad(-50), 0, 0), LAVA, { Material = M.Neon })
	end
end

local function buildEmberpeak(c)
	local spot = landmarkSpot(c, 0.5, 125, 46, 1)
	if spot then
		volcanoCone(c, spot)
	end
	border(c, 24, 6, { basaltCluster, jaggedRock, charredTree, jaggedRock }, 18)
	scatter(c, 9, 9, lavaPool, { MinZ = 28, MinS = 0.7, MaxS = 1.4 })
	scatter(c, 14, 6, basaltCluster, { Wall = true })
	scatter(c, 18, 5, jaggedRock, { MinS = 0.6, MaxS = 1.3 })
	scatter(c, 9, 3, smokingVent, { MinZ = 20 })
	cluster(c, 6, 2, 12, 3, obsidianShards, {})
	scatter(c, 10, 3, charredTree, {})
	scatter(c, 14, 5, function(cc, p, s)
		ellip(cc, model(cc, "Ash"), CFrame.new(p) * yaw(cc), Vector3.new(9, 1.6, 6) * s, pick(cc, { C(90, 85, 85), C(75, 70, 72) }))
	end, { Overlap = true })
	scatter(c, 20, 2, pebbles, { Overlap = true, MaxZ = 45 })
end

-- ===== Biome 7: Frostveil Tundra (frozen) =====

local SNOW = { C(240, 248, 255), C(230, 240, 252), C(248, 252, 255) }
local ICE = { C(170, 215, 255), C(140, 200, 250), C(190, 230, 255) }
local AURORA = { C(90, 255, 170), C(80, 220, 255), C(200, 110, 255) }

local function iceSpikes(c, pos: Vector3, s: number)
	local m = model(c, "IceSpikes")
	local rng = c.Rng
	for i = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(6, 15) * s * (i == 1 and 1.3 or 1)
		local w = rng:NextNumber(1.8, 3) * s
		local cf = CFrame.new(pos + Vector3.new(rng:NextNumber(-3, 3) * s, h * 0.4, rng:NextNumber(-3, 3) * s)) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, TAU), rng:NextNumber(-0.35, 0.35))
		mk(c, m, Vector3.new(w, h, w), cf * CFrame.Angles(0, rad(45), 0), pick(c, ICE), { Material = M.Ice, Transparency = 0.15, Solid = h > 9 })
	end
end

local function frozenPine(c, pos: Vector3, s: number)
	local m = model(c, "FrozenPine")
	local _, top = vcyl(c, m, pos - Vector3.new(0, 0.5, 0), 5 * s, 1.8 * s, C(90, 70, 60), { Solid = true, Material = M.Wood })
	local g = jitter(c, C(40, 95, 90), 0.08)
	for i = 1, 3 do
		local d = (12 - (i - 1) * 3.5) * s
		local base = top + Vector3.new(0, (i - 1) * 3.4 * s - 1.5 * s, 0)
		vcyl(c, m, base, 3.2 * s, d, g, { Shadow = true })
		vcyl(c, m, base + Vector3.new(0, 3.2 * s, 0), 0.6 * s, d * 0.85, pick(c, SNOW), { Material = M.Snow })
	end
	ball(c, m, top + Vector3.new(0, 9.6 * s, 0), 2.4 * s, WHITE, { Material = M.Snow })
end

local function igloo(c, pos: Vector3, s: number)
	local m = model(c, "Igloo")
	local d = 14 * s
	mk(c, m, Vector3.one * d, CFrame.new(pos - Vector3.new(0, d * 0.1, 0)), C(245, 250, 255), { Shape = BALL, Solid = true, Material = M.Snow })
	local toLane = CFrame.lookAt(pos, Vector3.new(pos.X, pos.Y, 0))
	local tunnel = toLane * CFrame.new(0, 0, -d * 0.45) * CFrame.Angles(0, HALF_PI, 0)
	hcyl(c, m, tunnel, 6 * s, 6 * s, C(235, 244, 255), { Solid = true, Material = M.Snow })
	hcyl(c, m, toLane * CFrame.new(0, 0.6 * s, -d * 0.45 - 3 * s) * CFrame.Angles(0, HALF_PI, 0), 0.2, 4.2 * s, C(40, 60, 90))
end

local function frozenPond(c, pos: Vector3, s: number)
	local m = model(c, "FrozenPond")
	local r = 9 * s
	disc(c, m, pos, r, 0.2, 0.3, C(175, 220, 245), { Material = M.Ice, Reflectance = 0.15 })
	mk(c, m, Vector3.new(r * 1.2, 0.1, 0.25), CFrame.new(pos + Vector3.new(0, 0.25, 0)) * yaw(c), WHITE)
	for i = 1, 3 do
		local a = i * TAU / 3 + c.Rng:NextNumber(0, 1)
		ellip(c, m, CFrame.new(pos + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r)) * CFrame.Angles(0, -a, 0), Vector3.new(3, 1.6, 6) * s, pick(c, SNOW), { Material = M.Snow })
	end
end

local function snowRock(c, pos: Vector3, s: number)
	rock(c, pos, s, { C(110, 120, 135), C(95, 105, 120) }, C(245, 250, 255))
end

local function aurora(c, idx: number)
	local m = model(c, "Aurora")
	local rng = c.Rng
	local b = c.B
	local x = b.MinX + 40 + rng:NextNumber(0, b.MaxX - b.MinX - 80)
	local z = (idx % 2 == 0 and 1 or -1) * rng:NextNumber(40, c.Edge - 20)
	local y = c.Top + rng:NextNumber(95, 125)
	local col = AURORA[(idx - 1) % #AURORA + 1]
	local heading = rng:NextNumber(-0.4, 0.4)
	for i = 0, 5 do
		local seg = 32
		local px = x + (i - 2.5) * seg * math.cos(heading)
		local pz = z + (i - 2.5) * seg * math.sin(heading) + math.sin(i * 1.3) * 8
		mk(c, m, Vector3.new(seg + 2, rng:NextNumber(12, 18), 0.2),
			CFrame.new(px, y + math.sin(i * 0.9) * 5, pz) * CFrame.Angles(0, -heading + (i % 2 == 0 and 0.18 or -0.18), rad(rng:NextNumber(-4, 4))),
			col:Lerp(AURORA[idx % #AURORA + 1], i / 6), { Material = M.Neon, Transparency = rng:NextNumber(0.62, 0.75) })
	end
end

local function giantIceCrystal(c, pos: Vector3)
	local m = model(c, "IceCrystal")
	ellip(c, m, CFrame.new(pos), Vector3.new(34, 8, 30), C(240, 248, 255), { Material = M.Snow })
	local main = CFrame.new(pos + Vector3.new(0, 24, 0)) * CFrame.Angles(0, rad(45), rad(4))
	mk(c, m, Vector3.new(10, 48, 10), main, C(160, 215, 255), { Material = M.Glass, Transparency = 0.25, Solid = true })
	mk(c, m, Vector3.new(7.1, 7.1, 7.1), main * CFrame.new(0, 26, 0) * CFrame.Angles(rad(45), 0, rad(45)) , C(190, 230, 255), { Material = M.Glass, Transparency = 0.25 })
	local core = mk(c, m, Vector3.new(2.5, 40, 2.5), main, C(120, 210, 255), { Material = M.Neon, Transparency = 0.2 })
	light(c, core, C(120, 200, 255), 40, 2.5)
	for i = 1, 6 do
		local a = i * TAU / 6 + c.Rng:NextNumber(-0.2, 0.2)
		local h = c.Rng:NextNumber(12, 24)
		mk(c, m, Vector3.new(4.5, h, 4.5), CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.new(0, h * 0.35, -8) * CFrame.Angles(rad(-28), rad(45), 0),
			pick(c, ICE), { Material = M.Glass, Transparency = 0.2, Solid = true })
	end
end

local function buildFrostveil(c)
	wallMounds(c, "SnowDrift", SNOW, M.Snow, 8)
	local spot = landmarkSpot(c, 0.45, 115, 20, 1)
	if spot then
		giantIceCrystal(c, spot)
	end
	for i = 1, 4 do
		aurora(c, i)
	end
	border(c, 22, 6, { frozenPine, frozenPine, iceSpikes, snowRock }, 18)
	scatter(c, 5, 8, igloo, { MinZ = 35, MinS = 0.9, MaxS = 1.2 })
	scatter(c, 20, 6, frozenPine, { Wall = true })
	cluster(c, 8, 2, 14, 4, iceSpikes, {})
	scatter(c, 7, 10, frozenPond, { MinZ = 30, Overlap = true, MinS = 0.7, MaxS = 1.4 })
	scatter(c, 14, 4, snowRock, { MinS = 0.5, MaxS = 1.2 })
	scatter(c, 18, 7, function(cc, p, s)
		ellip(cc, model(cc, "SnowMound"), CFrame.new(p) * yaw(cc), Vector3.new(12, 3, 8) * s, pick(cc, SNOW), { Material = M.Snow })
	end, { Overlap = true })
	motes(c, 30, { C(220, 240, 255), C(160, 220, 255) }, 4, 30, 0.4)
end

-- ===== Biome 8: Astral Ruins (space / ancient extras) =====

local TEMPLE = { C(190, 185, 215), C(170, 165, 200), C(205, 200, 225) }
local RUNE = { C(170, 140, 255), C(110, 230, 255), C(255, 140, 230) }

local function templeColumn(c, pos: Vector3, s: number)
	local m = model(c, "Column")
	local rng = c.Rng
	local col = pick(c, TEMPLE)
	local broken = rng:NextNumber() < 0.65
	mk(c, m, Vector3.new(5.5, 1.6, 5.5) * s, CFrame.new(pos + Vector3.new(0, 0.6 * s, 0)), jitter(c, col, 0.05), { Solid = true })
	local h = (broken and rng:NextNumber(7, 16) or 24) * s
	local _, top = vcyl(c, m, pos + Vector3.new(0, 1.3 * s, 0), h, 3.4 * s, col, { Solid = true })
	vcyl(c, m, pos + Vector3.new(0, 1.3 * s + h * 0.4, 0), 0.5, 3.6 * s, pick(c, RUNE), { Material = M.Neon })
	if broken then
		hcyl(c, m, CFrame.new(pos + Vector3.new(rng:NextNumber(4, 6) * s, 1.7 * s, rng:NextNumber(-3, 3) * s)) * yaw(c), rng:NextNumber(4, 7) * s, 3.4 * s, col, { Solid = true })
	else
		mk(c, m, Vector3.new(5.5, 1.6, 5.5) * s, CFrame.new(top + Vector3.new(0, 0.8 * s, 0)), jitter(c, col, 0.05), { Solid = true })
	end
end

local function runeStone(c, pos: Vector3, s: number)
	local m = model(c, "RuneStone")
	local rng = c.Rng
	local face = CFrame.lookAt(pos, Vector3.new(pos.X, pos.Y, 0)) * CFrame.Angles(rng:NextNumber(-0.12, 0.05), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.1, 0.1))
	local cf = face * CFrame.new(0, 3.2 * s, 0)
	mk(c, m, Vector3.new(4.5, 8, 1.6) * s, cf, C(55, 50, 85), { Solid = true })
	local col = pick(c, RUNE)
	local glyph = mk(c, m, Vector3.new(0.4, 3.6, 0.2) * s, cf * CFrame.new(0, 0.6 * s, -0.85 * s), col, { Material = M.Neon })
	mk(c, m, Vector3.new(2.4, 0.4, 0.2) * s, cf * CFrame.new(0, 1.6 * s, -0.85 * s), col, { Material = M.Neon })
	mk(c, m, Vector3.new(1.1, 1.1, 0.2) * s, cf * CFrame.new(0, -2 * s, -0.85 * s) * CFrame.Angles(0, 0, rad(45)), col, { Material = M.Neon })
	if rng:NextNumber() < 0.5 then
		light(c, glyph, col, 12, 1.2)
	end
end

local function floatingIsland(c, idx: number)
	local m = model(c, "FloatingIsland")
	local rng = c.Rng
	local b = c.B
	for _ = 1, 20 do
		local s = rng:NextNumber(0.8, 1.6)
		local x = rng:NextNumber(b.MinX + GATE_CLEAR + 10, b.MaxX - END_CLEAR - 10)
		local z = rng:NextNumber(-c.Edge + 15, c.Edge - 15)
		local y = c.Top + rng:NextNumber(24, 60)
		if fits(c, x, z, 2, true, true) then
			local p = Vector3.new(x, y, z)
			vcyl(c, m, p, 2 * s, 13 * s, C(85, 75, 135))
			vcyl(c, m, p - Vector3.new(0, 3 * s, 0), 3 * s, 10 * s, C(60, 55, 85))
			vcyl(c, m, p - Vector3.new(0, 6 * s, 0), 3 * s, 6 * s, C(50, 45, 75))
			vcyl(c, m, p - Vector3.new(0, 8.5 * s, 0), 2.5 * s, 2.4 * s, C(45, 40, 70))
			if idx % 2 == 0 then
				local crystal = mk(c, m, Vector3.new(1.6, 4, 1.6) * s, CFrame.new(p + Vector3.new(1.5 * s, 4 * s, 0)) * CFrame.Angles(0.2, rad(45), 0.15), pick(c, RUNE), { Material = M.Neon })
				light(c, crystal, crystal.Color, 14, 1)
			else
				vcyl(c, m, p + Vector3.new(-2 * s, 2 * s, 1 * s), 5 * s, 1.6 * s, pick(c, TEMPLE))
			end
			return
		end
	end
end

local function archGate(c): boolean
	local m = model(c, "ArchGate")
	local b = c.B
	local rng = c.Rng
	for _ = 1, 40 do
		local x = rng:NextNumber(b.MinX + 80, b.MaxX - 60)
		if fits(c, x, 26, 6, false, true) and fits(c, x, -26, 6, false, true) then
			claim(c, x, 26, 6)
			claim(c, x, -26, 6)
			local stone = C(180, 175, 210)
			for side = -1, 1, 2 do
				local p = Vector3.new(x, c.Top, side * 26)
				mk(c, m, Vector3.new(9, 3, 9), CFrame.new(p + Vector3.new(0, 1.5, 0)), C(150, 145, 185), { Solid = true })
				mk(c, m, Vector3.new(6, 40, 6), CFrame.new(p + Vector3.new(0, 23, 0)), stone, { Solid = true })
				mk(c, m, Vector3.new(0.4, 30, 1.6), CFrame.new(p + Vector3.new(-3.05, 22, 0)), RUNE[1], { Material = M.Neon })
				mk(c, m, Vector3.new(8, 2.5, 8), CFrame.new(p + Vector3.new(0, 44, 0)), C(150, 145, 185), { Solid = true })
			end
			-- broken lintel: one half still up, the other half fell beside the lane
			mk(c, m, Vector3.new(8, 5, 32), CFrame.new(x, c.Top + 47.5, -12) * CFrame.Angles(rad(-4), 0, 0), stone, { Solid = true })
			mk(c, m, Vector3.new(0.4, 1.2, 26), CFrame.new(x - 4.05, c.Top + 47.5, -12), RUNE[2], { Material = M.Neon })
			if fits(c, x + 3, 46, 11) then
				claim(c, x + 3, 46, 11)
				mk(c, m, Vector3.new(8, 5, 22), CFrame.new(x + 3, c.Top + 4, 46) * CFrame.Angles(rad(8), rad(25), rad(-12)), stone, { Solid = true })
			end
			local orb = ball(c, m, Vector3.new(x, c.Top + 38, 0), 4, RUNE[1], { Material = M.Neon, Transparency = 0.2 })
			light(c, orb, RUNE[1], 35, 2)
			for i = 1, 6 do
				mk(c, m, Vector3.one * rng:NextNumber(1.5, 3.2), CFrame.new(x + rng:NextNumber(-4, 4), c.Top + 44 + i * 1.5, 6 + i * 2.5) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), stone)
			end
			return true
		end
	end
	return false
end

local function ringedPlanet(c)
	local m = model(c, "Planet")
	local centre = Vector3.new(c.B.MaxX + 420, c.Top + 230, -60)
	local d = 220
	ball(c, m, centre, d, C(120, 85, 200))
	ellip(c, m, CFrame.new(centre), Vector3.new(d * 1.01, d * 0.22, d * 1.01), C(170, 130, 240))
	ellip(c, m, CFrame.new(centre + Vector3.new(0, d * 0.25, 0)), Vector3.new(d * 0.97, d * 0.12, d * 0.97), C(90, 60, 170))
	local tilt = CFrame.new(centre) * CFrame.Angles(rad(18), 0, rad(-12))
	local segs = 24
	local ringR = d * 0.95
	for i = 0, segs - 1 do
		local a = i * TAU / segs
		mk(c, m, Vector3.new(TAU * ringR / segs + 2, 1, 48), tilt * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -ringR), i % 2 == 0 and C(220, 190, 255) or C(190, 160, 240),
			{ Transparency = 0.25 })
	end
	ball(c, m, centre + Vector3.new(-120, 150, 260), 46, C(200, 205, 230))
end

local function brokenTiles(c, pos: Vector3, s: number)
	local m = model(c, "Tiles")
	for _ = 1, c.Rng:NextInteger(2, 4) do
		mk(c, m, Vector3.new(4, 0.35, 4) * s * c.Rng:NextNumber(0.7, 1.1), CFrame.new(pos + Vector3.new(c.Rng:NextNumber(-3, 3), 0.15, c.Rng:NextNumber(-3, 3)) * s) * CFrame.Angles(0, c.Rng:NextNumber(0, 0.6), 0), pick(c, TEMPLE))
	end
end

local function buildAstralRuins(c)
	ringedPlanet(c)
	archGate(c)
	border(c, 30, 5, { templeColumn, templeColumn, runeStone }, 20)
	scatter(c, 14, 5, templeColumn, {})
	scatter(c, 10, 3, runeStone, {})
	scatter(c, 6, 8, function(cc, p, s)
		local mm = model(cc, "FallenColumn")
		local cf = CFrame.new(p + Vector3.new(0, 1.7 * s, 0)) * CFrame.Angles(0, cc.Rng:NextNumber(-0.6, 0.6), 0)
		for i = 0, 2 do
			hcyl(cc, mm, cf * CFrame.new((i - 1) * 5.4 * s, 0, cc.Rng:NextNumber(-0.4, 0.4)) * CFrame.Angles(0, cc.Rng:NextNumber(-0.08, 0.08), 0), 5 * s, 3.4 * s, pick(cc, TEMPLE), { Solid = true })
		end
	end, { MinZ = 30 })
	for i = 1, 9 do
		if full(c, 60) then
			break
		end
		floatingIsland(c, i)
	end
	scatter(c, 14, 3, brokenTiles, { Overlap = true, MaxZ = 40 })
	motes(c, 70, { WHITE, C(200, 180, 255), C(140, 230, 255) }, 3, 45, 0.45)
end

local BUILDERS = {
	RiftLab = buildRiftLab,
	Mosswood = buildMosswood,
	GlimmerLake = buildGlimmerLake,
	Sunscorch = buildSunscorch,
	Vinewild = buildVinewild,
	Emberpeak = buildEmberpeak,
	Frostveil = buildFrostveil,
	AstralRuins = buildAstralRuins,
}

local function paint(inst: Instance?, color: Color3, material: Enum.Material?)
	if not inst then
		return
	end
	local parts = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
	for _, p in ipairs(parts) do
		if p:IsA("BasePart") then
			p.Color = color
			if material then
				p.Material = material
			end
		end
	end
end

function BiomeDecor.Decorate(zoneModel: Model, biome, bounds, avoid: { Vector3 }): Folder
	local old = zoneModel:FindFirstChild("RR_Decor")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "RR_Decor"

	local ground = biome.Theme.Ground
	paint(zoneModel:FindFirstChild("Floor"), ground, FLOOR_MATERIAL[biome.Id])
	paint(zoneModel:FindFirstChild("Path", true), ground:Lerp(BLACK, 0.25), nil)

	local c = {
		Folder = folder,
		Rng = Random.new(biome.Index * 7919),
		B = bounds,
		Top = bounds.TopY,
		Edge = math.min(math.abs(bounds.MinZ), math.abs(bounds.MaxZ)) - 1,
		Avoid = avoid or {},
		Placed = {},
		Groups = {},
		Count = 0,
		Lights = 0,
		Budget = BUDGETS[biome.Id] or 300,
		Theme = biome.Theme,
	}
	local builder = BUILDERS[biome.Id]
	if builder then
		builder(c)
	end
	folder:SetAttribute("PartCount", c.Count)
	folder.Parent = zoneModel -- parent last so the whole set replicates in one go
	return folder
end

return BiomeDecor

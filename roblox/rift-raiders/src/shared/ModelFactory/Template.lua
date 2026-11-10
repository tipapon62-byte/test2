-- Classic characters: clones ReplicatedStorage.CharacterModels.<Template> (loose parts built around the
-- origin, facing -Z, feet at Y≈0) and converts it to the factory rig:
--   * Root at bottom-centre; parts scaled to ~4.5 studs tall (wide models capped at 6.5 studs)
--   * torso-like part -> "Body" (Root), "Head" (Body), Arm/Hand/Shoulder/Sleeve/... per side -> "ArmL"/"ArmR"
--     (Body), Leg/Shoe/Boot/... -> "LegL"/"LegR" or "LegFL".. (Root); face parts follow the Head,
--     ground decorations (dishes, splashes, pedestals) stay on Root; everything else joins its nearest group
--   * Eye/Pupil/Shine/Iris get L/R suffixes (blinking), glossy eyes, extra eye shine
--   * 1-3 signature details per character, then the toy-brick restyle
-- Returns false when the template is missing so the caller can fall back to the procedural archetype.

local Kit = require(script.Parent.Style)

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local C = Color3.fromRGB
local Neon, Glass = Enum.Material.Neon, Enum.Material.Glass

local Template = {}

local TARGET_H, MAX_W = 4.5, 6.5
local MAX_BASE_PARTS = 42

local function set(list: { string }): { [string]: boolean }
	local t = {}
	for _, v in list do
		t[v] = true
	end
	return t
end

local ARM_NAMES = set({ "Arm", "Hand", "Shoulder", "Sleeve", "Glove", "Claw", "Pincer" })
local LEG_NAMES = set({ "Leg", "Shoe", "Foot", "Boot", "BootTip", "Sock", "SockStripe", "Shorts", "Warmer", "Sneaker",
	"Sole", "Swoosh" })
local EYE_NAMES = set({ "Eye", "Pupil", "Shine", "Iris", "EyeA", "EyeB", "Eye3", "Pupil3" })
local SIDED_EYES = set({ "Eye", "Pupil", "Shine", "Iris" })
local FACE_NAMES = set({ "Mouth", "Brow", "Teeth", "Tooth", "Lid", "Nose", "Blush", "Cheek", "Lash", "Smile", "Smirk",
	"Drool", "Whisker", "Stubble", "Unibrow", "Nostril" })
local HEAD_NAMES = set({ "Hair", "HairCap", "Spike", "Ear", "Tuft", "Fringe", "Headband", "Flame", "Peak", "Hat",
	"HatTop", "HatTrim", "Skull", "Beard", "Muzzle", "Dome" })
local BODY_PRIORITY = { "Torso", "Body", "Log", "Fuselage", "Pickle", "Egg", "Bowl", "Shirt" }
local KEEP_DENSE = set({ "Spike", "Flame" }) -- hair spikes are never thinned out

-- rotated bounding box
local function extents(p: BasePart): (Vector3, Vector3)
	local cf, s = p.CFrame, p.Size
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local h = V3(
		(math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z) / 2,
		(math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2,
		(math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z) / 2
	)
	return cf.Position - h, cf.Position + h
end

local function boxDistance(q: Vector3, p: BasePart): number
	local lo, hi = extents(p)
	local dx = math.max(lo.X - q.X, 0, q.X - hi.X)
	local dy = math.max(lo.Y - q.Y, 0, q.Y - hi.Y)
	local dz = math.max(lo.Z - q.Z, 0, q.Z - hi.Z)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function volume(p: BasePart): number
	local s = p.Size
	return math.max(s.X * s.Y * s.Z, 0.001)
end

local function colorDist(a: Color3, b: Color3): number
	return math.sqrt((a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.B) ^ 2)
end

-- End point of the part's long axis that is nearest to `target` (shoulder / hip pivots).
local function nearEnd(p: BasePart, target: Vector3): Vector3
	local s = p.Size
	local axis
	if s.Y >= s.X and s.Y >= s.Z then
		axis = V3(0, s.Y / 2, 0)
	elseif s.X >= s.Z then
		axis = V3(s.X / 2, 0, 0)
	else
		axis = V3(0, 0, s.Z / 2)
	end
	local a, b = p.CFrame * axis, p.CFrame * -axis
	return (a - target).Magnitude <= (b - target).Magnitude and a or b
end

local function topEnd(p: BasePart): Vector3
	return nearEnd(p, p.Position + V3(0, 1000, 0))
end

-- Removes every other copy of the most repeated small decoration until the part budget fits.
local function thin(parts: { BasePart }): { BasePart }
	while #parts > MAX_BASE_PARTS do
		local groups: { [string]: { BasePart } } = {}
		for _, p in parts do
			groups[p.Name] = groups[p.Name] or {}
			table.insert(groups[p.Name], p)
		end
		local best, bestN, bestName = nil, 5, ""
		for name, list in groups do
			if not KEEP_DENSE[name] and (#list > bestN or (#list == bestN and best and name < bestName)) then
				best, bestN, bestName = list, #list, name
			end
		end
		if not best then
			break
		end
		local drop = {}
		for i = 2, #best, 2 do
			drop[best[i]] = true
		end
		local kept = {}
		for _, p in parts do
			if drop[p] then
				p:Destroy()
			else
				table.insert(kept, p)
			end
		end
		parts = kept
	end
	return parts
end

-- ===================================================================== signature details
-- Coordinates are in the original template space (from the CharacterModels dump); T.P / T.S convert.

type T = {
	model: Model,
	ctx: any,
	k: number,
	body: BasePart,
	head: BasePart?,
	root: BasePart,
	P: (x: number, y: number, z: number) -> Vector3,
	S: (x: number, y: number, z: number) -> Vector3,
	find: (name: string, side: string?) -> BasePart?,
	add: (attach: BasePart?, name: string, shape: string, size: Vector3, pos: Vector3, color: Color3, role: string,
		mat: Enum.Material?, rot: CFrame?) -> BasePart,
	parent: { [BasePart]: BasePart },
	pivot: { [BasePart]: Vector3 },
}

local function diamond(t: T, attach: BasePart?, name: string, size: number, pos: Vector3, color: Color3,
	role: string, mat: Enum.Material?): BasePart
	local d = Kit.Diamond(t.model, attach or t.body, name, size * t.k, size * 0.25 * t.k, CF(t.P(pos.X, pos.Y, pos.Z)),
		color, role, mat)
	d.CastShadow = false
	return d
end

local function glassify(p: BasePart, transparency: number, reflectance: number?)
	p.Material = Glass
	p.Transparency = transparency
	p.Reflectance = reflectance or 0.2
end

local function orbitize(t: T, name: string)
	local i = 0
	for _, p in t.model:GetChildren() do
		if p:IsA("BasePart") and p.Name == name then
			i += 1
			p.Name = "Orbit" .. i
			t.parent[p] = t.body
			t.pivot[p] = V3(t.body.Position.X, p.Position.Y, t.body.Position.Z)
		end
	end
end

local Details: { [string]: { Pre: ((T) -> ())?, Post: ((T) -> ())? } } = {}

Details.PanicGrandson = {
	Post = function(t)
		for _, s in { -1, 1 } do
			local drop = t.add(t.head, "SweatDrop", "Ell", V3(0.24, 0.36, 0.24), V3(s * 1.05, 4.95, -0.55),
				C(150, 220, 255), "Glass")
			glassify(drop, 0.1, 0.35)
		end
		t.add(t.body, "Backpack", "Block", V3(1.3, 1.4, 0.55), V3(0, 2.85, 0.72), C(230, 60, 50), "Accent")
		t.add(t.body, "BackpackFlap", "Block", V3(1.36, 0.42, 0.62), V3(0, 3.4, 0.74), C(255, 200, 40), "Accent")
	end,
}

Details.ButterRobot = {
	Post = function(t)
		t.add(t.find("ButterPaper"), "Toast", "Block", V3(1.7, 0.28, 1.2), V3(0, 2.6, -2.76), C(225, 165, 90), "Accent")
		local dome = t.find("Dome")
		for _, s in { -1, 1 } do
			t.add(dome, "StatusLight", "Ball", V3(0.34, 0.34, 0.34), V3(s * 1.25, 3.95, -0.85),
				s < 0 and C(90, 255, 140) or C(90, 200, 255), "Glow", Neon)
		end
		local butter = t.find("Butter")
		if butter then
			Kit.Emitter(butter, { Name = "ButterSparkle", Color = C(255, 245, 170), Rate = 1.5, Life = 0.8, Speed = 0.4,
				Size = 0.25 })
		end
	end,
}

Details.HelperBlue = {
	Post = function(t)
		diamond(t, t.body, "StarBadge", 0.6, V3(0, 3.75, -0.42), Kit.Gold, "Accent")
		for _, s in { -1, 1 } do
			diamond(t, t.find("Hand", s < 0 and "L" or "R"), "Sparkle", 0.36, V3(s * 1.9, 6.3, -0.1), C(255, 240, 120),
				"Glow", Neon)
		end
	end,
}

Details.PickleScientist = {
	Post = function(t)
		local dish = t.find("Dish") or t.root
		local flask = Kit.VCyl(t.model, dish, "Flask", 1.1 * t.k, 0.75 * t.k, CF(t.P(1.5, 0.95, -1.2)), C(210, 240, 255),
			"Glass", Glass)
		flask.Transparency = 0.45
		local fluid = Kit.VCyl(t.model, flask, "FlaskFluid", 0.6 * t.k, 0.62 * t.k, CF(t.P(1.5, 0.75, -1.2)),
			C(120, 255, 120), "Glow", Neon)
		t.add(flask, "Cork", "Block", V3(0.4, 0.25, 0.4), V3(1.5, 1.6, -1.2), C(160, 110, 60), "Accent")
		Kit.Emitter(fluid, { Name = "Bubbles", Color = C(190, 255, 190), Rate = 4, Life = 0.9, Speed = 1, Spread = 20,
			Size = 0.15, Accel = V3(0, 1.5, 0) })
		local goggles = t.find("Goggles")
		for _, s in { -1, 1 } do
			local lens = t.add(goggles, "GoggleLens", "Cyl", V3(0.18, 0.7, 0.7), V3(s * 0.55, 6.48, -1.0), C(120, 230, 255),
				"Glass", Glass, ANG(0, math.pi / 2, 0))
			glassify(lens, 0.15, 0.3)
		end
	end,
}

Details.MadGrandpa = {
	Post = function(t)
		local centre = CF(t.P(0, 4.4, 1.7)) * ANG(math.pi / 2, 0, 0)
		Kit.Ring(t.model, t.body, "Portal", centre, 1.5 * t.k, 0.28 * t.k, 0.3 * t.k, 8, C(90, 255, 120), "Glow", Neon)
		local core = t.add(t.body, "PortalCore", "Cyl", V3(0.12, 2.8, 2.8), V3(0, 4.4, 1.72), C(160, 255, 170), "Glass",
			Glass, ANG(0, math.pi / 2, 0))
		core.Transparency = 0.35
		Kit.Light(core, C(110, 255, 140), 10, 1.2)
		Kit.Emitter(core, { Name = "PortalSwirl", Color = C(140, 255, 160), Color2 = C(220, 255, 120), Rate = 6, Life = 1,
			Speed = 0.5, Size = 0.3, Rot = 180 })
	end,
}

Details.SlingshotKid = {
	Post = function(t)
		local deck = t.add(t.find("Hand", "L"), "Skateboard", "Block", V3(0.16, 2.3, 0.8), V3(-1.62, 1.65, 0.2),
			C(255, 90, 170), "Accent")
		for _, yz in { { 0.75, -0.05 }, { 0.75, 0.45 }, { 2.55, -0.05 }, { 2.55, 0.45 } } do
			t.add(deck, "Wheel", "Cyl", V3(0.16, 0.3, 0.3), V3(-1.78, yz[1], yz[2]), C(255, 230, 60), "Accent")
		end
		t.add(t.find("SlingHandle"), "Pebble", "Ball", V3(0.22, 0.22, 0.22), V3(1.32, 2.62, 1.13), C(150, 150, 160),
			"Accent")
	end,
}

Details.DonutDad = {
	Post = function(t)
		local hand = t.find("Hand", "L")
		local face = ANG(0, math.pi / 2, 0)
		local dough = t.add(hand, "BigDonut", "Cyl", V3(0.5, 1.9, 1.9), V3(-1.95, 2.45, -0.45), C(230, 165, 90), "Accent",
			nil, face)
		t.add(dough, "BigFrosting", "Cyl", V3(0.14, 1.72, 1.72), V3(-1.95, 2.45, -0.74), C(255, 120, 190), "Accent", nil,
			face)
		t.add(dough, "DonutHole", "Cyl", V3(0.2, 0.62, 0.62), V3(-1.95, 2.45, -0.79), C(150, 95, 45), "Accent", nil, face)
		local cols = { C(80, 200, 255), C(255, 240, 80), C(255, 255, 255), C(120, 230, 120), C(190, 110, 255) }
		for i, a in { 20, 95, 165, 235, 305 } do
			local ar = rad(a)
			t.add(dough, "Sprinkle", "Block", V3(0.26, 0.07, 0.07), V3(-1.95 + math.cos(ar) * 0.6, 2.45 + math.sin(ar) * 0.6,
				-0.84), cols[i], "Accent", nil, ANG(0, 0, ar * 1.7))
		end
	end,
}

Details.TowerHairMom = {
	Post = function(t)
		t.add(t.find("Hand", "L"), "Handbag", "Block", V3(0.62, 0.5, 0.28), V3(-1.05, 0.88, -0.12), C(220, 50, 70), "Accent")
		local top: BasePart? = nil
		for _, p in t.model:GetChildren() do
			if p:IsA("BasePart") and p.Name == "Hair" and (not top or p.Position.Y > top.Position.Y) then
				top = p
			end
		end
		if top then
			local pos = top.Position + V3(top.Size.X * 0.25, top.Size.Y * 0.1, -top.Size.Z * 0.5 - 0.02)
			local gem = Kit.Diamond(t.model, top, "HairGem", 0.3 * t.k, 0.08 * t.k, CF(pos), C(255, 240, 120), "Glow", Neon)
			gem.CastShadow = false
		end
	end,
}

Details.GreedyBoss = {
	Post = function(t)
		local bag = t.add(t.find("LegR") or t.root, "MoneyBag", "Block", V3(1.0, 1.0, 0.9), V3(1.3, 0.5, -0.35),
			C(205, 175, 110), "Accent")
		t.add(bag, "BagTie", "Block", V3(0.55, 0.22, 0.5), V3(1.3, 1.1, -0.35), C(150, 110, 60), "Accent")
		t.add(bag, "BagCoin", "Cyl", V3(0.08, 0.55, 0.55), V3(1.3, 0.55, -0.82), Kit.Gold, "Accent", nil, ANG(0, math.pi / 2, 0))
		local monocle = t.add(t.head, "Monocle", "Cyl", V3(0.06, 0.64, 0.64), V3(0.31, 6.41, -1.38), C(190, 235, 255), "Glass",
			Glass, ANG(0, math.pi / 2, 0))
		glassify(monocle, 0.3, 0.35)
	end,
}

Details.ThreeEyedFish = {
	Post = function(t)
		for _, p in { V3(1.8, 4.6, 0.8), V3(-1.8, 4.2, 0.4), V3(1.55, 3.3, -1.3) } do
			t.add(t.body, "RadSpot", "Ball", V3(0.6, 0.6, 0.6), p, C(140, 255, 110), "Glow", Neon)
		end
		Kit.Emitter(t.body, { Name = "Bubbles", Color = C(200, 240, 255), Rate = 3, Life = 1.4, Speed = 0.8, Spread = 40,
			Size = 0.25, Accel = V3(0, 1.5, 0) })
	end,
}

Details.PinkStar = {
	Post = function(t)
		local arm = t.find("ArmR")
		local cone = t.add(arm, "Cone", "Block", V3(0.34, 0.6, 0.34), V3(1.85, 3.55, -0.35), C(225, 170, 95), "Accent")
		t.add(cone, "Scoop", "Ball", V3(0.62, 0.62, 0.62), V3(1.85, 4.05, -0.35), C(160, 240, 210), "Accent")
		t.add(cone, "Cherry", "Ball", V3(0.22, 0.22, 0.22), V3(1.85, 4.42, -0.35), C(230, 30, 50), "Accent")
	end,
}

Details.GrumpySquid = {
	Post = function(t)
		local tilt = ANG(rad(18), 0, 0)
		local clar = Kit.VCyl(t.model, t.head or t.body, "Clarinet", 1.7 * t.k, 0.2 * t.k, CF(t.P(0, 3.45, -1.15)) * tilt,
			C(35, 35, 45), "Accent")
		Kit.VCyl(t.model, clar, "ClarinetBell", 0.3 * t.k, 0.46 * t.k, CF(t.P(0, 2.62, -1.42)) * tilt, C(35, 35, 45), "Accent")
	end,
}

Details.SquareSponge = {
	Post = function(t)
		local handle = t.add(t.find("Hand", "R"), "Spatula", "Block", V3(0.12, 1.1, 0.12), V3(2.42, 2.85, -0.1), C(40, 40, 50),
			"Accent")
		t.add(handle, "SpatulaBlade", "Block", V3(0.62, 0.5, 0.07), V3(2.42, 3.6, -0.1), C(200, 205, 215), "Accent")
		Kit.Emitter(t.body, { Name = "Bubbles", Color = C(220, 245, 255), Rate = 2, Life = 1.6, Speed = 0.8, Spread = 50,
			Size = 0.3, Accel = V3(0, 1.2, 0) })
	end,
}

Details.MoneyCrab = {
	Post = function(t)
		for i = 1, 4 do
			Kit.VCyl(t.model, t.root, "CoinStack", 0.2 * t.k, 0.95 * t.k, CF(t.P(1.5 + (i % 2) * 0.06, 0.1 + 0.2 * (i - 1), -1.7)),
				Kit.Gold, "Accent")
		end
		Kit.Emitter(t.body, { Name = "CoinSparkle", Color = C(255, 230, 120), Rate = 3, Life = 0.9, Speed = 0.6, Size = 0.3,
			Rot = 60 })
	end,
}

Details.GhostCaptain = {
	Post = function(t)
		local cage = t.add(t.find("Hand", "R"), "Lantern", "Block", V3(0.55, 0.7, 0.55), V3(2.67, 2.5, -0.1),
			C(230, 255, 220), "Glass", Glass)
		cage.Transparency = 0.4
		t.add(cage, "LanternCap", "Block", V3(0.64, 0.15, 0.64), V3(2.67, 2.92, -0.1), C(60, 50, 40), "Accent")
		local core = t.add(cage, "LanternFlame", "Ball", V3(0.36, 0.36, 0.36), V3(2.67, 2.5, -0.1), C(210, 255, 150), "Glow",
			Neon)
		Kit.Light(core, C(190, 255, 170), 8, 1.2)
		Kit.Emitter(t.body, { Name = "GhostWisps", Color = C(150, 255, 210), Rate = 3, Life = 1.3, Speed = 0.4, Size = 0.35,
			Accel = V3(0, 1, 0), Transp = 0.5 })
	end,
}

Details.ToiletHead = {
	Pre = function(t)
		-- the cistern belongs to the toilet, not the head poking out of it
		for _, n in { "Tank", "TankLid", "Flush", "Lid", "Seat", "Water" } do
			local p = t.find(n)
			if p then
				t.parent[p] = t.body
			end
		end
	end,
	Post = function(t)
		local lid = t.find("Lid")
		if lid then
			lid.Color = C(250, 252, 255)
			lid.Reflectance = 0.35
		end
		t.add(lid, "LidHinge", "Cyl", V3(1.8, 0.22, 0.22), V3(0, 3.05, 0.9), Kit.Gold, "Accent")
		diamond(t, lid, "LidGlint", 0.38, V3(0.85, 5.3, 0.77), C(255, 255, 255), "Glow", Neon)
		local stick = t.add(t.root, "Plunger", "Block", V3(0.15, 1.5, 0.15), V3(1.7, 0.95, 0.4), C(170, 120, 70), "Accent")
		t.add(stick, "PlungerCup", "Block", V3(0.6, 0.35, 0.6), V3(1.7, 0.18, 0.4), C(220, 40, 50), "Accent")
	end,
}

Details.SneakerShark = {
	Pre = function(t)
		for _, p in t.model:GetChildren() do
			if p:IsA("BasePart") and p.Name == "Sole" then
				p.Material = Neon
				p.Color = C(90, 255, 220)
				p:SetAttribute("Role", "Glow")
			end
		end
	end,
	Post = function(t)
		local bar = t.add(t.body, "Shades", "Block", V3(1.9, 0.12, 0.12), V3(0, 4.15, -1.55), C(30, 30, 40), "Accent")
		for _, s in { -1, 1 } do
			local lens = t.add(bar, "ShadesLens", "Block", V3(0.62, 0.34, 0.1), V3(s * 0.5, 4.08, -1.62), C(25, 25, 35),
				"Accent")
			lens.Reflectance = 0.3
		end
	end,
}

Details.CappuccinoBallerina = {
	Post = function(t)
		local band = t.add(t.find("Cup") or t.body, "Tiara", "Block", V3(1.2, 0.2, 0.14), V3(0, 6.72, -0.9), Kit.Gold, "Accent")
		diamond(t, band, "TiaraGem", 0.32, V3(0, 6.95, -0.92), C(255, 110, 190), "Glow", Neon)
		local foam = t.find("Foam") or t.body
		Kit.Emitter(foam, { Name = "Steam", Color = C(255, 255, 255), Rate = 3, Life = 1.4, Speed = 0.6, Spread = 15,
			Size = 0.4, Light = 0, Transp = 0.55, Accel = V3(0, 1, 0) })
	end,
}

Details.WoodenDrummer = {
	Post = function(t)
		local drum = Kit.VCyl(t.model, t.root, "Drum", 1.2 * t.k, 1.6 * t.k, CF(t.P(0, 0.6, -1.55)), C(215, 55, 55), "Accent")
		Kit.VCyl(t.model, drum, "DrumRim", 0.16 * t.k, 1.7 * t.k, CF(t.P(0, 1.16, -1.55)), Kit.Gold, "Accent")
		Kit.VCyl(t.model, drum, "DrumSkin", 0.08 * t.k, 1.62 * t.k, CF(t.P(0, 1.23, -1.55)), C(250, 245, 230), "Accent")
		Kit.Pipe(t.model, t.find("Hand", "L") or t.body, "DrumStick", t.P(-1.5, 2.58, 0), t.P(-0.55, 1.45, -1.25), 0.2 * t.k,
			C(200, 160, 110), "Accent")
	end,
}

Details.CrocBomber = {
	Post = function(t)
		for i, side in { "L", "R" } do
			local prop = t.find("Prop", side)
			if not prop then
				continue
			end
			local hub = Kit.Add(t.model, t.find("Engine", side) or t.body, "Spinner" .. i, "Block", V3(0.3, 0.3, 0.2) * t.k,
				CF(prop.Position + V3(0, 0, -0.06 * t.k)), C(255, 200, 40), "Accent", nil, prop.Position)
			Kit.Add(t.model, hub, "PropBlade", "Block", V3(prop.Size.Y, prop.Size.X, prop.Size.Z), prop.CFrame, prop.Color,
				"Accent")
			-- re-hang the original blade on the spinning hub
			local old = prop:FindFirstChildOfClass("Motor6D")
			if old then
				old:Destroy()
			end
			Kit.Joint(hub, prop, prop.Name)
			local engine = t.find("Engine", side)
			if engine then
				Kit.Emitter(engine, { Name = "Exhaust", Color = C(255, 220, 90), Color2 = C(255, 90, 30), Rate = 5, Life = 0.3,
					Speed = 2, Spread = 10, Size = 0.4, Texture = Kit.FireTexture })
			end
		end
	end,
}

Details.HeadbandRookie = {
	Post = function(t)
		local base = CF(t.P(0, 3.05, 0.8)) * ANG(0, 0, rad(35))
		local scroll = Kit.Add(t.model, t.body, "Scroll", "Cyl", V3(1.7, 0.45, 0.45) * t.k, base, C(240, 225, 180), "Accent")
		for _, s in { -1, 1 } do
			Kit.Add(t.model, scroll, "ScrollCap", "Cyl", V3(0.16, 0.55, 0.55) * t.k, base * CF(s * 0.85 * t.k, 0, 0),
				C(220, 60, 50), "Accent")
		end
	end,
}

Details.RamenNinja = {
	Post = function(t)
		local noodles = t.find("Noodles") or t.body
		Kit.VCyl(t.model, noodles, "Fishcake", 0.08 * t.k, 0.36 * t.k, CF(t.P(1.22, 3.52, 1.3)), C(255, 215, 230), "Accent")
		Kit.Emitter(noodles, { Name = "Steam", Color = C(255, 255, 255), Rate = 3, Life = 1.2, Speed = 0.6, Spread = 15,
			Size = 0.3, Light = 0, Transp = 0.55, Accel = V3(0, 1, 0) })
	end,
}

Details.BigSwordBoy = {
	Pre = function(t)
		-- an even HUGER sword: blade and edge grow 25% away from the guard
		local guard = t.find("Guard")
		if not guard then
			return
		end
		for _, n in { "Blade", "Edge" } do
			local p = t.find(n)
			if p then
				t.parent[p] = guard
				local s = p.Size
				local axisLocal, len
				if s.Y >= s.X and s.Y >= s.Z then
					axisLocal, len = V3(0, 1, 0), s.Y
				elseif s.X >= s.Z then
					axisLocal, len = V3(1, 0, 0), s.X
				else
					axisLocal, len = V3(0, 0, 1), s.Z
				end
				local axis = p.CFrame:VectorToWorldSpace(axisLocal)
				local dir = (p.Position - guard.Position):Dot(axis) >= 0 and 1 or -1
				p.Size = s + axisLocal * len * 0.25
				p.CFrame = p.CFrame + axis * dir * len * 0.125
			end
		end
	end,
	Post = function(t)
		diamond(t, t.find("Guard"), "SwordGem", 0.36, V3(0.28, 2.61, 0.42), C(255, 50, 80), "Glow", Neon)
		local blade = t.find("Blade")
		if blade then
			Kit.Emitter(blade, { Name = "SwordGlint", Color = C(220, 240, 255), Rate = 3, Life = 0.6, Speed = 0.3, Size = 0.3,
				Rot = 90 })
		end
	end,
}

Details.SpikyHairPrince = {
	Post = function(t)
		local ball = t.add(t.find("Hand", "R"), "KiBall", "Ball", V3(0.75, 0.75, 0.75), V3(1.45, 1.75, -0.5),
			C(110, 200, 255), "Glow", Neon)
		Kit.Light(ball, C(110, 200, 255), 8, 1.5)
		Kit.Emitter(ball, { Name = "KiSparks", Color = C(180, 230, 255), Rate = 6, Life = 0.5, Speed = 1.2, Size = 0.18 })
		Kit.Emitter(t.body, { Name = "PowerAura", Color = C(255, 230, 90), Rate = 3, Life = 1, Speed = 0.3, Size = 0.45,
			Accel = V3(0, 2.5, 0), Transp = 0.4 })
	end,
}

Details.OnePunchBald = {
	Post = function(t)
		if t.head then
			t.head.Reflectance = 0.2
		end
		local glove = t.find("Glove", "R")
		for _, o in { V3(0.75, 0.45, 0), V3(0.55, -0.55, 0.2), V3(-0.1, 0.85, 0.25) } do
			diamond(t, glove, "PunchSpark", 0.42, V3(1.85, 5.0, 2.34) + o, C(255, 235, 80), "Glow", Neon)
		end
	end,
}

Details.MultiverseEgg = {
	Pre = function(t)
		orbitize(t, "Orbit")
	end,
	Post = function(t)
		local gem = diamond(t, t.find("Crown"), "CrownGem", 0.5, V3(0, 8.3, -1.18), C(0, 255, 170), "Glow", Neon)
		Kit.Light(gem, C(0, 255, 170), 9, 1.2)
	end,
}

Details.GrandpaOfAll = {
	Post = function(t)
		local head = t.head or t.body
		Kit.Add(t.model, head, "Orbit1", "Ball", V3(0.6, 0.6, 0.6) * t.k, CF(t.P(2.1, 8.1, 0)), C(255, 150, 60), "Glow", Neon,
			t.P(0, 8.1, 0))
		Kit.Add(t.model, head, "Orbit2", "Ball", V3(0.45, 0.45, 0.45) * t.k, CF(t.P(-2.0, 7.3, 0.4)), C(120, 200, 255), "Glow",
			Neon, t.P(0, 7.3, 0))
		local orb = t.find("StaffOrb")
		if orb then
			Kit.Light(orb, C(0, 255, 200), 10, 1.4)
		end
	end,
}

Details.GlitchTwin = {
	Pre = function(t)
		orbitize(t, "GlitchCube")
	end,
}

-- ===================================================================== conversion

local function pickBody(parts: { BasePart }): BasePart
	for _, name in BODY_PRIORITY do
		for _, p in parts do
			if p.Name == name then
				return p
			end
		end
	end
	local best = parts[1]
	for _, p in parts do
		if p.Name ~= "Head" and (best.Name == "Head" or volume(p) > volume(best)) then
			best = p
		end
	end
	return best
end

local function assignRoles(parts: { BasePart }, body: BasePart)
	local clusters: { { c: Color3, v: number } } = {}
	local plain = {}
	for _, p in parts do
		local role
		if EYE_NAMES[p.Name] then
			role = "Eye"
		elseif FACE_NAMES[p.Name] then
			role = "Face"
		elseif p.Material == Neon then
			role = "Glow"
		elseif p.Material == Glass and p ~= body then
			role = "Glass"
		end
		if role then
			p:SetAttribute("Role", role)
			continue
		end
		table.insert(plain, p)
		local hit = nil
		for _, cl in clusters do
			if colorDist(cl.c, p.Color) < 0.14 then
				hit = cl
				break
			end
		end
		if hit then
			hit.v += volume(p)
		else
			table.insert(clusters, { c = p.Color, v = volume(p) })
		end
	end
	table.sort(clusters, function(a, b)
		return a.v > b.v
	end)
	local main, belly = clusters[1], clusters[2]
	for _, p in plain do
		local role = "Accent"
		if main and colorDist(main.c, p.Color) < 0.14 then
			role = "Main"
		elseif belly and colorDist(belly.c, p.Color) < 0.14 then
			role = "Belly"
		end
		p:SetAttribute("Role", role)
	end
	body:SetAttribute("Role", "Main")
end

function Template.Build(ctx, templateName: string): boolean
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("CharacterModels")
	local src = folder and folder:FindFirstChild(templateName)
	if not src or not src:IsA("Model") then
		return false
	end
	local clone = src:Clone()
	local parts: { BasePart } = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Root" or d.Name == "HumanoidRootPart" then
				d:Destroy()
			else
				table.insert(parts, d)
			end
		end
	end
	if #parts == 0 then
		clone:Destroy()
		return false
	end
	parts = thin(parts)

	-- bounds -> offset + scale
	local lo, hi = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, p in parts do
		local a, b = extents(p)
		lo = V3(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z))
		hi = V3(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z))
	end
	local size = hi - lo
	local k = math.min(TARGET_H / math.max(size.Y, 0.1), MAX_W / math.max(size.X, size.Z, 0.1))
	local offset = V3((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local model, root = ctx.model, ctx.root
	for _, p in parts do
		for _, d in p:GetDescendants() do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") or d:IsA("LuaSourceContainer") then
				d:Destroy()
			elseif d:IsA("SpecialMesh") then
				d.Offset *= k
			elseif d:IsA("Attachment") then
				d.Position *= k
			end
		end
		local rot = p.CFrame.Rotation
		p.Size *= k
		p.CFrame = CF((p.Position - offset) * k) * rot
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = math.max(p.Size.X, p.Size.Y, p.Size.Z) > 0.7
		p.Parent = model
	end
	clone:Destroy()
	local H = size.Y * k

	-- ---------------------------------------------------------------- grouping
	local body = pickBody(parts)
	body.Name = "Body"
	local head: BasePart? = nil
	for _, p in parts do
		if p.Name == "Head" and p ~= body then
			head = p
			break
		end
	end
	local cx = body.Position.X
	local function sideOf(p: BasePart): string
		return p.Position.X < cx and "L" or "R"
	end

	local group: { [BasePart]: BasePart } = {} -- member -> main
	local mains: { { part: BasePart, parent: BasePart, pivot: Vector3 } } = {}
	local isMain: { [BasePart]: boolean } = { [body] = true }
	table.insert(mains, { part = body, parent = root, pivot = V3(body.Position.X, extents(body).Y, body.Position.Z) })

	-- legs
	local legs = {}
	for _, p in parts do
		if p.Name == "Leg" then
			table.insert(legs, p)
		end
	end
	table.sort(legs, function(a, b)
		return a.Position.X < b.Position.X
	end)
	if #legs == 2 then
		legs[1].Name, legs[2].Name = "LegL", "LegR"
	elseif #legs == 4 then
		for _, l in legs do
			l.Name = "Leg" .. (l.Position.Z < body.Position.Z and "F" or "B") .. sideOf(l)
		end
	end
	for _, l in legs do
		isMain[l] = true
		table.insert(mains, { part = l, parent = root, pivot = topEnd(l) })
	end
	if #legs > 0 then
		for _, p in parts do
			if LEG_NAMES[p.Name] and not isMain[p] then
				local best, bd = nil, math.huge
				for _, l in legs do
					local d = V3(p.Position.X - l.Position.X, 0, p.Position.Z - l.Position.Z).Magnitude
					if d < bd then
						best, bd = l, d
					end
				end
				group[p] = best
			end
		end
	end

	-- arms
	local width = math.max(size.X * k, 0.1)
	for _, side in { "L", "R" } do
		local cands = {}
		for _, p in parts do
			if ARM_NAMES[p.Name] and not isMain[p] and not group[p] and sideOf(p) == side
				and math.abs(p.Position.X - cx) > width * 0.05 then
				table.insert(cands, p)
			end
		end
		local main: BasePart? = nil
		for _, want in { "Arm", "Hand", "Claw", "Glove" } do
			for _, p in cands do
				if p.Name == want and (not main or p.Position.Y > main.Position.Y) then
					main = p
				end
			end
			if main then
				break
			end
		end
		if main then
			local shoulder: BasePart? = nil
			for _, p in cands do
				if p.Name == "Shoulder" then
					shoulder = p
				end
			end
			local pivot = shoulder and shoulder.Position or nearEnd(main, body.Position)
			main.Name = "Arm" .. side
			isMain[main] = true
			table.insert(mains, { part = main, parent = body, pivot = pivot })
			for _, p in cands do
				if p ~= main then
					group[p] = main
				end
			end
		end
	end

	-- head + face
	if head then
		isMain[head] = true
		local hlo, hhi = extents(head)
		table.insert(mains, { part = head, parent = body, pivot = V3(head.Position.X, hlo.Y, head.Position.Z) })
		local hc, hh = head.Position, (hhi - hlo) / 2
		local headMax = math.max(hh.X, hh.Y, hh.Z) * 2
		for _, p in parts do
			if isMain[p] or group[p] then
				continue
			end
			-- unnamed head-wear (hats, halos, crowns): small parts sitting on the upper half of the head
			local q, s = p.Position, p.Size
			local onTop = q.Y >= hc.Y and q.Y <= hhi.Y + hh.Y * 0.9 and math.abs(q.X - hc.X) <= hh.X * 1.3
				and math.abs(q.Z - hc.Z) <= hh.Z * 1.15 and math.max(s.X, s.Y, s.Z) <= headMax * 1.2
			if EYE_NAMES[p.Name] or FACE_NAMES[p.Name] or HEAD_NAMES[p.Name] or onTop then
				group[p] = head
			end
		end
	else
		for _, p in parts do
			if not isMain[p] and not group[p] and (EYE_NAMES[p.Name] or FACE_NAMES[p.Name]) then
				group[p] = body
			end
		end
	end

	-- ground decorations stay planted; everything else joins the nearest group
	local onRoot: { [BasePart]: boolean } = {}
	for _, p in parts do
		if isMain[p] or group[p] then
			continue
		end
		local plo, phi = extents(p)
		if plo.Y < H * 0.12 and phi.Y < H * 0.35 then
			onRoot[p] = true
		end
	end
	for _, p in parts do
		if isMain[p] or group[p] or onRoot[p] then
			continue
		end
		local q = p.Position
		local bodyD = boxDistance(q, body)
		local best, bd = body, bodyD
		for member, main in group do
			local d = boxDistance(q, member)
			if d < bd - 0.05 then
				best, bd = main, d
			end
		end
		for _, m in mains do
			local d = boxDistance(q, m.part)
			if d < bd - 0.05 then
				best, bd = m.part, d
			end
		end
		group[p] = best
	end

	assignRoles(parts, body)

	-- L/R eye names (the animator blinks EyeL/EyeR/PupilL/...), glossy eyes
	local faceX = (head or body).Position.X
	for _, p in parts do
		if SIDED_EYES[p.Name] then
			p.Name ..= (p.Position.X < faceX and "L" or "R")
		end
		if p:GetAttribute("Role") == "Eye" and p.Material ~= Neon then
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = math.max(p.Reflectance, 0.12)
		end
	end

	local t: T = {
		model = model,
		ctx = ctx,
		k = k,
		body = body,
		head = head,
		root = root,
		P = function(x, y, z)
			return (V3(x, y, z) - offset) * k
		end,
		S = function(x, y, z)
			return V3(x, y, z) * k
		end,
		find = function(name, side)
			for _, p in model:GetChildren() do
				if p:IsA("BasePart") and p.Name == name and (side == nil or sideOf(p) == side) then
					return p
				end
			end
			return nil
		end,
		add = function(attach, name, shape, sz, pos, color, role, mat, rot)
			local cf = CF((pos - offset) * k) * (rot or CF())
			return Kit.Add(model, attach or body, name, shape, sz * k, cf, color, role, mat)
		end,
		parent = {},
		pivot = {},
	}
	local details = Details[templateName]
	if details and details.Pre then
		details.Pre(t)
	end

	-- ---------------------------------------------------------------- joints
	for _, m in mains do
		Kit.Joint(m.parent, m.part, m.part.Name, t.pivot[m.part] or m.pivot)
	end
	for _, p in parts do
		if isMain[p] or not p.Parent then
			continue
		end
		local p0 = t.parent[p] or (onRoot[p] and root) or group[p] or body
		Kit.Joint(p0, p, p.Name, t.pivot[p])
	end

	-- extra eye shine where the template has none
	for _, side in { "L", "R" } do
		local eye = model:FindFirstChild("Eye" .. side)
		if eye and eye:IsA("BasePart") and eye.Material ~= Neon and not model:FindFirstChild("Shine" .. side) then
			local ref = model:FindFirstChild("Pupil" .. side)
			local r: BasePart = (ref and ref:IsA("BasePart")) and ref or eye
			local d = math.max(eye.Size.X, eye.Size.Y) * 0.26
			local pos = r.Position + V3(eye.Size.X * 0.18, eye.Size.Y * 0.22, -(r.Size.Z / 2 + d * 0.2))
			local shine = Kit.Add(model, group[eye] or body, "Shine" .. side, "Ball", V3(d, d, d), CF(pos), Kit.White, "Eye", Neon)
			shine.CastShadow = false
		end
	end

	if details and details.Post then
		details.Post(t)
	end
	Kit.Brickify(model)

	ctx.Body = body
	ctx.Head = head or body
	ctx.Radius = math.clamp(math.max(size.X, size.Z) * k * 0.4, 1.3, 2.4)
	ctx.TopCount = 1
	-- already crowned / haloed characters skip the Divine flair halo
	ctx.HasHalo = model:FindFirstChild("Halo") ~= nil or model:FindFirstChild("Crown") ~= nil
	ctx.Template = templateName
	return true
end

return Template

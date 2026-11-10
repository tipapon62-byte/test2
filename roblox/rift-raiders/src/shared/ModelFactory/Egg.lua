-- Toy-brick eggs: a stack of studded square slabs stepping in and out like a LEGO egg, chunky biome
-- tiles on the faces, and rarity bling (neon trim, gold corner posts + gold cap, peeking eyes, halo).
-- "Body" (the widest slab) is jointed to Root at the egg's bottom so the animator can rock it around its
-- base; every other slab is named "Shell" and hangs off Body (the client places hatch cracks on them).

local GameConfig = require(script.Parent.Parent.GameConfig)
local Kit = require(script.Parent.Style)
local Mutation = require(script.Parent.Mutation)

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local C = Color3.fromRGB
local Neon = Enum.Material.Neon

local Egg = {}

local H = 3.4 -- Normal egg height
-- { width, bottom, top }
local SLABS = {
	{ 1.7, 0.0, 0.45 },
	{ 2.3, 0.45, 1.15 },
	{ 2.6, 1.15, 2.05 },
	{ 2.3, 2.05, 2.7 },
	{ 1.8, 2.7, 3.1 },
	{ 1.1, 3.1, H },
}
local BODY_SLAB = 3
local FACE_DIRS = { V3(0, 0, -1), V3(1, 0, 0), V3(0, 0, 1), V3(-1, 0, 0) }

-- Flat tile on one side face of a slab. u, v in -1..1 across the face; face 1 = front (-Z), then clockwise.
local function tile(model, slab: BasePart, name: string, face: number, u: number, v: number, size: Vector3, color: Color3,
	role: string, mat: Enum.Material?, spin: number?, shape: string?): BasePart
	local n = FACE_DIRS[face]
	local hs = slab.Size / 2
	local tangent = V3(-n.Z, 0, n.X)
	local pos = slab.Position + n * (hs.X + size.Z / 2 - 0.04) + tangent * (u * hs.X) + V3(0, v * hs.Y, 0)
	local p = Kit.Add(model, slab, name, shape or "Block", size, CFrame.lookAt(pos, pos + n) * ANG(0, 0, spin or 0), color,
		role, mat)
	p.CastShadow = false
	return p
end

local function recolor(slab: BasePart, color: Color3)
	slab.Color = color
	slab:SetAttribute("Role", "Accent")
end

local Patterns = {}

function Patterns.Spots(model, sl, _base, pat)
	local sq = V3(0.55, 0.55, 0.12)
	for _, t in { { 2, 1, -0.4, 0 }, { 3, 2, 0.35, 0.1 }, { 4, 3, -0.25, 0 }, { 3, 4, -0.3, -0.1 }, { 2, 3, 0.4, 0 },
		{ 4, 1, 0.4, 0 } } do
		tile(model, sl[t[1]], "Spot", t[2], t[3], t[4], sq, pat, "Accent")
	end
	tile(model, sl[3], "Spot", 1, -0.1, 0, V3(0.32, 0.32, 0.12), Kit.Lighter(pat, 0.35), "Accent")
end

function Patterns.Leaves(model, sl, _base, pat)
	for i, t in { { 2, 1, -0.3 }, { 3, 2, 0.2 }, { 4, 3, -0.2 }, { 3, 4, 0.3 }, { 2, 3, 0.35 }, { 4, 1, 0.3 } } do
		tile(model, sl[t[1]], "Leaf", t[2], t[3], 0, V3(0.45, sl[t[1]].Size.Y * 0.9, 0.12), pat, "Accent", nil,
			rad(i % 2 == 0 and 30 or -30))
	end
	local top = sl[6]
	for _, s in { -1, 1 } do
		local base = CF(top.Position + V3(0, top.Size.Y / 2, 0)) * ANG(0, 0, -s * rad(40))
		Kit.Add(model, top, "Sprout", "Block", V3(0.3, 0.65, 0.12), base * CF(0, 0.3, 0), Kit.Lighter(pat, 0.25), "Accent")
	end
end

function Patterns.Waves(model, sl, base, pat)
	recolor(sl[2], pat)
	recolor(sl[4], pat)
	recolor(sl[6], Kit.Lighter(pat, 0.3))
	for face = 1, 4 do
		tile(model, sl[3], "Bubble", face, (face % 2 == 0) and 0.35 or -0.35, 0.1, V3(0.32, 0.32, 0.12), Kit.Lighter(base, 0.6),
			"Belly")
	end
end

function Patterns.Stripes(_model, sl, base, pat)
	recolor(sl[2], pat)
	recolor(sl[4], pat)
	recolor(sl[6], pat)
	sl[1].Color = Kit.Darker(base, 0.15)
end

function Patterns.Vines(model, sl, base, pat)
	local vine = Kit.Darker(base, 0.3)
	for face = 1, 4 do
		tile(model, sl[3], "Vine", face, (face % 2 == 0) and 0.3 or -0.3, 0, V3(0.2, 0.85, 0.12), vine, "Accent", nil,
			rad(face % 2 == 0 and 25 or -25))
	end
	for _, f in { { 2, 1, 0.35 }, { 4, 3, -0.3 } } do
		local petal = tile(model, sl[f[1]], "Flower", f[2], f[3], 0, V3(0.48, 0.48, 0.12), pat, "Accent", nil, rad(45))
		Kit.Add(model, petal, "FlowerCore", "Block", V3(0.2, 0.2, 0.1), petal.CFrame * CF(0, 0, -0.08), C(255, 225, 80),
			"Accent")
	end
end

function Patterns.Cracks(model, sl, _base, pat)
	for _, face in { 1, 3 } do
		for i, si in { 4, 3, 2 } do
			tile(model, sl[si], "Crack", face, (i % 2 == 0) and 0.12 or -0.1, 0, V3(0.15, sl[si].Size.Y * 0.95, 0.1), pat,
				"Glow", Neon, rad(i % 2 == 0 and 35 or -35))
		end
	end
	Kit.Light(sl[BODY_SLAB], pat, 8, 1.2)
end

function Patterns.Crystals(model, sl, _base, pat)
	local top = sl[6]
	local tall = Kit.Add(model, top, "Crystal", "Block", V3(0.45, 1.0, 0.45), CF(top.Position + V3(0, 0.55, 0)) * ANG(0, rad(45), 0),
		pat, "Accent", Enum.Material.Glass)
	local shards = { tall }
	for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 } } do
		local pos = V3(c[1] * 1.2, 1.75, c[2] * 1.2)
		table.insert(shards, Kit.Add(model, sl[BODY_SLAB], "Crystal", "Block", V3(0.36, 0.9, 0.36),
			CF(pos) * ANG(c[2] * rad(-25), rad(45), c[1] * rad(-25)), pat, "Accent", Enum.Material.Glass))
	end
	for _, s in shards do
		s.Transparency = 0.15
		s.Reflectance = 0.2
	end
	tile(model, sl[2], "Frost", 1, -0.3, 0, V3(0.5, 0.4, 0.12), Kit.White, "Belly")
	tile(model, sl[4], "Frost", 3, 0.3, 0, V3(0.5, 0.4, 0.12), Kit.White, "Belly")
end

function Patterns.Stars(model, sl, _base, pat)
	for _, t in { { 2, 1, -0.35, 0.45 }, { 3, 2, 0.3, 0.5 }, { 4, 3, -0.2, 0.4 }, { 3, 4, -0.3, 0.45 }, { 3, 1, 0.4, 0.38 } } do
		local slab = sl[t[1]]
		tile(model, slab, "Star", t[2], t[3], 0, V3(t[4], t[4], 0.1), pat, "Glow", Neon, rad(45))
	end
	tile(model, sl[4], "Dot", 1, 0.45, 0.3, V3(0.16, 0.16, 0.1), Kit.White, "Glow", Neon)
	tile(model, sl[2], "Dot", 3, -0.4, -0.2, V3(0.16, 0.16, 0.1), Kit.White, "Glow", Neon)
end

-- Mythic/Divine: a dark crack with two eyes peeking out.
local function peek(model, slab: BasePart)
	local slit = tile(model, slab, "Peek", 1, 0, 0, V3(1.1, 0.4, 0.12), Kit.Ink, "Face")
	for _, s in { -1, 1 } do
		local side = s < 0 and "L" or "R"
		local cf = slit.CFrame * CF(s * 0.22, 0, -0.06)
		local eye = Kit.Add(model, slit, "Eye" .. side, "Ball", V3(0.3, 0.3, 0.3), cf, Kit.White, "Eye")
		eye.Reflectance = 0.12
		Kit.Add(model, slit, "Pupil" .. side, "Ball", V3(0.17, 0.17, 0.17), cf * CF(-s * 0.02, -0.02, -0.11), Kit.Ink, "Eye")
	end
end

function Egg.Build(biomeId: string, rarity: string, opts): Model
	opts = opts or {}
	local biome = GameConfig.GetBiome(biomeId) or GameConfig.Biomes[1]
	local r = GameConfig.Rarities.ById[rarity] or GameConfig.Rarities.ById.Common
	local idx = r.Index
	local base, pat = biome.EggColors[1], biome.EggColors[2] or Kit.Darker(biome.EggColors[1], 0.3)
	if idx >= 7 then
		base, pat = C(255, 250, 228), C(255, 205, 80)
	end

	local model, root = Kit.NewModel((string.gsub(biome.EggName or "Egg", " ", "")))
	local bs = SLABS[BODY_SLAB]
	local body = Kit.Add(model, root, "Body", "Block", V3(bs[1], bs[3] - bs[2], bs[1]), CF(0, (bs[2] + bs[3]) / 2, 0), base,
		"Main", nil, V3(0, 0, 0))
	local sl = {}
	for i, s in SLABS do
		sl[i] = i == BODY_SLAB and body
			or Kit.Add(model, body, "Shell", "Block", V3(s[1], s[3] - s[2], s[1]), CF(0, (s[2] + s[3]) / 2, 0), base, "Main")
	end

	local pattern = Patterns[biome.EggPattern] or Patterns.Spots
	pattern(model, sl, base, pat)

	if idx >= 3 then
		local trim = Kit.Add(model, body, "RarityBand", "Block", V3(2.7, 0.16, 2.7), CF(0, SLABS[BODY_SLAB][3], 0), r.Color, "Fx",
			Neon)
		trim.CastShadow = false
	end
	if idx >= 4 then
		Kit.Light(body, r.Color, 6 + (idx - 4) * 2.5, 0.8 + (idx - 4) * 0.35)
	end
	if idx >= 5 then
		recolor(sl[6], Kit.Gold)
		for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
			Kit.Add(model, body, "GoldPost", "Block", V3(0.5, 1.0, 0.5), CF(c[1] * 1.2, body.Position.Y, c[2] * 1.2), Kit.Gold,
				"Accent")
		end
		Kit.Emitter(body, { Name = "RaritySparkle", Color = Kit.Lighter(r.Color, 0.3), Rate = 2 + (idx - 5) * 2,
			Life = 0.9, Speed = 0.6, Size = 0.32, Rot = 60 })
	end
	if idx >= 6 then
		peek(model, sl[4])
	end
	if idx >= 7 then
		local centre = CF(0, H + 0.55, 0) * ANG(rad(-10), 0, 0)
		Kit.Ring(model, body, "Halo", centre, 0.8, 0.16, 0.16, 5, C(255, 228, 120), "Fx", Neon)
		Kit.Emitter(body, { Name = "DivineRays", Color = C(255, 245, 200), Color2 = C(255, 210, 90), Rate = 5, Life = 1.3,
			Speed = 0.2, Spread = 0, Size = 0.45, Accel = V3(0, 2.5, 0), Transp = 0.3 })
	end
	Kit.Brickify(model)

	local size = opts.Size or "Normal"
	local sizeCfg = GameConfig.Rarities.Sizes[size] or GameConfig.Rarities.Sizes.Normal
	model:SetAttribute("Biome", biome.Id)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Size", size)
	model:SetAttribute("Archetype", "Egg")
	Mutation.Apply(model, opts.Mutation)
	if sizeCfg.Scale ~= 1 then
		model:ScaleTo(sizeCfg.Scale)
	end
	model:SetAttribute("Height", H * sizeCfg.Scale)
	return model
end

return Egg

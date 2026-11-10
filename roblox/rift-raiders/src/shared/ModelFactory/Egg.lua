-- Procedural eggs: glossy ellipsoid shell + biome pattern + rarity flair (+ peeking eyes for Mythic/Divine).
-- "Body" is jointed to Root at the egg's bottom so the animator can rock it around its base.

local GameConfig = require(script.Parent.Parent.GameConfig)
local Kit = require(script.Parent.Style)
local Mutation = require(script.Parent.Mutation)

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local C = Color3.fromRGB

local Egg = {}

local W, H = 2.6, 3.4 -- Normal egg width/height
local CY = H / 2

local function dir(thetaDeg: number, e: number): Vector3
	local t = rad(thetaDeg)
	return V3(math.sin(t), e, -math.cos(t))
end

-- radius of the shell at height y (for bands)
local function radiusAt(y: number): number
	local k = (y - CY) / CY
	return W / 2 * math.sqrt(math.max(0, 1 - k * k))
end

local function band(model, body, name, y, thick, color, role, mat)
	local b = Kit.VCyl(model, body, name, thick, radiusAt(y) * 2 + 0.08, CF(0, y, 0), color, role, mat)
	b.CastShadow = false
	return b
end

local function decal(model, body, name, shape, size, d, color, role, mat, spin)
	local cf = Kit.Facing(body, d, 0.03) * ANG(0, 0, spin or 0)
	local p = Kit.Add(model, body, name, shape, size, cf, color, role, mat)
	p.CastShadow = false
	return p
end

local Patterns = {}

function Patterns.Spots(model, body, base, pat)
	for _, s in { { 0, 0.25, 0.8 }, { 75, -0.25, 0.62 }, { 150, 0.45, 0.58 }, { 220, -0.1, 0.75 }, { 290, 0.35, 0.52 },
		{ 35, -0.65, 0.48 }, { 0, 1, 0.6 } } do
		decal(model, body, "Spot", "Ell", V3(s[3], s[3] * 0.82, 0.18), dir(s[1], s[2]), pat, "Accent")
	end
	decal(model, body, "Spot", "Ell", V3(0.32, 0.28, 0.14), dir(320, -0.4), Kit.Lighter(pat, 0.35), "Accent")
end

function Patterns.Leaves(model, body, base, pat)
	for _, l in { { 0, 0.15, 20 }, { 60, -0.35, -30 }, { 120, 0.35, 15 }, { 180, -0.1, -20 }, { 240, 0.4, 30 },
		{ 300, -0.3, -15 } } do
		decal(model, body, "Leaf", "Ell", V3(0.6, 1.05, 0.16), dir(l[1], l[2]), pat, "Accent", nil, rad(l[3]))
	end
	-- little sprout on top
	local top = Kit.OnSurface(body, V3(0, 1, 0), 0.1)
	for _, s in { -1, 1 } do
		Kit.Stick(model, body, "Sprout", "Ell", V3(0.4, 0.7, 0.12), top * ANG(0, 0, -s * rad(45)), Kit.Lighter(pat, 0.2),
			"Accent", nil, 0.05)
	end
end

function Patterns.Waves(model, body, base, pat, mid)
	band(model, body, "Wave", 0.85, 0.34, pat, "Accent")
	band(model, body, "Wave", 2.55, 0.3, pat, "Accent")
	if not mid then
		band(model, body, "Wave", CY, 0.2, Kit.Lighter(pat, 0.4), "Accent")
	end
	for _, b in { { 30, 0.15, 0.32 }, { 140, -0.05, 0.26 }, { 250, 0.2, 0.3 }, { 320, 0.6, 0.22 } } do
		decal(model, body, "Bubble", "Ball", V3(b[3], b[3], b[3]), dir(b[1], b[2]), Kit.Lighter(base, 0.6), "Belly")
	end
end

function Patterns.Stripes(model, body, base, pat, mid)
	band(model, body, "Stripe", 0.7, 0.3, pat, "Accent")
	band(model, body, "Stripe", 1.12, 0.18, Kit.Darker(pat, 0.15), "Accent")
	band(model, body, "Stripe", 2.3, 0.28, pat, "Accent")
	band(model, body, "Stripe", 2.72, 0.16, Kit.Darker(pat, 0.15), "Accent")
	if not mid then
		band(model, body, "Stripe", CY, 0.22, Kit.Lighter(pat, 0.25), "Accent")
	end
end

function Patterns.Vines(model, body, base, pat)
	local vine = Kit.Darker(base, 0.25)
	for _, v in { { 0, 0.4, 25 }, { 15, -0.2, -20 }, { 120, 0.3, -25 }, { 135, -0.3, 20 }, { 240, 0.35, 25 },
		{ 255, -0.25, -25 } } do
		decal(model, body, "Vine", "Ell", V3(0.18, 1.3, 0.12), dir(v[1], v[2]), vine, "Accent", nil, rad(v[3]))
	end
	for _, f in { { 330, 0.1 }, { 190, 0.45 } } do
		local petal = decal(model, body, "Flower", "Ball", V3(0.5, 0.5, 0.5), dir(f[1], f[2]), pat, "Accent")
		Kit.Add(model, petal, "FlowerCore", "Ball", V3(0.22, 0.22, 0.22), petal.CFrame * CF(0, 0, -0.2), C(255, 225, 80),
			"Accent")
	end
end

function Patterns.Cracks(model, body, base, pat)
	for _, line in { { 0, 10 }, { 140, -8 }, { 250, 6 } } do
		local e = 0.75
		local th = line[1]
		for i = 1, 3 do
			decal(model, body, "Crack", "Block", V3(0.13, 0.62, 0.1), dir(th, e), pat, "Glow", Enum.Material.Neon,
				rad(i % 2 == 0 and 35 or -35))
			e -= 0.42
			th += line[2]
		end
	end
	Kit.Light(body, pat, 8, 1.2)
end

function Patterns.Crystals(model, body, base, pat)
	for _, c in { { 0, 0.55, 0.9 }, { 90, 0.1, 0.75 }, { 180, 0.45, 0.85 }, { 270, -0.1, 0.7 }, { 45, -0.45, 0.55 } } do
		local f = Kit.OnSurface(body, dir(c[1], c[2]), 0.05) * ANG(0, rad(45), 0)
		local shard = Kit.Stick(model, body, "Crystal", "Block", V3(0.36, c[3], 0.36), f, pat, "Accent", Enum.Material.Glass,
			0.22)
		shard.Transparency = 0.15
		shard.Reflectance = 0.2
	end
	for _, s in { { 200, -0.4 }, { 320, 0.2 }, { 120, -0.5 } } do
		decal(model, body, "Frost", "Ell", V3(0.55, 0.42, 0.14), dir(s[1], s[2]), Kit.White, "Belly")
	end
end

function Patterns.Stars(model, body, base, pat)
	for _, s in { { 0, 0.3, 0.5 }, { 70, -0.2, 0.42 }, { 140, 0.5, 0.38 }, { 200, -0.35, 0.48 }, { 270, 0.25, 0.4 },
		{ 330, -0.55, 0.32 } } do
		local cf = Kit.Facing(body, dir(s[1], s[2]), 0.02)
		local st = Kit.Diamond(model, body, "Star", s[3], 0.1, cf, pat, "Glow", Enum.Material.Neon)
		st.CastShadow = false
	end
	for _, s in { { 35, 0.6 }, { 110, 0.05 }, { 235, -0.05 }, { 300, 0.65 } } do
		decal(model, body, "Dot", "Ball", V3(0.16, 0.16, 0.16), dir(s[1], s[2]), Kit.White, "Glow", Enum.Material.Neon)
	end
end

-- Mythic/Divine: a dark crack with two eyes peeking out.
local function peek(model, body)
	local cf = Kit.Facing(body, V3(0, 0.55, -1), 0.02)
	local slit = Kit.Add(model, body, "Peek", "Ell", V3(1.0, 0.4, 0.22), cf, Kit.Ink, "Face")
	slit.CastShadow = false
	for _, s in { -1, 1 } do
		local side = s < 0 and "L" or "R"
		Kit.Add(model, slit, "Eye" .. side, "Ball", V3(0.3, 0.3, 0.3), cf * CF(s * 0.2, -0.01, -0.06), Kit.White, "Eye")
		Kit.Add(model, slit, "Pupil" .. side, "Ball", V3(0.17, 0.17, 0.17), cf * CF(s * 0.19, -0.03, -0.17), Kit.Ink, "Eye")
		for i, off in { { 0.62, 0.05, 40 } } do
			local crack = Kit.Add(model, slit, "CrackLine", "Block", V3(0.07, 0.42, 0.06),
				cf * CF(s * off[1], off[2] + (i - 1) * 0.06, 0.0) * ANG(0, 0, s * rad(off[3])), Kit.Ink, "Face")
			crack.CastShadow = false
		end
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
	local body = Kit.Add(model, root, "Body", "Ell", V3(W, H, W), CF(0, CY, 0), base, "Main", nil, V3(0, 0, 0))
	body.Reflectance = 0.04

	local pattern = Patterns[biome.EggPattern] or Patterns.Spots
	pattern(model, body, base, pat, idx >= 3)
	Kit.Gloss(model, body, V3(-0.5, 0.55, -0.7))

	if idx >= 3 then
		local b = band(model, body, "RarityBand", CY, 0.24, r.Color, "Fx", Enum.Material.Neon)
		b.Transparency = 0.05
	end
	if idx >= 4 then
		Kit.Light(body, r.Color, 6 + (idx - 4) * 2.5, 0.8 + (idx - 4) * 0.35)
	end
	if idx >= 5 then
		Kit.Emitter(body, { Name = "RaritySparkle", Color = Kit.Lighter(r.Color, 0.3), Rate = 2 + (idx - 5) * 2,
			Life = 0.9, Speed = 0.6, Size = 0.32, Rot = 60 })
	end
	if idx >= 6 then
		peek(model, body)
	end
	if idx >= 7 then
		local centre = CF(0, H + 0.55, 0) * ANG(rad(-10), 0, 0)
		Kit.Ring(model, body, "Halo", centre, 0.85, 0.16, 0.16, 6, C(255, 228, 120), "Fx", Enum.Material.Neon)
		Kit.Emitter(body, { Name = "DivineRays", Color = C(255, 245, 200), Color2 = C(255, 210, 90), Rate = 5, Life = 1.3,
			Speed = 0.2, Spread = 0, Size = 0.45, Accel = V3(0, 2.5, 0), Transp = 0.3 })
	end

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

-- Nest guardians: the mothers of each biome's nest, built as toy-brick BOSSES from the pet archetypes
-- (ctx.G = true: bulky boss proportions, angry brows, glowing eyes) plus a boss kit shared by every
-- biome (roaring mouth with fangs, gold crown, gold cuffs, spiky shoulder pads) and biome-themed extras.
-- Scaled so the model is exactly Biome.Guardian.Size studs tall.

local GameConfig = require(script.Parent.Parent.GameConfig)
local Kit = require(script.Parent.Style)
local Pet = require(script.Parent.Pet)

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local C = Color3.fromRGB

local Guardian = {}

local function B(ctx, attach, name, size, cf, color, role, mat)
	return Kit.Add(ctx.model, attach, name, "Block", size, cf, color, role, mat)
end

-- Thin neon crack laid flat on a part's surface.
local function crack(ctx, part, d, len, spin, color)
	local p = Kit.Add(ctx.model, part, "LavaCrack", "Block", V3(0.16, len, 0.1),
		Kit.Facing(part, d, 0.02) * ANG(0, 0, rad(spin)), color, "Glow", Enum.Material.Neon)
	p.CastShadow = false
	return p
end

local function find(ctx, name): BasePart?
	local p = ctx.model:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- ===================================================================== boss kit

-- Wedge turned to face the viewer; tipDown flips it so the point hangs down (upper fangs).
local function fangRot(s: number, tipDown: boolean): CFrame
	local r = ANG(0, s < 0 and math.pi / 2 or -math.pi / 2, 0)
	return tipDown and r * ANG(math.pi, 0, 0) or r
end

-- Big open roaring mouth: dark red inside, tongue, teeth row, upper + lower fangs.
local function bossMouth(ctx)
	local part = ctx.MouthPart or ctx.Head
	local onHead = part == ctx.Head
	local ps = part.Size
	local w = ps.X * (onHead and 0.58 or 0.72)
	local h = ps.Y * (onHead and 0.34 or 0.66)
	local y = onHead and (-ps.Y / 2 + h / 2 + ps.Y * 0.08) or -ps.Y * 0.04
	local cf = part.CFrame * CF(0, y, -ps.Z / 2)
	local m = ctx.model
	local mouth = Kit.Add(m, part, "Mouth", "Block", V3(w, h, 0.16), cf * CF(0, 0, -0.03), C(120, 15, 30), "Face")
	Kit.Add(m, mouth, "Tongue", "Block", V3(w * 0.55, h * 0.3, 0.1), cf * CF(0, -h * 0.3, -0.09), C(235, 90, 110), "Face")
	Kit.Add(m, mouth, "Teeth", "Block", V3(w * 0.9, h * 0.16, 0.1), cf * CF(0, h * 0.42, -0.09), Kit.Ivory, "Face")
	local lower = ctx.Jaw or mouth
	for _, s in { -1, 1 } do
		Kit.Add(m, mouth, "Fang", "Wedge", V3(0.12, h * 0.5, w * 0.17), cf * CF(s * w * 0.32, h * 0.17, -0.13)
			* fangRot(s, true), Kit.Ivory, "Face")
		Kit.Add(m, lower, "Fang", "Wedge", V3(0.12, h * 0.38, w * 0.14), cf * CF(s * w * 0.2, -h * 0.31, -0.13)
			* fangRot(s, false), Kit.Ivory, "Face")
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Fang" or d.Name == "Teeth" or d.Name == "Tongue") then
			d.CastShadow = false
		end
	end
end

local function bossCrown(ctx)
	local head = ctx.Head
	local hs = head.Size
	local top = (head.CFrame * CF(0, hs.Y / 2, 0)).Position
	local w = math.min(hs.X, hs.Z) * 0.62
	local m = ctx.model
	local band = Kit.Add(m, head, "BossCrown", "Block", V3(w, 0.5, w), CF(top + V3(0, 0.22, 0)), Kit.Gold, "Accent")
	for _, p in { { -0.36, -1 }, { 0, -1 }, { 0.36, -1 }, { -0.25, 1 }, { 0.25, 1 } } do
		local spike = Kit.Diamond(m, band, "CrownSpike", 0.44, 0.16, CF(top + V3(p[1] * w, 0.64, p[2] * (w / 2 - 0.08))),
			Kit.Gold, "Accent")
		spike.CastShadow = false
	end
	local gem = Kit.Diamond(m, band, "CrownGem", 0.34, 0.14, CF(top + V3(0, 0.22, -w / 2 - 0.05)), C(255, 40, 70), "Glow",
		Enum.Material.Neon)
	gem.CastShadow = false
end

local function bossCuffs(ctx)
	local gold = Kit.Gold
	local pairsToTry = { { "HandL", "HandR", "top" }, { "LegFL", "LegFR", "ankle" }, { "LegL", "LegR", "ankle" },
		{ "Seg1", "Seg2", "mid" } }
	for _, pr in pairsToTry do
		local a, b = find(ctx, pr[1]), find(ctx, pr[2])
		if a and b then
			for _, p in { a, b } do
				local s = p.Size
				local y = pr[3] == "top" and s.Y / 2 or (pr[3] == "ankle" and -s.Y / 2 + 0.45 or 0)
				B(ctx, p, "Cuff", V3(s.X * 1.12, 0.5, s.Z * 1.12), CF(p.Position + V3(0, y, 0)), gold, "Accent")
			end
			return
		end
	end
end

local function bossShoulders(ctx)
	if ctx.Arch == "Serpent" then
		return
	end
	local dark = Kit.Darker(ctx.P, 0.4)
	for _, s in { -1, 1 } do
		local arm = find(ctx, "Arm" .. (s < 0 and "L" or "R"))
		local attach, top, pw, pd
		if ctx.Arch == "Golem" and arm then
			attach, pw, pd = arm, arm.Size.X * 1.4, arm.Size.Z * 1.4
			top = arm.Position + V3(0, arm.Size.Y / 2, 0)
		else
			attach, pw, pd = ctx.Body, ctx.Body.Size.X * 0.42, ctx.Body.Size.Z * 0.32
			top = Kit.Surface(ctx.Body, V3(s * 0.7, 1, -0.6))
		end
		local pad = B(ctx, attach, "ShoulderPad", V3(pw, 0.5, pd), CF(top + V3(0, 0.1, 0)), dark, "Accent")
		local padTop = top + V3(0, 0.35, 0)
		for _, z in { -0.22, 0.22 } do
			local base = CF(padTop + V3(s * pw * 0.12, 0, z * pd)) * ANG(0, 0, -s * rad(25)) * ANG(0, s * math.pi / 2, 0)
			Kit.Stick(ctx.model, pad, "ShoulderSpike", "Wedge", V3(0.32, 1.0, 0.75), base, dark, "Accent", nil, 0.12)
		end
	end
end

-- ===================================================================== biome themes

local Themes = {}

Themes.RiftLab = {
	Features = { "Goggles" },
	S = C(225, 235, 245),
	Extra = function(ctx)
		local body, glow = ctx.Body, ctx.Glow
		B(ctx, body, "Belt", V3(3.3, 0.36, 2.3), body.CFrame * CF(0, -1.0, 0), C(255, 200, 40), "Accent")
		local tank = Kit.VCyl(ctx.model, body, "Tank", 1.7, 1.1, body.CFrame * CF(0, 0.2, 1.6), C(210, 240, 255), "Glass",
			Enum.Material.Glass)
		tank.Transparency = 0.45
		Kit.VCyl(ctx.model, tank, "TankFluid", 1.25, 0.9, body.CFrame * CF(0, 0.05, 1.6), glow, "Glow", Enum.Material.Neon)
		for _, s in { -1, 1 } do
			Kit.Pipe(ctx.model, body, "Tube", body.CFrame * V3(s * 0.35, 1.0, 1.6), V3(s * 1.9, 3.95, 0.3), 0.24, glow, "Glow",
				Enum.Material.Neon)
		end
	end,
}

Themes.Mosswood = {
	Features = { "Antlers", "Leaves" },
	AntlerColor = C(170, 128, 82),
	Extra = function(ctx)
		local moss = ctx.Glow
		for i, sp in ctx.Spine do
			B(ctx, sp[1], "Moss", V3(1.3 - i * 0.12, 0.35, 1.1), Kit.OnSurface(sp[1], sp[2], 0.1), Kit.Darker(moss, 0.1 * i),
				"Belly")
		end
		local snout = find(ctx, "Snout") or ctx.Head
		B(ctx, snout, "Beard", V3(1.2, 0.8, 0.5), snout.CFrame * CF(0, -snout.Size.Y / 2 - 0.3, -0.05), moss, "Belly")
		for _, n in { "LegFL", "LegFR", "LegBL", "LegBR" } do
			local leg = find(ctx, n)
			if leg then
				B(ctx, leg, "MossBand", V3(leg.Size.X * 1.12, 0.34, leg.Size.Z * 1.12), leg.CFrame * CF(0, 0.15, 0), moss,
					"Belly")
			end
		end
		-- a red toadstool growing on her back
		local base = Kit.OnSurface(ctx.Body, V3(0.45, 1, 0.35), 0.05)
		local stem = Kit.Stick(ctx.model, ctx.Body, "Shroom", "Block", V3(0.28, 0.5, 0.28), base, Kit.Ivory, "Face")
		B(ctx, stem, "ShroomCap", V3(0.8, 0.36, 0.8), base * CF(0, 0.55, 0), C(230, 60, 60), "Accent")
	end,
}

Themes.GlimmerLake = {
	Features = { "Fins", "Horns" },
	S = C(170, 230, 250),
	Extra = function(ctx)
		local glow = ctx.Glow
		for _, i in { 1, 3 } do
			local sp = ctx.Spine[i]
			Kit.Add(ctx.model, sp[1], "Fin", "Wedge", V3(0.18, 0.85, 1.1), Kit.OnSurface(sp[1], sp[2], 0.2) * CF(0, 0.42, 0),
				ctx.A, "Accent")
		end
		for _, s in { -1, 1 } do
			local p = Kit.Surface(ctx.Head, V3(s * 0.55, -0.3, -0.9))
			local w = Kit.Add(ctx.model, ctx.Head, "Whisker", "Ell", V3(0.12, 0.12, 1.6),
				CF(p) * ANG(rad(15), s * rad(35), 0) * CF(0, 0, 0.1), glow, "Glow", Enum.Material.Neon, p)
			w.CastShadow = false
		end
		for _, sp in ctx.Spine do
			for _, s in { -1, 1 } do
				local dot = Kit.Add(ctx.model, sp[1], "GlowSpot", "Block", V3(0.3, 0.3, 0.12),
					Kit.Facing(sp[1], V3(s, 0.1, 0.2), 0.04), glow, "Glow", Enum.Material.Neon)
				dot.CastShadow = false
			end
		end
		Kit.Emitter(ctx.Head, { Name = "Bubbles", Color = Kit.Lighter(glow, 0.5), Rate = 3, Life = 1.6, Speed = 1,
			Spread = 40, Size = 0.3, Accel = V3(0, 1.5, 0) })
	end,
}

Themes.Sunscorch = {
	Features = { "Plates", "Horns" },
	S = C(255, 235, 190),
	A = C(215, 120, 55),
	PlateColor = C(235, 170, 85),
	HornColor = C(130, 80, 40),
	Extra = function(ctx)
		local body = ctx.Body
		for i, a in { 0, 120, 240 } do
			local ar = rad(a + 30)
			local d = V3(math.sin(ar), 0.8, -math.cos(ar))
			Kit.Stick(ctx.model, body, "SandPlate", "Block", V3(0.22, 0.75, 0.7), Kit.OnSurface(body, d, 0.05),
				i % 2 == 0 and ctx.PlateColor or Kit.Darker(ctx.PlateColor, 0.15), "Accent", nil, 0.2)
		end
		local tail = ctx.Tail
		if tail then
			local prev = tail
			for i = 1, 2 do
				prev = B(ctx, prev, "Rattle", V3(0.5 - i * 0.08, 0.45 - i * 0.06, 0.42),
					tail.CFrame * CF(0, 0, tail.Size.Z / 2 + 0.15 + (i - 1) * 0.38), C(240, 215, 160), "Accent")
			end
		end
		Kit.Emitter(body, { Name = "Dust", Color = C(240, 210, 150), Rate = 4, Life = 1.2, Speed = 0.8, Spread = 70,
			Size = 0.5, Light = 0, Transp = 0.5 })
	end,
}

Themes.Vinewild = {
	Features = { "Spikes", "Flower", "Leaves" },
	S = C(190, 230, 150),
	SpikeColor = C(30, 75, 35),
	LeafColor = C(80, 170, 70),
	Extra = function(ctx)
		local tip = find(ctx, "TailTip")
		if tip then
			Kit.Stick(ctx.model, tip, "Thorn", "Wedge", V3(0.22, 0.6, 0.55), Kit.OnSurface(tip, V3(0, 1, 0.2), 0.05),
				ctx.SpikeColor, "Accent", nil, 0.1)
		end
		for i, a in { 25, -25 } do
			B(ctx, ctx.Body, "Vine", V3(ctx.Body.Size.X * 1.06, 0.24, ctx.Body.Size.Z * 1.06),
				ctx.Body.CFrame * CF(0, (i - 1.5) * 0.7, 0) * ANG(0, 0, rad(a)), C(45, 110, 50), "Accent")
		end
		for _, n in { "FootL", "FootR" } do
			local foot = find(ctx, n)
			if foot then
				for _, x in { -0.25, 0.25 } do
					local claw = Kit.Add(ctx.model, foot, "Claw", "Wedge", V3(0.16, 0.32, 0.34),
						foot.CFrame * CF(x, 0.0, -foot.Size.Z / 2 - 0.05) * ANG(0, math.pi, 0), Kit.Ivory, "Face")
					claw.CastShadow = false
				end
			end
		end
	end,
}

Themes.Emberpeak = {
	Features = { "Horns", "Flame", "Spikes" },
	S = C(85, 70, 80),
	SpikeColor = C(70, 55, 60),
	HornColor = C(60, 50, 55),
	EyeGlow = C(255, 190, 40),
	Extra = function(ctx)
		local lava = ctx.Glow
		for _, c in { { ctx.Body, V3(-1, 0.2, -0.3), 1.0, 30 }, { ctx.Body, V3(1, -0.1, -0.2), 0.9, -25 },
			{ ctx.Body, V3(-1, 0.4, 0.5), 0.8, -40 }, { ctx.Body, V3(1, 0.3, 0.6), 0.9, 35 },
			{ ctx.Head, V3(-1, 0.3, -0.2), 0.6, 20 }, { ctx.Head, V3(1, 0.3, -0.1), 0.55, -30 } } do
			crack(ctx, c[1], c[2], c[3], c[4], lava)
		end
		if ctx.Tail then
			crack(ctx, ctx.Tail, V3(0, 1, 0.1), 0.9, 15, lava)
		end
		Kit.Emitter(ctx.Body, { Name = "Embers", Color = C(255, 200, 80), Color2 = C(255, 60, 20), Rate = 6, Life = 1.2,
			Speed = 1.5, Spread = 50, Size = 0.25, Accel = V3(0, 3, 0) })
	end,
}

Themes.Frostveil = {
	Features = { "Crystal", "Tusks", "Horns" },
	S = C(245, 250, 255),
	CrystalColor = C(170, 220, 255),
	HornColor = C(235, 245, 255),
	EyeGlow = C(90, 220, 255),
	Extra = function(ctx)
		local fur = C(250, 252, 255)
		for _, n in { "LegFL", "LegFR", "LegBL", "LegBR" } do
			local leg = find(ctx, n)
			if leg then
				B(ctx, leg, "Fur", V3(leg.Size.X * 1.25, 0.55, leg.Size.Z * 1.25), leg.CFrame * CF(0, -0.1, 0), fur, "Belly")
			end
		end
		local p = Kit.Surface(ctx.Body, V3(0, 0.3, -1))
		B(ctx, ctx.Body, "Mane", V3(2.4, 1.4, 0.8), CF(p + V3(0, 0.2, 0.2)), fur, "Belly")
		local snout = find(ctx, "Snout")
		if snout then
			for _, s in { -0.3, 0.3 } do
				local sp = Kit.Surface(snout, V3(s, -1, -0.3))
				local ice = Kit.Add(ctx.model, snout, "Icicle", "Wedge", V3(0.14, 0.5, 0.28),
					CF(sp + V3(0, -0.2, 0)) * ANG(math.pi, 0, 0), C(200, 235, 255), "Glow", Enum.Material.Glass)
				ice.Transparency = 0.2
			end
		end
		Kit.Emitter(ctx.Body, { Name = "Snow", Color = Kit.White, Rate = 4, Life = 1.6, Speed = 0.6, Spread = 90,
			Size = 0.22, Light = 0.3, Accel = V3(0, -1, 0) })
	end,
}

Themes.AstralRuins = {
	Features = { "Runes", "Stars", "Crystal" },
	S = C(90, 80, 140),
	Extra = function(ctx)
		local glow = ctx.Glow
		for _, n in { "ArmL", "ArmR" } do
			local arm = find(ctx, n)
			if arm then
				local r = Kit.Diamond(ctx.model, arm, "Rune", 0.55, 0.08, Kit.Facing(arm, V3(0, 0.2, -1), 0.01), glow, "Glow",
					Enum.Material.Neon)
				r.CastShadow = false
			end
		end
		Kit.Emitter(ctx.Body, { Name = "Stardust", Color = Kit.White, Color2 = glow, Rate = 5, Life = 1.5, Speed = 0.4,
			Size = 0.25, Rot = 90 })
	end,
}

function Guardian.Build(biomeId: string): Model
	local biome = GameConfig.GetBiome(biomeId) or GameConfig.Biomes[1]
	local g = biome.Guardian
	local P, glow = g.Colors[1], g.Colors[2] or Kit.Lighter(g.Colors[1], 0.5)
	local theme = Themes[biome.Id] or { Features = { "Spikes" } }
	local features = {}
	for _, f in theme.Features do
		features[f] = true
	end
	local model, root = Kit.NewModel(g.Name)
	local ctx: any = {
		model = model,
		root = root,
		P = P,
		S = theme.S or Kit.Lighter(P, 0.35),
		A = theme.A or glow,
		Glow = glow,
		EyeGlow = theme.EyeGlow or C(255, 60, 50),
		F = features,
		Arch = g.Archetype,
		G = true,
		AntlerColor = theme.AntlerColor,
		HornColor = theme.HornColor,
		SpikeColor = theme.SpikeColor,
		PlateColor = theme.PlateColor,
		CrystalColor = theme.CrystalColor,
		LeafColor = theme.LeafColor or (biome.Id == "Mosswood" and glow or nil),
		PetalColor = biome.Id == "Vinewild" and glow or nil,
		-- the crown owns the head top: head-top features move to the sides / back / tail
		TopCount = 1,
	}
	Pet.Assemble(ctx)
	bossMouth(ctx)
	bossCrown(ctx)
	bossCuffs(ctx)
	bossShoulders(ctx)
	if theme.Extra then
		theme.Extra(ctx)
	end
	Kit.Light(ctx.Body, glow, 12, 1)
	Kit.Brickify(model)

	local height = Kit.TopY(model)
	local scale = g.Size / math.max(height, 0.1)
	model:ScaleTo(scale)
	model:SetAttribute("Biome", biome.Id)
	model:SetAttribute("Archetype", g.Archetype)
	model:SetAttribute("GuardianName", g.Name)
	model:SetAttribute("Height", g.Size)
	return model
end

return Guardian

-- Nest guardians: big "mama/boss" versions of each biome's creature, built from the pet archetypes
-- with ctx.G = true (bulkier body, angry brows, glowing slit eyes, fangs) plus biome-themed extras.
-- Scaled so the model is exactly Biome.Guardian.Size studs tall.

local GameConfig = require(script.Parent.Parent.GameConfig)
local Kit = require(script.Parent.Style)
local Pet = require(script.Parent.Pet)

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local C = Color3.fromRGB

local Guardian = {}

local function E(ctx, attach, name, size, cf, color, role, mat)
	return Kit.Add(ctx.model, attach, name, "Ell", size, cf, color, role, mat)
end

-- Thin neon crack laid flat on a part's surface.
local function crack(ctx, part, d, len, spin, color)
	local p = Kit.Add(ctx.model, part, "LavaCrack", "Block", V3(0.14, len, 0.1),
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

local Themes = {}

Themes.RiftLab = {
	Variant = "LabDome",
	Features = { "Antenna" },
	S = C(225, 235, 245),
	Extra = function(ctx)
		local body, glow = ctx.Body, ctx.Glow
		Kit.Add(ctx.model, body, "Belt", "Block", V3(2.7, 0.32, 2.0), body.CFrame * CF(0, -0.75, 0), C(255, 200, 40),
			"Accent")
		local tank = Kit.VCyl(ctx.model, body, "Tank", 1.7, 1.05, CF(0, 2.4, 1.45), C(210, 240, 255), "Glass",
			Enum.Material.Glass)
		tank.Transparency = 0.45
		Kit.VCyl(ctx.model, tank, "TankFluid", 1.25, 0.85, CF(0, 2.25, 1.45), glow, "Glow", Enum.Material.Neon)
		for _, s in { -1, 1 } do
			Kit.Pipe(ctx.model, body, "Tube", V3(s * 0.35, 3.0, 1.45), V3(s * 1.45, 3.05, 0.35), 0.22, glow, "Glow",
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
			E(ctx, sp[1], "Moss", V3(1.3 - i * 0.12, 0.35, 1.1), Kit.OnSurface(sp[1], sp[2], 0.1), Kit.Darker(moss, 0.1 * i),
				"Belly")
		end
		local p = Kit.Surface(ctx.Head, V3(0, -0.8, -0.55))
		E(ctx, ctx.Head, "Beard", V3(0.95, 0.85, 0.55), CF(p + V3(0, -0.2, 0)), moss, "Belly")
		for _, n in { "LegFL", "LegFR", "LegBL", "LegBR" } do
			local leg = find(ctx, n)
			if leg then
				E(ctx, leg, "MossBand", V3(leg.Size.X * 1.12, 0.32, leg.Size.Z * 1.12), leg.CFrame * CF(0, 0.05, 0), moss,
					"Belly")
			end
		end
		-- a tiny red mushroom growing on her back
		local base = Kit.OnSurface(ctx.Body, V3(0.45, 0.9, 0.35), 0.05)
		local stem = Kit.Stick(ctx.model, ctx.Body, "Shroom", "Ell", V3(0.25, 0.5, 0.25), base, Kit.Ivory, "Face")
		E(ctx, stem, "ShroomCap", V3(0.7, 0.38, 0.7), base * CF(0, 0.5, 0), C(230, 60, 60), "Accent")
	end,
}

Themes.GlimmerLake = {
	Features = { "Fins", "Horns" },
	S = C(170, 230, 250),
	Extra = function(ctx)
		local glow = ctx.Glow
		for _, i in { 1, 3 } do
			local sp = ctx.Spine[i]
			Kit.Add(ctx.model, sp[1], "Fin", "Wedge", V3(0.16, 0.85, 1.1), Kit.OnSurface(sp[1], sp[2], 0.2) * CF(0, 0.42, 0),
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
				local dot = Kit.Add(ctx.model, sp[1], "GlowSpot", "Ball", V3(0.28, 0.28, 0.28),
					Kit.Facing(sp[1], V3(s, 0.1, 0.2), 0.08), glow, "Glow", Enum.Material.Neon)
				dot.CastShadow = false
			end
		end
		Kit.Emitter(ctx.Head, { Name = "Bubbles", Color = Kit.Lighter(glow, 0.5), Rate = 3, Life = 1.6, Speed = 1,
			Spread = 40, Size = 0.3, Accel = V3(0, 1.5, 0) })
	end,
}

Themes.Sunscorch = {
	Features = { "Crown", "Plates", "Horns" },
	S = C(255, 235, 190),
	A = C(215, 120, 55),
	PlateColor = C(235, 170, 85),
	HornColor = C(130, 80, 40),
	Extra = function(ctx)
		local body = ctx.Body
		for i, a in { 0, 120, 240 } do
			local ar = rad(a + 30)
			local d = V3(math.sin(ar), 0.8, -math.cos(ar))
			Kit.Stick(ctx.model, body, "SandPlate", "Ell", V3(0.2, 0.75, 0.7), Kit.OnSurface(body, d, 0.05),
				i % 2 == 0 and ctx.PlateColor or Kit.Darker(ctx.PlateColor, 0.15), "Accent", nil, 0.2)
		end
		local tail = ctx.Tail
		if tail then
			local prev = tail
			for i = 1, 2 do
				prev = E(ctx, prev, "Rattle", V3(0.5 - i * 0.08, 0.45 - i * 0.06, 0.45),
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
			Kit.Stick(ctx.model, tip, "Thorn", "Wedge", V3(0.2, 0.6, 0.55), Kit.OnSurface(tip, V3(0, 1, 0.2), 0.05),
				ctx.SpikeColor, "Accent", nil, 0.1)
		end
		Kit.Stick(ctx.model, ctx.Head, "Thorn", "Wedge", V3(0.24, 0.8, 0.7), Kit.OnSurface(ctx.Head, V3(0, 0.8, 0.7), 0.05),
			ctx.SpikeColor, "Accent", nil, 0.1)
		for i, a in { 25, -25 } do
			E(ctx, ctx.Body, "Vine", V3(ctx.Body.Size.X * 1.06, 0.22, ctx.Body.Size.Z * 1.06),
				ctx.Body.CFrame * CF(0, (i - 1.5) * 0.7, 0) * ANG(0, 0, rad(a)), C(45, 110, 50), "Accent")
		end
		for _, n in { "FootL", "FootR" } do
			local foot = find(ctx, n)
			if foot then
				for _, x in { -0.22, 0.22 } do
					local claw = Kit.Add(ctx.model, foot, "Claw", "Wedge", V3(0.14, 0.3, 0.32),
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
	Extra = function(ctx)
		local lava = ctx.Glow
		for _, c in { { ctx.Body, V3(-0.8, 0.2, -0.5), 1.0, 30 }, { ctx.Body, V3(0.8, -0.1, -0.4), 0.9, -25 },
			{ ctx.Body, V3(-0.9, 0.4, 0.5), 0.8, -40 }, { ctx.Body, V3(0.9, 0.3, 0.6), 0.9, 35 },
			{ ctx.Head, V3(-0.7, 0.5, -0.2), 0.6, 20 }, { ctx.Head, V3(0.7, 0.4, -0.1), 0.55, -30 } } do
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
	Extra = function(ctx)
		local fur = C(250, 252, 255)
		for _, n in { "LegFL", "LegFR", "LegBL", "LegBR" } do
			local leg = find(ctx, n)
			if leg then
				E(ctx, leg, "Fur", V3(leg.Size.X * 1.25, 0.55, leg.Size.Z * 1.25), leg.CFrame * CF(0, -0.35, 0), fur, "Belly")
			end
		end
		local p = Kit.Surface(ctx.Body, V3(0, 0.3, -1))
		E(ctx, ctx.Body, "Mane", V3(2.3, 1.4, 0.9), CF(p + V3(0, 0.2, 0.15)), fur, "Belly")
		local snout = find(ctx, "Snout")
		if snout then
			for _, s in { -0.25, 0.25 } do
				local sp = Kit.Surface(snout, V3(s, -1, -0.3))
				local ice = Kit.Add(ctx.model, snout, "Icicle", "Wedge", V3(0.12, 0.45, 0.25),
					CF(sp + V3(0, -0.18, 0)) * ANG(math.pi, 0, 0), C(200, 235, 255), "Glow", Enum.Material.Glass)
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
				local r = Kit.Diamond(ctx.model, arm, "Rune", 0.5, 0.08, Kit.Facing(arm, V3(0, 0.2, -1), 0.01), glow, "Glow",
					Enum.Material.Neon)
				r.CastShadow = false
			end
		end
		-- floating crown of shards above the head
		local top = Kit.Surface(ctx.Head, V3(0, 1, 0))
		for i = 1, 3 do
			local a = (i - 2) * rad(35)
			local cf = CF(top + V3(math.sin(a) * 0.55, 0.75 + (i == 2 and 0.25 or 0), -math.cos(a) * 0.25)) * ANG(0, 0, -a)
			local shard = Kit.Add(ctx.model, ctx.Head, "ShardCrown", "Block", V3(0.28, i == 2 and 0.8 or 0.6, 0.28),
				cf * ANG(0, rad(45), 0), Kit.Lighter(glow, 0.3), "Glow", Enum.Material.Neon)
			shard.CastShadow = false
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
	local ctx = {
		model = model,
		root = root,
		P = P,
		S = theme.S or Kit.Lighter(P, 0.35),
		A = theme.A or glow,
		Glow = glow,
		F = features,
		Arch = g.Archetype,
		G = true,
		Variant = theme.Variant,
		AntlerColor = theme.AntlerColor,
		HornColor = theme.HornColor,
		SpikeColor = theme.SpikeColor,
		PlateColor = theme.PlateColor,
		CrystalColor = theme.CrystalColor,
		LeafColor = theme.LeafColor or (biome.Id == "Mosswood" and glow or nil),
		PetalColor = biome.Id == "Vinewild" and glow or nil,
	}
	Pet.Assemble(ctx)
	if theme.Extra then
		theme.Extra(ctx)
	end
	Kit.Light(ctx.Body, glow, 12, 1)

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

-- Procedural pets: 8 chunky-cute archetypes + composable features + rarity flair + tier badge.
-- Guardians reuse the same archetypes and features with ctx.G = true (bulkier, angry, glowing eyes).
--
-- ctx fields: model, root, P/S/A (primary, secondary/belly, accent colours), F (feature set),
--   Arch, G (guardian), Glow (Color3), Variant (guardian-specific body variant)
-- Archetype builders set: Body, Head, Tail?, Spine ({ {part, dir} } x3 for back features),
--   WingPart, FinPart, Radius (footprint for the rarity ring), FaceOpts, FacePart?

local GameConfig = require(script.Parent.Parent.GameConfig)
local Kit = require(script.Parent.Style)
local Mutation = require(script.Parent.Mutation)

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local C = Color3.fromRGB

local Pet = {}
local Arch = {}
local Feat = {}
Pet.Archetypes = Arch
Pet.Features = Feat

local function E(ctx, attach, name, size, cf, color, role, pivot, mat)
	return Kit.Add(ctx.model, attach, name, "Ell", size, cf, color, role, mat, pivot)
end

local function B(ctx, attach, name, size, cf, color, role, pivot, mat)
	return Kit.Add(ctx.model, attach, name, "Block", size, cf, color, role, mat, pivot)
end

local function sides()
	return { { -1, "L" }, { 1, "R" } }
end

-- Most-green / most-pink colour of the palette for leaves and petals.
local function pickColor(ctx, score, fallback: Color3): Color3
	local best, bestScore = fallback, 0.12
	for _, c in { ctx.A, ctx.S, ctx.P } do
		local s = score(c)
		if s > bestScore then
			best, bestScore = c, s
		end
	end
	return best
end

local function leafColor(ctx)
	return ctx.LeafColor or pickColor(ctx, function(c)
		return c.G - math.max(c.R, c.B)
	end, C(110, 200, 80))
end

local function petalColor(ctx)
	return ctx.PetalColor or pickColor(ctx, function(c)
		return (c.R + c.B) / 2 - c.G
	end, C(255, 130, 190))
end

-- Head-top slots: first claimer sits dead centre, later ones to the sides.
local TOP_DIRS = { V3(0, 1, -0.05), V3(0.55, 0.85, 0.05), V3(-0.55, 0.85, 0.05) }
local function topSlot(ctx): Vector3
	ctx.TopCount = (ctx.TopCount or 0) + 1
	return TOP_DIRS[math.min(ctx.TopCount, #TOP_DIRS)]
end

-- ===================================================================== archetypes

function Arch.Quadruped(ctx)
	local g, P, S = ctx.G, ctx.P, ctx.S
	local body = E(ctx, ctx.root, "Body", g and V3(2.7, 2.0, 3.2) or V3(2.3, 1.8, 2.7), CF(0, 1.6, 0.3), P, "Main",
		V3(0, 1.3, 0.3))
	E(ctx, body, "Belly", g and V3(2.2, 1.5, 2.8) or V3(1.8, 1.3, 2.2), CF(0, 1.32, 0.05), S, "Belly")
	local lw = g and 1.0 or 0.78
	local lx, lzF, lzB = g and 0.82 or 0.68, -0.7, g and 1.35 or 1.2
	for _, l in { { "LegFL", -lx, lzF }, { "LegFR", lx, lzF }, { "LegBL", -lx, lzB }, { "LegBR", lx, lzB } } do
		E(ctx, ctx.root, l[1], V3(lw, 1.2, lw), CF(l[2], 0.58, l[3]), Kit.Darker(P, 0.07), "Main",
			V3(l[2], 1.1, l[3]))
	end
	local headPos = g and V3(0, 2.75, -1.45) or V3(0, 2.8, -1.05)
	local head = E(ctx, body, "Head", g and V3(2.1, 1.75, 2.0) or V3(2.15, 1.95, 1.95), CF(headPos), P, "Main",
		headPos + V3(0, -0.55, 0.3))
	local snoutY = headPos.Y - 0.32
	local headFront = headPos.Z - head.Size.Z / 2
	local snout = E(ctx, head, "Snout", V3(1.15, 0.72, 0.62), CF(0, snoutY, headFront + 0.12), S, "Belly")
	Kit.Add(ctx.model, snout, "Nose", "Ball", V3(0.3, 0.3, 0.3), CF(0, snoutY + 0.18, headFront - 0.16), Kit.Ink,
		"Face")
	local tail
	if ctx.F.Tail then
		tail = E(ctx, body, "Tail", V3(0.95, 0.95, 1.6), CF(0, 2.3, 1.9) * ANG(rad(-50), 0, 0), P, "Main",
			V3(0, 1.85, 1.45))
		E(ctx, tail, "TailTip", V3(0.78, 0.78, 0.7), tail.CFrame * CF(0, 0, 0.72), S, "Belly")
	else
		tail = E(ctx, body, "Tail", V3(0.45, 0.45, 1.0), CF(0, 1.95, 1.8) * ANG(rad(-35), 0, 0), P, "Main",
			V3(0, 1.8, 1.45))
	end
	ctx.Body, ctx.Head, ctx.Tail = body, head, tail
	ctx.Spine = { { body, V3(0, 1, -0.45) }, { body, V3(0, 1, 0.05) }, { body, V3(0, 1, 0.5) } }
	ctx.WingPart, ctx.FinPart = body, head
	ctx.Radius = g and 1.9 or 1.65
	ctx.FaceOpts = { Spread = 0.44, EyeY = 0.2, MouthPart = snout, MouthDir = V3(0, -0.6, -1) }
	Kit.Gloss(ctx.model, head)
end

function Arch.Dino(ctx)
	local g, P, S = ctx.G, ctx.P, ctx.S
	local lean = ANG(rad(-12), 0, 0)
	local body = E(ctx, ctx.root, "Body", g and V3(2.6, 2.6, 2.8) or V3(2.3, 2.4, 2.5), CF(0, 2.0, 0.25) * lean, P,
		"Main", V3(0, 1.4, 0.3))
	E(ctx, body, "Belly", V3(1.75, 2.0, 1.35), CF(0, 1.85, -0.42) * lean, S, "Belly")
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		local x = s * (g and 0.9 or 0.8)
		local leg = E(ctx, ctx.root, "Leg" .. n, V3(1.0, 1.4, 1.2), CF(x, 0.85, 0.45), P, "Main", V3(x, 1.45, 0.45))
		E(ctx, leg, "Foot" .. n, V3(0.88, 0.42, 1.3), CF(x, 0.21, 0.15), Kit.Darker(P, 0.12), "Main")
		E(ctx, body, "Arm" .. n, V3(0.38, 0.38, 0.85), CF(s * 0.98, 2.15, -0.92) * ANG(rad(40), 0, 0), P, "Main",
			V3(s * 0.88, 2.4, -0.65))
	end
	local head = E(ctx, body, "Head", g and V3(2.2, 1.8, 2.5) or V3(2.2, 1.85, 2.3), CF(0, 3.4, -0.8), P, "Main",
		V3(0, 2.9, -0.35))
	local jaw = E(ctx, head, "Jaw", V3(1.7, 0.6, 1.95), CF(0, 2.75, -1.05), S, "Belly", V3(0, 2.9, -0.2))
	local tail = E(ctx, body, "Tail", V3(1.1, 1.0, 1.9), CF(0, 1.65, 1.75) * ANG(rad(15), 0, 0), P, "Main",
		V3(0, 1.8, 1.0))
	E(ctx, tail, "TailTip", V3(0.62, 0.55, 1.4), CF(0, 1.3, 2.95) * ANG(rad(10), 0, 0), P, "Main", V3(0, 1.4, 2.5))
	ctx.Body, ctx.Head, ctx.Tail, ctx.Jaw = body, head, tail, jaw
	ctx.Spine = { { body, V3(0, 1, -0.15) }, { body, V3(0, 0.85, 0.5) }, { tail, V3(0, 1, -0.1) } }
	ctx.WingPart, ctx.FinPart = body, head
	ctx.Radius = 1.7
	ctx.FaceOpts = { Spread = 0.42, EyeY = 0.32, MouthDir = V3(0, -0.45, -1) }
	Kit.Gloss(ctx.model, head)
end

function Arch.Bird(ctx)
	local P, S, A = ctx.P, ctx.S, ctx.A
	local body = E(ctx, ctx.root, "Body", V3(2.5, 2.3, 2.4), CF(0, 1.5, 0.15), P, "Main", V3(0, 0.9, 0.15))
	E(ctx, body, "Belly", V3(1.9, 1.7, 1.1), CF(0, 1.35, -0.78), S, "Belly")
	local head = E(ctx, body, "Head", V3(2.0, 1.85, 1.9), CF(0, 2.85, -0.3), P, "Main", V3(0, 2.2, -0.3))
	E(ctx, head, "Beak", V3(0.72, 0.42, 0.78), CF(0, 2.68, -1.36), A, "Accent")
	if ctx.F.Beak then
		E(ctx, head, "Jaw", V3(0.56, 0.26, 0.56), CF(0, 2.47, -1.24), Kit.Darker(A, 0.15), "Accent",
			V3(0, 2.6, -1.0))
	end
	local big = ctx.F.Wings
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		local pivot = V3(s * 1.08, 2.0, 0.2)
		if big then
			local w = E(ctx, body, "Wing" .. n, V3(0.3, 1.8, 2.2), CF(s * 1.45, 2.0, 0.45) * ANG(rad(15), 0, -s * rad(25)),
				P, "Main", pivot)
			E(ctx, w, "WingTip" .. n, V3(0.24, 1.0, 1.2), w.CFrame * CF(0, 0.45, 0.75), A, "Accent")
		else
			E(ctx, body, "Wing" .. n, V3(0.35, 1.2, 1.5), CF(s * 1.25, 1.6, 0.25) * ANG(0, 0, -s * rad(10)), P, "Main",
				pivot)
		end
		local leg = E(ctx, ctx.root, "Leg" .. n, V3(0.28, 0.62, 0.28), CF(s * 0.5, 0.36, 0.2), A, "Accent",
			V3(s * 0.5, 0.65, 0.2))
		E(ctx, leg, "Foot" .. n, V3(0.56, 0.18, 0.66), CF(s * 0.5, 0.09, 0.02), A, "Accent")
	end
	E(ctx, body, "Tail", V3(1.1, 0.25, 1.1), CF(0, 1.7, 1.45) * ANG(rad(-25), 0, 0), A, "Accent", V3(0, 1.6, 1.1))
	ctx.Body, ctx.Head = body, head
	ctx.Spine = { { body, V3(0, 1, 0.45) }, { body, V3(0, 0.8, 0.8) }, { head, V3(0, 1, 0.3) } }
	ctx.WingPart, ctx.FinPart = body, head
	ctx.Radius = 1.6
	ctx.FaceOpts = { Spread = 0.4, EyeY = 0.14, NoMouth = true }
	Kit.Gloss(ctx.model, head)
end

function Arch.Blob(ctx)
	local P, S = ctx.P, ctx.S
	local body = E(ctx, ctx.root, "Body", V3(3.1, 1.7, 2.9), CF(0, 0.85, 0), P, "Main", V3(0, 0, 0))
	local head = E(ctx, body, "Head", V3(2.75, 2.25, 2.55), CF(0, 1.9, -0.05), P, "Main", V3(0, 1.1, 0))
	E(ctx, body, "Belly", V3(2.0, 1.3, 1.0), CF(0, 0.9, -1.02), S, "Belly")
	for _, sd in sides() do
		E(ctx, body, "Foot" .. sd[2], V3(0.85, 0.42, 0.85), CF(sd[1] * 0.78, 0.2, -0.82), Kit.Darker(P, 0.08), "Main")
	end
	ctx.Body, ctx.Head = body, head
	ctx.Spine = { { head, V3(0, 1, -0.25) }, { head, V3(0, 0.9, 0.35) }, { head, V3(0, 0.6, 0.8) } }
	ctx.WingPart, ctx.FinPart = head, body
	ctx.Radius = 1.75
	ctx.FaceOpts = { Spread = 0.36, EyeY = 0.05, EyeScale = 0.4, MouthDir = V3(0, -0.38, -1) }
	Kit.Gloss(ctx.model, head)
end

function Arch.Serpent(ctx)
	local g, P, S = ctx.G, ctx.P, ctx.S
	local body = E(ctx, ctx.root, "Body", V3(2.9, 1.0, 2.9), CF(0, 0.5, 0.3), P, "Main", V3(0, 0, 0.3))
	local segs = {
		{ V3(1.4, 1.4, 1.4), V3(0, 1.15, -0.25), V3(0, 0.85, 0.0) },
		{ V3(1.25, 1.25, 1.25), V3(0, 1.85, -0.7), V3(0, 1.5, -0.5) },
		{ V3(1.1, 1.1, 1.1), V3(0, 2.45, -1.1), V3(0, 2.15, -0.9) },
	}
	local prev = body
	local spine = {}
	for i, sg in segs do
		local col = i % 2 == 0 and Kit.Lighter(P, 0.12) or P
		local seg = E(ctx, prev, "Seg" .. i, sg[1], CF(sg[2]), col, "Main", sg[3])
		E(ctx, seg, "Belly" .. i, V3(sg[1].X * 0.75, sg[1].Y * 0.8, 0.3), Kit.Facing(seg, V3(0, -0.15, -1), 0.1), S,
			"Belly")
		table.insert(spine, { seg, V3(0, 0.55, 1) })
		prev = seg
	end
	local head = E(ctx, prev, "Head", g and V3(1.9, 1.45, 2.4) or V3(1.8, 1.45, 2.1), CF(0, 3.05, -1.6), P, "Main",
		V3(0, 2.7, -1.25))
	local tail = E(ctx, body, "Tail", V3(0.6, 0.5, 1.6), CF(1.15, 0.35, 1.55) * ANG(0, rad(-40), 0), P, "Main",
		V3(0.7, 0.4, 1.0))
	ctx.Body, ctx.Head, ctx.Tail = body, head, tail
	ctx.Spine = spine
	ctx.WingPart, ctx.FinPart = spine[1][1], head
	ctx.Radius = 1.7
	ctx.FaceOpts = { Spread = 0.45, EyeY = 0.3, MouthDir = V3(0, -0.35, -1) }
	Kit.Gloss(ctx.model, head)
end

function Arch.Bug(ctx)
	local P, S = ctx.P, ctx.S
	local body = E(ctx, ctx.root, "Body", V3(2.3, 1.4, 2.6), CF(0, 1.2, 0.3), S, "Belly", V3(0, 0.8, 0.3))
	-- elytra halves double as "wings" so the animator can lift them
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		E(ctx, body, "Wing" .. n, V3(1.32, 1.5, 2.9), CF(s * 0.63, 1.65, 0.45), P, "Main", V3(s * 0.2, 2.0, -0.7))
	end
	local head = E(ctx, body, "Head", V3(1.9, 1.7, 1.7), CF(0, 1.75, -1.2), P, "Main", V3(0, 1.4, -0.7))
	for _, l in { { "LegFL", -1, -0.5 }, { "LegFR", 1, -0.5 }, { "LegML", -1, 0.3 }, { "LegMR", 1, 0.3 },
		{ "LegBL", -1, 1.1 }, { "LegBR", 1, 1.1 } } do
		local s = l[2]
		E(ctx, ctx.root, l[1], V3(1.2, 0.28, 0.28), CF(s * 1.3, 0.55, l[3]) * ANG(0, 0, -s * rad(50)),
			Kit.Darker(P, 0.25), "Main", V3(s * 0.85, 0.95, l[3]))
	end
	local wl, wr = ctx.model:FindFirstChild("WingL"), ctx.model:FindFirstChild("WingR")
	ctx.Body, ctx.Head = body, head
	ctx.Spine = { { wl, V3(0.2, 1, -0.3) }, { wr, V3(-0.2, 1, 0.1) }, { wl, V3(0.2, 1, 0.5) } }
	ctx.WingPart, ctx.FinPart = body, head
	ctx.Radius = 1.75
	ctx.FaceOpts = { Spread = 0.42, EyeY = 0.18, MouthDir = V3(0, -0.4, -1) }
	ctx.OwnWings = true
	Kit.Gloss(ctx.model, wl :: BasePart, V3(-0.3, 1, -0.4))
end

function Arch.Floaty(ctx)
	local P, S, A = ctx.P, ctx.S, ctx.A
	local body = E(ctx, ctx.root, "Body", V3(2.75, 0.85, 2.75), CF(0, 1.75, 0), Kit.Lighter(P, 0.15), "Main",
		V3(0, 1.75, 0))
	body.Transparency = 0.08
	local head = E(ctx, body, "Head", V3(2.5, 2.2, 2.5), CF(0, 2.65, 0), P, "Main", V3(0, 2.0, 0))
	head.Transparency = 0.04
	local i = 0
	for _, xz in { { -0.65, -0.55 }, { 0.65, -0.55 }, { -0.65, 0.65 }, { 0.65, 0.65 } } do
		i += 1
		local t = E(ctx, body, "Tendril" .. i, V3(0.36, 1.5, 0.36), CF(xz[1], 0.98, xz[2]), S, "Belly",
			V3(xz[1], 1.7, xz[2]))
		t.Transparency = 0.12
		local tip = Kit.Add(ctx.model, t, "TendrilTip", "Ball", V3(0.34, 0.34, 0.34), CF(xz[1], 0.25, xz[2]), A, "Glow",
			Enum.Material.Neon)
		tip.CastShadow = false
	end
	ctx.Body, ctx.Head = body, head
	ctx.Spine = { { head, V3(0, 1, -0.4) }, { head, V3(0, 1, 0) }, { head, V3(0, 1, 0.45) } }
	ctx.WingPart, ctx.FinPart = head, head
	ctx.Radius = 1.6
	ctx.FaceOpts = { Spread = 0.38, EyeY = -0.05, MouthDir = V3(0, -0.4, -1) }
	Kit.Gloss(ctx.model, head)
end

function Arch.Golem(ctx)
	local g, P, S, A = ctx.G, ctx.P, ctx.S, ctx.A
	local lab = ctx.Variant == "LabDome"
	local mat = lab and Enum.Material.Metal or (g and Enum.Material.Slate or nil)
	local body = B(ctx, ctx.root, "Body", V3(2.6, 2.1, 1.9), CF(0, 2.15, 0.1), P, "Main", V3(0, 1.2, 0.1), mat)
	B(ctx, body, "Chest", V3(1.8, 1.3, 0.3), CF(0, 2.3, -0.88), S, "Belly", nil, lab and Enum.Material.DiamondPlate or nil)
	local core = Kit.Diamond(ctx.model, body, "Core", 0.6, 0.3, CF(0, 2.35, -1.06), A, "Glow", Enum.Material.Neon)
	core.CastShadow = false
	local head
	if lab then
		-- glass dome head with bubbling neon fluid; the face floats in the fluid
		head = E(ctx, body, "Head", V3(2.2, 2.0, 2.0), CF(0, 4.0, -0.05), C(200, 240, 255), "Glass", V3(0, 3.2, 0),
			Enum.Material.Glass)
		head.Transparency = 0.55
		B(ctx, body, "Collar", V3(2.3, 0.4, 2.1), CF(0, 3.3, -0.05), Kit.Darker(P, 0.2), "Main", nil, Enum.Material.Metal)
		local fluid = E(ctx, head, "Fluid", V3(1.75, 1.15, 1.6), CF(0, 3.75, -0.05), A, "Glow", nil, Enum.Material.Neon)
		Kit.Emitter(fluid, { Name = "Bubbles", Color = Kit.Lighter(A, 0.5), Rate = 6, Life = 0.9, Speed = 1.2, Spread = 25,
			Size = 0.18, Accel = V3(0, 2, 0) })
		ctx.FacePart = fluid
	else
		head = B(ctx, body, "Head", V3(1.75, 1.4, 1.5), CF(0, 3.9, -0.05), P, "Main", V3(0, 3.2, 0), mat)
	end
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		local arm = B(ctx, body, "Arm" .. n, V3(0.95, 1.7, 1.0), CF(s * 1.85, 2.3, 0), Kit.Darker(P, 0.08), "Main",
			V3(s * 1.4, 3.0, 0), mat)
		if lab then
			local cup = Kit.VCyl(ctx.model, arm, "Hand" .. n, 1.2, 1.15, CF(s * 1.95, 1.05, -0.1), C(210, 240, 255), "Glass",
				Enum.Material.Glass)
			cup.Transparency = 0.5
			Kit.VCyl(ctx.model, cup, "Fluid", 0.7, 0.95, CF(s * 1.95, 0.85, -0.1), A, "Glow", Enum.Material.Neon)
		else
			B(ctx, arm, "Hand" .. n, V3(1.15, 1.0, 1.15), CF(s * 1.95, 1.05, -0.1), Kit.Darker(P, 0.18), "Main", nil, mat)
		end
		B(ctx, ctx.root, "Leg" .. n, V3(0.95, 1.2, 1.0), CF(s * 0.65, 0.6, 0.1), Kit.Darker(P, 0.12), "Main",
			V3(s * 0.65, 1.15, 0.1), mat)
	end
	ctx.Body, ctx.Head = body, head
	ctx.Spine = { { body, V3(-0.5, 1, 0.2) }, { head, V3(0, 1, 0) }, { body, V3(0.5, 1, 0.2) } }
	ctx.WingPart, ctx.FinPart = body, head
	ctx.Radius = 1.9
	ctx.FaceOpts = lab and { Spread = 0.4, EyeY = 0.1, EyeScale = 0.4, NoMouth = true }
		or { Spread = 0.42, EyeY = 0.12, EyeScale = 0.42, MouthDir = V3(0, -0.6, -1) }
	if not lab then
		Kit.Gloss(ctx.model, head, V3(-0.6, 0.8, -1))
	end
end

-- ===================================================================== features

-- Where a head-top feature goes: the head's top (free slot) or, when `backOk` and the top is taken, the back.
local function headTop(ctx, backOk: boolean?)
	if backOk and (ctx.TopCount or 0) > 0 then
		local sp = ctx.Spine[2]
		return sp[1], Kit.OnSurface(sp[1], sp[2], 0.05)
	end
	return ctx.Head, Kit.OnSurface(ctx.Head, topSlot(ctx), 0.08)
end

function Feat.Crown(ctx)
	local head = ctx.Head
	local base = Kit.OnSurface(head, topSlot(ctx), 0.12, true)
	local d = math.min(head.Size.X, head.Size.Z) * 0.5
	local band = Kit.VCyl(ctx.model, head, "Crown", 0.42, d, base * CF(0, 0.21, 0), Kit.Gold, "Accent", Enum.Material.Foil)
	for i, a in { -50, 0, 50 } do
		local ar = rad(a)
		local cf = base * CF(math.sin(ar) * d * 0.42, 0.5, -math.cos(ar) * d * 0.42) * ANG(0, -ar, 0)
		if i == 2 then
			Kit.Diamond(ctx.model, band, "CrownGem", 0.42, 0.22, cf, ctx.A, "Glow", Enum.Material.Neon)
		else
			Kit.Diamond(ctx.model, band, "CrownPoint", 0.36, 0.14, cf, Kit.Gold, "Accent", Enum.Material.Foil)
		end
	end
end

function Feat.Mushroom(ctx)
	local head = ctx.Head
	local base = Kit.OnSurface(head, topSlot(ctx), 0.35, true)
	local hs = head.Size
	local cap = E(ctx, head, "Cap", V3(hs.X * 1.05, hs.Y * 0.55, hs.Z * 1.05), base * CF(0, hs.Y * 0.15, 0), ctx.A, "Accent")
	for _, d in { V3(0, 1, 0), V3(0.7, 0.5, -0.5), V3(-0.65, 0.45, 0.4), V3(-0.3, 0.55, -0.8) } do
		local spot = Kit.Add(ctx.model, cap, "CapSpot", "Ell", V3(0.5, 0.5, 0.12), Kit.Facing(cap, d, 0.02), Kit.Ivory,
			"Face")
		spot.CastShadow = false
	end
end

function Feat.Flower(ctx)
	local parent, base = headTop(ctx, false)
	local col = petalColor(ctx)
	local centre = Kit.Add(ctx.model, parent, "Flower", "Ball", V3(0.34, 0.34, 0.34), base * CF(0, 0.2, 0),
		C(255, 220, 70), "Accent")
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		local petal = E(ctx, centre, "Petal", V3(0.48, 0.12, 0.34),
			base * CF(math.cos(a) * 0.3, 0.16, math.sin(a) * 0.3) * ANG(0, -a, rad(18)), col, "Accent")
		petal.CastShadow = false
	end
end

function Feat.Bolt(ctx)
	local parent, base = headTop(ctx, false)
	local y = C(255, 235, 60)
	local s1 = B(ctx, parent, "Bolt", V3(0.26, 0.62, 0.16), base * CF(0, 0.28, 0) * ANG(0, 0, rad(28)), y, "Glow",
		base, Enum.Material.Neon)
	B(ctx, s1, "BoltSeg", V3(0.24, 0.62, 0.16), base * CF(0.1, 0.72, 0) * ANG(0, 0, rad(-38)), y, "Glow", nil,
		Enum.Material.Neon)
	B(ctx, s1, "BoltSeg", V3(0.2, 0.55, 0.16), base * CF(0.02, 1.12, 0) * ANG(0, 0, rad(28)), y, "Glow", nil,
		Enum.Material.Neon)
end

function Feat.Flame(ctx)
	local parent, base
	if ctx.Tail and (ctx.TopCount or 0) > 0 then
		parent = ctx.Tail
		local p = ctx.Tail.CFrame * CF(0, 0, ctx.Tail.Size.Z * 0.42)
		base = Kit.UpFrame(p.Position, V3(0, 1, 0))
	else
		parent, base = ctx.Head, Kit.OnSurface(ctx.Head, topSlot(ctx), 0.15, true)
	end
	local orange, yellow = C(255, 120, 30), C(255, 225, 70)
	local outer = Kit.Stick(ctx.model, parent, "Flame", "Ell", V3(0.8, 1.05, 0.8), base, orange, "Glow",
		Enum.Material.Neon, 0.15)
	outer.CastShadow = false
	E(ctx, outer, "FlameCore", V3(0.48, 0.7, 0.48), outer.CFrame * CF(0, -0.1, -0.22), yellow, "Glow", nil,
		Enum.Material.Neon)
	E(ctx, outer, "FlameTip", V3(0.34, 0.6, 0.34), outer.CFrame * CF(0.05, 0.62, 0.08) * ANG(rad(20), 0, rad(-12)),
		orange, "Glow", nil, Enum.Material.Neon)
	Kit.Emitter(outer, { Name = "FlameFx", Color = yellow, Color2 = C(255, 70, 20), Rate = 7, Life = 0.45, Speed = 2,
		Spread = 12, Size = 0.55, Texture = Kit.FireTexture, Transp = 0.3 })
	Kit.Light(outer, orange, 7, 1)
end

function Feat.Leaves(ctx)
	local parent, base = headTop(ctx, true)
	local col = leafColor(ctx)
	local stem = Kit.Stick(ctx.model, parent, "Stem", "Ell", V3(0.16, 0.55, 0.16), base, Kit.Darker(col, 0.25), "Accent",
		nil, 0.1)
	for _, s in { -1, 1 } do
		local f = base * CF(0, 0.35, 0) * ANG(0, 0, -s * rad(55))
		local leaf = Kit.Stick(ctx.model, stem, "Leaf", "Ell", V3(0.55, 1.0, 0.14), f, col, "Accent", nil, 0.05)
		leaf.CastShadow = false
	end
	if not ctx.G then
		local sp = ctx.Spine[3]
		local f = Kit.OnSurface(sp[1], sp[2], 0.08) * ANG(rad(-35), 0, 0)
		Kit.Stick(ctx.model, sp[1], "Leaf", "Ell", V3(0.6, 1.0, 0.14), f, Kit.Lighter(col, 0.1), "Accent", nil, 0.05)
	end
end

function Feat.Antlers(ctx)
	local col = ctx.AntlerColor or ctx.A
	local scale = ctx.G and 1.5 or 1
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		local f = Kit.OnSurface(ctx.Head, V3(s * 0.45, 0.85, 0.1), 0.1) * ANG(0, 0, -s * rad(25))
		local main = Kit.Stick(ctx.model, ctx.Head, "Antler" .. n, "Ell", V3(0.3, 1.6, 0.3) * scale, f, col, "Accent")
		Kit.Stick(ctx.model, main, "Tine", "Ell", V3(0.22, 0.85, 0.22) * scale,
			f * CF(0, 0.85 * scale, 0) * ANG(rad(-40), 0, -s * rad(30)), Kit.Lighter(col, 0.08), "Accent")
		Kit.Stick(ctx.model, main, "Tine", "Ell", V3(0.2, 0.75, 0.2) * scale,
			f * CF(0, 1.4 * scale, 0) * ANG(0, 0, -s * rad(45)), Kit.Lighter(col, 0.15), "Accent")
	end
end

function Feat.Horns(ctx)
	local col = ctx.HornColor or ctx.A
	local k = ctx.G and 1.35 or 1
	if ctx.Arch == "Bug" then
		local f = Kit.OnSurface(ctx.Head, V3(0, 0.8, -0.6), 0.15)
		local main = Kit.Stick(ctx.model, ctx.Head, "Horn", "Ell", V3(0.5, 1.15, 0.5), f, col, "Accent")
		Kit.Stick(ctx.model, main, "HornTip", "Ell", V3(0.3, 0.7, 0.3), f * CF(0, 0.85, 0) * ANG(rad(30), 0, 0),
			Kit.Lighter(col, 0.35), "Accent")
		return
	end
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		local f = Kit.OnSurface(ctx.Head, V3(s * 0.55, 0.75, -0.05), 0.12) * ANG(0, 0, -s * rad(28))
		local main = Kit.Stick(ctx.model, ctx.Head, "Horn" .. n, "Ell", V3(0.42, 0.78, 0.42) * k, f, col, "Accent")
		Kit.Stick(ctx.model, main, "HornTip", "Ell", V3(0.26, 0.62, 0.26) * k,
			f * CF(0, 0.6 * k, 0) * ANG(rad(30), 0, -s * rad(22)), Kit.Lighter(col, 0.4), "Accent")
	end
end

function Feat.Ears(ctx)
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		local f = Kit.OnSurface(ctx.Head, V3(s * 0.62, 0.75, 0.05), 0.22) * ANG(0, 0, -s * rad(22))
		local ear = Kit.Stick(ctx.model, ctx.Head, "Ear" .. n, "Ell", V3(0.62, 1.0, 0.3), f, ctx.P, "Main")
		E(ctx, ear, "EarInner", V3(0.36, 0.62, 0.1), ear.CFrame * CF(0, -0.04, -0.12), ctx.S, "Belly")
	end
end

function Feat.Antenna(ctx)
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		local f = Kit.OnSurface(ctx.Head, V3(s * 0.32, 1, -0.15), 0.08) * ANG(0, 0, -s * rad(20))
		local stalk = Kit.Stick(ctx.model, ctx.Head, "Antenna" .. n, "Ell", V3(0.13, 1.0, 0.13), f, Kit.Darker(ctx.P, 0.3),
			"Accent")
		local tip = Kit.Add(ctx.model, stalk, "AntennaTip", "Ball", V3(0.38, 0.38, 0.38), f * CF(0, 1.0, 0), ctx.A, "Glow",
			Enum.Material.Neon)
		tip.CastShadow = false
	end
end

function Feat.Goggles(ctx)
	local head = ctx.Head
	local hs = head.Size
	local y = (ctx.FaceOpts and ctx.FaceOpts.EyeY or 0.15) + 0.42
	local strap = E(ctx, head, "GoggleStrap", V3(hs.X * 1.04, 0.28, hs.Z * 1.04),
		head.CFrame * CF(0, y * hs.Y * 0.42, 0), C(60, 50, 65), "Face")
	strap.CastShadow = false
	for _, s in { -1, 1 } do
		local f = Kit.Facing(head, V3(s * 0.34, y, -1), -0.02)
		local lens = Kit.Add(ctx.model, strap, "Goggle", "Cyl", V3(0.2, 0.62, 0.62), f * ANG(0, math.pi / 2, 0),
			Kit.Lighter(ctx.A, 0.2), "Accent", Enum.Material.Glass)
		lens.Transparency = 0.15
		lens.Reflectance = 0.25
	end
end

function Feat.Beak(ctx)
	if ctx.Arch == "Bird" then
		return -- the bird archetype builds its own beak (and a lower beak when Beak is listed)
	end
	E(ctx, ctx.Head, "Beak", V3(0.62, 0.38, 0.66), Kit.Facing(ctx.Head, V3(0, -0.1, -1), 0) * CF(0, 0, -0.18), ctx.A,
		"Accent")
end

function Feat.Tusks(ctx)
	local part = ctx.Jaw or ctx.Head
	local k = ctx.G and 1.4 or 1
	for _, s in { -1, 1 } do
		local p = Kit.Surface(part, V3(s * 0.45, -0.45, -1))
		local f = Kit.UpFrame(p, V3(0, 1, 0)) * ANG(rad(-28), 0, -s * rad(15))
		Kit.Stick(ctx.model, part, "Tusk", "Ell", V3(0.22, 0.75, 0.22) * k, f, Kit.Ivory, "Accent", nil, 0.2)
	end
end

function Feat.Wings(ctx)
	if ctx.Arch == "Bird" or ctx.OwnWings then
		return
	end
	local part = ctx.WingPart
	local col = ctx.WingColor or ctx.A
	for _, sd in sides() do
		local s, n = sd[1], sd[2]
		local p = Kit.Surface(part, V3(s * 0.85, 0.6, 0.1))
		local w = E(ctx, part, "Wing" .. n, V3(0.24, 1.55, 2.0), CF(p + V3(s * 0.55, 0.65, 0.35)) * ANG(rad(20), 0, -s * rad(35)),
			col, "Accent", p)
		E(ctx, w, "WingTip" .. n, V3(0.2, 0.95, 1.1), w.CFrame * CF(0, 0.38, 0.72), Kit.Lighter(col, 0.3), "Accent")
	end
end

function Feat.Fins(ctx)
	local col = ctx.A
	local sp = ctx.Spine[2]
	local fin = Kit.Add(ctx.model, sp[1], "Fin", "Wedge", V3(0.16, 1.0, 1.3), Kit.OnSurface(sp[1], sp[2], 0.2) * CF(0, 0.5, 0),
		col, "Accent")
	fin.Transparency = 0.05
	if ctx.Arch == "Blob" then
		for _, sd in sides() do
			local s = sd[1]
			local p = Kit.Surface(ctx.Body, V3(s, -0.2, -0.2))
			E(ctx, ctx.Body, "Fin" .. sd[2], V3(1.0, 0.2, 0.65), CF(p + V3(s * 0.3, 0, 0)) * ANG(0, s * rad(20), -s * rad(15)),
				ctx.P, "Main", p)
		end
		return
	end
	for _, sd in sides() do
		local s = sd[1]
		local p = Kit.Surface(ctx.FinPart, V3(s, 0.15, 0.25))
		E(ctx, ctx.FinPart, "Fin" .. sd[2], V3(0.14, 0.8, 1.05), CF(p + V3(s * 0.15, 0.1, 0.2)) * ANG(rad(25), 0, -s * rad(45)),
			col, "Accent", p)
	end
end

function Feat.Spikes(ctx)
	local col = ctx.SpikeColor or ctx.A
	local k = ctx.G and 1.3 or 1
	for i, sp in ctx.Spine do
		local h = ({ 0.8, 0.95, 0.7 })[i] or 0.7
		Kit.Stick(ctx.model, sp[1], "Spike", "Wedge", V3(0.22, h, h * 0.9) * k, Kit.OnSurface(sp[1], sp[2], 0.05), col,
			"Accent", nil, 0.12)
	end
end

function Feat.Plates(ctx)
	local col = ctx.PlateColor or ctx.A
	local k = ctx.G and 1.3 or 1
	for i, sp in ctx.Spine do
		local h = ({ 0.95, 1.15, 0.85 })[i] or 0.8
		Kit.Stick(ctx.model, sp[1], "Plate", "Ell", V3(0.18, h, h * 0.85) * k,
			Kit.OnSurface(sp[1], sp[2], 0.05) * ANG(0, 0, (i % 2 == 0 and 1 or -1) * rad(6)), col, "Accent", nil, 0.3)
	end
end

function Feat.Crystal(ctx)
	local col = Kit.Lighter(ctx.CrystalColor or ctx.A, 0.15)
	local k = ctx.G and 1.4 or 1
	local mid
	for i, sp in ctx.Spine do
		local h = ({ 0.9, 1.2, 0.75 })[i] or 0.8
		local f = Kit.OnSurface(sp[1], sp[2], 0.05) * ANG(0, rad(45), (i - 2) * rad(14))
		local shard = Kit.Stick(ctx.model, sp[1], "Crystal", "Block", V3(0.38, h, 0.38) * k, f, col, "Accent",
			Enum.Material.Glass, 0.18)
		shard.Transparency = 0.18
		shard.Reflectance = 0.2
		if i == 2 then
			mid = shard
		end
	end
	if mid then
		Kit.Light(mid, col, 7, 0.8)
	end
end

function Feat.Shell(ctx)
	if ctx.Arch == "Bug" then
		for _, n in { "WingL", "WingR" } do
			local w = ctx.model:FindFirstChild(n)
			if w then
				for _, d in { V3(0, 1, -0.3), V3(0, 0.8, 0.45) } do
					E(ctx, w, "ShellSpot", V3(0.5, 0.5, 0.12), Kit.Facing(w, d, 0.02), ctx.A, "Accent")
				end
			end
		end
		return
	end
	local body = ctx.Body
	local bs = body.Size
	local shell = E(ctx, body, "Shell", V3(bs.X * 1.12, bs.Y * 0.85, bs.Z * 1.05), body.CFrame * CF(0, bs.Y * 0.2, 0.05),
		ctx.A, "Accent")
	E(ctx, shell, "ShellRim", V3(shell.Size.X * 1.04, 0.28, shell.Size.Z * 1.04), shell.CFrame * CF(0, -shell.Size.Y * 0.18, 0),
		ctx.S, "Belly")
	for _, d in { V3(0, 1, 0), V3(0.6, 0.7, -0.4), V3(-0.6, 0.7, 0.4) } do
		local spot = E(ctx, shell, "ShellSpot", V3(0.7, 0.6, 0.12), Kit.Facing(shell, d, 0.02), Kit.Darker(ctx.A, 0.2),
			"Accent")
		spot.CastShadow = false
	end
end

function Feat.Runes(ctx)
	local col = ctx.RuneColor or ctx.A
	local spots = {
		{ ctx.Body, V3(-1, 0.1, 0) },
		{ ctx.Body, V3(1, 0.1, 0) },
		{ ctx.Head, V3(0, 0.6, -1) },
	}
	if ctx.F.Goggles or ctx.Variant == "LabDome" then
		spots[3] = { ctx.Body, V3(0, -0.3, -1) }
	end
	for _, sp in spots do
		local r = Kit.Diamond(ctx.model, sp[1], "Rune", 0.55, 0.08, Kit.Facing(sp[1], sp[2], 0.01), col, "Glow",
			Enum.Material.Neon)
		r.CastShadow = false
	end
end

function Feat.Stars(ctx)
	local head = ctx.Head
	local hs = head.Size
	local centre = head.Position + V3(0, hs.Y * 0.35, 0)
	local r = hs.X * 0.85
	local n = ctx.G and 4 or 3
	for i = 1, n do
		local a = i / n * math.pi * 2
		local pos = centre + V3(math.cos(a) * r, (i % 2) * 0.25, math.sin(a) * r)
		local star = Kit.Diamond(ctx.model, head, "Orbit" .. i, 0.4, 0.12, CFrame.lookAt(pos, centre), C(255, 236, 130), "Glow",
			Enum.Material.Neon, centre)
		star.CastShadow = false
	end
end

local function halo(ctx, color: Color3)
	if ctx.HasHalo then
		return
	end
	ctx.HasHalo = true
	local head = ctx.Head
	local p = Kit.Surface(head, V3(0, 1, 0))
	local lift = ctx.TopCount and ctx.TopCount > 0 and 1.15 or 0.65
	local centre = CF(p + V3(0, lift, 0)) * ANG(rad(-12), 0, 0)
	Kit.Ring(ctx.model, head, "Halo", centre, math.max(head.Size.X * 0.32, 0.55), 0.14, 0.14, 8, color, "Fx",
		Enum.Material.Neon)
end

function Feat.Halo(ctx)
	halo(ctx, C(255, 228, 120))
end

function Feat.Tail(_ctx)
	-- archetypes with tails build the fluffy variant themselves when Tail is listed
end

Pet.FeatureOrder = {
	"Crown", "Mushroom", "Flower", "Bolt", "Flame", "Leaves", "Antlers", "Horns", "Ears", "Antenna", "Goggles", "Beak",
	"Tusks", "Wings", "Fins", "Spikes", "Plates", "Shell", "Crystal", "Runes", "Stars", "Halo", "Tail",
}

-- ===================================================================== assembly

function Pet.Assemble(ctx)
	local build = Arch[ctx.Arch] or Arch.Blob
	build(ctx)
	for _, f in Pet.FeatureOrder do
		if ctx.F[f] and Feat[f] then
			Feat[f](ctx)
		end
	end
	local fo = table.clone(ctx.FaceOpts or {})
	if ctx.G then
		fo.EyeScale = (fo.EyeScale or 0.36) * 0.8
		fo.Angry = true
		fo.Glow = fo.Glow or ctx.Glow
		fo.NoMouth = fo.NoMouth and not ctx.ForceMouth
	end
	Kit.Face(ctx.model, ctx.FacePart or ctx.Head, fo)
end

-- Rarity readability: ring (Rare+), light (Epic+), sparkles (Legendary+), aura (Mythic+), halo + beam (Divine).
function Pet.Flair(ctx, rarity: string)
	local r = GameConfig.Rarities.ById[rarity]
	if not r or r.Index < 3 then
		return
	end
	local idx, col = r.Index, r.Color
	local d = ctx.Radius * 2 * (idx >= 6 and 1.25 or 1.1)
	local ring = Kit.VCyl(ctx.model, ctx.root, "RarityRing", 0.1, d, CF(0, 0.06, 0), col, "Fx", Enum.Material.Neon)
	ring.Transparency = 0.45
	ring.CastShadow = false
	if idx >= 4 then
		Kit.Light(ctx.Body, col, 6 + (idx - 4) * 3, 0.8 + (idx - 4) * 0.4)
	end
	if idx >= 5 then
		Kit.Emitter(ctx.Body, { Name = "RaritySparkle", Color = Kit.Lighter(col, 0.3), Rate = 2 + (idx - 5) * 2, Life = 1,
			Speed = 0.5, Size = 0.3, Rot = 60 })
	end
	if idx >= 6 then
		Kit.Emitter(ring, { Name = "RarityAura", Color = col, Color2 = Kit.Lighter(col, 0.5), Rate = 8, Life = 1.4,
			Speed = 0.1, Spread = 0, Size = 0.4, Accel = V3(0, 2.2, 0), Transp = 0.35 })
	end
	if idx >= 7 then
		halo(ctx, C(255, 225, 110))
		-- ring's local X axis points up (vertical cylinder)
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamBase"
		a0.Parent = ring
		local a1 = Instance.new("Attachment")
		a1.Name = "BeamTop"
		a1.Position = V3(9, 0, 0)
		a1.Parent = ring
		local beam = Instance.new("Beam")
		beam.Name = "DivineBeam"
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Color = ColorSequence.new(C(255, 245, 200), C(255, 210, 90))
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Width0, beam.Width1 = d * 0.7, d * 0.25
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = 1
		beam.Parent = ring
	end
end

local TIER_COLORS = { C(255, 255, 255), C(255, 170, 90), C(200, 235, 255), C(255, 215, 60), C(255, 90, 230) }

function Pet.TierBadge(ctx, tier: number)
	if tier < 2 then
		return
	end
	local n = math.clamp(tier - 1, 1, 4)
	local col = TIER_COLORS[math.clamp(tier, 1, #TIER_COLORS)]
	local head = ctx.Head
	local top = Kit.TopY(ctx.model)
	local pos = V3(0, top + 0.55, head.Position.Z)
	local plate = E(ctx, head, "TierBadge", V3(0.48 * n + 0.38, 0.6, 0.18), CF(pos), Kit.Ink, "Fx")
	plate.Transparency = 0.3
	plate.CastShadow = false
	for i = 1, n do
		local x = (i - (n + 1) / 2) * 0.48
		local star = Kit.Diamond(ctx.model, plate, "TierStar", 0.34, 0.1, CF(pos + V3(x, 0, -0.1)), col, "Fx",
			Enum.Material.Neon)
		star.CastShadow = false
	end
end

function Pet.Build(speciesId: string, opts): Model
	opts = opts or {}
	local sp = GameConfig.GetSpecies(speciesId)
	local colors = sp and sp.Colors or { C(190, 190, 205), C(245, 245, 250), C(120, 130, 160) }
	local features = {}
	for _, f in (sp and sp.Features or {}) do
		features[f] = true
	end
	local model, root = Kit.NewModel(speciesId)
	local ctx = {
		model = model,
		root = root,
		P = colors[1],
		S = colors[2] or Kit.Lighter(colors[1], 0.6),
		A = colors[3] or Kit.Darker(colors[1], 0.3),
		F = features,
		Arch = sp and sp.Archetype or "Blob",
	}
	Pet.Assemble(ctx)
	local rarity = sp and sp.Rarity or "Common"
	Pet.Flair(ctx, rarity)
	local tier = math.clamp(opts.Tier or 1, 1, GameConfig.Rarities.MaxTier)
	Pet.TierBadge(ctx, tier)
	local height = Kit.TopY(model)

	local size = opts.Size or "Normal"
	local sizeCfg = GameConfig.Rarities.Sizes[size] or GameConfig.Rarities.Sizes.Normal
	model:SetAttribute("Species", speciesId)
	model:SetAttribute("Archetype", ctx.Arch)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Size", size)
	model:SetAttribute("Tier", tier)
	Mutation.Apply(model, opts.Mutation)
	if sizeCfg.Scale ~= 1 then
		model:ScaleTo(sizeCfg.Scale)
	end
	model:SetAttribute("Height", height * sizeCfg.Scale)
	return model
end

return Pet

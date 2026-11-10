-- Hero: a chunky toy-brick minifigure (~4.5 studs tall at Normal size) dressed by species.Costume.
-- Rig: Root -> Body (torso), LegL, LegR; Body -> Head, ArmL, ArmR (+ costume); ArmX -> HandX; HandR -> Item.
-- Ghosts have no legs/hips: a wispy tail ("GhostTail") hangs under the torso and the model gets
-- attribute Float = true. Colours: P = outfit, S = skin, A = accent (also used by the character's egg).
--
-- Hero.Hat is shared with Egg.lua: hats are modelled on a 1.5-wide head whose top centre is `top`
-- and scaled by k, so the same builder dresses a hero head or the tip of a character egg.

local Kit = require(script.Parent.Style)

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local C = Color3.fromRGB
local Neon, Glass = Enum.Material.Neon, Enum.Material.Glass
local HALF_PI = math.pi / 2

local Hero = {}

local TORSO_Y0, TORSO_Y1 = 1.65, 2.95
local HEAD_SIZE = V3(1.5, 1.3, 1.3)
local HEAD_Y = 3.72
local SHOULDER = V3(0.66, 2.82, 0)
local STEEL = C(185, 190, 205)
local BLADE = C(225, 232, 242)
local WOOD = C(140, 95, 55)
local DARK = C(52, 46, 60)

local function scaled(c: CFrame, k: number): CFrame
	return CF(c.Position * k) * c.Rotation
end

local function lum(c: Color3): number
	return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
end

-- ===================================================================== hats

-- Builder context for hats: add(name, shape, size, offset, color, role?, mat?) in head-top space.
type HatCtx = {
	add: (string, string, Vector3, CFrame, Color3, string?, Enum.Material?) -> BasePart,
	vcyl: (string, number, number, CFrame, Color3, string?, Enum.Material?) -> BasePart,
	P: Color3,
	S: Color3,
	A: Color3,
}

local Hats: { [string]: (HatCtx) -> () } = {}

function Hats.Wizard(h)
	local col = Kit.Darker(h.P, 0.1)
	h.vcyl("HatBrim", 0.12, 2.1, CF(0, 0.06, 0), col)
	h.vcyl("HatCone", 0.5, 1.25, CF(0, 0.37, 0), col)
	h.vcyl("HatCone", 0.5, 0.85, CF(0, 0.84, 0.06), col)
	h.vcyl("HatTip", 0.45, 0.45, CF(0, 1.25, 0.16) * ANG(rad(-14), 0, 0), col)
	h.add("HatStar", "Block", V3(0.32, 0.32, 0.08), CF(0, 0.4, -0.64) * ANG(0, 0, rad(45)), h.A, "Glow", Neon)
end

function Hats.Helmet(h)
	local dome = h.add("HelmetDome", "Ball", V3(2.45, 2.45, 2.45), CF(0, -0.62, 0), Kit.Lighter(h.A, 0.6), "Glass", Glass)
	dome.Transparency = 0.6
	dome.Reflectance = 0.25
	h.vcyl("HelmetRing", 0.25, 1.95, CF(0, -1.32, 0), Kit.Lighter(h.P, 0.2))
	h.add("HelmetLight", "Ball", V3(0.28, 0.28, 0.28), CF(0, 0.66, 0), h.A, "Glow", Neon)
end

function Hats.Crown(h)
	local band = h.add("Crown", "Block", V3(1.35, 0.36, 1.18), CF(0, 0.16, 0), Kit.Gold)
	band.Reflectance = 0.15
	for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		h.add("CrownPoint", "Block", V3(0.3, 0.32, 0.3), CF(c[1] * 0.52, 0.48, c[2] * 0.44) * ANG(0, rad(45), 0), Kit.Gold)
	end
	h.add("CrownGem", "Block", V3(0.28, 0.28, 0.06), CF(0, 0.16, -0.61) * ANG(0, 0, rad(45)), C(255, 50, 90), "Glow", Neon)
end

function Hats.Pirate(h)
	local col = C(40, 35, 48)
	h.add("HatBrim", "Ell", V3(2.2, 0.2, 1.8), CF(0, 0.06, 0), col)
	h.add("HatTop", "Block", V3(1.35, 0.55, 1.15), CF(0, 0.36, 0.05), col)
	for _, s in { -1, 1 } do
		h.add("HatFlap", "Block", V3(0.12, 0.5, 1.3), CF(s * 1.0, 0.26, 0) * ANG(0, 0, -s * rad(28)), col)
	end
	h.add("HatSkull", "Block", V3(0.34, 0.3, 0.06), CF(0, 0.36, -0.6), Kit.White, "Face")
end

function Hats.Cowboy(h)
	local col = h.P:Lerp(C(150, 100, 55), 0.6)
	h.add("HatBrim", "Ell", V3(2.5, 0.16, 2.2), CF(0, 0.08, 0), col)
	h.add("HatTop", "Block", V3(1.3, 0.6, 1.1), CF(0, 0.42, 0), col)
	h.add("HatBand", "Block", V3(1.34, 0.14, 1.14), CF(0, 0.2, 0), h.A)
end

function Hats.Ninja(h)
	h.add("Headband", "Block", V3(1.58, 0.26, 1.38), CF(0, -0.42, 0), h.A)
	h.add("HeadbandPlate", "Block", V3(0.5, 0.2, 0.06), CF(0, -0.42, -0.71), STEEL)
	for _, s in { -1, 1 } do
		h.add("HeadbandTail", "Block", V3(0.14, 0.55, 0.07), CF(s * 0.15, -0.68, 0.72) * ANG(0, 0, s * rad(20)), h.A)
	end
end

function Hats.Knight(h)
	local steel = C(175, 180, 195)
	h.add("HelmTop", "Block", V3(1.66, 0.42, 1.46), CF(0, 0.05, 0), steel)
	for _, s in { -1, 1 } do
		h.add("HelmCheek", "Block", V3(0.14, 1.0, 1.46), CF(s * 0.83, -0.55, 0), steel)
	end
	h.add("HelmBack", "Block", V3(1.66, 1.0, 0.14), CF(0, -0.55, 0.73), steel)
	h.add("HelmPlume", "Block", V3(0.22, 0.55, 0.95), CF(0, 0.5, 0.1), h.A)
end

function Hats.Chef(h)
	h.add("ChefBand", "Block", V3(1.54, 0.36, 1.34), CF(0, 0.1, 0), Kit.White)
	h.add("ChefPuff", "Ell", V3(1.9, 0.95, 1.7), CF(0, 0.7, 0), Kit.White)
	h.add("ChefPuff", "Ell", V3(1.1, 0.6, 1.0), CF(0, 1.15, 0), Kit.White)
end

function Hats.Hood(h)
	local col = Kit.Darker(h.P, 0.15)
	h.add("HoodTop", "Block", V3(1.72, 0.25, 1.5), CF(0, 0.1, 0.08), col)
	for _, s in { -1, 1 } do
		h.add("HoodSide", "Block", V3(0.14, 1.2, 1.5), CF(s * 0.86, -0.55, 0.08), col)
	end
	h.add("HoodBack", "Block", V3(1.72, 1.2, 0.16), CF(0, -0.55, 0.8), col)
	h.add("HoodTip", "Wedge", V3(0.6, 0.5, 0.6), CF(0, 0.45, 0.55), col)
end

function Hats.Horns(h)
	h.add("HornCap", "Block", V3(1.6, 0.42, 1.4), CF(0, 0.1, 0), C(150, 155, 170))
	for _, s in { -1, 1 } do
		h.add("HornBase", "Block", V3(0.42, 0.32, 0.32), CF(s * 0.95, -0.02, 0), Kit.Ivory)
		h.add("Horn", "Block", V3(0.26, 0.62, 0.26), CF(s * 1.17, 0.32, 0) * ANG(0, 0, -s * rad(20)), Kit.Ivory)
	end
end

function Hats.Mohawk(h)
	h.add("Mohawk", "Block", V3(0.32, 0.42, 1.3), CF(0, 0.2, 0.05), h.A)
	for _, z in { -0.42, 0, 0.42 } do
		h.add("MohawkSpike", "Block", V3(0.26, 0.32, 0.32), CF(0, 0.45, z) * ANG(rad(45), 0, 0), h.A)
	end
end

function Hats.Cap(h)
	h.add("Cap", "Block", V3(1.56, 0.42, 1.38), CF(0, 0.18, 0.02), h.A)
	h.add("CapVisor", "Block", V3(1.25, 0.1, 0.75), CF(0, 0.02, -0.95), Kit.Darker(h.A, 0.25))
	h.vcyl("CapButton", 0.12, 0.3, CF(0, 0.45, 0), Kit.Darker(h.A, 0.25))
end

function Hats.Antenna(h)
	h.vcyl("AntennaBase", 0.12, 0.45, CF(0, 0.06, 0), STEEL)
	h.vcyl("AntennaRod", 0.75, 0.1, CF(0, 0.48, 0), STEEL)
	h.add("AntennaTip", "Ball", V3(0.3, 0.3, 0.3), CF(0, 0.9, 0), h.A, "Glow", Neon)
end

function Hats.TopHat(h)
	local col = C(35, 30, 42)
	h.vcyl("HatBrim", 0.12, 2.0, CF(0, 0.06, 0), col)
	h.vcyl("HatTop", 1.05, 1.25, CF(0, 0.62, 0), col)
	h.vcyl("HatBand", 0.2, 1.28, CF(0, 0.25, 0), h.A)
end

function Hats.Beanie(h)
	h.add("Beanie", "Block", V3(1.6, 0.55, 1.42), CF(0, 0.12, 0), h.A)
	h.add("BeanieFold", "Block", V3(1.66, 0.24, 1.48), CF(0, -0.15, 0), h.P)
	h.add("Pompom", "Ball", V3(0.5, 0.5, 0.5), CF(0, 0.55, 0), Kit.Lighter(h.A, 0.5))
end

function Hats.Headphones(h)
	h.add("Headband", "Block", V3(1.8, 0.15, 0.3), CF(0, 0.08, 0), DARK)
	for _, s in { -1, 1 } do
		h.add("HeadphoneArm", "Block", V3(0.14, 0.55, 0.3), CF(s * 0.9, -0.2, 0), DARK)
		h.add("Earcup", "Cyl", V3(0.3, 0.75, 0.75), CF(s * 0.95, -0.6, 0), h.A)
	end
end

-- Dresses a head (or egg tip) whose top centre is `top`; k scales from the 1.5-wide hero head.
function Hero.Hat(model: Model, attach: BasePart, top: CFrame, k: number, hat: string?, P: Color3, S: Color3,
	A: Color3): boolean
	local build = hat and Hats[hat]
	if not build then
		return false
	end
	local function add(name, shape, size, off, color, role, mat)
		local p = Kit.Add(model, attach, name, shape, size * k, top * scaled(off, k), color, role or "Accent", mat)
		p.CastShadow = false
		return p
	end
	build({
		add = add,
		vcyl = function(name, height, d, off, color, role, mat)
			return add(name, "Cyl", V3(height, d, d), off * ANG(0, 0, HALF_PI), color, role, mat)
		end,
		P = P,
		S = S,
		A = A,
	})
	return true
end

Hero.HatNames = {}
for name in Hats do
	Hero.HatNames[name] = true
end

-- ===================================================================== held items
-- Item space: origin = grip in the right hand, +Y up the handle, -Z forward. First part is "Item".

local Items: { [string]: (any) -> () } = {}

function Items.Staff(it)
	it.cyl("Item", 3.0, 0.18, CF(0, 0.5, 0), WOOD)
	it.cyl("StaffClaw", 0.18, 0.45, CF(0, 1.98, 0), Kit.Gold)
	local orb = it.add("StaffOrb", "Ball", V3(0.55, 0.55, 0.55), CF(0, 2.2, 0), it.A, "Glow", Neon)
	Kit.Light(orb, it.A, 6, 0.8)
end

function Items.Sword(it)
	it.cyl("Item", 0.5, 0.2, CF(0, 0, 0), DARK)
	it.add("SwordGuard", "Block", V3(0.75, 0.14, 0.26), CF(0, 0.32, 0), Kit.Gold)
	local blade = it.add("SwordBlade", "Block", V3(0.36, 1.6, 0.1), CF(0, 1.19, 0), BLADE)
	blade.Reflectance = 0.2
	it.add("SwordTip", "Block", V3(0.255, 0.255, 0.1), CF(0, 1.99, 0) * ANG(0, 0, rad(45)), BLADE)
	it.add("Pommel", "Ball", V3(0.26, 0.26, 0.26), CF(0, -0.3, 0), Kit.Gold)
end

function Items.Blaster(it)
	it.add("Item", "Block", V3(0.2, 0.45, 0.25), CF(0, -0.05, 0), DARK)
	it.add("BlasterBody", "Block", V3(0.32, 0.38, 0.95), CF(0, 0.3, -0.28), Kit.Lighter(it.P, 0.25))
	it.add("BlasterBarrel", "Cyl", V3(0.5, 0.22, 0.22), CF(0, 0.33, -0.95) * ANG(0, HALF_PI, 0), STEEL)
	it.add("BlasterTip", "Cyl", V3(0.08, 0.27, 0.27), CF(0, 0.33, -1.22) * ANG(0, HALF_PI, 0), it.A, "Glow", Neon)
	it.add("BlasterFin", "Block", V3(0.08, 0.18, 0.5), CF(0, 0.56, -0.3), it.A)
end

function Items.Shield(it)
	it.add("Item", "Block", V3(1.25, 1.45, 0.16), CF(0.05, 0.1, -0.32), Kit.Darker(it.A, 0.25))
	it.add("ShieldFace", "Block", V3(1.05, 1.25, 0.08), CF(0.05, 0.1, -0.43), it.A)
	it.add("ShieldBoss", "Block", V3(0.5, 0.5, 0.08), CF(0.05, 0.15, -0.5) * ANG(0, 0, rad(45)), Kit.Gold)
end

function Items.Wrench(it)
	it.add("Item", "Block", V3(0.18, 1.2, 0.12), CF(0, 0.25, 0), STEEL)
	it.add("WrenchHead", "Block", V3(0.55, 0.28, 0.14), CF(0, 0.95, 0), STEEL)
	for _, s in { -1, 1 } do
		it.add("WrenchJaw", "Block", V3(0.14, 0.32, 0.14), CF(s * 0.2, 1.2, 0), STEEL)
	end
end

function Items.Guitar(it)
	local tilt = ANG(0, 0, rad(-28))
	it.add("Item", "Block", V3(0.16, 1.3, 0.1), tilt * CF(0, 0.1, -0.1), C(90, 60, 40))
	it.add("GuitarHead", "Block", V3(0.26, 0.32, 0.12), tilt * CF(0, 0.88, -0.1), DARK)
	it.add("GuitarBody", "Ell", V3(0.85, 0.85, 0.3), tilt * CF(0, -0.75, -0.1), it.A)
	it.add("GuitarBody", "Ell", V3(1.05, 0.8, 0.3), tilt * CF(0, -1.2, -0.1), it.A)
	it.add("GuitarHole", "Cyl", V3(0.06, 0.3, 0.3), tilt * CF(0, -0.85, -0.26) * ANG(0, HALF_PI, 0), DARK, "Face")
end

function Items.Book(it)
	it.add("Item", "Block", V3(0.75, 0.95, 0.24), CF(0, 0.1, -0.18), it.A)
	it.add("BookPages", "Block", V3(0.68, 0.86, 0.26), CF(0.05, 0.1, -0.18), Kit.Ivory)
	it.add("BookRune", "Block", V3(0.3, 0.3, 0.05), CF(-0.02, 0.12, -0.32) * ANG(0, 0, rad(45)), Kit.Gold, "Glow", Neon)
end

function Items.Lantern(it)
	it.add("Item", "Block", V3(0.3, 0.07, 0.07), CF(0, 0, 0), DARK)
	it.add("LanternCap", "Block", V3(0.45, 0.12, 0.45), CF(0, -0.22, 0), DARK)
	local glow = it.add("LanternGlow", "Block", V3(0.36, 0.42, 0.36), CF(0, -0.5, 0), C(255, 210, 110), "Glow", Neon)
	it.add("LanternBase", "Block", V3(0.45, 0.12, 0.45), CF(0, -0.77, 0), DARK)
	Kit.Light(glow, C(255, 200, 110), 8, 0.9)
end

function Items.Pickaxe(it)
	it.cyl("Item", 1.8, 0.16, CF(0, 0.45, 0), WOOD)
	for _, s in { -1, 1 } do
		it.add("PickHead", "Block", V3(0.7, 0.18, 0.18), CF(s * 0.32, 1.3, 0) * ANG(0, 0, -s * rad(15)), STEEL)
	end
end

function Items.Trident(it)
	local col = Kit.Gold
	it.cyl("Item", 2.8, 0.15, CF(0, 0.5, 0), col)
	it.add("TridentBar", "Block", V3(0.75, 0.12, 0.12), CF(0, 1.92, 0), col)
	for _, x in { -0.32, 0, 0.32 } do
		local len = x == 0 and 0.7 or 0.5
		it.add("TridentProng", "Block", V3(0.1, len, 0.1), CF(x, 1.95 + len / 2, 0), col)
	end
end

function Items.Hammer(it)
	it.cyl("Item", 1.4, 0.18, CF(0, 0.3, 0), WOOD)
	it.add("HammerHead", "Block", V3(0.8, 0.5, 0.5), CF(0, 1.1, 0), STEEL)
	it.add("HammerBand", "Block", V3(0.82, 0.14, 0.52), CF(0, 1.1, 0), it.A, "Glow", Neon)
end

function Items.Bow(it)
	local wood = C(150, 95, 50)
	it.add("Item", "Block", V3(0.14, 0.4, 0.14), CF(0, 0, 0), wood)
	local tipU, tipD = V3(0, 1.15, 0.32), V3(0, -1.15, 0.32)
	it.pipe("BowLimb", V3(0, 0.15, 0), tipU, 0.13, wood)
	it.pipe("BowLimb", V3(0, -0.15, 0), tipD, 0.13, wood)
	it.pipe("BowString", tipU, tipD, 0.05, Kit.White)
end

function Items.Torch(it)
	it.cyl("Item", 1.0, 0.2, CF(0, 0.2, 0), WOOD)
	it.cyl("TorchCup", 0.25, 0.36, CF(0, 0.75, 0), DARK)
	local flame = it.add("TorchFlame", "Ell", V3(0.34, 0.55, 0.34), CF(0, 1.05, 0), C(255, 150, 40), "Glow", Neon)
	Kit.Light(flame, C(255, 160, 60), 8, 1)
	Kit.Emitter(flame, { Name = "Fire", Color = C(255, 190, 70), Color2 = C(255, 70, 20), Rate = 8, Life = 0.5,
		Speed = 1, Spread = 15, Size = 0.35, Texture = Kit.FireTexture, Accel = V3(0, 2, 0) })
end

function Items.Clipboard(it)
	it.add("Item", "Block", V3(0.75, 0.95, 0.08), CF(0, -0.1, -0.22), C(160, 115, 70))
	it.add("Paper", "Block", V3(0.62, 0.75, 0.04), CF(0, -0.15, -0.28), Kit.White)
	it.add("Clip", "Block", V3(0.3, 0.12, 0.1), CF(0, 0.33, -0.28), STEEL)
end

function Items.Lasso(it)
	local rope = C(205, 170, 110)
	it.add("Item", "Cyl", V3(0.16, 0.55, 0.55), CF(0, 0, 0) * ANG(0, HALF_PI, 0), rope)
	local c = V3(0.12, -0.75, 0)
	for i = 0, 3 do
		local a = i * HALF_PI + rad(45)
		local off = V3(math.cos(a), math.sin(a), 0) * 0.3
		it.add("LassoLoop", "Block", V3(0.45, 0.08, 0.08), CF(c + off) * ANG(0, 0, a + HALF_PI), rope)
	end
end

function Items.Camera(it)
	it.add("Item", "Block", V3(0.75, 0.5, 0.38), CF(0, 0.15, -0.15), DARK)
	local lens = it.add("CameraLens", "Cyl", V3(0.3, 0.34, 0.34), CF(0, 0.13, -0.45) * ANG(0, HALF_PI, 0), C(60, 90, 140),
		"Glass", Glass)
	lens.Reflectance = 0.3
	it.add("CameraFlash", "Block", V3(0.2, 0.12, 0.1), CF(-0.22, 0.45, -0.2), Kit.White, "Glow", Neon)
end

function Items.Scroll(it)
	it.add("Item", "Cyl", V3(0.85, 0.28, 0.28), CF(0, 0.1, -0.12), Kit.Ivory)
	for _, s in { -1, 1 } do
		it.add("ScrollKnob", "Cyl", V3(0.1, 0.36, 0.36), CF(s * 0.47, 0.1, -0.12), WOOD)
	end
	it.add("ScrollSheet", "Block", V3(0.72, 0.55, 0.03), CF(0, -0.2, -0.2), Kit.Ivory)
	it.add("ScrollSeal", "Block", V3(0.16, 0.16, 0.04), CF(0, -0.35, -0.22) * ANG(0, 0, rad(45)), C(200, 40, 50))
end

local function buildItem(ctx, hand: BasePart, item: string?)
	local build = item and Items[item]
	if not build then
		return
	end
	local ic = CF(hand.Position) * ANG(rad(-10), 0, 0)
	local first: BasePart? = nil
	local function add(name, shape, size, off, color, role, mat)
		local p = Kit.Add(ctx.model, first or hand, name, shape, size, ic * off, color, role or "Accent", mat)
		p.CastShadow = false
		first = first or p
		return p
	end
	build({
		P = ctx.P,
		A = ctx.A,
		add = add,
		cyl = function(name, len, d, off, color)
			return add(name, "Cyl", V3(len, d, d), off * ANG(0, 0, HALF_PI), color)
		end,
		pipe = function(name, a, b, d, color)
			local wa, wb = ic * a, ic * b
			local cf = CFrame.lookAt((wa + wb) / 2, wb) * ANG(0, HALF_PI, 0)
			return add(name, "Cyl", V3((wb - wa).Magnitude, d, d), ic:ToObjectSpace(cf), color)
		end,
	})
end

-- ===================================================================== auras

local AURAS = {
	Fire = { C(255, 190, 60), C(255, 60, 20), Texture = Kit.FireTexture, Rate = 6, Size = 0.55, Accel = V3(0, 3, 0) },
	Ice = { C(220, 245, 255), C(120, 190, 255), Rate = 4, Size = 0.28, Accel = V3(0, -0.6, 0), Rot = 60 },
	Stars = { C(255, 245, 190), C(255, 210, 90), Rate = 3, Size = 0.32, Rot = 90 },
	Void = { C(170, 90, 255), C(30, 10, 60), Rate = 5, Size = 0.4, Accel = V3(0, 0.8, 0), LightE = 0.4 },
	Gold = { C(255, 230, 120), C(255, 190, 40), Rate = 4, Size = 0.3, Rot = 60 },
	Electric = { C(200, 250, 255), C(80, 200, 255), Rate = 6, Size = 0.25, Speed = 3, Life = 0.25 },
}

-- Particle aura + soft light around the character (works on template characters too).
function Hero.Aura(ctx, aura: string?)
	local a = aura and AURAS[aura]
	local body = ctx.Body
	if not a or not body then
		return
	end
	Kit.Emitter(body, { Name = "Aura", Color = a[1], Color2 = a[2], Rate = a.Rate, Life = a.Life or 1.1,
		Speed = a.Speed or 0.6, Size = a.Size, Accel = a.Accel, Texture = a.Texture, Rot = a.Rot, Light = a.LightE,
		Transp = 0.3 })
	local l = Kit.Light(body, a[2], 7, 0.7)
	l.Name = "AuraLight"
end

-- ===================================================================== body

local function emblem(ctx, body: BasePart)
	local z = -0.43 - 0.04
	Kit.Diamond(ctx.model, body, "Emblem", 0.5, 0.08, CF(0, 2.38, z), ctx.A, "Accent")
	Kit.Add(ctx.model, body, "EmblemDot", "Block", V3(0.18, 0.18, 0.06), CF(0, 2.38, z - 0.05), Kit.White, "Accent")
end

local HAIR_TOP_OK = { Crown = true, Headphones = true, Ninja = true, Helmet = true }
local HAIR_BACK_OFF = { Knight = true, Hood = true, Mohawk = true, Horns = true, Chef = true, Beanie = true }

function Hero.Build(ctx, sp)
	local costume = (sp and sp.Costume) or {}
	local model, root = ctx.model, ctx.root
	local P, S, A = ctx.P, ctx.S, ctx.A
	local body_ = costume.Body
	local robot, ghost = body_ == "Robot", body_ == "Ghost"
	local skin = robot and Kit.Lighter(STEEL, 0.25) or S
	local pants = robot and Kit.Darker(P, 0.25) or Kit.Darker(P, 0.35)
	local shirt = body_ == "Jacket" and Kit.Lighter(A, 0.25) or P
	local function B(attach, name, size, cf, color, role, pivot)
		return Kit.Add(model, attach, name, "Block", size, cf, color, role, nil, pivot)
	end

	-- torso: centre block + side wedges = minifig trapezoid
	local torsoH = TORSO_Y1 - TORSO_Y0
	local torsoY = (TORSO_Y0 + TORSO_Y1) / 2
	local body = B(root, "Body", V3(1.2, torsoH, 0.85), CF(0, torsoY, 0), shirt, "Main", V3(0, TORSO_Y0, 0))
	for _, s in { -1, 1 } do
		Kit.Add(model, body, "TorsoSide", "Wedge", V3(0.85, torsoH, 0.22),
			CF(s * 0.71, torsoY, 0) * ANG(0, -s * HALF_PI, 0), P, "Main")
	end

	-- legs (ghosts get a wispy tail instead)
	if ghost then
		Kit.Add(model, body, "GhostTail", "Ell", V3(1.55, 1.25, 0.95), CF(0, 1.25, 0.05), P, "Main")
		Kit.Add(model, body, "GhostTip", "Ell", V3(0.95, 0.75, 0.7), CF(0, 0.6, 0.18) * ANG(rad(-15), 0, 0), P, "Main")
		model:SetAttribute("Float", true)
	else
		B(body, "Hips", V3(1.6, 0.3, 0.92), CF(0, 1.5, 0), pants, "Main")
		for _, sd in { { -1, "L" }, { 1, "R" } } do
			local s, n = sd[1], sd[2]
			local leg = B(root, "Leg" .. n, V3(0.72, 1.25, 0.88), CF(s * 0.4, 0.75, 0), pants, "Main", V3(s * 0.4, 1.4, 0))
			B(leg, "Shoe" .. n, V3(0.76, 0.26, 1.04), CF(s * 0.4, 0.13, -0.07), DARK, "Accent")
		end
	end

	-- head
	Kit.VCyl(model, body, "Neck", 0.16, 0.7, CF(0, TORSO_Y1 + 0.05, 0), skin, "Belly")
	local head = B(body, "Head", HEAD_SIZE, CF(0, HEAD_Y, 0), skin, "Belly", V3(0, TORSO_Y1 + 0.06, 0))
	local hcf = head.CFrame
	local fz = -HEAD_SIZE.Z / 2
	if robot then
		Kit.Face(model, head, { Spread = 0.5, EyeY = 0.15, EyeScale = 0.4, Glow = A, NoBlush = true, NoMouth = true })
		B(head, "Mouth", V3(0.7, 0.26, 0.08), hcf * CF(0, -0.33, fz - 0.03), DARK, "Face")
		for _, y in { -0.28, -0.38 } do
			B(head, "Grille", V3(0.6, 0.04, 0.05), hcf * CF(0, y, fz - 0.07), A, "Glow").Material = Neon
		end
		for _, s in { -1, 1 } do
			Kit.Add(model, head, "Bolt", "Cyl", V3(0.16, 0.36, 0.36), hcf * CF(s * 0.8, 0, 0), STEEL, "Accent")
		end
	else
		Kit.Face(model, head, { Spread = 0.5, EyeY = 0.15, EyeScale = 0.4, NoMouth = true })
		local mcf = hcf * CF(0, -0.34, fz - 0.02)
		Kit.Add(model, head, "Mouth", "Ell", V3(0.62, 0.28, 0.1), mcf, Kit.Ink, "Face")
		B(head, "Teeth", V3(0.42, 0.07, 0.05), mcf * CF(0, 0.07, -0.04), Kit.White, "Face")
		Kit.Add(model, head, "Tongue", "Ell", V3(0.28, 0.1, 0.05), mcf * CF(0, -0.07, -0.04), C(240, 110, 130), "Face")
	end
	local hat = costume.Hat
	if not robot and (hat == nil or HAIR_TOP_OK[hat]) then
		local hair = lum(A) < 0.45 and A or C(95, 62, 40)
		B(head, "Hair", V3(1.56, 0.32, 1.36), hcf * CF(0, 0.55, 0.02), hair, "Accent")
		if not HAIR_BACK_OFF[hat or ""] then
			B(head, "HairBack", V3(1.56, 0.85, 0.3), hcf * CF(0, 0.15, 0.56), hair, "Accent")
		end
	elseif not robot and hat and not HAIR_BACK_OFF[hat] then
		local hair = lum(A) < 0.45 and A or C(95, 62, 40)
		B(head, "HairBack", V3(1.56, 0.7, 0.3), hcf * CF(0, 0.05, 0.56), hair, "Accent")
	end
	local top = CF(0, HEAD_Y + HEAD_SIZE.Y / 2, 0)
	if Hero.Hat(model, head, top, 1, hat, P, S, A) then
		ctx.TopCount = 1
	elseif robot then
		Kit.VCyl(model, head, "HeadStud", 0.22, 0.65, top * CF(0, 0.1, 0), skin, "Belly")
	end

	-- arms + C-shaped hands
	local hands = {}
	for _, sd in { { -1, "L" }, { 1, "R" } } do
		local s, n = sd[1], sd[2]
		local sh = V3(s * SHOULDER.X, SHOULDER.Y, 0)
		local acf = CF(sh) * ANG(s > 0 and rad(14) or rad(4), 0, s * rad(10)) * CF(s * 0.14, -0.5, 0)
		local arm = B(body, "Arm" .. n, V3(0.42, 1.05, 0.52), acf, P, "Main", sh)
		local hcf2 = acf * CF(0, -0.66, -0.05)
		local hand = Kit.VCyl(model, arm, "Hand" .. n, 0.36, 0.44, hcf2, skin, "Belly")
		B(hand, "HandSlot", V3(0.14, 0.38, 0.12), hcf2 * CF(0, 0, -0.19), Kit.Darker(skin, 0.45), "Face")
		hands[n] = hand
	end

	-- outfit
	local face = costume.Face
	if body_ == "Robot" then
		B(body, "ChestPanel", V3(0.85, 0.7, 0.08), CF(0, 2.4, -0.47), DARK, "Accent")
		for i, col in { C(255, 70, 70), A, C(255, 220, 60) } do
			B(body, "PanelLight", V3(0.16, 0.16, 0.06), CF((i - 2) * 0.24, 2.5, -0.53), col, "Glow").Material = Neon
		end
	elseif body_ == "Armor" then
		local armor = P:Lerp(C(205, 210, 222), 0.5)
		B(body, "ChestPlate", V3(1.35, 1.0, 0.18), CF(0, 2.42, -0.5), armor, "Accent")
		Kit.Diamond(model, body, "ChestGem", 0.3, 0.08, CF(0, 2.5, -0.62), A, "Glow", Neon)
		for _, n in { "L", "R" } do
			local arm = model:FindFirstChild("Arm" .. n) :: BasePart
			B(arm, "Pauldron", V3(0.62, 0.3, 0.7), arm.CFrame * CF(0, 0.5, 0), armor, "Accent")
		end
	elseif body_ == "Robe" then
		B(body, "Robe", V3(1.7, 1.35, 1.05), CF(0, 0.82, 0), P, "Main")
		B(body, "RobeHem", V3(1.78, 0.2, 1.12), CF(0, 0.22, 0), A, "Accent")
		B(body, "Sash", V3(1.66, 0.22, 0.9), CF(0, 1.78, 0), A, "Accent")
	elseif body_ == "Dress" then
		B(body, "Skirt", V3(1.8, 0.85, 1.12), CF(0, 1.2, 0), P, "Main")
		B(body, "SkirtHem", V3(1.86, 0.16, 1.18), CF(0, 0.82, 0), A, "Accent")
		emblem(ctx, body)
	elseif body_ == "Suit" then
		B(body, "ShirtFront", V3(0.45, 1.2, 0.06), CF(0, 2.32, -0.44), Kit.White, "Belly")
		B(body, "Tie", V3(0.18, 0.85, 0.08), CF(0, 2.3, -0.49), A, "Accent")
		B(body, "TieKnot", V3(0.24, 0.16, 0.09), CF(0, 2.8, -0.5), A, "Accent")
	elseif body_ == "Jacket" then
		for _, s in { -1, 1 } do
			B(body, "Lapel", V3(0.36, 1.28, 0.12), CF(s * 0.43, 2.3, -0.46), P, "Main")
		end
		B(body, "Collar", V3(1.3, 0.25, 0.4), CF(0, 2.98, 0.3), P, "Main")
	elseif not ghost then
		emblem(ctx, body)
	end
	if ghost then
		B(body, "Belt", V3(1.66, 0.22, 0.9), CF(0, 1.75, 0), A, "Accent")
	end

	if face == "Visor" then
		local v = B(head, "Visor", V3(1.56, 0.45, 0.1), hcf * CF(0, 0.1, fz - 0.21), A, "Glass")
		v.Material, v.Transparency, v.Reflectance = Glass, 0.35, 0.3
	elseif face == "Goggles" then
		B(head, "GoggleStrap", V3(1.58, 0.2, 1.38), hcf * CF(0, 0.5, 0), DARK, "Accent")
		for _, s in { -1, 1 } do
			local l = Kit.Add(model, head, "GoggleLens", "Cyl", V3(0.18, 0.38, 0.38), hcf * CF(s * 0.33, 0.5, fz - 0.06)
				* ANG(0, HALF_PI, 0), A, "Glass", Glass)
			l.Transparency, l.Reflectance = 0.2, 0.3
		end
	elseif face == "Mask" then
		B(head, "Mask", V3(1.58, 0.55, 1.38), hcf * CF(0, -0.38, 0), Kit.Darker(P, 0.2), "Accent")
	elseif face == "Beard" then
		B(head, "Moustache", V3(0.75, 0.16, 0.14), hcf * CF(0, -0.2, fz - 0.07), A, "Accent")
		B(head, "Beard", V3(1.3, 0.5, 0.25), hcf * CF(0, -0.48, fz + 0.03), A, "Accent")
		Kit.Add(model, head, "BeardTip", "Ell", V3(1.0, 0.8, 0.5), hcf * CF(0, -0.95, fz + 0.12), A, "Accent")
	elseif face == "Eyepatch" then
		B(head, "Eyepatch", V3(0.5, 0.45, 0.08), hcf * CF(0.325, 0.1, fz - 0.22), Kit.Ink, "Face")
		B(head, "PatchStrap", V3(1.58, 0.08, 1.38), hcf * CF(0, 0.15, 0) * ANG(0, 0, rad(-18)), Kit.Ink, "Face")
	elseif face == "Glasses" then
		for _, s in { -1, 1 } do
			local l = B(head, "Lens", V3(0.5, 0.42, 0.05), hcf * CF(s * 0.33, 0.1, fz - 0.2), Kit.Lighter(A, 0.5), "Glass")
			l.Material, l.Transparency = Glass, 0.5
		end
		B(head, "GlassesBridge", V3(0.2, 0.06, 0.05), hcf * CF(0, 0.18, fz - 0.2), Kit.Ink, "Face")
	elseif face == "Scarf" then
		B(body, "Scarf", V3(1.35, 0.3, 1.0), CF(0, TORSO_Y1 - 0.05, 0), A, "Accent")
		B(body, "ScarfTail", V3(0.35, 0.75, 0.12), CF(0.35, TORSO_Y1 - 0.5, -0.5) * ANG(0, 0, rad(10)), A, "Accent")
	end

	-- back
	local back = costume.Back
	if back == "Cape" then
		local piv = V3(0, TORSO_Y1, 0.5)
		B(body, "Cape", V3(1.5, 1.9, 0.1), CF(piv) * ANG(rad(-8), 0, 0) * CF(0, -0.95, 0), A, "Accent", piv)
		B(body, "CapeCollar", V3(1.3, 0.2, 0.5), CF(0, TORSO_Y1 - 0.02, 0.32), Kit.Darker(A, 0.2), "Accent")
	elseif back == "Jetpack" then
		B(body, "Jetpack", V3(1.0, 1.0, 0.35), CF(0, 2.35, 0.6), STEEL, "Accent")
		for _, sd in { { -1, "L" }, { 1, "R" } } do
			local s, n = sd[1], sd[2]
			Kit.VCyl(model, body, "JetTank", 1.2, 0.45, CF(s * 0.32, 2.3, 0.85), A, "Accent")
			local flame = Kit.Add(model, body, "JetFlame" .. n, "Ell", V3(0.32, 0.6, 0.32), CF(s * 0.32, 1.45, 0.85),
				C(255, 150, 40), "Glow", Neon, V3(s * 0.32, 1.72, 0.85))
			flame.CastShadow = false
			Kit.Emitter(flame, { Name = "JetFire", Color = C(255, 200, 80), Color2 = C(255, 60, 20), Rate = 10, Life = 0.35,
				Speed = 2.5, Spread = 10, Size = 0.3, Texture = Kit.FireTexture, Accel = V3(0, -2, 0) })
		end
	elseif back == "Wings" then
		local wing = Kit.Lighter(A, 0.35)
		for _, sd in { { -1, "L" }, { 1, "R" } } do
			local s, n = sd[1], sd[2]
			local piv = V3(s * 0.25, 2.6, 0.48)
			local base = CF(piv) * ANG(0, s * rad(-25), 0)
			local w = B(body, "Wing" .. n, V3(1.4, 1.0, 0.1), base * CF(s * 0.7, 0.15, 0), wing, "Accent", piv)
			B(w, "WingTip", V3(0.8, 0.5, 0.08), base * CF(s * 1.25, 0.65, 0) * ANG(0, 0, s * rad(35)), A, "Accent")
		end
	elseif back == "Backpack" then
		local col = Kit.Darker(P:Lerp(C(150, 100, 55), 0.5), 0.1)
		B(body, "Backpack", V3(1.0, 1.05, 0.5), CF(0, 2.25, 0.65), col, "Accent")
		B(body, "BackpackFlap", V3(1.02, 0.4, 0.52), CF(0, 2.62, 0.66), Kit.Darker(col, 0.2), "Accent")
		B(body, "BackpackPocket", V3(0.6, 0.35, 0.12), CF(0, 2.05, 0.94), Kit.Darker(col, 0.2), "Accent")
	elseif back == "Quiver" then
		local qcf = CF(0.15, 2.4, 0.66) * ANG(0, 0, rad(25))
		Kit.VCyl(model, body, "Quiver", 1.3, 0.45, qcf, C(140, 90, 50), "Accent")
		for i = -1, 1 do
			B(body, "Fletch", V3(0.1, 0.3, 0.18), qcf * CF(i * 0.12, 0.8, 0), A, "Accent")
		end
	end

	buildItem(ctx, hands.R, costume.Item)

	if ghost then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				local role = d:GetAttribute("Role")
				if role == "Main" or role == "Belly" or role == "Accent" then
					d.Transparency = math.max(d.Transparency, 0.3)
				end
			end
		end
		Kit.Emitter(body, { Name = "GhostWisps", Color = Kit.Lighter(P, 0.4), Rate = 3, Life = 1.3, Speed = 0.4, Size = 0.35,
			Accel = V3(0, 1, 0), Transp = 0.5 })
	end

	Kit.Brickify(model)
	ctx.Body, ctx.Head = body, head
	ctx.Radius = 1.45
	ctx.HasHalo = hat == "Crown"
end

return Hero

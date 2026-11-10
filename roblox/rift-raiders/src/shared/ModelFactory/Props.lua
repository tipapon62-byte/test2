-- Base props: incubator, fuse machine, shop terminal, bear trap, foam bat.

local Kit = require(script.Parent.Style)

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local C = Color3.fromRGB
local Neon, Metal, Glass = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Glass

local Props = {}

local function noShadow(p: BasePart)
	p.CastShadow = false
	return p
end

-- ===================================================================== incubator (~6 studs wide)

local PAD_TOP_Y = 1.0

function Props.Incubator(): Model
	local model, root = Kit.NewModel("Incubator")
	local cyan, heat = C(90, 255, 220), C(255, 140, 50)
	local base = Kit.VCyl(model, root, "Base", 0.6, 6, CF(0, 0.3, 0), C(55, 60, 85), "Main", Metal)
	noShadow(Kit.VCyl(model, base, "Rim", 0.18, 6.3, CF(0, 0.55, 0), cyan, "Glow", Neon))
	local deck = Kit.VCyl(model, base, "Deck", 0.3, 5.2, CF(0, 0.75, 0), C(215, 222, 240), "Belly")
	local pad = noShadow(Kit.VCyl(model, deck, "Pad", 0.12, 3.4, CF(0, PAD_TOP_Y - 0.06, 0), cyan, "Glow", Neon))
	pad.Transparency = 0.15
	Kit.Ring(model, deck, "HeatCoil", CF(0, PAD_TOP_Y - 0.04, 0), 2.05, 0.2, 0.16, 10, heat, "Glow", Neon)
	for i = 1, 4 do
		local a = rad(45 + (i - 1) * 90)
		local dx, dz = math.cos(a), math.sin(a)
		local post = Kit.VCyl(model, base, "Post", 2.6, 0.45, CF(dx * 2.75, 2.0, dz * 2.75), C(70, 78, 105), "Main", Metal)
		local top = V3(dx * 2.5, 4.3, dz * 2.5)
		Kit.Pipe(model, post, "Claw", V3(dx * 2.75, 3.25, dz * 2.75), top, 0.4, C(215, 222, 240), "Belly")
		noShadow(Kit.Add(model, post, "ClawTip", "Ball", V3(0.5, 0.5, 0.5), CF(top), cyan, "Glow", Neon))
		for _, y in { 1.45, 2.15 } do
			noShadow(Kit.VCyl(model, post, "Coil", 0.18, 0.62, CF(dx * 2.75, y, dz * 2.75), heat, "Glow", Neon))
		end
	end
	local holo = Kit.Ring(model, base, "HoloRing", CF(0, 4.7, 0), 2.3, 0.08, 0.12, 8, cyan, "Glow", Neon)
	for _, p in holo do
		p.Transparency = 0.45
	end
	Kit.Light(pad, cyan, 10, 1.2)
	Kit.Emitter(pad, { Name = "Warmth", Color = C(255, 200, 120), Color2 = cyan, Rate = 3, Life = 1.6, Speed = 0.6,
		Spread = 15, Size = 0.2, Accel = V3(0, 1, 0) })
	model:SetAttribute("PadTopY", PAD_TOP_Y)
	model:SetAttribute("Height", 4.95)
	model:SetAttribute("Archetype", "Incubator")
	return model
end

-- ===================================================================== fuse machine (~10 studs tall)

function Props.FuseMachine(): Model
	local model, root = Kit.NewModel("FuseMachine")
	local purple, cyan, gold = C(200, 90, 255), C(90, 230, 255), C(255, 205, 70)
	local metal, dark = C(160, 165, 190), C(45, 40, 70)
	local base = Kit.Add(model, root, "Base", "Block", V3(11, 0.8, 7.5), CF(0, 0.4, 0), dark, "Main", Metal)
	noShadow(Kit.Add(model, base, "Trim", "Block", V3(11.15, 0.14, 7.65), CF(0, 0.78, 0), purple, "Glow", Neon))

	for i, x in { -3.4, 0, 3.4 } do
		local ped = Kit.VCyl(model, base, "Pedestal", 0.7, 2.2, CF(x, 1.15, -2), metal, "Belly", Metal)
		noShadow(Kit.VCyl(model, ped, "InputRing", 0.15, 2.3, CF(x, 1.55, -2), cyan, "Glow", Neon))
		local cap = Kit.Add(model, ped, "Input" .. i, "Ell", V3(1.8, 2.8, 1.8), CF(x, 2.95, -2), C(220, 245, 255), "Glass",
			Glass)
		cap.Transparency = 0.6
		Kit.VCyl(model, ped, "InputCap", 0.4, 1.4, CF(x, 4.45, -2), metal, "Belly", Metal)
		Kit.Pipe(model, base, "Pipe", V3(x, 4.5, -2), V3(x * 0.25, 4.6, 0.6), 0.32, purple, "Glow", Neon)
	end

	local rbase = Kit.VCyl(model, base, "ReactorBase", 1.2, 4, CF(0, 1.4, 1.6), metal, "Belly", Metal)
	local cage = Kit.Add(model, rbase, "ReactorGlass", "Ell", V3(3.2, 4.2, 3.2), CF(0, 4.1, 1.6), C(220, 240, 255), "Glass",
		Glass)
	cage.Transparency = 0.55
	local core = noShadow(Kit.Add(model, rbase, "Core", "Ell", V3(1.8, 2.5, 1.8), CF(0, 4.1, 1.6), purple, "Glow", Neon))
	for _, y in { 2.9, 5.3 } do
		noShadow(Kit.VCyl(model, rbase, "ReactorRing", 0.25, 3.45, CF(0, y, 1.6), cyan, "Glow", Neon))
	end
	local cap = Kit.VCyl(model, rbase, "ReactorCap", 0.8, 2.6, CF(0, 6.55, 1.6), metal, "Belly", Metal)
	Kit.Add(model, cap, "Dome", "Ell", V3(2.6, 1.4, 2.6), CF(0, 6.95, 1.6), dark, "Main", Metal)
	Kit.VCyl(model, cap, "Antenna", 1.8, 0.25, CF(0, 8.4, 1.6), metal, "Belly", Metal)
	noShadow(Kit.Add(model, cap, "AntennaBulb", "Ball", V3(0.75, 0.75, 0.75), CF(0, 9.55, 1.6), gold, "Glow", Neon))
	Kit.Light(core, purple, 14, 2)
	Kit.Emitter(core, { Name = "FuseSparks", Color = purple, Color2 = cyan, Rate = 8, Life = 0.8, Speed = 1.5, Size = 0.3,
		Rot = 120 })

	-- "FUSE" sign
	local sign = Kit.Add(model, cap, "Sign", "Block", V3(4.2, 1.2, 0.3), CF(0, 7.55, 0.05), dark, "Main")
	noShadow(Kit.Add(model, sign, "SignFrame", "Block", V3(4.4, 1.4, 0.2), CF(0, 7.55, 0.15), purple, "Glow", Neon))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.PixelsPerStud = 50
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "FUSE"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = C(255, 235, 120)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = C(90, 20, 120)
	label.Parent = gui
	gui.Parent = sign

	-- output pod
	local opod = Kit.VCyl(model, base, "OutputPedestal", 0.9, 2.4, CF(4.4, 1.25, 1.9), metal, "Belly", Metal)
	noShadow(Kit.VCyl(model, opod, "OutputPad", 0.15, 2.0, CF(4.4, 1.75, 1.9), gold, "Glow", Neon))
	local dome = Kit.Add(model, opod, "OutputDome", "Ell", V3(2.2, 2.4, 2.2), CF(4.4, 2.3, 1.9), C(255, 245, 220), "Glass",
		Glass)
	dome.Transparency = 0.65
	Kit.Pipe(model, base, "Pipe", V3(1.4, 2.4, 1.6), V3(4.1, 2.4, 1.9), 0.32, gold, "Glow", Neon)

	-- big friendly button
	local btnBase = Kit.VCyl(model, base, "ButtonBase", 0.3, 1.5, CF(0, 0.95, -3.25), dark, "Main", Metal)
	noShadow(Kit.VCyl(model, btnBase, "FuseButton", 0.25, 1.1, CF(0, 1.2, -3.25), C(255, 70, 90), "Glow", Neon))

	model:SetAttribute("Height", 9.95)
	model:SetAttribute("Archetype", "FuseMachine")
	return model
end

-- ===================================================================== shop terminal

function Props.ShopTerminal(): Model
	local model, root = Kit.NewModel("ShopTerminal")
	local bodyCol, trim = C(70, 200, 255), C(255, 255, 255)
	local base = Kit.Add(model, root, "Base", "Block", V3(4.4, 0.5, 2.9), CF(0, 0.25, 0), C(45, 50, 75), "Main", Metal)
	local body = Kit.Add(model, base, "Body", "Block", V3(4, 5, 2.4), CF(0, 3.0, 0), bodyCol, "Main")
	local top = Kit.Add(model, body, "Top", "Cyl", V3(4, 2.4, 2.4), CF(0, 5.5, 0), bodyCol, "Main")
	Kit.Add(model, body, "Bezel", "Block", V3(3.5, 2.35, 0.08), CF(0, 3.85, -1.2), trim, "Belly")
	local screen = Kit.Add(model, body, "Screen", "Block", V3(3.2, 2.05, 0.1), CF(0, 3.85, -1.24), C(25, 30, 55), "Face")
	screen.CastShadow = false
	Kit.Light(screen, C(120, 200, 255), 6, 0.6)
	-- awning
	for i = 1, 4 do
		local x = -1.65 + (i - 1) * 1.1
		noShadow(Kit.Add(model, body, "Awning", "Block", V3(1.1, 0.18, 1.0),
			CF(x, 5.1, -1.55) * ANG(rad(-18), 0, 0), i % 2 == 0 and trim or C(255, 90, 110), "Accent"))
	end
	-- friendly face on the rounded top
	Kit.Face(model, top, { EyeScale = 0.3, Spread = 0.24, EyeY = 0.2, MouthDir = V3(0, -0.15, -1) })
	-- keypad, coin slot, dispenser tray
	for i, col in { C(255, 90, 110), C(255, 220, 70), C(90, 255, 160) } do
		noShadow(Kit.Add(model, body, "Key", "Ball", V3(0.32, 0.32, 0.32), CF(0.9 + (i - 2) * 0.45, 2.3, -1.22), col, "Glow",
			Neon))
	end
	Kit.Add(model, body, "CoinSlot", "Block", V3(0.6, 0.12, 0.08), CF(-1.0, 2.3, -1.22), C(30, 30, 40), "Face")
	Kit.Add(model, body, "Tray", "Block", V3(2.2, 0.5, 0.6), CF(0, 1.35, -1.35), C(40, 44, 66), "Main", Metal)
	-- antenna + spinning coin sign
	Kit.VCyl(model, top, "Antenna", 1.0, 0.18, CF(1.4, 7.1, 0), C(200, 205, 220), "Belly", Metal)
	noShadow(Kit.Add(model, top, "AntennaBulb", "Ball", V3(0.45, 0.45, 0.45), CF(1.4, 7.65, 0), C(255, 220, 70), "Glow", Neon))
	local coin = Kit.Add(model, top, "Coin", "Cyl", V3(0.25, 1.5, 1.5), CF(-0.6, 7.6, 0) * ANG(0, math.pi / 2, 0), Kit.Gold,
		"Accent", Enum.Material.Foil, V3(-0.6, 6.7, 0))
	Kit.Add(model, coin, "CoinFace", "Cyl", V3(0.3, 1.05, 1.05), coin.CFrame, C(255, 235, 140), "Accent")
	Kit.VCyl(model, top, "CoinStick", 0.6, 0.15, CF(-0.6, 6.9, 0), C(200, 205, 220), "Belly", Metal)
	model:SetAttribute("Height", 8.35)
	model:SetAttribute("Archetype", "ShopTerminal")
	return model
end

-- ===================================================================== bear trap (~4 studs, flat)

local JAW_R = 1.75
local JAW_ANGLE = rad(85)

local function buildJaw(model, root, name: string, side: number)
	-- semicircle of 5 chord segments on the `side` (-1 = -X) half, ends at the hinge points (0, ±R)
	local steel = C(165, 172, 185)
	local pts = {}
	for i = 0, 5 do
		local phi = rad(-90 + i * 36)
		table.insert(pts, V3(side * JAW_R * math.cos(phi), 0.22, JAW_R * math.sin(phi)))
	end
	local main
	local segs = {}
	for i = 1, 5 do
		local a, b = pts[i], pts[i + 1]
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, b)
		local len = (b - a).Magnitude * 1.08
		local seg
		if i == 3 then
			seg = Kit.Add(model, root, name, "Block", V3(0.22, 0.26, len), cf, steel, "Main", Metal, V3(0, 0.22, 0))
			main = seg
		end
		segs[i] = { cf, len, seg }
	end
	for i = 1, 5 do
		local cf, len = segs[i][1], segs[i][2]
		if i ~= 3 then
			Kit.Add(model, main, name .. "Seg", "Block", V3(0.22, 0.26, len), cf, steel, "Main", Metal)
		end
		if i >= 2 and i <= 4 then
			for _, t in { -0.25, 0.25 } do
				local tooth = Kit.Add(model, main, name .. "Tooth", "Wedge", V3(0.14, 0.42, 0.34),
					cf * CF(0, 0.32, t * len), C(235, 238, 245), "Accent", Metal)
				tooth.CastShadow = false
			end
		end
	end
end

function Props.BearTrap(): Model
	local model, root = Kit.NewModel("BearTrap")
	local dark = C(70, 72, 82)
	local base = Kit.VCyl(model, root, "Base", 0.18, 1.6, CF(0, 0.09, 0), dark, "Main", Metal)
	noShadow(Kit.VCyl(model, base, "Plate", 0.08, 1.1, CF(0, 0.21, 0), C(255, 200, 40), "Accent"))
	Kit.Add(model, base, "Hinge", "Cyl", V3(2 * JAW_R + 0.3, 0.22, 0.22), CF(0, 0.2, 0) * ANG(0, math.pi / 2, 0), dark,
		"Main", Metal)
	for _, z in { -1, 1 } do
		Kit.Add(model, base, "Spring", "Block", V3(0.55, 0.2, 1.3), CF(0, 0.12, z * (JAW_R + 0.75)), dark, "Main", Metal)
		noShadow(Kit.Add(model, base, "SpringCoil", "Cyl", V3(0.5, 0.36, 0.36), CF(0, 0.22, z * (JAW_R + 0.35)), C(255, 90, 60),
			"Glow"))
	end
	buildJaw(model, root, "JawL", -1)
	buildJaw(model, root, "JawR", 1)
	model:SetAttribute("Height", 0.5)
	model:SetAttribute("Archetype", "BearTrap")
	model:SetAttribute("Closed", false)
	return model
end

-- Rotates the jaws around the hinge (Z axis through the trap centre). Uses C0 so it replicates.
function Props.SetTrapClosed(model: Model, closed: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and (d.Name == "JawL" or d.Name == "JawR") then
			local sign = d.Name == "JawL" and -1 or 1
			d.C0 = CF(d.C0.Position) * ANG(0, 0, closed and sign * JAW_ANGLE or 0)
		end
	end
	model:SetAttribute("Closed", closed)
end

-- ===================================================================== foam bat (~4.5 studs)

-- "Handle" is an invisible axis-aligned grip block: the bat extends along Handle's +Y (up), grip centre = Handle CFrame.
function Props.FoamBat(): Model
	local model, root = Kit.NewModel("FoamBat")
	local pink, cyan, yellow = C(255, 90, 170), C(80, 220, 255), C(255, 225, 60)
	local handle = Kit.Add(model, root, "Handle", "Block", V3(0.45, 1.1, 0.45), CF(0, 0.75, 0), C(45, 45, 60), "Main")
	handle.Transparency = 1
	handle.CastShadow = false
	Kit.VCyl(model, handle, "Grip", 1.1, 0.42, CF(0, 0.75, 0), C(45, 45, 60), "Main")
	Kit.Add(model, handle, "Pommel", "Ball", V3(0.6, 0.6, 0.6), CF(0, 0.22, 0), yellow, "Accent")
	Kit.VCyl(model, handle, "Guard", 0.2, 0.8, CF(0, 1.35, 0), cyan, "Accent")
	local foam = Kit.VCyl(model, handle, "Foam", 2.6, 0.95, CF(0, 2.75, 0), pink, "Main")
	for i, y in { 1.95, 2.75, 3.55 } do
		noShadow(Kit.VCyl(model, foam, "Stripe", 0.2, 0.99, CF(0, y, 0) * ANG(rad(12), 0, 0), i == 2 and yellow or cyan,
			"Accent"))
	end
	Kit.Add(model, foam, "Tip", "Ball", V3(1.0, 1.0, 1.0), CF(0, 4.05, 0), Kit.Lighter(pink, 0.15), "Main")
	noShadow(Kit.Diamond(model, foam, "Sticker", 0.42, 0.06, CF(0, 2.35, -0.47), yellow, "Glow", Neon))
	model:SetAttribute("Height", 4.55)
	model:SetAttribute("Archetype", "FoamBat")
	return model
end

return Props

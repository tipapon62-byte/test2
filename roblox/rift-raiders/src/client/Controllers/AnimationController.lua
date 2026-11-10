-- AnimationController: client-side procedural animation for ModelFactory models.
-- Drives Motor6D.Transform only (never moves the server-owned Root), so it is purely cosmetic and local.
--   RR_Pet          bouncy idle, breathing, blinks, wing flaps, tail wags, serpent waves, rainbow hue,
--                   occasional happy jump / spin, propeller spinners, rotating aura ring for Legendary+
--   RR_Egg          gentle wobble
--   RR_IncubatorEgg hatching show: wobble growing with progress, crack lines in 3 stages, glow +
--                   sparkles + little hops in the last 10 s (cracks/glow are local parts)
--   RR_Guardian     speed-scaled walk/run cycle with heavy stomps while chasing, roar pose on "Alert",
--                   state bubble (! / ? / stars), attack lunge, stunned wobble
-- LowGraphics: 20 Hz updates, no aura rings / sparkles / secondary motion. Everything beyond
-- CULL_DISTANCE is frozen and its local effects hidden.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local AnimationController = {}

local TAGS = {
	RR_Pet = "Pet",
	RR_Egg = "Egg",
	RR_IncubatorEgg = "IncubatorEgg",
	RR_Guardian = "Guardian",
}
local CULL_DISTANCE = 160
local LOW_RATE = 1 / 20 -- update rate when LowGraphics is on
local BLINK_PARTS = {
	EyeL = true, EyeR = true, PupilL = true, PupilR = true, ShineL = true, ShineR = true, IrisL = true, IrisR = true,
}
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local CRACK_COLOR = Color3.fromRGB(30, 22, 40)
local AURA_SEGMENTS = 10

local CF, ANG = CFrame.new, CFrame.Angles
local sin, cos, abs, clamp = math.sin, math.cos, math.abs, math.clamp
local TAU = math.pi * 2

type Crack = { part: BasePart, rel: CFrame }

type Rec = {
	model: Model,
	kind: string,
	root: BasePart?,
	joints: { [string]: Motor6D },
	rootJoints: { Motor6D },
	segs: { Motor6D },
	tendrils: { Motor6D },
	orbits: { Motor6D },
	spinners: { Motor6D },
	legsQuad: { { m: Motor6D, phase: number } },
	blink: { BasePart },
	main: { BasePart },
	shells: { BasePart },
	mesh: SpecialMesh?,
	meshScale: Vector3,
	scale: number,
	arch: string,
	rarityIndex: number,
	rarityColor: Color3,
	phase: number,
	t: number,
	dirty: boolean,
	nextBlink: number,
	blinkUntil: number,
	rainbowOn: boolean,
	lastPos: Vector3?,
	lastSeen: number,
	speed: number,
	cycle: number,
	state: string?,
	stateAt: number,
	bubble: BillboardGui?,
	bubbleLabel: TextLabel?,
	nextHappy: number,
	happyAt: number,
	happySpin: boolean,
	groupActive: boolean,
	aura: { BasePart }?,
	auraRadius: number,
	cracks: { Crack },
	crackStage: number,
	glowAnchor: BasePart?,
	glowLight: PointLight?,
	glowSparks: ParticleEmitter?,
	conns: { RBXScriptConnection },
}

local records: { [Model]: Rec } = {}
local origColors: { [BasePart]: Color3 } = setmetatable({}, { __mode = "k" }) :: any
local started = false
local rng = Random.new()
local fxFolder: Folder? = nil

local function setT(m: Motor6D?, cf: CFrame)
	if m and m.Parent then
		m.Transform = cf
	end
end

-- Local-only effect parts (cracks, aura ring, glow anchor) live in one client folder.
local function localPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	if not fxFolder or not fxFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "RR_LocalFx"
		f.Parent = workspace
		fxFolder = f
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = fxFolder
	return p
end

local function rarityOf(model: Model): (number, Color3)
	local r = model:GetAttribute("Rarity")
	local cfg = typeof(r) == "string" and GameConfig.Rarities.ById[r] or nil
	if cfg then
		return cfg.Index, cfg.Color
	end
	return 1, Color3.new(1, 1, 1)
end

local function scan(rec: Rec)
	local joints, segs, tendrils, orbits, spinners, blink, main, shells = {}, {}, {}, {}, {}, {}, {}, {}
	local legsQuad, rootJoints = {}, {}
	local rootInst: Instance? = rec.model.PrimaryPart or rec.model:FindFirstChild("Root")
	local root = (rootInst and rootInst:IsA("BasePart")) and rootInst or nil
	for _, d in rec.model:GetDescendants() do
		if d:IsA("Motor6D") then
			local n = d.Name
			if not joints[n] then
				joints[n] = d
			end
			if root and d.Part0 == root and n ~= "RarityRing" then
				table.insert(rootJoints, d)
			end
			local seg = string.match(n, "^Seg(%d+)$")
			if seg then
				segs[tonumber(seg) :: number] = d
			elseif string.match(n, "^Tendril%d+$") then
				table.insert(tendrils, d)
			elseif string.match(n, "^Orbit%d+$") then
				table.insert(orbits, d)
			elseif string.match(n, "^Spinner%d+$") then
				table.insert(spinners, d)
			end
		elseif d:IsA("BasePart") then
			if BLINK_PARTS[d.Name] and d.Parent == rec.model then
				table.insert(blink, d)
			end
			if d:GetAttribute("Role") == "Main" then
				table.insert(main, d)
				if not origColors[d] then
					origColors[d] = d.Color
				end
			end
			if d.Name == "Body" or d.Name == "Shell" then
				table.insert(shells, d)
			end
		end
	end
	-- Seg1..SegN in order
	local ordered = {}
	local i = 1
	while segs[i] do
		table.insert(ordered, segs[i])
		i += 1
	end
	-- diagonal gait pairs (FL+BR / FR+BL; middle bug legs follow the opposite group)
	for name, phase in { LegFL = 0, LegBR = 0, LegMR = 0, LegFR = math.pi, LegBL = math.pi, LegML = math.pi } do
		if joints[name] then
			table.insert(legsQuad, { m = joints[name], phase = phase })
		end
	end
	rec.joints, rec.segs, rec.tendrils, rec.orbits, rec.spinners = joints, ordered, tendrils, orbits, spinners
	rec.legsQuad, rec.blink, rec.main, rec.shells, rec.rootJoints = legsQuad, blink, main, shells, rootJoints
	local body = rec.model:FindFirstChild("Body")
	local mesh = body and body:FindFirstChildOfClass("SpecialMesh")
	if mesh ~= rec.mesh then
		rec.mesh = mesh
		rec.meshScale = mesh and mesh.Scale or Vector3.one
	end
	rec.scale = rec.model:GetScale()
	local arch = rec.model:GetAttribute("Archetype")
	rec.arch = typeof(arch) == "string" and arch or ""
	rec.rarityIndex, rec.rarityColor = rarityOf(rec.model)
	local ring = rec.model:FindFirstChild("RarityRing")
	rec.auraRadius = (ring and ring:IsA("BasePart")) and ring.Size.Y * 0.5 + 0.3 * rec.scale or 2 * rec.scale
	rec.root = root
	rec.dirty = false
end

local function restoreRainbow(rec: Rec)
	for _, p in rec.main do
		local c = origColors[p]
		if c then
			p.Color = c
		end
	end
	rec.rainbowOn = false
end

local function destroyAura(rec: Rec)
	if rec.aura then
		for _, p in rec.aura do
			p:Destroy()
		end
		rec.aura = nil
	end
end

local function destroyHatchFx(rec: Rec)
	for _, c in rec.cracks do
		c.part:Destroy()
	end
	rec.cracks = {}
	rec.crackStage = 0
	if rec.glowAnchor then
		rec.glowAnchor:Destroy()
	end
	rec.glowAnchor, rec.glowLight, rec.glowSparks = nil, nil, nil
end

local function remove(model: Model)
	local rec = records[model]
	if not rec then
		return
	end
	records[model] = nil
	for _, c in rec.conns do
		c:Disconnect()
	end
	if rec.bubble then
		rec.bubble:Destroy()
	end
	destroyAura(rec)
	destroyHatchFx(rec)
	if rec.rainbowOn and model.Parent then
		restoreRainbow(rec)
	end
	for _, p in rec.blink do
		p.LocalTransparencyModifier = 0
	end
end

local function add(inst: Instance, kind: string)
	if not inst:IsA("Model") or records[inst] then
		return
	end
	local model = inst :: Model
	local rec: Rec = {
		model = model,
		kind = kind,
		root = nil,
		joints = {},
		rootJoints = {},
		segs = {},
		tendrils = {},
		orbits = {},
		spinners = {},
		legsQuad = {},
		blink = {},
		main = {},
		shells = {},
		mesh = nil,
		meshScale = Vector3.one,
		scale = 1,
		arch = "",
		rarityIndex = 1,
		rarityColor = Color3.new(1, 1, 1),
		phase = rng:NextNumber(0, 10),
		t = 0,
		dirty = true,
		nextBlink = rng:NextNumber(1, 4),
		blinkUntil = 0,
		rainbowOn = false,
		lastPos = nil,
		lastSeen = 0,
		speed = 0,
		cycle = 0,
		state = nil,
		stateAt = 0,
		bubble = nil,
		bubbleLabel = nil,
		nextHappy = rng:NextNumber(3, 9),
		happyAt = -10,
		happySpin = false,
		groupActive = false,
		aura = nil,
		auraRadius = 2,
		cracks = {},
		crackStage = 0,
		glowAnchor = nil,
		glowLight = nil,
		glowSparks = nil,
		conns = {},
	}
	records[model] = rec
	-- streaming can deliver descendants late: rescan lazily
	table.insert(rec.conns, model.DescendantAdded:Connect(function()
		rec.dirty = true
	end))
	table.insert(rec.conns, model.DescendantRemoving:Connect(function()
		rec.dirty = true
	end))
	table.insert(rec.conns, model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			remove(model)
		end
	end))
end

-- ===================================================================== shared bits

local function updateBlink(rec: Rec)
	local t = rec.t
	if t >= rec.nextBlink and rec.blinkUntil == 0 then
		rec.blinkUntil = t + 0.12
		for _, p in rec.blink do
			p.LocalTransparencyModifier = 1
		end
	elseif rec.blinkUntil > 0 and t >= rec.blinkUntil then
		rec.blinkUntil = 0
		-- occasional double blink
		rec.nextBlink = t + (rng:NextNumber() < 0.2 and 0.18 or rng:NextNumber(2.2, 5.5))
		for _, p in rec.blink do
			p.LocalTransparencyModifier = 0
		end
	end
end

local function updateRainbow(rec: Rec, now: number, low: boolean)
	local on = rec.model:GetAttribute("Rainbow") == true and not low
	if on then
		rec.rainbowOn = true
		for i, p in rec.main do
			p.Color = Color3.fromHSV((now * 0.15 + i * 0.03) % 1, 0.55, 1)
		end
	elseif rec.rainbowOn then
		restoreRainbow(rec)
	end
end

local function breathe(rec: Rec, k: number)
	local mesh = rec.mesh
	if mesh and mesh.Parent then
		local s = rec.meshScale
		mesh.Scale = Vector3.new(s.X * (1 - k * 0.5), s.Y * (1 + k), s.Z * (1 - k * 0.5))
	end
end

-- Moves every Root-attached part as one piece by `g` (in Root space, pivoting at the model's base).
-- Must run after the per-joint transforms of the frame; joints left untouched this frame are reset first.
local function applyGroup(rec: Rec, g: CFrame?, touched: { [Motor6D]: boolean })
	if not g then
		if rec.groupActive then
			for _, m in rec.rootJoints do
				if not touched[m] and m.Parent then
					m.Transform = CFrame.identity
				end
			end
			rec.groupActive = false
		end
		return
	end
	for _, m in rec.rootJoints do
		if m.Parent then
			local own = touched[m] and m.Transform or CFrame.identity
			m.Transform = m.C0:Inverse() * g * m.C0 * own
		end
	end
	rec.groupActive = true
end

-- ===================================================================== pets

local function updateAura(rec: Rec, show: boolean)
	local root = rec.root
	if not show or not root then
		if rec.aura then
			for _, p in rec.aura do
				p.Transparency = 1
			end
		end
		return
	end
	local r = rec.auraRadius
	if not rec.aura then
		local parts = {}
		local seg = TAU * r / AURA_SEGMENTS * 0.55
		for i = 1, AURA_SEGMENTS do
			local p = localPart("RR_Aura", Vector3.new(0.14, 0.14, seg), rec.rarityColor, Enum.Material.Neon)
			parts[i] = p
		end
		rec.aura = parts
	end
	local t = rec.t
	local s = rec.scale
	local base = root.CFrame
	for i, p in rec.aura :: { BasePart } do
		local a = t * 0.8 + i / AURA_SEGMENTS * TAU
		local y = (0.35 + 0.08 * sin(t * 2 + i)) * s
		p.CFrame = base * ANG(0, a, 0) * CF(r, y, 0)
		p.Transparency = 0.25 + 0.2 * sin(t * 3 + i * 0.7)
	end
end

local function updatePet(rec: Rec, now: number, low: boolean)
	local J = rec.joints
	local t = rec.t + rec.phase
	local s = rec.scale
	local arch = rec.arch
	local touched: { [Motor6D]: boolean } = {}

	-- bouncy idle: floaties drift, blobs squish, everyone else hops in place
	local bob
	if arch == "Floaty" then
		bob = sin(t * 1.6) * 0.28 * s
	elseif arch == "Blob" then
		bob = abs(sin(t * 2.2)) * 0.05 * s
	else
		bob = abs(sin(t * 2.4)) * 0.08 * s
		local h = sin(t * 0.9)
		if h > 0.93 then
			bob += (h - 0.93) / 0.07 * 0.3 * s
		end
	end
	setT(J.Body, CF(0, bob, 0) * ANG(0, 0, sin(t * 1.2) * 0.03))
	if J.Body then
		touched[J.Body] = true
	end
	breathe(rec, sin(t * 2.4) * (arch == "Blob" and 0.06 or 0.025))
	setT(J.Head, ANG(sin(t * 1.1) * 0.05, sin(t * 0.55) * 0.14, sin(t * 0.8) * 0.04))

	-- happy jump / spin every few seconds
	local g: CFrame? = nil
	if rec.t >= rec.nextHappy then
		rec.happyAt = rec.t
		rec.happySpin = rng:NextNumber() < 0.5
		rec.nextHappy = rec.t + rng:NextNumber(6, 14)
	end
	local hk = (rec.t - rec.happyAt) / 0.8
	if hk >= 0 and hk < 1 then
		local hop = sin(hk * math.pi) * (rec.happySpin and 0.55 or 0.9) * s
		local spin = rec.happySpin and (1 - (1 - hk) ^ 2) * TAU or 0
		g = CF(0, hop, 0) * ANG(0, spin, 0)
	end
	applyGroup(rec, g, touched)

	if low then
		if rec.rainbowOn then
			restoreRainbow(rec)
		end
		updateAura(rec, false)
		return
	end

	-- wings: lazy flaps with periodic bursts (and during happy jumps)
	if J.WingL or J.WingR then
		local burst = sin(t * 0.7) > 0.75 or g ~= nil
		local f
		if arch == "Bug" then
			f = burst and (0.25 + sin(t * 30) * 0.1) or 0
		else
			f = burst and (0.35 + sin(t * 16) * 0.45) or sin(t * 2) * 0.08
		end
		setT(J.WingL, ANG(0, 0, -f))
		setT(J.WingR, ANG(0, 0, f))
	end
	setT(J.Tail, ANG(0, sin(t * 4.2) * 0.35, 0))
	setT(J.TailTip, ANG(0, sin(t * 4.2 - 0.8) * 0.3, 0))
	if J.Jaw then
		local chomp = sin(t * 0.8)
		setT(J.Jaw, ANG(chomp > 0.9 and -(chomp - 0.9) * 3 or 0, 0, 0))
	end
	if J.ArmL or J.ArmR then
		local wave = g and 0.9 or 0
		setT(J.ArmL, ANG(sin(t * 1.3) * 0.08, 0, -wave))
		setT(J.ArmR, ANG(-sin(t * 1.3) * 0.08, 0, wave))
	end
	for i, m in rec.segs do
		setT(m, ANG(sin(t * 1.4 - i * 0.6) * 0.05, sin(t * 1.8 - i * 0.8) * 0.12, 0))
	end
	for i, m in rec.tendrils do
		setT(m, ANG(sin(t * 2 + i) * 0.22, 0, cos(t * 1.7 + i * 1.3) * 0.22))
	end
	for _, m in rec.orbits do
		setT(m, ANG(0, t * 1.3, 0))
	end
	for _, m in rec.spinners do
		setT(m, ANG(0, 0, t * 18))
	end
	updateAura(rec, rec.rarityIndex >= 5)
	updateBlink(rec)
	updateRainbow(rec, now, low)
end

-- ===================================================================== eggs

local EGG_FACES = {
	{ n = Vector3.new(0, 0, -1), u = Vector3.new(1, 0, 0) },
	{ n = Vector3.new(1, 0, 0), u = Vector3.new(0, 0, 1) },
	{ n = Vector3.new(0, 0, 1), u = Vector3.new(-1, 0, 0) },
	{ n = Vector3.new(-1, 0, 0), u = Vector3.new(0, 0, -1) },
}
-- per stage: { face, u (-1..1 across the face), h0, h1 (0..1 up the egg), segments }
local CRACK_LINES = {
	{ { 1, 0.1, 0.55, 0.85, 3 } },
	{ { 2, -0.15, 0.35, 0.7, 3 }, { 1, -0.35, 0.25, 0.5, 2 } },
	{ { 4, 0.2, 0.4, 0.8, 3 }, { 3, 0.0, 0.3, 0.75, 3 }, { 1, 0.35, 0.1, 0.32, 2 } },
}

-- Body's CFrame for the Transform we are about to set (Body.CFrame itself lags a frame).
local function bodyFrame(rec: Rec, transform: CFrame): CFrame?
	local m = rec.joints.Body
	if not m or not m.Part0 or not m.Part1 then
		return nil
	end
	return m.Part0.CFrame * m.C0 * transform * m.C1:Inverse()
end

-- Egg surface point in Body space: slabs ("Body"/"Shell") are axis-aligned boxes stacked on Body.
local function crackPoint(rec: Rec, body: BasePart, face, u: number, h: number, ymin: number, ymax: number): Vector3
	local y = ymin + (ymax - ymin) * h
	local half = body.Size.X / 2
	for _, sh in rec.shells do
		if sh.Parent then
			local rel = body.CFrame:ToObjectSpace(sh.CFrame).Position
			if abs(rel.Y - y) <= sh.Size.Y / 2 then
				half = sh.Size.X / 2
				break
			end
		end
	end
	return face.n * (half + 0.03 * rec.scale) + face.u * (u * half * 0.8) + Vector3.new(0, y, 0)
end

local function addCracks(rec: Rec, stage: number)
	local body = rec.model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return
	end
	local ymin, ymax = math.huge, -math.huge
	for _, sh in rec.shells do
		if sh.Parent then
			local rel = body.CFrame:ToObjectSpace(sh.CFrame).Position
			ymin = math.min(ymin, rel.Y - sh.Size.Y / 2)
			ymax = math.max(ymax, rel.Y + sh.Size.Y / 2)
		end
	end
	if ymin > ymax then
		ymin, ymax = -body.Size.Y / 2, body.Size.Y / 2
	end
	local s = rec.scale
	for _, line in CRACK_LINES[stage] do
		local face = EGG_FACES[line[1]]
		local segsN = line[5]
		local prev: Vector3? = nil
		for j = 0, segsN do
			local h = line[3] + (line[4] - line[3]) * j / segsN
			local u = line[2] + (j % 2 == 0 and -0.12 or 0.12)
			local pt = crackPoint(rec, body, face, u, h, ymin, ymax)
			if prev then
				local n = face.n
				local dir = pt - prev
				dir -= n * dir:Dot(n)
				if dir.Magnitude > 1e-3 then
					local mid = (pt + prev) / 2
					local depth = math.max(pt:Dot(n), prev:Dot(n))
					mid += n * (depth - mid:Dot(n))
					local vy = dir.Unit
					local rel = CFrame.fromMatrix(mid, vy:Cross(n), vy, n)
					local p = localPart("RR_Crack", Vector3.new(0.1 * s, dir.Magnitude + 0.08 * s, 0.06 * s), CRACK_COLOR,
						Enum.Material.SmoothPlastic)
					table.insert(rec.cracks, { part = p, rel = rel })
				end
			end
			prev = pt
		end
	end
end

local function updateEgg(rec: Rec, now: number, dt: number, low: boolean, serverNow: number)
	local t = rec.t + rec.phase
	local s = rec.scale
	local amp, freq = 0.03, 2.2
	local hop = 0
	local remaining: number? = nil
	if rec.kind == "IncubatorEgg" then
		local hatchAt = rec.model:GetAttribute("HatchAt")
		if typeof(hatchAt) == "number" then
			local rem = hatchAt - serverNow
			remaining = rem
			local dur = rec.model:GetAttribute("Duration")
			local duration = (typeof(dur) == "number" and dur > 0) and dur or 60
			local p = clamp(1 - rem / duration, 0, 1)
			if rem <= 10 then
				local k = clamp(1 - rem / 10, 0, 1)
				amp, freq = 0.12 + 0.06 * k, 16
				local period = 1.6 - 0.8 * k
				local ph = (t % period) / period
				if ph < 0.3 then
					hop = sin(ph / 0.3 * math.pi) * 0.35 * s * (0.5 + 0.5 * k)
				end
			else
				amp, freq = 0.03 + 0.08 * p, 2.4 + 6 * p
				-- shiver bursts that get more frequent as the egg gets closer
				if sin(t * (0.8 + 1.5 * p)) > 0.9 then
					amp *= 1.8
					freq *= 2.5
				end
			end
			local stage = (p >= 0.9 or rem <= 10) and 3 or (p >= 0.66 and 2 or (p >= 0.33 and 1 or 0))
			while rec.crackStage < stage do
				rec.crackStage += 1
				addCracks(rec, rec.crackStage)
			end
		end
	end
	-- occasional jiggle so idle eggs feel alive
	local j = sin(t * 0.6)
	if j > 0.92 and amp < 0.1 then
		local k = (j - 0.92) / 0.08
		amp *= 1 + 1.5 * k
		freq *= 1 + 3 * k
	end
	-- accumulate phase so frequency changes never make the egg jump
	rec.cycle += dt * freq
	local c = rec.cycle
	local transform = CF(0, hop, 0) * ANG(sin(c) * amp, 0, cos(c * 0.83) * amp * 0.7)
	setT(rec.joints.Body, transform)

	if #rec.cracks > 0 or (remaining and remaining <= 10) then
		local bcf = bodyFrame(rec, transform)
		if bcf then
			local glowing = remaining ~= nil and remaining <= 10
			local k = glowing and clamp(1 - (remaining :: number) / 10, 0, 1) or 0
			for _, cr in rec.cracks do
				local p = cr.part
				p.CFrame = bcf * cr.rel
				if glowing then
					p.Material = Enum.Material.Neon
					p.Color = rec.rarityColor
					p.Transparency = 0.15 * (1 + sin(t * (6 + 10 * k)))
				end
			end
			if glowing and not low then
				if not rec.glowAnchor then
					local a = localPart("RR_HatchGlow", Vector3.new(0.2, 0.2, 0.2), rec.rarityColor, Enum.Material.SmoothPlastic)
					a.Transparency = 1
					local light = Instance.new("PointLight")
					light.Color = rec.rarityColor
					light.Shadows = false
					light.Parent = a
					local e = Instance.new("ParticleEmitter")
					e.Texture = SPARKLE_TEXTURE
					e.Color = ColorSequence.new(rec.rarityColor, Color3.new(1, 1, 1))
					e.LightEmission = 1
					e.LightInfluence = 0
					e.Lifetime = NumberRange.new(0.5, 0.9)
					e.Speed = NumberRange.new(2, 4)
					e.SpreadAngle = Vector2.new(180, 180)
					e.Size = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.35 * s),
						NumberSequenceKeypoint.new(1, 0),
					})
					e.RotSpeed = NumberRange.new(-120, 120)
					e.Parent = a
					rec.glowAnchor, rec.glowLight, rec.glowSparks = a, light, e
				end
				local a = rec.glowAnchor :: BasePart
				a.CFrame = bcf
				local pulse = 0.75 + 0.25 * sin(t * (5 + 8 * k))
				if rec.glowLight then
					rec.glowLight.Brightness = (0.5 + 3 * k) * pulse
					rec.glowLight.Range = (6 + 8 * k) * s
				end
				if rec.glowSparks then
					rec.glowSparks.Rate = 4 + 26 * k
				end
			elseif rec.glowAnchor then
				rec.glowAnchor:Destroy()
				rec.glowAnchor, rec.glowLight, rec.glowSparks = nil, nil, nil
			end
		end
	end
	updateRainbow(rec, now, low)
end

-- ===================================================================== guardians

local BUBBLES = {
	Alert = { "!", Color3.fromRGB(255, 220, 40) },
	Chase = { "!", Color3.fromRGB(255, 70, 60) },
	Attack = { "!", Color3.fromRGB(255, 70, 60) },
	Return = { "?", Color3.fromRGB(150, 210, 255) },
	Search = { "?", Color3.fromRGB(150, 210, 255) },
	Stunned = { "★", Color3.fromRGB(255, 235, 120) },
}

local function ensureBubble(rec: Rec)
	if rec.bubble and rec.bubble.Parent then
		return
	end
	local root = rec.root
	if not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RR_StateBubble"
	gui.Adornee = root
	gui.Size = UDim2.new(3, 0, 3, 0)
	local h = rec.model:GetAttribute("Height")
	gui.StudsOffsetWorldSpace = Vector3.new(0, (typeof(h) == "number" and h or 8) + 1.8, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = CULL_DISTANCE
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(30, 20, 30)
	label.Parent = gui
	gui.Parent = root
	rec.bubble, rec.bubbleLabel = gui, label
end

local ROAR_TIME = 1.3

local function updateGuardian(rec: Rec, now: number, dt: number, low: boolean)
	local J = rec.joints
	local root = rec.root :: BasePart
	local s = math.max(rec.scale, 0.1)
	local arch = rec.arch

	-- speed from Root movement (server PivotTo's the model every frame)
	local pos = root.Position
	if rec.lastPos and dt > 0 and now - rec.lastSeen < 0.5 then
		local d = pos - rec.lastPos
		local v = Vector3.new(d.X, 0, d.Z).Magnitude / dt
		rec.speed += (math.min(v, 200) - rec.speed) * math.min(1, dt * 8)
	else
		rec.speed = 0
	end
	rec.lastPos, rec.lastSeen = pos, now

	local speed = rec.speed
	local move = clamp(speed / (5 * s), 0, 1)
	rec.cycle += dt * speed / (0.8 * s)
	local c = rec.cycle
	local t = rec.t + rec.phase

	-- state changes
	local state = rec.model:GetAttribute("State")
	if state ~= rec.state then
		rec.state = state
		rec.stateAt = now
	end
	local since = now - rec.stateAt

	-- locomotion
	local stride = 0.55 * move
	for _, l in rec.legsQuad do
		setT(l.m, ANG(sin(c + l.phase) * stride, 0, 0))
	end
	setT(J.LegL, ANG(sin(c) * stride * 1.1, 0, 0))
	setT(J.LegR, ANG(-sin(c) * stride * 1.1, 0, 0))
	local armSwing = (arch == "Golem" and 0.7 or 0.35) * move
	local armL = ANG(-sin(c) * armSwing, 0, 0)
	local armR = ANG(sin(c) * armSwing, 0, 0)

	local bodyCF = CF(0, abs(sin(c)) * 0.12 * move * s + sin(t * 1.6) * 0.04 * s, 0) * ANG(0, 0, sin(c) * 0.04 * move)
	local headCF = ANG(sin(t * 0.9) * 0.04, sin(t * 0.45) * 0.25 * (1 - move), 0)
	local jawOpen = (sin(t * 0.7) > 0.85) and 0.15 or 0

	if state == "Chase" and move > 0.2 then
		-- heavy boss stomps: rise slowly, slam down on every footfall, sway side to side
		local step = abs(sin(c))
		local lift = step ^ 0.6 * 0.3 * move * s
		bodyCF = CF(0, lift, 0) * ANG(-0.06 * move, 0, sin(c) * 0.09 * move)
		headCF = headCF * ANG((1 - step) * 0.12 * move, 0, 0)
		jawOpen = 0.25 + 0.1 * sin(t * 6)
		if arch == "Golem" then
			-- knuckle-walk: big alternating arm swings
			armL = ANG(-sin(c) * 0.95 * move, 0, -0.1)
			armR = ANG(sin(c) * 0.95 * move, 0, 0.1)
		end
	end

	if state == "Attack" then
		-- lunge + jaw snap, re-triggered every 1.2 s while attacking
		local k = clamp((since % 1.2) / 0.45, 0, 1)
		local env = sin(k * math.pi)
		bodyCF = bodyCF * CF(0, 0, -1.0 * env * s) * ANG(-0.12 * env, 0, 0)
		headCF = headCF * ANG(-0.3 * env, 0, 0)
		jawOpen = k < 0.6 and (k / 0.6) * 0.7 or (1 - k) / 0.4 * 0.7
		if arch == "Golem" then
			armL = ANG(2.2 * env, 0, 0)
			armR = ANG(2.2 * env, 0, 0)
		else
			armL = ANG(1.0 * env, 0, 0)
			armR = ANG(1.0 * env, 0, 0)
		end
	elseif state == "Stunned" then
		bodyCF = bodyCF * ANG(sin(t * 6) * 0.12, 0, cos(t * 6) * 0.12)
		headCF = ANG(cos(t * 6) * 0.15, sin(t * 3) * 0.3, sin(t * 6) * 0.15)
	elseif state == "Alert" and since < ROAR_TIME then
		-- ROAR: rear up, head back with a shake, jaws wide, arms thrown out
		local k = since / ROAR_TIME
		local env = k < 0.2 and k / 0.2 or (k > 0.8 and (1 - k) / 0.2 or 1)
		env = env * env * (3 - 2 * env)
		local shake = sin(t * 38) * 0.05 * env
		bodyCF = bodyCF * CF(0, 0.3 * env * s, 0.2 * env * s) * ANG(0.22 * env, 0, shake * 0.5)
		headCF = ANG(0.35 * env, shake, shake)
		jawOpen = 0.8 * env
		armL = ANG(-0.4 * env, 0, -1.9 * env)
		armR = ANG(-0.4 * env, 0, 1.9 * env)
		for _, l in rec.legsQuad do
			if l.m.Name == "LegFL" or l.m.Name == "LegFR" then
				setT(l.m, ANG(-0.7 * env, 0, 0))
			end
		end
	end

	setT(J.Body, bodyCF)
	setT(J.Head, headCF)
	setT(J.Jaw, ANG(-jawOpen, 0, 0))
	setT(J.ArmL, armL)
	setT(J.ArmR, armR)
	setT(J.Tail, ANG(0, sin(c * 0.5 + t * 1.5) * (0.15 + 0.25 * move), 0))
	setT(J.TailTip, ANG(0, sin(c * 0.5 + t * 1.5 - 0.8) * (0.2 + 0.25 * move), 0))
	for i, m in rec.segs do
		setT(m, ANG(0, sin(c * 0.5 + t * 1.2 - i * 0.9) * (0.08 + 0.3 * move), sin(t * 1.3 - i * 0.6) * 0.04))
	end
	if not low then
		for i, m in rec.tendrils do
			setT(m, ANG(sin(t * 2 + i) * 0.2, 0, cos(t * 1.7 + i) * 0.2))
		end
		for _, m in rec.orbits do
			setT(m, ANG(0, t * 1.6, 0))
		end
		if J.WingL or J.WingR then
			local f = move > 0.3 and (0.3 + sin(t * 14) * 0.4) or sin(t * 2) * 0.06
			setT(J.WingL, ANG(0, 0, -f))
			setT(J.WingR, ANG(0, 0, f))
		end
		updateBlink(rec)
	end

	-- state bubble
	local b = state and BUBBLES[state]
	if b then
		ensureBubble(rec)
		local gui, label = rec.bubble, rec.bubbleLabel
		if gui and label then
			gui.Enabled = true
			label.Text = b[1]
			label.TextColor3 = b[2]
			local pop = 1 + math.max(0, 1 - since / 0.25) * 0.6
			label.Size = UDim2.fromScale(pop, pop)
			label.Rotation = state == "Stunned" and (t * 240) % 360 or sin(t * 8) * 6
		end
	elseif rec.bubble then
		rec.bubble.Enabled = false
	end
end

-- ===================================================================== loop

local accum = 0

local function hideLocalFx(rec: Rec)
	if rec.aura then
		for _, p in rec.aura do
			p.Transparency = 1
		end
	end
	for _, cr in rec.cracks do
		cr.part.Transparency = 1
	end
	if rec.glowAnchor then
		rec.glowAnchor:Destroy()
		rec.glowAnchor, rec.glowLight, rec.glowSparks = nil, nil, nil
	end
end

local function step(dt: number)
	local lowAttr = Players.LocalPlayer and Players.LocalPlayer:GetAttribute("LowGraphics")
	local low = lowAttr == true
	accum += dt
	if low and accum < LOW_RATE then
		return
	end
	local stepDt = math.min(accum, 0.25)
	accum = 0

	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()

	for _, rec in records do
		if rec.dirty then
			scan(rec)
		end
		local root = rec.root
		if not root or not root.Parent then
			rec.dirty = true
			continue
		end
		if (root.Position - camPos).Magnitude > CULL_DISTANCE then
			if rec.bubble then
				rec.bubble.Enabled = false
			end
			hideLocalFx(rec)
			continue
		end
		for _, cr in rec.cracks do
			if cr.part.Transparency >= 1 then
				cr.part.Transparency = 0
			end
		end
		rec.t += stepDt
		local kind = rec.kind
		if kind == "Pet" then
			updatePet(rec, now, low)
		elseif kind == "Guardian" then
			updateGuardian(rec, now, stepDt, low)
		else
			updateEgg(rec, now, stepDt, low, serverNow)
		end
	end
end

function AnimationController.Start()
	if started then
		return
	end
	started = true
	for tag, kind in TAGS do
		for _, inst in CollectionService:GetTagged(tag) do
			add(inst, kind)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			add(inst, kind)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
			if inst:IsA("Model") then
				remove(inst)
			end
		end)
	end
	RunService.PreSimulation:Connect(step)
end

return AnimationController

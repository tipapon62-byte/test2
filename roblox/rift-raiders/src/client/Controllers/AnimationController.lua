-- AnimationController: client-side procedural animation for ModelFactory models.
-- Drives Motor6D.Transform only (never moves the server-owned Root), so it is purely cosmetic and local.
--   RR_Pet          idle bob, squash/stretch breathing, blinks, wing flaps, tail wags, serpent waves, rainbow hue
--   RR_Egg          gentle wobble
--   RR_IncubatorEgg wobble that grows as HatchAt approaches (hard shakes in the last 10 s)
--   RR_Guardian     speed-scaled walk/run cycle, state bubble (! / ? / stars), attack lunge, stunned wobble

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnimationController = {}

local TAGS = {
	RR_Pet = "Pet",
	RR_Egg = "Egg",
	RR_IncubatorEgg = "IncubatorEgg",
	RR_Guardian = "Guardian",
}
local CULL_DISTANCE = 160
local LOW_RATE = 1 / 20 -- update rate when LowGraphics is on
local BLINK_PARTS = { EyeL = true, EyeR = true, PupilL = true, PupilR = true, ShineL = true, ShineR = true }

local CF, ANG = CFrame.new, CFrame.Angles
local sin, cos, abs, clamp = math.sin, math.cos, math.abs, math.clamp

type Rec = {
	model: Model,
	kind: string,
	root: BasePart?,
	joints: { [string]: Motor6D },
	segs: { Motor6D },
	tendrils: { Motor6D },
	orbits: { Motor6D },
	legsQuad: { { m: Motor6D, phase: number } },
	blink: { BasePart },
	main: { BasePart },
	mesh: SpecialMesh?,
	meshScale: Vector3,
	scale: number,
	arch: string,
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
	conns: { RBXScriptConnection },
}

local records: { [Model]: Rec } = {}
local origColors: { [BasePart]: Color3 } = setmetatable({}, { __mode = "k" }) :: any
local started = false
local rng = Random.new()

local function setT(m: Motor6D?, cf: CFrame)
	if m and m.Parent then
		m.Transform = cf
	end
end

local function scan(rec: Rec)
	local joints, segs, tendrils, orbits, blink, main = {}, {}, {}, {}, {}, {}
	local legsQuad = {}
	for _, d in rec.model:GetDescendants() do
		if d:IsA("Motor6D") then
			local n = d.Name
			if not joints[n] then
				joints[n] = d
			end
			local seg = string.match(n, "^Seg(%d+)$")
			if seg then
				segs[tonumber(seg) :: number] = d
			elseif string.match(n, "^Tendril%d+$") then
				table.insert(tendrils, d)
			elseif string.match(n, "^Orbit%d+$") then
				table.insert(orbits, d)
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
	rec.joints, rec.segs, rec.tendrils, rec.orbits = joints, ordered, tendrils, orbits
	rec.legsQuad, rec.blink, rec.main = legsQuad, blink, main
	local body = rec.model:FindFirstChild("Body")
	local mesh = body and body:FindFirstChildOfClass("SpecialMesh")
	if mesh ~= rec.mesh then
		rec.mesh = mesh
		rec.meshScale = mesh and mesh.Scale or Vector3.one
	end
	rec.scale = rec.model:GetScale()
	local arch = rec.model:GetAttribute("Archetype")
	rec.arch = typeof(arch) == "string" and arch or ""
	local root: Instance? = rec.model.PrimaryPart or rec.model:FindFirstChild("Root")
	rec.root = (root and root:IsA("BasePart")) and root or nil
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
		segs = {},
		tendrils = {},
		orbits = {},
		legsQuad = {},
		blink = {},
		main = {},
		mesh = nil,
		meshScale = Vector3.one,
		scale = 1,
		arch = "",
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

-- ===================================================================== pets

local function updatePet(rec: Rec, now: number, low: boolean)
	local J = rec.joints
	local t = rec.t + rec.phase
	local s = rec.scale
	local arch = rec.arch

	local bobAmp = (arch == "Floaty") and 0.28 or (arch == "Blob" and 0.02 or 0.06)
	local bob = sin(t * (arch == "Floaty" and 1.6 or 2.4)) * bobAmp * s
	if arch == "Bird" or arch == "Quadruped" then
		-- little hop every few seconds
		local h = sin(t * 0.9)
		if h > 0.93 then
			bob += (h - 0.93) / 0.07 * 0.35 * s
		end
	end
	setT(J.Body, CF(0, bob, 0) * ANG(0, 0, sin(t * 1.2) * 0.03))
	breathe(rec, sin(t * 2.4) * (arch == "Blob" and 0.06 or 0.025))
	setT(J.Head, ANG(sin(t * 1.1) * 0.05, sin(t * 0.55) * 0.14, sin(t * 0.8) * 0.04))

	if low then
		if rec.rainbowOn then
			restoreRainbow(rec)
		end
		return
	end

	-- wings: lazy flaps with periodic bursts
	if J.WingL or J.WingR then
		local burst = sin(t * 0.7) > 0.75
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
	for i, m in rec.segs do
		setT(m, ANG(sin(t * 1.4 - i * 0.6) * 0.05, sin(t * 1.8 - i * 0.8) * 0.12, 0))
	end
	for i, m in rec.tendrils do
		setT(m, ANG(sin(t * 2 + i) * 0.22, 0, cos(t * 1.7 + i * 1.3) * 0.22))
	end
	for _, m in rec.orbits do
		setT(m, ANG(0, t * 1.3, 0))
	end
	updateBlink(rec)
	updateRainbow(rec, now, low)
end

-- ===================================================================== eggs

local function updateEgg(rec: Rec, now: number, dt: number, low: boolean, serverNow: number)
	local t = rec.t + rec.phase
	local amp, freq = 0.03, 2.2
	if rec.kind == "IncubatorEgg" then
		local hatchAt = rec.model:GetAttribute("HatchAt")
		if typeof(hatchAt) == "number" then
			local remaining = hatchAt - serverNow
			if remaining <= 10 then
				amp, freq = 0.14, 18
			elseif remaining <= 60 then
				local k = (60 - remaining) / 50
				amp, freq = 0.05 + k * 0.07, 3 + k * 5
			else
				amp, freq = 0.045, 2.6
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
	setT(rec.joints.Body, ANG(sin(c) * amp, 0, cos(c * 0.83) * amp * 0.7))
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
	elseif state == "Alert" then
		-- startled rear-up on noticing a thief
		local k = clamp(since / 0.35, 0, 1)
		local env = sin(k * math.pi)
		bodyCF = bodyCF * CF(0, 0.4 * env * s, 0) * ANG(0.15 * env, 0, 0)
		headCF = ANG(0.2 * env, 0, 0)
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

	for model, rec in records do
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
			continue
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

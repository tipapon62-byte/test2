-- Kit: low-level helpers shared by every ModelFactory builder.
-- Models are built at the origin (Root at CFrame.new(), Y up, facing -Z) so build-space == world-space.
-- Every visual part is unanchored, massless, non-colliding and joined to its parent with a Motor6D
-- named after the part, so the client can animate through Motor6D.Transform.
--
-- Part "Role" attribute (used by ApplyMutation and the animator):
--   Main   primary body colour        Belly  secondary / belly colour
--   Accent features (horns, leaves)   Glow   neon details (flames, runes, cracks)
--   Eye    eye whites/pupils/shines   Face   mouth, blush, nose, brows, lids
--   Fx     rarity/tier effects        Gloss  specular highlight blobs
--   Glass  glass shells (domes, beakers) - never recoloured

local Kit = {}

local V3 = Vector3.new
local CF = CFrame.new

Kit.White = Color3.fromRGB(255, 255, 255)
Kit.Ink = Color3.fromRGB(30, 22, 40)
Kit.Blush = Color3.fromRGB(255, 135, 170)
Kit.Gold = Color3.fromRGB(255, 206, 64)
Kit.Ivory = Color3.fromRGB(255, 248, 230)
Kit.Steel = Color3.fromRGB(120, 126, 140)
Kit.DarkSteel = Color3.fromRGB(55, 58, 72)

Kit.FireTexture = "rbxasset://textures/particles/fire_main.dds"
Kit.SparkTexture = "rbxasset://textures/particles/sparkles_main.dds"

function Kit.Darker(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), f)
end

function Kit.Lighter(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), f)
end

function Kit.NewModel(name: string)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = V3(1, 1, 1)
	root.CFrame = CF()
	root.Anchored = true
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

-- Motor6D Part0 -> Part1 whose rest pose keeps both parts where they are now.
-- pivot (Vector3 | CFrame | nil) is the rotation centre used by Transform; a Vector3 pivot is
-- axis-aligned with the model so animation axes are consistent (X = pitch, Y = yaw, Z = roll).
function Kit.Joint(p0: BasePart, p1: BasePart, name: string, pivot: any?): Motor6D
	local piv: CFrame
	if typeof(pivot) == "Vector3" then
		piv = CF(pivot)
	elseif typeof(pivot) == "CFrame" then
		piv = pivot
	else
		piv = p1.CFrame
	end
	local m = Instance.new("Motor6D")
	m.Name = name
	m.C0 = p0.CFrame:ToObjectSpace(piv)
	m.C1 = p1.CFrame:ToObjectSpace(piv)
	m.Part0 = p0
	m.Part1 = p1
	m.Parent = p1
	return m
end

local function newPart(shape: string): BasePart
	if shape == "Wedge" then
		return Instance.new("WedgePart")
	elseif shape == "Corner" then
		return Instance.new("CornerWedgePart")
	end
	local p = Instance.new("Part")
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Ell" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	return p
end

-- shape: "Ell" (ellipsoid: Block + Sphere mesh) | "Ball" | "Block" | "Cyl" (axis = local X) | "Wedge" | "Corner"
function Kit.Add(model: Model, attach: BasePart, name: string, shape: string, size: Vector3, cf: CFrame,
	color: Color3, role: string?, mat: Enum.Material?, pivot: any?): BasePart
	local p = newPart(shape)
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = math.max(size.X, size.Y, size.Z) > 0.7
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if role then
		p:SetAttribute("Role", role)
	end
	p.Parent = model
	Kit.Joint(attach, p, name, pivot)
	return p
end

-- Vertical cylinder centred at cf (cf's Y axis = cylinder axis).
function Kit.VCyl(model, attach, name, height: number, diameter: number, cf: CFrame, color: Color3, role: string?,
	mat: Enum.Material?, pivot: any?): BasePart
	return Kit.Add(model, attach, name, "Cyl", V3(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2),
		color, role, mat, pivot)
end

-- Cylinder spanning two points.
function Kit.Pipe(model, attach, name, a: Vector3, b: Vector3, diameter: number, color: Color3, role: string?,
	mat: Enum.Material?): BasePart
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0)
	return Kit.Add(model, attach, name, "Cyl", V3(len, diameter, diameter), cf, color, role, mat)
end

-- Flat diamond (block rotated 45 deg around its facing axis); cf's -Z faces the viewer.
function Kit.Diamond(model, attach, name, size: number, depth: number, cf: CFrame, color: Color3, role: string?,
	mat: Enum.Material?, pivot: any?): BasePart
	return Kit.Add(model, attach, name, "Block", V3(size, size, depth), cf * CFrame.Angles(0, 0, math.pi / 4), color,
		role, mat, pivot)
end

-- Ring of n blocks around centre's Y axis.
function Kit.Ring(model, attach, name, centre: CFrame, radius: number, thick: number, height: number, n: number,
	color: Color3, role: string?, mat: Enum.Material?)
	local parts = {}
	local seg = 2 * math.pi * radius / n * 1.12
	for i = 1, n do
		local a = (i / n) * 2 * math.pi
		local cf = centre * CFrame.Angles(0, -a, 0) * CF(radius, 0, 0)
		local p = Kit.Add(model, attach, name, "Block", V3(thick, height, seg), cf, color, role, mat, centre)
		p.CastShadow = false
		table.insert(parts, p)
	end
	return parts
end

-- Point and outward normal on a part's surface along a direction given in the part's local space.
function Kit.Surface(part: BasePart, dir: Vector3): (Vector3, Vector3)
	local d = dir.Unit
	local h = part.Size / 2
	local lp: Vector3, ln: Vector3
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	local isPart = part:IsA("Part")
	local shape = isPart and (part :: Part).Shape or nil
	if shape == Enum.PartType.Ball then
		local r = math.min(h.X, h.Y, h.Z)
		lp, ln = d * r, d
	elseif shape == Enum.PartType.Cylinder then
		-- axis = local X
		local radial = math.sqrt((d.Y / h.Y) ^ 2 + (d.Z / h.Z) ^ 2)
		local tr = radial > 1e-6 and 1 / radial or math.huge
		local tx = math.abs(d.X) > 1e-6 and h.X / math.abs(d.X) or math.huge
		if tr <= tx then
			lp = d * tr
			ln = V3(0, lp.Y, lp.Z).Unit
		else
			lp = d * tx
			ln = V3(math.sign(d.X), 0, 0)
		end
	elseif mesh and mesh.MeshType == Enum.MeshType.Sphere then
		local t = 1 / math.sqrt((d.X / h.X) ^ 2 + (d.Y / h.Y) ^ 2 + (d.Z / h.Z) ^ 2)
		lp = d * t
		ln = V3(lp.X / (h.X * h.X), lp.Y / (h.Y * h.Y), lp.Z / (h.Z * h.Z)).Unit
	else
		local tx = math.abs(d.X) > 1e-6 and h.X / math.abs(d.X) or math.huge
		local ty = math.abs(d.Y) > 1e-6 and h.Y / math.abs(d.Y) or math.huge
		local tz = math.abs(d.Z) > 1e-6 and h.Z / math.abs(d.Z) or math.huge
		local t = math.min(tx, ty, tz)
		lp = d * t
		if t == tx then
			ln = V3(math.sign(d.X), 0, 0)
		elseif t == ty then
			ln = V3(0, math.sign(d.Y), 0)
		else
			ln = V3(0, 0, math.sign(d.Z))
		end
	end
	return part.CFrame:PointToWorldSpace(lp), part.CFrame:VectorToWorldSpace(ln)
end

-- Frame at pos whose UpVector = up and whose LookVector points as close to fwd (default -Z) as possible.
function Kit.UpFrame(pos: Vector3, up: Vector3, fwd: Vector3?): CFrame
	up = up.Unit
	local hint = fwd or V3(0, 0, -1)
	local f = hint - up * hint:Dot(up)
	if f.Magnitude < 1e-3 then
		f = V3(0, 1, 0) - up * up.Y
		if f.Magnitude < 1e-3 then
			f = V3(0, 0, -1)
		end
	end
	f = f.Unit
	local back = -f
	return CFrame.fromMatrix(pos, up:Cross(back), up, back)
end

-- Frame on a part's surface: Up = surface normal (or world up when worldUp), sunk by `sink` studs.
function Kit.OnSurface(part: BasePart, dir: Vector3, sink: number?, worldUp: boolean?): CFrame
	local p, n = Kit.Surface(part, dir)
	p -= n * (sink or 0)
	return Kit.UpFrame(p, worldUp and V3(0, 1, 0) or n)
end

-- Frame on a part's surface whose LookVector is the outward normal (for flat decals like spots/eyes).
function Kit.Facing(part: BasePart, dir: Vector3, sink: number?): CFrame
	local p, n = Kit.Surface(part, dir)
	p -= n * (sink or 0)
	local up = part.CFrame.UpVector
	if math.abs(n:Dot(up)) > 0.97 then
		up = -part.CFrame.LookVector
	end
	return CFrame.lookAt(p, p + n, up)
end

-- Part whose base (-Y face) sits on `base` (a frame with Up = growth direction).
function Kit.Stick(model, attach, name, shape: string, size: Vector3, base: CFrame, color: Color3, role: string?,
	mat: Enum.Material?, sink: number?): BasePart
	return Kit.Add(model, attach, name, shape, size, base * CF(0, size.Y / 2 - (sink or 0), 0), color, role, mat, base)
end

function Kit.Light(parent: Instance, color: Color3, range: number, brightness: number?): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = false
	l.Parent = parent
	return l
end

-- o: {Name, Color, Color2, Rate, Life, Speed, Spread, Size, Transp, Accel, Texture, Light, Locked, Rot}
function Kit.Emitter(parent: Instance, o): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = o.Name or "Fx"
	e.Color = ColorSequence.new(o.Color, o.Color2 or o.Color)
	e.LightEmission = o.Light or 1
	e.LightInfluence = 0
	e.Rate = o.Rate or 4
	local life = o.Life or 1
	e.Lifetime = NumberRange.new(life, life * 1.5)
	e.Speed = NumberRange.new(o.Speed or 1)
	local spread = o.Spread or 180
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, o.Size or 0.3),
		NumberSequenceKeypoint.new(0.4, (o.Size or 0.3) * 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(o.Transp or 0.2, 1)
	e.Acceleration = o.Accel or Vector3.zero
	e.Texture = o.Texture or Kit.SparkTexture
	e.LockedToPart = o.Locked or false
	if o.Rot then
		e.RotSpeed = NumberRange.new(-o.Rot, o.Rot)
		e.Rotation = NumberRange.new(0, 360)
	end
	e.Parent = parent
	return e
end

-- Highest point of the model (ignores Root and Fx-role parts). Uses each part's rotated bounding box.
function Kit.TopY(model: Model): number
	local top = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and d:GetAttribute("Role") ~= "Fx" then
			local cf, s = d.CFrame, d.Size
			local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
			local hy = (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2
			top = math.max(top, cf.Y + hy)
		end
	end
	return top
end

-- Big cartoon face on `head`.
-- o: {EyeScale, Spread, EyeY, Angry, Glow (Color3 = glowing guardian eyes), NoBlush, NoMouth,
--     MouthPart, MouthDir, Fangs}
function Kit.Face(model: Model, head: BasePart, o)
	o = o or {}
	local hs = head.Size
	local ed = (o.EyeScale or 0.36) * math.min(hs.X, hs.Y)
	local spread = o.Spread or 0.42
	local ey = o.EyeY or 0.15
	for _, s in { -1, 1 } do
		local side = s < 0 and "L" or "R"
		local c = Kit.Facing(head, V3(s * spread, ey, -1), ed * 0.24)
		local glow = o.Glow
		local eye = Kit.Add(model, head, "Eye" .. side, "Ball", V3(ed, ed, ed), c, glow or Kit.White, "Eye",
			glow and Enum.Material.Neon or nil)
		eye.Reflectance = glow and 0 or 0.12
		-- closed-eye line hidden inside the eye white; shows when the animator hides the eye for a blink
		local lid = Kit.Add(model, head, "Lid" .. side, "Block", V3(ed * 0.7, ed * 0.09, ed * 0.2),
			c * CF(0, -ed * 0.04, -ed * 0.22), Kit.Ink, "Face")
		lid.CastShadow = false
		local pupilSize = glow and V3(ed * 0.22, ed * 0.72, ed * 0.3) or V3(ed * 0.6, ed * 0.68, ed * 0.3)
		local pupil = Kit.Add(model, head, "Pupil" .. side, "Ell", pupilSize, c * CF(-s * ed * 0.04, -ed * 0.03, -ed * 0.36),
			Kit.Ink, "Eye")
		pupil.CastShadow = false
		pupil.Reflectance = 0.15
		local shine = Kit.Add(model, head, "Shine" .. side, "Ball", V3(ed * 0.2, ed * 0.2, ed * 0.2),
			c * CF(s * ed * 0.13, ed * 0.16, -ed * 0.46), Kit.White, "Eye", Enum.Material.Neon)
		shine.CastShadow = false
		if o.Angry then
			local brow = Kit.Add(model, head, "Brow" .. side, "Block", V3(ed * 0.85, ed * 0.2, ed * 0.35),
				c * CF(0, ed * 0.6, -ed * 0.28) * CFrame.Angles(0, 0, s * math.rad(24)), Kit.Ink, "Face")
			brow.CastShadow = false
		end
		if not o.NoBlush and not o.Angry then
			local b = Kit.Add(model, head, "Blush", "Ell", V3(ed * 0.5, ed * 0.24, ed * 0.14),
				Kit.Facing(head, V3(s * (spread + 0.18), ey - 0.32, -1), 0.02), Kit.Blush, "Face")
			b.Transparency = 0.1
			b.CastShadow = false
		end
	end
	if o.NoMouth then
		return
	end
	local mouthPart = o.MouthPart or head
	local mcf = Kit.Facing(mouthPart, o.MouthDir or V3(0, ey - 0.45, -1), 0.03)
	if o.Angry then
		local mouth = Kit.Add(model, mouthPart, "Mouth", "Ell", V3(ed * 1.1, ed * 0.36, ed * 0.2), mcf, Kit.Ink, "Face")
		mouth.CastShadow = false
		-- fangs: right-triangle wedges, tip down, mirrored
		for _, s in { -1, 1 } do
			local rot = CFrame.Angles(0, s < 0 and math.pi / 2 or -math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0)
			local fang = Kit.Add(model, mouthPart, "Fang", "Wedge", V3(ed * 0.12, ed * 0.42, ed * 0.24),
				mcf * CF(s * ed * 0.34, -ed * 0.12, -ed * 0.12) * rot, Kit.Ivory, "Face")
			fang.CastShadow = false
		end
	else
		local mouth = Kit.Add(model, mouthPart, "Mouth", "Ell", V3(ed * 0.36, ed * 0.17, ed * 0.14), mcf, Kit.Ink, "Face")
		mouth.CastShadow = false
	end
end

-- ===================================================================== brick look

local NO_BRICK_ROLES = { Eye = true, Gloss = true, Fx = true, Glow = true, Glass = true }
local KEEP_MATERIALS = {
	[Enum.Material.Neon] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.ForceField] = true,
}
-- parts whose front stays smooth so the face reads like a printed minifig face
local SMOOTH_FRONT = { Head = true, Snout = true, Muzzle = true }

local function eyeLike(name: string): boolean
	return string.match(name, "^Eye") ~= nil or string.match(name, "^Pupil") ~= nil
		or string.match(name, "^Shine") ~= nil or string.match(name, "^Iris") ~= nil
end

-- Toy-brick restyle: Plastic material, studs on top faces (and on every large face of body parts),
-- inlets underneath. Eyes, glows, glass and effects are left glossy/untouched. Safe on any model.
function Kit.Brickify(model: Instance)
	local Studs, Inlet, Smooth = Enum.SurfaceType.Studs, Enum.SurfaceType.Inlet, Enum.SurfaceType.Smooth
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") or d.Name == "Root" or d.Transparency >= 0.99 then
			continue
		end
		local role = d:GetAttribute("Role")
		if (role and NO_BRICK_ROLES[role]) or KEEP_MATERIALS[d.Material] or (role == nil and eyeLike(d.Name)) then
			continue
		end
		d.Material = Enum.Material.Plastic
		d.BottomSurface = Inlet
		local s = d.Size
		local isBlock = d:IsA("Part") and (d :: Part).Shape == Enum.PartType.Block
			and d:FindFirstChildOfClass("SpecialMesh") == nil
		if not isBlock or role == "Face" then
			d.TopSurface = Smooth
			continue
		end
		d.TopSurface = math.min(s.X, s.Z) >= 0.45 and Studs or Smooth
		local bodyPart = role == nil or role == "Main" or role == "Belly"
		if bodyPart and math.min(s.X, s.Y, s.Z) >= 0.5 then
			if math.min(s.X, s.Y) >= 0.8 then
				d.FrontSurface = SMOOTH_FRONT[d.Name] and Smooth or Studs
				d.BackSurface = Studs
			end
			if math.min(s.Y, s.Z) >= 0.8 then
				d.LeftSurface = Studs
				d.RightSurface = Studs
			end
		end
	end
end

-- Soft specular highlight that sells the glossy-toy look.
function Kit.Gloss(model: Model, part: BasePart, dir: Vector3?)
	local hs = part.Size
	local g = Kit.Add(model, part, "Gloss", "Ell", V3(hs.X * 0.28, hs.Y * 0.16, hs.Z * 0.08),
		Kit.Facing(part, dir or V3(-0.45, 0.7, -0.55), 0.02), Kit.White, "Gloss")
	g.Transparency = 0.45
	g.CastShadow = false
	return g
end

return Kit

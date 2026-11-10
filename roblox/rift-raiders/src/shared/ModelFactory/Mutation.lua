-- Mutation looks. Reversible: original colours/materials are stored as part attributes the first time
-- a mutation touches a part, so ApplyMutation can be called again with another id (or nil to clear).

local GameConfig = require(script.Parent.Parent.GameConfig)
local Kit = require(script.Parent.Style)

local Mutation = {}

local FX_NAME = "MutationFx"

local function remember(p: BasePart)
	if p:GetAttribute("OrigColor") == nil then
		p:SetAttribute("OrigColor", p.Color)
		p:SetAttribute("OrigMaterial", p.Material.Name)
		p:SetAttribute("OrigReflectance", p.Reflectance)
	end
end

local function restore(p: BasePart)
	local c = p:GetAttribute("OrigColor")
	if typeof(c) ~= "Color3" then
		return
	end
	p.Color = c
	local matName = p:GetAttribute("OrigMaterial")
	local ok, mat = pcall(function()
		return (Enum.Material :: any)[matName]
	end)
	if ok and mat then
		p.Material = mat
	end
	local refl = p:GetAttribute("OrigReflectance")
	p.Reflectance = typeof(refl) == "number" and refl or 0
end

local function set(p: BasePart, color: Color3, mat: Enum.Material?, refl: number?)
	remember(p)
	p.Color = color
	if mat then
		p.Material = mat
	end
	if refl then
		p.Reflectance = refl
	end
end

local function matOf(cfg): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[cfg.Material]
	end)
	return (ok and m) or Enum.Material.SmoothPlastic
end

local function findBody(model: Model): BasePart?
	local b = model:FindFirstChild("Body", true)
	if b and b:IsA("BasePart") then
		return b
	end
	return nil
end

-- Thin ForceField-material shell around a part (the "rift" overlay).
local function overlay(model: Model, part: BasePart, color: Color3)
	local shell = Kit.Add(model, part, FX_NAME, "Block", part.Size * 1.08, part.CFrame, color, "Fx",
		Enum.Material.ForceField)
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh:Clone().Parent = shell
	elseif part:IsA("Part") then
		(shell :: Part).Shape = (part :: Part).Shape
	end
	shell.CastShadow = false
end

local painters = {}

function painters.Silver(p, role, cfg)
	local base = cfg.Color
	if role == "Main" then
		set(p, base, Enum.Material.Metal, 0.1)
	elseif role == "Belly" then
		set(p, Kit.Lighter(base, 0.45), Enum.Material.Metal, 0.05)
	elseif role == "Accent" then
		set(p, p.Color:Lerp(Kit.Darker(base, 0.2), 0.65), Enum.Material.Metal)
	end
end

function painters.Gold(p, role, cfg)
	local base = cfg.Color
	if role == "Main" then
		set(p, base, Enum.Material.Foil, 0.15)
	elseif role == "Belly" then
		set(p, Kit.Lighter(base, 0.5), Enum.Material.Foil)
	elseif role == "Accent" then
		set(p, p.Color:Lerp(Kit.Darker(base, 0.25), 0.65), Enum.Material.Foil)
	end
end

function painters.Rainbow(p, role, _cfg)
	-- the client cycles hue on Main parts; brighten the base so it reads before the cycle kicks in
	if role == "Main" then
		set(p, Kit.Lighter(p.Color, 0.25), Enum.Material.SmoothPlastic, 0.05)
	elseif role == "Belly" then
		set(p, Kit.Lighter(p.Color, 0.4))
	end
end

function painters.Neon(p, role, cfg)
	if role == "Accent" or role == "Glow" then
		set(p, cfg.Color, Enum.Material.Neon)
	elseif role == "Main" then
		set(p, p.Color:Lerp(cfg.Color, 0.35))
	elseif role == "Belly" then
		set(p, p.Color:Lerp(Kit.Lighter(cfg.Color, 0.6), 0.3))
	end
end

function painters.Galaxy(p, role, cfg)
	if role == "Main" then
		set(p, Color3.fromRGB(45, 25, 110), Enum.Material.Glass, 0.15)
	elseif role == "Belly" then
		set(p, Kit.Lighter(cfg.Color, 0.25), Enum.Material.Glass, 0.1)
	elseif role == "Accent" then
		set(p, Color3.fromRGB(200, 180, 255), Enum.Material.Neon)
	end
end

function painters.Rift(p, role, cfg)
	if role == "Main" then
		set(p, p.Color:Lerp(cfg.Color, 0.3))
	elseif role == "Accent" or role == "Glow" then
		set(p, cfg.Color, Enum.Material.Neon)
	end
end

-- Generic fallback for mutations added to config later without a dedicated painter.
local function genericPainter(p, role, cfg)
	if role == "Main" then
		set(p, p.Color:Lerp(cfg.Color, 0.6), matOf(cfg))
	elseif role == "Accent" then
		set(p, p.Color:Lerp(cfg.Color, 0.4), matOf(cfg))
	end
end

function Mutation.Apply(model: Model, mutationId: string?)
	-- undo any previous mutation
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			restore(d)
		end
	end
	for _, d in model:GetDescendants() do
		if d.Name == FX_NAME and d.Parent then
			d:Destroy()
		end
	end
	model:SetAttribute("Rainbow", nil)

	local cfg = mutationId and GameConfig.Rarities.Mutations[mutationId] or nil
	model:SetAttribute("Mutation", cfg and mutationId or "")
	if not cfg then
		return
	end

	local painter = painters[mutationId :: string] or genericPainter
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			local role = d:GetAttribute("Role")
			if role and role ~= "Eye" and role ~= "Fx" and role ~= "Face" and role ~= "Gloss" then
				painter(d, role, cfg)
			end
		end
	end

	local body = findBody(model)
	if mutationId == "Rainbow" then
		model:SetAttribute("Rainbow", true)
		if body then
			local e = Kit.Emitter(body, { Name = FX_NAME, Color = Color3.fromRGB(255, 120, 200),
				Color2 = Color3.fromRGB(120, 220, 255), Rate = 3, Life = 1.2, Speed = 0.6, Size = 0.25 })
			e.Name = FX_NAME
		end
	elseif mutationId == "Galaxy" then
		if body then
			Kit.Emitter(body, { Name = FX_NAME, Color = Kit.White, Color2 = Color3.fromRGB(120, 170, 255), Rate = 7,
				Life = 1.4, Speed = 0.4, Size = 0.22, Rot = 90 })
			local l = Kit.Light(body, Color3.fromRGB(140, 110, 255), 9, 1)
			l.Name = FX_NAME
		end
	elseif mutationId == "Neon" then
		if body then
			local l = Kit.Light(body, cfg.Color, 9, 1.5)
			l.Name = FX_NAME
		end
	elseif mutationId == "Rift" then
		if body then
			overlay(model, body, cfg.Color)
			local head = model:FindFirstChild("Head", true)
			if head and head:IsA("BasePart") then
				overlay(model, head, cfg.Color)
			end
			local l = Kit.Light(body, cfg.Color, 10, 1.6)
			l.Name = FX_NAME
			Kit.Emitter(body, { Name = FX_NAME, Color = cfg.Color, Rate = 5, Life = 0.9, Speed = 1.2, Size = 0.2,
				Accel = Vector3.new(0, 2, 0) })
		end
	elseif mutationId == "Gold" or mutationId == "Silver" then
		if body then
			Kit.Emitter(body, { Name = FX_NAME, Color = Kit.Lighter(cfg.Color, 0.4), Rate = 1.5, Life = 0.8, Speed = 0.3,
				Size = 0.3 })
		end
	end
end

return Mutation

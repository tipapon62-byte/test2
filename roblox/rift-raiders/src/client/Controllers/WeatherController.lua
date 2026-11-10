-- WeatherController: tweens Lighting toward the current biome's theme and runs local weather
-- particles around the camera. Reads the replicated "BiomeIndex" attribute (0/nil = hub).

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))

local WeatherController = {}

local TWEEN = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local BOX = Vector3.new(110, 40, 110)

-- Per-biome mood that the palette alone does not carry.
local MOOD = {
	[1] = { Clock = 14.5, Density = 0.28, Haze = 0.6, FogEnd = 900, Brightness = 2.2 },
	[2] = { Clock = 15.5, Density = 0.33, Haze = 1.2, FogEnd = 700, Brightness = 2 },
	[3] = { Clock = 13, Density = 0.42, Haze = 1.6, FogEnd = 500, Brightness = 1.8 },
	[4] = { Clock = 13.5, Density = 0.38, Haze = 2.4, FogEnd = 550, Brightness = 2.8 },
	[5] = { Clock = 16.5, Density = 0.4, Haze = 1.8, FogEnd = 500, Brightness = 1.7 },
	[6] = { Clock = 18.3, Density = 0.42, Haze = 2.2, FogEnd = 450, Brightness = 1.6 },
	[7] = { Clock = 10, Density = 0.36, Haze = 1.5, FogEnd = 550, Brightness = 2.4 },
	[8] = { Clock = 0.5, Density = 0.3, Haze = 0.4, FogEnd = 800, Brightness = 1.4 },
}

-- Extra Atmosphere density (or FogEnd multiplier) for weather that should cut visibility.
local VISIBILITY = { Sandstorm = { 0.22, 0.55 }, Snow = { 0.14, 0.7 }, Ash = { 0.18, 0.6 } }

local function seq(a: number, b: number?): NumberSequence
	return NumberSequence.new(a, b or a)
end

-- Emitter presets per weather; each entry is a list of emitters. Offset = box centre relative to camera.
local WEATHER = {
	Leaves = {
		Offset = Vector3.new(0, 18, 0),
		Emitters = {
			{
				Color = ColorSequence.new(Color3.fromRGB(150, 210, 80), Color3.fromRGB(230, 170, 60)), Size = seq(0.45, 0.35),
				Lifetime = NumberRange.new(6, 9), Rate = 22, Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(1.5, -1.5, 0.8),
				EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(40, 40), RotSpeed = NumberRange.new(-120, 120),
				Rotation = NumberRange.new(0, 360), Squash = seq(-0.6), Transparency = NumberSequence.new(0, 0.2),
			},
		},
	},
	Bubbles = {
		Offset = Vector3.new(0, -12, 0),
		Emitters = {
			{
				Color = ColorSequence.new(Color3.fromRGB(210, 245, 255)), Size = NumberSequence.new(0.15, 0.45),
				Transparency = NumberSequence.new(0.35, 0.8), Lifetime = NumberRange.new(5, 8), Rate = 35, Speed = NumberRange.new(2, 5),
				Acceleration = Vector3.new(0, 1.5, 0), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(15, 15), LightEmission = 0.4,
			},
		},
	},
	Sandstorm = {
		Offset = Vector3.new(-20, 4, 0),
		Emitters = {
			{
				Color = ColorSequence.new(Color3.fromRGB(235, 195, 135)), Size = NumberSequence.new(2, 4),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(2, 3), Rate = 70, Speed = NumberRange.new(35, 50), EmissionDirection = Enum.NormalId.Right,
				SpreadAngle = Vector2.new(8, 8), Acceleration = Vector3.new(0, -2, 6),
			},
			{
				Color = ColorSequence.new(Color3.fromRGB(255, 225, 170)), Size = seq(0.12),
				Lifetime = NumberRange.new(1.5, 2.5), Rate = 160, Speed = NumberRange.new(45, 60), EmissionDirection = Enum.NormalId.Right,
				SpreadAngle = Vector2.new(5, 5), Squash = seq(-1.5), Orientation = Enum.ParticleOrientation.VelocityParallel,
			},
		},
	},
	Rain = {
		Offset = Vector3.new(0, 30, 0),
		Emitters = {
			{
				Color = ColorSequence.new(Color3.fromRGB(180, 210, 230)), Size = seq(0.12), Transparency = seq(0.35),
				Lifetime = NumberRange.new(0.8, 1), Rate = 320, Speed = NumberRange.new(75, 90), EmissionDirection = Enum.NormalId.Bottom,
				Acceleration = Vector3.new(4, 0, 2), Squash = seq(3), Orientation = Enum.ParticleOrientation.VelocityParallel, LightEmission = 0.15,
			},
		},
	},
	Ash = {
		Offset = Vector3.new(0, 18, 0),
		Emitters = {
			{
				Color = ColorSequence.new(Color3.fromRGB(95, 90, 90)), Size = NumberSequence.new(0.25, 0.4), Transparency = NumberSequence.new(0.1, 0.5),
				Lifetime = NumberRange.new(7, 10), Rate = 60, Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(1.2, -1.2, 0.6),
				EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(30, 30), RotSpeed = NumberRange.new(-60, 60),
			},
			{
				Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 70, 20)), Size = NumberSequence.new(0.18, 0),
				Lifetime = NumberRange.new(3, 5), Rate = 14, Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(0, 2.5, 0),
				EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(40, 40), LightEmission = 1,
			},
		},
	},
	Snow = {
		Offset = Vector3.new(0, 20, 0),
		Emitters = {
			{
				Color = ColorSequence.new(Color3.new(1, 1, 1)), Size = NumberSequence.new(0.3, 0.5), Transparency = NumberSequence.new(0, 0.3),
				Lifetime = NumberRange.new(6, 9), Rate = 130, Speed = NumberRange.new(4, 7), Acceleration = Vector3.new(2, -1, 0.5),
				EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(25, 25), RotSpeed = NumberRange.new(-90, 90), LightEmission = 0.2,
			},
		},
	},
	Stars = {
		Offset = Vector3.new(0, 6, 0),
		Emitters = {
			{
				Color = ColorSequence.new(Color3.fromRGB(230, 220, 255), Color3.fromRGB(170, 140, 255)),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) }),
				Lifetime = NumberRange.new(3, 5), Rate = 45, Speed = NumberRange.new(0.2, 0.6), SpreadAngle = Vector2.new(180, 180), LightEmission = 1,
			},
		},
	},
}

local player = Players.LocalPlayer
local atmosphere: Atmosphere? = nil
local correction: ColorCorrectionEffect? = nil
local original: any = nil
local emitterPart: BasePart? = nil
local activeWeather: string? = nil
local activeOffset = Vector3.zero
local tweens: { Tween } = {}

local function capture()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	original = {
		Lighting = {
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			ClockTime = Lighting.ClockTime,
			FogColor = Lighting.FogColor,
			FogEnd = Lighting.FogEnd,
			Brightness = Lighting.Brightness,
		},
	}
	local atm = atmosphere
	if atm then
		original.Atmosphere = { Color = atm.Color, Decay = atm.Decay, Density = atm.Density, Haze = atm.Haze }
	end
	local cc = correction
	if cc then
		original.Correction = { TintColor = cc.TintColor, Saturation = cc.Saturation }
	end
end

local function play(inst: Instance, goals: { [string]: any })
	local t = TweenService:Create(inst, TWEEN, goals)
	table.insert(tweens, t)
	t:Play()
end

local function applyLighting(index: number)
	for _, t in ipairs(tweens) do
		t:Cancel()
	end
	table.clear(tweens)
	local biome = index > 0 and GameConfig.GetBiomeByIndex(index) or nil
	if not biome then
		play(Lighting, original.Lighting)
		if atmosphere and original.Atmosphere then
			play(atmosphere, original.Atmosphere)
		end
		if correction and original.Correction then
			play(correction, original.Correction)
		end
		return
	end

	local theme = biome.Theme
	local mood = MOOD[index] or MOOD[1]
	local vis = VISIBILITY[biome.Weather or ""]
	local grey = Color3.fromRGB(128, 128, 128)
	-- short tween path for ClockTime when crossing midnight
	local clock = mood.Clock
	if math.abs(clock - Lighting.ClockTime) > 12 then
		clock += clock < Lighting.ClockTime and 24 or -24
	end
	play(Lighting, {
		Ambient = theme.Ground:Lerp(grey, 0.55),
		OutdoorAmbient = theme.Fog:Lerp(grey, 0.45),
		ClockTime = math.clamp(clock, 0, 23.99),
		FogColor = theme.Fog,
		FogEnd = mood.FogEnd * (vis and vis[2] or 1),
		Brightness = mood.Brightness,
	})
	if atmosphere then
		play(atmosphere, {
			Color = theme.Fog,
			Decay = theme.Sky,
			Density = math.clamp(mood.Density + (vis and vis[1] or 0), 0, 1),
			Haze = mood.Haze,
		})
	end
	if correction then
		play(correction, { TintColor = Color3.new(1, 1, 1):Lerp(theme.Sky, 0.12), Saturation = 0.1 })
	end
end

local function clearEmitters()
	if emitterPart then
		emitterPart:Destroy()
		emitterPart = nil
	end
	activeWeather = nil
end

local function applyWeather(index: number)
	local biome = index > 0 and GameConfig.GetBiomeByIndex(index) or nil
	local kind = biome and biome.Weather or nil
	if player:GetAttribute("LowGraphics") == true then
		kind = nil
	end
	if kind == activeWeather and (kind == nil or emitterPart ~= nil) then
		return
	end
	clearEmitters()
	local preset = kind and WEATHER[kind]
	if not preset then
		return
	end
	local p = Instance.new("Part")
	p.Name = "RR_Weather"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = BOX
	for _, props in ipairs(preset.Emitters) do
		local e = Instance.new("ParticleEmitter")
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.LockedToPart = false
		for k, v in pairs(props) do
			(e :: any)[k] = v
		end
		e.Parent = p
	end
	p.Parent = workspace.CurrentCamera or workspace
	emitterPart = p
	activeWeather = kind
	activeOffset = preset.Offset
end

local currentIndex = -1

local function refresh()
	local idx = player:GetAttribute("BiomeIndex")
	local index = typeof(idx) == "number" and idx or 0
	if index ~= currentIndex then
		currentIndex = index
		applyLighting(index)
	end
	applyWeather(index)
end

function WeatherController.Start()
	capture()
	refresh()
	player:GetAttributeChangedSignal("BiomeIndex"):Connect(refresh)
	player:GetAttributeChangedSignal("LowGraphics"):Connect(refresh)

	RunService.RenderStepped:Connect(function()
		local p = emitterPart
		local cam = workspace.CurrentCamera
		if not p or not cam then
			return
		end
		if p.Parent ~= cam then
			p.Parent = cam
		end
		-- lead the box slightly ahead of the view so particles fill the screen
		local look = cam.CFrame.LookVector
		local ahead = Vector3.new(look.X, 0, look.Z) * 20
		p.CFrame = CFrame.new(cam.CFrame.Position + activeOffset + ahead)
	end)
end

return WeatherController

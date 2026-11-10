-- JuiceController: screen-space game feel.
--   * red vignette that pulses while a guardian chases you with an egg
--   * speed lines (thin white streaks) when running very fast or on a speed lane
--   * big rarity-coloured "LEGENDARY EGG! RUN!" callout when you grab an Epic+ egg
--   * celebration banner + confetti when an upgrade level goes up
-- API: JuiceController.BigCallout(text, color, duration?)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Client = script.Parent.Parent
local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
local ClientState = require(Client:WaitForChild("Data"):WaitForChild("ClientState"))
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local New = Components.New
local Text = Components.Text
local Economy = GameConfig.Economy

local player = Players.LocalPlayer

local JuiceController = {}

local FAST_SPEED = 40 -- studs/s of horizontal speed that counts as "very fast"
local LINE_POOL = 26

local gui: ScreenGui? = nil
local function screen(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	gui = New("ScreenGui", {
		Name = "RR_Juice",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 4, -- under the HUD
		Parent = player:WaitForChild("PlayerGui"),
	})
	return gui :: ScreenGui
end

-- ===== Chase vignette =====
local function buildVignette(parent: Instance): { Frame }
	local edges = {}
	-- {AnchorPoint, Position, Size, gradient rotation (opaque side = edge)}
	local defs = {
		{ Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90 }, -- top
		{ Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.22), -90 }, -- bottom
		{ Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.16, 1), 0 }, -- left
		{ Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.16, 1), 180 }, -- right
	}
	for _, d in ipairs(defs) do
		local f = New("Frame", {
			Name = "Vignette",
			AnchorPoint = d[1],
			Position = d[2],
			Size = d[3],
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(255, 30, 40),
			BackgroundTransparency = 1,
			Active = false,
			Parent = parent,
		})
		New("UIGradient", {
			Rotation = d[4],
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = f,
		})
		table.insert(edges, f)
	end
	return edges
end

-- ===== Speed lines =====
local function buildLines(parent: Instance): { any }
	local pool = {}
	for _ = 1, LINE_POOL do
		local f = New("Frame", {
			Name = "SpeedLine",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Active = false,
			Parent = parent,
		})
		table.insert(pool, { Frame = f, Life = 0, Age = 0, Angle = 0, R0 = 0 })
	end
	return pool
end

-- ===== Big centre callout =====
local calloutToken = 0
function JuiceController.BigCallout(text: string, color: Color3, duration: number?)
	calloutToken += 1
	local token = calloutToken
	local root = Components.Layer("Toasts")
	local old = root:FindFirstChild("BigCallout")
	if old then
		old:Destroy()
	end
	local label = Text({
		Name = "BigCallout",
		Text = text,
		TextSize = 64,
		Font = Theme.FontHeavy,
		Outline = 6,
		TextColor3 = color,
		TextWrapped = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(900, 90),
		ZIndex = 35,
		Parent = root,
	})
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.Darken(color, 0.75)
	end
	Components.Pop(label, 0.3, Theme.Tween.Bounce)
	local pulse = New("UIScale", { Parent = label })
	local tw = TweenService:Create(pulse, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 })
	tw:Play()
	task.delay(duration or 2.4, function()
		if token ~= calloutToken or not label.Parent then
			return
		end
		tw:Cancel()
		TweenService:Create(label, Theme.Tween.Smooth, { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, Theme.Tween.Smooth, { Transparency = 1 }):Play()
		end
		task.wait(0.35)
		label:Destroy()
	end)
end

local UPGRADE_NAMES = {
	BaseLevel = { "🏠 ENCLOSURE", Economy.BaseLevels, Color3.fromRGB(80, 200, 120) },
	TreadmillLevel = { "🏃 TREADMILL", Economy.TreadmillLevels, Color3.fromRGB(80, 170, 255) },
	IncubatorLevel = { "🥚 INCUBATOR", Economy.IncubatorLevels, Color3.fromRGB(255, 160, 60) },
}

local function upgradeSub(key: string, level: number): string
	local info = UPGRADE_NAMES[key]
	local l = info and info[2][level]
	if not l then
		return "Upgrade complete!"
	end
	if key == "BaseLevel" then
		return ("%d character slots · +%d%% income"):format(l.Slots or 0, math.floor((l.IncomeBonus or 0) * 100 + 0.5))
	elseif key == "TreadmillLevel" then
		return ("%s · +%s Speed/s"):format(l.Name or "Treadmill", GameConfig.FormatNumber(l.Gain or 0))
	end
	return ("%d hatch pad%s · %d%% faster hatching"):format(l.Pads or 1, if (l.Pads or 1) == 1 then "" else "s", math.floor((l.HatchSpeed or 0) * 100 + 0.5))
end

function JuiceController.Start()
	local sg = screen()
	local edges = buildVignette(sg)
	local lines = buildLines(sg)

	-- rare egg grabbed
	local lastRarity = ClientState.CarryRarity()
	local function onCarry()
		local r = ClientState.CarryRarity()
		if r ~= "" and r ~= lastRarity and ClientState.Carrying() then
			local idx = Theme.RarityIndex(r)
			if idx >= 4 then
				local color = Theme.Rarity(r)
				JuiceController.BigCallout(("%s EGG! RUN!"):format(string.upper(r)), color, if idx >= 5 then 3 else 2.4)
				Components.PlaySound("Rare")
				if idx >= 5 then
					Components.Confetti({ color, Theme.Lighten(color, 0.4), Color3.new(1, 1, 1) }, 50, UDim2.fromScale(0.5, 0.3))
				end
			end
		end
		lastRarity = r
	end
	player:GetAttributeChangedSignal("CarryingRarity"):Connect(onCarry)
	player:GetAttributeChangedSignal("CarryingEgg"):Connect(onCarry)

	-- upgrade celebration
	local levels: { [string]: number } = {}
	for key in pairs(UPGRADE_NAMES) do
		levels[key] = tonumber(ClientData.Get()[key]) or 1
	end
	ClientData.Observe({ "BaseLevel", "TreadmillLevel", "IncubatorLevel" }, function(p)
		for key, info in pairs(UPGRADE_NAMES) do
			local v = tonumber(p[key]) or levels[key]
			if v > levels[key] then
				ClientState.Call("NotificationController", "Banner", ("⬆️ %s LEVEL %d!"):format(info[1], v), upgradeSub(key, v), info[3], 3.5)
				Components.Confetti({ info[3], Theme.Colors.Gold, Color3.new(1, 1, 1) }, 60, UDim2.fromScale(0.5, 0.25))
			end
			levels[key] = v
		end
	end)

	-- per-frame: vignette + speed lines
	local chased = false
	local chaseAcc = 1
	local spawnAcc = 0
	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		chaseAcc += dt
		if chaseAcc >= 0.2 then
			chaseAcc = 0
			chased = ClientState.IsChased()
		end
		-- vignette
		local target = 1
		if chased then
			target = 0.35 + 0.3 * (0.5 + 0.5 * math.sin(clock * 9))
		end
		for _, e in ipairs(edges) do
			local cur = e.BackgroundTransparency
			local nextT = cur + (target - cur) * math.min(1, dt * 10)
			if math.abs(nextT - cur) > 0.001 then
				e.BackgroundTransparency = nextT
			end
		end

		-- speed lines
		local intensity = 0
		local root = ClientState.Root()
		if root and not Components.LowGraphics() then
			local v = root.AssemblyLinearVelocity
			local horiz = Vector3.new(v.X, 0, v.Z).Magnitude
			if horiz > FAST_SPEED then
				intensity = math.clamp((horiz - FAST_SPEED) / 40, 0.25, 1)
			end
			if player:GetAttribute("SpeedLane") == true and horiz > 10 then
				intensity = math.max(intensity, 0.8)
			end
		end
		if intensity > 0 then
			spawnAcc += dt * (12 + 38 * intensity)
		else
			spawnAcc = 0
		end
		while spawnAcc >= 1 do
			spawnAcc -= 1
			for _, l in ipairs(lines) do
				if l.Life <= 0 then
					l.Life = 0.22 + math.random() * 0.14
					l.Age = 0
					l.Angle = math.random() * math.pi * 2
					l.R0 = 0.34 + math.random() * 0.1
					local f = l.Frame
					f.Size = UDim2.fromOffset(math.random(70, 170), math.random(2, 3))
					f.Rotation = math.deg(l.Angle)
					f.Visible = true
					break
				end
			end
		end
		for _, l in ipairs(lines) do
			if l.Life > 0 then
				l.Age += dt
				local t = l.Age / l.Life
				if t >= 1 then
					l.Life = 0
					l.Frame.Visible = false
				else
					local r = l.R0 + t * 0.25
					l.Frame.Position = UDim2.fromScale(0.5 + math.cos(l.Angle) * r, 0.5 + math.sin(l.Angle) * r)
					l.Frame.BackgroundTransparency = 0.35 + 0.65 * t
				end
			end
		end
	end)
end

return JuiceController

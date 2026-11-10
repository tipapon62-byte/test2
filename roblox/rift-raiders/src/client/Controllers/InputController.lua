-- InputController: combat/item actions for every input device.
--   Keyboard: F tag · G drop egg · T bear trap · Q decoy egg
--   Gamepad : RB tag · LB drop egg · Y bear trap · D-pad up decoy egg   (B closes windows)
--   Touch   : large round buttons above the jump button
-- Interact (pick up / deliver) is handled by ProximityPrompts (E / ButtonX / tap).
-- The client only asks; the server validates range, cooldowns, ownership and protections.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent.Parent
local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local New = Components.New
local Text = Components.Text

local player = Players.LocalPlayer

local InputController = {}

local ACTIONS = {
	{ Id = "Tag", Icon = Theme.Icons.Bat, Label = "Tag", Key = Enum.KeyCode.F, Pad = Enum.KeyCode.ButtonR1, PadText = "RB", Color = Color3.fromRGB(255, 90, 90) },
	{ Id = "Drop", Icon = Theme.Icons.Egg, Label = "Drop", Key = Enum.KeyCode.G, Pad = Enum.KeyCode.ButtonL1, PadText = "LB", Color = Color3.fromRGB(255, 180, 60) },
	{ Id = "Trap", Icon = Theme.Icons.Trap, Label = "Trap", Key = Enum.KeyCode.T, Pad = Enum.KeyCode.ButtonY, PadText = "Y", Color = Color3.fromRGB(150, 120, 90) },
	{ Id = "Decoy", Icon = Theme.Icons.Decoy, Label = "Decoy", Key = Enum.KeyCode.Q, Pad = Enum.KeyCode.DPadUp, PadText = "↑", Color = Color3.fromRGB(250, 230, 160) },
}

local localTagReadyAt = 0 -- optimistic cooldown until the server's TagReadyAt attribute arrives
local lastTagPress = 0

local function itemCount(id: string): number
	local items = ClientData.Get().Items or {}
	return items[id] or 0
end

local function carrying(): boolean
	local egg = player:GetAttribute("CarryingEgg")
	return type(egg) == "string" and egg ~= ""
end

local function tagReadyAt(): number
	return math.max(player:GetAttribute("TagReadyAt") or 0, localTagReadyAt)
end

-- 0 = ready, 1 = just swung.
function InputController.TagCooldownFraction(): number
	local left = tagReadyAt() - Components.Now()
	if left <= 0 then
		return 0
	end
	return math.clamp(left / GameConfig.Settings.TagCooldown, 0, 1)
end

local function effects(): any
	local m = script.Parent:FindFirstChild("EffectsController")
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok then
			return res
		end
	end
	return nil
end

function InputController.Tag()
	if os.clock() - lastTagPress < 0.25 or InputController.TagCooldownFraction() > 0 then
		return
	end
	if player:GetAttribute("Ragdolled") or player:GetAttribute("Trapped") then
		return
	end
	lastTagPress = os.clock()
	localTagReadyAt = Components.Now() + GameConfig.Settings.TagCooldown
	Net.Event("Tag"):FireServer()
	local fx = effects()
	if fx and fx.PlaySwing then
		fx.PlaySwing()
	end
end

function InputController.Drop()
	if carrying() then
		Net.Event("DropEgg"):FireServer()
	end
end

function InputController.Trap()
	if itemCount("BearTrap") <= 0 then
		Components.Toast("No bear traps — buy some in the Shop 🛒", "warn", 2.5)
		return
	end
	Net.Event("UseItem"):FireServer("BearTrap")
end

function InputController.Decoy()
	if itemCount("DecoyEgg") <= 0 and not player:GetAttribute("HoldingDecoy") then
		Components.Toast("No decoy eggs — buy some in the Shop 🛒", "warn", 2.5)
		return
	end
	Net.Event("UseItem"):FireServer("DecoyEgg")
end

local RUN = {
	Tag = InputController.Tag,
	Drop = InputController.Drop,
	Trap = InputController.Trap,
	Decoy = InputController.Decoy,
}

-- Whether an action's button/hint should be shown right now.
local function actionVisible(id: string): boolean
	if id == "Drop" then
		return carrying()
	elseif id == "Trap" then
		return itemCount("BearTrap") > 0
	elseif id == "Decoy" then
		return itemCount("DecoyEgg") > 0 or player:GetAttribute("HoldingDecoy") == true
	end
	return true
end

local function badgeText(id: string): string?
	if id == "Trap" then
		return "x" .. itemCount("BearTrap")
	elseif id == "Decoy" then
		return if player:GetAttribute("HoldingDecoy") then "ON" else "x" .. itemCount("DecoyEgg")
	end
	return nil
end

-- ===== Touch buttons =====
local function buildTouchButtons(): (any, { [string]: any })
	local gui = New("ScreenGui", {
		Name = "RR_TouchActions",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 6,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local buttons = {}
	for _, a in ipairs(ACTIONS) do
		local btn = New("TextButton", {
			Name = a.Id,
			Text = "",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = a.Color,
			Parent = gui,
		})
		Components.CornerScale(btn, 0.5)
		Components.Gradient(btn, Theme.Lighten(a.Color, 0.2), Theme.Darken(a.Color, 0.3))
		Components.Stroke(btn, Theme.Colors.Stroke, 3)
		local icon = Text({ Name = "Icon", Text = a.Icon, TextScaled = true, Outline = false, Size = UDim2.fromScale(0.55, 0.5), Position = UDim2.fromScale(0.225, 0.1), Parent = btn })
		local label = Text({ Name = "Label", Text = a.Label, TextScaled = true, Size = UDim2.fromScale(0.8, 0.24), Position = UDim2.fromScale(0.1, 0.62), Parent = btn })
		local cd = New("Frame", {
			Name = "Cooldown",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			ZIndex = 3,
			Parent = btn,
		})
		Components.CornerScale(cd, 0.5)
		local badge = New("Frame", {
			Name = "Badge",
			BackgroundColor3 = Theme.Colors.Accent2,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 4, 0, -4),
			Size = UDim2.fromScale(0.5, 0.3),
			ZIndex = 4,
			Visible = false,
			Parent = btn,
		})
		Components.CornerScale(badge, 0.5)
		Components.Stroke(badge, Theme.Colors.Stroke, 2)
		local badgeLabel = Text({ Text = "", TextScaled = true, ZIndex = 5, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Parent = badge })
		local scale = New("UIScale", { Parent = btn })
		btn.Activated:Connect(function()
			scale.Scale = 0.85
			Components.Tween(scale, Theme.Tween.Pop, { Scale = 1 })
			RUN[a.Id]()
		end)
		buttons[a.Id] = { Button = btn, Cooldown = cd, Badge = badge, BadgeLabel = badgeLabel, Icon = icon, Label = label }
	end

	-- Laid out around the default jump button (small screens: 70 px at 1,-95/1,-90; else 120 px at 1,-170/1,-210).
	local function layout()
		local size = gui.AbsoluteSize
		if size.X < 2 then
			return
		end
		local small = math.min(size.X, size.Y) < 500
		local jumpSize = if small then 70 else 120
		local jump = if small then Vector2.new(size.X - 60, size.Y - 55) else Vector2.new(size.X - 110, size.Y - 150)
		local b = if small then 64 else 90
		local gap = if small then 10 else 14
		local tagSize = math.floor(b * 1.2)
		local tagPos = jump - Vector2.new(0, jumpSize / 2 + tagSize / 2 + gap)
		local dropPos = jump - Vector2.new(jumpSize / 2 + b / 2 + gap, 0)
		local trapPos = jump - Vector2.new(jumpSize / 2 + b / 2 + gap, jumpSize / 2 + b / 2 + gap)
		local decoyPos = trapPos - Vector2.new(b + gap, 0)
		local placements = {
			Tag = { tagPos, tagSize },
			Drop = { dropPos, b },
			Trap = { trapPos - Vector2.new(0, gap), b },
			Decoy = { decoyPos - Vector2.new(0, gap), b },
		}
		for id, p in pairs(placements) do
			local entry = buttons[id]
			entry.Button.Position = UDim2.fromOffset(p[1].X, p[1].Y)
			entry.Button.Size = UDim2.fromOffset(p[2], p[2])
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	return gui, buttons
end

-- ===== Key / gamepad hint bar =====
local function buildHints(): { [string]: any }
	local root = Components.Layer("HUD")
	local bar = New("Frame", {
		Name = "ActionHints",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(640, 56),
		Parent = root,
	})
	Components.List(bar, 10, true, Enum.HorizontalAlignment.Center)
	local chips = {}
	for i, a in ipairs(ACTIONS) do
		local chip = New("Frame", {
			Name = a.Id,
			BackgroundColor3 = Theme.Colors.WindowDark,
			BackgroundTransparency = 0.1,
			Size = UDim2.fromOffset(140, 50),
			LayoutOrder = i,
			ClipsDescendants = true,
			Parent = bar,
		})
		Components.CornerScale(chip, 0.4)
		Components.Stroke(chip, Theme.Colors.Stroke, 3)
		local cd = New("Frame", {
			Name = "Cooldown",
			BackgroundColor3 = a.Color,
			BackgroundTransparency = 0.5,
			Size = UDim2.fromScale(0, 1),
			Parent = chip,
		})
		Components.CornerScale(cd, 0.4)
		local key = New("Frame", { BackgroundColor3 = a.Color, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(5, 5), ZIndex = 2, Parent = chip })
		Components.Corner(key, 10)
		Components.Stroke(key, Theme.Colors.Stroke, 2)
		local keyLabel = Text({ Text = "", TextSize = 20, ZIndex = 3, Parent = key })
		local label = Text({
			Text = a.Icon .. " " .. a.Label,
			TextSize = 18,
			ZIndex = 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -54, 1, 0),
			Position = UDim2.fromOffset(50, 0),
			Parent = chip,
		})
		chips[a.Id] = { Chip = chip, Cooldown = cd, Key = keyLabel, Label = label, Action = a }
	end
	return chips
end

function InputController.Start()
	-- Bindings (pass through while a menu has gamepad focus so D-pad/shoulders still navigate UI)
	for _, a in ipairs(ACTIONS) do
		ContextActionService:BindAction("RR_" .. a.Id, function(_, state, input)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			local isPad = input.UserInputType.Name:sub(1, 7) == "Gamepad"
			if isPad and (Components.CurrentWindow or GuiService.SelectedObject) then
				return Enum.ContextActionResult.Pass
			end
			RUN[a.Id]()
			return Enum.ContextActionResult.Sink
		end, false, a.Key, a.Pad)
	end

	local touchGui, touchButtons = buildTouchButtons()
	local chips = buildHints()

	local function refresh()
		local mode = Components.InputMode()
		touchGui.Enabled = mode == "Touch"
		for _, a in ipairs(ACTIONS) do
			local visible = actionVisible(a.Id)
			local t = touchButtons[a.Id]
			t.Button.Visible = visible
			local badge = badgeText(a.Id)
			t.Badge.Visible = badge ~= nil
			if badge then
				t.BadgeLabel.Text = badge
			end
			local c = chips[a.Id]
			c.Chip.Visible = visible and mode ~= "Touch"
			c.Key.Text = if mode == "Gamepad" then a.PadText else a.Key.Name
			c.Label.Text = a.Icon .. " " .. a.Label .. (if badge then " " .. badge else "")
		end
	end

	Components.InputModeChanged:Connect(refresh)
	for _, attr in ipairs({ "CarryingEgg", "HoldingDecoy" }) do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	ClientData.Observe({ "Items" }, refresh)

	-- cooldown overlays
	RunService.RenderStepped:Connect(function()
		local f = InputController.TagCooldownFraction()
		touchButtons.Tag.Cooldown.Size = UDim2.fromScale(1, f)
		chips.Tag.Cooldown.Size = UDim2.fromScale(f, 1)
		local stunned = player:GetAttribute("Ragdolled") == true or player:GetAttribute("Trapped") == true
		touchButtons.Tag.Button.BackgroundTransparency = if stunned then 0.5 else 0
	end)

	refresh()
end

return InputController

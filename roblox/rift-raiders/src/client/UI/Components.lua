-- Components: UI constructors shared by every controller (windows, buttons, tabs, grids, cards,
-- progress bars, badges, dialogs, toasts, 3D pet previews) plus the window manager.
--
-- Layout model: every layer ScreenGui has a "Root" frame scaled with a UIScale so that a virtual
-- canvas of roughly Theme.Design (1100x620) fills the screen. Children are laid out in virtual
-- pixels, so a phone, a monitor and a TV all show the same proportions (bigger on TV).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Components = {}
Components.Theme = Theme
Components.Windows = {} :: { [string]: any }
Components.CurrentWindow = nil :: string?

local windowChanged = Instance.new("BindableEvent")
Components.WindowChanged = windowChanged.Event -- (name: string?, open: boolean)

-- ===== Generic helpers =====

function Components.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst: any = Instance.new(className)
	local parent = nil
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local New = Components.New

function Components.Corner(parent: Instance, radius: number?): any
	return New("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner), Parent = parent })
end

function Components.CornerScale(parent: Instance, scale: number): any
	return New("UICorner", { CornerRadius = UDim.new(scale, 0), Parent = parent })
end

function Components.Stroke(parent: Instance, color: Color3?, thickness: number?, border: boolean?): any
	return New("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or Theme.Stroke,
		ApplyStrokeMode = if border == false then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function Components.Gradient(parent: Instance, top: Color3, bottom: Color3?, rotation: number?): any
	return New("UIGradient", {
		Color = ColorSequence.new(top, bottom or Theme.Darken(top, 0.25)),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

function Components.Padding(parent: Instance, px: number, py: number?): any
	local y = py or px
	return New("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, y),
		PaddingBottom = UDim.new(0, y),
		Parent = parent,
	})
end

function Components.List(parent: Instance, padding: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?): any
	return New("UIListLayout", {
		Padding = UDim.new(0, padding or 8),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

-- Text label with the chunky dark outline.
function Components.Text(props: { [string]: any }): any
	local p = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.Text,
		TextSize = 22,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in pairs(props) do
		if k ~= "Outline" then
			p[k] = v
		end
	end
	local label = New(if props.ClassName == "TextBox" then "TextBox" else "TextLabel", nil)
	p.ClassName = nil
	for k, v in pairs(p) do
		if k ~= "Parent" then
			label[k] = v
		end
	end
	if props.Outline ~= false then
		New("UIStroke", {
			Color = Theme.Colors.Stroke,
			Thickness = if type(props.Outline) == "number" then props.Outline else 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = label,
		})
	end
	label.Parent = p.Parent
	return label
end
local Text = Components.Text

function Components.Clear(container: Instance)
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

function Components.Fmt(n: number?): string
	return GameConfig.FormatNumber(n or 0)
end

function Components.Price(currency: string?, amount: number): string
	local icon = if currency == "Shards" then Theme.Icons.Shards else Theme.Icons.Coins
	return icon .. " " .. GameConfig.FormatNumber(amount)
end

function Components.Now(): number
	return workspace:GetServerTimeNow()
end

-- Scale "pop" animation using a dedicated UIScale.
function Components.Pop(obj: Instance, from: number?, info: TweenInfo?)
	local s: any = obj:FindFirstChild("PopScale")
	if not s then
		s = New("UIScale", { Name = "PopScale", Parent = obj })
	end
	s.Scale = from or 0.6
	TweenService:Create(s, info or Theme.Tween.Pop, { Scale = 1 }):Play()
end

function Components.Tween(obj: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local t = TweenService:Create(obj, info, goal)
	t:Play()
	return t
end

-- ===== Device / input =====

function Components.Device(): string
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Desktop"
end

local function modeFromInputType(t: Enum.UserInputType): string?
	if t == Enum.UserInputType.Touch then
		return "Touch"
	end
	if t.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	end
	if t == Enum.UserInputType.Keyboard or t.Name:sub(1, 5) == "Mouse" then
		return "Keyboard"
	end
	return nil
end

local inputMode = modeFromInputType(UserInputService:GetLastInputType())
	or (if GuiService:IsTenFootInterface() then "Gamepad" elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard")
local inputModeChanged = Instance.new("BindableEvent")
Components.InputModeChanged = inputModeChanged.Event -- (mode: "Keyboard" | "Gamepad" | "Touch")

UserInputService.LastInputTypeChanged:Connect(function(t)
	local m = modeFromInputType(t)
	if m and m ~= inputMode then
		inputMode = m
		inputModeChanged:Fire(m)
	end
end)

function Components.InputMode(): string
	return inputMode
end

-- ===== Layers (ScreenGuis with a scaled virtual root) =====

local function computeScale(abs: Vector2): number
	local device = Components.Device()
	local s = math.min(abs.X / Theme.Design.X, abs.Y / Theme.Design.Y)
	if device == "Touch" then
		s *= Theme.TouchBoost
	end
	return math.clamp(s, Theme.MinScale, Theme.MaxScale[device] or 1.35)
end

function Components.Screen(name: string, displayOrder: number, ignoreInset: boolean?): (any, any)
	local gui = New("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = ignoreInset == true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Parent = playerGui,
	})
	local root = New("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local scale = New("UIScale", { Parent = root })
	local function update()
		local abs = gui.AbsoluteSize
		if abs.X < 2 or abs.Y < 2 then
			return
		end
		local s = computeScale(abs)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
	return gui, root
end

local layers: { [string]: any } = {}
local LAYER_ORDER = { HUD = 5, Windows = 10, Popups = 20, Toasts = 30 }

-- Shared layers: "HUD", "Windows", "Popups", "Toasts". Returns the scaled root frame.
function Components.Layer(name: string): any
	if not layers[name] then
		local _, root = Components.Screen("RR_" .. name, LAYER_ORDER[name] or 5)
		layers[name] = root
	end
	return layers[name]
end

-- Gamepad selection highlight shared by every selectable.
local selectionImage = New("Frame", { Name = "RR_Selection", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
Components.Corner(selectionImage, Theme.Corner)
New("UIStroke", { Color = Theme.Colors.Accent, Thickness = 4, Parent = selectionImage })

function Components.Selectable(obj: any)
	obj.Selectable = true
	obj.SelectionImageObject = selectionImage
end

function Components.Select(obj: any?)
	if obj and Components.InputMode() == "Gamepad" then
		GuiService.SelectedObject = obj
	end
end

-- ===== Buttons =====

local buttonInfo: any = setmetatable({}, { __mode = "k" })

-- opts: Text, Color, TextColor, TextSize, Size, Position, AnchorPoint, Parent, OnClick, Name,
--       LayoutOrder, Corner, Font
function Components.Button(opts: { [string]: any }): any
	local color = opts.Color or Theme.Colors.Accent
	local btn = New("TextButton", {
		Name = opts.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Size = opts.Size or UDim2.fromOffset(160, Theme.ButtonHeight),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = opts.ZIndex or 1,
	})
	Components.Selectable(btn)
	Components.Corner(btn, opts.Corner or Theme.Corner)
	New("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 185)),
		Rotation = 90,
		Parent = btn,
	})
	Components.Stroke(btn, Theme.Colors.Stroke, 3)
	-- glossy highlight on the upper half
	local shine = New("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		Size = UDim2.new(1, -10, 0.38, 0),
		Position = UDim2.fromOffset(5, 4),
		ZIndex = btn.ZIndex,
		Parent = btn,
	})
	Components.Corner(shine, math.max((opts.Corner or Theme.Corner) - 4, 4))
	local label = Text({
		Name = "Label",
		Text = opts.Text or "",
		TextSize = opts.TextSize or 24,
		Font = opts.Font or Theme.Font,
		TextColor3 = opts.TextColor or Theme.Colors.Text,
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.fromOffset(6, 3),
		RichText = true,
		ZIndex = btn.ZIndex + 1,
		Parent = btn,
	})
	local scale = New("UIScale", { Parent = btn })
	local info = { Color = color, Enabled = true, OnClick = opts.OnClick, Last = 0, Label = label }
	buttonInfo[btn] = info

	btn.MouseEnter:Connect(function()
		if info.Enabled then
			TweenService:Create(scale, Theme.Tween.Fast, { Scale = 1.05 }):Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		if info.Enabled then
			TweenService:Create(scale, Theme.Tween.Fast, { Scale = 0.92 }):Play()
		end
	end)
	btn.Activated:Connect(function()
		scale.Scale = 0.92
		TweenService:Create(scale, Theme.Tween.Pop, { Scale = 1 }):Play()
		local now = os.clock()
		if not info.Enabled or now - info.Last < 0.15 then
			return
		end
		info.Last = now
		if info.OnClick then
			task.spawn(info.OnClick)
		end
	end)
	btn.Parent = opts.Parent
	return btn
end

function Components.SetEnabled(btn: any, enabled: boolean)
	local info = buttonInfo[btn]
	if not info or info.Enabled == enabled then
		return
	end
	info.Enabled = enabled
	btn.BackgroundColor3 = if enabled then info.Color else Theme.Colors.Disabled
	info.Label.TextTransparency = if enabled then 0 else 0.3
end

function Components.SetText(btn: any, text: string)
	local info = buttonInfo[btn]
	if info and info.Label.Text ~= text then
		info.Label.Text = text
	end
end

function Components.SetColor(btn: any, color: Color3)
	local info = buttonInfo[btn]
	if info then
		info.Color = color
		if info.Enabled then
			btn.BackgroundColor3 = color
		end
	end
end

function Components.SetOnClick(btn: any, fn: () -> ())
	local info = buttonInfo[btn]
	if info then
		info.OnClick = fn
	end
end

-- ===== Containers =====

-- opts: Color, Parent, Size, Position, AnchorPoint, LayoutOrder, Name, Corner, Stroke
function Components.Card(opts: { [string]: any }): any
	local color = opts.Color or Theme.Colors.Panel
	local card = New("Frame", {
		Name = opts.Name or "Card",
		BackgroundColor3 = color,
		Size = opts.Size or UDim2.fromScale(1, 1),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
		BackgroundTransparency = opts.Transparency or 0,
	})
	Components.Corner(card, opts.Corner or Theme.Corner)
	Components.Gradient(card, Theme.Lighten(color, 0.08), Theme.Darken(color, 0.18))
	Components.Stroke(card, opts.Stroke or Theme.Colors.Stroke, opts.StrokeThickness or 3)
	card.Parent = opts.Parent
	return card
end

function Components.ScrollList(parent: Instance, padding: number?, props: { [string]: any }?): any
	local sf = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.Accent,
		Selectable = false,
	})
	if props then
		for k, v in pairs(props) do
			sf[k] = v
		end
	end
	Components.List(sf, padding or 8)
	New("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = sf,
	})
	sf.Parent = parent
	return sf
end

function Components.ScrollGrid(parent: Instance, cell: Vector2, padding: number?, props: { [string]: any }?): any
	local sf = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.Accent,
		Selectable = false,
	})
	if props then
		for k, v in pairs(props) do
			sf[k] = v
		end
	end
	New("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(padding or 10, padding or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = sf,
	})
	New("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = sf,
	})
	sf.Parent = parent
	return sf
end

-- Horizontal tab bar. tabs = { {Id=, Text=} }. Returns { Frame, Buttons, Current, Select(id) }.
function Components.Tabs(parent: Instance, tabs: { any }, onSelect: (string) -> (), props: { [string]: any }?): any
	local bar = New("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 58),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		Selectable = false,
	})
	if props then
		for k, v in pairs(props) do
			bar[k] = v
		end
	end
	Components.List(bar, 8, true)
	New("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6), Parent = bar })
	local obj = { Frame = bar, Buttons = {}, Current = nil }
	function obj.Select(id: string)
		obj.Current = id
		for tid, b in pairs(obj.Buttons) do
			Components.SetColor(b, if tid == id then Theme.Colors.Accent else Theme.Colors.PanelLight)
		end
		onSelect(id)
	end
	for i, t in ipairs(tabs) do
		local w = math.max(110, 22 + (utf8.len(t.Text) or #t.Text) * 13)
		obj.Buttons[t.Id] = Components.Button({
			Name = "Tab_" .. t.Id,
			Text = t.Text,
			TextSize = 22,
			Size = UDim2.fromOffset(w, 48),
			LayoutOrder = i,
			Color = Theme.Colors.PanelLight,
			Parent = bar,
			OnClick = function()
				obj.Select(t.Id)
			end,
		})
	end
	bar.Parent = parent
	return obj
end

-- Progress bar. Returns { Frame, Fill, Label, Set(fraction, text?) }.
function Components.ProgressBar(opts: { [string]: any }): any
	local frame = New("Frame", {
		Name = opts.Name or "Progress",
		BackgroundColor3 = Theme.Colors.WindowDark,
		Size = opts.Size or UDim2.new(1, 0, 0, 22),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
		ClipsDescendants = true,
	})
	Components.CornerScale(frame, 0.5)
	Components.Stroke(frame, Theme.Colors.Stroke, 2)
	local fill = New("Frame", {
		Name = "Fill",
		BackgroundColor3 = opts.Color or Theme.Colors.Accent,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	Components.CornerScale(fill, 0.5)
	Components.Gradient(fill, Theme.Lighten(opts.Color or Theme.Colors.Accent, 0.25), opts.Color or Theme.Colors.Accent)
	local label = Text({ Name = "Label", Text = "", TextSize = opts.TextSize or 16, ZIndex = 2, Parent = frame })
	local obj = { Frame = frame, Fill = fill, Label = label }
	function obj.Set(fraction: number, text: string?)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		if text then
			label.Text = text
		end
	end
	function obj.SetColor(c: Color3)
		fill.BackgroundColor3 = c
		local g = fill:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(Theme.Lighten(c, 0.25), c)
		end
	end
	frame.Parent = opts.Parent
	return obj
end

function Components.RarityBadge(rarity: string?, props: { [string]: any }?): any
	local color = Theme.Rarity(rarity)
	local badge = New("Frame", {
		Name = "Rarity",
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(110, 26),
	})
	Components.CornerScale(badge, 0.5)
	Components.Stroke(badge, Theme.Colors.Stroke, 2)
	Components.Gradient(badge, Theme.Lighten(color, 0.2), Theme.Darken(color, 0.15))
	Text({ Name = "Label", Text = rarity or "?", TextSize = 16, TextColor3 = Theme.Colors.Text, Size = UDim2.fromScale(1, 1), Parent = badge })
	if props then
		for k, v in pairs(props) do
			badge[k] = v
		end
	end
	return badge
end

function Components.SetRarityBadge(badge: any, rarity: string?)
	local color = Theme.Rarity(rarity)
	badge.BackgroundColor3 = color
	local g = badge:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(Theme.Lighten(color, 0.2), Theme.Darken(color, 0.15))
	end
	badge.Label.Text = rarity or "?"
end

-- Currency pill: icon + number. Returns { Frame, Label, Set(n) }.
function Components.CurrencyLabel(kind: string, props: { [string]: any }?): any
	local color = Theme.Colors[kind] or Theme.Colors.Coins
	local frame = New("Frame", {
		Name = kind,
		BackgroundColor3 = Theme.Colors.WindowDark,
		Size = UDim2.fromOffset(170, 46),
	})
	Components.CornerScale(frame, 0.5)
	Components.Stroke(frame, Theme.Colors.Stroke, 3)
	Components.Gradient(frame, Theme.Colors.Panel, Theme.Colors.WindowDark)
	local icon = New("Frame", {
		Name = "Icon",
		BackgroundColor3 = color,
		Size = UDim2.new(0, 46, 0, 46),
		Position = UDim2.fromOffset(-6, 0),
		Parent = frame,
	})
	Components.CornerScale(icon, 0.5)
	Components.Stroke(icon, Theme.Colors.Stroke, 3)
	Text({ Text = Theme.Icons[kind] or "", TextSize = 24, Outline = false, Parent = icon })
	local label = Text({
		Name = "Value",
		Text = "0",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Size = UDim2.new(1, -52, 1, 0),
		Position = UDim2.fromOffset(48, 0),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	if props then
		for k, v in pairs(props) do
			frame[k] = v
		end
	end
	local obj = { Frame = frame, Label = label, Icon = icon, Value = nil :: number? }
	function obj.Set(n: number, suffix: string?)
		local text = GameConfig.FormatNumber(n) .. (suffix or "")
		if label.Text ~= text then
			label.Text = text
			if obj.Value and n > obj.Value then
				Components.Pop(icon, 1.25, Theme.Tween.Fast)
			end
		end
		obj.Value = n
	end
	return obj
end

-- ===== 3D pet previews =====

local modelFactory: any = nil
local function getModelFactory(): any
	if modelFactory then
		return modelFactory
	end
	-- dynamic lookup: ModelFactory is optional at type-check time and may load after us
	local mf = Shared:FindFirstChild("ModelFactory")
	if mf and mf:IsA("ModuleScript") then
		local ok, res = pcall(require, mf)
		if ok and type(res) == "table" and type(res.BuildPet) == "function" then
			modelFactory = res
		end
	end
	return modelFactory
end

local ARCHETYPE_EMOJI = {
	Quadruped = "🐾",
	Dino = "🦖",
	Bird = "🐦",
	Blob = "🫧",
	Serpent = "🐍",
	Bug = "🐞",
	Floaty = "✨",
	Golem = "🗿",
}

local spinning: { [any]: any } = {}
RunService.Heartbeat:Connect(function(dt)
	if player:GetAttribute("LowGraphics") then
		return
	end
	for vp, data in pairs(spinning) do
		if not vp.Parent then
			spinning[vp] = nil
		elseif vp.Visible then
			data.Angle += dt * 0.8
			local a = data.Angle
			data.Camera.CFrame = CFrame.lookAt(
				data.Center + Vector3.new(math.sin(a) * data.Dist, data.Dist * 0.28, -math.cos(a) * data.Dist),
				data.Center
			)
		end
	end
end)

local function fallbackIcon(parent: any, species: any, silhouette: boolean?)
	local circle = New("Frame", {
		Name = "Fallback",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundColor3 = if silhouette then Color3.fromRGB(15, 12, 30) elseif species then species.Colors[1] else Theme.Colors.Panel,
		Parent = parent,
	})
	New("UIAspectRatioConstraint", { Parent = circle })
	Components.CornerScale(circle, 0.5)
	Components.Stroke(circle, Theme.Colors.Stroke, 3)
	Text({
		Text = if silhouette then "?" else (species and ARCHETYPE_EMOJI[species.Archetype] or "🥚"),
		TextScaled = true,
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.15, 0.15),
		Outline = false,
		Parent = circle,
	})
end

-- Builds a ViewportFrame showing a pet. pet = PetData-like ({Species, Size, Mutation, Tier}).
-- opts: Silhouette (black shape for undiscovered species), Spin (slow turntable), Size, Position, Parent.
function Components.PetViewport(pet: { [string]: any }, opts: { [string]: any }?): any
	local o = opts or {}
	local holder = New("Frame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = o.Size or UDim2.fromScale(1, 1),
		Position = o.Position or UDim2.new(),
		AnchorPoint = o.AnchorPoint or Vector2.zero,
		LayoutOrder = o.LayoutOrder or 0,
	})
	local species = GameConfig.GetSpecies(pet.Species)
	local mf = getModelFactory()
	local model: any = nil
	if mf and species then
		local ok, res = pcall(mf.BuildPet, pet.Species, { Size = pet.Size, Mutation = pet.Mutation, Tier = pet.Tier })
		if ok and typeof(res) == "Instance" and (res:IsA("Model") or res:IsA("BasePart")) then
			model = res
		end
	end
	if not model then
		fallbackIcon(holder, species, o.Silhouette)
		holder.Parent = o.Parent
		return holder
	end
	local vp = New("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.5),
		Parent = holder,
	})
	if o.Silhouette then
		vp.ImageColor3 = Color3.fromRGB(0, 0, 0)
		vp.ImageTransparency = 0.15
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	local center: Vector3
	local size: Vector3
	if model:IsA("Model") then
		model:PivotTo(CFrame.new())
		local cf, sz = model:GetBoundingBox()
		center, size = cf.Position, sz
	else
		model.CFrame = CFrame.new()
		center, size = Vector3.zero, model.Size
	end
	model.Parent = vp
	local cam = New("Camera", { FieldOfView = 35, Parent = vp })
	vp.CurrentCamera = cam
	local radius = size.Magnitude / 2
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.02
	local angle = math.rad(25)
	cam.CFrame = CFrame.lookAt(center + Vector3.new(math.sin(angle) * dist, dist * 0.28, -math.cos(angle) * dist), center)
	if o.Spin then
		spinning[vp] = { Camera = cam, Center = center, Dist = dist, Angle = angle }
	end
	holder.Parent = o.Parent
	return holder
end

-- ===== Modal stack + windows =====

local modalStack: { any } = {} -- confirm dialogs / popups that B should close first

local function pushModal(entry: any)
	table.insert(modalStack, entry)
end

local function removeModal(entry: any)
	local i = table.find(modalStack, entry)
	if i then
		table.remove(modalStack, i)
	end
end

local backdrop: any = nil
local function getBackdrop(): any
	if not backdrop then
		local root = Components.Layer("Windows")
		backdrop = New("TextButton", {
			Name = "Backdrop",
			Text = "",
			AutoButtonColor = false,
			Selectable = false,
			BackgroundColor3 = Theme.Colors.Backdrop,
			BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = root,
		})
		backdrop.Activated:Connect(function()
			if Components.CurrentWindow then
				Components.Close(Components.CurrentWindow)
			end
		end)
	end
	return backdrop
end

-- Creates a registered window. Returns { Name, Frame, Body, TitleLabel, CloseButton, OnOpen, OnClose, DefaultSelection }.
function Components.Window(name: string, title: string, icon: string?, opts: { [string]: any }?): any
	local o = opts or {}
	local root = Components.Layer("Windows")
	getBackdrop()
	local size = o.Size or Theme.WindowSize
	local color = o.Color or Theme.Colors.Window
	local frame = New("Frame", {
		Name = "Window_" .. name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = color,
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	Components.Corner(frame, 24)
	Components.Gradient(frame, Theme.Lighten(color, 0.06), Theme.Colors.WindowDark)
	Components.Stroke(frame, Theme.Colors.Stroke, 5)

	local titleBar = New("Frame", {
		Name = "TitleBar",
		BackgroundColor3 = o.TitleColor or Theme.Colors.Accent2,
		Size = UDim2.new(1, 0, 0, 60),
		Parent = frame,
	})
	Components.Corner(titleBar, 24)
	Components.Gradient(titleBar, Theme.Lighten(o.TitleColor or Theme.Colors.Accent2, 0.2), o.TitleColor or Theme.Colors.Accent2)
	Components.Stroke(titleBar, Theme.Colors.Stroke, 4)
	local titleLabel = Text({
		Name = "Title",
		Text = (icon and (icon .. "  ") or "") .. title,
		TextSize = 34,
		Outline = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -100, 1, 0),
		Position = UDim2.fromOffset(22, 0),
		Parent = titleBar,
	})
	local win: any = { Name = name, Frame = frame, OnOpen = nil, OnClose = nil, DefaultSelection = nil, IsOpen = false, TitleLabel = titleLabel }
	win.CloseButton = Components.Button({
		Name = "Close",
		Text = Theme.Icons.Close,
		TextSize = 30,
		Color = Theme.Colors.Bad,
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 14, 0, 6),
		Corner = 32,
		ZIndex = 3,
		Parent = frame,
		OnClick = function()
			Components.Close(name)
		end,
	})
	win.Body = New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 72),
		Size = UDim2.new(1, -32, 1, -86),
		Parent = frame,
	})
	Components.Windows[name] = win
	return win
end

function Components.Open(name: string)
	local win = Components.Windows[name]
	if not win then
		warn("[UI] unknown window", name)
		return
	end
	if Components.CurrentWindow and Components.CurrentWindow ~= name then
		Components.Close(Components.CurrentWindow, true)
	end
	Components.CurrentWindow = name
	win.IsOpen = true
	getBackdrop().Visible = true
	win.Frame.Visible = true
	Components.Pop(win.Frame, 0.75)
	if win.OnOpen then
		local ok, err = pcall(win.OnOpen)
		if not ok then
			warn("[UI] OnOpen", name, err)
		end
	end
	Components.Select(win.DefaultSelection or win.CloseButton)
	windowChanged:Fire(name, true)
end

function Components.Close(name: string, switching: boolean?)
	local win = Components.Windows[name]
	if not win or not win.IsOpen then
		return
	end
	win.IsOpen = false
	win.Frame.Visible = false
	if Components.CurrentWindow == name then
		Components.CurrentWindow = nil
	end
	if not switching then
		getBackdrop().Visible = false
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(win.Frame) then
			GuiService.SelectedObject = nil
		end
	end
	if win.OnClose then
		pcall(win.OnClose)
	end
	windowChanged:Fire(name, false)
end

function Components.Toggle(name: string)
	local win = Components.Windows[name]
	if win and win.IsOpen then
		Components.Close(name)
	else
		Components.Open(name)
	end
end

-- Gamepad B: close the top dialog, then the open window, then clear menu selection.
ContextActionService:BindActionAtPriority("RR_Back", function(_, state)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local top = modalStack[#modalStack]
	if top then
		top.Close()
		return Enum.ContextActionResult.Sink
	end
	if Components.CurrentWindow then
		Components.Close(Components.CurrentWindow)
		return Enum.ContextActionResult.Sink
	end
	if GuiService.SelectedObject then
		GuiService.SelectedObject = nil
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)

-- ===== Modal popup helper =====

-- Creates a dimmed full-screen modal on the Popups layer. Returns { Frame (backdrop), Close() }.
function Components.Modal(onClose: (() -> ())?, dismissOnBackdrop: boolean?): any
	local root = Components.Layer("Popups")
	local bg = New("TextButton", {
		Name = "Modal",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	TweenService:Create(bg, Theme.Tween.Fast, { BackgroundTransparency = 0.35 }):Play()
	local prevSelection = GuiService.SelectedObject
	local entry: any = {}
	local closed = false
	entry.Frame = bg
	function entry.Close()
		if closed then
			return
		end
		closed = true
		removeModal(entry)
		bg:Destroy()
		if Components.InputMode() == "Gamepad" and prevSelection and prevSelection.Parent and prevSelection.Visible then
			GuiService.SelectedObject = prevSelection
		end
		if onClose then
			task.spawn(onClose)
		end
	end
	if dismissOnBackdrop then
		bg.Activated:Connect(entry.Close)
	end
	pushModal(entry)
	return entry
end

-- Hold-to-confirm behaviour for a button (mouse, touch, and gamepad A while selected).
local function attachHold(btn: any, seconds: number, onDone: () -> ()): any
	local fill = New("Frame", {
		Name = "HoldFill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(0, 1),
		ZIndex = btn.ZIndex,
		Parent = btn,
	})
	Components.Corner(fill, Theme.Corner)
	local holding = false
	local progress = 0
	local done = false
	local conn: RBXScriptConnection? = nil
	local function stop()
		holding = false
	end
	local function start()
		if done or holding then
			return
		end
		holding = true
		if conn then
			return
		end
		conn = RunService.RenderStepped:Connect(function(dt)
			if not btn.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			if holding then
				progress = math.min(progress + dt / seconds, 1)
			else
				progress = math.max(progress - dt * 2, 0)
			end
			fill.Size = UDim2.fromScale(progress, 1)
			if progress >= 1 and not done then
				done = true
				if conn then
					conn:Disconnect()
				end
				onDone()
			elseif progress <= 0 and not holding and conn then
				conn:Disconnect()
				conn = nil
			end
		end)
	end
	btn.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			start()
		end
	end)
	btn.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			stop()
		end
	end)
	btn.MouseLeave:Connect(stop)
	local c1 = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonA and GuiService.SelectedObject == btn then
			start()
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonA then
			stop()
		end
	end)
	btn.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
		if conn then
			conn:Disconnect()
		end
	end)
	return fill
end
Components.AttachHold = attachHold

-- Confirmation dialog.
-- opts: Title, Text, ConfirmText, CancelText, Danger, HoldSeconds (hold-to-confirm), Color,
--       OnConfirm, OnCancel, Build(contentFrame) for extra content, Height
function Components.Confirm(opts: { [string]: any }): any
	local confirmed = false
	local modal = Components.Modal(function()
		if not confirmed and opts.OnCancel then
			opts.OnCancel()
		end
	end, false)
	local height = opts.Height or 330
	local accent = opts.Color or (if opts.Danger then Theme.Colors.Bad else Theme.Colors.Accent2)
	local dialog = New("Frame", {
		Name = "Dialog",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, height),
		BackgroundColor3 = Theme.Colors.Window,
		Parent = modal.Frame,
	})
	Components.Corner(dialog, 22)
	Components.Gradient(dialog, Theme.Colors.Window, Theme.Colors.WindowDark)
	Components.Stroke(dialog, Theme.Colors.Stroke, 5)
	local head = New("Frame", { BackgroundColor3 = accent, Size = UDim2.new(1, 0, 0, 54), Parent = dialog })
	Components.Corner(head, 22)
	Components.Stroke(head, Theme.Colors.Stroke, 4)
	Text({ Text = opts.Title or "Are you sure?", TextSize = 30, Outline = 3, Parent = head })
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 64),
		Size = UDim2.new(1, -40, 1, -64 - 92),
		Parent = dialog,
	})
	if opts.Text then
		Text({
			Text = opts.Text,
			TextSize = 22,
			Font = Theme.FontBody,
			RichText = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = content,
		})
	end
	if opts.Build then
		opts.Build(content)
	end
	local cancel = Components.Button({
		Text = opts.CancelText or "Cancel",
		Color = Theme.Colors.PanelLight,
		Size = UDim2.fromOffset(200, Theme.ButtonHeight),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -16),
		Parent = dialog,
		OnClick = function()
			modal.Close()
		end,
	})
	local okBtn
	local function doConfirm()
		if confirmed then
			return
		end
		confirmed = true
		modal.Close()
		if opts.OnConfirm then
			opts.OnConfirm()
		end
	end
	if opts.HoldSeconds then
		okBtn = Components.Button({
			Text = opts.ConfirmText or ("Hold " .. opts.HoldSeconds .. "s to confirm"),
			Color = accent,
			Size = UDim2.fromOffset(290, Theme.ButtonHeight),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -24, 1, -16),
			Parent = dialog,
		})
		attachHold(okBtn, opts.HoldSeconds, doConfirm)
	else
		okBtn = Components.Button({
			Text = opts.ConfirmText or "Confirm",
			Color = accent,
			Size = UDim2.fromOffset(290, Theme.ButtonHeight),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -24, 1, -16),
			Parent = dialog,
			OnClick = doConfirm,
		})
	end
	Components.Pop(dialog, 0.7)
	Components.Select(cancel)
	modal.Dialog = dialog
	modal.ConfirmButton = okBtn
	modal.Content = content
	return modal
end

-- ===== Toasts =====

local toastList: any = nil
local function getToastList(): any
	if not toastList then
		local root = Components.Layer("Toasts")
		toastList = New("Frame", {
			Name = "Toasts",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 168),
			Size = UDim2.fromOffset(520, 320),
			Parent = root,
		})
		Components.List(toastList, 6, false, Enum.HorizontalAlignment.Center)
	end
	return toastList
end

local toastCounter = 0
function Components.Toast(text: string, kind: string?, duration: number?)
	local list = getToastList()
	toastCounter += 1
	local color = Theme.Kind[kind or "info"] or Theme.Colors.Info
	local toast = New("Frame", {
		Name = "Toast",
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(500, 48),
		LayoutOrder = toastCounter,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = list,
	})
	Components.CornerScale(toast, 0.3)
	Components.Gradient(toast, Theme.Lighten(color, 0.15), Theme.Darken(color, 0.25))
	Components.Stroke(toast, Theme.Colors.Stroke, 3)
	Components.Padding(toast, 14, 8)
	Text({
		Text = text,
		TextSize = 22,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = toast,
	})
	Components.Pop(toast, 0.5)
	-- keep at most 4 toasts on screen
	local toasts = {}
	for _, c in ipairs(list:GetChildren()) do
		if c.Name == "Toast" then
			table.insert(toasts, c)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #toasts - 4 do
		toasts[i]:Destroy()
	end
	task.delay(duration or 3.5, function()
		if toast.Parent then
			local s = toast:FindFirstChild("PopScale")
			if s then
				TweenService:Create(s, Theme.Tween.Fast, { Scale = 0 }):Play()
			end
			task.wait(0.15)
			toast:Destroy()
		end
	end)
end

return Components

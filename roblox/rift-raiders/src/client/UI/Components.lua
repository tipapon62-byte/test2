-- Components: UI constructors shared by every controller (windows, chunky buttons, badges, switches,
-- big outlined numbers, tabs, grids, cards, progress bars, dialogs, toasts, confetti, 3D pet
-- previews) plus the window manager.
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
Components.Anchors = {} :: { [string]: GuiObject } -- named HUD elements other controllers can aim at

local windowChanged = Instance.new("BindableEvent")
Components.WindowChanged = windowChanged.Event -- (name: string?, open: boolean)

local function lowGraphics(): boolean
	return player:GetAttribute("LowGraphics") == true
end
Components.LowGraphics = lowGraphics

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

-- Text label with the chunky dark outline. Extra prop: Outline (false | thickness), ClassName "TextBox".
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
		local size = tonumber(p.TextSize) or 22
		New("UIStroke", {
			Color = Theme.Colors.Stroke,
			Thickness = if type(props.Outline) == "number" then props.Outline else math.clamp(size / 10, 1.5, 3.5),
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

-- Press squash for custom buttons (squeeze on press, springy release).
function Components.Squash(btn: GuiButton)
	local s: any = btn:FindFirstChild("SquashScale") or New("UIScale", { Name = "SquashScale", Parent = btn })
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(s, Theme.Tween.Fast, { Scale = 0.88 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(s, Theme.Tween.Fast, { Scale = 1 }):Play()
	end)
	btn.Activated:Connect(function()
		s.Scale = 0.88
		TweenService:Create(s, Theme.Tween.Bounce, { Scale = 1 }):Play()
	end)
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

-- Converts a screen-space (absolute) point into the virtual coordinates of a layer root.
function Components.ToLayer(root: GuiObject, abs: Vector2): UDim2
	local s = root:FindFirstChildOfClass("UIScale")
	local k = if s then s.Scale else 1
	local rel = (abs - root.AbsolutePosition) / k
	return UDim2.fromOffset(rel.X, rel.Y)
end

-- Gamepad selection highlight shared by every selectable.
local selectionImage = New("Frame", { Name = "RR_Selection", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
Components.Corner(selectionImage, Theme.Corner + 4)
New("UIStroke", { Color = Theme.Colors.Accent, Thickness = 5, LineJoinMode = Enum.LineJoinMode.Round, Parent = selectionImage })

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

-- Chunky outlined button: flat colour, dark bevel lip at the bottom, glossy top, thick outline.
-- opts: Text, Icon (emoji shown left of the text), Color, TextColor, TextSize, Size, Position,
--       AnchorPoint, Parent, OnClick, Name, LayoutOrder, Corner, Font, ZIndex, IconScale
function Components.Button(opts: { [string]: any }): any
	local color = opts.Color or Theme.Colors.Good
	local corner = opts.Corner or Theme.Corner
	local z = opts.ZIndex or 1
	local btn = New("TextButton", {
		Name = opts.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Size = opts.Size or UDim2.fromOffset(160, Theme.ButtonHeight),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = z,
	})
	Components.Selectable(btn)
	Components.Corner(btn, corner)
	New("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(236, 236, 236)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 190)),
		}),
		Rotation = 90,
		Parent = btn,
	})
	Components.Stroke(btn, Theme.Colors.Stroke, 4)
	-- bevel lip (darker bottom band) + glossy highlight
	local lip = New("Frame", {
		Name = "Lip",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.78,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0.2, 0),
		ZIndex = z,
		Parent = btn,
	})
	Components.Corner(lip, corner)
	local shine = New("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.72,
		Size = UDim2.new(1, -12, 0.26, 0),
		Position = UDim2.fromOffset(6, 4),
		ZIndex = z,
		Parent = btn,
	})
	Components.Corner(shine, math.max(corner - 4, 4))
	local icon = nil
	local textSize = opts.TextSize or 26
	if opts.Icon then
		local k = opts.IconScale or 0.72
		icon = Text({
			Name = "Icon",
			Text = opts.Icon,
			TextScaled = true,
			Outline = false,
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Size = UDim2.fromScale(k, k),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.47, 0),
			ZIndex = z + 1,
			Parent = btn,
		})
	end
	local hasText = (opts.Text or "") ~= ""
	local label = Text({
		Name = "Label",
		Text = opts.Text or "",
		TextSize = textSize,
		Font = opts.Font or Theme.Font,
		TextColor3 = opts.TextColor or Theme.Colors.Text,
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 2),
		RichText = true,
		ZIndex = z + 1,
		Outline = math.clamp(textSize / 9, 2, 3.5),
		Parent = btn,
	})
	if icon then
		if hasText then
			-- icon on the left, label fills the rest
			-- the icon is square (height-relative): keep the label clear of it
			local h = if btn.Size.Y.Offset > 0 then btn.Size.Y.Offset else Theme.ButtonHeight
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Position = UDim2.fromOffset(0, 2)
			label.Size = UDim2.new(1, -6, 1, -8)
			New("UIPadding", { PaddingLeft = UDim.new(0, 14 + (opts.IconScale or 0.72) * h), Parent = label })
		else
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.47)
		end
	end
	local scale = New("UIScale", { Parent = btn })
	local info = { Color = color, Enabled = true, OnClick = opts.OnClick, Last = 0, Label = label, Icon = icon }
	buttonInfo[btn] = info

	btn.MouseEnter:Connect(function()
		if info.Enabled then
			TweenService:Create(scale, Theme.Tween.Fast, { Scale = 1.06 }):Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		if info.Enabled then
			TweenService:Create(scale, Theme.Tween.Fast, { Scale = 0.9 }):Play()
		end
	end)
	btn.Activated:Connect(function()
		scale.Scale = 0.9
		TweenService:Create(scale, Theme.Tween.Bounce, { Scale = 1 }):Play()
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

-- Square icon-only button (right side of the HUD). opts: Icon, Color, Size (number), + Button opts.
function Components.IconButton(opts: { [string]: any }): any
	local size = opts.Size or 72
	local o = table.clone(opts)
	o.Size = UDim2.fromOffset(size, size)
	o.Text = opts.Text or ""
	o.IconScale = opts.IconScale or 0.66
	o.Corner = opts.Corner or 16
	local btn = Components.Button(o)
	if opts.Caption then
		Text({
			Name = "Caption",
			Text = opts.Caption,
			TextSize = 15,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 4),
			Size = UDim2.new(1, 10, 0, 18),
			ZIndex = btn.ZIndex + 2,
			Parent = btn,
		})
	end
	return btn
end

function Components.SetEnabled(btn: any, enabled: boolean)
	local info = buttonInfo[btn]
	if not info or info.Enabled == enabled then
		return
	end
	info.Enabled = enabled
	btn.BackgroundColor3 = if enabled then info.Color else Theme.Colors.Disabled
	info.Label.TextTransparency = if enabled then 0 else 0.25
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

-- ===== Badges / switches / pills =====

-- Red circular notification badge ("!") on the top-right corner of `parent`.
function Components.Badge(parent: Instance, text: string?): any
	local badge = New("Frame", {
		Name = "Badge",
		BackgroundColor3 = Theme.Colors.Badge,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 20,
		Visible = false,
		Parent = parent,
	})
	Components.CornerScale(badge, 0.5)
	Components.Stroke(badge, Color3.new(1, 1, 1), 3)
	Text({ Name = "Label", Text = text or "!", TextSize = 22, Font = Theme.FontHeavy, Outline = 2, ZIndex = 21, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 2), Parent = badge })
	local s = New("UIScale", { Parent = badge })
	TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.18 }):Play()
	return badge
end

function Components.SetBadge(badge: any, visible: boolean, text: string?)
	if not badge then
		return
	end
	if text then
		badge.Label.Text = text
	end
	if visible and not badge.Visible then
		badge.Visible = true
		Components.Pop(badge, 0.2, Theme.Tween.Bounce)
	elseif not visible then
		badge.Visible = false
	end
end

-- On/off switch. opts: Value, OnChanged(v), Size, Position, AnchorPoint, LayoutOrder, Parent, Name.
-- Returns { Frame, Set(v, silent?), Get() }.
function Components.Switch(opts: { [string]: any }): any
	local value = opts.Value == true
	local track = New("TextButton", {
		Name = opts.Name or "Switch",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.Disabled,
		Size = opts.Size or UDim2.fromOffset(96, 48),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
	})
	Components.Selectable(track)
	Components.Corner(track, 12)
	Components.Stroke(track, Theme.Colors.Stroke, 4)
	Components.Gradient(track, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	local knob = New("Frame", {
		Name = "Knob",
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0.44, 0, 1, -10),
		Position = UDim2.new(0, 5, 0.5, 0),
		Parent = track,
	})
	Components.Corner(knob, 9)
	Components.Stroke(knob, Theme.Colors.Stroke, 3)
	local mark = Text({ Text = "", TextSize = 18, Outline = 2, Parent = knob })
	local obj = { Frame = track }
	local function render(animate: boolean)
		local goal = {
			Position = if value then UDim2.new(0.56, -5, 0.5, 0) else UDim2.new(0, 5, 0.5, 0),
		}
		track.BackgroundColor3 = if value then Theme.Colors.Good else Theme.Colors.Disabled
		knob.BackgroundColor3 = if value then Color3.fromRGB(235, 255, 235) else Color3.new(1, 1, 1)
		mark.Text = if value then "✓" else ""
		mark.TextColor3 = Theme.Colors.Good
		if animate then
			TweenService:Create(knob, Theme.Tween.Pop, goal):Play()
		else
			knob.Position = goal.Position
		end
	end
	function obj.Set(v: boolean, silent: boolean?)
		value = v == true
		render(true)
		if not silent and opts.OnChanged then
			task.spawn(opts.OnChanged, value)
		end
	end
	function obj.Get(): boolean
		return value
	end
	track.Activated:Connect(function()
		obj.Set(not value)
	end)
	Components.Squash(track)
	render(false)
	track.Parent = opts.Parent
	return obj
end

-- Rounded HUD pill (dark translucent or coloured). opts: Text, Color, Transparency, Size, Position,
-- AnchorPoint, LayoutOrder, Parent, Name, TextSize, TextColor. The text label is pill.Label.
function Components.Pill(opts: { [string]: any }): any
	local color = opts.Color or Theme.Colors.PillBg
	local pill = New("Frame", {
		Name = opts.Name or "Pill",
		BackgroundColor3 = color,
		BackgroundTransparency = opts.Transparency or 0,
		Size = opts.Size or UDim2.fromOffset(220, 44),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
		Visible = opts.Visible ~= false,
	})
	Components.CornerScale(pill, 0.5)
	Components.Gradient(pill, Theme.Lighten(color, 0.12), Theme.Darken(color, 0.2))
	Components.Stroke(pill, Theme.Colors.Stroke, 4)
	Text({
		Name = "Label",
		Text = opts.Text or "",
		TextSize = opts.TextSize or 22,
		TextColor3 = opts.TextColor or Theme.Colors.Text,
		RichText = true,
		TextWrapped = false,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Parent = pill,
	})
	pill.Parent = opts.Parent
	return pill
end

-- Big outlined number with an emoji icon on the left (HUD currencies), with count-up + bounce.
-- opts: Icon, Color, TextSize, Prefix, Suffix, Parent, Position, AnchorPoint, LayoutOrder, Name.
-- Returns { Frame, Label, Icon, Value, Set(n, instant?) }.
function Components.BigNumber(opts: { [string]: any }): any
	local size = opts.TextSize or 46
	local frame = New("Frame", {
		Name = opts.Name or "BigNumber",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 6),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
	})
	Components.List(frame, 6, true)
	local icon = Text({
		Name = "Icon",
		Text = opts.Icon or "",
		TextScaled = true,
		Outline = false,
		Size = UDim2.fromOffset(size + 6, size + 6),
		LayoutOrder = 1,
		Parent = frame,
	})
	local label = Text({
		Name = "Value",
		Text = "0",
		TextSize = size,
		Font = Theme.FontHeavy,
		TextColor3 = opts.Color or Theme.Colors.Text,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 6),
		Position = UDim2.fromOffset(0, 3),
		LayoutOrder = 2,
		Outline = math.max(3, size / 12),
		Parent = frame,
	})
	frame.Parent = opts.Parent
	local scale = New("UIScale", { Parent = frame })
	local shown = New("NumberValue", { Value = 0 })
	local obj = { Frame = frame, Label = label, Icon = icon, Value = nil :: number? }
	local prefix, suffix = opts.Prefix or "", opts.Suffix or ""
	local function render()
		label.Text = prefix .. GameConfig.FormatNumber(math.floor(shown.Value + 0.5)) .. suffix
	end
	shown.Changed:Connect(render)
	local tween: Tween? = nil
	function obj.Set(n: number, instant: boolean?)
		local old = obj.Value
		if n == old and not instant then
			return
		end
		obj.Value = n
		if tween then
			tween:Cancel()
		end
		if instant or old == nil or lowGraphics() then
			shown.Value = n
			render()
			return
		end
		tween = TweenService:Create(shown, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = n })
		if tween then
			tween:Play()
		end
		if n > old then
			scale.Scale = 1.18
			TweenService:Create(scale, Theme.Tween.Bounce, { Scale = 1 }):Play()
		end
	end
	return obj
end

-- Text that rises and fades. opts: Text, Color, TextSize, Position (UDim2), Rise (px), Duration, Parent.
function Components.FloatText(opts: { [string]: any }): any
	local label = Text({
		Text = opts.Text or "",
		TextSize = opts.TextSize or 30,
		Font = Theme.FontHeavy,
		TextColor3 = opts.Color or Theme.Colors.Text,
		RichText = true,
		TextWrapped = false,
		AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = opts.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(260, (opts.TextSize or 30) + 8),
		ZIndex = opts.ZIndex or 30,
		Parent = opts.Parent or Components.Layer("Toasts"),
	})
	Components.Pop(label, 0.4, Theme.Tween.Pop)
	local duration = opts.Duration or 1.1
	local p = label.Position
	TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(p.X.Scale, p.X.Offset + (opts.Drift or 0), p.Y.Scale, p.Y.Offset - (opts.Rise or 60)),
	}):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	task.delay(duration * 0.55, function()
		local fade = TweenInfo.new(duration * 0.45)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
	end)
	task.delay(duration + 0.05, function()
		label:Destroy()
	end)
	return label
end

-- ===== Shiny gradient sweep (rarity cards) =====

local shines: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
RunService.Heartbeat:Connect(function()
	if lowGraphics() then
		return
	end
	local t = os.clock()
	for g, phase in pairs(shines) do
		if not g.Parent then
			shines[g] = nil
		else
			-- sweep for ~0.9s, then rest
			local cycle = (t * 0.8 + phase) % 2.6
			g.Offset = Vector2.new(math.min(cycle, 1.3) * 2 - 1.3, 0)
		end
	end
end)

-- Adds a diagonal light band that sweeps across `frame` every few seconds.
function Components.Shine(frame: GuiObject, strength: number?): any
	local sheet = New("Frame", {
		Name = "ShineSweep",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = frame.ZIndex + 3,
		Active = false,
		Parent = frame,
	})
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		New("UICorner", { CornerRadius = corner.CornerRadius, Parent = sheet })
	end
	local a = 1 - (strength or 0.45)
	local g = New("UIGradient", {
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, a),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1.3, 0),
		Parent = sheet,
	})
	shines[g] = math.random() * 2.6
	return sheet
end

-- ===== Confetti =====

local CONFETTI = {
	Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 200, 40), Color3.fromRGB(80, 220, 90),
	Color3.fromRGB(40, 180, 255), Color3.fromRGB(190, 100, 255), Color3.fromRGB(255, 120, 200),
}

-- Burst of confetti from `origin` (virtual UDim2 on the Toasts layer, default screen centre).
function Components.Confetti(colors: { Color3 }?, count: number?, origin: UDim2?)
	if lowGraphics() then
		return
	end
	local root = Components.Layer("Toasts")
	local palette = colors or CONFETTI
	local o = origin or UDim2.fromScale(0.5, 0.45)
	for i = 1, count or 60 do
		local w = math.random(10, 18)
		local piece = New("Frame", {
			BackgroundColor3 = palette[(i % #palette) + 1],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(w, math.random(16, 26)),
			Position = o,
			Rotation = math.random(0, 360),
			ZIndex = 40,
			Parent = root,
		})
		if i % 3 == 0 then
			Components.CornerScale(piece, 0.5)
		end
		local angle = math.random() * math.pi * 2
		local dist = math.random(140, 420)
		local mid = UDim2.new(o.X.Scale, o.X.Offset + math.cos(angle) * dist, o.Y.Scale, o.Y.Offset + math.sin(angle) * dist * 0.7 - 120)
		local up = TweenService:Create(piece, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = mid, Rotation = piece.Rotation + math.random(-180, 180) })
		up:Play()
		up.Completed:Connect(function()
			if not piece.Parent then
				return
			end
			local fall = TweenService:Create(piece, TweenInfo.new(math.random(14, 24) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(mid.X.Scale, mid.X.Offset + math.random(-80, 80), 1.1, 0),
				Rotation = piece.Rotation + math.random(-360, 360),
				BackgroundTransparency = 0.3,
			})
			fall:Play()
			fall.Completed:Connect(function()
				piece:Destroy()
			end)
		end)
	end
end

-- ===== Containers =====

-- opts: Color, Parent, Size, Position, AnchorPoint, LayoutOrder, Name, Corner, Stroke, StrokeThickness, Transparency
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
	Components.Gradient(card, Theme.Lighten(color, 0.12), Theme.Darken(color, 0.12))
	Components.Stroke(card, opts.Stroke or Theme.Colors.Stroke, opts.StrokeThickness or 4)
	card.Parent = opts.Parent
	return card
end

local function scrollFrame(props: { [string]: any }?): any
	local sf = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		ScrollBarImageTransparency = 0.2,
		Selectable = false,
	})
	if props then
		for k, v in pairs(props) do
			sf[k] = v
		end
	end
	New("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 16),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		Parent = sf,
	})
	return sf
end

function Components.ScrollList(parent: Instance, padding: number?, props: { [string]: any }?): any
	local sf = scrollFrame(props)
	Components.List(sf, padding or 8)
	sf.Parent = parent
	return sf
end

function Components.ScrollGrid(parent: Instance, cell: Vector2, padding: number?, props: { [string]: any }?): any
	local sf = scrollFrame(props)
	New("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(padding or 10, padding or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
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
	Components.List(bar, 10, true)
	New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6), Parent = bar })
	local obj = { Frame = bar, Buttons = {}, Current = nil }
	function obj.Select(id: string)
		obj.Current = id
		for tid, b in pairs(obj.Buttons) do
			local on = tid == id
			Components.SetColor(b, if on then Theme.Colors.Accent else Theme.Colors.WindowDark)
			local s = b:FindFirstChildOfClass("UIScale")
			if s and on then
				s.Scale = 0.9
				TweenService:Create(s, Theme.Tween.Bounce, { Scale = 1 }):Play()
			end
		end
		onSelect(id)
	end
	for i, t in ipairs(tabs) do
		local w = math.max(116, 30 + (utf8.len(t.Text) or #t.Text) * 13)
		obj.Buttons[t.Id] = Components.Button({
			Name = "Tab_" .. t.Id,
			Text = t.Text,
			TextSize = 22,
			Size = UDim2.fromOffset(w, 48),
			LayoutOrder = i,
			Color = Theme.Colors.WindowDark,
			Corner = 12,
			Parent = bar,
			OnClick = function()
				obj.Select(t.Id)
			end,
		})
	end
	bar.Parent = parent
	return obj
end

-- Progress bar. Returns { Frame, Fill, Label, Set(fraction, text?), SetColor(c) }.
function Components.ProgressBar(opts: { [string]: any }): any
	local frame = New("Frame", {
		Name = opts.Name or "Progress",
		BackgroundColor3 = Color3.fromRGB(22, 32, 72),
		Size = opts.Size or UDim2.new(1, 0, 0, 22),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
		ClipsDescendants = true,
	})
	Components.CornerScale(frame, 0.5)
	Components.Stroke(frame, Theme.Colors.Stroke, 3)
	local color = opts.Color or Theme.Colors.Good
	local fill = New("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	Components.CornerScale(fill, 0.5)
	local grad = Components.Gradient(fill, Theme.Lighten(color, 0.35), Theme.Darken(color, 0.1))
	local gloss = New("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.7,
		Size = UDim2.new(1, -8, 0.3, 0),
		Position = UDim2.new(0, 4, 0.1, 0),
		Parent = fill,
	})
	Components.CornerScale(gloss, 0.5)
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
		grad.Color = ColorSequence.new(Theme.Lighten(c, 0.35), Theme.Darken(c, 0.1))
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
	Components.Stroke(badge, Theme.Colors.Stroke, 3)
	Components.Gradient(badge, Theme.Lighten(color, 0.25), Theme.Darken(color, 0.15))
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
		g.Color = ColorSequence.new(Theme.Lighten(color, 0.25), Theme.Darken(color, 0.15))
	end
	badge.Label.Text = rarity or "?"
end

-- Currency pill: icon bubble + outlined number. Returns { Frame, Label, Icon, Set(n, suffix?) }.
function Components.CurrencyLabel(kind: string, props: { [string]: any }?): any
	local color = Theme.Colors[kind] or Theme.Colors.Coins
	local frame = New("Frame", {
		Name = kind,
		BackgroundColor3 = Theme.Colors.PillBg,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(170, 46),
	})
	Components.CornerScale(frame, 0.5)
	Components.Stroke(frame, Theme.Colors.Stroke, 4)
	local icon = New("Frame", {
		Name = "Icon",
		BackgroundColor3 = color,
		Size = UDim2.new(0, 46, 0, 46),
		Position = UDim2.fromOffset(-6, 0),
		Parent = frame,
	})
	Components.CornerScale(icon, 0.5)
	Components.Stroke(icon, Theme.Colors.Stroke, 4)
	Text({ Text = Theme.Icons[kind] or "", TextSize = 24, Outline = false, Parent = icon })
	local label = Text({
		Name = "Value",
		Text = "0",
		TextSize = 26,
		Font = Theme.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Size = UDim2.new(1, -52, 1, 0),
		Position = UDim2.fromOffset(48, 2),
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
	if lowGraphics() then
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
		Ambient = Color3.fromRGB(200, 200, 210),
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
			BackgroundTransparency = 1,
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

-- Header tab that sits on the top edge of windows / dialogs.
local function headerTab(parent: any, text: string, color: Color3, textSize: number?): any
	local tab = New("Frame", {
		Name = "TitleBar",
		BackgroundColor3 = color,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(160, 58),
		Position = UDim2.fromOffset(26, -28),
		ZIndex = 3,
		Parent = parent,
	})
	Components.Corner(tab, 16)
	Components.Gradient(tab, Theme.Lighten(color, 0.25), Theme.Darken(color, 0.1))
	Components.Stroke(tab, Theme.Colors.Stroke, 5)
	New("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = tab })
	local label = Text({
		Name = "Title",
		Text = text,
		TextSize = textSize or 36,
		Font = Theme.FontHeavy,
		Outline = 3.5,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Position = UDim2.fromOffset(0, 3),
		ZIndex = 4,
		Parent = tab,
	})
	return tab, label
end

-- Creates a registered window. Returns { Name, Frame, Body, TitleLabel, CloseButton, OnOpen, OnClose, DefaultSelection }.
-- opts: Size (Vector2), Color (body), TitleColor (header tab)
function Components.Window(name: string, title: string, icon: string?, opts: { [string]: any }?): any
	local o = opts or {}
	local root = Components.Layer("Windows")
	getBackdrop()
	local size = o.Size or Theme.WindowSize
	local color = o.Color or Theme.Colors.Window
	local accent = o.TitleColor or Theme.Colors.Accent2
	local frame = New("Frame", {
		Name = "Window_" .. name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = color,
		Visible = false,
		Active = true, -- sink clicks so they don't fall through to the closing backdrop
		ZIndex = 2,
		Parent = root,
	})
	Components.Corner(frame, 26)
	Components.Gradient(frame, Theme.Lighten(color, 0.12), Theme.Darken(color, 0.18))
	Components.Stroke(frame, Theme.Colors.Stroke, 6)
	-- coloured rim along the top, tinted with the window's accent
	local rim = New("Frame", {
		Name = "Rim",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.15,
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 2,
		Parent = frame,
	})
	Components.Corner(rim, 26)
	New("UIGradient", {
		Transparency = NumberSequence.new(0, 1),
		Rotation = 90,
		Parent = rim,
	})
	local _, titleLabel = headerTab(frame, (icon and (icon .. " ") or "") .. title, accent)
	local win: any = { Name = name, Frame = frame, OnOpen = nil, OnClose = nil, DefaultSelection = nil, IsOpen = false, TitleLabel = titleLabel }
	win.CloseButton = Components.Button({
		Name = "Close",
		Text = Theme.Icons.Close,
		TextSize = 36,
		Font = Theme.FontHeavy,
		Color = Theme.Colors.Bad,
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -10, 0, 10),
		Corner = 32,
		ZIndex = 5,
		Parent = frame,
		OnClick = function()
			Components.Close(name)
		end,
	})
	win.Body = New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 46),
		Size = UDim2.new(1, -36, 1, -62),
		ZIndex = 2,
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
	local bd = getBackdrop()
	if not bd.Visible then
		bd.Visible = true
		bd.BackgroundTransparency = 1
		TweenService:Create(bd, Theme.Tween.Fast, { BackgroundTransparency = 0.5 }):Play()
	end
	win.Frame.Visible = true
	win.Frame.Position = UDim2.fromScale(0.5, 0.6)
	TweenService:Create(win.Frame, Theme.Tween.Pop, { Position = UDim2.fromScale(0.5, 0.53) }):Play()
	Components.Pop(win.Frame, 0.6)
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
		BackgroundTransparency = 0.5,
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
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(580, height),
		BackgroundColor3 = Theme.Colors.Window,
		Parent = modal.Frame,
	})
	Components.Corner(dialog, 24)
	Components.Gradient(dialog, Theme.Lighten(Theme.Colors.Window, 0.12), Theme.Darken(Theme.Colors.Window, 0.18))
	Components.Stroke(dialog, Theme.Colors.Stroke, 6)
	headerTab(dialog, opts.Title or "Are you sure?", accent, 30)
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 44),
		Size = UDim2.new(1, -44, 1, -44 - 92),
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
		Color = Theme.Colors.Disabled,
		Size = UDim2.fromOffset(200, Theme.ButtonHeight),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -18),
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
			Size = UDim2.fromOffset(300, Theme.ButtonHeight),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -24, 1, -18),
			Parent = dialog,
		})
		attachHold(okBtn, opts.HoldSeconds, doConfirm)
	else
		okBtn = Components.Button({
			Text = opts.ConfirmText or "Confirm",
			Color = if opts.Danger then Theme.Colors.Bad else Theme.Colors.Good,
			Size = UDim2.fromOffset(300, Theme.ButtonHeight),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -24, 1, -18),
			Parent = dialog,
			OnClick = doConfirm,
		})
	end
	Components.Pop(dialog, 0.6)
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
			Position = UDim2.new(0.5, 0, 0, 96),
			Size = UDim2.fromOffset(540, 320),
			Parent = root,
		})
		Components.List(toastList, 8, false, Enum.HorizontalAlignment.Center)
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
		Size = UDim2.fromOffset(520, 50),
		LayoutOrder = toastCounter,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = list,
	})
	Components.CornerScale(toast, 0.5)
	Components.Gradient(toast, Theme.Lighten(color, 0.25), Theme.Darken(color, 0.15))
	Components.Stroke(toast, Theme.Colors.Stroke, 4)
	Components.Padding(toast, 20, 8)
	Text({
		Text = text,
		TextSize = 23,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 32),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = toast,
	})
	Components.Pop(toast, 0.4, Theme.Tween.Bounce)
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

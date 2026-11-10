-- SettingsController: music/SFX volume, low graphics, trail visibility, notifications and fuse
-- confirmation. Applied locally right away, saved with a debounced SaveSettings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent.Parent
local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local New = Components.New
local Text = Components.Text

local player = Players.LocalPlayer

local SettingsController = {}

local DEFAULTS = { Music = 0.5, Sfx = 0.8, LowGraphics = false, ShowTrails = true, Notifications = true, ConfirmFuse = true }
local SAVE_DELAY = 1.5

local settings: { [string]: any } = table.clone(DEFAULTS)
local dirtyVersion = 0
local savedVersion = 0

function SettingsController.Get(key: string): any
	local v = settings[key]
	if v == nil then
		return DEFAULTS[key]
	end
	return v
end

local function soundGroup(name: string): SoundGroup
	local g = SoundService:FindFirstChild(name)
	if g and g:IsA("SoundGroup") then
		return g
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Parent = SoundService
	return created
end

-- ===== trail visibility for other players =====
local hiddenTrails: { [Trail]: boolean } = {}
local charConns: { [Player]: { RBXScriptConnection } } = {}

local function hideTrail(t: Instance)
	if t:IsA("Trail") and t.Enabled then
		t.Enabled = false
		hiddenTrails[t] = true
	end
end

local function watchCharacter(plr: Player, char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if not settings.ShowTrails then
			hideTrail(d)
		end
	end
	local conns = charConns[plr] or {}
	charConns[plr] = conns
	table.insert(conns, char.DescendantAdded:Connect(function(d)
		if not settings.ShowTrails then
			task.defer(hideTrail, d) -- after the server script finishes setting it up
		end
	end))
end

local function applyTrails()
	if settings.ShowTrails then
		for t in pairs(hiddenTrails) do
			if t.Parent then
				t.Enabled = true
			end
		end
		table.clear(hiddenTrails)
	else
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player and plr.Character then
				for _, d in ipairs(plr.Character:GetDescendants()) do
					hideTrail(d)
				end
			end
		end
	end
end

local function apply()
	player:SetAttribute("LowGraphics", settings.LowGraphics == true)
	soundGroup("Music").Volume = math.clamp(tonumber(settings.Music) or DEFAULTS.Music, 0, 1)
	soundGroup("SFX").Volume = math.clamp(tonumber(settings.Sfx) or DEFAULTS.Sfx, 0, 1)
	applyTrails()
end

local function changed(key: string, value: any)
	settings[key] = value
	apply()
	ClientData.SetLocal("Settings", table.clone(settings))
	dirtyVersion += 1
	local myVersion = dirtyVersion
	task.delay(SAVE_DELAY, function()
		if myVersion == dirtyVersion then
			savedVersion = myVersion
			Net.Event("SaveSettings"):FireServer(table.clone(settings))
		end
	end)
end

local function slider(parent, order: number, label: string, key: string): () -> ()
	local row = Components.Card({ Color = Theme.Colors.Panel, Size = UDim2.new(1, 0, 0, 76), LayoutOrder = order, Parent = parent })
	Text({ Text = label, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(190, 76), Position = UDim2.fromOffset(16, 0), Parent = row })
	local track = New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Theme.Colors.WindowDark,
		Position = UDim2.new(0, 220, 0.5, -10),
		Size = UDim2.new(1, -460, 0, 20),
		Parent = row,
	})
	Components.CornerScale(track, 0.5)
	Components.Stroke(track, Theme.Colors.Stroke, 2)
	local fill = New("Frame", { BackgroundColor3 = Theme.Colors.Accent, Size = UDim2.fromScale(0.5, 1), Parent = track })
	Components.CornerScale(fill, 0.5)
	local knob = New("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = 2,
		Parent = track,
	})
	Components.CornerScale(knob, 0.5)
	Components.Stroke(knob, Theme.Colors.Stroke, 3)
	local valueLabel = Text({ Text = "", TextSize = 20, AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(60, 76), Position = UDim2.new(1, -170, 0, 0), Parent = row })

	local function render()
		local v = math.clamp(tonumber(settings[key]) or 0, 0, 1)
		fill.Size = UDim2.fromScale(v, 1)
		knob.Position = UDim2.fromScale(v, 0.5)
		valueLabel.Text = ("%d%%"):format(math.floor(v * 100 + 0.5))
	end
	local function set(v: number)
		v = math.floor(math.clamp(v, 0, 1) * 20 + 0.5) / 20
		if v ~= settings[key] then
			changed(key, v)
		end
		render()
	end
	-- -/+ buttons keep the slider usable with a gamepad
	Components.Button({
		Text = "−",
		TextSize = 30,
		Color = Theme.Colors.PanelLight,
		Size = UDim2.fromOffset(64, 56),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -86, 0.5, 0),
		Parent = row,
		OnClick = function()
			set((tonumber(settings[key]) or 0) - 0.1)
		end,
	})
	Components.Button({
		Text = "+",
		TextSize = 30,
		Color = Theme.Colors.PanelLight,
		Size = UDim2.fromOffset(64, 56),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Parent = row,
		OnClick = function()
			set((tonumber(settings[key]) or 0) + 0.1)
		end,
	})
	local dragging = false
	local function fromInput(pos: Vector3)
		local x = (pos.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
		set(x)
	end
	track.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true
			fromInput(input.Position)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return render
end

local function toggle(parent, order: number, label: string, hint: string, key: string): () -> ()
	local row = Components.Card({ Color = Theme.Colors.Panel, Size = UDim2.new(1, 0, 0, 76), LayoutOrder = order, Parent = parent })
	Text({ Text = label, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -220, 0, 34), Position = UDim2.fromOffset(16, 6), Parent = row })
	Text({
		Text = hint,
		TextSize = 15,
		Font = Theme.FontBody,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -220, 0, 26),
		Position = UDim2.fromOffset(16, 40),
		Parent = row,
	})
	local btn = Components.Button({
		Text = "",
		TextSize = 22,
		Size = UDim2.fromOffset(150, 56),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Parent = row,
	})
	local function render()
		local on = settings[key] == true
		Components.SetText(btn, if on then "ON" else "OFF")
		Components.SetColor(btn, if on then Theme.Colors.Good else Theme.Colors.Bad)
	end
	Components.SetOnClick(btn, function()
		changed(key, not (settings[key] == true))
		render()
	end)
	return render
end

function SettingsController.Start()
	local win = Components.Window("Settings", "Settings", Theme.Icons.Settings, { TitleColor = Color3.fromRGB(110, 110, 150) })
	local list = Components.ScrollList(win.Body, 8)
	local renders = {
		slider(list, 1, "🎵 Music", "Music"),
		slider(list, 2, "🔊 Sound FX", "Sfx"),
		toggle(list, 3, "🪶 Low graphics", "Fewer particles and effects for older devices", "LowGraphics"),
		toggle(list, 4, "✨ Show trails", "Show other raiders' trails", "ShowTrails"),
		toggle(list, 5, "🔔 Notifications", "Pop-up messages (warnings always show)", "Notifications"),
		toggle(list, 6, "🔮 Confirm fuse", "Ask before every fusion (valuable fusions always ask)", "ConfirmFuse"),
	}
	local function renderAll()
		for _, r in ipairs(renders) do
			r()
		end
	end

	local function adopt(serverSettings)
		if type(serverSettings) ~= "table" or dirtyVersion ~= savedVersion then
			return -- a local change is still waiting to be saved
		end
		for k, def in pairs(DEFAULTS) do
			local v = serverSettings[k]
			settings[k] = if v == nil then def else v
		end
		apply()
		renderAll()
	end

	adopt(ClientData.Get().Settings)
	ClientData.Changed:Connect(function(keys)
		if keys.Settings and dirtyVersion == savedVersion then
			adopt(ClientData.Get().Settings)
		end
	end)

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			if plr.Character then
				watchCharacter(plr, plr.Character)
			end
			plr.CharacterAdded:Connect(function(c)
				watchCharacter(plr, c)
			end)
		end
	end
	Players.PlayerAdded:Connect(function(plr)
		plr.CharacterAdded:Connect(function(c)
			watchCharacter(plr, c)
		end)
	end)
	Players.PlayerRemoving:Connect(function(plr)
		for _, c in ipairs(charConns[plr] or {}) do
			c:Disconnect()
		end
		charConns[plr] = nil
	end)

	win.OnOpen = renderAll
	apply()
	renderAll()
end

return SettingsController

-- HUDController: always-on HUD — currencies, Speed, income, biome indicator, carried egg,
-- incubator timers with speed-up buttons, new-player shield, event banner and the side menu.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent.Parent
local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local New = Components.New
local Text = Components.Text
local Economy = GameConfig.Economy
local Progression = GameConfig.Progression

local player = Players.LocalPlayer

local HUDController = {}

local MENU = {
	{ Window = "Shop", Icon = Theme.Icons.Shop, Label = "Shop", Color = Color3.fromRGB(255, 170, 40) },
	{ Window = "Pets", Icon = Theme.Icons.Pets, Label = "Pets", Color = Color3.fromRGB(80, 200, 120) },
	{ Window = "Index", Icon = Theme.Icons.Index, Label = "Index", Color = Color3.fromRGB(70, 160, 255) },
	{ Window = "Fuse", Icon = Theme.Icons.Fuse, Label = "Fuse", Color = Color3.fromRGB(190, 90, 255) },
	{ Window = "Daily", Icon = Theme.Icons.Daily, Label = "Rewards", Color = Color3.fromRGB(255, 90, 140) },
	{ Window = "Leaderboards", Icon = Theme.Icons.Leaderboard, Label = "Ranks", Color = Color3.fromRGB(255, 210, 60) },
	{ Window = "Rebirth", Icon = Theme.Icons.Rebirth, Label = "Rebirth", Color = Color3.fromRGB(0, 220, 170) },
	{ Window = "Settings", Icon = Theme.Icons.Settings, Label = "Settings", Color = Color3.fromRGB(140, 140, 170) },
}

local function attr(name: string, fallback: any): any
	local v = player:GetAttribute(name)
	if v == nil then
		return fallback
	end
	return v
end

local function derived(): { [string]: any }
	return ClientData.Get().Derived or {}
end

local function coins(): number
	return attr("Coins", ClientData.Get().Coins or 0)
end

local function shards(): number
	return attr("Shards", ClientData.Get().Shards or 0)
end

local function effectiveSpeed(): number
	return attr("EffectiveSpeed", derived().EffectiveSpeed or 0)
end

local function bestBiome(profile): any
	local best = GameConfig.Biomes[1]
	for _, b in ipairs(GameConfig.Biomes) do
		if profile.Biomes and profile.Biomes[b.Id] and b.Index > best.Index then
			best = b
		end
	end
	return best
end

-- Display-only copies of the server's speed-up prices (the server charges the real amount).
function HUDController.SpeedUpCost(egg, remaining: number, currency: string): number
	if currency == "Shards" then
		return math.max(1, math.ceil(remaining / Economy.SpeedUpSecondsPerShard))
	end
	local biome = GameConfig.GetBiome(egg.Biome) or bestBiome(ClientData.Get())
	return math.max(1, math.ceil(remaining * Economy.SpeedUpCoinsPerSecond * biome.IncomeBase))
end

-- Daily reward or a finished quest waiting to be claimed.
function HUDController.HasClaimable(): boolean
	local p = ClientData.Get()
	local now = Components.Now()
	local daily = p.Daily or {}
	if now - (daily.LastClaim or 0) >= Progression.Daily.ClaimCooldown then
		return true
	end
	local quests = p.Quests or {}
	for kind, defs in pairs({ Daily = Progression.DailyQuests, Weekly = Progression.WeeklyQuests }) do
		local q = quests[kind]
		for _, entry in ipairs(q and q.List or {}) do
			if not entry.Claimed then
				for _, def in ipairs(defs) do
					if def.Id == entry.Id and (entry.Progress or 0) >= def.Goal then
						return true
					end
				end
			end
		end
	end
	return false
end

local function pill(parent, size: Vector2, color: Color3, props): any
	local f = New("Frame", {
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(size.X, size.Y),
	})
	Components.CornerScale(f, 0.5)
	Components.Gradient(f, Theme.Lighten(color, 0.1), Theme.Darken(color, 0.3))
	Components.Stroke(f, Theme.Colors.Stroke, 3)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

function HUDController.Start()
	local root = Components.Layer("HUD")

	-- ===== Top bar =====
	local top = New("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(800, 50),
		Parent = root,
	})
	Components.List(top, 18, true, Enum.HorizontalAlignment.Center)
	local coinLabel = Components.CurrencyLabel("Coins", { LayoutOrder = 1, Size = UDim2.fromOffset(180, 46), Parent = top })
	local shardLabel = Components.CurrencyLabel("Shards", { LayoutOrder = 2, Size = UDim2.fromOffset(130, 46), Parent = top })
	local speedLabel = Components.CurrencyLabel("Speed", { LayoutOrder = 3, Size = UDim2.fromOffset(230, 46), Parent = top })
	speedLabel.Label.RichText = true
	local incomeLabel = Components.CurrencyLabel("Income", { LayoutOrder = 4, Size = UDim2.fromOffset(170, 46), Parent = top })

	local function refreshTop()
		coinLabel.Set(coins())
		shardLabel.Set(shards())
		incomeLabel.Set(attr("Income", derived().Income or 0), "/s")
		local eff = effectiveSpeed()
		local stat = attr("SpeedStat", ClientData.Get().SpeedStat or 0)
		speedLabel.Label.Text = GameConfig.FormatNumber(eff)
			.. ' <font size="15" color="#C8C3EB">trained '
			.. GameConfig.FormatNumber(stat)
			.. "</font>"
	end

	-- ===== Biome indicator =====
	local biomePill = pill(root, Vector2.new(520, 34), Theme.Colors.WindowDark, {
		Name = "Biome",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
	})
	local biomeText = Text({ Text = "", TextScaled = true, RichText = true, Size = UDim2.new(1, -20, 1, -6), Position = UDim2.fromOffset(10, 3), Parent = biomePill })
	New("UITextSizeConstraint", { MaxTextSize = 19, Parent = biomeText })

	local function hexOf(c: Color3): string
		return "#" .. c:ToHex()
	end

	local function refreshBiome()
		local idx = attr("BiomeIndex", 0)
		local eff = effectiveSpeed()
		local profile = ClientData.Get()
		local b = if idx > 0 then GameConfig.GetBiomeByIndex(idx) else nil
		if not b then
			-- in the hub: point at the next biome the player cannot enter yet
			local nextB = nil
			for _, biome in ipairs(GameConfig.Biomes) do
				if not (profile.Biomes and profile.Biomes[biome.Id]) or eff < biome.RequiredSpeed then
					nextB = biome
					break
				end
			end
			biomePill.BackgroundColor3 = Theme.Colors.WindowDark
			if nextB then
				local col = if eff >= nextB.RequiredSpeed then Theme.Colors.Good else Theme.Colors.Warn
				biomeText.Text = ('🏠 Safe zone  ·  next: <b>%s</b> <font color="%s">⚡ %s / %s</font>'):format(
					nextB.Name,
					hexOf(col),
					GameConfig.FormatNumber(eff),
					GameConfig.FormatNumber(nextB.RequiredSpeed)
				)
			else
				biomeText.Text = "🏠 Safe zone  ·  every rift is open to you!"
			end
			return
		end
		local col
		if eff < b.RequiredSpeed then
			col = Theme.Colors.Bad
		elseif eff < b.RecommendedSpeed then
			col = Theme.Colors.Warn
		else
			col = Theme.Colors.Good
		end
		biomePill.BackgroundColor3 = Theme.Darken(col, 0.55)
		biomeText.Text = ('📍 <b>%s</b> (%s)  <font color="%s">⚡ %s</font> · need %s · safe %s'):format(
			b.Name,
			b.Kind,
			hexOf(col),
			GameConfig.FormatNumber(eff),
			GameConfig.FormatNumber(b.RequiredSpeed),
			GameConfig.FormatNumber(b.RecommendedSpeed)
		)
	end

	-- ===== Carried egg =====
	local carry = pill(root, Vector2.new(520, 62), Theme.Colors.WindowDark, {
		Name = "Carry",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Visible = false,
	})
	local carryStroke = carry:FindFirstChildOfClass("UIStroke")
	local carryName = Text({ Text = "", TextSize = 20, RichText = true, Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 4), Parent = carry })
	local runText = Text({
		Text = "RUN HOME!",
		TextSize = 28,
		Font = Theme.FontHeavy,
		TextColor3 = Theme.Colors.Warn,
		Outline = 3,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 28),
		Parent = carry,
	})
	local runScale = New("UIScale", { Parent = runText })
	local pulse = TweenService:Create(runScale, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 })

	local function refreshCarry()
		local egg = attr("CarryingEgg", "")
		if egg == "" then
			if carry.Visible then
				carry.Visible = false
				pulse:Cancel()
				runScale.Scale = 1
			end
			return
		end
		local rarity = attr("CarryingRarity", "")
		local color = Theme.Rarity(rarity)
		carryName.Text = ('🥚 <font color="#%s">%s</font>'):format(color:ToHex(), egg)
		if carryStroke then
			carryStroke.Color = color
			carryStroke.Thickness = 4
		end
		if not carry.Visible then
			carry.Visible = true
			Components.Pop(carry, 0.5)
			pulse:Play()
		end
	end

	-- ===== Top-right: event banner + shield =====
	local rightTop = New("Frame", {
		Name = "RightTop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 62),
		Size = UDim2.fromOffset(240, 100),
		Parent = root,
	})
	Components.List(rightTop, 6, false, Enum.HorizontalAlignment.Right)
	local eventPill = pill(rightTop, Vector2.new(230, 44), Theme.Colors.Accent, { Name = "Event", LayoutOrder = 1, Visible = false })
	local eventText = Text({ Text = "", TextSize = 19, RichText = true, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), Parent = eventPill })
	local shieldPill = pill(rightTop, Vector2.new(230, 38), Theme.Colors.Info, { Name = "Shield", LayoutOrder = 2, Visible = false })
	local shieldText = Text({ Text = "", TextSize = 18, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), Parent = shieldPill })

	local function refreshTimers()
		local now = Components.Now()
		local ev = derived().ActiveEvent
		if ev and ev.Id and (ev.EndsAt or 0) > now then
			local cfg = Progression.Events[ev.Id]
			local color = cfg and cfg.Color or Theme.Colors.Accent
			eventPill.BackgroundColor3 = color
			eventText.Text = ("%s <b>%s</b>  %s"):format(Theme.Icons.Event, ev.Name or (cfg and cfg.Name) or ev.Id, GameConfig.FormatTime(ev.EndsAt - now))
			if not eventPill.Visible then
				eventPill.Visible = true
				Components.Pop(eventPill, 0.5)
			end
		else
			eventPill.Visible = false
		end
		local shieldUntil = attr("ShieldUntil", derived().ShieldUntil or 0)
		if shieldUntil > now then
			shieldPill.Visible = true
			shieldText.Text = ("%s Egg shield  %s"):format(Theme.Icons.Shield, GameConfig.FormatTime(shieldUntil - now))
		else
			shieldPill.Visible = false
		end
	end

	-- ===== Incubators =====
	local incPanel = Components.Card({
		Name = "Incubators",
		Color = Theme.Colors.WindowDark,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 172),
		Size = UDim2.fromOffset(310, 50),
		Parent = root,
	})
	incPanel.AutomaticSize = Enum.AutomaticSize.Y
	incPanel.BackgroundTransparency = 0.15
	Components.Padding(incPanel, 8)
	Components.List(incPanel, 6)
	local isTouch = Components.Device() == "Touch"
	local collapsed = isTouch -- keep the right side clear for the touch action buttons
	local header = Components.Button({
		Name = "Header",
		Text = "🥚 Incubators",
		TextSize = 20,
		Color = Theme.Colors.Panel,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 0,
		Parent = incPanel,
	})
	local rows: { any } = {}

	local function buildRows(count: number)
		for _, r in ipairs(rows) do
			r.Frame:Destroy()
		end
		rows = {}
		for pad = 1, count do
			local frame = New("Frame", {
				Name = "Pad" .. pad,
				BackgroundColor3 = Theme.Colors.Panel,
				Size = UDim2.new(1, 0, 0, 100),
				LayoutOrder = pad,
				Visible = not collapsed,
				Parent = incPanel,
			})
			Components.Corner(frame, 12)
			Components.Stroke(frame, Theme.Colors.Stroke, 2)
			local name = Text({
				Text = "",
				TextSize = 17,
				RichText = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, -16, 0, 22),
				Position = UDim2.fromOffset(8, 3),
				Parent = frame,
			})
			local bar = Components.ProgressBar({ Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 26), Parent = frame })
			local coinBtn = Components.Button({
				Text = "",
				TextSize = 17,
				Color = Theme.Colors.Coins,
				TextColor = Theme.Colors.TextDark,
				Size = UDim2.new(0.5, -12, 0, 44),
				Position = UDim2.fromOffset(8, 51),
				Corner = 10,
				Parent = frame,
			})
			local shardBtn = Components.Button({
				Text = "",
				TextSize = 17,
				Color = Theme.Colors.Shards,
				TextColor = Theme.Colors.TextDark,
				Size = UDim2.new(0.5, -12, 0, 44),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 51),
				Corner = 10,
				Parent = frame,
			})
			coinBtn.Label.TextColor3 = Theme.Colors.TextDark
			shardBtn.Label.TextColor3 = Theme.Colors.TextDark
			Components.SetOnClick(coinBtn, function()
				Net.Event("SpeedUpHatch"):FireServer(pad, "Coins")
			end)
			Components.SetOnClick(shardBtn, function()
				Net.Event("SpeedUpHatch"):FireServer(pad, "Shards")
			end)
			table.insert(rows, { Frame = frame, Name = name, Bar = bar, Coin = coinBtn, Shard = shardBtn })
		end
	end

	Components.SetOnClick(header, function()
		collapsed = not collapsed
		for _, r in ipairs(rows) do
			r.Frame.Visible = not collapsed
		end
		Components.SetText(header, if collapsed then "🥚 Incubators ▸" else "🥚 Incubators")
	end)

	local function refreshIncubators()
		local profile = ClientData.Get()
		local pads = math.max(1, derived().Pads or 1)
		if #rows ~= pads then
			buildRows(pads)
		end
		local now = Components.Now()
		local busy = 0
		local incubators = profile.Incubators or {}
		for pad, row in ipairs(rows) do
			local egg = incubators[tostring(pad)] or incubators[pad]
			if not egg then
				row.Name.Text = ("Pad %d · <i>empty — bring an egg!</i>"):format(pad)
				row.Bar.Set(0, "")
				row.Coin.Visible = false
				row.Shard.Visible = false
				row.Frame.Size = UDim2.new(1, 0, 0, 52)
			else
				busy += 1
				local color = Theme.Rarity(egg.Rarity)
				row.Name.Text = ('<font color="#%s">%s</font>'):format(color:ToHex(), GameConfig.EggDisplayName(egg))
				row.Bar.SetColor(color)
				row.Frame.Size = UDim2.new(1, 0, 0, 100)
				local hatchAt = egg.HatchAt
				if not hatchAt then
					row.Bar.Set(0, "waiting for a free pad")
					row.Coin.Visible = false
					row.Shard.Visible = false
				else
					local remaining = hatchAt - now
					local duration = egg.Duration or GameConfig.HatchDuration(egg.Rarity, egg.Size, profile.IncubatorLevel or 1)
					if remaining <= 0 then
						row.Bar.Set(1, "Hatching...")
						row.Coin.Visible = false
						row.Shard.Visible = false
					else
						row.Bar.Set(1 - remaining / math.max(duration, 1), GameConfig.FormatTime(remaining))
						local cc = HUDController.SpeedUpCost(egg, remaining, "Coins")
						local sc = HUDController.SpeedUpCost(egg, remaining, "Shards")
						row.Coin.Visible = true
						row.Shard.Visible = true
						Components.SetText(row.Coin, "⏩ " .. Components.Price("Coins", cc))
						Components.SetText(row.Shard, "⏩ " .. Components.Price("Shards", sc))
						Components.SetEnabled(row.Coin, coins() >= cc)
						Components.SetEnabled(row.Shard, shards() >= sc)
					end
				end
			end
		end
		Components.SetText(header, ("🥚 Incubators %d/%d%s"):format(busy, #rows, if collapsed then " ▸" else ""))
	end

	-- ===== Side menu =====
	local menu = New("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		-- touch: pinned high so it never sits under the thumbstick
		AnchorPoint = if isTouch then Vector2.zero else Vector2.new(0, 0.5),
		Position = if isTouch then UDim2.fromOffset(10, 58) else UDim2.new(0, 10, 0.5, 10),
		Size = UDim2.fromOffset(172, 4 * 88),
		Parent = root,
	})
	New("UIGridLayout", {
		CellSize = if isTouch then UDim2.fromOffset(72, 72) else UDim2.fromOffset(80, 80),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = menu,
	})
	local menuButtons = {}
	local dailyDot
	for i, m in ipairs(MENU) do
		local b = Components.Button({
			Name = "Menu_" .. m.Window,
			Text = ('<font size="34">%s</font>\n<font size="15">%s</font>'):format(m.Icon, m.Label),
			Color = m.Color,
			LayoutOrder = i,
			Corner = 20,
			Parent = menu,
			OnClick = function()
				Components.Toggle(m.Window)
			end,
		})
		b.Label.TextWrapped = false
		b.Label.LineHeight = 0.95
		menuButtons[m.Window] = b
		if m.Window == "Daily" then
			dailyDot = New("Frame", {
				Name = "Dot",
				BackgroundColor3 = Theme.Colors.Bad,
				Size = UDim2.fromOffset(22, 22),
				Position = UDim2.new(1, -16, 0, -6),
				ZIndex = 5,
				Visible = false,
				Parent = b,
			})
			Components.CornerScale(dailyDot, 0.5)
			Components.Stroke(dailyDot, Theme.Colors.Stroke, 2)
			Text({ Text = "!", TextSize = 16, ZIndex = 6, Parent = dailyDot })
		end
	end
	HUDController.MenuButtons = menuButtons

	-- Gamepad: D-pad left jumps into the side menu when no window is open.
	ContextActionService:BindAction("RR_FocusMenu", function(_, state)
		if state ~= Enum.UserInputState.Begin or Components.CurrentWindow or GuiService.SelectedObject then
			return Enum.ContextActionResult.Pass
		end
		GuiService.SelectedObject = menuButtons.Shop
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.DPadLeft)

	-- ===== Wiring =====
	for _, a in ipairs({ "Coins", "Shards", "SpeedStat", "EffectiveSpeed", "Income" }) do
		player:GetAttributeChangedSignal(a):Connect(function()
			refreshTop()
			refreshBiome()
		end)
	end
	player:GetAttributeChangedSignal("BiomeIndex"):Connect(refreshBiome)
	player:GetAttributeChangedSignal("CarryingEgg"):Connect(refreshCarry)
	player:GetAttributeChangedSignal("CarryingRarity"):Connect(refreshCarry)

	ClientData.Observe({ "Coins", "Shards", "SpeedStat", "Derived", "Biomes" }, function()
		refreshTop()
		refreshBiome()
	end)
	ClientData.Observe({ "Incubators", "Derived", "IncubatorLevel" }, refreshIncubators)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		refreshTimers()
		refreshIncubators()
		if dailyDot then
			dailyDot.Visible = HUDController.HasClaimable()
		end
	end)

	refreshTop()
	refreshBiome()
	refreshCarry()
	refreshTimers()
	refreshIncubators()
end

return HUDController

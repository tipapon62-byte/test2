-- HUDController: the always-on HUD, laid out like a classic Roblox simulator so the 3D world stays
-- visible: chunky menu buttons on the left, big outlined currency numbers bottom-left, icon buttons
-- on the right, a "Hatching" chip, event / shield / training / speed-lane pills, a pulsing carried-
-- egg banner and a big biome title toast.
--
-- Desktop / console: menu column mid-left, currencies bottom-left, icons mid-right,
--                    event + shield bottom-right, hatching chip top-right.
-- Touch:             currencies top-left, menu as a 2-column grid under them (clear of the
--                    thumbstick), icons in a row top-right with the hatching chip and pills
--                    stacked below (clear of the jump / action buttons).

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
local Fmt = GameConfig.FormatNumber
local Economy = GameConfig.Economy
local Progression = GameConfig.Progression

local player = Players.LocalPlayer

local HUDController = {}

local MENU = {
	{ Window = "Shop", Icon = Theme.Icons.Shop, Label = "Shop", Color = Theme.Buttons.Shop },
	{ Window = "Pets", Icon = Theme.Icons.Pets, Label = "Pets", Color = Theme.Buttons.Pets },
	{ Window = "Index", Icon = Theme.Icons.Index, Label = "Index", Color = Theme.Buttons.Index },
	{ Window = "Fuse", Icon = Theme.Icons.Fuse, Label = "Fuse", Color = Theme.Buttons.Fuse },
	{ Window = "Daily", Icon = Theme.Icons.Daily, Label = "Quests", Color = Theme.Buttons.Quests },
}

local SIDE = {
	{ Window = "Leaderboards", Icon = Theme.Icons.Leaderboard, Caption = "Ranks", Color = Theme.Buttons.Ranks },
	{ Window = "Rebirth", Icon = Theme.Icons.Rebirth, Caption = "Rebirth", Color = Theme.Buttons.Rebirth },
	{ Window = "Settings", Icon = Theme.Icons.Settings, Caption = "Settings", Color = Theme.Buttons.Settings },
}

local UPGRADE_TRACKS = {
	{ Key = "BaseLevel", Track = Economy.BaseLevels },
	{ Key = "TreadmillLevel", Track = Economy.TreadmillLevels },
	{ Key = "IncubatorLevel", Track = Economy.IncubatorLevels },
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

local function hex(c: Color3): string
	return "#" .. c:ToHex()
end

local function countKeys(t: any): number
	local n = 0
	if type(t) == "table" then
		for _ in pairs(t) do
			n += 1
		end
	end
	return n
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

-- Any shop upgrade the player can afford right now.
function HUDController.CanAffordUpgrade(): boolean
	local p = ClientData.Get()
	local c = coins()
	for _, u in ipairs(UPGRADE_TRACKS) do
		local lvl = math.clamp(p[u.Key] or 1, 1, #u.Track)
		local nxt = u.Track[lvl + 1]
		if nxt and (nxt.Price or math.huge) <= c then
			return true
		end
	end
	return false
end

-- Hatching eggs (profile.Incubators keyed by enclosure slot number string), sorted by slot.
local function hatchingList(): { any }
	local list = {}
	for key, egg in pairs(ClientData.Get().Incubators or {}) do
		if type(egg) == "table" then
			table.insert(list, { Slot = tonumber(key) or 0, Key = tostring(key), Egg = egg })
		end
	end
	table.sort(list, function(a, b)
		return a.Slot < b.Slot
	end)
	return list
end

local function onOwnTreadmill(): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local baseName = player:GetAttribute("BaseName")
	local bases = workspace:FindFirstChild("Bases")
	local base = type(baseName) == "string" and bases and bases:FindFirstChild(baseName)
	if not (char and root and base) then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
	local inst: Instance? = hit and hit.Instance
	while inst and inst ~= base do
		if inst.Name == "Treadmill" then
			return true
		end
		inst = inst.Parent
	end
	return false
end

function HUDController.Start()
	local root = Components.Layer("HUD")
	local device = Components.Device()
	local isTouch = device == "Touch"
	local M = if device == "Console" then 28 else 12 -- console: stay inside the TV safe area

	-- ===== Currencies =====
	local wallet = New("Frame", {
		Name = "Wallet",
		BackgroundTransparency = 1,
		AnchorPoint = if isTouch then Vector2.zero else Vector2.new(0, 1),
		Position = if isTouch then UDim2.fromOffset(M, 4) else UDim2.new(0, M, 1, -M),
		Size = UDim2.fromOffset(360, if isTouch then 118 else 160),
		Parent = root,
	})
	local walletList = Components.List(wallet, if isTouch then 0 else 2)
	walletList.VerticalAlignment = if isTouch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
	local big = if isTouch then 34 else 46
	local speedNum = Components.BigNumber({ Name = "Speed", Icon = Theme.Icons.Speed, Color = Theme.Colors.Speed, TextSize = big, LayoutOrder = 1, Parent = wallet })
	local coinNum = Components.BigNumber({ Name = "Coins", Icon = Theme.Icons.Coins, Color = Theme.Colors.Coins, TextSize = big, LayoutOrder = 2, Parent = wallet })
	local subRow = New("Frame", { Name = "Sub", BackgroundTransparency = 1, Size = UDim2.fromOffset(360, if isTouch then 28 else 36), LayoutOrder = 3, Parent = wallet })
	Components.List(subRow, 14, true)
	local shardNum = Components.BigNumber({ Name = "Shards", Icon = Theme.Icons.Shards, Color = Theme.Colors.Shards, TextSize = if isTouch then 22 else 28, LayoutOrder = 1, Parent = subRow })
	local incomeLabel = Text({
		Name = "Income",
		Text = "",
		TextSize = if isTouch then 18 else 22,
		TextColor3 = Theme.Colors.Income,
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 2,
		Parent = subRow,
	})
	Components.Anchors.Coins = coinNum.Frame
	Components.Anchors.Speed = speedNum.Frame

	local lastCoins: number? = nil
	local function refreshWallet()
		local c = coins()
		speedNum.Set(effectiveSpeed())
		coinNum.Set(c)
		shardNum.Set(shards())
		incomeLabel.Text = "+" .. Fmt(attr("Income", derived().Income or 0)) .. "/s"
		if lastCoins and c > lastCoins and not Components.LowGraphics() then
			local f = coinNum.Frame
			local at = Components.ToLayer(root, f.AbsolutePosition + Vector2.new(f.AbsoluteSize.X + 10, f.AbsoluteSize.Y * 0.5))
			Components.FloatText({
				Text = "+" .. Fmt(c - lastCoins),
				Color = Theme.Colors.Coins,
				TextSize = if isTouch then 24 else 30,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = at,
				Rise = 46,
				Drift = 20,
				Parent = root,
			})
		end
		lastCoins = c
	end

	-- ===== Left menu =====
	local menu = New("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = if isTouch then Vector2.zero else Vector2.new(0, 0.5),
		Position = if isTouch then UDim2.fromOffset(M, 4 + 118 + 8) else UDim2.new(0, M, 0.4, 0),
		Size = if isTouch then UDim2.fromOffset(240, 200) else UDim2.fromOffset(214, #MENU * 72),
		Parent = root,
	})
	if isTouch then
		New("UIGridLayout", {
			CellSize = UDim2.fromOffset(114, 58),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = menu,
		})
	else
		Components.List(menu, 12)
	end
	local menuButtons, badges = {}, {}
	for i, m in ipairs(MENU) do
		local b = Components.Button({
			Name = "Menu_" .. m.Window,
			Icon = m.Icon,
			Text = m.Label,
			TextSize = if isTouch then 22 else 30,
			IconScale = if isTouch then 0.6 else 0.66,
			Color = m.Color,
			Size = if isTouch then UDim2.fromOffset(114, 58) else UDim2.fromOffset(204, 60),
			LayoutOrder = i,
			Parent = menu,
			OnClick = function()
				Components.Toggle(m.Window)
			end,
		})
		menuButtons[m.Window] = b
		badges[m.Window] = Components.Badge(b)
	end

	-- ===== Right icon buttons =====
	local side = New("Frame", {
		Name = "Side",
		BackgroundTransparency = 1,
		AnchorPoint = if isTouch then Vector2.new(1, 0) else Vector2.new(1, 0.5),
		Position = if isTouch then UDim2.new(1, -M, 0, 6) else UDim2.new(1, -M, 0.46, 0),
		Size = if isTouch then UDim2.fromOffset(#SIDE * 74, 66) else UDim2.fromOffset(80, #SIDE * 94),
		Parent = root,
	})
	local sideList = Components.List(side, if isTouch then 10 else 18, isTouch, Enum.HorizontalAlignment.Right)
	sideList.VerticalAlignment = Enum.VerticalAlignment.Center
	for i, s in ipairs(SIDE) do
		local b = Components.IconButton({
			Name = "Side_" .. s.Window,
			Icon = s.Icon,
			Caption = if isTouch then nil else s.Caption,
			Color = s.Color,
			Size = if isTouch then 62 else 76,
			LayoutOrder = i,
			Parent = side,
			OnClick = function()
				Components.Toggle(s.Window)
			end,
		})
		menuButtons[s.Window] = b
		badges[s.Window] = Components.Badge(b)
	end
	HUDController.MenuButtons = menuButtons

	-- ===== Right column: hatching chip (+ list), and on touch the status pills =====
	local rightCol = New("Frame", {
		Name = "RightCol",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = if isTouch then UDim2.new(1, -M, 0, 6 + 66 + 12) else UDim2.new(1, -M, 0, M),
		Size = UDim2.fromOffset(340, 400),
		Parent = root,
	})
	Components.List(rightCol, 8, false, Enum.HorizontalAlignment.Right)

	local hatchChip = Components.Button({
		Name = "Hatching",
		Icon = Theme.Icons.Hatch,
		Text = "Hatching", -- non-empty so the icon is laid out on the left
		TextSize = 22,
		IconScale = 0.7,
		Color = Theme.Buttons.Hatch,
		Size = UDim2.fromOffset(236, 56),
		LayoutOrder = 1,
		Parent = rightCol,
	})
	hatchChip.Visible = false
	local hatchList = New("Frame", {
		Name = "HatchList",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(330, 0),
		LayoutOrder = 2,
		Visible = false,
		ZIndex = 5,
		Parent = rightCol,
	})
	Components.List(hatchList, 6, false, Enum.HorizontalAlignment.Right)
	local expanded = false
	Components.SetOnClick(hatchChip, function()
		expanded = not expanded
		hatchList.Visible = expanded
		if expanded then
			Components.Pop(hatchList, 0.7)
		end
	end)

	local hatchRows: { [string]: any } = {}
	local function makeHatchRow(key: string, slot: number): any
		local card = Components.Card({ Name = "Slot" .. key, Color = Theme.Colors.WindowDark, Size = UDim2.fromOffset(330, 104), Parent = hatchList })
		card.LayoutOrder = slot
		local name = Text({
			Text = "",
			TextSize = 19,
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Size = UDim2.new(1, -20, 0, 24),
			Position = UDim2.fromOffset(10, 5),
			Parent = card,
		})
		local bar = Components.ProgressBar({ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 30), TextSize = 16, Parent = card })
		local coinBtn = Components.Button({
			Text = "",
			TextSize = 18,
			Color = Theme.Colors.Coins,
			Size = UDim2.new(0.5, -14, 0, 44),
			Position = UDim2.fromOffset(10, 56),
			Corner = 12,
			Parent = card,
			OnClick = function()
				Net.Event("SpeedUpHatch"):FireServer(slot, "Coins")
			end,
		})
		local shardBtn = Components.Button({
			Text = "",
			TextSize = 18,
			Color = Theme.Colors.Shards,
			Size = UDim2.new(0.5, -14, 0, 44),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 56),
			Corner = 12,
			Parent = card,
			OnClick = function()
				Net.Event("SpeedUpHatch"):FireServer(slot, "Shards")
			end,
		})
		return { Frame = card, Name = name, Bar = bar, Coin = coinBtn, Shard = shardBtn }
	end

	local function refreshHatching()
		local profile = ClientData.Get()
		local list = hatchingList()
		local pads = math.max(1, derived().Pads or 1)
		local waiting = #(profile.EggStorage or {})
		local busy = 0
		local seen = {}
		local now = Components.Now()
		for _, h in ipairs(list) do
			local egg = h.Egg
			if egg.HatchAt then
				busy += 1
			end
			seen[h.Key] = true
			local row = hatchRows[h.Key]
			if not row then
				row = makeHatchRow(h.Key, h.Slot)
				hatchRows[h.Key] = row
			end
			local color = Theme.Rarity(egg.Rarity)
			row.Name.Text = ('<font color="%s">%s</font> <font size="14" color="#DDE8FF">· slot %d</font>'):format(hex(color), GameConfig.EggDisplayName(egg), h.Slot)
			row.Bar.SetColor(color)
			local remaining = if egg.HatchAt then egg.HatchAt - now else nil
			if not remaining then
				row.Bar.Set(0, "waiting...")
				row.Coin.Visible, row.Shard.Visible = false, false
			elseif remaining <= 0 then
				row.Bar.Set(1, "🐣 Hatching!")
				row.Coin.Visible, row.Shard.Visible = false, false
			else
				local duration = egg.Duration or GameConfig.HatchDuration(egg.Rarity, egg.Size, profile.IncubatorLevel or 1)
				row.Bar.Set(1 - remaining / math.max(duration, 1), "⏱ " .. GameConfig.FormatTime(remaining))
				local cc = HUDController.SpeedUpCost(egg, remaining, "Coins")
				local sc = HUDController.SpeedUpCost(egg, remaining, "Shards")
				row.Coin.Visible, row.Shard.Visible = true, true
				Components.SetText(row.Coin, "⏩ " .. Components.Price("Coins", cc))
				Components.SetText(row.Shard, "⏩ " .. Components.Price("Shards", sc))
				Components.SetEnabled(row.Coin, coins() >= cc)
				Components.SetEnabled(row.Shard, shards() >= sc)
			end
			row.Frame.Size = UDim2.fromOffset(330, if row.Coin.Visible then 104 else 60)
		end
		for key, row in pairs(hatchRows) do
			if not seen[key] then
				row.Frame:Destroy()
				hatchRows[key] = nil
			end
		end
		local show = #list > 0 or waiting > 0
		if show and not hatchChip.Visible then
			hatchChip.Visible = true
			Components.Pop(hatchChip, 0.4, Theme.Tween.Bounce)
		elseif not show then
			hatchChip.Visible = false
			expanded = false
			hatchList.Visible = false
		end
		local label = ("Hatching %d/%d"):format(busy, pads)
		if waiting > 0 then
			label ..= ('\n<font size="16" color="#FFF3B0">+%d waiting</font>'):format(waiting)
		end
		Components.SetText(hatchChip, label .. (if expanded then " ▴" else " ▾"))
	end

	-- ===== Status pills =====
	local bottomRight = New("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -M, 1, -M),
		Size = UDim2.fromOffset(340, 110),
		Parent = root,
	})
	local brList = Components.List(bottomRight, 8, false, Enum.HorizontalAlignment.Right)
	brList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	local pillParent = if isTouch then rightCol else bottomRight
	local shieldPill = Components.Pill({ Name = "Shield", Color = Theme.Colors.Info, Size = UDim2.fromOffset(250, 44), LayoutOrder = 3, Visible = false, Parent = pillParent })
	local eventPill = Components.Pill({
		Name = "Event",
		Transparency = 0.15,
		Size = UDim2.fromOffset(if isTouch then 270 else 320, if isTouch then 46 else 54),
		TextSize = if isTouch then 22 else 28,
		LayoutOrder = 4,
		Visible = false,
		Parent = pillParent,
	})

	local centerPills = New("Frame", {
		Name = "CenterPills",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if isTouch then -16 else -78),
		Size = UDim2.fromOffset(560, 50),
		Parent = root,
	})
	Components.List(centerPills, 12, true, Enum.HorizontalAlignment.Center)
	local trainPill = Components.Pill({ Name = "Training", Color = Theme.Colors.Good, Size = UDim2.fromOffset(250, 48), TextSize = 24, LayoutOrder = 1, Visible = false, Parent = centerPills })
	local lanePill = Components.Pill({ Name = "SpeedLane", Color = Theme.Colors.Speed, Size = UDim2.fromOffset(230, 48), TextSize = 26, TextColor = Theme.Colors.Text, LayoutOrder = 2, Visible = false, Parent = centerPills })
	lanePill.Label.Text = "⚡ SPEED LANE!"
	local laneScale = New("UIScale", { Parent = lanePill })
	TweenService:Create(laneScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 }):Play()

	local function refreshTimers()
		local now = Components.Now()
		local ev = derived().ActiveEvent
		if ev and ev.Id and (ev.EndsAt or 0) > now then
			local cfg = Progression.Events[ev.Id]
			local color = cfg and cfg.Color or Theme.Colors.Accent
			eventPill.Label.Text = ('%s <font color="%s">%s</font> %s'):format(
				Theme.Icons.Event,
				hex(color),
				ev.Name or (cfg and cfg.Name) or ev.Id,
				GameConfig.FormatTime(ev.EndsAt - now)
			)
			local st = eventPill:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = Theme.Darken(color, 0.5)
			end
			if not eventPill.Visible then
				eventPill.Visible = true
				Components.Pop(eventPill, 0.5, Theme.Tween.Bounce)
			end
		else
			eventPill.Visible = false
		end
		local shieldUntil = attr("ShieldUntil", derived().ShieldUntil or 0)
		if shieldUntil > now then
			shieldPill.Visible = true
			shieldPill.Label.Text = ("%s Egg shield %s"):format(Theme.Icons.Shield, GameConfig.FormatTime(shieldUntil - now))
		else
			shieldPill.Visible = false
		end
	end

	-- ===== Carried egg banner =====
	local carry = Components.Pill({
		Name = "Carry",
		Transparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(if isTouch then 440 else 580, 56),
		TextSize = if isTouch then 22 else 28,
		Visible = false,
		Parent = root,
	})
	local carryStroke = carry:FindFirstChildOfClass("UIStroke")
	local carryScale = New("UIScale", { Parent = carry })
	local pulse = TweenService:Create(carryScale, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.07 })

	local function refreshCarry()
		local egg = attr("CarryingEgg", "")
		if egg == "" then
			if carry.Visible then
				carry.Visible = false
				pulse:Cancel()
				carryScale.Scale = 1
			end
			return
		end
		local color = Theme.Rarity(attr("CarryingRarity", ""))
		carry.Label.Text = ('🥚 <font color="%s">%s</font> — <font color="%s">RUN HOME!</font>'):format(hex(color), egg, hex(Theme.Colors.Speed))
		if carryStroke then
			carryStroke.Color = Theme.Darken(color, 0.3)
			carryStroke.Thickness = 5
		end
		if not carry.Visible then
			carry.Visible = true
			Components.Pop(carry, 0.4, Theme.Tween.Bounce)
			pulse:Play()
		end
	end

	-- ===== Biome title toast =====
	local biomeToken = 0
	local function showBiomeToast()
		biomeToken += 1
		local token = biomeToken
		local idx = attr("BiomeIndex", 0)
		local eff = effectiveSpeed()
		local profile = ClientData.Get()
		local b = if idx > 0 then GameConfig.GetBiomeByIndex(idx) else nil
		local title, sub, color
		if b then
			color = b.Theme and b.Theme.Accent or Theme.Colors.Accent
			local col = if eff < b.RequiredSpeed then Theme.Colors.Bad elseif eff < b.RecommendedSpeed then Theme.Colors.Warn else Theme.Colors.Good
			title = b.Name
			sub = ('%s · <font color="%s">⚡ %s</font>  need %s · safe %s'):format(b.Kind, hex(col), Fmt(eff), Fmt(b.RequiredSpeed), Fmt(b.RecommendedSpeed))
		else
			color = Theme.Colors.Good
			title = Theme.Icons.Home .. " SAFE ZONE"
			local nextB = nil
			for _, biome in ipairs(GameConfig.Biomes) do
				if not (profile.Biomes and profile.Biomes[biome.Id]) or eff < biome.RequiredSpeed then
					nextB = biome
					break
				end
			end
			sub = if nextB
				then ('Next rift: <b>%s</b>  <font color="%s">⚡ %s / %s</font>'):format(nextB.Name, hex(if eff >= nextB.RequiredSpeed then Theme.Colors.Good else Theme.Colors.Warn), Fmt(eff), Fmt(nextB.RequiredSpeed))
				else "Every rift is open to you!"
		end
		local old = root:FindFirstChild("BiomeToast")
		if old then
			old:Destroy()
		end
		local holder = New("Frame", {
			Name = "BiomeToast",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.28),
			Size = UDim2.fromOffset(820, 130),
			Parent = root,
		})
		local t1 = Text({ Text = title, TextSize = if isTouch then 54 else 70, Font = Theme.FontHeavy, TextColor3 = color, Outline = 5, TextWrapped = false, Size = UDim2.new(1, 0, 0, 80), Parent = holder })
		local t2 = Text({ Text = sub, TextSize = 26, RichText = true, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 84), Parent = holder })
		Components.Pop(holder, 0.4, Theme.Tween.Bounce)
		task.delay(2.6, function()
			if token ~= biomeToken or not holder.Parent then
				return
			end
			local fade = TweenInfo.new(0.5)
			for _, lbl in ipairs({ t1, t2 }) do
				TweenService:Create(lbl, fade, { TextTransparency = 1 }):Play()
				local s = lbl:FindFirstChildOfClass("UIStroke")
				if s then
					TweenService:Create(s, fade, { Transparency = 1 }):Play()
				end
			end
			task.wait(0.55)
			holder:Destroy()
		end)
	end

	-- ===== Treadmill training feedback =====
	local billboard = New("BillboardGui", {
		Name = "RR_TrainingPopups",
		Size = UDim2.fromOffset(240, 260),
		StudsOffset = Vector3.new(0, 2.5, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 150,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local lastStat = math.max(ClientData.Get().SpeedStat or 0, attr("SpeedStat", 0))
	local gains: { any } = {}
	local pendingGain = 0
	local lastPopup = 0
	local onTread = false
	local lastTrainAt = -100

	local function worldPopup(amount: number)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or Components.LowGraphics() then
			return
		end
		billboard.Adornee = hrp
		local label = Text({
			Text = "+" .. Fmt(amount) .. " " .. Theme.Icons.Speed,
			TextSize = 38,
			Font = Theme.FontHeavy,
			TextColor3 = Theme.Colors.Speed,
			TextWrapped = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.random(-40, 40), 0.85, 0),
			Size = UDim2.fromOffset(220, 44),
			Outline = 4,
			Parent = billboard,
		})
		Components.Pop(label, 0.3, Theme.Tween.Bounce)
		TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, label.Position.X.Offset, 0.15, 0) }):Play()
		task.delay(0.6, function()
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			local s = label:FindFirstChildOfClass("UIStroke")
			if s then
				TweenService:Create(s, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end)
		task.delay(1.15, function()
			label:Destroy()
		end)
	end

	local function onSpeedStat()
		local current = math.max(ClientData.Get().SpeedStat or 0, attr("SpeedStat", 0))
		local delta = current - lastStat
		lastStat = current
		if delta <= 0 or not onTread then
			return
		end
		local t = os.clock()
		lastTrainAt = t
		table.insert(gains, { T = t, N = delta })
		pendingGain += delta
		if t - lastPopup >= 0.35 then
			lastPopup = t
			local n = pendingGain
			pendingGain = 0
			worldPopup(if n >= 10 then math.floor(n) else math.floor(n * 10 + 0.5) / 10)
		end
	end

	local function refreshTraining()
		local t = os.clock()
		while gains[1] and t - gains[1].T > 2 do
			table.remove(gains, 1)
		end
		local active = t - lastTrainAt < 1.5
		if active then
			local sum = 0
			for _, g in ipairs(gains) do
				sum += g.N
			end
			trainPill.Label.Text = ("🏃 TRAINING +%s/s"):format(Fmt(math.floor(sum / 2 + 0.5)))
			if not trainPill.Visible then
				trainPill.Visible = true
				Components.Pop(trainPill, 0.5, Theme.Tween.Bounce)
			end
		else
			trainPill.Visible = false
		end
	end

	-- ===== Speed lane: pill + smooth FOV boost =====
	local fovApplied, fovCurrent = 0, 0
	local cam = workspace.CurrentCamera
	RunService.RenderStepped:Connect(function(dt)
		local c = workspace.CurrentCamera
		if c ~= cam then
			cam = c
			fovApplied = 0
		end
		local target = if player:GetAttribute("SpeedLane") == true then 8 else 0
		fovCurrent += (target - fovCurrent) * math.min(1, dt * 5)
		if math.abs(target - fovCurrent) < 0.02 then
			fovCurrent = target
		end
		if cam and fovCurrent ~= fovApplied then
			-- apply only our delta so other camera effects keep working
			cam.FieldOfView += fovCurrent - fovApplied
			fovApplied = fovCurrent
		end
	end)
	local function refreshLane()
		local on = player:GetAttribute("SpeedLane") == true
		if on and not lanePill.Visible then
			lanePill.Visible = true
			Components.Pop(lanePill, 0.4, Theme.Tween.Bounce)
		elseif not on then
			lanePill.Visible = false
		end
	end

	-- ===== Badges =====
	local seenPets = countKeys(ClientData.Get().Pets)
	local seenIndex = countKeys(ClientData.Get().Index)
	Components.WindowChanged:Connect(function(name, open)
		if open and name == "Pets" then
			seenPets = countKeys(ClientData.Get().Pets)
		elseif open and name == "Index" then
			seenIndex = countKeys(ClientData.Get().Index)
		end
	end)
	local function refreshBadges()
		local p = ClientData.Get()
		local nPets, nIndex = countKeys(p.Pets), countKeys(p.Index)
		seenPets = math.min(seenPets, nPets) -- selling/fusing lowers the count
		Components.SetBadge(badges.Shop, HUDController.CanAffordUpgrade())
		Components.SetBadge(badges.Daily, HUDController.HasClaimable())
		Components.SetBadge(badges.Pets, nPets > seenPets, if nPets - seenPets > 1 then tostring(math.min(nPets - seenPets, 9)) else "!")
		Components.SetBadge(badges.Index, nIndex > seenIndex)
		Components.SetBadge(badges.Rebirth, derived().CanRebirth == true)
	end

	-- Gamepad: D-pad left jumps into the side menu when no window is open.
	ContextActionService:BindAction("RR_FocusMenu", function(_, state)
		if state ~= Enum.UserInputState.Begin or Components.CurrentWindow or GuiService.SelectedObject then
			return Enum.ContextActionResult.Pass
		end
		GuiService.SelectedObject = menuButtons.Shop
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.DPadLeft)

	-- ===== Wiring =====
	for _, a in ipairs({ "Coins", "Shards", "EffectiveSpeed", "Income" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshWallet)
	end
	player:GetAttributeChangedSignal("SpeedStat"):Connect(onSpeedStat)
	player:GetAttributeChangedSignal("BiomeIndex"):Connect(showBiomeToast)
	player:GetAttributeChangedSignal("CarryingEgg"):Connect(refreshCarry)
	player:GetAttributeChangedSignal("CarryingRarity"):Connect(refreshCarry)
	player:GetAttributeChangedSignal("SpeedLane"):Connect(refreshLane)
	player.CharacterAdded:Connect(function()
		lastStat = math.max(ClientData.Get().SpeedStat or 0, attr("SpeedStat", 0))
	end)

	ClientData.Observe({ "Coins", "Shards", "Derived" }, refreshWallet)
	ClientData.Observe({ "SpeedStat" }, onSpeedStat)
	ClientData.Observe({ "Incubators", "EggStorage", "Derived", "IncubatorLevel" }, refreshHatching)

	local acc, treadAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		treadAcc += dt
		if treadAcc >= 0.2 then
			treadAcc = 0
			onTread = onOwnTreadmill()
		end
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		refreshTimers()
		refreshHatching()
		refreshTraining()
		refreshBadges()
	end)

	refreshWallet()
	refreshCarry()
	refreshTimers()
	refreshHatching()
	refreshLane()
	refreshBadges()
	task.delay(1.5, showBiomeToast)
end

return HUDController

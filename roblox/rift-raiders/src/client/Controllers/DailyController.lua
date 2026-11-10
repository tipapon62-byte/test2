-- DailyController: daily streak rewards, daily/weekly quests, achievements and bonus codes.

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
local Fmt = GameConfig.FormatNumber
local Progression = GameConfig.Progression
local Economy = GameConfig.Economy

local DailyController = {}

local function rewardText(r): string
	local parts = {}
	if r.Coins and r.Coins > 0 then
		table.insert(parts, "🪙 " .. Fmt(r.Coins))
	end
	if r.Shards and r.Shards > 0 then
		table.insert(parts, "💎 " .. Fmt(r.Shards))
	end
	if r.Item then
		local item = Economy.Items[r.Item]
		table.insert(parts, ("%dx %s"):format(r.Amount or 1, item and item.Name or r.Item))
	end
	if r.Egg then
		for _, e in ipairs(Economy.ShardEggs) do
			if e.Id == r.Egg then
				table.insert(parts, "🥚 " .. e.Name)
			end
		end
	end
	return table.concat(parts, "\n")
end

-- Which day of the 7-day track the next claim gives (1..7) and whether it can be claimed now.
function DailyController.DailyState(profile): (number, boolean, number)
	local daily = profile.Daily or {}
	local last = daily.LastClaim or 0
	local elapsed = Components.Now() - last
	local day
	if last == 0 or elapsed > Progression.Daily.StreakGrace then
		day = 1
	else
		day = ((daily.Streak or 0) % #Progression.Daily.Rewards) + 1
	end
	local wait = Progression.Daily.ClaimCooldown - elapsed
	return day, wait <= 0, math.max(wait, 0)
end

local function statValue(profile, stat: string): number
	if stat == "BiomesUnlocked" then
		local n = 0
		for _ in pairs(profile.Biomes or {}) do
			n += 1
		end
		return n
	elseif stat == "IndexCount" then
		local n = 0
		for _ in pairs(profile.Index or {}) do
			n += 1
		end
		return n
	elseif stat == "Rebirths" then
		return profile.Rebirths or 0
	end
	return (profile.Stats or {})[stat] or 0
end

local function findDef(defs, id: string)
	for _, d in ipairs(defs) do
		if d.Id == id then
			return d
		end
	end
	return nil
end

function DailyController.Start()
	local win = Components.Window("Daily", "Rewards & Quests", Theme.Icons.Daily, { TitleColor = Color3.fromRGB(255, 80, 140) })
	local body = win.Body
	local content = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), Parent = body })
	local pages = {}
	for _, id in ipairs({ "Rewards", "Quests", "Achievements", "Codes" }) do
		pages[id] = New("Frame", { Name = id, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
	end

	-- ===== Daily rewards =====
	local track = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 190), Parent = pages.Rewards })
	Components.List(track, 8, true, Enum.HorizontalAlignment.Center)
	local dayCards = {}
	for i, r in ipairs(Progression.Daily.Rewards) do
		local card = Components.Card({ Color = Theme.Colors.Panel, Size = UDim2.new(1 / 7, -8, 1, -8), LayoutOrder = i, Parent = track })
		Text({ Text = "Day " .. i, TextSize = 20, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), Parent = card })
		Text({ Text = if r.Egg then "🥚" elseif r.Shards and not r.Coins then "💎" else "🪙", TextSize = 34, Outline = false, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 36), Parent = card })
		Text({
			Text = rewardText(r),
			TextSize = 14,
			Font = Theme.FontBody,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -8, 1, -88),
			Position = UDim2.fromOffset(4, 84),
			Parent = card,
		})
		local mark = Text({ Text = "✅", TextSize = 26, Outline = false, Visible = false, AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, 4, 0, -8), Parent = card })
		dayCards[i] = { Card = card, Mark = mark, Stroke = card:FindFirstChildOfClass("UIStroke") }
	end
	local streakText = Text({ Text = "", TextSize = 22, RichText = true, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 198), Parent = pages.Rewards })
	local claimBtn = Components.Button({
		Text = "Claim!",
		TextSize = 26,
		Color = Theme.Colors.Good,
		Size = UDim2.fromOffset(320, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 240),
		Parent = pages.Rewards,
		OnClick = function()
			Net.Event("ClaimDaily"):FireServer()
		end,
	})

	local function refreshDaily()
		local p = ClientData.Get()
		local day, can, wait = DailyController.DailyState(p)
		for i, c in ipairs(dayCards) do
			local isNext = i == day
			c.Mark.Visible = i < day
			if c.Stroke then
				c.Stroke.Color = if isNext then Theme.Colors.Gold else Theme.Colors.Stroke
				c.Stroke.Thickness = if isNext then 5 else 3
			end
			c.Card.BackgroundColor3 = if isNext then Theme.Colors.Accent2 elseif i < day then Theme.Darken(Theme.Colors.Good, 0.4) else Theme.Colors.Panel
		end
		streakText.Text = ("🔥 Streak: <b>%d</b> day%s  ·  miss 48h and it resets"):format((p.Daily and p.Daily.Streak) or 0, if ((p.Daily and p.Daily.Streak) or 0) == 1 then "" else "s")
		if can then
			Components.SetText(claimBtn, ("🎁 Claim Day %d!"):format(day))
			Components.SetEnabled(claimBtn, true)
		else
			Components.SetText(claimBtn, "Next in " .. GameConfig.FormatTime(wait))
			Components.SetEnabled(claimBtn, false)
		end
	end

	-- ===== Quests =====
	local questList = Components.ScrollList(pages.Quests, 8)
	local function questRow(parent, order: number, def, entry, kind: string)
		local done = (entry.Progress or 0) >= def.Goal
		local row = Components.Card({
			Color = if entry.Claimed then Theme.Darken(Theme.Colors.Good, 0.45) else Theme.Colors.Panel,
			Size = UDim2.new(1, 0, 0, 78),
			LayoutOrder = order,
			Parent = parent,
		})
		Text({
			Text = def.Text,
			TextSize = 19,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -230, 0, 28),
			Position = UDim2.fromOffset(12, 6),
			Parent = row,
		})
		local bar = Components.ProgressBar({ Size = UDim2.new(1, -330, 0, 22), Position = UDim2.fromOffset(12, 44), Color = if done then Theme.Colors.Good else Theme.Colors.Accent, Parent = row })
		bar.Set((entry.Progress or 0) / def.Goal, ("%s / %s"):format(Fmt(math.min(entry.Progress or 0, def.Goal)), Fmt(def.Goal)))
		Text({
			Text = rewardText(def):gsub("\n", "  "),
			TextSize = 16,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(110, 30),
			Position = UDim2.new(1, -214, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		local btn = Components.Button({
			Text = if entry.Claimed then "✅ Claimed" elseif done then "Claim!" else "In progress",
			TextSize = 19,
			Color = Theme.Colors.Good,
			Size = UDim2.fromOffset(190, 58),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Parent = row,
			OnClick = function()
				Net.Event("ClaimQuest"):FireServer(kind, def.Id)
			end,
		})
		Components.SetEnabled(btn, done and not entry.Claimed)
	end
	local function header(parent, text: string, order: number)
		Text({ Text = text, TextSize = 24, Outline = 3, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = order, Parent = parent })
	end
	local function refreshQuests()
		Components.Clear(questList)
		local quests = ClientData.Get().Quests or {}
		local order = 0
		for _, section in ipairs({
			{ Kind = "Daily", Title = "☀️ Daily quests", Defs = Progression.DailyQuests },
			{ Kind = "Weekly", Title = "📅 Weekly quests", Defs = Progression.WeeklyQuests },
		}) do
			order += 1
			header(questList, section.Title, order)
			local q = quests[section.Kind]
			local any = false
			for _, entry in ipairs(q and q.List or {}) do
				local def = findDef(section.Defs, entry.Id)
				if def then
					order += 1
					any = true
					questRow(questList, order, def, entry, section.Kind)
				end
			end
			if not any then
				order += 1
				Text({ Text = "New quests arrive soon!", TextSize = 18, TextColor3 = Theme.Colors.TextDim, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order, Parent = questList })
			end
		end
		order += 1
		Text({
			Text = "Coin rewards grow with your best unlocked rift.",
			TextSize = 15,
			Font = Theme.FontBody,
			TextColor3 = Theme.Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = order,
			Parent = questList,
		})
	end

	-- ===== Achievements =====
	local achList = Components.ScrollList(pages.Achievements, 8)
	local function refreshAchievements()
		Components.Clear(achList)
		local p = ClientData.Get()
		local doneMap = p.Achievements or {}
		for i, a in ipairs(Progression.Achievements) do
			local done = doneMap[a.Id] == true
			local value = statValue(p, a.Stat)
			local row = Components.Card({
				Color = if done then Theme.Darken(Theme.Colors.Gold, 0.5) else Theme.Colors.Panel,
				Size = UDim2.new(1, 0, 0, 72),
				LayoutOrder = (if done then 1000 else 0) + i,
				Parent = achList,
			})
			Text({ Text = if done then "🏅" else "🎯", TextSize = 34, Outline = false, Size = UDim2.fromOffset(56, 72), Parent = row })
			Text({
				Text = a.Text,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -200, 0, 28),
				Position = UDim2.fromOffset(60, 6),
				Parent = row,
			})
			local bar = Components.ProgressBar({ Size = UDim2.new(1, -200, 0, 20), Position = UDim2.fromOffset(60, 40), Color = if done then Theme.Colors.Gold else Theme.Colors.Accent, Parent = row })
			bar.Set(if done then 1 else value / a.Goal, if done then "Complete!" else ("%s / %s"):format(Fmt(math.min(value, a.Goal)), Fmt(a.Goal)))
			Text({
				Text = "💎 " .. Fmt(a.Shards or 0),
				TextSize = 22,
				TextColor3 = Theme.Colors.Shards,
				AnchorPoint = Vector2.new(1, 0.5),
				Size = UDim2.fromOffset(120, 40),
				Position = UDim2.new(1, -12, 0.5, 0),
				Parent = row,
			})
		end
	end

	-- ===== Codes =====
	local codePage = pages.Codes
	Text({ Text = "🎟️ Got a bonus code?", TextSize = 30, Outline = 3, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 20), Parent = codePage })
	local codeBox = New("TextBox", {
		Text = "",
		PlaceholderText = "Enter code",
		ClearTextOnFocus = false,
		Font = Theme.Font,
		TextSize = 28,
		TextColor3 = Theme.Colors.TextDark,
		PlaceholderColor3 = Color3.fromRGB(130, 125, 160),
		BackgroundColor3 = Color3.fromRGB(240, 238, 255),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(440, 66),
		Parent = codePage,
	})
	Components.Corner(codeBox, 16)
	Components.Stroke(codeBox, Theme.Colors.Stroke, 3)
	Components.Selectable(codeBox)
	local lastRedeem = 0
	local function redeem()
		local code = codeBox.Text:gsub("%s", "")
		if code == "" or os.clock() - lastRedeem < 2 then
			return
		end
		lastRedeem = os.clock()
		Net.Event("RedeemCode"):FireServer(code:sub(1, 32))
		codeBox.Text = ""
	end
	Components.Button({
		Text = "Redeem",
		TextSize = 26,
		Color = Theme.Colors.Good,
		Size = UDim2.fromOffset(260, 66),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 172),
		Parent = codePage,
		OnClick = redeem,
	})
	codeBox.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)
	Text({
		Text = "Codes are case-insensitive and can be used once per account.",
		TextSize = 16,
		Font = Theme.FontBody,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 254),
		Parent = codePage,
	})

	-- ===== wiring =====
	local current = "Rewards"
	local function refresh()
		if not win.IsOpen then
			return
		end
		if current == "Rewards" then
			refreshDaily()
		elseif current == "Quests" then
			refreshQuests()
		elseif current == "Achievements" then
			refreshAchievements()
		end
	end
	local tabs = Components.Tabs(body, {
		{ Id = "Rewards", Text = "🎁 Daily" },
		{ Id = "Quests", Text = "📜 Quests" },
		{ Id = "Achievements", Text = "🏅 Achievements" },
		{ Id = "Codes", Text = "🎟️ Codes" },
	}, function(id)
		current = id
		for pid, page in pairs(pages) do
			page.Visible = pid == id
		end
		refresh()
	end)
	tabs.Select("Rewards")
	win.DefaultSelection = tabs.Buttons.Rewards
	win.OnOpen = refresh

	-- Stats tick constantly (TimePlayed, CoinsEarned): only rebuild the page they affect, throttled.
	local lastAch = 0
	ClientData.Observe({ "Daily", "Quests", "Achievements", "Stats", "Biomes", "Index", "Rebirths" }, function(_, changed)
		if not win.IsOpen then
			return
		end
		if current == "Rewards" and changed.Daily then
			refreshDaily()
		elseif current == "Quests" and changed.Quests then
			refreshQuests()
		elseif current == "Achievements" then
			if changed.Achievements or os.clock() - lastAch > 5 then
				lastAch = os.clock()
				refreshAchievements()
			end
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			if win.IsOpen and current == "Rewards" then
				refreshDaily()
			end
		end
	end)
end

return DailyController

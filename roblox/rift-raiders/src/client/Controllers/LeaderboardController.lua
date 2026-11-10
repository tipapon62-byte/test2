-- LeaderboardController: global leaderboards per Progression.Leaderboards.Stats key, fetched
-- with GetLeaderboard(statId) and cached briefly (the server refreshes them every ~2 min anyway).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent.Parent
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local New = Components.New
local Text = Components.Text
local Fmt = GameConfig.FormatNumber
local Boards = GameConfig.Progression.Leaderboards

local player = Players.LocalPlayer

local LeaderboardController = {}

local PREFERRED = { "Speed", "Income", "RarePets", "Retrievals" }
local ICONS = { Speed = "⚡", Income = "📈", RarePets = "🦄", Retrievals = "🥚" }
local MEDALS = { "🥇", "🥈", "🥉" }
local REFRESH_COOLDOWN = 10

local function statOrder(): { string }
	local order = {}
	for _, id in ipairs(PREFERRED) do
		if Boards.Stats[id] then
			table.insert(order, id)
		end
	end
	local extra = {}
	for id in pairs(Boards.Stats) do
		if not table.find(order, id) then
			table.insert(extra, id)
		end
	end
	table.sort(extra)
	for _, id in ipairs(extra) do
		table.insert(order, id)
	end
	return order
end

function LeaderboardController.Start()
	local win = Components.Window("Leaderboards", "Leaderboards", Theme.Icons.Leaderboard, { TitleColor = Theme.Buttons.Ranks })
	local body = win.Body

	local ids = statOrder()
	local tabDefs = {}
	for _, id in ipairs(ids) do
		table.insert(tabDefs, { Id = id, Text = (ICONS[id] or "🏆") .. " " .. id })
	end

	local title = Text({ Text = "", TextSize = 24, Outline = 3, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -200, 0, 40), Position = UDim2.fromOffset(4, 62), Parent = body })
	local refreshBtn = Components.Button({
		Text = "🔄 Refresh",
		TextSize = 19,
		Color = Theme.Colors.Info,
		Size = UDim2.fromOffset(170, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 60),
		Parent = body,
	})
	local listHolder = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 1, -112), Parent = body })
	local list = Components.ScrollList(listHolder, 6)

	local cache: { [string]: any } = {}
	local lastFetch: { [string]: number } = {}
	local loading: { [string]: boolean } = {}
	local current = ids[1]

	local function render()
		Components.Clear(list)
		local cfg = Boards.Stats[current]
		title.Text = (ICONS[current] or "🏆") .. " " .. (cfg and cfg.Title or current)
		local rows = cache[current]
		if loading[current] and not rows then
			Text({ Text = "Loading...", TextSize = 22, TextColor3 = Theme.Colors.TextDim, Size = UDim2.new(1, 0, 0, 40), Parent = list })
			return
		end
		if not rows or #rows == 0 then
			Text({ Text = "No entries yet — be the first!", TextSize = 22, TextColor3 = Theme.Colors.TextDim, Size = UDim2.new(1, 0, 0, 40), Parent = list })
			return
		end
		for i, entry in ipairs(rows) do
			local me = entry.UserId == player.UserId
			local color = if me then Theme.Colors.Accent2 elseif i <= 3 then Theme.Darken(Theme.Colors.Gold, 0.45 + i * 0.05) else Theme.Colors.Panel
			local row = Components.Card({ Color = color, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = i, Parent = list })
			Text({ Text = MEDALS[i] or ("#" .. i), TextSize = if MEDALS[i] then 30 else 22, Outline = MEDALS[i] == nil, Size = UDim2.fromOffset(70, 52), Parent = row })
			Text({
				Text = tostring(entry.Name or "?") .. (if me then "  (you)" else ""),
				TextSize = 21,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, -260, 1, 0),
				Position = UDim2.fromOffset(74, 0),
				Parent = row,
			})
			Text({
				Text = Fmt(entry.Value or 0),
				TextSize = 22,
				TextColor3 = Theme.Colors.Gold,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Size = UDim2.fromOffset(170, 52),
				Position = UDim2.new(1, -14, 0, 0),
				Parent = row,
			})
		end
	end

	local function fetch(statId: string, force: boolean?)
		local last = lastFetch[statId]
		if loading[statId] or (last and os.clock() - last < REFRESH_COOLDOWN) then
			if force then
				Components.Toast("Leaderboards refresh every few seconds — hang on!", "info", 2)
			end
			return
		end
		if not force and cache[statId] and last and os.clock() - last < 60 then
			return
		end
		loading[statId] = true
		lastFetch[statId] = os.clock()
		render()
		task.spawn(function()
			local fn = Net.Function("GetLeaderboard")
			local ok, res = pcall(fn.InvokeServer, fn, statId)
			loading[statId] = false
			if ok and type(res) == "table" then
				cache[statId] = res
			elseif not cache[statId] then
				cache[statId] = {}
			end
			if current == statId and win.IsOpen then
				render()
			end
		end)
	end

	Components.SetOnClick(refreshBtn, function()
		fetch(current, true)
	end)

	local tabs = Components.Tabs(body, tabDefs, function(id)
		current = id
		render()
		if win.IsOpen then
			fetch(id)
		end
	end)
	if current then
		tabs.Select(current)
		win.DefaultSelection = tabs.Buttons[current]
	end
	win.OnOpen = function()
		render()
		fetch(current)
	end
end

return LeaderboardController

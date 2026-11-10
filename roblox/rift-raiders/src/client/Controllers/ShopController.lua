-- ShopController: upgrades, Rift Keys (biome access), trails, items and shard eggs.
-- Every button only sends Purchase/EquipTrail; the server validates price, range and limits
-- and answers through ProfileUpdated + Notify.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local Fmt = GameConfig.FormatNumber

local player = Players.LocalPlayer

local ShopController = {}

local function wallet(currency: string?): number
	local p = ClientData.Get()
	if currency == "Shards" then
		return player:GetAttribute("Shards") or p.Shards or 0
	end
	return player:GetAttribute("Coins") or p.Coins or 0
end

local function purchase(category: string, id: any)
	Net.Event("Purchase"):FireServer(category, id)
end

local function pct(x: number): string
	return ("%d%%"):format(math.floor(x * 100 + 0.5))
end

-- ===== Upgrades tab =====
local UPGRADES = {
	{
		Id = "BaseUpgrade",
		Title = "🏠 Enclosure",
		LevelKey = "BaseLevel",
		Track = Economy.BaseLevels,
		Color = Color3.fromRGB(80, 200, 120),
		Describe = function(l)
			return ("%d pet slots\n+%s income"):format(l.Slots, pct(l.IncomeBonus))
		end,
	},
	{
		Id = "TreadmillUpgrade",
		Title = "🏃 Treadmill",
		LevelKey = "TreadmillLevel",
		Track = Economy.TreadmillLevels,
		Color = Color3.fromRGB(80, 170, 255),
		Describe = function(l)
			return ("%s\n+%s Speed/s · x%.2f running\n+%s base Speed"):format(l.Name, Fmt(l.Gain), l.Efficiency, Fmt(l.BaseSpeed))
		end,
	},
	{
		Id = "IncubatorUpgrade",
		Title = "🥚 Incubator",
		LevelKey = "IncubatorLevel",
		Track = Economy.IncubatorLevels,
		Color = Color3.fromRGB(255, 160, 60),
		Describe = function(l)
			return ("%d pad%s\n-%s hatch time"):format(l.Pads, if l.Pads == 1 then "" else "s", pct(l.HatchSpeed))
		end,
	},
}

local function buildUpgrades(page): () -> ()
	Components.List(page, 12, true, Enum.HorizontalAlignment.Center)
	local cards = {}
	for i, u in ipairs(UPGRADES) do
		local card = Components.Card({ Color = Theme.Darken(u.Color, 0.35), Size = UDim2.new(1 / 3, -10, 1, -4), LayoutOrder = i, Parent = page })
		Text({ Text = u.Title, TextSize = 28, Outline = 3, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 6), Parent = card })
		local level = Text({ Text = "", TextSize = 18, TextColor3 = Theme.Colors.TextDim, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 44), Parent = card })
		local stats = Text({
			Text = "",
			TextSize = 17,
			Font = Theme.FontBody,
			RichText = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -20, 1, -150),
			Position = UDim2.fromOffset(10, 72),
			Parent = card,
		})
		local btn = Components.Button({
			Text = "",
			Color = Theme.Colors.Good,
			Size = UDim2.new(1, -24, 0, Theme.ButtonHeight),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Parent = card,
			OnClick = function()
				purchase(u.Id, 0)
			end,
		})
		cards[i] = { Level = level, Stats = stats, Button = btn }
	end
	return function()
		local p = ClientData.Get()
		for i, u in ipairs(UPGRADES) do
			local c = cards[i]
			local lvl = math.clamp(p[u.LevelKey] or 1, 1, #u.Track)
			local cur = u.Track[lvl]
			local nxt = u.Track[lvl + 1]
			c.Level.Text = ("Level %d / %d"):format(lvl, #u.Track)
			if nxt then
				c.Stats.Text = ("<b>Now</b>\n%s\n<font color=\"#%s\"><b>Next</b>\n%s</font>"):format(
					u.Describe(cur),
					Theme.Colors.Accent:ToHex(),
					u.Describe(nxt)
				)
				Components.SetText(c.Button, "Upgrade " .. Components.Price("Coins", nxt.Price))
				Components.SetEnabled(c.Button, wallet("Coins") >= nxt.Price)
			else
				c.Stats.Text = "<b>Now</b>\n" .. u.Describe(cur) .. "\n\n🏆 Fully upgraded!"
				Components.SetText(c.Button, "MAX")
				Components.SetEnabled(c.Button, false)
			end
		end
	end
end

-- ===== Rift Keys tab =====
local function buildKeys(page): () -> ()
	local list = Components.ScrollList(page, 8)
	local rows = {}
	for _, b in ipairs(GameConfig.Biomes) do
		local row = Components.Card({ Color = Theme.Darken(b.Theme.Accent, 0.55), Size = UDim2.new(1, 0, 0, 76), LayoutOrder = b.Index, Parent = list })
		local swatch = New("Frame", { BackgroundColor3 = b.Theme.Accent, Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(10, 10), Parent = row })
		Components.Corner(swatch, 12)
		Components.Stroke(swatch, Theme.Colors.Stroke, 3)
		Text({ Text = tostring(b.Index), TextSize = 28, Outline = 3, Parent = swatch })
		Text({
			Text = ("<b>%s</b>  <font color=\"#C8C3EB\">%s</font>"):format(b.Name, b.Kind),
			RichText = true,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -310, 0, 30),
			Position = UDim2.fromOffset(78, 6),
			Parent = row,
		})
		local info = Text({
			Text = "",
			RichText = true,
			TextSize = 16,
			Font = Theme.FontBody,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -310, 0, 34),
			Position = UDim2.fromOffset(78, 36),
			Parent = row,
		})
		local btn = Components.Button({
			Text = "",
			Color = Theme.Colors.Coins,
			Size = UDim2.fromOffset(210, 58),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Parent = row,
			OnClick = function()
				purchase("BiomeKey", b.Index)
			end,
		})
		rows[b.Index] = { Info = info, Button = btn, Biome = b }
	end
	return function()
		local p = ClientData.Get()
		local eff = player:GetAttribute("EffectiveSpeed") or (p.Derived and p.Derived.EffectiveSpeed) or 0
		for _, r in pairs(rows) do
			local b = r.Biome
			local owned = p.Biomes and p.Biomes[b.Id]
			local speedColor = if eff >= b.RecommendedSpeed then Theme.Colors.Good elseif eff >= b.RequiredSpeed then Theme.Colors.Warn else Theme.Colors.Bad
			r.Info.Text = ("<font color=\"#%s\">⚡ need %s · safe %s</font>  ·  pets from 🪙%s/s"):format(
				speedColor:ToHex(),
				Fmt(b.RequiredSpeed),
				Fmt(b.RecommendedSpeed),
				Fmt(b.IncomeBase)
			)
			if owned then
				Components.SetText(r.Button, Theme.Icons.Check .. " Owned")
				Components.SetEnabled(r.Button, false)
			else
				Components.SetText(r.Button, "🔑 " .. Components.Price("Coins", b.UnlockPrice))
				Components.SetEnabled(r.Button, wallet("Coins") >= b.UnlockPrice)
			end
		end
	end
end

-- ===== Trails tab =====
local function buildTrails(page): () -> ()
	local grid = Components.ScrollGrid(page, Vector2.new(196, 170), 10)
	local cards = {}
	for i, id in ipairs(Economy.TrailOrder) do
		local t = Economy.Trails[id]
		local card = Components.Card({ Color = Theme.Colors.Panel, LayoutOrder = i, Parent = grid })
		local swatch = New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 10), Parent = card })
		Components.CornerScale(swatch, 0.5)
		Components.Stroke(swatch, Theme.Colors.Stroke, 2)
		New("UIGradient", { Color = ColorSequence.new(t.Colors[1], t.Colors[2] or t.Colors[1]), Parent = swatch })
		Text({ Text = t.Name, TextSize = 19, Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 40), Parent = card })
		Text({
			Text = ("⚡ x%.2f Speed"):format(t.SpeedMult):gsub("0+ ", " "):gsub("%. ", " "),
			TextSize = 16,
			TextColor3 = Theme.Colors.Speed,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 66),
			Parent = card,
		})
		local btn = Components.Button({
			Text = "",
			TextSize = 19,
			Size = UDim2.new(1, -20, 0, 56),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Parent = card,
		})
		cards[id] = { Button = btn, Trail = t }
	end
	return function()
		local p = ClientData.Get()
		local trails = p.Trails or { Owned = { None = true }, Equipped = "None" }
		for id, c in pairs(cards) do
			local owned = trails.Owned and trails.Owned[id]
			if trails.Equipped == id then
				Components.SetText(c.Button, "Equipped")
				Components.SetColor(c.Button, Theme.Colors.Accent2)
				Components.SetEnabled(c.Button, false)
			elseif owned then
				Components.SetText(c.Button, "Equip")
				Components.SetColor(c.Button, Theme.Colors.Info)
				Components.SetEnabled(c.Button, true)
				Components.SetOnClick(c.Button, function()
					Net.Event("EquipTrail"):FireServer(id)
				end)
			else
				local currency = c.Trail.Currency or "Coins"
				Components.SetText(c.Button, Components.Price(currency, c.Trail.Price))
				Components.SetColor(c.Button, if currency == "Shards" then Theme.Colors.Shards else Theme.Colors.Good)
				Components.SetEnabled(c.Button, wallet(currency) >= c.Trail.Price)
				Components.SetOnClick(c.Button, function()
					purchase("Trail", id)
				end)
			end
		end
	end
end

-- ===== Items tab =====
local ITEM_ORDER = { "BearTrap", "DecoyEgg", "MutationPotion" }
local ITEM_ICON = { BearTrap = Theme.Icons.Trap, DecoyEgg = Theme.Icons.Decoy, MutationPotion = "🧪" }

local function buildItems(page): () -> ()
	Components.List(page, 12, true, Enum.HorizontalAlignment.Center)
	local cards = {}
	for i, id in ipairs(ITEM_ORDER) do
		local item = Economy.Items[id]
		local card = Components.Card({ Color = Theme.Colors.Panel, Size = UDim2.new(1 / 3, -10, 1, -4), LayoutOrder = i, Parent = page })
		Text({ Text = ITEM_ICON[id] or "📦", TextSize = 46, Outline = false, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 6), Parent = card })
		Text({ Text = item.Name, TextSize = 22, Size = UDim2.new(1, -10, 0, 28), Position = UDim2.fromOffset(5, 62), Parent = card })
		Text({
			Text = item.Description,
			TextSize = 15,
			Font = Theme.FontBody,
			TextColor3 = Theme.Colors.TextDim,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -20, 1, -200),
			Position = UDim2.fromOffset(10, 94),
			Parent = card,
		})
		local owned = Text({ Text = "", TextSize = 18, Size = UDim2.new(1, 0, 0, 24), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -84), Parent = card })
		local btn = Components.Button({
			Text = "",
			Color = if item.Currency == "Shards" then Theme.Colors.Shards else Theme.Colors.Good,
			Size = UDim2.new(1, -24, 0, Theme.ButtonHeight),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Parent = card,
			OnClick = function()
				purchase("Item", id)
			end,
		})
		cards[id] = { Owned = owned, Button = btn, Item = item }
	end
	return function()
		local items = ClientData.Get().Items or {}
		for id, c in pairs(cards) do
			local n = items[id] or 0
			c.Owned.Text = ("Owned %d / %d"):format(n, c.Item.MaxOwned)
			local currency = c.Item.Currency or "Coins"
			if n >= c.Item.MaxOwned then
				Components.SetText(c.Button, "Full")
				Components.SetEnabled(c.Button, false)
			else
				Components.SetText(c.Button, "Buy " .. Components.Price(currency, c.Item.Price))
				Components.SetEnabled(c.Button, wallet(currency) >= c.Item.Price)
			end
		end
	end
end

-- ===== Shard eggs tab =====
local function buildShardEggs(page): () -> ()
	Components.List(page, 12, true, Enum.HorizontalAlignment.Center)
	local cards = {}
	for i, egg in ipairs(Economy.ShardEggs) do
		local card = Components.Card({ Color = Theme.Darken(Theme.Colors.Accent2, 0.3), Size = UDim2.new(0.5, -10, 1, -4), LayoutOrder = i, Parent = page })
		Text({ Text = "🥚 " .. egg.Name, TextSize = 26, Outline = 3, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 8), Parent = card })
		local total = 0
		for _, w in pairs(egg.Weights) do
			total += w
		end
		local lines = {}
		for _, r in ipairs(GameConfig.Rarities.Order) do
			local w = egg.Weights[r]
			if w then
				local chance = w / total * 100
				table.insert(lines, ("<font color=\"#%s\">%s</font>  %s%%"):format(Theme.Rarity(r):ToHex(), r, if chance < 1 then ("%.1f"):format(chance) else tostring(math.floor(chance + 0.5))))
			end
		end
		if egg.ForceMutation then
			table.insert(lines, ("Always <b>%s</b>!"):format(egg.ForceMutation))
		end
		table.insert(lines, "<i>Your best unlocked rift · goes straight onto a free incubator pad</i>")
		Text({
			Text = table.concat(lines, "\n"),
			RichText = true,
			TextSize = 17,
			Font = Theme.FontBody,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -20, 1, -140),
			Position = UDim2.fromOffset(10, 52),
			Parent = card,
		})
		local btn = Components.Button({
			Text = "Buy " .. Components.Price("Shards", egg.Price),
			Color = Theme.Colors.Shards,
			Size = UDim2.new(1, -24, 0, Theme.ButtonHeight),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Parent = card,
			OnClick = function()
				purchase("ShardEgg", egg.Id)
			end,
		})
		cards[i] = { Button = btn, Egg = egg }
	end
	return function()
		for _, c in ipairs(cards) do
			Components.SetEnabled(c.Button, wallet("Shards") >= c.Egg.Price)
		end
	end
end

function ShopController.Start()
	local win = Components.Window("Shop", "Rift Shop", Theme.Icons.Shop, { TitleColor = Color3.fromRGB(255, 150, 40) })
	local body = win.Body
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64 - 34),
		Parent = body,
	})
	Text({
		Text = "🛈 Purchases only work inside your base or next to the hub shop.",
		TextSize = 16,
		Font = Theme.FontBody,
		TextColor3 = Theme.Colors.TextDim,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = body,
	})

	local pages = {}
	local refreshers = {}
	local builders = {
		{ Id = "Upgrades", Text = "⬆️ Upgrades", Build = buildUpgrades },
		{ Id = "Keys", Text = "🔑 Rift Keys", Build = buildKeys },
		{ Id = "Trails", Text = "✨ Trails", Build = buildTrails },
		{ Id = "Items", Text = "🧰 Items", Build = buildItems },
		{ Id = "ShardEggs", Text = "💎 Shard Eggs", Build = buildShardEggs },
	}
	for _, b in ipairs(builders) do
		local page = New("Frame", { Name = b.Id, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
		pages[b.Id] = page
		refreshers[b.Id] = b.Build(page)
	end

	local current = "Upgrades"
	local function refresh()
		if win.IsOpen and refreshers[current] then
			refreshers[current]()
		end
	end
	local tabs = Components.Tabs(body, builders, function(id)
		current = id
		for pid, page in pairs(pages) do
			page.Visible = pid == id
		end
		refresh()
	end)
	tabs.Select("Upgrades")
	win.DefaultSelection = tabs.Buttons.Upgrades
	win.OnOpen = refresh

	ClientData.Observe({ "Coins", "Shards", "BaseLevel", "TreadmillLevel", "IncubatorLevel", "Biomes", "Trails", "Items", "Derived" }, refresh)
	for _, a in ipairs({ "Coins", "Shards", "EffectiveSpeed" }) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
end

-- Lets other UI jump straight to a shop tab (e.g. "buy traps" hints).
function ShopController.Open()
	Components.Open("Shop")
end

return ShopController

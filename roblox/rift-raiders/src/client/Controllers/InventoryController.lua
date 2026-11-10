-- InventoryController: the Pets window — grid of owned pets with 3D previews, filters, sort,
-- a detail panel (place/store, lock, sell, rename, mutation potion) and "sell duplicates".
-- All actions go through PetAction; the server re-checks ownership, locks and slots.

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
local Fmt = GameConfig.FormatNumber
local Rarities = GameConfig.Rarities

local player = Players.LocalPlayer

local InventoryController = {}

local MAX_NAME = 20
local SORTS = { "Income", "Rarity", "Newest" }

local function petAction(action: string, uids: { string }, arg: any?)
	Net.Event("PetAction"):FireServer(action, uids, arg)
end

local function rarityOf(pet): string
	local s = GameConfig.GetSpecies(pet.Species)
	return s and s.Rarity or "Common"
end

local function rarityIndex(pet): number
	local r = Rarities.ById[rarityOf(pet)]
	return r and r.Index or 1
end

-- Server keeps the best copy of each species and skips locked pets; this mirrors that for the dialog.
function InventoryController.DuplicateCandidates(pets): ({ string }, number)
	local bySpecies = {}
	for _, pet in pairs(pets) do
		bySpecies[pet.Species] = bySpecies[pet.Species] or {}
		table.insert(bySpecies[pet.Species], pet)
	end
	local uids, value = {}, 0
	for _, group in pairs(bySpecies) do
		if #group > 1 then
			table.sort(group, function(a, b)
				return GameConfig.PetIncome(a) > GameConfig.PetIncome(b)
			end)
			for i = 2, #group do
				local pet = group[i]
				if not pet.Locked then
					table.insert(uids, pet.Uid)
					value += GameConfig.PetSellValue(pet)
				end
			end
		end
	end
	return uids, value
end

local function signature(pet): string
	return table.concat({ pet.Species, pet.Size or "", pet.Mutation or "", tostring(pet.Tier or 1), pet.Name or "", tostring(pet.Slot or ""), tostring(pet.Locked or false) }, "|")
end

function InventoryController.Start()
	local win = Components.Window("Pets", "My Pets", Theme.Icons.Pets, { TitleColor = Color3.fromRGB(70, 190, 110) })
	local body = win.Body

	local left = New("Frame", { Name = "Left", BackgroundTransparency = 1, Size = UDim2.new(1, -312, 1, 0), Parent = body })
	local detail = Components.Card({
		Name = "Detail",
		Color = Theme.Colors.Panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 300, 1, 0),
		Parent = body,
	})

	-- toolbar
	local filter = "All"
	local sortIdx = 1
	local selected: string? = nil
	local rebuild: () -> ()

	local tabs = Components.Tabs(left, {
		{ Id = "All", Text = "All" },
		{ Id = "Placed", Text = "Placed" },
		{ Id = "Stored", Text = "Stored" },
	}, function(id)
		filter = id
		if rebuild then
			rebuild()
		end
	end, { Size = UDim2.new(1, -160, 0, 58) })
	local sortBtn = Components.Button({
		Text = "Sort: Income",
		TextSize = 19,
		Color = Theme.Colors.Info,
		Size = UDim2.fromOffset(150, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Parent = left,
		OnClick = function()
			sortIdx = sortIdx % #SORTS + 1
			if rebuild then
				rebuild()
			end
		end,
	})
	local slotsLabel = Text({
		Text = "",
		TextSize = 19,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -230, 0, 44),
		Position = UDim2.fromOffset(4, 60),
		Parent = left,
	})
	local dupBtn = Components.Button({
		Text = "🧹 Sell duplicates",
		TextSize = 19,
		Color = Theme.Colors.Warn,
		Size = UDim2.fromOffset(220, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 58),
		Parent = left,
	})
	local grid = Components.ScrollGrid(left, Vector2.new(124, 156), 8, {
		Position = UDim2.fromOffset(0, 112),
		Size = UDim2.new(1, 0, 1, -112),
	})
	local emptyLabel = Text({
		Text = "No pets here yet.\nGrab an egg from a rift nest and run it home! 🥚",
		TextSize = 22,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.fromOffset(0, 180),
		Visible = false,
		Parent = left,
	})

	-- detail panel
	Components.Padding(detail, 10)
	Components.List(detail, 6, false, Enum.HorizontalAlignment.Center)
	local previewHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 108), LayoutOrder = 1, Parent = detail })
	local dTitle = Text({ Text = "Select a pet", TextSize = 21, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Parent = detail })
	local dInfo = Text({
		Text = "",
		TextSize = 15,
		Font = Theme.FontBody,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 72),
		LayoutOrder = 3,
		Parent = detail,
	})
	local renameRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 4, Parent = detail })
	local nameBox = New("TextBox", {
		Text = "",
		PlaceholderText = "Rename (max 20)",
		ClearTextOnFocus = false,
		Font = Theme.FontBody,
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDark,
		PlaceholderColor3 = Color3.fromRGB(120, 115, 150),
		BackgroundColor3 = Color3.fromRGB(240, 238, 255),
		Size = UDim2.new(1, -70, 1, 0),
		Parent = renameRow,
	})
	Components.Corner(nameBox, 10)
	Components.Stroke(nameBox, Theme.Colors.Stroke, 2)
	Components.Selectable(nameBox)
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		local len = utf8.len(nameBox.Text) or #nameBox.Text
		if len > MAX_NAME then
			local cut = utf8.offset(nameBox.Text, MAX_NAME + 1)
			nameBox.Text = nameBox.Text:sub(1, (cut or (MAX_NAME + 1)) - 1)
		end
	end)
	local renameBtn = Components.Button({
		Text = "✏️",
		TextSize = 22,
		Color = Theme.Colors.Info,
		Size = UDim2.fromOffset(62, 46),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = renameRow,
	})
	local function actionRow(order: number): any
		local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = order, Parent = detail })
		return row
	end
	local row1 = actionRow(5)
	local row2 = actionRow(6)
	local placeBtn = Components.Button({ Text = "Place", TextSize = 19, Color = Theme.Colors.Good, Size = UDim2.new(0.5, -4, 1, 0), Parent = row1 })
	local lockBtn = Components.Button({
		Text = "🔒 Lock",
		TextSize = 19,
		Color = Theme.Colors.Accent2,
		Size = UDim2.new(0.5, -4, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = row1,
	})
	local sellBtn = Components.Button({ Text = "Sell", TextSize = 19, Color = Theme.Colors.Bad, Size = UDim2.new(0.5, -4, 1, 0), Parent = row2 })
	local potionBtn = Components.Button({
		Text = "🧪 Potion",
		TextSize = 17,
		Color = Theme.Colors.Shards,
		Size = UDim2.new(0.5, -4, 1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = row2,
	})
	for _, b in ipairs({ placeBtn, lockBtn, sellBtn, potionBtn, renameBtn }) do
		Components.SetEnabled(b, false)
	end
	nameBox.Visible = false

	local cards: { [string]: any } = {}
	local previewKey = ""

	local function pets(): { [string]: any }
		return ClientData.Get().Pets or {}
	end

	local function counts()
		local placed, total = 0, 0
		for _, p in pairs(pets()) do
			total += 1
			if p.Slot then
				placed += 1
			end
		end
		return placed, total
	end

	local function refreshDetail()
		local pet = selected and pets()[selected]
		if not pet then
			selected = nil
			dTitle.Text = "Select a pet"
			dInfo.Text = "Tap a pet to see its stats."
			previewKey = ""
			Components.Clear(previewHolder)
			nameBox.Visible = false
			for _, b in ipairs({ placeBtn, lockBtn, sellBtn, potionBtn, renameBtn }) do
				Components.SetEnabled(b, false)
			end
			return
		end
		local p = ClientData.Get()
		local rarity = rarityOf(pet)
		local key = signature(pet)
		if key ~= previewKey then
			previewKey = key
			Components.Clear(previewHolder)
			Components.PetViewport(pet, { Spin = true, Parent = previewHolder })
		end
		dTitle.Text = GameConfig.PetDisplayName(pet)
		dTitle.TextColor3 = Theme.Rarity(rarity)
		local species = GameConfig.GetSpecies(pet.Species)
		dInfo.Text = ("<font color=\"#%s\"><b>%s</b></font> %s · Tier %d\n%s · %s · %.1f kg\n<font color=\"#FFCD32\">🪙 %s/s</font> · sells for 🪙 %s"):format(
			Theme.Rarity(rarity):ToHex(),
			rarity,
			species and species.Name or pet.Species,
			pet.Tier or 1,
			pet.Size or "Normal",
			pet.Mutation or "No mutation",
			pet.Kg or 0,
			Fmt(GameConfig.PetIncome(pet)),
			Fmt(GameConfig.PetSellValue(pet))
		)
		nameBox.Visible = true
		if not nameBox:IsFocused() then
			nameBox.Text = pet.Name or ""
		end
		Components.SetEnabled(renameBtn, true)

		local placed = counts()
		local slots = (p.Derived and p.Derived.Slots) or 6
		if pet.Slot then
			Components.SetText(placeBtn, "📦 Store")
			Components.SetColor(placeBtn, Theme.Colors.Info)
			Components.SetEnabled(placeBtn, true)
		else
			Components.SetText(placeBtn, if placed >= slots then "Pen full" else "🏠 Place")
			Components.SetColor(placeBtn, Theme.Colors.Good)
			Components.SetEnabled(placeBtn, placed < slots)
		end
		Components.SetText(lockBtn, if pet.Locked then "🔓 Unlock" else "🔒 Lock")
		Components.SetEnabled(lockBtn, true)
		Components.SetText(sellBtn, if pet.Locked then "🔒 Locked" else "💰 Sell")
		Components.SetEnabled(sellBtn, not pet.Locked)
		local potions = (p.Items and p.Items.MutationPotion) or 0
		Components.SetText(potionBtn, ("🧪 Potion x%d"):format(potions))
		Components.SetEnabled(potionBtn, potions > 0)
	end

	local function makeCard(pet): any
		local rarity = rarityOf(pet)
		local color = Theme.Rarity(rarity)
		local card = New("TextButton", {
			Name = pet.Uid,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Darken(color, 0.55),
		})
		Components.Selectable(card)
		Components.Corner(card, 14)
		Components.Gradient(card, Theme.Darken(color, 0.35), Theme.Darken(color, 0.7))
		local stroke = Components.Stroke(card, color, 3)
		Components.PetViewport(pet, { Size = UDim2.new(1, -10, 0, 86), Position = UDim2.fromOffset(5, 4), Parent = card })
		Text({
			Text = GameConfig.PetDisplayName(pet),
			TextSize = 14,
			Size = UDim2.new(1, -8, 0, 34),
			Position = UDim2.fromOffset(4, 90),
			Parent = card,
		})
		Text({
			Text = "🪙 " .. Fmt(GameConfig.PetIncome(pet)) .. "/s",
			TextSize = 15,
			TextColor3 = Theme.Colors.Coins,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 128),
			Parent = card,
		})
		if pet.Locked then
			Text({ Text = Theme.Icons.Lock, TextSize = 20, Outline = false, Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(4, 4), Parent = card })
		end
		if pet.Slot then
			local tag = New("Frame", { BackgroundColor3 = Theme.Colors.Good, Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Parent = card })
			Components.CornerScale(tag, 0.5)
			Components.Stroke(tag, Theme.Colors.Stroke, 2)
			Text({ Text = "🏠", TextSize = 14, Outline = false, Parent = tag })
		end
		card.Activated:Connect(function()
			selected = pet.Uid
			for uid, c in pairs(cards) do
				local s = c.Stroke
				s.Thickness = if uid == selected then 5 else 3
				s.Color = if uid == selected then Theme.Colors.Accent else c.Color
			end
			refreshDetail()
			Components.Pop(card, 0.9, Theme.Tween.Fast)
		end)
		return { Frame = card, Key = signature(pet), Stroke = stroke, Color = color }
	end

	rebuild = function()
		if not win.IsOpen then
			return
		end
		local all = pets()
		-- drop stale cards, rebuild changed ones
		for uid, c in pairs(cards) do
			local pet = all[uid]
			if not pet or c.Key ~= signature(pet) then
				c.Frame:Destroy()
				cards[uid] = nil
			end
		end
		local list = {}
		for uid, pet in pairs(all) do
			pet.Uid = pet.Uid or uid
			local show = filter == "All" or (filter == "Placed" and pet.Slot ~= nil) or (filter == "Stored" and pet.Slot == nil)
			if show then
				table.insert(list, pet)
			end
		end
		local mode = SORTS[sortIdx]
		Components.SetText(sortBtn, "Sort: " .. mode)
		table.sort(list, function(a, b)
			if mode == "Rarity" then
				local ra, rb = rarityIndex(a), rarityIndex(b)
				if ra ~= rb then
					return ra > rb
				end
			elseif mode == "Newest" then
				if (a.Obtained or 0) ~= (b.Obtained or 0) then
					return (a.Obtained or 0) > (b.Obtained or 0)
				end
			end
			local ia, ib = GameConfig.PetIncome(a), GameConfig.PetIncome(b)
			if ia ~= ib then
				return ia > ib
			end
			return a.Uid < b.Uid
		end)
		local visible = {}
		for i, pet in ipairs(list) do
			local c = cards[pet.Uid]
			if not c then
				c = makeCard(pet)
				cards[pet.Uid] = c
				c.Frame.Parent = grid
			end
			c.Frame.LayoutOrder = i
			c.Frame.Visible = true
			c.Stroke.Thickness = if pet.Uid == selected then 5 else 3
			c.Stroke.Color = if pet.Uid == selected then Theme.Colors.Accent else c.Color
			visible[pet.Uid] = true
		end
		for uid, c in pairs(cards) do
			if not visible[uid] then
				c.Frame.Visible = false
			end
		end
		emptyLabel.Visible = #list == 0

		local p = ClientData.Get()
		local placed, total = counts()
		local slots = (p.Derived and p.Derived.Slots) or 6
		slotsLabel.Text = ("🏠 Placed <b>%d/%d</b>  ·  📦 Total %d/%d"):format(placed, slots, total, slots + GameConfig.Economy.InventoryCap)
		local dupes = InventoryController.DuplicateCandidates(all)
		Components.SetEnabled(dupBtn, #dupes > 0)
		refreshDetail()
	end

	-- actions
	Components.SetOnClick(placeBtn, function()
		local pet = selected and pets()[selected]
		if pet then
			petAction(if pet.Slot then "Store" else "Place", { pet.Uid })
		end
	end)
	Components.SetOnClick(lockBtn, function()
		local pet = selected and pets()[selected]
		if pet then
			petAction(if pet.Locked then "Unlock" else "Lock", { pet.Uid })
		end
	end)
	Components.SetOnClick(sellBtn, function()
		local pet = selected and pets()[selected]
		if not pet or pet.Locked then
			return
		end
		Components.Confirm({
			Title = "Sell pet?",
			Text = ("Sell <b>%s</b> for <font color=\"#FFCD32\">🪙 %s</font>?\nThis cannot be undone."):format(GameConfig.PetDisplayName(pet), Fmt(GameConfig.PetSellValue(pet))),
			ConfirmText = "💰 Sell",
			Danger = true,
			OnConfirm = function()
				petAction("Sell", { pet.Uid })
			end,
		})
	end)
	Components.SetOnClick(potionBtn, function()
		local pet = selected and pets()[selected]
		if not pet then
			return
		end
		Components.Confirm({
			Title = "Use Mutation Potion?",
			Text = ("Re-roll the mutation of <b>%s</b>.\nCurrent: %s. A potion never downgrades it."):format(GameConfig.PetDisplayName(pet), pet.Mutation or "none"),
			ConfirmText = "🧪 Use potion",
			OnConfirm = function()
				petAction("MutationPotion", { pet.Uid })
			end,
		})
	end)
	local function submitRename()
		local pet = selected and pets()[selected]
		local text = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if pet and text ~= (pet.Name or "") then
			petAction("Rename", { pet.Uid }, text) -- the server filters the text
		end
	end
	Components.SetOnClick(renameBtn, submitRename)
	nameBox.FocusLost:Connect(function(enter)
		if enter then
			submitRename()
		end
	end)
	Components.SetOnClick(dupBtn, function()
		local uids, value = InventoryController.DuplicateCandidates(pets())
		if #uids == 0 then
			Components.Toast("No duplicates to sell.", "info")
			return
		end
		Components.Confirm({
			Title = "Sell duplicates?",
			Text = ("Sell <b>%d</b> duplicate pet%s for about <font color=\"#FFCD32\">🪙 %s</font>.\nYour best copy of each species and every 🔒 locked pet are kept."):format(
				#uids,
				if #uids == 1 then "" else "s",
				Fmt(value)
			),
			ConfirmText = "🧹 Sell " .. #uids,
			Danger = true,
			OnConfirm = function()
				petAction("SellDuplicates", uids)
			end,
		})
	end)

	tabs.Select("All")
	win.DefaultSelection = tabs.Buttons.All
	win.OnOpen = rebuild
	ClientData.Observe({ "Pets", "Derived", "Items" }, function()
		rebuild()
	end)
end

return InventoryController

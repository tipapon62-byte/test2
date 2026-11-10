-- IndexController: the collection book. Per-biome grids of every species; discovered ones show
-- a 3D preview and count, undiscovered ones a dark silhouette with "???".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Client = script.Parent.Parent
local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local New = Components.New
local Text = Components.Text
local Rarities = GameConfig.Rarities
local Progression = GameConfig.Progression

local IndexController = {}

-- Species shown for a biome: all regular ones, event-only ones only once discovered.
function IndexController.SpeciesFor(biomeId: string, index): { any }
	local list = {}
	for _, s in ipairs(GameConfig.Pets) do
		if s.Biome == biomeId and (not s.EventOnly or index[s.Id]) then
			table.insert(list, s)
		end
	end
	table.sort(list, function(a, b)
		return Rarities.ById[a.Rarity].Index < Rarities.ById[b.Rarity].Index
	end)
	return list
end

function IndexController.Totals(index): (number, number)
	local found, total = 0, 0
	for _, s in ipairs(GameConfig.Pets) do
		if not s.EventOnly then
			total += 1
			if index[s.Id] then
				found += 1
			end
		end
	end
	return found, total
end

function IndexController.Start()
	local win = Components.Window("Index", "Rift Index", Theme.Icons.Index, { TitleColor = Theme.Buttons.Index })
	local body = win.Body

	local totalBar = Components.ProgressBar({ Size = UDim2.new(1, 0, 0, 30), TextSize = 18, Color = Theme.Colors.Accent, Parent = body })
	local current = GameConfig.Biomes[1].Id
	local tabDefs = {}
	for _, b in ipairs(GameConfig.Biomes) do
		table.insert(tabDefs, { Id = b.Id, Text = ("%d %s"):format(b.Index, b.Name) })
	end
	local biomeInfo = Text({
		Text = "",
		TextSize = 18,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(4, 98),
		Parent = body,
	})
	local gridHolder = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 130),
		Size = UDim2.new(1, 0, 1, -130),
		Parent = body,
	})
	local grid = Components.ScrollGrid(gridHolder, Vector2.new(152, 196), 10)

	local function render()
		if not win.IsOpen then
			return
		end
		local p = ClientData.Get()
		local index = p.Index or {}
		local found, total = IndexController.Totals(index)
		totalBar.Set(found / math.max(total, 1), ("📖 Discovered %d / %d species"):format(found, total))

		local biome = GameConfig.GetBiome(current)
		if not biome then
			return
		end
		local species = IndexController.SpeciesFor(current, index)
		local bFound, bTotal = 0, 0
		for _, s in ipairs(species) do
			if not s.EventOnly then
				bTotal += 1
				if index[s.Id] then
					bFound += 1
				end
			end
		end
		local done = p.IndexBiomesDone and p.IndexBiomesDone[current]
		biomeInfo.Text = ("<b>%s</b>  %d/%d found  ·  complete it for <font color=\"#6EDCFF\">💎 %d</font> %s"):format(
			biome.Name,
			bFound,
			bTotal,
			Progression.IndexBiomeCompleteShards,
			if done then "✅" else ""
		)

		Components.Clear(grid)
		for i, s in ipairs(species) do
			local entry = index[s.Id]
			local rarity = Rarities.ById[s.Rarity]
			local color = rarity.Color
			local card = Components.Card({ Color = if entry then Theme.Darken(color, 0.1) else Color3.fromRGB(40, 52, 96), LayoutOrder = i, Parent = grid })
			card.Name = s.Id
			Components.Selectable(card)
			if entry and rarity.Index >= 4 then
				Components.Shine(card)
			end
			Components.PetViewport({ Species = s.Id, Size = "Normal", Tier = 1 }, {
				Silhouette = entry == nil,
				Size = UDim2.new(1, -12, 0, 100),
				Position = UDim2.fromOffset(6, 6),
				Parent = card,
			})
			Text({
				Text = if entry then s.Name else "???",
				TextSize = 18,
				Size = UDim2.new(1, -8, 0, 24),
				Position = UDim2.fromOffset(4, 106),
				Parent = card,
			})
			Components.RarityBadge(s.Rarity, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 132),
				Size = UDim2.fromOffset(112, 24),
				Parent = card,
			})
			Text({
				Text = if entry then ("Owned x%d"):format(entry.Count or 1) else ("First find: 💎 %d"):format(rarity.IndexShards),
				TextSize = 15,
				TextColor3 = if entry then Theme.Colors.Good else Theme.Colors.Shards,
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 162),
				Parent = card,
			})
			if s.EventOnly then
				Text({ Text = "🌀 EVENT", TextSize = 13, TextColor3 = Theme.Colors.Accent, Size = UDim2.fromOffset(70, 18), Position = UDim2.fromOffset(6, 4), Parent = card })
			end
		end
	end

	local tabs = Components.Tabs(body, tabDefs, function(id)
		current = id
		render()
	end, { Position = UDim2.fromOffset(0, 38) })
	tabs.Select(current)
	win.DefaultSelection = tabs.Buttons[current]
	win.OnOpen = render
	ClientData.Observe({ "Index", "IndexBiomesDone" }, render)
end

return IndexController

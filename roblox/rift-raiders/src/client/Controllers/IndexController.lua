-- IndexController: the Multiverse Index. One tab per rift (= universe); every character of that
-- universe is shown next to its own egg. Discovered characters show a 3D preview and
-- how many you own; undiscovered ones are a dark silhouette with "???" (their egg is always shown
-- in full colour so players know what to look for in the nests).

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

-- Universe of each rift (used when a character has no Universe field of its own).
local UNIVERSE = {
	RiftLab = "Mad Science Universe",
	Mosswood = "Yellow Town Universe",
	GlimmerLake = "Bikini Deep Universe",
	Sunscorch = "Meme Universe",
	Vinewild = "Anime Dimension",
	Emberpeak = "Forge Universe",
	Frostveil = "Frozen Universe",
	AstralRuins = "Multiverse Core",
}

function IndexController.UniverseOf(biomeId: string): string
	for _, s in ipairs(GameConfig.Pets) do
		if s.Biome == biomeId and type(s.Universe) == "string" and s.Universe ~= "" then
			return s.Universe
		end
	end
	return UNIVERSE[biomeId] or "Unknown Universe"
end

local function rarityIdx(id: string?): number
	local r = id and Rarities.ById[id]
	return r and r.Index or 0
end

-- Characters shown for a biome: all regular ones, event-only ones only once discovered.
function IndexController.SpeciesFor(biomeId: string, index): { any }
	local list = {}
	for _, s in ipairs(GameConfig.Pets) do
		if s.Biome == biomeId and (not s.EventOnly or (index and index[s.Id])) then
			table.insert(list, s)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = rarityIdx(a.Rarity), rarityIdx(b.Rarity)
		if ra ~= rb then
			return ra < rb
		end
		return a.Name < b.Name
	end)
	return list
end

function IndexController.Totals(index): (number, number)
	local found, total = 0, 0
	for _, s in ipairs(GameConfig.Pets) do
		if not s.EventOnly then
			total += 1
			if index and index[s.Id] then
				found += 1
			end
		end
	end
	return found, total
end

local CELL = Vector2.new(196, 206)

function IndexController.Start()
	local win = Components.Window("Index", "Multiverse Index", Theme.Icons.Index, { TitleColor = Theme.Buttons.Index })
	local body = win.Body

	local totalBar = Components.ProgressBar({ Size = UDim2.new(1, 0, 0, 30), TextSize = 18, Color = Theme.Colors.Accent, Parent = body })
	local first = GameConfig.Biomes[1]
	local current = first and first.Id or "RiftLab"
	local tabDefs = {}
	for _, b in ipairs(GameConfig.Biomes) do
		table.insert(tabDefs, { Id = b.Id, Text = ("%d %s"):format(b.Index, b.Name) })
	end
	local biomeInfo = Text({
		Text = "",
		TextSize = 18,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -8, 0, 28),
		Position = UDim2.fromOffset(4, 98),
		Parent = body,
	})
	local gridHolder = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 130),
		Size = UDim2.new(1, 0, 1, -130),
		Parent = body,
	})
	local grid = Components.ScrollGrid(gridHolder, CELL, 10)
	local renderedKey = ""

	local function render()
		if not win.IsOpen then
			return
		end
		local p = ClientData.Get()
		local index = type(p.Index) == "table" and p.Index or {}
		local found, total = IndexController.Totals(index)
		totalBar.Set(found / math.max(total, 1), ("📖 Discovered %d / %d characters across the multiverse"):format(found, total))

		local biome = GameConfig.GetBiome(current)
		if not biome then
			return
		end
		local species = IndexController.SpeciesFor(current, index)
		local bFound, bTotal = 0, 0
		local keyParts = { current }
		for _, s in ipairs(species) do
			local e = index[s.Id]
			table.insert(keyParts, s.Id .. ":" .. tostring(e and (e.Count or 1) or 0))
			if not s.EventOnly then
				bTotal += 1
				if e then
					bFound += 1
				end
			end
		end
		local done = type(p.IndexBiomesDone) == "table" and p.IndexBiomesDone[current]
		biomeInfo.Text = ("<b>🌌 %s</b>  ·  %d/%d found  ·  complete it for <font color=\"#6EDCFF\">💎 %d</font> %s"):format(
			IndexController.UniverseOf(current),
			bFound,
			bTotal,
			Progression.IndexBiomeCompleteShards or 0,
			if done then "✅" else ""
		)

		-- rebuilding viewports is costly: only when this tab's content actually changed
		local key = table.concat(keyParts, "|")
		if key == renderedKey then
			return
		end
		renderedKey = key

		Components.Clear(grid)
		for i, s in ipairs(species) do
			local entry = index[s.Id]
			local rarity = Rarities.ById[s.Rarity] or Rarities.ById.Common
			local color = rarity.Color
			local card = Components.Card({ Color = if entry then Theme.Darken(color, 0.1) else Color3.fromRGB(40, 52, 96), LayoutOrder = i, Parent = grid })
			card.Name = s.Id
			Components.Selectable(card)
			if entry and rarity.Index >= 4 then
				Components.Shine(card)
			end
			-- character (left) + its egg (right)
			Components.PetViewport({ Species = s.Id, Size = "Normal", Tier = 1 }, {
				Silhouette = entry == nil,
				Size = UDim2.new(0.6, -6, 0, 108),
				Position = UDim2.fromOffset(4, 4),
				Parent = card,
			})
			local eggBubble = New("Frame", {
				Name = "EggBubble",
				BackgroundColor3 = Color3.fromRGB(16, 20, 48),
				BackgroundTransparency = 0.55,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 10),
				Size = UDim2.new(0.4, -6, 0, 96),
				Parent = card,
			})
			Components.Corner(eggBubble, 12)
			Components.EggViewport({ Species = s.Id, Biome = s.Biome, Rarity = s.Rarity }, { Size = UDim2.new(1, 0, 1, -16), Parent = eggBubble })
			Text({ Text = "🥚 egg", TextSize = 12, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16), Parent = eggBubble })
			Text({
				Text = if entry then s.Name else "???",
				TextSize = 17,
				TextWrapped = true,
				Size = UDim2.new(1, -8, 0, 40),
				Position = UDim2.fromOffset(4, 112),
				Parent = card,
			})
			Components.RarityBadge(s.Rarity, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 152),
				Size = UDim2.fromOffset(112, 24),
				Parent = card,
			})
			Text({
				Text = if entry then ("Owned x%d"):format(entry.Count or 1) else ("First find: 💎 %d"):format(rarity.IndexShards or 0),
				TextSize = 15,
				TextColor3 = if entry then Theme.Colors.Good else Theme.Colors.Shards,
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 180),
				Parent = card,
			})
			if s.EventOnly then
				Text({ Text = "🌀 EVENT", TextSize = 13, TextColor3 = Theme.Colors.Accent, Size = UDim2.fromOffset(70, 18), Position = UDim2.fromOffset(6, 4), ZIndex = 3, Parent = card })
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

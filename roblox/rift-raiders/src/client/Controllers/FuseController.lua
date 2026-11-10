-- FuseController: the Fuse Machine window. Pick 3 identical pets (same Species + Tier), ask the
-- server for a PreviewFuse, show exactly those 3 pets + result + chances + warnings, then send
-- Fuse(uids, token). Valuable inputs (NeedsDoubleConfirm) require a 2-second hold to confirm.

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

local FuseController = {}

local function groupKey(pet): string
	return pet.Species .. "#" .. tostring(pet.Tier or 1)
end

local function pctText(x: number?): string
	local v = (x or 0) * 100
	return if v < 1 and v > 0 then ("%.1f%%"):format(v) else ("%d%%"):format(math.floor(v + 0.5))
end

-- Picks the 3 cheapest unlocked copies of the first fusable group (or of `key` if given).
function FuseController.AutoPick(pets, key: string?): { string }?
	local groups = {}
	for uid, pet in pairs(pets) do
		if not pet.Locked and (pet.Tier or 1) < Rarities.MaxTier then
			local k = groupKey(pet)
			groups[k] = groups[k] or {}
			table.insert(groups[k], { Uid = pet.Uid or uid, Income = GameConfig.PetIncome(pet), Tier = pet.Tier or 1 })
		end
	end
	local bestKey, bestScore = nil, math.huge
	for k, list in pairs(groups) do
		if #list >= 3 and (key == nil or k == key) then
			table.sort(list, function(a, b)
				return a.Income < b.Income
			end)
			local score = list[1].Income + list[2].Income + list[3].Income
			if score < bestScore then
				bestKey, bestScore = k, score
			end
		end
	end
	if not bestKey then
		return nil
	end
	local list = groups[bestKey]
	return { list[1].Uid, list[2].Uid, list[3].Uid }
end

function FuseController.Start()
	local win = Components.Window("Fuse", "Fuse Machine", Theme.Icons.Fuse, { TitleColor = Theme.Buttons.Fuse })
	local body = win.Body

	-- ===== left: picker =====
	local left = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 372, 1, 0), Parent = body })
	Text({
		Text = "Pick 3 identical characters\n(same character & tier)",
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -170, 0, 50),
		Position = UDim2.fromOffset(4, 0),
		Parent = left,
	})
	local autoBtn = Components.Button({
		Text = "✨ Auto-pick 3",
		TextSize = 18,
		Color = Theme.Colors.Info,
		Size = UDim2.fromOffset(164, 50),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = left,
	})
	local picker = Components.ScrollGrid(left, Vector2.new(106, 132), 8, {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
	})

	-- ===== right: preview =====
	local right = Components.Card({
		Color = Theme.Colors.WindowDark,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, -384, 1, 0),
		Parent = body,
	})
	local inputsRow = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 150), Parent = right })
	Components.List(inputsRow, 8, true, Enum.HorizontalAlignment.Center)
	local resultBox = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 162), Size = UDim2.new(1, -20, 0, 66), Parent = right })
	local resultText = Text({ Text = "", TextSize = 18, RichText = true, Parent = resultBox })
	local notes = Components.ScrollList(right, 2, {
		Position = UDim2.fromOffset(6, 230),
		Size = UDim2.new(1, -12, 1, -230 - 80),
	})
	local notesText = Text({
		Text = "",
		TextSize = 15,
		Font = Theme.FontBody,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = notes,
	})
	local fuseBtn = Components.Button({
		Text = "🔮 FUSE",
		TextSize = 24,
		Color = Theme.Colors.Accent2,
		Size = UDim2.new(1, -20, 0, Theme.ButtonHeight),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Parent = right,
	})
	Components.SetEnabled(fuseBtn, false)

	local selection: { string } = {}
	local preview: any = nil
	local requestId = 0
	local pickerCards: { [string]: any } = {}

	local function pets()
		return ClientData.Get().Pets or {}
	end

	local function inputCard(pet, order: number)
		local rarity = (GameConfig.GetSpecies(pet.Species) or {}).Rarity
		local color = Theme.Rarity(rarity)
		local card = Components.Card({ Color = Theme.Darken(color, 0.55), Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = order, Parent = inputsRow })
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
		Components.PetViewport(pet, { Size = UDim2.new(1, -8, 0, 64), Position = UDim2.fromOffset(4, 2), Parent = card })
		Text({
			Text = ("%s%s\n<font color=\"#FFCD32\">🪙 %s/s</font>\n%s · %s"):format(
				if pet.Locked then "🔒 " else "",
				GameConfig.PetDisplayName(pet),
				Fmt(GameConfig.PetIncome(pet)),
				pet.Size or "Normal",
				pet.Mutation or "no mutation"
			),
			RichText = true,
			TextSize = 13,
			Font = Theme.FontBody,
			Size = UDim2.new(1, -6, 1, -68),
			Position = UDim2.fromOffset(3, 66),
			Parent = card,
		})
	end

	local function emptySlot(order: number)
		local card = Components.Card({ Color = Theme.Colors.Panel, Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = order, Transparency = 0.4, Parent = inputsRow })
		Text({ Text = "?", TextSize = 48, TextColor3 = Theme.Colors.TextDim, Parent = card })
	end

	local function renderPreview()
		Components.Clear(inputsRow)
		if preview and preview.Ok and preview.Inputs then
			-- exactly what the server will consume
			for i, pet in ipairs(preview.Inputs) do
				inputCard(pet, i)
			end
		else
			local all = pets()
			for i = 1, 3 do
				local pet = selection[i] and all[selection[i]]
				if pet then
					inputCard(pet, i)
				else
					emptySlot(i)
				end
			end
		end

		local lines = {}
		if #selection < 3 then
			resultText.Text = ("Select <b>%d</b> more character%s"):format(3 - #selection, if 3 - #selection == 1 then "" else "s")
			Components.SetEnabled(fuseBtn, false)
			Components.SetText(fuseBtn, "🔮 FUSE")
		elseif not preview then
			resultText.Text = "Checking the machine..."
			Components.SetEnabled(fuseBtn, false)
		elseif not preview.Ok then
			resultText.Text = ("<font color=\"#%s\">%s</font>"):format(Theme.Colors.Bad:ToHex(), preview.Error or "These characters can't be fused.")
			Components.SetEnabled(fuseBtn, false)
		else
			local r = preview.Result or {}
			local species = GameConfig.GetSpecies(r.Species)
			resultText.Text = ("⬇️ <b>%s</b> %s  (Tier %d)\n<font color=\"#FFCD32\">🪙 %s/s  →  🪙 %s/s</font>   cost 🪙 %s"):format(
				species and species.Name or tostring(r.Species),
				string.rep(Theme.Icons.Star, math.max((r.Tier or 2) - 1, 0)),
				r.Tier or 0,
				Fmt(r.IncomeBefore or 0),
				Fmt(r.IncomeAfter or 0),
				Fmt(r.Cost or 0)
			)
			local ch = preview.Chances or {}
			table.insert(lines, ("🎲 Mutation %s  ·  Bigger size %s  ·  Bonus egg %s"):format(pctText(ch.Mutation), pctText(ch.Size), pctText(ch.BonusEgg)))
			for _, w in ipairs(preview.Warnings or {}) do
				table.insert(lines, ("<font color=\"#%s\">⚠️ %s</font>"):format(Theme.Colors.Bad:ToHex(), w))
			end
			local coins = player:GetAttribute("Coins") or ClientData.Get().Coins or 0
			local affordable = coins >= (r.Cost or 0)
			if not affordable then
				table.insert(lines, ("<font color=\"#%s\">Not enough coins.</font>"):format(Theme.Colors.Bad:ToHex()))
			end
			Components.SetText(fuseBtn, (if preview.NeedsDoubleConfirm then "⚠️ " else "🔮 ") .. "FUSE · " .. Components.Price("Coins", r.Cost or 0))
			Components.SetEnabled(fuseBtn, preview.Token ~= nil and affordable)
		end
		table.insert(lines, "<i>Fusion is permanent: the 3 characters are consumed. 🔒 Locked characters can't be used.</i>")
		notesText.Text = table.concat(lines, "\n")
	end

	local function requestPreview()
		preview = nil
		requestId += 1
		local myId = requestId
		renderPreview()
		if #selection ~= 3 then
			return
		end
		local uids = table.clone(selection)
		task.spawn(function()
			local fn = Net.Function("PreviewFuse")
			local ok, res = pcall(fn.InvokeServer, fn, uids)
			if myId ~= requestId then
				return -- selection changed meanwhile
			end
			if ok and type(res) == "table" then
				preview = res
			else
				preview = { Ok = false, Error = "The machine didn't answer. Try again." }
			end
			renderPreview()
		end)
	end

	local function refreshPickerHighlight()
		local first = selection[1] and pets()[selection[1]]
		local key = first and groupKey(first)
		for uid, c in pairs(pickerCards) do
			local isSel = table.find(selection, uid) ~= nil
			c.Stroke.Thickness = if isSel then 5 else 3
			c.Stroke.Color = if isSel then Theme.Colors.Accent elseif c.Locked then Theme.Colors.Stroke else c.Color
			c.Check.Visible = isSel
			c.Frame.BackgroundTransparency = if key and c.Key ~= key and not isSel then 0.6 else 0
		end
	end

	local function toggle(uid: string)
		local all = pets()
		local pet = all[uid]
		if not pet then
			return
		end
		if pet.Locked then
			Components.Toast("🔒 Unlock this character in the Characters window before fusing it.", "warn")
			return
		end
		local idx = table.find(selection, uid)
		if idx then
			table.remove(selection, idx)
		else
			local first = selection[1] and all[selection[1]]
			if first and groupKey(first) ~= groupKey(pet) then
				selection = { uid } -- different species/tier starts a new pick
			elseif #selection < 3 then
				table.insert(selection, uid)
			end
		end
		refreshPickerHighlight()
		requestPreview()
	end

	local function buildPicker()
		Components.Clear(picker)
		pickerCards = {}
		local all = pets()
		local counts = {}
		for _, pet in pairs(all) do
			local k = groupKey(pet)
			counts[k] = (counts[k] or 0) + 1
		end
		local list = {}
		for uid, pet in pairs(all) do
			pet.Uid = pet.Uid or uid
			if (pet.Tier or 1) < Rarities.MaxTier then
				table.insert(list, pet)
			end
		end
		table.sort(list, function(a, b)
			local ka, kb = groupKey(a), groupKey(b)
			local fa, fb = (counts[ka] or 0) >= 3, (counts[kb] or 0) >= 3
			if fa ~= fb then
				return fa
			end
			if ka ~= kb then
				return ka < kb
			end
			return GameConfig.PetIncome(a) < GameConfig.PetIncome(b)
		end)
		for i, pet in ipairs(list) do
			local rarity = (GameConfig.GetSpecies(pet.Species) or {}).Rarity
			local color = Theme.Rarity(rarity)
			local card = New("TextButton", {
				Name = pet.Uid,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = color,
				LayoutOrder = i,
				Parent = picker,
			})
			Components.Selectable(card)
			Components.Corner(card, 12)
			Components.Gradient(card, Theme.Lighten(color, 0.15), Theme.Darken(color, 0.4))
			local stroke = Components.Stroke(card, Theme.Colors.Stroke, 4)
			Components.Squash(card)
			Components.PetViewport(pet, { Size = UDim2.new(1, -8, 0, 70), Position = UDim2.fromOffset(4, 2), Parent = card })
			Text({
				Text = GameConfig.PetDisplayName(pet),
				TextSize = 13,
				Size = UDim2.new(1, -6, 0, 32),
				Position = UDim2.fromOffset(3, 72),
				Parent = card,
			})
			Text({
				Text = ("x%d owned"):format(counts[groupKey(pet)] or 1),
				TextSize = 13,
				TextColor3 = if (counts[groupKey(pet)] or 0) >= 3 then Theme.Colors.Good else Theme.Colors.TextDim,
				Size = UDim2.new(1, 0, 0, 20),
				Position = UDim2.fromOffset(0, 106),
				Parent = card,
			})
			if pet.Locked then
				Text({ Text = Theme.Icons.Lock, TextSize = 18, Outline = false, Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(3, 3), Parent = card })
			end
			local check = New("Frame", {
				BackgroundColor3 = Theme.Colors.Accent,
				Size = UDim2.fromOffset(26, 26),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -3, 0, 3),
				Visible = false,
				Parent = card,
			})
			Components.CornerScale(check, 0.5)
			Components.Stroke(check, Theme.Colors.Stroke, 2)
			Text({ Text = "✓", TextSize = 18, Parent = check })
			card.Activated:Connect(function()
				toggle(pet.Uid)
			end)
			pickerCards[pet.Uid] = { Frame = card, Stroke = stroke, Color = Theme.Colors.Stroke, Check = check, Key = groupKey(pet), Locked = pet.Locked }
		end
		refreshPickerHighlight()
	end

	Components.SetOnClick(autoBtn, function()
		local all = pets()
		local first = selection[1] and all[selection[1]]
		local pick = FuseController.AutoPick(all, first and groupKey(first) or nil) or FuseController.AutoPick(all, nil)
		if not pick then
			Components.Toast("You need 3 unlocked copies of the same character and tier.", "warn")
			return
		end
		selection = pick
		refreshPickerHighlight()
		requestPreview()
	end)

	Components.SetOnClick(fuseBtn, function()
		local p = preview
		if not (p and p.Ok and p.Token) or #selection ~= 3 then
			return
		end
		local uids = table.clone(selection)
		local token = p.Token
		local function send()
			Net.Event("Fuse"):FireServer(uids, token)
			selection = {}
			preview = nil
			requestId += 1
			refreshPickerHighlight()
			renderPreview()
		end
		local names = {}
		for _, pet in ipairs(p.Inputs or {}) do
			table.insert(names, "• " .. GameConfig.PetDisplayName(pet) .. "  (🪙 " .. Fmt(GameConfig.PetIncome(pet)) .. "/s)")
		end
		local warnings = {}
		for _, w in ipairs(p.Warnings or {}) do
			table.insert(warnings, ("<font color=\"#%s\">⚠️ %s</font>"):format(Theme.Colors.Bad:ToHex(), w))
		end
		local text = "These characters will be consumed <b>forever</b>:\n" .. table.concat(names, "\n") .. (if #warnings > 0 then "\n" .. table.concat(warnings, "\n") else "")
		local settings = ClientData.Get().Settings or {}
		if p.NeedsDoubleConfirm then
			Components.Confirm({
				Title = "⚠️ Valuable fusion",
				Text = text,
				Height = 380,
				Danger = true,
				HoldSeconds = 2,
				ConfirmText = "Hold 2s to FUSE",
				OnConfirm = send,
			})
		elseif settings.ConfirmFuse ~= false then
			Components.Confirm({
				Title = "Fuse these characters?",
				Text = text,
				Height = 360,
				ConfirmText = "🔮 Fuse",
				OnConfirm = send,
			})
		else
			send()
		end
	end)

	win.DefaultSelection = autoBtn
	win.OnOpen = function()
		buildPicker()
		renderPreview()
	end
	win.OnClose = function()
		selection = {}
		preview = nil
		requestId += 1
	end

	ClientData.Observe({ "Pets" }, function()
		if not win.IsOpen then
			return
		end
		-- drop selected pets that vanished or became locked
		local all = pets()
		local changed = false
		for i = #selection, 1, -1 do
			local pet = all[selection[i]]
			if not pet or pet.Locked then
				table.remove(selection, i)
				changed = true
			end
		end
		buildPicker()
		if changed then
			requestPreview()
		else
			renderPreview()
		end
	end)
	ClientData.Observe({ "Coins" }, function()
		if win.IsOpen and preview then
			renderPreview()
		end
	end)
end

return FuseController

-- NotificationController: Notify toasts, server-wide Announce banners (+ chat system message) and
-- the visual side of Effect events: hatch reveal, fuse result, discoveries, biome unlocks,
-- floating coins, event banners, tagged/trapped screen flashes and rebirth celebration.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
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

local player = Players.LocalPlayer

local NotificationController = {}

local function escape(s: string): string
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function lowGraphics(): boolean
	return player:GetAttribute("LowGraphics") == true
end

local function notificationsOn(): boolean
	local s = ClientData.Get().Settings
	return not (s and s.Notifications == false)
end

-- ===== Toasts =====
function NotificationController.Notify(text: string, kind: string?)
	kind = kind or "info"
	if kind ~= "bad" and not notificationsOn() then
		return
	end
	Components.Toast(escape(text), kind)
end

-- ===== Banners (queued) =====
local bannerQueue: { any } = {}
local bannerBusy = false

local function runBanners()
	if bannerBusy then
		return
	end
	bannerBusy = true
	task.spawn(function()
		local root = Components.Layer("Toasts")
		while #bannerQueue > 0 do
			local b = table.remove(bannerQueue, 1)
			local frame = New("Frame", {
				Name = "Banner",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, -140),
				Size = UDim2.fromOffset(720, 96),
				BackgroundColor3 = b.Color,
				Parent = root,
			})
			Components.Corner(frame, 24)
			Components.Gradient(frame, Theme.Lighten(b.Color, 0.2), Theme.Darken(b.Color, 0.35))
			Components.Stroke(frame, Theme.Colors.Stroke, 5)
			Text({
				Text = b.Title,
				TextSize = 34,
				Font = Theme.FontHeavy,
				Outline = 3,
				RichText = true,
				Size = UDim2.new(1, -24, 0, if b.Sub then 52 else 92),
				Position = UDim2.fromOffset(12, 2),
				Parent = frame,
			})
			if b.Sub then
				Text({ Text = b.Sub, TextSize = 20, RichText = true, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 54), Parent = frame })
			end
			TweenService:Create(frame, Theme.Tween.Pop, { Position = UDim2.new(0.5, 0, 0, 120) }):Play()
			task.wait(b.Duration or 3.5)
			local t = TweenService:Create(frame, Theme.Tween.Smooth, { Position = UDim2.new(0.5, 0, 0, -140) })
			t:Play()
			t.Completed:Wait()
			frame:Destroy()
		end
		bannerBusy = false
	end)
end

function NotificationController.Banner(title: string, sub: string?, color: Color3?, duration: number?)
	table.insert(bannerQueue, { Title = title, Sub = sub, Color = color or Theme.Colors.Accent2, Duration = duration })
	if #bannerQueue > 4 then
		table.remove(bannerQueue, 1)
	end
	runBanners()
end

local function chatSystemMessage(text: string, color: Color3)
	task.spawn(function()
		pcall(function()
			local channels = TextChatService:WaitForChild("TextChannels", 5)
			local general = channels and channels:WaitForChild("RBXGeneral", 5)
			if general and general:IsA("TextChannel") then
				general:DisplaySystemMessage(('<font color="#%s"><b>[Rift]</b> %s</font>'):format(color:ToHex(), escape(text)))
			end
		end)
	end)
end

function NotificationController.Announce(text: string, color: Color3?)
	local c = if typeof(color) == "Color3" then color else Theme.Colors.Gold
	NotificationController.Banner("📣 " .. escape(text), nil, c, 4.5)
	chatSystemMessage(text, c)
end

-- ===== Screen flash + big centre text =====
local function flash(color: Color3, text: string?, duration: number?)
	local root = Components.Layer("Toasts")
	local f = New("Frame", {
		Name = "Flash",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = root,
	})
	TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	task.delay(0.7, function()
		f:Destroy()
	end)
	if text then
		local label = Text({
			Text = text,
			TextSize = 56,
			Font = Theme.FontHeavy,
			Outline = 4,
			RichText = true,
			TextColor3 = Theme.Lighten(color, 0.3),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromOffset(800, 120),
			Parent = root,
		})
		Components.Pop(label, 0.3)
		task.delay(duration or 1.6, function()
			TweenService:Create(label, Theme.Tween.Smooth, { TextTransparency = 1 }):Play()
			task.wait(0.3)
			label:Destroy()
		end)
		return label
	end
	return nil
end

-- ===== Floating "+N coins" =====
local function floatCoins(amount: number)
	if not notificationsOn() then
		return
	end
	local root = Components.Layer("Toasts")
	local label = Text({
		Text = "+🪙 " .. Fmt(amount),
		TextSize = 34,
		Font = Theme.FontHeavy,
		Outline = 3,
		TextColor3 = Theme.Colors.Coins,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-120, 120), 0.45, 0),
		Size = UDim2.fromOffset(300, 50),
		Parent = root,
	})
	Components.Pop(label, 0.4)
	TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -260, 0, 30),
		TextTransparency = 1,
	}):Play()
	task.delay(1.5, function()
		label:Destroy()
	end)
end

-- ===== Reveal popups (hatch / fuse), shown one at a time =====
local popupQueue: { () -> () } = {}
local popupBusy = false

local function runPopups()
	if popupBusy then
		return
	end
	popupBusy = true
	task.spawn(function()
		while #popupQueue > 0 do
			local fn = table.remove(popupQueue, 1)
			local ok, err = pcall(fn)
			if not ok then
				warn("[Notification] popup failed:", err)
			end
		end
		popupBusy = false
	end)
end

local function enqueuePopup(fn: () -> ())
	table.insert(popupQueue, fn)
	runPopups()
end

local function rays(parent, color: Color3): any
	local burst = New("Frame", {
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(620, 620),
		Parent = parent,
	})
	for i = 1, 12 do
		local ray = New("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(46, 620),
			Rotation = i * 15,
			Parent = burst,
		})
		New("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 90,
			Parent = ray,
		})
	end
	if not lowGraphics() then
		TweenService:Create(burst, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
	end
	return burst
end

-- Shows the pet card part of a reveal and waits until the player closes it (or it times out).
local function revealCard(modal, pet, headline: string, tags: { string }, isNew: boolean?)
	if not modal.Frame.Parent then
		return -- dismissed (B / back) during the egg animation
	end
	local species = GameConfig.GetSpecies(pet.Species)
	local rarity = species and species.Rarity or "Common"
	local color = Theme.Rarity(rarity)
	local stage = modal.Frame
	rays(stage, color)
	local panel = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 540),
		Parent = stage,
	})
	Text({ Text = headline, TextSize = 40, Font = Theme.FontHeavy, Outline = 4, TextColor3 = color, Size = UDim2.new(1, 0, 0, 52), Parent = panel })
	Components.PetViewport(pet, { Spin = true, Size = UDim2.fromOffset(280, 230), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Parent = panel })
	Text({ Text = GameConfig.PetDisplayName(pet), TextSize = 34, Outline = 3, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 290), Parent = panel })
	Components.RarityBadge(rarity, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 338), Size = UDim2.fromOffset(160, 32), Parent = panel })
	Text({
		Text = ("🪙 %s/s  ·  %s  ·  %.1f kg"):format(Fmt(GameConfig.PetIncome(pet)), pet.Mutation or "No mutation", pet.Kg or 0),
		TextSize = 22,
		TextColor3 = Theme.Colors.Coins,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 376),
		Parent = panel,
	})
	if #tags > 0 then
		Text({ Text = table.concat(tags, "   "), TextSize = 22, RichText = true, TextColor3 = Theme.Colors.Accent, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 408), Parent = panel })
	end
	if isNew then
		local badge = New("Frame", { BackgroundColor3 = Theme.Colors.Bad, Rotation = -12, Size = UDim2.fromOffset(120, 48), Position = UDim2.new(0.5, 90, 0, 60), Parent = panel })
		Components.Corner(badge, 14)
		Components.Stroke(badge, Theme.Colors.Stroke, 4)
		Text({ Text = "NEW!", TextSize = 30, Font = Theme.FontHeavy, Outline = 3, Parent = badge })
		Components.Pop(badge, 0.2)
	end
	local closed = Instance.new("BindableEvent")
	local btn = Components.Button({
		Text = "Awesome!",
		TextSize = 28,
		Color = Theme.Colors.Good,
		Size = UDim2.fromOffset(260, 66),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Parent = panel,
		OnClick = function()
			modal.Close()
		end,
	})
	Components.Pop(panel, 0.4)
	Components.Select(btn)
	local done = false
	modal.OnDone = function()
		if not done then
			done = true
			closed:Fire()
		end
	end
	task.delay(8, function()
		modal.Close()
	end)
	if modal.Frame.Parent then
		closed.Event:Wait()
	end
	closed:Destroy()
end

local function newModal(): any
	local holder: any = {}
	local modal = Components.Modal(function()
		if holder.OnDone then
			holder.OnDone()
		end
	end, false)
	holder.Frame = modal.Frame
	holder.Close = modal.Close
	return holder
end

function NotificationController.ShowHatch(pet, isNew: boolean?)
	enqueuePopup(function()
		local species = GameConfig.GetSpecies(pet.Species)
		local rarity = species and species.Rarity or "Common"
		local color = Theme.Rarity(rarity)
		local biome = species and GameConfig.GetBiome(species.Biome)
		local eggColors = biome and biome.EggColors or { Color3.new(1, 1, 1), color }
		local modal = newModal()
		local stage = modal.Frame

		-- egg shakes harder and harder, then cracks
		local egg = New("Frame", {
			Name = "Egg",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(170, 220),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = stage,
		})
		Components.CornerScale(egg, 0.5)
		New("UIGradient", { Color = ColorSequence.new(eggColors[1], eggColors[2] or eggColors[1]), Rotation = 90, Parent = egg })
		New("UIStroke", { Color = color, Thickness = 6, Parent = egg })
		Components.Pop(egg, 0.3)
		Text({ Text = "?", TextSize = 72, Font = Theme.FontHeavy, Outline = 4, TextColor3 = color, Parent = egg })
		task.wait(0.35)
		local shakes = if lowGraphics() then 4 else 9
		for i = 1, shakes do
			local amp = 6 + i * 2.5
			TweenService:Create(egg, TweenInfo.new(0.07), { Rotation = if i % 2 == 0 then amp else -amp }):Play()
			task.wait(0.07)
		end
		if not stage.Parent then
			return
		end
		egg.Rotation = 0
		-- crack: two halves fly apart
		local halves = {}
		for side = -1, 1, 2 do
			local half = New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = egg.Position,
				Size = UDim2.fromOffset(170, 110),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = stage,
			})
			Components.CornerScale(half, 0.5)
			New("UIGradient", { Color = ColorSequence.new(eggColors[1], eggColors[2] or eggColors[1]), Rotation = 90, Parent = half })
			New("UIStroke", { Color = color, Thickness = 6, Parent = half })
			table.insert(halves, half)
			TweenService:Create(half, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, side * 260, 0.45, side * -140),
				Rotation = side * 70,
				BackgroundTransparency = 1,
			}):Play()
		end
		egg:Destroy()
		flash(color, nil)
		task.delay(0.6, function()
			for _, h in ipairs(halves) do
				h:Destroy()
			end
		end)
		local headline = if GameConfig.Rarities.ById[rarity] and GameConfig.Rarities.ById[rarity].Index >= 5 then "✨ " .. string.upper(rarity) .. "! ✨" else "You hatched..."
		revealCard(modal, pet, headline, {}, isNew)
	end)
end

function NotificationController.ShowFuse(data)
	enqueuePopup(function()
		local modal = newModal()
		local tags = {}
		if data.MutationUp then
			table.insert(tags, "🧬 Mutation up!")
		end
		if data.SizeUp then
			table.insert(tags, "📏 Size up!")
		end
		if type(data.BonusEgg) == "table" then
			table.insert(tags, "🥚 Bonus: " .. GameConfig.EggDisplayName(data.BonusEgg))
		end
		flash(Theme.Colors.Accent2, nil)
		revealCard(modal, data.Pet, "🔮 FUSION COMPLETE!", tags, false)
	end)
end

local function confetti(colorA: Color3, colorB: Color3)
	if lowGraphics() then
		return
	end
	local root = Components.Layer("Toasts")
	for i = 1, 40 do
		local piece = New("Frame", {
			BackgroundColor3 = if i % 2 == 0 then colorA else colorB,
			Size = UDim2.fromOffset(math.random(10, 18), math.random(14, 24)),
			Position = UDim2.new(math.random(), 0, 0, -30),
			Rotation = math.random(0, 360),
			Parent = root,
		})
		local fall = TweenService:Create(piece, TweenInfo.new(math.random(18, 32) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
			Rotation = piece.Rotation + math.random(-360, 360),
		})
		fall:Play()
		fall.Completed:Connect(function()
			piece:Destroy()
		end)
	end
end

-- ===== Effect dispatcher =====
local handlers: { [string]: (any) -> () } = {
	Hatch = function(d)
		if type(d.Pet) == "table" then
			NotificationController.ShowHatch(d.Pet, d.New)
		end
	end,
	Fuse = function(d)
		if type(d.Pet) == "table" then
			NotificationController.ShowFuse(d)
		end
	end,
	Discovery = function(d)
		local s = GameConfig.GetSpecies(d.Species)
		Components.Toast(("📖 New species: <b>%s</b>  +💎 %s"):format(escape(s and s.Name or tostring(d.Species)), Fmt(d.Shards or 0)), "good", 4)
	end,
	Unlock = function(d)
		local b = GameConfig.GetBiome(d.Biome)
		local color = b and b.Theme.Accent or Theme.Colors.Accent
		NotificationController.Banner("🔓 RIFT UNLOCKED!", escape(b and (b.Name .. " — " .. b.Tagline) or tostring(d.Biome)), color, 4)
	end,
	Coins = function(d)
		if (d.Amount or 0) > 0 then
			floatCoins(d.Amount)
		end
	end,
	Event = function(d)
		if d.Id then
			local cfg = GameConfig.Progression.Events[d.Id]
			local name = d.Name or (cfg and cfg.Name) or d.Id
			local left = d.EndsAt and math.max(d.EndsAt - Components.Now(), 0) or (cfg and cfg.Duration) or 0
			NotificationController.Banner(Theme.Icons.Event .. " " .. escape(name) .. " started!", "Ends in " .. GameConfig.FormatTime(left), cfg and cfg.Color or Theme.Colors.Accent, 4)
		else
			NotificationController.Banner("Event over", "Thanks for raiding!", Theme.Colors.PanelLight, 2.5)
		end
	end,
	Tagged = function(d)
		flash(Theme.Colors.Bad, "💥 TAGGED" .. (if d.By then " by " .. escape(d.By) else "") .. "!", 1.6)
	end,
	Trapped = function(d)
		local duration = tonumber(d.Duration) or GameConfig.Settings.TrapStunTime
		local label = flash(Theme.Colors.Warn, "🪤 TRAPPED!", duration)
		if label then
			task.spawn(function()
				local endsAt = os.clock() + duration
				while label.Parent and os.clock() < endsAt do
					label.Text = ("🪤 TRAPPED! %.1f"):format(endsAt - os.clock())
					task.wait(0.1)
				end
			end)
		end
	end,
	Rebirth = function(d)
		NotificationController.Banner(("🔄 REBIRTH #%d!"):format(d.Rebirths or 1), "Your income is now permanently boosted!", Theme.Colors.Gold, 5)
		confetti(Theme.Colors.Gold, Theme.Colors.Accent)
	end,
}

function NotificationController.Start()
	Net.Event("Notify").OnClientEvent:Connect(function(text, kind)
		if type(text) == "string" then
			NotificationController.Notify(text, if type(kind) == "string" then kind else "info")
		end
	end)
	Net.Event("Announce").OnClientEvent:Connect(function(text, color)
		if type(text) == "string" then
			NotificationController.Announce(text, color)
		end
	end)
	Net.Event("Effect").OnClientEvent:Connect(function(name, data)
		local h = type(name) == "string" and handlers[name]
		if h then
			local ok, err = pcall(h, if type(data) == "table" then data else {})
			if not ok then
				warn("[Notification] effect", name, err)
			end
		end
	end)
end

return NotificationController

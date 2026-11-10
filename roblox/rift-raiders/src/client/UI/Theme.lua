-- Theme: colours, fonts, icons and tween presets for the whole client UI.
-- Look: bright "simulator" style — flat vivid colours, chunky rounded fonts, white text with a
-- thick dark outline, thick dark strokes around every button and card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local C = Color3.fromRGB

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.FontHeavy = Enum.Font.LuckiestGuy -- big titles / numbers
Theme.FontBody = Enum.Font.FredokaOne

Theme.Colors = {
	Backdrop = C(8, 12, 35),
	Window = C(70, 150, 255), -- window body (bright sky blue)
	WindowDark = C(34, 92, 205),
	Panel = C(44, 112, 226), -- inset cards inside windows
	PanelLight = C(120, 190, 255),
	Card = C(255, 255, 255),
	Stroke = C(16, 20, 48), -- the thick dark outline used everywhere
	Text = C(255, 255, 255),
	TextDim = C(222, 236, 255),
	TextDark = C(24, 30, 62),
	Accent = C(255, 205, 30), -- highlight yellow (selected tab, selection ring)
	Accent2 = C(175, 95, 255),
	Good = C(70, 215, 70),
	Bad = C(245, 60, 60),
	Warn = C(255, 170, 30),
	Info = C(30, 170, 255),
	Disabled = C(140, 146, 168),
	Coins = C(255, 214, 40),
	Shards = C(90, 225, 255),
	Speed = C(255, 236, 60),
	Income = C(130, 255, 90),
	Gold = C(255, 210, 60),
	Badge = C(240, 40, 50),
	PillBg = C(16, 20, 48), -- translucent HUD pills
}

-- Button palette for the HUD (matches the reference: green shop, cyan index...).
Theme.Buttons = {
	Shop = C(70, 215, 70),
	Pets = C(255, 150, 40),
	Index = C(30, 190, 255),
	Fuse = C(175, 95, 255),
	Quests = C(255, 85, 160),
	Ranks = C(255, 200, 30),
	Rebirth = C(0, 215, 170),
	Settings = C(150, 160, 185),
	Hatch = C(255, 120, 60),
}

-- Notification kind -> colour.
Theme.Kind = {
	info = Theme.Colors.Info,
	good = Theme.Colors.Good,
	bad = Theme.Colors.Bad,
	warn = Theme.Colors.Warn,
}

Theme.Icons = {
	Coins = "🪙",
	Shards = "💎",
	Speed = "⚡",
	Income = "📈",
	Egg = "🥚",
	Hatch = "🐣",
	Shield = "🛡️",
	Lock = "🔒",
	Check = "✅",
	Shop = "🛒",
	Pets = "🐾",
	Index = "📖",
	Fuse = "🔮",
	Daily = "🎁",
	Quests = "📜",
	Leaderboard = "🏆",
	Rebirth = "🔄",
	Settings = "⚙️",
	Close = "✕",
	Trap = "🪤",
	Decoy = "🐔",
	Bat = "🏏",
	Drop = "⬇️",
	Event = "🌙",
	Star = "★",
	Shoe = "👟",
	Home = "🏠",
}

Theme.Corner = 14
Theme.Stroke = 4

-- Virtual design resolution. Every ScreenGui root is uniformly scaled so this fits the screen.
Theme.Design = Vector2.new(1100, 620)
Theme.MaxScale = { Desktop = 1.35, Console = 2.0, Touch = 1.8 }
Theme.MinScale = 0.45
Theme.TouchBoost = 1.1 -- slightly larger UI on touch screens so targets stay >= 44 px

Theme.WindowSize = Vector2.new(880, 500)
Theme.ButtonHeight = 64

Theme.Tween = {
	Pop = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	Bounce = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
}

function Theme.Rarity(rarity: string?): Color3
	local r = rarity and GameConfig.Rarities.ById[rarity]
	return r and r.Color or Theme.Colors.TextDim
end

function Theme.RarityIndex(rarity: string?): number
	local r = rarity and GameConfig.Rarities.ById[rarity]
	return r and r.Index or 0
end

function Theme.Mutation(mutation: string?): Color3?
	local m = mutation and GameConfig.Rarities.Mutations[mutation]
	return m and m.Color or nil
end

function Theme.Darken(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), f)
end

function Theme.Lighten(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), f)
end

-- Readable text colour on top of `bg`.
function Theme.TextOn(bg: Color3): Color3
	local lum = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
	return if lum > 0.72 then Theme.Colors.TextDark else Theme.Colors.Text
end

return Theme

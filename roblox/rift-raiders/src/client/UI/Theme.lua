-- Theme: colours, fonts, icons and tween presets for the whole client UI (chunky cartoon style).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local C = Color3.fromRGB

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.FontHeavy = Enum.Font.GothamBlack
Theme.FontBody = Enum.Font.GothamBold

Theme.Colors = {
	Backdrop = C(10, 8, 30),
	Window = C(48, 38, 110),
	WindowDark = C(30, 22, 75),
	Panel = C(70, 58, 150),
	PanelLight = C(95, 82, 185),
	Card = C(255, 255, 255),
	Stroke = C(18, 12, 45),
	Text = C(255, 255, 255),
	TextDim = C(200, 195, 235),
	TextDark = C(30, 25, 60),
	Accent = C(0, 235, 175), -- rift green
	Accent2 = C(170, 90, 255), -- rift purple
	Good = C(70, 215, 90),
	Bad = C(240, 70, 80),
	Warn = C(255, 185, 40),
	Info = C(70, 160, 255),
	Disabled = C(120, 118, 140),
	Coins = C(255, 205, 50),
	Shards = C(110, 220, 255),
	Speed = C(120, 255, 140),
	Income = C(255, 150, 60),
	Gold = C(255, 215, 80),
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
	Shield = "🛡️",
	Lock = "🔒",
	Check = "✅",
	Shop = "🛒",
	Pets = "🐾",
	Index = "📖",
	Fuse = "🔮",
	Daily = "🎁",
	Leaderboard = "🏆",
	Rebirth = "🔄",
	Settings = "⚙️",
	Close = "✕",
	Trap = "🪤",
	Decoy = "🐔",
	Bat = "🏏",
	Drop = "⬇️",
	Event = "🌀",
	Star = "★",
}

Theme.Corner = 14
Theme.Stroke = 3

-- Virtual design resolution. Every ScreenGui root is uniformly scaled so this fits the screen.
Theme.Design = Vector2.new(1100, 620)
Theme.MaxScale = { Desktop = 1.35, Console = 2.0, Touch = 1.8 }
Theme.MinScale = 0.45
Theme.TouchBoost = 1.1 -- slightly larger UI on touch screens so targets stay >= 44 px

Theme.WindowSize = Vector2.new(880, 500)
Theme.ButtonHeight = 64

Theme.Tween = {
	Pop = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

function Theme.Rarity(rarity: string?): Color3
	local r = rarity and GameConfig.Rarities.ById[rarity]
	return r and r.Color or Theme.Colors.TextDim
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

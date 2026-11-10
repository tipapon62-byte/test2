-- RebirthController: the Rebirth (prestige) window. Shows cost, requirements, what resets and
-- what is kept; the button only works when the server says Derived.CanRebirth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent.Parent
local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local Text = Components.Text
local Fmt = GameConfig.FormatNumber
local Rebirth = GameConfig.Economy.Rebirth

local player = Players.LocalPlayer

local RebirthController = {}

local function hex(c: Color3): string
	return c:ToHex()
end

function RebirthController.Start()
	local win = Components.Window("Rebirth", "Rebirth", Theme.Icons.Rebirth, { TitleColor = Theme.Buttons.Rebirth })
	local body = win.Body

	local leftCard = Components.Card({ Color = Theme.Colors.Panel, Size = UDim2.new(0.5, -8, 1, -84), Parent = body })
	local rightCard = Components.Card({ Color = Theme.Colors.Panel, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, -8, 1, -84), Parent = body })
	local status = Text({
		Text = "",
		RichText = true,
		TextSize = 19,
		Font = Theme.FontBody,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(12, 10),
		Parent = leftCard,
	})
	Text({
		Text = ("<b>🔄 Resets</b>\ncoins, trained Speed, treadmill, enclosure, incubator and Rift Keys\n\n<b>✅ Keeps</b>\ncharacters (extras go to storage), Index, trails, Rift Shards, stats\n\n<b>🎁 Each rebirth</b>\n+%d%% income · +%d%% training · 💎 %d shards"):format(
			math.floor(Rebirth.IncomeBonusPerRebirth * 100),
			math.floor(Rebirth.TrainingBonusPerRebirth * 100),
			Rebirth.ShardsPerRebirth
		),
		RichText = true,
		TextSize = 17,
		Font = Theme.FontBody,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(12, 10),
		Parent = rightCard,
	})
	local btn = Components.Button({
		Text = "🔄 REBIRTH",
		TextSize = 28,
		Color = Theme.Colors.Accent,
		Size = UDim2.fromOffset(360, 70),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Parent = body,
	})

	local requiredBiome = GameConfig.GetBiomeByIndex(Rebirth.RequiredBiome)

	local function refresh()
		local p = ClientData.Get()
		local d = p.Derived or {}
		local rebirths = p.Rebirths or 0
		local cost = d.RebirthCost or GameConfig.RebirthCost(rebirths)
		local coins = player:GetAttribute("Coins") or p.Coins or 0
		local hasKey = requiredBiome and p.Biomes and p.Biomes[requiredBiome.Id]
		local good, bad = hex(Theme.Colors.Good), hex(Theme.Colors.Bad)
		status.Text = table.concat({
			("<b>Rebirths:</b> %d"):format(rebirths),
			("<b>Current bonus:</b> +%d%% income, +%d%% training"):format(
				math.floor(rebirths * Rebirth.IncomeBonusPerRebirth * 100),
				math.floor(rebirths * Rebirth.TrainingBonusPerRebirth * 100)
			),
			("<b>After rebirth:</b> +%d%% income, +%d%% training"):format(
				math.floor((rebirths + 1) * Rebirth.IncomeBonusPerRebirth * 100),
				math.floor((rebirths + 1) * Rebirth.TrainingBonusPerRebirth * 100)
			),
			"",
			"<b>Requirements</b>",
			('<font color="#%s">%s Own the %s Rift Key</font>'):format(if hasKey then good else bad, if hasKey then "✅" else "❌", requiredBiome and requiredBiome.Name or "?"),
			('<font color="#%s">%s 🪙 %s / %s coins</font>'):format(if coins >= cost then good else bad, if coins >= cost then "✅" else "❌", Fmt(coins), Fmt(cost)),
		}, "\n")
		Components.SetText(btn, "🔄 REBIRTH · " .. Components.Price("Coins", cost))
		Components.SetEnabled(btn, d.CanRebirth == true)
	end

	Components.SetOnClick(btn, function()
		local p = ClientData.Get()
		if not (p.Derived and p.Derived.CanRebirth) then
			return
		end
		Components.Confirm({
			Title = "Rebirth?",
			Text = ("You will lose your coins, Speed, upgrades and Rift Keys.\nYou keep your characters, Index, trails and shards, and gain <b>+%d%% income</b> forever."):format(
				math.floor(Rebirth.IncomeBonusPerRebirth * 100)
			),
			ConfirmText = "Hold to rebirth",
			HoldSeconds = 1.5,
			Color = Theme.Colors.Accent,
			OnConfirm = function()
				Net.Event("Rebirth"):FireServer()
			end,
		})
	end)

	win.DefaultSelection = btn
	win.OnOpen = refresh
	ClientData.Observe({ "Derived", "Rebirths", "Biomes", "Coins" }, function()
		if win.IsOpen then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		if win.IsOpen then
			refresh()
		end
	end)
end

return RebirthController

-- TutorialController: first-time onboarding + light permanent hints.
--
-- Steps (progress is derived from profile Stats / attributes, so it resumes after rejoining):
--   1 Run to the Rift Run      -> BiomeIndex >= 1
--   2 Steal an egg (E)         -> CarryingEgg ~= ""
--   3 Bring it home            -> Stats.EggsDelivered >= 1
--   4 Watch it hatch           -> Stats.PetsHatched >= 1
--   5 Train on your treadmill  -> Stats.TreadmillSeconds >= TRAIN_SECONDS
--   6 Buy an upgrade           -> any upgrade level > 1 (or a rebirth)
--   done -> confetti + "You're a Rift Raider!", saved as Settings.TutorialDone = true.
-- A glowing trail of arrows on the ground leads from the character to each target, with a beacon
-- and a floating marker on the target. After the tutorial the same guide points home while you
-- carry an egg, and a hint appears when your base is full.
--
-- API: TutorialController.IsActive(): boolean, TutorialController.Skip()

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent.Parent
local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
local ClientState = require(Client:WaitForChild("Data"):WaitForChild("ClientState"))
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local New = Components.New
local Text = Components.Text
local Fmt = GameConfig.FormatNumber
local Economy = GameConfig.Economy

local player = Players.LocalPlayer

local TutorialController = {}

local TRAIN_SECONDS = 6
local STEP_COUNT = 6
local DONE = STEP_COUNT + 1
local ARROWS = 12
local SPACING = 5
local FULL_HINT_COOLDOWN = 120

local active = false
local finished = false

function TutorialController.IsActive(): boolean
	return active
end

-- ===== Targets =====
local function firstBiomeId(): string
	local b = GameConfig.Biomes[1]
	return b and b.Id or "RiftLab"
end

local function zone1(): Instance?
	local run = workspace:FindFirstChild("RiftRun")
	local zones = run and run:FindFirstChild("Zones")
	return zones and zones:FindFirstChild("Zone1") or nil
end

-- Zone 1's entrance: its Gate, else the near end of its floor, else the configured layout start.
local function zoneEntrance(): Vector3
	local z = zone1()
	local gate = z and z:FindFirstChild("Gate", true)
	local p = ClientState.PositionOf(gate)
	if p then
		return p
	end
	local floor = z and z:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return floor.Position - Vector3.new(floor.Size.X / 2 - 25, 0, 0)
	end
	local L = GameConfig.Layout or {}
	return Vector3.new((L.StartX or 350) + 25, L.FloorTopY or 0, 0)
end

local function riftRunTarget(): (Vector3?, string)
	local hub = workspace:FindFirstChild("Hub")
	local arch = hub and hub:FindFirstChild("RiftRunArch", true)
	local archPos = ClientState.PositionOf(arch)
	local root = ClientState.Root()
	if archPos and root then
		local flat = (archPos - root.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude > 18 then
			return archPos, "Rift Run"
		end
	end
	return zoneEntrance(), "Rift Run"
end

local eggPick: Model? = nil
local eggPickAt = -10
local function eggTarget(): (Vector3?, string)
	local root = ClientState.Root()
	if not root then
		return nil, ""
	end
	local valid = eggPick and eggPick.Parent and eggPick:GetAttribute("State") == "Nest"
	if not valid or os.clock() - eggPickAt > 1.5 then
		eggPickAt = os.clock()
		local best, bestD = nil, math.huge
		local want = firstBiomeId()
		for _, m in ipairs(CollectionService:GetTagged("RR_Egg")) do
			if m:IsA("Model") and m:GetAttribute("State") == "Nest" and m:GetAttribute("Biome") == want then
				local p = ClientState.PositionOf(m)
				local d = p and (p - root.Position).Magnitude or math.huge
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
		eggPick = best
	end
	local p = ClientState.PositionOf(eggPick)
	if p then
		return p, "Egg"
	end
	-- no egg in a nest right now: lead into the zone, eggs respawn there
	local z = zone1()
	return ClientState.PositionOf(z and z:FindFirstChild("Floor")) or zoneEntrance(), "Nests"
end

local function homeTarget(): (Vector3?, string)
	return ClientState.HomePosition(), "Home"
end

local function incubatorTarget(): (Vector3?, string)
	local base = ClientState.Base()
	if base then
		for _, m in ipairs(CollectionService:GetTagged("RR_IncubatorEgg")) do
			if m:IsDescendantOf(base) then
				local p = ClientState.PositionOf(m)
				if p then
					return p, "Your egg"
				end
			end
		end
	end
	return homeTarget()
end

local function treadmillTarget(): (Vector3?, string)
	local base = ClientState.Base()
	local p = base and ClientState.PositionOf(base:FindFirstChild("Treadmill"))
	if p then
		return p, "Treadmill"
	end
	return homeTarget()
end

local function shopTarget(): (Vector3?, string)
	local base = ClientState.Base()
	local rt = base and base:FindFirstChild("RiftRaiders")
	local p = rt and ClientState.PositionOf(rt:FindFirstChild("ShopTerminal"))
	if p then
		return p, "Shop"
	end
	return homeTarget()
end

-- ===== Progress =====
local function upgraded(p): boolean
	return (tonumber(p.BaseLevel) or 1) > 1 or (tonumber(p.TreadmillLevel) or 1) > 1
		or (tonumber(p.IncubatorLevel) or 1) > 1 or (tonumber(p.Rebirths) or 0) > 0
end

local function currentStep(): number
	local p = ClientData.Get()
	local owned = ClientState.Count(p.Pets) > 0
	local hatched = ClientState.Stat("PetsHatched") > 0 or owned
	local delivered = ClientState.Stat("EggsDelivered") > 0 or hatched
	if not delivered then
		if ClientState.Carrying() then
			return 3
		end
		local idx = player:GetAttribute("BiomeIndex")
		if type(idx) == "number" and idx >= 1 then
			return 2
		end
		return 1
	end
	if not hatched then
		return 4
	end
	if ClientState.Stat("TreadmillSeconds") < TRAIN_SECONDS then
		return 5
	end
	if not upgraded(p) then
		return 6
	end
	return DONE
end

local function cheapestUpgrade(): number
	local p = ClientData.Get()
	local best = math.huge
	for key, track in pairs({ BaseLevel = Economy.BaseLevels, TreadmillLevel = Economy.TreadmillLevels, IncubatorLevel = Economy.IncubatorLevels }) do
		local lvl = math.clamp(tonumber(p[key]) or 1, 1, #track)
		local nxt = track[lvl + 1]
		if nxt and nxt.Price and nxt.Price < best then
			best = nxt.Price
		end
	end
	return if best == math.huge then 0 else best
end

local function coins(): number
	local c = player:GetAttribute("Coins")
	return if type(c) == "number" then c else (tonumber(ClientData.Get().Coins) or 0)
end

local function grabHint(): string
	local mode = Components.InputMode()
	if mode == "Touch" then
		return "Walk up to an egg in a nest and tap it"
	elseif mode == "Gamepad" then
		return "Walk up to an egg in a nest and press X"
	end
	return "Walk up to an egg in a nest and press E"
end

local function hatchLeft(): number?
	local best = nil
	local now = Components.Now()
	for _, egg in pairs(ClientData.Get().Incubators or {}) do
		if type(egg) == "table" and egg.HatchAt then
			local left = egg.HatchAt - now
			if not best or left < best then
				best = left
			end
		end
	end
	return best
end

-- Step definitions: Title, Sub() -> (text, progress 0..1?), Target() -> (pos, label), Color
local STEPS = {
	{
		Title = "Run to the Rift Run!",
		Sub = function()
			return "Follow the glowing arrows to the rift gate 🏃", nil
		end,
		Target = riftRunTarget,
		Color = Color3.fromRGB(90, 255, 200),
	},
	{
		Title = "Steal an egg!",
		Sub = function()
			return grabHint() .. " 🥚", nil
		end,
		Target = eggTarget,
		Color = Color3.fromRGB(255, 220, 60),
	},
	{
		Title = "Bring it home!",
		Sub = function()
			return "Run back to your base — dodge the guardian! 🏠", nil
		end,
		Target = homeTarget,
		Color = Color3.fromRGB(120, 255, 120),
	},
	{
		Title = "Watch it hatch!",
		Sub = function()
			local left = hatchLeft()
			if left then
				return ("Your egg hatches in %s ⏳"):format(GameConfig.FormatTime(math.max(left, 0))), nil
			end
			return "Your egg is hatching in your base ⏳", nil
		end,
		Target = incubatorTarget,
		Color = Color3.fromRGB(255, 160, 60),
	},
	{
		Title = "Train on your treadmill",
		Sub = function()
			local t = ClientState.Stat("TreadmillSeconds")
			return ("Run on the treadmill in your base to get faster ⚡  %d/%ds"):format(math.floor(math.min(t, TRAIN_SECONDS)), TRAIN_SECONDS), math.clamp(t / TRAIN_SECONDS, 0, 1)
		end,
		Target = treadmillTarget,
		Color = Color3.fromRGB(80, 170, 255),
	},
	{
		Title = "Buy an upgrade in the Shop",
		Sub = function()
			local price = cheapestUpgrade()
			local c = coins()
			if price > 0 and c < price then
				return ("Your characters earn coins! 🪙 %s / %s"):format(Fmt(c), Fmt(price)), math.clamp(c / price, 0, 1)
			end
			return "Open 🛒 Shop at your base → ⬆️ Upgrades", 1
		end,
		Target = shopTarget,
		Color = Color3.fromRGB(70, 215, 70),
	},
}

-- ===== 3D guide (local-only parts) =====
local guideFolder: Folder? = nil
local arrows: { { L: BasePart, R: BasePart, Y: number?, YAt: number } } = {}
local marker: { Pillar: BasePart, Anchor: BasePart, Gui: BillboardGui, Label: TextLabel, Arrow: TextLabel }? = nil

local function part(name: string, size: Vector3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = size
	p.Transparency = 1
	p.Parent = parent
	return p
end

local function ensureGuide(): Folder
	if guideFolder and guideFolder.Parent then
		return guideFolder
	end
	local f = Instance.new("Folder")
	f.Name = "RR_LocalGuide"
	f.Parent = workspace
	guideFolder = f
	arrows = {}
	for _ = 1, ARROWS do
		table.insert(arrows, {
			L = part("ArrowL", Vector3.new(0.5, 0.2, 1.9), f),
			R = part("ArrowR", Vector3.new(0.5, 0.2, 1.9), f),
			Y = nil,
			YAt = -1,
		})
	end
	local pillar = part("Beacon", Vector3.new(40, 2.2, 2.2), f)
	pillar.Shape = Enum.PartType.Cylinder
	local anchor = part("MarkerAnchor", Vector3.new(0.2, 0.2, 0.2), f)
	local gui = New("BillboardGui", {
		Name = "Marker",
		Size = UDim2.fromOffset(200, 96),
		StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 2000,
		Adornee = anchor,
		Enabled = false,
		Parent = anchor,
	})
	local label = Text({ Text = "", TextSize = 24, Font = Theme.FontHeavy, RichText = true, TextWrapped = false, Size = UDim2.new(1, 0, 0, 30), Parent = gui })
	local arrow = Text({ Text = "⬇", TextSize = 46, Font = Theme.FontHeavy, Outline = 4, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 32), Parent = gui })
	marker = { Pillar = pillar, Anchor = anchor, Gui = gui, Label = label, Arrow = arrow }
	return f
end

local function hideGuide()
	for _, a in ipairs(arrows) do
		a.L.Transparency = 1
		a.R.Transparency = 1
	end
	if marker then
		marker.Pillar.Transparency = 1
		marker.Gui.Enabled = false
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundY(pos: Vector3, fallback: number): number
	local list: { Instance } = {}
	if player.Character then
		table.insert(list, player.Character)
	end
	if guideFolder then
		table.insert(list, guideFolder)
	end
	rayParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(Vector3.new(pos.X, fallback + 6, pos.Z), Vector3.new(0, -14, 0), rayParams)
	return if hit then hit.Position.Y else fallback
end

local clock = 0
local function updateGuide(target: Vector3?, color: Color3, label: string)
	local root = ClientState.Root()
	local hum = ClientState.Humanoid()
	if not target or not root or not hum or hum.Health <= 0 then
		hideGuide()
		return
	end
	ensureGuide()
	local feetY = root.Position.Y - (hum.HipHeight + root.Size.Y / 2)
	local from = Vector3.new(root.Position.X, feetY, root.Position.Z)
	local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	local dist = flat.Magnitude
	local dir = if dist > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local maxLen = math.min(dist - 4, ARROWS * SPACING)
	local offset = (clock * 9) % SPACING
	local now = os.clock()
	for i, a in ipairs(arrows) do
		local d = 3 + offset + (i - 1) * SPACING
		if d > maxLen then
			a.L.Transparency = 1
			a.R.Transparency = 1
		else
			local pos = from + dir * d
			if not a.Y or now - a.YAt > 0.1 then
				a.Y = groundY(pos, feetY)
				a.YAt = now
			end
			local base = CFrame.lookAt(Vector3.new(pos.X, (a.Y or feetY) + 0.3, pos.Z), Vector3.new(pos.X, (a.Y or feetY) + 0.3, pos.Z) + dir)
			-- chevron ">" pointing along dir: two arms meeting at the tip
			a.L.CFrame = base * CFrame.new(-0.55, 0, 0.1) * CFrame.Angles(0, math.rad(-40), 0)
			a.R.CFrame = base * CFrame.new(0.55, 0, 0.1) * CFrame.Angles(0, math.rad(40), 0)
			local fade = math.clamp(math.min((d - 3) / 4, (maxLen - d) / 6), 0, 1)
			local t = 1 - 0.85 * fade
			a.L.Transparency = t
			a.R.Transparency = t
			a.L.Color = color
			a.R.Color = color
		end
	end
	if marker then
		local gy = groundY(target, target.Y)
		marker.Pillar.CFrame = CFrame.new(target.X, gy + 20, target.Z) * CFrame.Angles(0, 0, math.rad(90))
		marker.Pillar.Color = color
		marker.Pillar.Transparency = if Components.LowGraphics() then 1 else 0.55 + 0.15 * math.sin(clock * 4)
		marker.Anchor.Position = Vector3.new(target.X, gy + 2, target.Z)
		marker.Gui.Enabled = true
		marker.Label.Text = ("%s  <font color=\"#FFE14A\">%dm</font>"):format(label, math.floor(dist + 0.5))
		marker.Label.TextColor3 = color
		marker.Arrow.TextColor3 = color
		marker.Arrow.Position = UDim2.fromOffset(0, 32 + math.abs(math.sin(clock * 5)) * -10)
	end
end

-- ===== Objective banner =====
local banner: any = nil

local function buildBanner()
	local root = Components.Layer("HUD")
	local isTouch = Components.Device() == "Touch"
	local frame = New("Frame", {
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(if isTouch then 430 else 540, 82),
		BackgroundColor3 = Theme.Colors.PillBg,
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = root,
	})
	Components.Corner(frame, 18)
	local stroke = Components.Stroke(frame, Theme.Colors.Stroke, 4)
	local chip = New("Frame", {
		Name = "Step",
		BackgroundColor3 = Theme.Colors.Accent,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(58, 58),
		Parent = frame,
	})
	Components.CornerScale(chip, 0.5)
	Components.Stroke(chip, Theme.Colors.Stroke, 3)
	local chipText = Text({ Text = "1/6", TextSize = 20, Font = Theme.FontHeavy, Parent = chip })
	local title = Text({
		Text = "",
		TextSize = if isTouch then 24 else 28,
		Font = Theme.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -170, 0, 34),
		Position = UDim2.fromOffset(78, 6),
		Parent = frame,
	})
	local sub = Text({
		Text = "",
		TextSize = if isTouch then 15 else 17,
		Font = Theme.FontBody,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
		Size = UDim2.new(1, -170, 0, 22),
		Position = UDim2.fromOffset(78, 40),
		Parent = frame,
	})
	local bar = Components.ProgressBar({ Size = UDim2.new(1, -170, 0, 10), Position = UDim2.fromOffset(78, 64), TextSize = 1, Parent = frame })
	bar.Frame.Visible = false
	local skip = Components.Button({
		Name = "Skip",
		Text = "Skip",
		TextSize = 17,
		Color = Theme.Colors.Disabled,
		Size = UDim2.fromOffset(72, 36),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Corner = 10,
		Parent = frame,
		OnClick = function()
			Components.Confirm({
				Title = "Skip the tutorial?",
				Text = "You can still find everything in the menus.\nThe guide arrows will still point home when you carry an egg.",
				ConfirmText = "Skip",
				OnConfirm = TutorialController.Skip,
			})
		end,
	})
	local action = Components.Button({
		Name = "Action",
		Text = "🛒 Open",
		TextSize = 17,
		Color = Theme.Buttons.Shop,
		Size = UDim2.fromOffset(72, 32),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -6),
		Corner = 10,
		Parent = frame,
		OnClick = function()
			ClientState.Call("ShopController", "Open", "Upgrades")
		end,
	})
	action.Visible = false
	banner = { Frame = frame, Stroke = stroke, Chip = chip, ChipText = chipText, Title = title, Sub = sub, Bar = bar, Skip = skip, Action = action }
end

-- Bouncing pointer next to the HUD Shop button during the shop step.
local shopPointer: any = nil
local function setShopPointer(on: boolean)
	if on and not shopPointer then
		local hud = ClientState.Controller("HUDController")
		local btn = hud and hud.MenuButtons and hud.MenuButtons.Shop
		if not btn then
			return
		end
		shopPointer = Text({
			Name = "TutorialPointer",
			Text = "👈",
			TextSize = 40,
			Outline = false,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, 8, 0.5, 0),
			Size = UDim2.fromOffset(50, 50),
			ZIndex = 10,
			Parent = btn,
		})
		local tw = TweenService:Create(shopPointer, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.new(1, 22, 0.5, 0) })
		tw:Play()
	elseif not on and shopPointer then
		shopPointer:Destroy()
		shopPointer = nil
	end
end

local shownStep = 0
local function renderBanner(step: number)
	if not banner then
		buildBanner()
	end
	local def = STEPS[step]
	if not def then
		return
	end
	local text, progress = def.Sub()
	banner.Title.Text = def.Title
	banner.Sub.Text = text
	banner.ChipText.Text = ("%d/%d"):format(step, STEP_COUNT)
	banner.Chip.BackgroundColor3 = def.Color
	banner.Stroke.Color = Theme.Darken(def.Color, 0.45)
	banner.Bar.Frame.Visible = progress ~= nil
	if progress then
		banner.Bar.Set(progress, "")
		banner.Bar.SetColor(def.Color)
	end
	banner.Action.Visible = step == 6
	setShopPointer(step == 6)
	if not banner.Frame.Visible then
		banner.Frame.Visible = true
		Components.Pop(banner.Frame, 0.5, Theme.Tween.Bounce)
	end
	if step ~= shownStep then
		if shownStep > 0 and step > shownStep then
			Components.PlaySound("Step")
			Components.Pop(banner.Chip, 1.5, Theme.Tween.Bounce)
		end
		shownStep = step
	end
end

local function saveDone()
	local s = ClientData.Get().Settings
	if type(s) == "table" and s.TutorialDone == true then
		return
	end
	local settingsCtl = ClientState.Controller("SettingsController")
	if settingsCtl and type(settingsCtl.Set) == "function" then
		ClientState.Call("SettingsController", "Set", "TutorialDone", true)
	else
		local copy = if type(s) == "table" then table.clone(s) else {}
		copy.TutorialDone = true
		ClientData.SetLocal("Settings", copy)
		Net.Event("SaveSettings"):FireServer({ TutorialDone = true })
	end
end

local function finish(celebrate: boolean)
	if finished then
		return
	end
	finished = true
	active = false
	saveDone()
	setShopPointer(false)
	hideGuide()
	Components.SetToastOffset(nil)
	if not banner then
		return
	end
	if celebrate then
		banner.Title.Text = "You're a Rift Raider! 🎉"
		banner.Sub.Text = "Steal rarer eggs from deeper rifts and collect every character!"
		banner.ChipText.Text = "✓"
		banner.Chip.BackgroundColor3 = Theme.Colors.Good
		banner.Bar.Frame.Visible = false
		banner.Action.Visible = false
		banner.Skip.Visible = false
		Components.Pop(banner.Frame, 0.6, Theme.Tween.Bounce)
		Components.Confetti(nil, 120)
		Components.PlaySound("LevelUp")
		ClientState.Call("JuiceController", "BigCallout", "YOU'RE A RIFT RAIDER!", Theme.Colors.Accent, 3)
		task.delay(5, function()
			if banner and banner.Frame.Parent then
				banner.Frame.Visible = false
			end
		end)
	else
		banner.Frame.Visible = false
	end
end

function TutorialController.Skip()
	finish(false)
end

-- ===== Permanent light hints (after the tutorial) =====
local lastFullHint = -math.huge
local wasFull = false
local function permanentHints(dt: number): (Vector3?, Color3, string)
	-- base-full hint (only meaningful when something waits for a slot)
	local used, slots = ClientState.EnclosureUse()
	local waiting = ClientState.Count(ClientData.Get().EggStorage) > 0 or ClientState.Carrying()
	local full = used >= slots and waiting
	if full and not wasFull and os.clock() - lastFullHint > FULL_HINT_COOLDOWN then
		lastFullHint = os.clock()
		Components.Toast("🏠 Your base is full! Upgrade your Enclosure in the 🛒 Shop or sell extra copies.", "warn", 6)
	end
	wasFull = full
	if ClientState.Carrying() then
		local color = Theme.Rarity(ClientState.CarryRarity())
		return ClientState.HomePosition(), color, "🏠 Home"
	end
	return nil, Color3.new(1, 1, 1), ""
end

function TutorialController.Start()
	local settings = ClientData.Get().Settings
	local done = type(settings) == "table" and settings.TutorialDone == true
	if not done and currentStep() == DONE then
		-- veteran from before the tutorial existed: mark it done silently
		done = true
		saveDone()
	end
	finished = done
	active = not done
	if active then
		Components.SetToastOffset(156)
	end

	local acc = 0
	local target: Vector3? = nil
	local color = Color3.new(1, 1, 1)
	local label = ""
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		acc += dt
		if acc >= 0.2 then
			acc = 0
			local ok, err = pcall(function()
				if active then
					local step = currentStep()
					if step >= DONE then
						finish(true)
						target = nil
					else
						renderBanner(step)
						local def = STEPS[step]
						local pos, name = def.Target()
						target, color, label = pos, def.Color, name
					end
				else
					target, color, label = permanentHints(dt)
				end
			end)
			if not ok then
				warn("[Tutorial]", err)
				target = nil
			end
		end
		updateGuide(target, color, label)
	end)

	-- the settings window or another device may finish it elsewhere
	ClientData.Observe({ "Settings" }, function(p)
		local s = p.Settings
		if active and type(s) == "table" and s.TutorialDone == true then
			finish(false)
		end
	end)
	player.CharacterAdded:Connect(function()
		for _, a in ipairs(arrows) do
			a.Y = nil
		end
	end)
end

return TutorialController

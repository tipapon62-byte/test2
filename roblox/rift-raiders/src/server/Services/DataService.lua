-- DataService: owns every loaded profile, replicates changes to the owning client
-- (ProfileUpdated + player attributes) and drives autosave / leave / shutdown saves.
--
-- Other services never touch DataStores. They mutate the profile table returned by Get()
-- and then call DataService.Changed(player, "Key", ...) so the change is replicated.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local SaveService = require(script.Parent.SaveService)

local S = GameConfig.Settings
local E = GameConfig.Economy

local DataService = {}

local profiles: { [Player]: any } = {}
local dirty: { [Player]: { [string]: boolean } } = {}
local derivedProviders: { (Player, any, any) -> () } = {}
local loadedCallbacks: { (Player, any) -> () } = {}
local removingCallbacks: { (Player, any) -> () } = {}
local Services

local function template()
	local now = os.time()
	return {
		Version = GameConfig.DataVersion,
		Coins = E.StartCoins,
		Shards = E.StartShards,
		SpeedStat = 0,
		TreadmillLevel = 1,
		BaseLevel = 1,
		IncubatorLevel = 1,
		Rebirths = 0,
		Biomes = { RiftLab = true },
		Trails = { Owned = { None = true }, Equipped = "None" },
		Items = { BearTrap = 0, DecoyEgg = 0, MutationPotion = 0 },
		Pets = {},
		Incubators = {},
		EggStorage = {},
		Index = {},
		IndexBiomesDone = {},
		Stats = {
			EggsDelivered = 0, EggsRetrieved = 0, PetsHatched = 0, RareHatches = 0, Tags = 0,
			TrapsSprung = 0, Fuses = 0, CoinsEarned = 0, TreadmillSeconds = 0, TimePlayed = 0, BestIncome = 0,
		},
		Daily = { Streak = 0, LastClaim = 0 },
		Quests = { Daily = { Period = -1, List = {} }, Weekly = { Period = -1, List = {} } },
		Achievements = {},
		Codes = {},
		Settings = { Music = 0.5, Sfx = 0.8, LowGraphics = false, ShowTrails = true, Notifications = true, ConfirmFuse = true, TutorialDone = false },
		FirstJoin = now,
		LastOnline = now,
	}
end

-- Upgrades older saves in place. Add a branch per DataVersion bump.
local function migrate(data)
	Util.Reconcile(data, template())
	-- v1 is the first schema; future: if data.Version < 2 then ... end
	data.Version = GameConfig.DataVersion
	return data
end

-- Values that are not saved but derived from the profile and other services.
local function computeDerived(player: Player, profile)
	local d = {
		Slots = E.BaseLevels[math.clamp(profile.BaseLevel, 1, #E.BaseLevels)].Slots,
		Pads = E.IncubatorLevels[math.clamp(profile.IncubatorLevel, 1, #E.IncubatorLevels)].Pads,
		RebirthCost = GameConfig.RebirthCost(profile.Rebirths),
	}
	for _, provider in ipairs(derivedProviders) do
		provider(player, profile, d)
	end
	local requiredBiome = GameConfig.GetBiomeByIndex(E.Rebirth.RequiredBiome)
	d.CanRebirth = profile.Coins >= d.RebirthCost and requiredBiome ~= nil and profile.Biomes[requiredBiome.Id] == true
	profile.Derived = d
	return d
end

local function syncAttributes(player: Player, profile)
	local d = profile.Derived or computeDerived(player, profile)
	player:SetAttribute("Coins", math.floor(profile.Coins))
	player:SetAttribute("Shards", profile.Shards)
	player:SetAttribute("SpeedStat", math.floor(profile.SpeedStat))
	player:SetAttribute("EffectiveSpeed", math.floor(d.EffectiveSpeed or 0))
	player:SetAttribute("Income", d.Income or 0)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local coins = ls:FindFirstChild("Coins") :: StringValue?
		local speed = ls:FindFirstChild("Speed") :: StringValue?
		if coins then
			coins.Value = GameConfig.FormatNumber(profile.Coins)
		end
		if speed then
			speed.Value = GameConfig.FormatNumber(d.EffectiveSpeed or 0)
		end
	end
end

local function snapshot(profile)
	local copy = Util.DeepCopy(profile)
	return copy
end

-- ===== Public API =====

function DataService.Init(services)
	Services = services
end

function DataService.Get(player: Player)
	return profiles[player]
end

function DataService.WaitFor(player: Player, timeout: number?)
	local t = 0
	while not profiles[player] and player.Parent and t < (timeout or 30) do
		t += task.wait(0.1)
	end
	return profiles[player]
end

function DataService.All(): { [Player]: any }
	return profiles
end

-- Marks top-level keys as changed; they are replicated on the next flush (~5x per second).
function DataService.Changed(player: Player, ...: string)
	local set = dirty[player]
	if not set then
		set = {}
		dirty[player] = set
	end
	for _, k in ipairs({ ... }) do
		set[k] = true
	end
	set.Derived = true
end

function DataService.RegisterDerived(fn: (Player, any, any) -> ())
	table.insert(derivedProviders, fn)
end

function DataService.OnLoaded(fn: (Player, any) -> ())
	table.insert(loadedCallbacks, fn)
	for player, profile in pairs(profiles) do
		task.spawn(fn, player, profile)
	end
end

function DataService.OnRemoving(fn: (Player, any) -> ())
	table.insert(removingCallbacks, fn)
end

function DataService.Recompute(player: Player)
	local profile = profiles[player]
	if profile then
		computeDerived(player, profile)
		syncAttributes(player, profile)
	end
end

-- Adds coins. countAsEarned = true for income/rewards (feeds stats and quests), false for refunds.
function DataService.AddCoins(player: Player, amount: number, countAsEarned: boolean?)
	local profile = profiles[player]
	if not profile or amount ~= amount or amount == math.huge then
		return
	end
	profile.Coins = math.max(0, profile.Coins + amount)
	if countAsEarned and amount > 0 then
		profile.Stats.CoinsEarned += amount
		if Services.QuestService then
			Services.QuestService.Track(player, "CoinsEarned", amount)
		end
	end
	DataService.Changed(player, "Coins", "Stats")
end

function DataService.AddShards(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Shards = math.max(0, profile.Shards + math.floor(amount))
	DataService.Changed(player, "Shards")
end

-- Atomically checks and spends a currency. Returns true when paid.
function DataService.Spend(player: Player, currency: string, amount: number): boolean
	local profile = profiles[player]
	if not profile or amount < 0 or amount ~= amount then
		return false
	end
	local field = if currency == "Shards" then "Shards" else "Coins"
	if profile[field] < amount then
		return false
	end
	profile[field] -= amount
	DataService.Changed(player, field)
	return true
end

function DataService.Notify(player: Player, text: string, kind: string?)
	Net.Event("Notify"):FireClient(player, text, kind or "info")
end

function DataService.Effect(player: Player, name: string, data: any)
	Net.Event("Effect"):FireClient(player, name, data or {})
end

function DataService.Announce(text: string, color: Color3?)
	Net.Event("Announce"):FireAllClients(text, color or Color3.new(1, 1, 1))
end

-- Saves now. release = clear the session lock (player leaving / shutdown).
function DataService.Save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or profile._noSave then
		return false
	end
	profile.LastOnline = os.time()
	local data = Util.DeepCopy(profile)
	data.Derived = nil
	data._noSave = nil
	return SaveService.Save(player.UserId, data, release == true)
end

-- ===== Lifecycle =====

local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Value = "0"
	coins.Parent = ls
	local speed = Instance.new("StringValue")
	speed.Name = "Speed"
	speed.Value = "0"
	speed.Parent = ls
	ls.Parent = player

	local status, data = SaveService.Load(player.UserId)
	if not player.Parent then
		if status == "ok" then
			SaveService.Save(player.UserId, data or template(), true) -- just release the lock
		end
		return
	end
	if status == "locked" then
		player:Kick("Your progress is still being saved on another server. Please rejoin in a minute.")
		return
	elseif status == "error" then
		player:Kick("Could not load your progress (Roblox data services are having trouble). Please rejoin.")
		return
	end

	local profile = migrate(data or template())
	if not SaveService.IsAvailable() then
		profile._noSave = true
	end
	profiles[player] = profile
	computeDerived(player, profile)
	syncAttributes(player, profile)
	for _, fn in ipairs(loadedCallbacks) do
		task.spawn(fn, player, profile)
	end
	DataService.Changed(player, "Coins")
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	for _, fn in ipairs(removingCallbacks) do
		local ok, err = pcall(fn, player, profile)
		if not ok then
			warn("[DataService] removing callback failed:", err)
		end
	end
	DataService.Save(player, true)
	profiles[player] = nil
	dirty[player] = nil
end

function DataService.Start()
	local getLimiter = RateLimiter.new(5, 0.5)
	Net.Function("GetProfile").OnServerInvoke = function(player)
		if not getLimiter:Allow(player) then
			return nil
		end
		local profile = DataService.WaitFor(player, 20)
		if not profile then
			return nil
		end
		computeDerived(player, profile)
		local snap = snapshot(profile)
		snap._noSave = nil
		return snap
	end

	local settingsLimiter = RateLimiter.new(4, 0.5)
	Net.Event("SaveSettings").OnServerEvent:Connect(function(player, settings)
		local profile = profiles[player]
		if not profile or type(settings) ~= "table" or not settingsLimiter:Allow(player) then
			return
		end
		local cur = profile.Settings
		for k, v in pairs(cur) do
			local incoming = settings[k]
			if type(incoming) == type(v) then
				if type(v) == "number" then
					cur[k] = math.clamp(incoming, 0, 1)
				else
					cur[k] = incoming
				end
			end
		end
		DataService.Changed(player, "Settings")
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end

	-- replicate dirty keys in batches
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		for player, set in pairs(dirty) do
			local profile = profiles[player]
			if profile and player.Parent then
				computeDerived(player, profile)
				syncAttributes(player, profile)
				local partial = {}
				for k in pairs(set) do
					partial[k] = Util.DeepCopy(profile[k])
				end
				Net.Event("ProfileUpdated"):FireClient(player, partial)
			end
			dirty[player] = nil
		end
	end)

	-- autosave
	task.spawn(function()
		while true do
			task.wait(S.AutoSaveInterval)
			for player in pairs(profiles) do
				task.spawn(DataService.Save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				for _, fn in ipairs(removingCallbacks) do
					pcall(fn, player, profiles[player])
				end
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		local t = 0
		while pending > 0 and t < 25 do
			t += task.wait(0.2)
		end
	end)
end

return DataService

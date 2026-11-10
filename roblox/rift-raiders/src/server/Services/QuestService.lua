-- QuestService: daily rewards, daily/weekly quests, achievements, bonus codes, admin commands.
-- Other services report progress with Track(player, stat, amount) or SetStat(player, stat, value).
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local P = GameConfig.Progression
local E = GameConfig.Economy

local QuestService = {}
local Services

local DAY = 86400
local function dailyPeriod(): number
	return os.time() // DAY
end
local function weeklyPeriod(): number
	return (os.time() + 3 * DAY) // (7 * DAY) -- weeks start Monday 00:00 UTC
end

local function questDef(kind: string, id: string)
	for _, q in ipairs(if kind == "Daily" then P.DailyQuests else P.WeeklyQuests) do
		if q.Id == id then
			return q
		end
	end
	return nil
end

local function roll(player: Player, kind: string, period: number)
	local pool = table.clone(if kind == "Daily" then P.DailyQuests else P.WeeklyQuests)
	local rng = Random.new(period * 1000003 + player.UserId % 1000003 + (if kind == "Daily" then 0 else 7))
	local list = {}
	for _ = 1, math.min(if kind == "Daily" then P.DailyQuestCount else P.WeeklyQuestCount, #pool) do
		local q = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(list, { Id = q.Id, Progress = 0, Claimed = false })
	end
	return list
end

local function ensureQuests(player: Player, profile): boolean
	local changed = false
	for kind, period in pairs({ Daily = dailyPeriod(), Weekly = weeklyPeriod() }) do
		local q = profile.Quests[kind]
		if q.Period ~= period then
			q.Period = period
			q.List = roll(player, kind, period)
			changed = true
		end
	end
	if changed then
		Services.DataService.Changed(player, "Quests")
	end
	return changed
end

local function rewardScale(profile): number
	return math.max(1, Services.EggService.BestBiome(profile).IncomeBase / 2)
end

local function statValue(profile, stat: string): number
	if stat == "Rebirths" then
		return profile.Rebirths
	elseif stat == "BiomesUnlocked" then
		return Util.Count(profile.Biomes)
	elseif stat == "IndexCount" then
		return Util.Count(profile.Index)
	end
	return profile.Stats[stat] or 0
end

local function checkAchievements(player: Player, profile)
	local got = false
	for _, a in ipairs(P.Achievements) do
		if not profile.Achievements[a.Id] and statValue(profile, a.Stat) >= a.Goal then
			profile.Achievements[a.Id] = true
			Services.DataService.AddShards(player, a.Shards or 0)
			Services.DataService.Notify(player, ("🏆 Achievement: %s (+%d Rift Shards)"):format(a.Text, a.Shards or 0), "good")
			got = true
		end
	end
	if got then
		Services.DataService.Changed(player, "Achievements")
	end
end

function QuestService.Track(player: Player, stat: string, amount: number)
	local profile = Services.DataService.Get(player)
	if not profile then
		return
	end
	ensureQuests(player, profile)
	local changed = false
	for kind, q in pairs(profile.Quests) do
		for _, entry in ipairs(q.List) do
			local def = questDef(kind, entry.Id)
			if def and def.Stat == stat and not entry.Claimed and entry.Progress < def.Goal then
				entry.Progress = math.min(def.Goal, entry.Progress + amount)
				changed = true
			end
		end
	end
	if changed then
		Services.DataService.Changed(player, "Quests")
	end
	if stat ~= "CoinsEarned" and stat ~= "TreadmillSeconds" then
		checkAchievements(player, profile)
	end
end

function QuestService.SetStat(player: Player, _stat: string, _value: number)
	local profile = Services.DataService.Get(player)
	if profile then
		checkAchievements(player, profile)
	end
end

-- Grants a reward table {Coins, Shards, Item, Amount, Egg}; returns a readable summary.
function QuestService.Grant(player: Player, reward, coinScale: number?): string
	local parts = {}
	if reward.Coins and reward.Coins > 0 then
		local coins = math.floor(reward.Coins * (coinScale or 1))
		Services.DataService.AddCoins(player, coins, true)
		table.insert(parts, GameConfig.FormatNumber(coins) .. " coins")
	end
	if reward.Shards and reward.Shards > 0 then
		Services.DataService.AddShards(player, reward.Shards)
		table.insert(parts, reward.Shards .. " Rift Shards")
	end
	if reward.Item and E.Items[reward.Item] then
		local profile = Services.DataService.Get(player)
		profile.Items[reward.Item] = math.min(E.Items[reward.Item].MaxOwned, (profile.Items[reward.Item] or 0) + (reward.Amount or 1))
		Services.DataService.Changed(player, "Items")
		table.insert(parts, ("%dx %s"):format(reward.Amount or 1, E.Items[reward.Item].Name))
	end
	if reward.Egg then
		for _, egg in ipairs(E.ShardEggs) do
			if egg.Id == reward.Egg then
				local profile = Services.DataService.Get(player)
				local rarity = Util.WeightedPick(egg.Weights, GameConfig.Rarities.Order) or "Rare"
				if Services.EggService.GiveEgg(player, { Uid = Util.Uid("e"), Biome = Services.EggService.BestBiome(profile).Id, Rarity = rarity, Size = "Normal", Mutation = egg.ForceMutation }) then
					table.insert(parts, egg.Name)
				end
			end
		end
	end
	return table.concat(parts, ", ")
end

local function claimDaily(player: Player)
	local profile = Services.DataService.Get(player)
	if not profile then
		return
	end
	local now = os.time()
	local since = now - profile.Daily.LastClaim
	if since < P.Daily.ClaimCooldown then
		Services.DataService.Notify(player, "Come back in " .. GameConfig.FormatTime(P.Daily.ClaimCooldown - since), "info")
		return
	end
	if since > P.Daily.StreakGrace then
		profile.Daily.Streak = 0
	end
	profile.Daily.Streak += 1
	profile.Daily.LastClaim = now
	local day = (profile.Daily.Streak - 1) % #P.Daily.Rewards + 1
	local text = QuestService.Grant(player, P.Daily.Rewards[day], rewardScale(profile) / 2 + 0.5)
	Services.DataService.Changed(player, "Daily")
	Services.DataService.Notify(player, ("🎁 Day %d reward: %s"):format(day, text), "good")
end

local function claimQuest(player: Player, kind: any, id: any)
	local profile = Services.DataService.Get(player)
	if not profile or (kind ~= "Daily" and kind ~= "Weekly") or type(id) ~= "string" then
		return
	end
	ensureQuests(player, profile)
	local def = questDef(kind, id)
	for _, entry in ipairs(profile.Quests[kind].List) do
		if entry.Id == id and def and not entry.Claimed and entry.Progress >= def.Goal then
			entry.Claimed = true
			local text = QuestService.Grant(player, def, rewardScale(profile))
			Services.DataService.Changed(player, "Quests")
			Services.DataService.Notify(player, "✅ Quest complete: " .. text, "good")
			return
		end
	end
end

local function redeem(player: Player, code: any)
	local profile = Services.DataService.Get(player)
	if not profile or type(code) ~= "string" then
		return
	end
	code = code:upper():gsub("%s", ""):sub(1, 32)
	local reward = P.Codes[code]
	if not reward then
		Services.DataService.Notify(player, "That code doesn't exist.", "bad")
		return
	end
	if reward.Expires and os.time() > reward.Expires then
		Services.DataService.Notify(player, "That code has expired.", "bad")
		return
	end
	if profile.Codes[code] then
		Services.DataService.Notify(player, "You already used that code.", "warn")
		return
	end
	profile.Codes[code] = true
	Services.DataService.Changed(player, "Codes")
	Services.DataService.Notify(player, "🎉 Code redeemed: " .. QuestService.Grant(player, reward), "good")
end

local function isAdmin(player: Player): boolean
	return table.find(P.Admins, player.UserId) ~= nil or (game:GetService("RunService"):IsStudio())
end

function QuestService.Init(services)
	Services = services
end

function QuestService.Start()
	Services.DataService.OnLoaded(function(player, profile)
		ensureQuests(player, profile)
		checkAchievements(player, profile)
	end)
	-- roll new quests when the UTC day/week changes while players are online
	task.spawn(function()
		while true do
			task.wait(60)
			for player, profile in pairs(Services.DataService.All()) do
				ensureQuests(player, profile)
			end
		end
	end)

	local limiter = RateLimiter.new(5, 1)
	Net.Event("ClaimDaily").OnServerEvent:Connect(function(player)
		if limiter:Allow(player) then
			claimDaily(player)
		end
	end)
	Net.Event("ClaimQuest").OnServerEvent:Connect(function(player, kind, id)
		if limiter:Allow(player) then
			claimQuest(player, kind, id)
		end
	end)
	local codeLimiter = RateLimiter.new(3, 0.2)
	Net.Event("RedeemCode").OnServerEvent:Connect(function(player, code)
		if codeLimiter:Allow(player) then
			redeem(player, code)
		end
	end)

	local function onPlayer(player: Player)
		player.Chatted:Connect(function(msg)
			if not isAdmin(player) then
				return
			end
			local cmd, arg = msg:match("^/(%w+)%s*(.*)$")
			if cmd == "event" then
				Services.EventService.StartEvent(arg)
			elseif cmd == "coins" then
				Services.DataService.AddCoins(player, tonumber(arg) or 0, false)
			elseif cmd == "speed" then
				local profile = Services.DataService.Get(player)
				if profile then
					profile.SpeedStat += tonumber(arg) or 0
					Services.DataService.Changed(player, "SpeedStat")
					Services.SpeedService.Apply(player)
				end
			elseif cmd == "divine" then
				Services.EventService.SpawnDivine()
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
end

return QuestService

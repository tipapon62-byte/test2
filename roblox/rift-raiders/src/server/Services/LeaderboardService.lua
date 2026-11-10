-- LeaderboardService: global leaderboards in OrderedDataStores (one per stat), refreshed
-- periodically. Falls back to the players in this server when DataStores are unavailable.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local P = GameConfig.Progression
local R = GameConfig.Rarities

local LeaderboardService = {}
local Services

local stores: { [string]: OrderedDataStore } = {}
local cache: { [string]: { any } } = {}
local names: { [number]: string } = {}

local function value(statId: string, player: Player, profile): number
	if statId == "Speed" then
		return math.floor(profile.SpeedStat)
	elseif statId == "Income" then
		return math.floor(Services.PetService.GetIncome(player))
	elseif statId == "RarePets" then
		local n = 0
		for _, pet in pairs(profile.Pets) do
			local s = GameConfig.GetSpecies(pet.Species)
			if s and R.ById[s.Rarity].Index >= R.ById.Legendary.Index then
				n += 1
			end
		end
		return n
	elseif statId == "Retrievals" then
		return profile.Stats.EggsRetrieved
	end
	return 0
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok then n else ("Raider " .. userId)
	return names[userId]
end

local function localBoard(statId: string)
	local list = {}
	for player, profile in pairs(Services.DataService.All()) do
		table.insert(list, { Name = player.DisplayName, UserId = player.UserId, Value = value(statId, player, profile) })
	end
	table.sort(list, function(a, b)
		return a.Value > b.Value
	end)
	return list
end

local function refresh()
	for statId in pairs(P.Leaderboards.Stats) do
		local store = stores[statId]
		if store then
			for player, profile in pairs(Services.DataService.All()) do
				pcall(store.SetAsync, store, tostring(player.UserId), value(statId, player, profile))
			end
			local ok, pages = pcall(store.GetSortedAsync, store, false, 25)
			if ok then
				local list = {}
				for _, entry in ipairs(pages:GetCurrentPage()) do
					local uid = tonumber(entry.key) or 0
					table.insert(list, { Name = nameOf(uid), UserId = uid, Value = entry.value })
				end
				cache[statId] = list
			end
		end
	end
end

function LeaderboardService.Init(services)
	Services = services
end

function LeaderboardService.Start()
	for statId in pairs(P.Leaderboards.Stats) do
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "RR_LB_" .. statId)
		if ok then
			stores[statId] = store
		end
	end
	local limiter = RateLimiter.new(4, 0.5)
	Net.Function("GetLeaderboard").OnServerInvoke = function(player, statId)
		if type(statId) ~= "string" or not P.Leaderboards.Stats[statId] or not limiter:Allow(player) then
			return {}
		end
		return cache[statId] or localBoard(statId)
	end
	task.spawn(function()
		task.wait(15)
		while true do
			refresh()
			task.wait(P.Leaderboards.RefreshInterval)
		end
	end)
end

return LeaderboardService

-- EconomyService: passive income, offline earnings, every coin/shard purchase, and rebirth.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local E = GameConfig.Economy

local EconomyService = {}
local Services

function EconomyService.Init(services)
	Services = services
end

local function notify(player, text, kind)
	Services.DataService.Notify(player, text, kind)
end

local function pay(player: Player, price: number, currency: string?): boolean
	if Services.DataService.Spend(player, currency or "Coins", price) then
		return true
	end
	notify(player, ("Not enough %s (%s needed)."):format(if currency == "Shards" then "Rift Shards" else "coins", GameConfig.FormatNumber(price)), "bad")
	return false
end

-- Upgrade tracks share one shape: {profileKey, levels}
local TRACKS = {
	BaseUpgrade = { Key = "BaseLevel", Levels = E.BaseLevels, Label = "Enclosure" },
	TreadmillUpgrade = { Key = "TreadmillLevel", Levels = E.TreadmillLevels, Label = "Treadmill" },
	IncubatorUpgrade = { Key = "IncubatorLevel", Levels = E.IncubatorLevels, Label = "Incubator" },
}

local handlers = {}

function handlers.Track(player, profile, category)
	local track = TRACKS[category]
	local nextLevel = profile[track.Key] + 1
	local cfg = track.Levels[nextLevel]
	if not cfg then
		notify(player, track.Label .. " is already max level!", "warn")
		return
	end
	if not pay(player, cfg.Price) then
		return
	end
	profile[track.Key] = nextLevel
	Services.DataService.Changed(player, track.Key)
	Services.BaseService.ApplyLevels(player)
	Services.SpeedService.Apply(player)
	Services.PetService.RefreshBase(player)
	notify(player, ("%s upgraded to level %d!"):format(track.Label, nextLevel), "good")
end

function handlers.Trail(player, profile, id)
	local trail = E.Trails[id]
	if type(id) ~= "string" or not trail then
		return
	end
	if profile.Trails.Owned[id] then
		notify(player, "You already own that trail.", "info")
		return
	end
	if not pay(player, trail.Price, trail.Currency) then
		return
	end
	profile.Trails.Owned[id] = true
	profile.Trails.Equipped = id
	Services.DataService.Changed(player, "Trails")
	Services.SpeedService.Apply(player)
	Services.SpeedService.ApplyTrail(player)
	notify(player, trail.Name .. " equipped! Speed x" .. trail.SpeedMult, "good")
end

function handlers.Item(player, profile, id)
	local item = E.Items[id]
	if type(id) ~= "string" or not item then
		return
	end
	if (profile.Items[id] or 0) >= item.MaxOwned then
		notify(player, ("You can hold at most %d %s."):format(item.MaxOwned, item.Name), "warn")
		return
	end
	if not pay(player, item.Price, item.Currency) then
		return
	end
	profile.Items[id] = (profile.Items[id] or 0) + 1
	Services.DataService.Changed(player, "Items")
	notify(player, "Bought " .. item.Name .. "!", "good")
end

function handlers.BiomeKey(player, profile, index)
	local biome = type(index) == "number" and GameConfig.GetBiomeByIndex(index)
	if not biome then
		return
	end
	if profile.Biomes[biome.Id] then
		notify(player, "You already own the " .. biome.Name .. " Rift Key.", "info")
		return
	end
	local prev = GameConfig.GetBiomeByIndex(index - 1)
	if prev and not profile.Biomes[prev.Id] then
		notify(player, "Unlock " .. prev.Name .. " first.", "warn")
		return
	end
	if not pay(player, biome.UnlockPrice) then
		return
	end
	profile.Biomes[biome.Id] = true
	Services.DataService.Changed(player, "Biomes")
	Services.QuestService.SetStat(player, "BiomesUnlocked", Util.Count(profile.Biomes))
	Services.DataService.Effect(player, "Unlock", { Biome = biome.Id })
	notify(player, ("Rift Key bought! Reach %s Speed to enter %s."):format(GameConfig.FormatNumber(biome.RequiredSpeed), biome.Name), "good")
end

function handlers.ShardEgg(player, profile, id)
	local cfg
	for _, e in ipairs(E.ShardEggs) do
		if e.Id == id then
			cfg = e
		end
	end
	if not cfg then
		return
	end
	if not Services.EggService.HasFreeStorage(player) then
		notify(player, "Your incubators and egg shelf are full.", "warn")
		return
	end
	if not pay(player, cfg.Price, "Shards") then
		return
	end
	local biome = Services.EggService.BestBiome(profile)
	local rarity = Util.WeightedPick(cfg.Weights, GameConfig.Rarities.Order) or "Rare"
	Services.EggService.GiveEgg(player, {
		Uid = Util.Uid("e"),
		Biome = biome.Id,
		Rarity = rarity,
		Size = "Normal",
		Mutation = cfg.ForceMutation,
	})
	notify(player, ("%s added to your incubator!"):format(cfg.Name), "good")
end

function EconomyService.Purchase(player: Player, category: string, id: any)
	local profile = Services.DataService.Get(player)
	if not profile then
		return
	end
	if not Services.BaseService.CanShop(player) then
		notify(player, "Go to your base (or the hub shop) to buy things.", "warn")
		return
	end
	if TRACKS[category] then
		handlers.Track(player, profile, category)
	elseif handlers[category] and category ~= "Track" then
		handlers[category](player, profile, id)
	end
end

function EconomyService.Rebirth(player: Player)
	local profile = Services.DataService.Get(player)
	if not profile then
		return
	end
	Services.DataService.Recompute(player)
	if not profile.Derived.CanRebirth then
		notify(player, "You can't rebirth yet — check the requirements.", "warn")
		return
	end
	if Services.EggService.IsCarrying(player) then
		notify(player, "Deliver or drop your egg first.", "warn")
		return
	end
	local cost = GameConfig.RebirthCost(profile.Rebirths)
	if not pay(player, cost) then
		return
	end
	profile.Rebirths += 1
	profile.Coins = E.StartCoins
	profile.SpeedStat = 0
	profile.TreadmillLevel = 1
	profile.BaseLevel = 1
	profile.IncubatorLevel = 1
	profile.Biomes = { RiftLab = true }
	Services.DataService.AddShards(player, E.Rebirth.ShardsPerRebirth * profile.Rebirths)
	Services.PetService.StoreOverflow(player)
	Services.DataService.Changed(player, "Rebirths", "Coins", "SpeedStat", "TreadmillLevel", "BaseLevel", "IncubatorLevel", "Biomes", "Pets")
	Services.BaseService.ApplyLevels(player)
	Services.SpeedService.Apply(player)
	Services.PetService.RefreshBase(player)
	Services.QuestService.Track(player, "Rebirths", 1)
	Services.DataService.Effect(player, "Rebirth", { Rebirths = profile.Rebirths })
	Services.DataService.Announce(("🔄 %s reached Rebirth %d!"):format(player.DisplayName, profile.Rebirths), Color3.fromRGB(0, 255, 170))
end

function EconomyService.Start()
	-- offline earnings
	Services.DataService.OnLoaded(function(player, profile)
		task.wait(2) -- let PetService rebuild the base first
		local away = math.clamp(os.time() - (profile.LastOnline or os.time()), 0, E.OfflineIncomeCapSeconds)
		local income = Services.PetService.GetIncome(player)
		local earned = math.floor(away * income * E.OfflineIncomeRate)
		if earned > 0 and player.Parent then
			Services.DataService.AddCoins(player, earned, true)
			notify(player, ("Welcome back! Your pets earned %s coins while you were away."):format(GameConfig.FormatNumber(earned)), "good")
		end
	end)

	-- passive income, once per second
	task.spawn(function()
		while true do
			task.wait(1)
			for player, profile in pairs(Services.DataService.All()) do
				local income = Services.PetService.GetIncome(player)
				profile.Stats.TimePlayed += 1
				if income > 0 then
					Services.DataService.AddCoins(player, income, true)
					if income > profile.Stats.BestIncome then
						profile.Stats.BestIncome = income
					end
				end
			end
		end
	end)

	local purchaseLimiter = RateLimiter.new(6, 2)
	Net.Event("Purchase").OnServerEvent:Connect(function(player, category, id)
		if type(category) ~= "string" or not purchaseLimiter:Allow(player) then
			return
		end
		EconomyService.Purchase(player, category, id)
	end)

	local rebirthLimiter = RateLimiter.new(1, 0.2)
	Net.Event("Rebirth").OnServerEvent:Connect(function(player)
		if rebirthLimiter:Allow(player) then
			EconomyService.Rebirth(player)
		end
	end)

end

return EconomyService

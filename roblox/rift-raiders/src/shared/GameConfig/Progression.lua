-- Retention: daily rewards, quests, achievements, codes, events, leaderboards.
-- Quest/achievement "Stat" keys are the events counted by QuestService.Track(player, stat, amount):
--   EggsDelivered, PetsHatched, RareHatches (Rare+), TreadmillSeconds, CoinsEarned, Tags,
--   EggsRetrieved (picked up an egg another player dropped and delivered it), Fuses, TrapsSprung,
--   BiomesUnlocked, IndexCount, Rebirths, Biome:<BiomeId> (egg delivered from that biome)

local Progression = {}

-- 7-day streak. Claim once per ClaimCooldown; the streak resets if StreakGrace passes without a claim.
Progression.Daily = {
	ClaimCooldown = 20 * 3600,
	StreakGrace = 48 * 3600,
	Rewards = {
		{ Coins = 500 },
		{ Coins = 1500 },
		{ Shards = 10 },
		{ Coins = 5000, Item = "BearTrap", Amount = 1 },
		{ Shards = 20 },
		{ Coins = 15000, Item = "DecoyEgg", Amount = 2 },
		{ Shards = 50, Egg = "RiftCrate" },
	},
}

-- Coin rewards scale with the player's best unlocked biome: Coins * (IncomeBase of that biome / 2).
Progression.DailyQuestCount = 3
Progression.WeeklyQuestCount = 3
Progression.DailyQuests = {
	{ Id = "d_deliver3", Text = "Deliver 3 eggs to your incubator", Stat = "EggsDelivered", Goal = 3, Coins = 150, Shards = 3 },
	{ Id = "d_hatch5", Text = "Hatch 5 pets", Stat = "PetsHatched", Goal = 5, Coins = 200, Shards = 3 },
	{ Id = "d_train300", Text = "Train on the treadmill for 5 minutes", Stat = "TreadmillSeconds", Goal = 300, Coins = 120, Shards = 2 },
	{ Id = "d_tag3", Text = "Tag 3 rival raiders", Stat = "Tags", Goal = 3, Coins = 150, Shards = 3 },
	{ Id = "d_rare1", Text = "Hatch a Rare or better pet", Stat = "RareHatches", Goal = 1, Coins = 250, Shards = 4 },
	{ Id = "d_earn", Text = "Earn 2,000 coins", Stat = "CoinsEarned", Goal = 2000, Coins = 0, Shards = 4 },
	{ Id = "d_fuse1", Text = "Fuse pets once", Stat = "Fuses", Goal = 1, Coins = 300, Shards = 4 },
}
Progression.WeeklyQuests = {
	{ Id = "w_deliver40", Text = "Deliver 40 eggs", Stat = "EggsDelivered", Goal = 40, Coins = 3000, Shards = 25 },
	{ Id = "w_retrieve5", Text = "Retrieve 5 eggs dropped by rivals", Stat = "EggsRetrieved", Goal = 5, Coins = 2500, Shards = 25 },
	{ Id = "w_rare10", Text = "Hatch 10 Rare or better pets", Stat = "RareHatches", Goal = 10, Coins = 4000, Shards = 30 },
	{ Id = "w_train3600", Text = "Train for 60 minutes", Stat = "TreadmillSeconds", Goal = 3600, Coins = 2000, Shards = 20 },
	{ Id = "w_fuse5", Text = "Fuse 5 times", Stat = "Fuses", Goal = 5, Coins = 4000, Shards = 30 },
}

Progression.Achievements = {
	{ Id = "a_first_egg", Text = "First Heist: deliver your first egg", Stat = "EggsDelivered", Goal = 1, Shards = 5 },
	{ Id = "a_eggs100", Text = "Egg Baron: deliver 100 eggs", Stat = "EggsDelivered", Goal = 100, Shards = 50 },
	{ Id = "a_eggs1000", Text = "Nest Nemesis: deliver 1,000 eggs", Stat = "EggsDelivered", Goal = 1000, Shards = 250 },
	{ Id = "a_tags50", Text = "Foam Fighter: tag 50 raiders", Stat = "Tags", Goal = 50, Shards = 30 },
	{ Id = "a_retrieve25", Text = "Finders Keepers: retrieve 25 dropped eggs", Stat = "EggsRetrieved", Goal = 25, Shards = 40 },
	{ Id = "a_biomes4", Text = "Rift Walker: unlock 4 biomes", Stat = "BiomesUnlocked", Goal = 4, Shards = 25 },
	{ Id = "a_biomes8", Text = "Multiverse Master: unlock all 8 biomes", Stat = "BiomesUnlocked", Goal = 8, Shards = 200 },
	{ Id = "a_index20", Text = "Collector: discover 20 species", Stat = "IndexCount", Goal = 20, Shards = 60 },
	{ Id = "a_fuse10", Text = "Mad Fuser: fuse 10 times", Stat = "Fuses", Goal = 10, Shards = 30 },
	{ Id = "a_rebirth1", Text = "Born Again: rebirth once", Stat = "Rebirths", Goal = 1, Shards = 100 },
	{ Id = "a_traps10", Text = "Trapper: catch 10 raiders in traps", Stat = "TrapsSprung", Goal = 10, Shards = 20 },
}

-- Index: Rift Shards per new species come from Rarities.IndexShards. Completing a biome's index pays this.
Progression.IndexBiomeCompleteShards = 40

-- Bonus codes (case-insensitive). Expires = os.time() UTC seconds, or nil for no expiry.
Progression.Codes = {
	RIFTRAID = { Coins = 1000, Shards = 10 },
	EGGVERSE = { Shards = 25, Expires = nil },
	TRAPPED = { Item = "BearTrap", Amount = 2 },
}

-- Timed events. EventService rotates them; admins can force one with the chat command "/event <Id>".
Progression.Events = {
	RiftStorm = { Name = "Rift Storm", Duration = 300, RarityBoost = 2.0, GuardianSpeedMult = 1.1, EventMutation = "Rift", Color = Color3.fromRGB(0, 255, 170) },
	GoldenHour = { Name = "Golden Hour", Duration = 300, MutationBoost = 3.0, Color = Color3.fromRGB(255, 200, 50) },
	Stampede = { Name = "Egg Stampede", Duration = 180, NestRespawnMult = 0.3, Color = Color3.fromRGB(255, 120, 60) },
}
Progression.EventInterval = { Min = 20 * 60, Max = 30 * 60 }
Progression.DivineSpawn = { CheckInterval = 15 * 60, Chance = 0.35, MinBiome = 6, Lifetime = 240 }

-- Leaderboards (global OrderedDataStore, refreshed every RefreshInterval seconds).
Progression.Leaderboards = {
	RefreshInterval = 120,
	Stats = {
		Speed = { Title = "Fastest Raiders", Key = "SpeedStat" },
		Income = { Title = "Top Income /s", Key = "Income" },
		RarePets = { Title = "Rare Pet Hoarders", Key = "RarePets" },
		Retrievals = { Title = "Egg Retrievals", Key = "EggsRetrieved" },
	},
}

-- Admin UserIds (chat commands /event, /givecoins). Fill in your own.
Progression.Admins = {} :: { number }

return Progression

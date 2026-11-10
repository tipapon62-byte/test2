-- Prices, upgrade tracks, shop items and rebirth. All prices are in coins unless Currency = "Shards".
-- Level 1 of every track is the free starting state. Add levels at the end to extend a track.

local C = Color3.fromRGB

local Economy = {}

Economy.StartCoins = 100
Economy.StartShards = 0
Economy.SellValueSeconds = 30       -- a pet sells for (income/sec * this)
Economy.OfflineIncomeRate = 0.25    -- fraction of income earned while offline
Economy.OfflineIncomeCapSeconds = 2 * 3600
Economy.SpeedUpCoinsPerSecond = 0.6 -- coin cost per remaining hatch second, multiplied by the biome IncomeBase
Economy.SpeedUpSecondsPerShard = 60 -- 1 Rift Shard skips this many seconds

-- 🏠 Base (enclosure) upgrades: pet slots + flat income bonus. Floors 2/3 of the base model appear
-- at the listed level (VisualFloors).
Economy.BaseLevels = {
	{ Slots = 6, IncomeBonus = 0.00, Price = 0, VisualFloors = 1 },
	{ Slots = 8, IncomeBonus = 0.05, Price = 250, VisualFloors = 1 },
	{ Slots = 10, IncomeBonus = 0.10, Price = 900, VisualFloors = 1 },
	{ Slots = 12, IncomeBonus = 0.15, Price = 3000, VisualFloors = 1 },
	{ Slots = 15, IncomeBonus = 0.20, Price = 10000, VisualFloors = 2 },
	{ Slots = 18, IncomeBonus = 0.25, Price = 35000, VisualFloors = 2 },
	{ Slots = 21, IncomeBonus = 0.30, Price = 120000, VisualFloors = 2 },
	{ Slots = 24, IncomeBonus = 0.40, Price = 400000, VisualFloors = 2 },
	{ Slots = 30, IncomeBonus = 0.50, Price = 1500000, VisualFloors = 3 },
	{ Slots = 36, IncomeBonus = 0.65, Price = 5000000, VisualFloors = 3 },
}
Economy.InventoryCap = 80 -- pets kept in storage (not placed) beyond enclosure slots

-- 🏃 Treadmill: Gain = Speed/sec while standing on it (AFK); Efficiency multiplies Gain while
-- actively running; BaseSpeed = flat effective Speed bonus that is always applied.
Economy.TreadmillLevels = {
	{ Name = "Rusty Rift Treadmill", Gain = 1, Efficiency = 1.5, BaseSpeed = 0, Price = 0, Color = C(130, 130, 140) },
	{ Name = "Spring Treadmill", Gain = 2, Efficiency = 1.55, BaseSpeed = 10, Price = 150, Color = C(120, 220, 120) },
	{ Name = "Turbo Treadmill", Gain = 3.5, Efficiency = 1.6, BaseSpeed = 25, Price = 600, Color = C(80, 200, 255) },
	{ Name = "Neon Treadmill", Gain = 6, Efficiency = 1.65, BaseSpeed = 50, Price = 2500, Color = C(80, 255, 170) },
	{ Name = "Plasma Treadmill", Gain = 10, Efficiency = 1.7, BaseSpeed = 100, Price = 9000, Color = C(90, 140, 255) },
	{ Name = "Ion Treadmill", Gain = 16, Efficiency = 1.75, BaseSpeed = 200, Price = 30000, Color = C(170, 90, 255) },
	{ Name = "Quantum Treadmill", Gain = 25, Efficiency = 1.8, BaseSpeed = 400, Price = 100000, Color = C(255, 90, 200) },
	{ Name = "Warp Treadmill", Gain = 40, Efficiency = 1.85, BaseSpeed = 800, Price = 350000, Color = C(255, 170, 40) },
	{ Name = "Singularity Treadmill", Gain = 65, Efficiency = 1.9, BaseSpeed = 1500, Price = 1200000, Color = C(255, 60, 60) },
	{ Name = "Multiverse Treadmill", Gain = 100, Efficiency = 2.0, BaseSpeed = 3000, Price = 4000000, Color = C(0, 255, 170) },
}

-- 🥚 Incubator upgrades: number of eggs hatching at once + hatch-time reduction.
Economy.IncubatorLevels = {
	{ Pads = 1, HatchSpeed = 0.00, Price = 0 },
	{ Pads = 2, HatchSpeed = 0.05, Price = 500 },
	{ Pads = 2, HatchSpeed = 0.10, Price = 4000 },
	{ Pads = 3, HatchSpeed = 0.15, Price = 25000 },
	{ Pads = 3, HatchSpeed = 0.20, Price = 150000 },
	{ Pads = 4, HatchSpeed = 0.30, Price = 900000 },
}

-- ✨ Trails: cosmetic + permanent effective-Speed multiplier while equipped.
Economy.TrailOrder = { "None", "Sparkle", "Leafy", "Bubble", "Ember", "Frost", "Comet", "Aurora", "Prism", "Void" }
Economy.Trails = {
	None = { Name = "No Trail", SpeedMult = 1.0, Price = 0, Colors = { C(255, 255, 255), C(255, 255, 255) } },
	Sparkle = { Name = "Sparkle Trail", SpeedMult = 1.1, Price = 500, Colors = { C(255, 255, 200), C(255, 220, 90) } },
	Leafy = { Name = "Leafy Trail", SpeedMult = 1.2, Price = 3000, Colors = { C(150, 230, 90), C(60, 150, 50) } },
	Bubble = { Name = "Bubble Trail", SpeedMult = 1.35, Price = 15000, Colors = { C(150, 230, 255), C(60, 140, 255) } },
	Ember = { Name = "Ember Trail", SpeedMult = 1.5, Price = 75000, Colors = { C(255, 200, 60), C(255, 60, 20) } },
	Frost = { Name = "Frost Trail", SpeedMult = 1.75, Price = 350000, Colors = { C(230, 250, 255), C(100, 180, 255) } },
	Comet = { Name = "Comet Trail", SpeedMult = 2.0, Price = 1500000, Colors = { C(255, 255, 255), C(170, 120, 255) } },
	Aurora = { Name = "Aurora Trail", SpeedMult = 2.5, Price = 8000000, Colors = { C(90, 255, 180), C(170, 90, 255) } },
	Prism = { Name = "Prism Trail", SpeedMult = 1.6, Price = 150, Currency = "Shards", Colors = { C(255, 100, 200), C(100, 220, 255) } },
	Void = { Name = "Void Trail", SpeedMult = 3.0, Price = 800, Currency = "Shards", Colors = { C(120, 60, 255), C(10, 0, 30) } },
}

-- 🧰 Consumable items. MaxOwned caps stockpiling.
Economy.Items = {
	BearTrap = { Name = "Bear Trap", Price = 250, MaxOwned = 3, Description = "Place on the ground. Snaps shut on the next rival who steps on it." },
	DecoyEgg = { Name = "Decoy Chicken Egg", Price = 120, MaxOwned = 5, Description = "Run over a trap while holding it to disarm the trap safely." },
	MutationPotion = { Name = "Mutation Potion", Price = 40, Currency = "Shards", MaxOwned = 10, Description = "Re-roll a pet's mutation (never downgrades)." },
}

-- 💎 Special eggs bought with Rift Shards go straight into a free incubator pad.
Economy.ShardEggs = {
	{ Id = "RiftCrate", Name = "Rift Crate Egg", Price = 60, Biome = "max", Weights = { Rare = 50, Epic = 35, Legendary = 13, Mythic = 2 } },
	{ Id = "PrismEgg", Name = "Prism Egg", Price = 250, Biome = "max", Weights = { Epic = 50, Legendary = 38, Mythic = 11, Divine = 1 }, ForceMutation = "Rainbow" },
}

-- 🔄 Rebirth: resets coins, Speed, treadmill, base, incubator and biome keys. Keeps pets (extra
-- pets go to storage), index, trails, shards, stats. Each rebirth multiplies income and training.
Economy.Rebirth = {
	BaseCost = 1000000,
	CostGrowth = 2.5,
	RequiredBiome = 6,          -- must own the Emberpeak key
	IncomeBonusPerRebirth = 0.25,
	TrainingBonusPerRebirth = 0.25,
	ShardsPerRebirth = 50,
}

-- 🔀 Fuse machine
Economy.Fuse = {
	Cost = { 100, 2500, 40000, 600000 },  -- coin cost by input tier (tier 1 -> 2 costs Cost[1])
	MutationUpgradeChance = 0.15,         -- chance to roll/upgrade a mutation
	SizeUpgradeChance = 0.10,             -- chance to grow one size step
	BonusEggChance = 0.05,                -- chance to receive a bonus egg (biome of the pet, rarity +1)
	ConfirmValueThreshold = 50,           -- inputs worth more than this many coins/sec need a 2nd confirmation
}

return Economy

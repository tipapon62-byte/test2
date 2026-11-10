-- Rarities, egg sizes and mutations. Ids are persisted in saves: never rename them.

local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine" }

-- HatchTime: seconds in the incubator. IncomeMult: multiplies the species' biome base income.
-- GuardianSpeedMult: how much faster the nest guardian runs after this egg is taken.
-- IndexShards: Rift Shards awarded the first time a species of this rarity is discovered.
Rarities.ById = {
	Common = { Index = 1, Color = Color3.fromRGB(205, 210, 220), HatchTime = 20, IncomeMult = 1, GuardianSpeedMult = 1.00, IndexShards = 1, Announce = false },
	Uncommon = { Index = 2, Color = Color3.fromRGB(110, 230, 120), HatchTime = 45, IncomeMult = 1.6, GuardianSpeedMult = 1.03, IndexShards = 2, Announce = false },
	Rare = { Index = 3, Color = Color3.fromRGB(70, 160, 255), HatchTime = 90, IncomeMult = 2.6, GuardianSpeedMult = 1.06, IndexShards = 3, Announce = false },
	Epic = { Index = 4, Color = Color3.fromRGB(180, 90, 255), HatchTime = 180, IncomeMult = 4.5, GuardianSpeedMult = 1.10, IndexShards = 5, Announce = false },
	Legendary = { Index = 5, Color = Color3.fromRGB(255, 190, 40), HatchTime = 360, IncomeMult = 8, GuardianSpeedMult = 1.14, IndexShards = 10, Announce = false },
	Mythic = { Index = 6, Color = Color3.fromRGB(255, 70, 90), HatchTime = 720, IncomeMult = 15, GuardianSpeedMult = 1.18, IndexShards = 25, Announce = true },
	Divine = { Index = 7, Color = Color3.fromRGB(255, 250, 200), HatchTime = 1500, IncomeMult = 30, GuardianSpeedMult = 1.25, IndexShards = 50, Announce = true },
}

-- Egg sizes are rolled when an egg spawns and carried over to the pet.
-- Carry = walk speed multiplier while carrying. Scale = model scale.
Rarities.SizeOrder = { "Normal", "Large", "Huge" }
Rarities.Sizes = {
	Normal = { Weight = 85, Scale = 1.0, IncomeMult = 1.0, HatchMult = 1.0, Carry = 0.88, KgMult = 1 },
	Large = { Weight = 12, Scale = 1.4, IncomeMult = 1.75, HatchMult = 1.25, Carry = 0.80, KgMult = 2.6 },
	Huge = { Weight = 3, Scale = 1.9, IncomeMult = 3.0, HatchMult = 1.5, Carry = 0.72, KgMult = 6.5 },
}

-- Mutations: rolled when an egg spawns (visible on the egg) and, if none, once more on hatch.
-- Chance is per roll. EventOnly mutations only appear during their event.
Rarities.MutationOrder = { "Silver", "Gold", "Rainbow", "Neon", "Galaxy", "Rift" }
Rarities.Mutations = {
	Silver = { Chance = 0.06, IncomeMult = 1.5, Color = Color3.fromRGB(215, 225, 235), Material = "Metal" },
	Gold = { Chance = 0.025, IncomeMult = 2.5, Color = Color3.fromRGB(255, 200, 50), Material = "Foil" },
	Rainbow = { Chance = 0.008, IncomeMult = 4, Color = Color3.fromRGB(255, 120, 200), Material = "SmoothPlastic", Animated = true },
	Neon = { Chance = 0.004, IncomeMult = 6, Color = Color3.fromRGB(60, 255, 220), Material = "Neon" },
	Galaxy = { Chance = 0.001, IncomeMult = 10, Color = Color3.fromRGB(90, 60, 200), Material = "Glass", Sparkles = true },
	Rift = { Chance = 0.01, IncomeMult = 7, Color = Color3.fromRGB(0, 255, 170), Material = "ForceField", EventOnly = true },
}

-- Fusion tiers: 3 identical pets (same species + same tier) -> 1 pet of the next tier.
Rarities.MaxTier = 5
Rarities.TierIncomeMult = { 1, 3.3, 11, 36, 120 }

return Rarities

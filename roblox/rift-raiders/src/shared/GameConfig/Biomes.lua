-- The 8 shard-universes of the Rift Run, in order along the lane (+X from the hub).
-- Index N maps to workspace.RiftRun.Zones.ZoneN. Ids are persisted: never rename them.
--
-- RequiredSpeed   : effective Speed needed to pass the gate into this biome.
-- RecommendedSpeed: effective Speed at which a Normal Common egg reliably outruns the guardian.
-- UnlockPrice     : one-time coin price for the Rift Key (biome access). Both checks apply.
-- IncomeBase      : coins/sec of a Common, Normal, Tier-1 pet from this biome (rarity multiplies).
-- EggWeights      : rarity spawn weights for this biome's nests.
-- Guardian        : base stats; the egg's rarity multiplies Speed (see Rarities.GuardianSpeedMult).
-- Hazards         : hazard kinds spawned by BiomeService (see HazardTypes in BiomeService).

export type GuardianCfg = {
	Name: string,
	Archetype: string,
	Speed: number,
	DetectRadius: number,
	LeashRadius: number,
	AttackRange: number,
	AttackCooldown: number,
	Knockback: number,
	Size: number,
	Colors: { Color3 },
}

export type BiomeCfg = {
	Id: string,
	Index: number,
	Name: string,
	Kind: string,
	Tagline: string,
	RequiredSpeed: number,
	RecommendedSpeed: number,
	UnlockPrice: number,
	IncomeBase: number,
	NestRespawn: number,
	EggName: string,
	EggPattern: string,
	EggColors: { Color3 },
	EggWeights: { [string]: number },
	Guardian: GuardianCfg,
	Hazards: { string },
	Weather: string?,
	Theme: { Ground: Color3, Accent: Color3, Fog: Color3, Sky: Color3 },
}

local C = Color3.fromRGB

local Biomes: { BiomeCfg } = {
	{
		Id = "RiftLab", Index = 1, Name = "Rift Lab Grounds", Kind = "Starting Zone",
		Tagline = "Where the first tear in the multiverse opened.",
		RequiredSpeed = 0, RecommendedSpeed = 0, UnlockPrice = 0, IncomeBase = 2, NestRespawn = 20,
		EggName = "Lab Egg", EggPattern = "Spots", EggColors = { C(235, 245, 255), C(120, 220, 255) },
		EggWeights = { Common = 70, Uncommon = 22, Rare = 6.5, Epic = 1.4, Legendary = 0.1, Mythic = 0.02 },
		Guardian = { Name = "Beaker Bruiser", Archetype = "Golem", Speed = 13, DetectRadius = 45, LeashRadius = 110,
			AttackRange = 6, AttackCooldown = 2.2, Knockback = 45, Size = 6, Colors = { C(150, 170, 190), C(90, 255, 200) } },
		Hazards = { "GooPuddle" }, Weather = nil,
		Theme = { Ground = C(70, 90, 110), Accent = C(90, 255, 200), Fog = C(170, 220, 255), Sky = C(150, 200, 255) },
	},
	{
		Id = "Mosswood", Index = 2, Name = "Mosswood", Kind = "Forest",
		Tagline = "An ancient forest that grew through the rift overnight.",
		RequiredSpeed = 60, RecommendedSpeed = 120, UnlockPrice = 300, IncomeBase = 6, NestRespawn = 22,
		EggName = "Mossy Egg", EggPattern = "Leaves", EggColors = { C(140, 200, 90), C(80, 130, 50) },
		EggWeights = { Common = 55, Uncommon = 28, Rare = 12, Epic = 4.3, Legendary = 0.7, Mythic = 0.05 },
		Guardian = { Name = "Old Rootmother", Archetype = "Quadruped", Speed = 22, DetectRadius = 55, LeashRadius = 130,
			AttackRange = 7, AttackCooldown = 2.0, Knockback = 55, Size = 8, Colors = { C(95, 70, 45), C(120, 190, 70) } },
		Hazards = { "MudPit", "RollingLog" }, Weather = "Leaves",
		Theme = { Ground = C(70, 120, 55), Accent = C(170, 230, 90), Fog = C(150, 190, 140), Sky = C(170, 215, 170) },
	},
	{
		Id = "GlimmerLake", Index = 3, Name = "Glimmer Lake", Kind = "Lake",
		Tagline = "A drowned universe that glows from the bottom up.",
		RequiredSpeed = 250, RecommendedSpeed = 450, UnlockPrice = 2500, IncomeBase = 18, NestRespawn = 24,
		EggName = "Tide Egg", EggPattern = "Waves", EggColors = { C(90, 190, 255), C(230, 250, 255) },
		EggWeights = { Common = 15, Uncommon = 55, Rare = 28, Epic = 12.5, Legendary = 4, Mythic = 0.5 },
		Guardian = { Name = "Brinejaw Matriarch", Archetype = "Serpent", Speed = 30, DetectRadius = 60, LeashRadius = 140,
			AttackRange = 7, AttackCooldown = 1.9, Knockback = 60, Size = 8, Colors = { C(40, 110, 170), C(120, 240, 255) } },
		Hazards = { "Shallows", "Geyser" }, Weather = "Bubbles",
		Theme = { Ground = C(40, 90, 120), Accent = C(120, 240, 255), Fog = C(60, 140, 180), Sky = C(90, 170, 220) },
	},
	{
		Id = "Sunscorch", Index = 4, Name = "Sunscorch Dunes", Kind = "Desert",
		Tagline = "Three suns, zero shade, one very angry sand wyrm.",
		RequiredSpeed = 900, RecommendedSpeed = 1500, UnlockPrice = 15000, IncomeBase = 50, NestRespawn = 26,
		EggName = "Dune Egg", EggPattern = "Stripes", EggColors = { C(240, 200, 120), C(200, 110, 50) },
		EggWeights = { Common = 12, Uncommon = 48, Rare = 30, Epic = 15, Legendary = 6, Mythic = 1 },
		Guardian = { Name = "Dunecrown Wyrm", Archetype = "Serpent", Speed = 39, DetectRadius = 65, LeashRadius = 150,
			AttackRange = 8, AttackCooldown = 1.8, Knockback = 65, Size = 9, Colors = { C(200, 150, 80), C(255, 220, 120) } },
		Hazards = { "Quicksand", "Tumbleweed" }, Weather = "Sandstorm",
		Theme = { Ground = C(225, 185, 115), Accent = C(255, 140, 60), Fog = C(240, 200, 140), Sky = C(255, 210, 150) },
	},
	{
		Id = "Vinewild", Index = 5, Name = "Vinewild Jungle", Kind = "Jungle",
		Tagline = "Everything here is alive. Some of it is hungry.",
		RequiredSpeed = 3000, RecommendedSpeed = 5000, UnlockPrice = 80000, IncomeBase = 140, NestRespawn = 28,
		EggName = "Vine Egg", EggPattern = "Vines", EggColors = { C(60, 170, 90), C(255, 120, 180) },
		EggWeights = { Common = 10, Rare = 55, Epic = 30, Legendary = 12.5, Mythic = 2.5 },
		Guardian = { Name = "Thornback Alpha", Archetype = "Dino", Speed = 47, DetectRadius = 70, LeashRadius = 160,
			AttackRange = 8, AttackCooldown = 1.7, Knockback = 70, Size = 10, Colors = { C(40, 110, 50), C(255, 90, 140) } },
		Hazards = { "SwingingLog", "ThornBush" }, Weather = "Rain",
		Theme = { Ground = C(40, 100, 45), Accent = C(255, 100, 160), Fog = C(60, 110, 70), Sky = C(110, 170, 120) },
	},
	{
		Id = "Emberpeak", Index = 6, Name = "Emberpeak Caldera", Kind = "Volcano",
		Tagline = "The floor is lava. Literally, in places.",
		RequiredSpeed = 9000, RecommendedSpeed = 15000, UnlockPrice = 400000, IncomeBase = 400, NestRespawn = 30,
		EggName = "Magma Egg", EggPattern = "Cracks", EggColors = { C(50, 35, 35), C(255, 110, 30) },
		EggWeights = { Rare = 50, Epic = 30, Legendary = 15, Mythic = 4.8, Divine = 0.2 },
		Guardian = { Name = "Cindermaw Tyrant", Archetype = "Dino", Speed = 55, DetectRadius = 75, LeashRadius = 170,
			AttackRange = 9, AttackCooldown = 1.6, Knockback = 80, Size = 11, Colors = { C(40, 30, 30), C(255, 100, 20) } },
		Hazards = { "LavaCrack", "EruptionVent" }, Weather = "Ash",
		Theme = { Ground = C(45, 35, 35), Accent = C(255, 100, 20), Fog = C(90, 50, 40), Sky = C(120, 60, 40) },
	},
	{
		Id = "Frostveil", Index = 7, Name = "Frostveil Tundra", Kind = "Frozen Lands",
		Tagline = "A universe paused mid-blizzard. Try not to slide.",
		RequiredSpeed = 25000, RecommendedSpeed = 40000, UnlockPrice = 2000000, IncomeBase = 1100, NestRespawn = 32,
		EggName = "Glacier Egg", EggPattern = "Crystals", EggColors = { C(220, 245, 255), C(120, 190, 255) },
		EggWeights = { Epic = 55, Legendary = 30, Mythic = 14.5, Divine = 0.5 },
		Guardian = { Name = "Hoarfrost Behemoth", Archetype = "Quadruped", Speed = 62, DetectRadius = 80, LeashRadius = 180,
			AttackRange = 9, AttackCooldown = 1.5, Knockback = 85, Size = 12, Colors = { C(200, 230, 255), C(90, 170, 255) } },
		Hazards = { "IceSheet", "FallingIcicle" }, Weather = "Snow",
		Theme = { Ground = C(225, 240, 255), Accent = C(120, 200, 255), Fog = C(210, 230, 250), Sky = C(190, 220, 255) },
	},
	{
		Id = "AstralRuins", Index = 8, Name = "Astral Ruins", Kind = "Space / Ancient World",
		Tagline = "The broken temple at the centre of every universe.",
		RequiredSpeed = 70000, RecommendedSpeed = 110000, UnlockPrice = 10000000, IncomeBase = 3000, NestRespawn = 35,
		EggName = "Astral Egg", EggPattern = "Stars", EggColors = { C(30, 20, 70), C(150, 120, 255) },
		EggWeights = { Epic = 50, Legendary = 32, Mythic = 17, Divine = 1.5 },
		Guardian = { Name = "The Starbound Warden", Archetype = "Golem", Speed = 70, DetectRadius = 85, LeashRadius = 190,
			AttackRange = 10, AttackCooldown = 1.4, Knockback = 95, Size = 13, Colors = { C(40, 30, 80), C(170, 140, 255) } },
		Hazards = { "VoidPit", "MeteorStrike" }, Weather = "Stars",
		Theme = { Ground = C(35, 30, 60), Accent = C(170, 140, 255), Fog = C(40, 30, 80), Sky = C(20, 15, 45) },
	},
}

-- Shared zone geometry of the Rift Run lane (matches the place file; used for gates and fallback zones).
local Layout = {
	StartX = 350,     -- X of the Rift Run entrance (gate of zone 1)
	ZoneLength = 542, -- X length of each zone floor
	ZoneWidth = 343,  -- Z width of each zone floor
	FloorTopY = 0,
}

return { List = Biomes, Layout = Layout }

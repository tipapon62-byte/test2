-- Characters from across the multiverse (internally still "Pets" so saves keep working).
-- Every character has its OWN egg: a nest rolls a rarity from the biome's EggWeights, then picks a
-- character of that biome + rarity and the egg is styled after that character.
--
-- Two kinds of models:
--   * Template = name of a part-built model in ReplicatedStorage.CharacterModels (the classic cast
--     of the original place). ModelFactory restyles it in the brick look.
--   * Archetype = "Hero": a procedural brick minifigure dressed by Costume (original characters).
-- Colors = { Primary (outfit), Secondary (skin/face), Accent } — also used for the character's egg.
-- Costume keys (all optional):
--   Hat  : Wizard Helmet Crown Pirate Cowboy Ninja Knight Chef Hood Horns Mohawk Cap Antenna TopHat Beanie Headphones
--   Face : Visor Goggles Mask Beard Eyepatch Glasses Scarf
--   Body : Robot Armor Robe Suit Ghost Jacket Dress
--   Back : Cape Jetpack Wings Backpack Quiver
--   Item : Staff Sword Blaster Shield Wrench Guitar Book Lantern Pickaxe Trident Hammer Bow Torch Clipboard Lasso Camera Scroll
--   Aura : Fire Ice Stars Void Gold Electric
-- Kg: weight range at Normal size. Ids are persisted in saves: never rename them.

export type Species = {
	Id: string,
	Name: string,
	Biome: string,
	Rarity: string,
	Archetype: string,
	Features: { string },
	Colors: { Color3 },
	Kg: { number },
	EventOnly: boolean?,
	Template: string?,
	Costume: { [string]: string }?,
	Universe: string?,
}

local C = Color3.fromRGB

local Pets: { Species } = {
	-- ===== 1. Rift Lab Grounds — the Mad Science universe =====
	{ Id = "PanicGrandson", Name = "Panicking Grandson", Biome = "RiftLab", Rarity = "Common", Template = "PanicGrandson", Archetype = "Hero", Features = {}, Colors = { C(255, 220, 120), C(255, 240, 220), C(90, 160, 255) }, Kg = { 30, 45 }, Costume = { Item = "Clipboard" } },
	{ Id = "LabInternZip", Name = "Lab Intern Zip", Biome = "RiftLab", Rarity = "Uncommon", Archetype = "Hero", Features = {}, Colors = { C(245, 245, 250), C(255, 214, 170), C(90, 255, 200) }, Kg = { 40, 55 }, Costume = { Face = "Goggles", Body = "Jacket", Item = "Wrench", Hat = "Mohawk" } },
	{ Id = "ButterRobot", Name = "Butter-Passing Robot", Biome = "RiftLab", Rarity = "Rare", Template = "ButterRobot", Archetype = "Hero", Features = {}, Colors = { C(190, 195, 205), C(240, 240, 245), C(90, 255, 200) }, Kg = { 3, 6 }, Costume = { Body = "Robot", Hat = "Antenna" } },
	{ Id = "HelperBlue", Name = "Blue Helper Dude", Biome = "RiftLab", Rarity = "Epic", Template = "HelperBlue", Archetype = "Hero", Features = {}, Colors = { C(90, 170, 255), C(200, 230, 255), C(255, 255, 255) }, Kg = { 50, 80 } },
	{ Id = "PickleScientist", Name = "Pickle Scientist", Biome = "RiftLab", Rarity = "Legendary", Template = "PickleScientist", Archetype = "Hero", Features = {}, Colors = { C(120, 200, 80), C(200, 240, 160), C(60, 120, 40) }, Kg = { 0.5, 1 }, Costume = { Face = "Goggles" } },
	{ Id = "MadGrandpa", Name = "Mad Scientist Grandpa", Biome = "RiftLab", Rarity = "Mythic", Template = "MadGrandpa", Archetype = "Hero", Features = {}, Colors = { C(200, 210, 230), C(255, 255, 255), C(120, 220, 255) }, Kg = { 60, 75 }, Costume = { Body = "Jacket", Item = "Blaster" } },

	-- ===== 2. Mosswood — the Yellow Town universe =====
	{ Id = "SlingshotKid", Name = "Slingshot Troublemaker", Biome = "Mosswood", Rarity = "Common", Template = "SlingshotKid", Archetype = "Hero", Features = {}, Colors = { C(255, 220, 60), C(255, 140, 60), C(60, 120, 255) }, Kg = { 25, 35 }, Costume = { Hat = "Mohawk" } },
	{ Id = "RangerPip", Name = "Forest Ranger Pip", Biome = "Mosswood", Rarity = "Uncommon", Archetype = "Hero", Features = {}, Colors = { C(90, 150, 70), C(255, 214, 170), C(200, 150, 80) }, Kg = { 35, 50 }, Costume = { Hat = "Cowboy", Body = "Jacket", Item = "Lantern", Back = "Backpack" } },
	{ Id = "DonutDad", Name = "Donut Dad", Biome = "Mosswood", Rarity = "Rare", Template = "DonutDad", Archetype = "Hero", Features = {}, Colors = { C(255, 220, 60), C(255, 255, 255), C(255, 130, 200) }, Kg = { 110, 140 } },
	{ Id = "TowerHairMom", Name = "Blue Tower Hair Mom", Biome = "Mosswood", Rarity = "Epic", Template = "TowerHairMom", Archetype = "Hero", Features = {}, Colors = { C(255, 220, 60), C(60, 110, 255), C(120, 220, 120) }, Kg = { 55, 70 }, Costume = { Body = "Dress" } },
	{ Id = "GreedyBoss", Name = "Greedy Old Boss", Biome = "Mosswood", Rarity = "Legendary", Template = "GreedyBoss", Archetype = "Hero", Features = {}, Colors = { C(255, 220, 60), C(80, 70, 90), C(255, 200, 50) }, Kg = { 45, 60 }, Costume = { Body = "Suit", Hat = "TopHat" } },
	{ Id = "ThreeEyedFish", Name = "Three-Eyed Fish King", Biome = "Mosswood", Rarity = "Mythic", Template = "ThreeEyedFish", Archetype = "Hero", Features = {}, Colors = { C(255, 150, 40), C(255, 230, 160), C(120, 255, 120) }, Kg = { 8, 15 }, Costume = { Hat = "Crown" } },

	-- ===== 3. Glimmer Lake — the Bikini Deep universe =====
	{ Id = "PinkStar", Name = "Pink Starfish", Biome = "GlimmerLake", Rarity = "Common", Template = "PinkStar", Archetype = "Hero", Features = {}, Colors = { C(255, 150, 190), C(255, 210, 225), C(120, 220, 120) }, Kg = { 4, 8 } },
	{ Id = "DiverBubbles", Name = "Deep-Sea Diver Bubbles", Biome = "GlimmerLake", Rarity = "Uncommon", Archetype = "Hero", Features = {}, Colors = { C(255, 170, 40), C(255, 214, 170), C(120, 220, 255) }, Kg = { 60, 80 }, Costume = { Hat = "Helmet", Back = "Jetpack", Item = "Lantern" } },
	{ Id = "GrumpySquid", Name = "Grumpy Squid", Biome = "GlimmerLake", Rarity = "Rare", Template = "GrumpySquid", Archetype = "Hero", Features = {}, Colors = { C(150, 210, 200), C(220, 245, 240), C(120, 90, 60) }, Kg = { 15, 25 }, Costume = { Item = "Guitar" } },
	{ Id = "SquareSponge", Name = "Square Sponge", Biome = "GlimmerLake", Rarity = "Epic", Template = "SquareSponge", Archetype = "Hero", Features = {}, Colors = { C(255, 235, 80), C(255, 255, 200), C(160, 110, 60) }, Kg = { 1, 2 } },
	{ Id = "MoneyCrab", Name = "Millionaire Crab", Biome = "GlimmerLake", Rarity = "Legendary", Template = "MoneyCrab", Archetype = "Hero", Features = {}, Colors = { C(230, 60, 50), C(255, 200, 180), C(255, 210, 60) }, Kg = { 20, 35 }, Costume = { Aura = "Gold" } },
	{ Id = "GhostCaptain", Name = "Flying Ghost Captain", Biome = "GlimmerLake", Rarity = "Mythic", Template = "GhostCaptain", Archetype = "Hero", Features = {}, Colors = { C(140, 255, 200), C(220, 255, 240), C(60, 60, 80) }, Kg = { 0.1, 0.5 }, Costume = { Body = "Ghost", Hat = "Pirate", Item = "Sword" } },

	-- ===== 4. Sunscorch Dunes — the Meme universe =====
	{ Id = "ToiletHead", Name = "Toilet Head", Biome = "Sunscorch", Rarity = "Common", Template = "ToiletHead", Archetype = "Hero", Features = {}, Colors = { C(245, 245, 250), C(255, 255, 255), C(90, 160, 255) }, Kg = { 20, 30 } },
	{ Id = "CowboyDusty", Name = "Desert Cowboy Dusty", Biome = "Sunscorch", Rarity = "Uncommon", Archetype = "Hero", Features = {}, Colors = { C(170, 110, 60), C(255, 214, 170), C(240, 200, 80) }, Kg = { 60, 80 }, Costume = { Hat = "Cowboy", Face = "Scarf", Item = "Lasso", Body = "Jacket" } },
	{ Id = "SneakerShark", Name = "Shark In Sneakers", Biome = "Sunscorch", Rarity = "Rare", Template = "SneakerShark", Archetype = "Hero", Features = {}, Colors = { C(90, 140, 200), C(230, 240, 250), C(255, 255, 255) }, Kg = { 80, 140 } },
	{ Id = "CappuccinoBallerina", Name = "Cappuccino Ballerina", Biome = "Sunscorch", Rarity = "Epic", Template = "CappuccinoBallerina", Archetype = "Hero", Features = {}, Colors = { C(190, 140, 100), C(255, 240, 225), C(255, 170, 200) }, Kg = { 2, 4 }, Costume = { Body = "Dress" } },
	{ Id = "WoodenDrummer", Name = "Wooden Drummer", Biome = "Sunscorch", Rarity = "Legendary", Template = "WoodenDrummer", Archetype = "Hero", Features = {}, Colors = { C(180, 130, 80), C(230, 190, 140), C(200, 60, 60) }, Kg = { 15, 25 } },
	{ Id = "CrocBomber", Name = "Crocodile Bomber Jet", Biome = "Sunscorch", Rarity = "Mythic", Template = "CrocBomber", Archetype = "Hero", Features = {}, Colors = { C(80, 150, 70), C(200, 230, 160), C(150, 150, 160) }, Kg = { 300, 500 }, Costume = { Back = "Jetpack" } },

	-- ===== 5. Vinewild Jungle — the Anime dimension =====
	{ Id = "HeadbandRookie", Name = "Headband Rookie", Biome = "Vinewild", Rarity = "Common", Template = "HeadbandRookie", Archetype = "Hero", Features = {}, Colors = { C(255, 150, 40), C(255, 220, 180), C(40, 60, 120) }, Kg = { 40, 50 }, Costume = { Hat = "Ninja" } },
	{ Id = "JungleScoutKiko", Name = "Jungle Scout Kiko", Biome = "Vinewild", Rarity = "Uncommon", Archetype = "Hero", Features = {}, Colors = { C(70, 140, 70), C(255, 214, 170), C(255, 120, 180) }, Kg = { 35, 50 }, Costume = { Hat = "Beanie", Item = "Bow", Back = "Quiver", Body = "Jacket" } },
	{ Id = "RamenNinja", Name = "Ramen Ninja", Biome = "Vinewild", Rarity = "Rare", Template = "RamenNinja", Archetype = "Hero", Features = {}, Colors = { C(60, 60, 80), C(255, 220, 180), C(255, 200, 60) }, Kg = { 45, 55 }, Costume = { Hat = "Ninja", Face = "Mask" } },
	{ Id = "BigSwordBoy", Name = "Guy With A Huge Sword", Biome = "Vinewild", Rarity = "Epic", Template = "BigSwordBoy", Archetype = "Hero", Features = {}, Colors = { C(40, 40, 50), C(255, 220, 180), C(180, 180, 200) }, Kg = { 60, 70 }, Costume = { Item = "Sword" } },
	{ Id = "SpikyHairPrince", Name = "Spiky-Haired Prince", Biome = "Vinewild", Rarity = "Legendary", Template = "SpikyHairPrince", Archetype = "Hero", Features = {}, Colors = { C(60, 60, 150), C(255, 220, 180), C(255, 230, 80) }, Kg = { 55, 65 }, Costume = { Aura = "Electric" } },
	{ Id = "OnePunchBald", Name = "Bald One-Punch Hero", Biome = "Vinewild", Rarity = "Mythic", Template = "OnePunchBald", Archetype = "Hero", Features = {}, Colors = { C(255, 230, 60), C(255, 225, 190), C(230, 40, 40) }, Kg = { 65, 75 }, Costume = { Back = "Cape" } },

	-- ===== 6. Emberpeak Caldera — the Forge universe (original heroes) =====
	{ Id = "LavaKnightEmber", Name = "Lava Knight Ember", Biome = "Emberpeak", Rarity = "Rare", Archetype = "Hero", Features = {}, Colors = { C(70, 60, 65), C(255, 214, 170), C(255, 110, 30) }, Kg = { 90, 120 }, Costume = { Hat = "Knight", Body = "Armor", Item = "Sword", Back = "Cape" } },
	{ Id = "FireMageBlaze", Name = "Fire Mage Blaze", Biome = "Emberpeak", Rarity = "Epic", Archetype = "Hero", Features = {}, Colors = { C(200, 40, 40), C(255, 214, 170), C(255, 200, 60) }, Kg = { 50, 65 }, Costume = { Hat = "Wizard", Body = "Robe", Item = "Staff", Aura = "Fire" } },
	{ Id = "ForgeTitanBrick", Name = "Forge Titan Brick", Biome = "Emberpeak", Rarity = "Legendary", Archetype = "Hero", Features = {}, Colors = { C(110, 90, 80), C(230, 170, 130), C(255, 140, 40) }, Kg = { 200, 300 }, Costume = { Face = "Beard", Body = "Armor", Item = "Hammer", Hat = "Horns" } },
	{ Id = "ScorchRider", Name = "Scorch the Volcano Rider", Biome = "Emberpeak", Rarity = "Mythic", Archetype = "Hero", Features = {}, Colors = { C(40, 35, 45), C(255, 214, 170), C(255, 80, 20) }, Kg = { 70, 90 }, Costume = { Hat = "Helmet", Face = "Visor", Back = "Wings", Item = "Trident", Aura = "Fire" } },
	{ Id = "PhoenixQueenSolara", Name = "Phoenix Queen Solara", Biome = "Emberpeak", Rarity = "Divine", Archetype = "Hero", Features = {}, Colors = { C(255, 140, 30), C(255, 230, 200), C(255, 240, 120) }, Kg = { 55, 70 }, Costume = { Hat = "Crown", Body = "Dress", Back = "Wings", Item = "Torch", Aura = "Gold" } },

	-- ===== 7. Frostveil Tundra — the Frozen universe (original heroes) =====
	{ Id = "SnowRangerFlurry", Name = "Snow Ranger Flurry", Biome = "Frostveil", Rarity = "Epic", Archetype = "Hero", Features = {}, Colors = { C(80, 140, 220), C(255, 220, 200), C(240, 250, 255) }, Kg = { 50, 65 }, Costume = { Hat = "Beanie", Face = "Scarf", Item = "Pickaxe", Body = "Jacket" } },
	{ Id = "IceWizardFrostbeard", Name = "Ice Wizard Frostbeard", Biome = "Frostveil", Rarity = "Legendary", Archetype = "Hero", Features = {}, Colors = { C(120, 190, 255), C(255, 225, 205), C(230, 250, 255) }, Kg = { 60, 75 }, Costume = { Hat = "Wizard", Face = "Beard", Body = "Robe", Item = "Staff", Aura = "Ice" } },
	{ Id = "FrostQueenGlacia", Name = "Frost Queen Glacia", Biome = "Frostveil", Rarity = "Mythic", Archetype = "Hero", Features = {}, Colors = { C(170, 220, 255), C(240, 245, 255), C(120, 160, 255) }, Kg = { 50, 60 }, Costume = { Hat = "Crown", Body = "Dress", Back = "Cape", Item = "Staff", Aura = "Ice" } },
	{ Id = "AuroraPaladin", Name = "Aurora Paladin", Biome = "Frostveil", Rarity = "Divine", Archetype = "Hero", Features = {}, Colors = { C(230, 240, 255), C(255, 225, 205), C(150, 120, 255) }, Kg = { 120, 160 }, Costume = { Hat = "Knight", Body = "Armor", Back = "Wings", Item = "Shield", Aura = "Stars" } },

	-- ===== 8. Astral Ruins — the Multiverse core =====
	{ Id = "SpaceCadetNova", Name = "Space Cadet Nova", Biome = "AstralRuins", Rarity = "Epic", Archetype = "Hero", Features = {}, Colors = { C(240, 240, 250), C(255, 214, 170), C(120, 90, 255) }, Kg = { 60, 80 }, Costume = { Hat = "Helmet", Back = "Jetpack", Item = "Blaster" } },
	{ Id = "StarPilotOrion", Name = "Star Pilot Orion", Biome = "AstralRuins", Rarity = "Legendary", Archetype = "Hero", Features = {}, Colors = { C(40, 50, 110), C(255, 214, 170), C(255, 220, 90) }, Kg = { 65, 80 }, Costume = { Hat = "Headphones", Face = "Visor", Body = "Jacket", Back = "Jetpack", Item = "Blaster", Aura = "Stars" } },
	{ Id = "VoidSorcererNyx", Name = "Void Sorcerer Nyx", Biome = "AstralRuins", Rarity = "Mythic", Archetype = "Hero", Features = {}, Colors = { C(50, 30, 90), C(220, 200, 255), C(190, 120, 255) }, Kg = { 50, 60 }, Costume = { Hat = "Hood", Body = "Robe", Item = "Book", Aura = "Void" } },
	{ Id = "MultiverseEgg", Name = "Cosmic Egg Lord", Biome = "AstralRuins", Rarity = "Divine", Template = "MultiverseEgg", Archetype = "Hero", Features = {}, Colors = { C(0, 255, 170), C(230, 255, 250), C(255, 220, 90) }, Kg = { 100, 200 }, Costume = { Hat = "Crown", Aura = "Stars" } },
	{ Id = "GrandpaOfAll", Name = "Grandpa of All Dimensions", Biome = "AstralRuins", Rarity = "Divine", Template = "GrandpaOfAll", Archetype = "Hero", Features = {}, Colors = { C(90, 60, 200), C(230, 220, 255), C(0, 255, 200) }, Kg = { 60, 80 }, Costume = { Body = "Robe", Item = "Staff", Aura = "Stars" } },
	{ Id = "GlitchTwin", Name = "Glitched Twin From Another Timeline", Biome = "AstralRuins", Rarity = "Divine", Template = "GlitchTwin", Archetype = "Hero", Features = {}, Colors = { C(255, 60, 200), C(255, 220, 245), C(60, 255, 255) }, Kg = { 30, 45 }, Costume = { Aura = "Electric" } },

	-- Event-only (Rift Storm Divine egg)
	{ Id = "RiftSovereign", Name = "Rift Sovereign", Biome = "AstralRuins", Rarity = "Divine", Archetype = "Hero", Features = {}, Colors = { C(0, 230, 170), C(230, 255, 250), C(170, 90, 255) }, Kg = { 80, 120 }, EventOnly = true, Costume = { Hat = "Crown", Body = "Armor", Back = "Cape", Item = "Sword", Aura = "Void" } },
}

-- Removed animal species from older versions -> {biome, rarity}. Saved pets of these species are
-- converted into a character of the same biome and rarity on load (tier/size/mutation kept).
local Legacy = {
	Sproutpup = { "RiftLab", "Common" }, BoltChick = { "RiftLab", "Uncommon" }, GooNibbler = { "RiftLab", "Rare" },
	GearbackRaptor = { "RiftLab", "Epic" }, FlaskwingOwl = { "RiftLab", "Legendary" },
	AcornHopper = { "Mosswood", "Common" }, Fernfawn = { "Mosswood", "Uncommon" }, MushcapToad = { "Mosswood", "Rare" },
	BarkhideRex = { "Mosswood", "Epic" }, ElderOakwing = { "Mosswood", "Legendary" },
	PuddlePaddler = { "GlimmerLake", "Uncommon" }, RippleNewt = { "GlimmerLake", "Rare" }, ShellbackTurtle = { "GlimmerLake", "Epic" },
	TidefinSerpent = { "GlimmerLake", "Legendary" }, PearlLeviathan = { "GlimmerLake", "Mythic" },
	DuneSkitter = { "Sunscorch", "Uncommon" }, CactusPuffer = { "Sunscorch", "Rare" }, SandhornLizard = { "Sunscorch", "Epic" },
	SunscaleRaptor = { "Sunscorch", "Legendary" }, Sphinxling = { "Sunscorch", "Mythic" },
	LeafbackGecko = { "Vinewild", "Rare" }, ToucanGlider = { "Vinewild", "Epic" }, ThornjawCroc = { "Vinewild", "Legendary" },
	OrchidRaptor = { "Vinewild", "Mythic" },
	CinderImp = { "Emberpeak", "Rare" }, MagmaBeetle = { "Emberpeak", "Epic" }, LavafinSalamander = { "Emberpeak", "Legendary" },
	ObsidianRex = { "Emberpeak", "Mythic" }, PhoenixHatchling = { "Emberpeak", "Divine" },
	SnowpuffSeal = { "Frostveil", "Epic" }, IcehornYak = { "Frostveil", "Legendary" }, GlacierDrake = { "Frostveil", "Mythic" },
	AuroraStag = { "Frostveil", "Divine" },
	StarlingWisp = { "AstralRuins", "Epic" }, RuinGolem = { "AstralRuins", "Legendary" }, CometSerpent = { "AstralRuins", "Mythic" },
	CelestialSphinx = { "AstralRuins", "Divine" },
}

return { List = Pets, Legacy = Legacy }

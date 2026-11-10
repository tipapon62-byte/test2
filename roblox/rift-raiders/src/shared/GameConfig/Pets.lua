-- Pet species. Each species belongs to one biome and has a fixed rarity: when an egg of rarity R
-- from biome B hatches, a random species with Biome == B and Rarity == R is chosen
-- (falling back to the closest lower rarity in that biome).
--
-- Archetype + Features + Colors drive ModelFactory.BuildPet (procedural, stylised models).
--   Archetypes: Quadruped | Dino | Bird | Blob | Serpent | Bug | Floaty | Golem
--   Features  : Leaves Antlers Horns Wings Fins Spikes Plates Flame Crystal Mushroom Antenna
--               Shell Crown Halo Stars Runes Ears Beak Tusks Flower Bolt Goggles
-- Kg: weight range of a Normal-size pet (sizes multiply it).
-- Ids are persisted in saves: never rename them. Add new species at the end of a biome block.

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
}

local C = Color3.fromRGB

local Pets: { Species } = {
	-- 1. Rift Lab Grounds
	{ Id = "Sproutpup", Name = "Sproutpup", Biome = "RiftLab", Rarity = "Common", Archetype = "Quadruped", Features = { "Leaves", "Ears" }, Colors = { C(150, 220, 110), C(250, 245, 220), C(90, 160, 60) }, Kg = { 2, 5 } },
	{ Id = "BoltChick", Name = "Bolt Chick", Biome = "RiftLab", Rarity = "Uncommon", Archetype = "Bird", Features = { "Bolt", "Beak" }, Colors = { C(255, 225, 80), C(255, 255, 230), C(255, 140, 40) }, Kg = { 1, 3 } },
	{ Id = "GooNibbler", Name = "Goo Nibbler", Biome = "RiftLab", Rarity = "Rare", Archetype = "Blob", Features = { "Antenna" }, Colors = { C(80, 230, 200), C(200, 255, 245), C(40, 150, 140) }, Kg = { 3, 7 } },
	{ Id = "GearbackRaptor", Name = "Gearback Raptor", Biome = "RiftLab", Rarity = "Epic", Archetype = "Dino", Features = { "Plates", "Goggles" }, Colors = { C(255, 150, 60), C(240, 230, 220), C(120, 130, 150) }, Kg = { 15, 30 } },
	{ Id = "FlaskwingOwl", Name = "Flaskwing Owl", Biome = "RiftLab", Rarity = "Legendary", Archetype = "Bird", Features = { "Wings", "Crystal", "Goggles" }, Colors = { C(170, 110, 255), C(240, 225, 255), C(90, 255, 200) }, Kg = { 4, 9 } },

	-- 2. Mosswood (Forest)
	{ Id = "AcornHopper", Name = "Acorn Hopper", Biome = "Mosswood", Rarity = "Common", Archetype = "Quadruped", Features = { "Ears", "Tail" }, Colors = { C(190, 130, 80), C(250, 230, 200), C(110, 70, 40) }, Kg = { 2, 4 } },
	{ Id = "Fernfawn", Name = "Fernfawn", Biome = "Mosswood", Rarity = "Uncommon", Archetype = "Quadruped", Features = { "Antlers", "Leaves" }, Colors = { C(200, 150, 100), C(255, 240, 220), C(110, 190, 80) }, Kg = { 10, 22 } },
	{ Id = "MushcapToad", Name = "Mushcap Toad", Biome = "Mosswood", Rarity = "Rare", Archetype = "Blob", Features = { "Mushroom" }, Colors = { C(120, 170, 90), C(240, 240, 220), C(230, 60, 60) }, Kg = { 3, 8 } },
	{ Id = "BarkhideRex", Name = "Barkhide Rex", Biome = "Mosswood", Rarity = "Epic", Archetype = "Dino", Features = { "Leaves", "Spikes" }, Colors = { C(120, 85, 55), C(200, 170, 120), C(100, 180, 70) }, Kg = { 40, 80 } },
	{ Id = "ElderOakwing", Name = "Elder Oakwing", Biome = "Mosswood", Rarity = "Legendary", Archetype = "Bird", Features = { "Wings", "Leaves", "Crown" }, Colors = { C(90, 160, 70), C(240, 220, 150), C(255, 200, 60) }, Kg = { 6, 12 } },

	-- 3. Glimmer Lake
	{ Id = "PuddlePaddler", Name = "Puddle Paddler", Biome = "GlimmerLake", Rarity = "Uncommon", Archetype = "Bird", Features = { "Beak" }, Colors = { C(120, 200, 255), C(255, 255, 255), C(255, 170, 60) }, Kg = { 2, 5 } },
	{ Id = "RippleNewt", Name = "Ripple Newt", Biome = "GlimmerLake", Rarity = "Rare", Archetype = "Quadruped", Features = { "Fins", "Tail" }, Colors = { C(70, 220, 230), C(210, 255, 255), C(30, 120, 170) }, Kg = { 1, 3 } },
	{ Id = "ShellbackTurtle", Name = "Shellback Turtle", Biome = "GlimmerLake", Rarity = "Epic", Archetype = "Quadruped", Features = { "Shell" }, Colors = { C(110, 190, 130), C(230, 245, 220), C(60, 120, 170) }, Kg = { 25, 60 } },
	{ Id = "TidefinSerpent", Name = "Tidefin Serpent", Biome = "GlimmerLake", Rarity = "Legendary", Archetype = "Serpent", Features = { "Fins", "Horns" }, Colors = { C(40, 130, 220), C(200, 245, 255), C(120, 255, 240) }, Kg = { 30, 70 } },
	{ Id = "PearlLeviathan", Name = "Pearl Leviathan", Biome = "GlimmerLake", Rarity = "Mythic", Archetype = "Serpent", Features = { "Fins", "Crystal", "Crown" }, Colors = { C(250, 230, 245), C(255, 255, 255), C(255, 150, 210) }, Kg = { 80, 160 } },

	-- 4. Sunscorch Dunes (Desert)
	{ Id = "DuneSkitter", Name = "Dune Skitter", Biome = "Sunscorch", Rarity = "Uncommon", Archetype = "Bug", Features = { "Antenna", "Shell" }, Colors = { C(230, 180, 100), C(255, 235, 190), C(170, 100, 50) }, Kg = { 1, 2 } },
	{ Id = "CactusPuffer", Name = "Cactus Puffer", Biome = "Sunscorch", Rarity = "Rare", Archetype = "Blob", Features = { "Spikes", "Flower" }, Colors = { C(90, 180, 90), C(220, 250, 200), C(255, 120, 180) }, Kg = { 4, 9 } },
	{ Id = "SandhornLizard", Name = "Sandhorn Lizard", Biome = "Sunscorch", Rarity = "Epic", Archetype = "Quadruped", Features = { "Horns", "Spikes", "Tail" }, Colors = { C(220, 150, 80), C(255, 230, 180), C(150, 80, 40) }, Kg = { 8, 18 } },
	{ Id = "SunscaleRaptor", Name = "Sunscale Raptor", Biome = "Sunscorch", Rarity = "Legendary", Archetype = "Dino", Features = { "Plates", "Crown" }, Colors = { C(255, 190, 60), C(255, 245, 210), C(220, 90, 40) }, Kg = { 35, 70 } },
	{ Id = "Sphinxling", Name = "Sphinxling", Biome = "Sunscorch", Rarity = "Mythic", Archetype = "Quadruped", Features = { "Wings", "Crown", "Ears" }, Colors = { C(240, 200, 110), C(255, 250, 230), C(60, 110, 220) }, Kg = { 20, 45 } },

	-- 5. Vinewild Jungle
	{ Id = "LeafbackGecko", Name = "Leafback Gecko", Biome = "Vinewild", Rarity = "Rare", Archetype = "Quadruped", Features = { "Leaves", "Tail" }, Colors = { C(90, 210, 90), C(230, 255, 200), C(255, 200, 40) }, Kg = { 1, 3 } },
	{ Id = "ToucanGlider", Name = "Toucan Glider", Biome = "Vinewild", Rarity = "Epic", Archetype = "Bird", Features = { "Wings", "Beak" }, Colors = { C(40, 40, 50), C(255, 255, 240), C(255, 150, 30) }, Kg = { 2, 5 } },
	{ Id = "ThornjawCroc", Name = "Thornjaw Croc", Biome = "Vinewild", Rarity = "Legendary", Archetype = "Serpent", Features = { "Spikes", "Tusks" }, Colors = { C(70, 130, 60), C(210, 230, 160), C(255, 90, 140) }, Kg = { 60, 120 } },
	{ Id = "OrchidRaptor", Name = "Orchid Raptor", Biome = "Vinewild", Rarity = "Mythic", Archetype = "Dino", Features = { "Flower", "Leaves", "Crown" }, Colors = { C(255, 130, 200), C(255, 240, 250), C(80, 200, 100) }, Kg = { 40, 85 } },

	-- 6. Emberpeak Caldera (Volcano)
	{ Id = "CinderImp", Name = "Cinder Imp", Biome = "Emberpeak", Rarity = "Rare", Archetype = "Blob", Features = { "Flame", "Horns" }, Colors = { C(255, 110, 40), C(255, 220, 140), C(60, 30, 30) }, Kg = { 2, 6 } },
	{ Id = "MagmaBeetle", Name = "Magma Beetle", Biome = "Emberpeak", Rarity = "Epic", Archetype = "Bug", Features = { "Shell", "Horns", "Flame" }, Colors = { C(50, 35, 35), C(255, 170, 60), C(255, 80, 20) }, Kg = { 5, 12 } },
	{ Id = "LavafinSalamander", Name = "Lavafin Salamander", Biome = "Emberpeak", Rarity = "Legendary", Archetype = "Serpent", Features = { "Fins", "Flame" }, Colors = { C(230, 70, 30), C(255, 210, 120), C(255, 240, 60) }, Kg = { 25, 55 } },
	{ Id = "ObsidianRex", Name = "Obsidian Rex", Biome = "Emberpeak", Rarity = "Mythic", Archetype = "Dino", Features = { "Horns", "Spikes", "Flame" }, Colors = { C(30, 25, 35), C(90, 80, 100), C(255, 90, 20) }, Kg = { 120, 240 } },
	{ Id = "PhoenixHatchling", Name = "Phoenix Hatchling", Biome = "Emberpeak", Rarity = "Divine", Archetype = "Bird", Features = { "Wings", "Flame", "Halo", "Crown" }, Colors = { C(255, 140, 30), C(255, 240, 180), C(255, 60, 60) }, Kg = { 8, 16 } },

	-- 7. Frostveil Tundra (Frozen Lands)
	{ Id = "SnowpuffSeal", Name = "Snowpuff Seal", Biome = "Frostveil", Rarity = "Epic", Archetype = "Blob", Features = { "Fins", "Ears" }, Colors = { C(240, 248, 255), C(255, 255, 255), C(140, 190, 230) }, Kg = { 20, 45 } },
	{ Id = "IcehornYak", Name = "Icehorn Yak", Biome = "Frostveil", Rarity = "Legendary", Archetype = "Quadruped", Features = { "Horns", "Crystal" }, Colors = { C(170, 200, 230), C(245, 250, 255), C(90, 170, 255) }, Kg = { 150, 300 } },
	{ Id = "GlacierDrake", Name = "Glacier Drake", Biome = "Frostveil", Rarity = "Mythic", Archetype = "Dino", Features = { "Wings", "Crystal", "Horns" }, Colors = { C(120, 200, 255), C(235, 250, 255), C(60, 120, 230) }, Kg = { 90, 180 } },
	{ Id = "AuroraStag", Name = "Aurora Stag", Biome = "Frostveil", Rarity = "Divine", Archetype = "Quadruped", Features = { "Antlers", "Crystal", "Halo" }, Colors = { C(200, 255, 240), C(255, 255, 255), C(150, 120, 255) }, Kg = { 70, 140 } },

	-- 8. Astral Ruins (Space / Ancient World)
	{ Id = "StarlingWisp", Name = "Starling Wisp", Biome = "AstralRuins", Rarity = "Epic", Archetype = "Floaty", Features = { "Stars", "Antenna" }, Colors = { C(150, 130, 255), C(240, 235, 255), C(255, 240, 120) }, Kg = { 0.5, 1.5 } },
	{ Id = "RuinGolem", Name = "Ruin Golem", Biome = "AstralRuins", Rarity = "Legendary", Archetype = "Golem", Features = { "Runes", "Crystal" }, Colors = { C(120, 110, 140), C(200, 190, 210), C(140, 220, 255) }, Kg = { 300, 600 } },
	{ Id = "CometSerpent", Name = "Comet Serpent", Biome = "AstralRuins", Rarity = "Mythic", Archetype = "Serpent", Features = { "Stars", "Horns", "Fins" }, Colors = { C(40, 30, 90), C(170, 150, 255), C(255, 255, 255) }, Kg = { 50, 110 } },
	{ Id = "CelestialSphinx", Name = "Celestial Sphinx", Biome = "AstralRuins", Rarity = "Divine", Archetype = "Quadruped", Features = { "Wings", "Halo", "Runes", "Crown" }, Colors = { C(60, 50, 130), C(230, 220, 255), C(255, 220, 100) }, Kg = { 60, 130 } },

	-- Event-only (Rift Storm Divine egg)
	{ Id = "RiftSovereign", Name = "Rift Sovereign", Biome = "AstralRuins", Rarity = "Divine", Archetype = "Dino", Features = { "Crown", "Halo", "Stars", "Wings" }, Colors = { C(0, 230, 170), C(230, 255, 250), C(170, 90, 255) }, Kg = { 200, 400 }, EventOnly = true },
}

return Pets

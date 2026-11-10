-- GameConfig: the single source of truth for tunable data, shared by server and client.
-- Child modules hold the data tables; this module adds global settings, lookups and pure
-- formulas (income, value, walk speed) so the UI always shows exactly what the server computes.

local Rarities = require(script.Rarities)
local BiomeData = require(script.Biomes)
local PetList = require(script.Pets)
local Economy = require(script.Economy)
local Progression = require(script.Progression)

export type PetData = {
	Uid: string,
	Species: string,
	Size: string,
	Mutation: string?,
	Tier: number,
	Kg: number,
	Name: string?,
	Slot: number?,
	Locked: boolean?,
	Obtained: number,
}

export type EggData = {
	Uid: string,
	Biome: string,
	Rarity: string,
	Size: string,
	Mutation: string?,
	Species: string?, -- pre-rolled for special eggs
	HatchAt: number?, -- os.time() when it hatches (set when placed on a pad)
	Duration: number?,
}

local GameConfig = {}

GameConfig.GameName = "Rift Raiders: Egg Multiverse"
GameConfig.DataVersion = 1

GameConfig.Settings = {
	MaxPlayers = 7,

	-- Data
	DataStoreName = "RiftRaiders_Profiles_v1",
	AutoSaveInterval = 120,
	SessionLockTimeout = 1800, -- seconds before a stale session lock may be stolen

	-- Movement / Speed
	NormalWalkSpeed = 16,
	MaxWalkSpeed = 85,
	WalkSpeedScale = 5.5, -- walk = 16 + scale * log2(1 + effectiveSpeed / WalkSpeedDivisor)
	WalkSpeedDivisor = 30,
	TreadmillTick = 0.5,  -- server credits treadmill Speed this often

	-- Eggs
	NestGrabDistance = 12,
	DeliverDistance = 14,
	DroppedEggReturnTime = 25, -- a dropped egg nobody picks up flies back to its nest
	DroppedEggPickupDelay = 0.6, -- the player who dropped it must wait this long
	CarryMaxSeconds = 600,       -- safety net against eggs stuck on a player forever

	-- Combat (foam bat)
	TagRange = 9,
	TagAngle = 100, -- degrees of the swing cone in front of the attacker
	TagCooldown = 1.5,
	RagdollTime = 2.0,
	TagImmunity = 6,       -- a tagged player cannot be tagged again for this long
	NewPlayerShield = 300, -- seconds after joining when a player's carried egg can't be knocked loose
	StealLimit = 2,        -- max eggs one attacker can knock loose from the same victim...
	StealWindow = 600,     -- ...within this many seconds

	-- Bear traps
	TrapStunTime = 4,
	TrapImmunity = 8,
	TrapLifetime = 90,
	TrapMaxActive = 2,
	TrapPlaceCooldown = 5,
	TrapBaseExclusion = 30, -- traps can't be placed within this distance of any base footprint
	TrapSpacing = 12,       -- min distance between two traps

	-- Guardian AI
	GuardianReactTime = 0.35,
	GuardianLoseTime = 3,    -- seconds without line of sight before giving up
	GuardianStunAfterHit = 2.5,

	-- Base protection
	BaseIntruderPush = 18,   -- non-owners inside a base are moved this far out the front door

	-- Anti-cheat
	SpeedTolerance = 1.45,   -- allowed horizontal speed = walk * tolerance + flat slack
	SpeedSlack = 12,
	MaxStrikes = 6,          -- rubber-band strikes before the player is kicked

	-- Purchases
	ShopRange = 40,          -- must be inside own base or this close to the hub shop
}

GameConfig.Rarities = Rarities
GameConfig.Economy = Economy
GameConfig.Progression = Progression
GameConfig.Biomes = BiomeData.List
GameConfig.Layout = BiomeData.Layout
GameConfig.Pets = PetList

-- ===== Lookups =====
local biomeById: { [string]: any } = {}
for _, b in ipairs(BiomeData.List) do
	biomeById[b.Id] = b
end
local speciesById: { [string]: any } = {}
local speciesByBiomeRarity: { [string]: { [string]: { any } } } = {}
for _, s in ipairs(PetList) do
	speciesById[s.Id] = s
	if not s.EventOnly then
		local byR = speciesByBiomeRarity[s.Biome] or {}
		speciesByBiomeRarity[s.Biome] = byR
		byR[s.Rarity] = byR[s.Rarity] or {}
		table.insert(byR[s.Rarity], s)
	end
end

function GameConfig.GetBiome(id: string?)
	return id and biomeById[id] or nil
end

function GameConfig.GetBiomeByIndex(index: number)
	return BiomeData.List[index]
end

function GameConfig.GetSpecies(id: string?)
	return id and speciesById[id] or nil
end

-- Species candidates for an egg of `rarity` from `biomeId`, falling back to lower rarities.
function GameConfig.GetSpeciesPool(biomeId: string, rarity: string): { any }
	local byR = speciesByBiomeRarity[biomeId]
	if not byR then
		return {}
	end
	local idx = Rarities.ById[rarity] and Rarities.ById[rarity].Index or 1
	for i = idx, 1, -1 do
		local pool = byR[Rarities.Order[i]]
		if pool and #pool > 0 then
			return pool
		end
	end
	for i = idx + 1, #Rarities.Order do
		local pool = byR[Rarities.Order[i]]
		if pool and #pool > 0 then
			return pool
		end
	end
	return {}
end

-- ===== Formulas =====

-- Coins per second of one pet (without base/rebirth bonuses).
function GameConfig.PetIncome(pet: { Species: string, Size: string?, Mutation: string?, Tier: number? }): number
	local s = speciesById[pet.Species]
	if not s then
		return 0
	end
	local biome = biomeById[s.Biome]
	local rarity = Rarities.ById[s.Rarity]
	local size = Rarities.Sizes[pet.Size or "Normal"] or Rarities.Sizes.Normal
	local mut = pet.Mutation and Rarities.Mutations[pet.Mutation]
	local tierMult = Rarities.TierIncomeMult[math.clamp(pet.Tier or 1, 1, Rarities.MaxTier)]
	return biome.IncomeBase * rarity.IncomeMult * size.IncomeMult * (mut and mut.IncomeMult or 1) * tierMult
end

function GameConfig.PetSellValue(pet): number
	return math.floor(GameConfig.PetIncome(pet) * Economy.SellValueSeconds)
end

-- Total multiplier applied to all pet income for a profile.
function GameConfig.IncomeMultiplier(baseLevel: number, rebirths: number): number
	local lvl = Economy.BaseLevels[math.clamp(baseLevel, 1, #Economy.BaseLevels)]
	return (1 + lvl.IncomeBonus) * (1 + rebirths * Economy.Rebirth.IncomeBonusPerRebirth)
end

-- Effective Speed = (trained Speed + treadmill base bonus) * trail multiplier.
function GameConfig.EffectiveSpeed(speedStat: number, treadmillLevel: number, trailId: string?): number
	local tm = Economy.TreadmillLevels[math.clamp(treadmillLevel, 1, #Economy.TreadmillLevels)]
	local trail = Economy.Trails[trailId or "None"] or Economy.Trails.None
	return (speedStat + tm.BaseSpeed) * trail.SpeedMult
end

-- Humanoid.WalkSpeed for an effective Speed (fast early growth, then logarithmic).
function GameConfig.WalkSpeedFor(effectiveSpeed: number): number
	local S = GameConfig.Settings
	local w = S.NormalWalkSpeed + S.WalkSpeedScale * math.log(1 + math.max(effectiveSpeed, 0) / S.WalkSpeedDivisor, 2)
	return math.min(w, S.MaxWalkSpeed)
end

function GameConfig.HatchDuration(rarity: string, size: string, incubatorLevel: number): number
	local r = Rarities.ById[rarity] or Rarities.ById.Common
	local sz = Rarities.Sizes[size] or Rarities.Sizes.Normal
	local inc = Economy.IncubatorLevels[math.clamp(incubatorLevel, 1, #Economy.IncubatorLevels)]
	return math.ceil(r.HatchTime * sz.HatchMult * (1 - inc.HatchSpeed))
end

function GameConfig.RebirthCost(rebirths: number): number
	return math.floor(Economy.Rebirth.BaseCost * Economy.Rebirth.CostGrowth ^ rebirths)
end

function GameConfig.PetDisplayName(pet): string
	local s = speciesById[pet.Species]
	local parts = {}
	if pet.Size and pet.Size ~= "Normal" then
		table.insert(parts, pet.Size)
	end
	if pet.Mutation then
		table.insert(parts, pet.Mutation)
	end
	table.insert(parts, pet.Name or (s and s.Name) or pet.Species)
	local name = table.concat(parts, " ")
	if (pet.Tier or 1) > 1 then
		name ..= " " .. string.rep("★", pet.Tier - 1)
	end
	return name
end

function GameConfig.EggDisplayName(egg): string
	local b = biomeById[egg.Biome]
	local parts = {}
	if egg.Size and egg.Size ~= "Normal" then
		table.insert(parts, egg.Size)
	end
	if egg.Mutation then
		table.insert(parts, egg.Mutation)
	end
	table.insert(parts, egg.Rarity)
	table.insert(parts, b and b.EggName or "Egg")
	return table.concat(parts, " ")
end

function GameConfig.FormatNumber(n: number): string
	n = math.floor(n or 0)
	local abs = math.abs(n)
	local suffixes = { { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, s in ipairs(suffixes) do
		if abs >= s[1] then
			local text = string.format("%.2f", n / s[1]):gsub("%.?0+$", "")
			return text .. s[2]
		end
	end
	return tostring(n)
end

function GameConfig.FormatTime(sec: number): string
	sec = math.max(0, math.ceil(sec))
	if sec >= 3600 then
		return string.format("%d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

return GameConfig

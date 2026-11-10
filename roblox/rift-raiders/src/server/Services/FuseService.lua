-- FuseService: 3 identical pets (same species + same tier) -> 1 pet of the next tier.
-- Two-step protocol protects against accidental or spoofed fusions:
--   1. PreviewFuse(uids) returns the exact inputs, result, cost, warnings and a one-time token.
--   2. Fuse(uids, token) only succeeds with a fresh token issued for exactly those pets.
-- Locked pets can never be fused; expensive inputs require a second confirmation in the UI.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local R = GameConfig.Rarities
local F = GameConfig.Economy.Fuse

local FuseService = {}
local Services

local tokens: { [Player]: { Token: string, Key: string, Expires: number } } = {}

local function setKey(uids: { string }): string
	local copy = table.clone(uids)
	table.sort(copy)
	return table.concat(copy, "|")
end

local function sizeIndex(size: string?): number
	return table.find(R.SizeOrder, size or "Normal") or 1
end

local function mutationRank(id: string?): number
	return id and R.Mutations[id] and R.Mutations[id].IncomeMult or 0
end

-- Returns (ok, errorOrPreview)
local function validate(player: Player, uids: any)
	local profile = Services.DataService.Get(player)
	if not profile then
		return false, "Loading..."
	end
	if type(uids) ~= "table" or #uids ~= 3 then
		return false, "Pick exactly 3 characters."
	end
	local pets, seen = {}, {}
	for _, uid in ipairs(uids) do
		if type(uid) ~= "string" or seen[uid] then
			return false, "Pick 3 different characters."
		end
		seen[uid] = true
		local pet = profile.Pets[uid]
		if not pet then
			return false, "One of those characters is no longer yours."
		end
		if pet.Locked then
			return false, "Locked characters can't be fused. Unlock it first."
		end
		table.insert(pets, pet)
	end
	local a = pets[1]
	for i = 2, 3 do
		if pets[i].Species ~= a.Species or (pets[i].Tier or 1) ~= (a.Tier or 1) then
			return false, "All 3 must be the same character and the same tier."
		end
	end
	if (a.Tier or 1) >= R.MaxTier then
		return false, "This pet is already max tier."
	end
	return true, { Profile = profile, Pets = pets }
end

local function buildPreview(player: Player, uids)
	local ok, v = validate(player, uids)
	if not ok then
		return { Ok = false, Error = v, Warnings = {} }
	end
	local pets = v.Pets
	local tier = pets[1].Tier or 1
	local bestSize, bestMut = "Normal", nil
	local before = 0
	local warnings = {}
	for _, pet in ipairs(pets) do
		before += GameConfig.PetIncome(pet)
		if sizeIndex(pet.Size) > sizeIndex(bestSize) then
			bestSize = pet.Size
		end
		if mutationRank(pet.Mutation) > mutationRank(bestMut) then
			bestMut = pet.Mutation
		end
		if pet.Mutation then
			table.insert(warnings, ("%s has a %s mutation (only the best mutation is kept)."):format(GameConfig.PetDisplayName(pet), pet.Mutation))
		end
		if pet.Size ~= "Normal" then
			table.insert(warnings, ("%s is %s (only the biggest size is kept)."):format(GameConfig.PetDisplayName(pet), pet.Size))
		end
		if pet.Name then
			table.insert(warnings, ("You named this character \"%s\" — its name will be lost."):format(pet.Name))
		end
	end
	local result = { Species = pets[1].Species, Tier = tier + 1, Size = bestSize, Mutation = bestMut }
	local after = GameConfig.PetIncome(result)
	local species = GameConfig.GetSpecies(pets[1].Species)
	local valuable = before >= F.ConfirmValueThreshold or R.ById[species.Rarity].Index >= R.ById.Legendary.Index
	table.insert(warnings, "Fusion is permanent and cannot be undone.")
	local token = Util.Uid("f")
	tokens[player] = { Token = token, Key = setKey(uids), Expires = os.clock() + 60 }
	return {
		Ok = true,
		Inputs = Util.DeepCopy(pets),
		Result = { Species = result.Species, Tier = result.Tier, Size = bestSize, Mutation = bestMut,
			IncomeBefore = before, IncomeAfter = after, Cost = F.Cost[tier] or 0 },
		Chances = { Mutation = F.MutationUpgradeChance, Size = F.SizeUpgradeChance, BonusEgg = F.BonusEggChance },
		Warnings = warnings,
		NeedsDoubleConfirm = valuable or v.Profile.Settings.ConfirmFuse == true and #warnings > 1,
		Token = token,
	}
end

local function fuse(player: Player, uids, token)
	local t = tokens[player]
	if type(token) ~= "string" or not t or t.Token ~= token or os.clock() > t.Expires or type(uids) ~= "table" or t.Key ~= setKey(uids) then
		Services.DataService.Notify(player, "Fusion expired — please review it again.", "warn")
		return
	end
	tokens[player] = nil
	local ok, v = validate(player, uids)
	if not ok then
		Services.DataService.Notify(player, v, "bad")
		return
	end
	if Services.EggService.IsCarrying(player) then
		Services.DataService.Notify(player, "Deliver your egg before fusing.", "warn")
		return
	end
	local profile, pets = v.Profile, v.Pets
	local tier = pets[1].Tier or 1
	local cost = F.Cost[tier] or 0
	if not Services.DataService.Spend(player, "Coins", cost) then
		Services.DataService.Notify(player, ("Fusing costs %s coins."):format(GameConfig.FormatNumber(cost)), "bad")
		return
	end

	local bestSize, bestMut, slot, kg = "Normal", nil, nil, 0
	for _, pet in ipairs(pets) do
		if sizeIndex(pet.Size) > sizeIndex(bestSize) then
			bestSize = pet.Size
		end
		if mutationRank(pet.Mutation) > mutationRank(bestMut) then
			bestMut = pet.Mutation
		end
		slot = slot or pet.Slot
		kg += pet.Kg or 0
		profile.Pets[pet.Uid] = nil -- inputs are consumed before the result exists: no duplication window
	end

	local sizeUp, mutUp = false, false
	if math.random() < F.SizeUpgradeChance and sizeIndex(bestSize) < #R.SizeOrder then
		bestSize = R.SizeOrder[sizeIndex(bestSize) + 1]
		sizeUp = true
	end
	if math.random() < F.MutationUpgradeChance then
		local nextMut
		for _, id in ipairs(R.MutationOrder) do
			if not R.Mutations[id].EventOnly and mutationRank(id) > mutationRank(bestMut) then
				nextMut = id
				break
			end
		end
		if nextMut then
			bestMut = nextMut
			mutUp = true
		end
	end

	local result = {
		Uid = Util.Uid("p"),
		Species = pets[1].Species,
		Size = bestSize,
		Mutation = bestMut,
		Tier = tier + 1,
		Kg = math.floor(kg * 0.8 * 10) / 10,
		Obtained = os.time(),
		Slot = slot,
	}
	profile.Pets[result.Uid] = result
	if not result.Slot then
		Services.PetService.RefreshBase(player)
	end

	local bonusEgg
	if math.random() < F.BonusEggChance then
		local species = GameConfig.GetSpecies(result.Species)
		local idx = math.min(R.ById[species.Rarity].Index + 1, #R.Order)
		bonusEgg = { Uid = Util.Uid("e"), Biome = species.Biome, Rarity = R.Order[idx], Size = "Normal" }
		if not Services.EggService.GiveEgg(player, bonusEgg) then
			bonusEgg = nil
		end
	end

	profile.Stats.Fuses += 1
	Services.QuestService.Track(player, "Fuses", 1)
	Services.DataService.Changed(player, "Pets", "Stats")
	Services.PetService.RefreshBase(player)
	Services.DataService.Effect(player, "Fuse", { Pet = Util.DeepCopy(result), MutationUp = mutUp, SizeUp = sizeUp, BonusEgg = bonusEgg })
end

function FuseService.Init(services)
	Services = services
end

function FuseService.Start()
	local previewLimiter = RateLimiter.new(6, 2)
	Net.Function("PreviewFuse").OnServerInvoke = function(player, uids)
		if not previewLimiter:Allow(player) then
			return { Ok = false, Error = "Slow down a little.", Warnings = {} }
		end
		return buildPreview(player, uids)
	end
	local fuseLimiter = RateLimiter.new(2, 0.5)
	Net.Event("Fuse").OnServerEvent:Connect(function(player, uids, token)
		if fuseLimiter:Allow(player) then
			fuse(player, uids, token)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		tokens[p] = nil
	end)
end

return FuseService

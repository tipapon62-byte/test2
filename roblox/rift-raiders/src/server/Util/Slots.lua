local Slots = {}

function Slots.IsValid(slot: any, limit: number): boolean
	return type(slot) == "number" and slot >= 1 and slot <= limit and slot % 1 == 0
end

local function occupied(profile)
	local used = {}
	for _, pet in pairs(profile.Pets) do
		if pet.Slot then
			used[pet.Slot] = true
		end
	end
	for key in pairs(profile.Incubators or {}) do
		local slot = tonumber(key)
		if slot then
			used[slot] = true
		end
	end
	return used
end

function Slots.IsFree(profile, slot: any, limit: number): boolean
	return Slots.IsValid(slot, limit) and not occupied(profile)[slot]
end

function Slots.Free(profile, limit: number): number?
	local used = occupied(profile)
	for slot = 1, limit do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

function Slots.Revalidate(profile, limit: number, capacity: number): boolean
	local used = {}
	for _, pet in pairs(profile.Pets) do
		if pet.Slot then
			used[pet.Slot] = true
		end
	end
	local entries = {}
	for key, egg in pairs(profile.Incubators) do
		table.insert(entries, { Key = key, Slot = tonumber(key), Egg = egg })
	end
	table.sort(entries, function(a, b)
		local x, y = a.Slot or math.huge, b.Slot or math.huge
		return if x == y then tostring(a.Key) < tostring(b.Key) else x < y
	end)
	local incubators, count, changed = {}, 0, false
	for _, entry in ipairs(entries) do
		local slot, egg = entry.Slot, entry.Egg
		if Slots.IsValid(slot, limit) and not used[slot] and count < capacity then
			local key = tostring(slot)
			incubators[key] = egg
			used[slot] = true
			count += 1
			changed = changed or key ~= entry.Key
		else
			egg.HatchAt = nil
			-- Preserve owned eggs even when a downgrade temporarily exceeds the queue cap.
			table.insert(profile.EggStorage, egg)
			changed = true
		end
	end
	profile.Incubators = incubators
	return changed
end

return Slots

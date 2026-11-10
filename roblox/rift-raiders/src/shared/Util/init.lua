-- Small shared helpers: unique ids, weighted rolls, deep copy, table counting.
local HttpService = game:GetService("HttpService")

local Util = {}

function Util.IsFinite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Util.Uid(prefix: string?): string
	return (prefix or "") .. HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 16)
end

-- weights: {[key] = weight}. order (optional) makes the roll deterministic in iteration order.
function Util.WeightedPick(weights: { [string]: number }, order: { string }?, rng: Random?): string?
	local keys = order or {}
	if not order then
		for k in pairs(weights) do
			table.insert(keys, k)
		end
		table.sort(keys)
	end
	local total = 0
	for _, k in ipairs(keys) do
		total += math.max(weights[k] or 0, 0)
	end
	if total <= 0 then
		return nil
	end
	local r = (rng and rng:NextNumber() or math.random()) * total
	for _, k in ipairs(keys) do
		r -= math.max(weights[k] or 0, 0)
		if r <= 0 then
			return k
		end
	end
	return keys[#keys]
end

function Util.DeepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t :: any) do
		out[k] = Util.DeepCopy(v)
	end
	return out :: any
end

-- Fills missing keys of `t` from `template` (recursively), used for save migrations.
function Util.Reconcile(t: { [any]: any }, template: { [any]: any })
	for k, v in pairs(template) do
		if t[k] == nil then
			t[k] = Util.DeepCopy(v)
		elseif type(v) == "table" and type(t[k]) == "table" and next(v) ~= nil then
			Util.Reconcile(t[k], v)
		end
	end
end

function Util.Count(t: { [any]: any }?): number
	local n = 0
	if t then
		for _ in pairs(t) do
			n += 1
		end
	end
	return n
end

function Util.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

return Util

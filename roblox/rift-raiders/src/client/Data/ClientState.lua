-- ClientState: small read-only helpers about the local player's live situation (character, base,
-- carried egg, chasing guardians) shared by the HUD, tutorial, sound and juice controllers.
-- Everything is nil-safe: the character, base and profile keys can all be missing for a moment.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local ClientData = require(script.Parent:WaitForChild("ClientData"))

local player = Players.LocalPlayer

local ClientState = {}

function ClientState.Root(): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function ClientState.Humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

function ClientState.Alive(): boolean
	local hum = ClientState.Humanoid()
	return hum ~= nil and hum.Health > 0 and ClientState.Root() ~= nil
end

function ClientState.Carrying(): boolean
	local egg = player:GetAttribute("CarryingEgg")
	return type(egg) == "string" and egg ~= ""
end

function ClientState.CarryRarity(): string
	local r = player:GetAttribute("CarryingRarity")
	return if type(r) == "string" then r else ""
end

function ClientState.Stat(name: string): number
	local stats = ClientData.Get().Stats
	local v = type(stats) == "table" and stats[name] or 0
	return tonumber(v) or 0
end

function ClientState.Setting(name: string): any
	local s = ClientData.Get().Settings
	return type(s) == "table" and s[name] or nil
end

function ClientState.Count(t: any): number
	local n = 0
	if type(t) == "table" then
		for _ in pairs(t) do
			n += 1
		end
	end
	return n
end

-- The player's base model (workspace.Bases.BaseN) or nil.
function ClientState.Base(): Model?
	local name = player:GetAttribute("BaseName")
	local bases = workspace:FindFirstChild("Bases")
	local base = type(name) == "string" and name ~= "" and bases and bases:FindFirstChild(name)
	if base and base:IsA("Model") then
		return base
	end
	return nil
end

local function posOf(inst: Instance?): Vector3?
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		local ok, cf = pcall(inst.GetPivot, inst)
		return if ok then cf.Position else nil
	elseif inst:IsA("Attachment") then
		return inst.WorldPosition
	end
	return nil
end
ClientState.PositionOf = posOf

-- Where an egg is delivered: the base entrance mat, else its floor, else its pivot.
function ClientState.HomePosition(): Vector3?
	local base = ClientState.Base()
	if not base then
		return nil
	end
	return posOf(base:FindFirstChild("EntranceMat")) or posOf(base:FindFirstChild("Floor")) or posOf(base)
end

-- Enclosure slots used (placed characters + hatching eggs) vs capacity.
function ClientState.EnclosureUse(): (number, number)
	local p = ClientData.Get()
	local used = 0
	for _, pet in pairs(p.Pets or {}) do
		if type(pet) == "table" and pet.Slot then
			used += 1
		end
	end
	used += ClientState.Count(p.Incubators)
	local slots = (p.Derived and p.Derived.Slots) or 6
	return used, slots
end

-- Nearest guardian chasing within `radius` studs (cached ~5 Hz).
local chaseCache = { At = -1, Guardian = nil :: Model?, Dist = math.huge }
function ClientState.ChasingGuardian(radius: number?): (Model?, number)
	local now = os.clock()
	if now - chaseCache.At < 0.2 then
		local r = radius or 60
		if chaseCache.Dist <= r then
			return chaseCache.Guardian, chaseCache.Dist
		end
		return nil, chaseCache.Dist
	end
	chaseCache.At = now
	chaseCache.Guardian, chaseCache.Dist = nil, math.huge
	local root = ClientState.Root()
	if root then
		for _, g in ipairs(CollectionService:GetTagged("RR_Guardian")) do
			if g:IsA("Model") and g:GetAttribute("State") == "Chase" then
				local p = posOf(g)
				local d = p and (p - root.Position).Magnitude or math.huge
				if d < chaseCache.Dist then
					chaseCache.Guardian, chaseCache.Dist = g, d
				end
			end
		end
	end
	local r = radius or 60
	if chaseCache.Dist <= r then
		return chaseCache.Guardian, chaseCache.Dist
	end
	return nil, chaseCache.Dist
end

-- Chased = carrying an egg with a chasing guardian within 60 studs.
function ClientState.IsChased(): boolean
	if not ClientState.Carrying() then
		return false
	end
	local g = ClientState.ChasingGuardian(60)
	return g ~= nil
end

-- Lazily requires a sibling controller (nil if missing or failing) so controllers can talk
-- without load-order or circular-require problems.
local controllerCache: { [string]: any } = {}
function ClientState.Controller(name: string): any
	local cached = controllerCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local folder = script.Parent.Parent:FindFirstChild("Controllers")
	local m = folder and folder:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			controllerCache[name] = res
			return res
		end
	end
	return nil
end

-- Calls Controller(name)[fn](...) if it exists; never errors.
function ClientState.Call(name: string, fn: string, ...): any
	local c = ClientState.Controller(name)
	local f = c and c[fn]
	if type(f) == "function" then
		local ok, res = pcall(f, ...)
		if ok then
			return res
		end
		warn(("[ClientState] %s.%s failed: %s"):format(name, fn, tostring(res)))
	end
	return nil
end

return ClientState

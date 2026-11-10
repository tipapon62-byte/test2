-- SaveService: DataStore persistence with session locking, retries and safe release.
--
-- Record stored under "P_<UserId>":
--   { Data = <profile>, Meta = { Lock = {JobId, Time}?, SaveCount = n, LastSaved = unix } }
--
-- * A server only writes a record whose lock it owns, so two servers can never both save the
--   same profile (prevents item duplication by quickly rejoining another server).
-- * Stale locks (crashed servers) expire after Settings.SessionLockTimeout.
-- * In Studio without API access the service falls back to unsaved in-memory profiles.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local S = GameConfig.Settings

local SaveService = {}

local store: DataStore? = nil
local available = false
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(S.DataStoreName)
	end)
	if ok then
		store = result
		available = true
	else
		warn("[SaveService] DataStores unavailable, progress will NOT be saved:", result)
	end
end

local function key(userId: number): string
	return "P_" .. userId
end

local function retry<T>(label: string, attempts: number, fn: () -> T): (boolean, T?)
	local lastErr
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(("[SaveService] %s failed (attempt %d/%d): %s"):format(label, i, attempts, tostring(result)))
		task.wait(math.min(2 ^ i, 16))
	end
	warn("[SaveService] giving up on", label, lastErr)
	return false, nil
end

function SaveService.IsAvailable(): boolean
	return available
end

-- Loads and locks a profile. Returns (status, data):
--   "ok", data|nil (nil = new player) | "locked" | "error"
function SaveService.Load(userId: number): (string, any)
	if not available or not store then
		return "ok", nil
	end
	local st = store :: DataStore
	for attempt = 1, 5 do
		local lockedByOther = false
		local ok, record = retry("load " .. userId, 3, function()
			return st:UpdateAsync(key(userId), function(old)
				old = old or { Meta = {} }
				old.Meta = old.Meta or {}
				local lock = old.Meta.Lock
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < S.SessionLockTimeout then
					lockedByOther = true
					return nil -- abort the write, keep the other server's lock
				end
				old.Meta.Lock = { JobId = game.JobId, Time = os.time() }
				return old
			end)
		end)
		if not ok then
			return "error", nil
		end
		if not lockedByOther then
			return "ok", record and record.Data or nil
		end
		-- the previous server is probably still saving this player; give it a moment
		task.wait(4 + attempt * 2)
	end
	return "locked", nil
end

-- Saves a profile. release = true also clears the session lock (on leave / shutdown).
function SaveService.Save(userId: number, data: any, release: boolean): boolean
	if not available or not store then
		return true
	end
	local st = store :: DataStore
	local lostLock = false
	local ok = retry("save " .. userId, 4, function()
		st:UpdateAsync(key(userId), function(old)
			old = old or { Meta = {} }
			old.Meta = old.Meta or {}
			local lock = old.Meta.Lock
			if lock and lock.JobId ~= game.JobId then
				lostLock = true
				return nil
			end
			old.Data = data
			old.Meta.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
			old.Meta.SaveCount = (old.Meta.SaveCount or 0) + 1
			old.Meta.LastSaved = os.time()
			return old
		end)
	end)
	if lostLock then
		warn("[SaveService] session lock for", userId, "is owned by another server; save skipped")
		return false
	end
	return ok
end

if RunService:IsStudio() and available then
	-- Studio test sessions share JobId "" — make locks from earlier play tests expire quickly.
	S.SessionLockTimeout = math.min(S.SessionLockTimeout, 30)
end

return SaveService

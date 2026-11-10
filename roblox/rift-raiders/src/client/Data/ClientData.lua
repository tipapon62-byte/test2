-- ClientData: local read-only mirror of the player's profile.
-- Snapshot from GetProfile, then ProfileUpdated partials (top-level keys replace).
-- The client never decides anything with this data; it only renders it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

-- Minimal signal that passes tables by reference (BindableEvents deep-copy them).
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self._handlers
	local entry = { Fn = fn }
	table.insert(handlers, entry)
	return {
		Disconnect = function()
			local i = table.find(handlers, entry)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, entry in ipairs(table.clone(self._handlers)) do
		task.spawn(entry.Fn, ...)
	end
end

local ClientData = {}
ClientData.Signal = Signal
ClientData.Changed = Signal.new() -- (keys: {[string]: true})

local profile: { [string]: any } = {}
local ready = false
local readyEvent = Instance.new("BindableEvent")
local started = false

function ClientData.Get(): { [string]: any }
	return profile
end

function ClientData.IsReady(): boolean
	return ready
end

function ClientData.WaitReady()
	if not ready then
		readyEvent.Event:Wait()
	end
end

-- Optimistic local value (e.g. settings toggled in the UI). The next server update overwrites it.
function ClientData.SetLocal(key: string, value: any)
	profile[key] = value
	ClientData.Changed:Fire({ [key] = true })
end

-- Calls fn(profile, keys) now (if ready) and whenever any of `keys` change.
function ClientData.Observe(keys: { string }, fn: (any, any) -> ())
	local function matches(changed)
		for _, k in ipairs(keys) do
			if changed[k] then
				return true
			end
		end
		return false
	end
	local conn = ClientData.Changed:Connect(function(changed)
		if matches(changed) then
			fn(profile, changed)
		end
	end)
	if ready then
		task.spawn(fn, profile, {})
	end
	return conn
end

function ClientData.Init()
	if started then
		return
	end
	started = true

	Net.Event("ProfileUpdated").OnClientEvent:Connect(function(partial)
		if not ready or type(partial) ~= "table" then
			return -- the snapshot we are about to receive is complete
		end
		local keys = {}
		for k, v in pairs(partial) do
			profile[k] = v
			keys[k] = true
		end
		ClientData.Changed:Fire(keys)
	end)

	task.spawn(function()
		local getProfile = Net.Function("GetProfile")
		local attempt = 0
		while true do
			attempt += 1
			local ok, result = pcall(getProfile.InvokeServer, getProfile)
			if ok and type(result) == "table" then
				profile = result
				break
			end
			if attempt % 5 == 0 then
				warn("[ClientData] waiting for profile...", if ok then "not loaded yet" else result)
			end
			task.wait(math.min(1 + attempt * 0.25, 4))
		end
		ready = true
		readyEvent:Fire()
		local keys = {}
		for k in pairs(profile) do
			keys[k] = true
		end
		ClientData.Changed:Fire(keys)
	end)
end

return ClientData

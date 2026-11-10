-- Server bootstrap. Every service is a ModuleScript in ./Services exposing optional
-- Init(services) (wire references, no yielding) and Start() (connect events, start loops).
-- Start order matters: the world is built before eggs/guardians, and DataService starts last
-- so every OnLoaded hook is registered before the first profile loads.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

Players.CharacterAutoLoads = true
Net.Init()

-- remove scripts/remotes of the previous version of the place if they are still around
for _, name in ipairs({ "GameServer", "Conveyor", "StealSystem", "SpeedSystem", "EggRun", "WorldSigns" }) do
	local old = script.Parent.Parent:FindFirstChild(name)
	if old and old:IsA("Script") then
		old.Disabled = true
	end
end

local START_ORDER = {
	"BaseService", "SpeedService", "EventService", "BiomeService", "EggService", "GuardianService",
	"PetService", "FuseService", "CombatService", "QuestService", "EconomyService",
	"LeaderboardService", "AntiCheatService", "DataService",
}

local services = {}
for _, module in ipairs(script.Parent:WaitForChild("Services"):GetChildren()) do
	if module:IsA("ModuleScript") then
		services[module.Name] = require(module)
	end
end
services.SaveService = services.SaveService or require(script.Parent.Services.SaveService)

for _, service in pairs(services) do
	if type(service.Init) == "function" then
		service.Init(services)
	end
end

local started = {}
local function start(name: string)
	local service = services[name]
	if service and not started[name] and type(service.Start) == "function" then
		started[name] = true
		local ok, err = pcall(service.Start)
		if not ok then
			warn(("[Main] %s failed to start: %s"):format(name, tostring(err)))
		end
	end
end
for _, name in ipairs(START_ORDER) do
	start(name)
end
for name in pairs(services) do
	start(name)
end
print("[Rift Raiders] server ready")

-- Net: the full list of remotes. The server creates them (Net.Init) in ReplicatedStorage.Remotes;
-- clients fetch them with Net.Event / Net.Function (waits until they exist).
--
-- Client -> Server (RemoteEvent, every handler validates and rate-limits on the server):
--   Purchase(category: string, id: string|number)
--       category = "BaseUpgrade" | "TreadmillUpgrade" | "IncubatorUpgrade" | "Trail" | "Item" | "BiomeKey" | "ShardEgg"
--   EquipTrail(trailId: string)
--   Tag()                                   -- swing the foam bat; the server finds the target
--   DropEgg()                               -- drop the carried egg
--   UseItem(itemId: string)                 -- "BearTrap" places a trap at your feet; "DecoyEgg" toggles holding it
--   PetAction(action: string, uids: {string}, arg: any?)
--       action = "Place" | "Store" | "Sell" | "SellDuplicates" | "Lock" | "Unlock" | "Rename" | "MutationPotion"
--   Fuse(uids: {string}, token: string)     -- token comes from PreviewFuse; proves the player saw the preview
--   SpeedUpHatch(pad: number, currency: "Coins" | "Shards")
--   ClaimDaily()
--   ClaimQuest(kind: "Daily" | "Weekly", questId: string)
--   RedeemCode(code: string)
--   Rebirth()
--   SaveSettings(settings: {[string]: any})
--   TreadmillActive(running: boolean)       -- client hint for the active-training bonus
--
-- Server -> Client (RemoteEvent):
--   ProfileUpdated(partial: {[string]: any})  -- top-level profile keys that changed
--   Notify(text: string, kind: "info" | "good" | "bad" | "warn")
--   Announce(text: string, color: Color3)     -- server-wide (rare hatches, events)
--   Effect(name: string, data: {[string]: any}) -- "Hatch" | "Fuse" | "Tagged" | "Trapped" | "Unlock" | "Coins" | "Event"
--   Ragdoll(on: boolean, duration: number)
--   Knockback(velocity: Vector3)
--
-- RemoteFunctions (data requests only):
--   GetProfile() -> profile snapshot
--   GetLeaderboard(statId: string) -> { {Name: string, UserId: number, Value: number} }
--   PreviewFuse(uids: {string}) -> { Ok: boolean, Error: string?, Result: {...}?, Warnings: {string}, Token: string? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	"Purchase", "EquipTrail", "Tag", "DropEgg", "UseItem", "PetAction", "Fuse", "SpeedUpHatch",
	"ClaimDaily", "ClaimQuest", "RedeemCode", "Rebirth", "SaveSettings", "TreadmillActive",
	"ProfileUpdated", "Notify", "Announce", "Effect", "Ragdoll", "Knockback",
}
Net.Functions = { "GetProfile", "GetLeaderboard", "PreviewFuse" }

local FOLDER_NAME = "Remotes"

function Net.Init()
	assert(RunService:IsServer(), "Net.Init is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy() -- remove remotes left over from older versions of the place
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in ipairs(Net.Events) do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in ipairs(Net.Functions) do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function getFolder(): Instance
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		assert(f, "Net.Init must run before remotes are used")
		return f
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Net.Event(name: string): RemoteEvent
	local folder = getFolder()
	local r = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name)
	assert(r and r:IsA("RemoteEvent"), "Unknown RemoteEvent " .. name)
	return r
end

function Net.Function(name: string): RemoteFunction
	local folder = getFolder()
	local r = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name)
	assert(r and r:IsA("RemoteFunction"), "Unknown RemoteFunction " .. name)
	return r
end

return Net

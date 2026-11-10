-- SoundController: every game sound, built only from sounds that ship with the Roblox client
-- (rbxasset://sounds/...), so nothing has to be uploaded. Cues are short "recipes" of one or more
-- notes (source + pitch + volume + delay); pitch is varied so repeats don't sound robotic.
-- All sounds play through SoundService SoundGroups "SFX" / "Music" (volumes from Settings).
--
-- API: SoundController.Play(cue: string, volumeScale: number?)   -- never errors
--      SoundController.Group(name: "SFX" | "Music"): SoundGroup

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Client = script.Parent.Parent
local ClientData = require(Client:WaitForChild("Data"):WaitForChild("ClientData"))
local ClientState = require(Client:WaitForChild("Data"):WaitForChild("ClientState"))
local Components = require(Client:WaitForChild("UI"):WaitForChild("Components"))

local player = Players.LocalPlayer

local SoundController = {}

local SRC = {
	Button = "rbxasset://sounds/button.wav",
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Swoosh = "rbxasset://sounds/swoosh.wav",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Fall = "rbxasset://sounds/action_falling.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Oof = "rbxasset://sounds/uuhhh.mp3",
	ClickFast = "rbxasset://sounds/clickfast.wav",
	Snap = "rbxasset://sounds/snap.wav",
	Bass = "rbxasset://sounds/bass.wav",
}

-- note = { source, pitch, volume, delay?, pitchJitter? }
local CUES: { [string]: { any } } = {
	Click = { { "Button", 1.15, 0.45, 0, 0.06 } },
	Disabled = { { "Button", 0.6, 0.35 } },
	Open = { { "Swoosh", 1.35, 0.3, 0, 0.05 } },
	Close = { { "Swoosh", 1.7, 0.22, 0, 0.05 } },
	Good = { { "Ping", 1.3, 0.4 }, { "Ping", 1.7, 0.3, 0.07 } },
	Error = { { "Button", 0.62, 0.5 }, { "Button", 0.5, 0.5, 0.09 } },
	Purchase = { { "Ping", 1.0, 0.55 }, { "Ping", 1.5, 0.55, 0.08 }, { "ClickFast", 1.9, 0.4, 0.02 }, { "Ping", 2.0, 0.45, 0.17 } },
	Coin = { { "Ping", 2.0, 0.3, 0, 0.1 } },
	Grab = { { "GetUp", 1.3, 0.65 }, { "Ping", 1.6, 0.35, 0.05 } },
	Drop = { { "Fall", 1.25, 0.55 } },
	Deliver = { { "Ping", 1.0, 0.5 }, { "Ping", 1.26, 0.5, 0.08 }, { "Ping", 1.5, 0.5, 0.16 }, { "Splash", 1.5, 0.3, 0.16 } },
	Swing = { { "Swoosh", 0.95, 0.55, 0, 0.12 } },
	Bonk = { { "Bass", 1.5, 0.9 }, { "Oof", 1.1, 0.55, 0.05, 0.1 } },
	Trap = { { "Snap", 0.75, 1.0 }, { "Bass", 0.8, 0.6 } },
	Wobble = { { "ClickFast", 0.8, 0.35, 0, 0.15 } },
	Crack = { { "Snap", 1.35, 0.9 }, { "Splash", 1.8, 0.35, 0.03 } },
	Hatch = { { "Ping", 1.0, 0.5 }, { "Ping", 1.26, 0.5, 0.1 }, { "Ping", 1.5, 0.5, 0.2 }, { "Ping", 2.0, 0.6, 0.32 }, { "Bass", 1.2, 0.4, 0.32 } },
	HatchBig = {
		{ "Ping", 1.0, 0.55 }, { "Ping", 1.26, 0.55, 0.09 }, { "Ping", 1.5, 0.55, 0.18 }, { "Ping", 2.0, 0.6, 0.27 },
		{ "Ping", 1.5, 0.5, 0.42 }, { "Ping", 2.0, 0.65, 0.51 }, { "Bass", 1.0, 0.6, 0.51 }, { "Jump", 1.4, 0.4, 0.51 },
	},
	LevelUp = { { "Ping", 1.0, 0.5 }, { "Ping", 1.33, 0.5, 0.09 }, { "Ping", 1.5, 0.5, 0.18 }, { "Ping", 2.0, 0.6, 0.27 }, { "Jump", 1.2, 0.4, 0.27 } },
	Discovery = { { "Ping", 1.8, 0.4 }, { "Ping", 2.4, 0.4, 0.08 } },
	Alarm = { { "Ping", 0.75, 0.5 }, { "Ping", 0.56, 0.5, 0.17 } },
	Rare = { { "Ping", 1.5, 0.55 }, { "Ping", 1.0, 0.5, 0.1 }, { "Ping", 1.5, 0.55, 0.2 }, { "Ping", 2.0, 0.6, 0.3 }, { "Bass", 0.9, 0.6 } },
	Step = { { "Ping", 1.5, 0.45 }, { "Ping", 2.0, 0.45, 0.09 } },
	Whoosh = { { "Swoosh", 0.7, 0.4, 0, 0.1 } },
}

-- Cues that ignore repeats closer than this (seconds), so server + attribute signals don't double up.
local MIN_GAP: { [string]: number } = { Bonk = 0.6, Trap = 0.8, Coin = 0.06, Click = 0.05, Alarm = 0.5, Grab = 0.4, Drop = 0.4, Deliver = 0.6 }
local MAX_LIVE = 24

local folder: Folder? = nil
local templates: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local live = 0
local lastPurchaseAt = -100

-- ShopController calls this when it sends a Purchase, so the server's "good" reply goes cha-ching.
function SoundController.MarkPurchase()
	lastPurchaseAt = os.clock()
end

function SoundController.Group(name: string): SoundGroup
	local g = SoundService:FindFirstChild(name)
	if g and g:IsA("SoundGroup") then
		return g
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Volume = if name == "Music" then 0.5 else 0.8
	created.Parent = SoundService
	return created
end

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "RR_SFX"
	f.Parent = SoundService
	folder = f
	return f
end

local function template(key: string): Sound?
	local t = templates[key]
	if t and t.Parent then
		return t
	end
	local id = SRC[key]
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = id
	s.SoundGroup = SoundController.Group("SFX")
	s.Parent = getFolder()
	templates[key] = s
	return s
end

local function playNote(note: { any }, volumeScale: number)
	local base = template(note[1])
	if not base or live >= MAX_LIVE then
		return
	end
	local s = base:Clone()
	local jitter = note[5] or 0.04
	s.PlaybackSpeed = math.max(0.1, (note[2] or 1) * (1 + (math.random() * 2 - 1) * jitter))
	s.Volume = math.clamp((note[3] or 0.5) * volumeScale, 0, 3)
	s.Parent = getFolder()
	live += 1
	local cleaned = false
	local function cleanup()
		if not cleaned then
			cleaned = true
			live -= 1
			s:Destroy()
		end
	end
	s.Ended:Connect(cleanup)
	task.delay(4, cleanup) -- a sound that never loads/ends still gets removed
	s:Play()
end

function SoundController.Play(cue: string, volumeScale: number?)
	local ok, err = pcall(function()
		local notes = CUES[cue]
		if not notes then
			return
		end
		local now = os.clock()
		local gap = MIN_GAP[cue]
		if gap and now - (lastPlayed[cue] or -1) < gap then
			return
		end
		lastPlayed[cue] = now
		local vol = volumeScale or 1
		for _, note in ipairs(notes) do
			local delay = note[4] or 0
			if delay > 0 then
				task.delay(delay, function()
					pcall(playNote, note, vol)
				end)
			else
				playNote(note, vol)
			end
		end
	end)
	if not ok then
		warn("[Sound]", cue, err)
	end
end

function SoundController.Start()
	SoundController.Group("SFX")
	SoundController.Group("Music")
	for key in pairs(SRC) do
		template(key) -- preload
	end
	Components.Sound = SoundController.Play

	-- Server feedback
	Net.Event("Notify").OnClientEvent:Connect(function(_, kind)
		if kind == "good" then
			SoundController.Play(if os.clock() - lastPurchaseAt < 3 then "Purchase" else "Good")
		elseif kind == "bad" then
			SoundController.Play("Error")
		end
	end)
	Net.Event("Effect").OnClientEvent:Connect(function(name, data)
		if name == "Coins" then
			SoundController.Play("Coin")
		elseif name == "Tagged" then
			SoundController.Play("Bonk")
		elseif name == "Trapped" then
			SoundController.Play("Trap")
		elseif name == "Unlock" or name == "Rebirth" then
			SoundController.Play("LevelUp")
		elseif name == "Discovery" then
			SoundController.Play("Discovery")
		elseif name == "Event" and type(data) == "table" and data.Id then
			SoundController.Play("Good")
		end
	end)

	-- Egg grab / drop / deliver
	local lastDelivered = ClientState.Stat("EggsDelivered")
	local carryEndedAt = -100
	local deliveredSince = false
	local wasCarrying = ClientState.Carrying()
	player:GetAttributeChangedSignal("CarryingEgg"):Connect(function()
		local now = ClientState.Carrying()
		if now and not wasCarrying then
			SoundController.Play("Grab")
		elseif wasCarrying and not now then
			carryEndedAt = os.clock()
			deliveredSince = false
			local myEnd = carryEndedAt
			task.delay(0.9, function()
				if carryEndedAt == myEnd and not deliveredSince then
					SoundController.Play("Drop")
				end
			end)
		end
		wasCarrying = now
	end)
	ClientData.Observe({ "Stats" }, function()
		local d = ClientState.Stat("EggsDelivered")
		if d > lastDelivered then
			deliveredSince = true
			if os.clock() - carryEndedAt < 2 or not ClientState.Carrying() then
				SoundController.Play("Deliver")
			end
		end
		lastDelivered = d
	end)

	-- Knockdowns from guardians (tags already play Bonk; MIN_GAP stops doubles)
	player:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if player:GetAttribute("Ragdolled") == true then
			SoundController.Play("Bonk")
		end
	end)
	player:GetAttributeChangedSignal("Trapped"):Connect(function()
		if player:GetAttribute("Trapped") == true then
			SoundController.Play("Trap")
		end
	end)

	-- Upgrades
	local levels = {}
	for _, k in ipairs({ "BaseLevel", "TreadmillLevel", "IncubatorLevel" }) do
		levels[k] = ClientData.Get()[k] or 1
	end
	ClientData.Observe({ "BaseLevel", "TreadmillLevel", "IncubatorLevel" }, function(p)
		local up = false
		for k, old in pairs(levels) do
			local v = tonumber(p[k]) or old
			if v > old then
				up = true
			end
			levels[k] = v
		end
		if up then
			SoundController.Play("LevelUp")
		end
	end)

	-- Trap snapping shut near you (someone else's victim)
	CollectionService:GetInstanceAddedSignal("RR_Trap"):Connect(function(trap)
		trap:GetAttributeChangedSignal("Armed"):Connect(function()
			local root = ClientState.Root()
			local pos = ClientState.PositionOf(trap)
			if trap:GetAttribute("Armed") == false and root and pos and (pos - root.Position).Magnitude < 40 then
				SoundController.Play("Trap", 0.6)
			end
		end)
	end)

	-- Guardian alarm while it chases you with an egg
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		if ClientState.IsChased() then
			SoundController.Play("Alarm")
		end
	end)
end

return SoundController

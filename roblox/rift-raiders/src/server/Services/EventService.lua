-- EventService: timed server events (Rift Storm, Golden Hour, Egg Stampede), rare Divine egg
-- spawns, and global announcements (this server + other servers via MessagingService).
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Net = require(Shared:WaitForChild("Net"))

local P = GameConfig.Progression

local EventService = {}
local Services

local active = nil -- { Id, Name, EndsAt, ...cfg }
local TOPIC = "RR_Announce"

function EventService.GetActive()
	if active and workspace:GetServerTimeNow() >= active.EndsAt then
		return nil
	end
	return active
end

local function broadcastEvent()
	local data = if active then { Id = active.Id, Name = active.Name, EndsAt = active.EndsAt } else {}
	Net.Event("Effect"):FireAllClients("Event", data)
	for player in pairs(Services.DataService.All()) do
		Services.DataService.Changed(player, "Coins") -- refreshes Derived.ActiveEvent
	end
end

function EventService.StartEvent(id: string)
	local cfg = P.Events[id]
	if not cfg then
		return false
	end
	active = table.clone(cfg)
	active.Id = id
	active.EndsAt = workspace:GetServerTimeNow() + cfg.Duration
	Services.DataService.Announce(("⚡ %s has begun! (%s)"):format(cfg.Name, GameConfig.FormatTime(cfg.Duration)), cfg.Color)
	broadcastEvent()
	local mine = active
	task.delay(cfg.Duration, function()
		if active == mine then
			active = nil
			Services.DataService.Announce(cfg.Name .. " is over.", cfg.Color)
			broadcastEvent()
		end
	end)
	return true
end

function EventService.SpawnDivine()
	local d = P.DivineSpawn
	local zones = Services.BiomeService.Zones()
	local index = math.random(math.min(d.MinBiome, #zones), #zones)
	local zone = zones[index]
	local event = EventService.GetActive()
	local data = { Rarity = "Divine", Mutation = if event and event.EventMutation then event.EventMutation else nil }
	if event and event.Id == "RiftStorm" and math.random() < 0.3 then
		data.Species = "RiftSovereign"
	end
	local egg = Services.EggService.SpawnSpecial(index, data, d.Lifetime)
	if egg then
		EventService.GlobalAnnounce(("✨ A DIVINE egg appeared in %s! It vanishes in %s."):format(zone.Biome.Name, GameConfig.FormatTime(d.Lifetime)),
			GameConfig.Rarities.ById.Divine.Color, true)
	end
end

-- localOnly = true skips the cross-server publish (used for world spawns on this server).
function EventService.GlobalAnnounce(text: string, color: Color3, localOnly: boolean?)
	Services.DataService.Announce(text, color)
	if localOnly or RunService:IsStudio() then
		return
	end
	task.spawn(pcall, function()
		MessagingService:PublishAsync(TOPIC, { Text = text, R = color.R, G = color.G, B = color.B, Job = game.JobId })
	end)
end

function EventService.Init(services)
	Services = services
end

function EventService.Start()
	Services.DataService.RegisterDerived(function(_player, _profile, d)
		local ev = EventService.GetActive()
		d.ActiveEvent = if ev then { Id = ev.Id, Name = ev.Name, EndsAt = ev.EndsAt } else nil
	end)

	if not RunService:IsStudio() then
		task.spawn(pcall, function()
			MessagingService:SubscribeAsync(TOPIC, function(msg)
				local m = msg.Data
				if type(m) == "table" and m.Job ~= game.JobId and type(m.Text) == "string" then
					Services.DataService.Announce("🌐 " .. m.Text, Color3.new(m.R or 1, m.G or 1, m.B or 1))
				end
			end)
		end)
	end

	-- event rotation
	task.spawn(function()
		local ids = {}
		for id in pairs(P.Events) do
			table.insert(ids, id)
		end
		table.sort(ids)
		while true do
			task.wait(math.random(P.EventInterval.Min, P.EventInterval.Max))
			if not EventService.GetActive() then
				EventService.StartEvent(ids[math.random(#ids)])
			end
		end
	end)

	-- Divine egg chance
	task.spawn(function()
		while true do
			task.wait(P.DivineSpawn.CheckInterval)
			if math.random() < P.DivineSpawn.Chance then
				EventService.SpawnDivine()
			end
		end
	end)
end

return EventService

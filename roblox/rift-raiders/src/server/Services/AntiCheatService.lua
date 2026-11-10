-- AntiCheatService: server-side movement validation (speed hacks / teleports).
-- Samples every character 4x per second; moving faster than the server-allowed walk speed
-- (plus tolerance) rubber-bands the player back. Repeated strikes kick.
-- Other services call Grace(player, seconds) before legit fast movement (knockback, launches,
-- server teleports) so it isn't flagged.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local S = GameConfig.Settings

local AntiCheatService = {}

type Track = { Pos: Vector3, At: number, Grace: number, Strikes: number, StrikeAt: number }
local tracks: { [Player]: Track } = {}

function AntiCheatService.Grace(player: Player, seconds: number)
	local t = tracks[player]
	if t then
		t.Grace = math.max(t.Grace, os.clock() + seconds)
	end
end

function AntiCheatService.Init() end

function AntiCheatService.Start()
	local function reset(player: Player)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		tracks[player] = {
			Pos = if hrp then hrp.Position else Vector3.zero,
			At = os.clock(),
			Grace = os.clock() + 3,
			Strikes = if tracks[player] then tracks[player].Strikes else 0,
			StrikeAt = 0,
		}
	end
	local function onPlayer(player: Player)
		reset(player)
		player.CharacterAdded:Connect(function()
			reset(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		tracks[p] = nil
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local now = os.clock()
		for player, t in pairs(tracks) do
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				continue
			end
			local pos = hrp.Position
			local elapsed = now - t.At
			if now < t.Grace or elapsed <= 0 then
				t.Pos, t.At = pos, now
				continue
			end
			local horizontal = Vector3.new(pos.X - t.Pos.X, 0, pos.Z - t.Pos.Z).Magnitude / elapsed
			local rise = (pos.Y - t.Pos.Y) / elapsed
			local allowed = (player:GetAttribute("AllowedWalkSpeed") or S.NormalWalkSpeed) * S.SpeedTolerance + S.SpeedSlack
			if horizontal > allowed or rise > 120 then
				if now - t.StrikeAt > 30 then
					t.Strikes = 0
				end
				t.Strikes += 1
				t.StrikeAt = now
				player.Character:PivotTo(CFrame.new(t.Pos) * hrp.CFrame.Rotation)
				hrp.AssemblyLinearVelocity = Vector3.zero
				if t.Strikes >= S.MaxStrikes then
					player:Kick("Unusual movement detected. Please rejoin.")
				end
				t.At = now
			else
				t.Pos, t.At = pos, now
			end
		end
	end)
end

return AntiCheatService

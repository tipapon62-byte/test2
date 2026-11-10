-- Per-player token-bucket rate limiter for remotes.
-- local limiter = RateLimiter.new(5, 1)  -- burst of 5, refills 1 token/sec
-- if not limiter:Allow(player) then return end
local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

local all = {}

function RateLimiter.new(burst: number, refillPerSecond: number)
	local self = setmetatable({ Burst = burst, Refill = refillPerSecond, Buckets = {} }, RateLimiter)
	table.insert(all, self)
	return self
end

function RateLimiter:Allow(player: Player): boolean
	local now = os.clock()
	local b = self.Buckets[player]
	if not b then
		b = { Tokens = self.Burst, At = now }
		self.Buckets[player] = b
	end
	b.Tokens = math.min(self.Burst, b.Tokens + (now - b.At) * self.Refill)
	b.At = now
	if b.Tokens < 1 then
		return false
	end
	b.Tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	for _, limiter in ipairs(all) do
		limiter.Buckets[player] = nil
	end
end)

return RateLimiter

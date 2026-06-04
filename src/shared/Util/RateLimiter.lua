--!strict

type Bucket = {
	tokens: number,
	last: number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: {
	_capacity: number,
	_refillPerSecond: number,
	_buckets: { [any]: Bucket },
}, RateLimiter))

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	assert(capacity > 0, "capacity must be positive")
	assert(refillPerSecond > 0, "refillPerSecond must be positive")

	return setmetatable({
		_capacity = capacity,
		_refillPerSecond = refillPerSecond,
		_buckets = {},
	}, RateLimiter)
end

function RateLimiter:Check(key: any): boolean
	local now = os.clock()
	local bucket = self._buckets[key]

	if bucket == nil then
		self._buckets[key] = {
			tokens = self._capacity - 1,
			last = now,
		}
		return true
	end

	local elapsed = math.max(0, now - bucket.last)
	bucket.last = now
	bucket.tokens = math.min(self._capacity, bucket.tokens + elapsed * self._refillPerSecond)

	if bucket.tokens < 1 then
		return false
	end

	bucket.tokens -= 1
	return true
end

function RateLimiter:Clear(key: any)
	self._buckets[key] = nil
end

return RateLimiter

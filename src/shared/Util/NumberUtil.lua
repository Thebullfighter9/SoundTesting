--!strict

local NumberUtil = {}

function NumberUtil.clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

function NumberUtil.lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * NumberUtil.clamp01(alpha)
end

function NumberUtil.inverseLerp(a: number, b: number, value: number): number
	if a == b then
		return 0
	end

	return NumberUtil.clamp01((value - a) / (b - a))
end

function NumberUtil.remap(value: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return NumberUtil.lerp(outMin, outMax, NumberUtil.inverseLerp(inMin, inMax, value))
end

function NumberUtil.expSmooth(current: number, target: number, deltaTime: number, speed: number): number
	local alpha = 1 - math.exp(-math.max(0, speed) * math.max(0, deltaTime))
	return current + (target - current) * alpha
end

function NumberUtil.sanitizeFiniteNumber(value: any, fallback: number?): number
	if typeof(value) ~= "number" then
		return fallback or 0
	end

	if value ~= value or value == math.huge or value == -math.huge then
		return fallback or 0
	end

	return value
end

return table.freeze(NumberUtil)

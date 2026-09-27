-- Small geometry helpers shared by server and client.
-- Yaw convention: CFrame.Angles(0, yaw, 0) looks towards (-sin yaw, 0, -cos yaw).

local MathUtil = {}

function MathUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function MathUtil.yawFromDirection(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

function MathUtil.lookFromYaw(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function MathUtil.rightFromYaw(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

-- Smallest signed angle to go from `from` to `to`, in [-pi, pi)
function MathUtil.angleDiff(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

function MathUtil.normalizeAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

function MathUtil.turnTowards(current: number, target: number, maxStep: number): number
	local diff = MathUtil.angleDiff(current, target)
	if math.abs(diff) <= maxStep then
		return MathUtil.normalizeAngle(target)
	end
	return MathUtil.normalizeAngle(current + math.sign(diff) * maxStep)
end

return MathUtil

--[[
	AimTargets
	Which enemy squad is under the cursor while aiming a Rush (B) or a Fire-at (T) order.
]]

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SquadRenderer = require(script.Parent:WaitForChild("SquadRenderer"))

local AimTargets = {}

local PADDING = 6 -- studs of slack around a squad's footprint

-- Where a squad is drawn right now (smoothed client position, else the last snapshot)
function AimTargets.position(squad: any): Vector3
	return SquadRenderer.getPosition(squad.id) or Vector3.new(squad.x, squad.y, squad.z)
end

-- The enemy squad whose footprint contains `point` (nearest one), or nil
function AimTargets.enemyAt(point: Vector3): any
	local best, bestDistance = nil, math.huge
	for _, squad in ClientState.squads do
		if squad.team ~= "Blue" then
			local position = AimTargets.position(squad)
			local distance = Vector2.new(position.X - point.X, position.Z - point.Z).Magnitude
			if distance <= (squad.radius or 8) + PADDING and distance < bestDistance then
				best, bestDistance = squad, distance
			end
		end
	end
	return best
end

return AimTargets

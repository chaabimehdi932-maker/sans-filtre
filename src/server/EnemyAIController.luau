--[[
	EnemyAIController
	Brain of every Red squad. The tactics live in SquadAI (shared with AllyAIController);
	this module owns the enemy's per-round tuning and spawns its waves.
	Tuning per round comes from GameConfig.getRound(round).ai via setTuning().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local MapService = require(script.Parent:WaitForChild("MapService"))
local SquadAI = require(script.Parent:WaitForChild("SquadAI"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))

local EnemyAIController = {}

local tuning = { aggression = 0.5, flankPreference = 0.3, retreatThreshold = 0.25, regroupRecover = 0.7 }

function EnemyAIController.setTuning(newTuning: any)
	tuning = newTuning
end

-- units = { { unitId, name?, statMultiplier?, damageMultiplier? } }
function EnemyAIController.spawnWave(units: { any })
	local spots = MapService.deployPositions("Red", #units, GameConfig.Recruitment.DeploySpacing)
	for i, unit in units do
		SquadService.create({
			unitId = unit.unitId,
			team = "Red",
			position = spots[i].position,
			yaw = spots[i].yaw,
			name = unit.name,
			statMultiplier = unit.statMultiplier,
			damageMultiplier = unit.damageMultiplier,
		})
	end
end

function EnemyAIController.think(squad: any, enemies: { any }, allies: { any }, now: number)
	SquadAI.think(squad, enemies, allies, tuning, now)
end

return EnemyAIController

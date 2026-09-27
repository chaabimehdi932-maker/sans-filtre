--[[
	SquadController
	One decision path per squad. Every tick each non-routing squad is driven by exactly one of:
	  • CommandService.applyOrder   — the squad its owner is commanding (isPlayerControlled)
	  • AllyAIController.think      — the owner's other squads
	  • EnemyAIController.think     — Red squads
	Flip squad.isPlayerControlled (CommandService.setControlled) and the next tick the squad
	simply goes through the other branch: no separate state to migrate.
	Decisions are throttled per squad (player orders 0.3 s, AI 0.5 s).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local AllyAIController = require(script.Parent:WaitForChild("AllyAIController"))
local CommandService = require(script.Parent:WaitForChild("CommandService"))
local EnemyAIController = require(script.Parent:WaitForChild("EnemyAIController"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))

local AI = GameConfig.AI

local SquadController = {}

function SquadController.tick()
	local now = time()
	local active = { Blue = {}, Red = {} }
	for _, squad in SquadService.getAll() do
		if squad.alive and not squad.routing then
			table.insert(active[squad.team], squad)
		end
	end
	for _, squad in SquadService.getAll() do
		if not squad.alive or squad.routing or now < (squad.nextThink or 0) then
			continue
		end
		if squad.isPlayerControlled then
			squad.nextThink = now + AI.CommandInterval
			CommandService.applyOrder(squad)
		else
			squad.nextThink = now + AI.DecisionInterval
			squad.rushing = false
			local enemies = if squad.team == "Blue" then active.Red else active.Blue
			local allies = active[squad.team]
			if squad.team == "Red" then
				EnemyAIController.think(squad, enemies, allies, now)
			else
				AllyAIController.think(squad, enemies, allies, now)
			end
		end
	end
end

return SquadController

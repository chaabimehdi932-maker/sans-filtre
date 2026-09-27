--[[
	AllyAIController
	Brain of the player's squads that are NOT under direct command. They behave like real
	allies: advance on objectives, engage nearby enemies, fall back when morale is low.
	Same tactics as the enemy (SquadAI), with friendly-side goals and GameConfig.AI.Ally tuning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local SquadAI = require(script.Parent:WaitForChild("SquadAI"))

local AllyAIController = {}

function AllyAIController.think(squad: any, enemies: { any }, allies: { any }, now: number)
	SquadAI.think(squad, enemies, allies, GameConfig.AI.Ally, now)
end

return AllyAIController

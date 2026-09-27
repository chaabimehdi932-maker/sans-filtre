--[[
	ReputationService
	Reputation per player per faction (saved in profile.Campaign.Reputation). Only the
	reputation with your employer matters in v1: it is gained by completing contracts, lost
	by failing them, and unlocks direct command of more squads in battle
	(CampaignConfig.Reputation.Tiers: reputation threshold → maxSquads).
	Losing a battle outside a contract never costs reputation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CampaignConfig = require(Modules:WaitForChild("CampaignConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local ReputationService = {}

ReputationService.hooks = {
	-- fired whenever reputation changes (CampaignService pushes the new state to the client)
	onChanged = function(_player: Player, _newValue: number, _delta: number, _tierUp: any?) end,
}

function ReputationService.get(player: Player, faction: string?): number
	local campaign = DataService.getCampaign(player)
	if not campaign then
		return 0
	end
	local id = faction or campaign.Faction
	return if id then campaign.Reputation[id] or 0 else 0
end

-- Adds (or removes, with a negative amount) reputation with the employer faction
function ReputationService.add(player: Player, amount: number)
	local campaign = DataService.getCampaign(player)
	if not campaign or not campaign.Faction or amount == 0 then
		return
	end
	local before = ReputationService.get(player)
	local after = math.max(CampaignConfig.Reputation.Min, before + amount)
	campaign.Reputation[campaign.Faction] = after
	local oldTier = CampaignConfig.reputationTier(before)
	local newTier = CampaignConfig.reputationTier(after)
	ReputationService.hooks.onChanged(
		player,
		after,
		after - before,
		if newTier.maxSquads > oldTier.maxSquads then newTier else nil
	)
end

-- How many squads the player may command directly at once
function ReputationService.maxControllableSquads(player: Player): number
	return CampaignConfig.reputationTier(ReputationService.get(player)).maxSquads
end

return ReputationService

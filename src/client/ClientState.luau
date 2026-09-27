--[[
	ClientState
	Latest game state pushed by the server. UI/VFX scripts read from here and listen to
	`Changed(key, ...)`. Nothing here is trusted by the server: it's display state only.
	Keys: "Phase" | "Squads" | "Zones" | "Recruit" | "Progress" | "Summary" | "Notify"
	      | "Campaign" (overworld state) | "CampaignTick" (positions, 5×/s) | "Encounter"
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local changed = Instance.new("BindableEvent")

local ClientState: { [string]: any } = {
	phase = nil,
	squads = {},
	squadsById = {},
	zones = {},
	hold = nil,
	recruit = nil,
	progress = nil,
	summary = nil,
	campaign = nil, -- { view, faction, gold, reputation, tier, nextTier, day, owners, atLocation, contract, board, … }
	world = nil, -- { day, x, z, moving, waiting, dest?, parties }
}
ClientState.Changed = changed.Event

Remotes.get("RoundStateChanged").OnClientEvent:Connect(function(info)
	ClientState.phase = info
	changed:Fire("Phase", info)
end)

Remotes.get("UpdateSquadState").OnClientEvent:Connect(function(list)
	local byId = {}
	for _, squad in list do
		byId[squad.id] = squad
	end
	ClientState.squads = list
	ClientState.squadsById = byId
	changed:Fire("Squads")
end)

Remotes.get("UpdateZoneState").OnClientEvent:Connect(function(data)
	ClientState.zones = data.zones or {}
	ClientState.hold = data.hold
	changed:Fire("Zones")
end)

Remotes.get("RecruitState").OnClientEvent:Connect(function(data)
	ClientState.recruit = data
	changed:Fire("Recruit")
end)

Remotes.get("PlayerProgress").OnClientEvent:Connect(function(data)
	ClientState.progress = data
	changed:Fire("Progress")
end)

Remotes.get("RoundSummary").OnClientEvent:Connect(function(data)
	ClientState.summary = data
	changed:Fire("Summary")
end)

-- kills made by your squad / by you (combo counter)
Remotes.get("KillFeed").OnClientEvent:Connect(function(data)
	changed:Fire("Kill", data)
end)

Remotes.get("Notify").OnClientEvent:Connect(function(text, tone)
	changed:Fire("Notify", text, tone)
end)

Remotes.get("CampaignState").OnClientEvent:Connect(function(data)
	if data.encounter then
		changed:Fire("Encounter", data.encounter)
		return
	end
	ClientState.campaign = data
	changed:Fire("Campaign")
end)

Remotes.get("CampaignTick").OnClientEvent:Connect(function(data)
	ClientState.world = data
	changed:Fire("CampaignTick")
end)

-- "Creation" | "Overworld" | "Battle" (nil until the server sent it)
function ClientState.view(): string?
	return if ClientState.campaign then ClientState.campaign.view else nil
end

function ClientState.phaseName(): string
	return if ClientState.phase then ClientState.phase.phase else "Waiting"
end

function ClientState.mySquads(): { any }
	local list = {}
	for _, squad in ClientState.squads do
		if squad.ownerId == player.UserId then
			table.insert(list, squad)
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

return ClientState

-- Feeds server snapshots to SquadRenderer and runs its per-frame animation.

local RunService = game:GetService("RunService")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SquadRenderer = require(script.Parent:WaitForChild("SquadRenderer"))

ClientState.Changed:Connect(function(key)
	if key == "Squads" then
		-- between rounds squads just vanish; during battles they die on screen
		local phase = ClientState.phaseName()
		SquadRenderer.sync(ClientState.squads, phase ~= "Battle" and phase ~= "Reward")
	end
end)

RunService.RenderStepped:Connect(SquadRenderer.update)

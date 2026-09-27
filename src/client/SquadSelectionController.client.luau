--[[
	Outlines the squad you command (gold Highlight) so you can always spot it in the melee.
	(You command one unit per battle, chosen before the battle; reinforcements replace it.)
]]

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SquadRenderer = require(script.Parent:WaitForChild("SquadRenderer"))

local highlight = Instance.new("Highlight")
highlight.Name = "CommandedSquad"
highlight.FillColor = Color3.fromRGB(255, 225, 110)
highlight.FillTransparency = 0.88
highlight.OutlineColor = Color3.fromRGB(255, 235, 140)
highlight.OutlineTransparency = 0.15
highlight.DepthMode = Enum.HighlightDepthMode.Occluded

local function refresh()
	local model = SquadRenderer.getModel(ClientActions.controlledId())
	if highlight.Parent ~= model then
		highlight.Adornee = model
		highlight.Parent = model
	end
end

ClientActions.Changed:Connect(function(what)
	if what == "Controlled" then
		refresh()
	end
end)
ClientState.Changed:Connect(function(key)
	if key == "Squads" then
		refresh()
	end
end)

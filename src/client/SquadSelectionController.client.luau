--[[
	Outlines the squads you command directly (gold Highlight) so you can always spot them in
	the melee. Your other squads (ally AI) are not outlined.
]]

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SquadRenderer = require(script.Parent:WaitForChild("SquadRenderer"))

local highlights: { [number]: Highlight } = {}

local function newHighlight(): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "CommandedSquad"
	highlight.FillColor = Color3.fromRGB(255, 225, 110)
	highlight.FillTransparency = 0.88
	highlight.OutlineColor = Color3.fromRGB(255, 235, 140)
	highlight.OutlineTransparency = 0.15
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	return highlight
end

local function refresh()
	local wanted = {}
	for _, id in ClientActions.controlledIds() do
		wanted[id] = true
		local model = SquadRenderer.getModel(id)
		local highlight = highlights[id]
		if model then
			if not highlight then
				highlight = newHighlight()
				highlights[id] = highlight
			end
			if highlight.Parent ~= model then
				highlight.Adornee = model
				highlight.Parent = model
			end
		end
	end
	for id, highlight in highlights do
		if not wanted[id] or not highlight.Parent then
			highlight:Destroy()
			highlights[id] = nil
		end
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

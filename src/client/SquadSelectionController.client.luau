--[[
	Which ONE of your squads you command directly.
	  Tab / Shift+Tab : next / previous squad   ·   click a card in the squad selector (HUD)
	The server hands the previous squad back to the ally AI and publishes the new one in the
	"ControlledSquad" attribute. The commanded squad gets a gold outline.
]]

local UserInputService = game:GetService("UserInputService")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SquadRenderer = require(script.Parent:WaitForChild("SquadRenderer"))

UserInputService.InputBegan:Connect(function(input)
	-- (gameProcessed is ignored for Tab: Roblox may flag it for its player list, which we hide)
	if input.KeyCode ~= Enum.KeyCode.Tab or UserInputService:GetFocusedTextBox() then
		return
	end
	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	ClientActions.cancelHold()
	ClientActions.selectSquad(if shift then "prev" else "next")
end)

-- Gold outline on the commanded squad
local highlight = Instance.new("Highlight")
highlight.Name = "CommandedSquad"
highlight.FillColor = Color3.fromRGB(255, 225, 110)
highlight.FillTransparency = 0.82
highlight.OutlineColor = Color3.fromRGB(255, 235, 140)
highlight.OutlineTransparency = 0.05
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

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

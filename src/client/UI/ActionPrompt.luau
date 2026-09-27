--[[
	ActionPrompt: the mouse-button prompt shown on the right side of the screen while aiming
	an order, e.g.  [🖱] Rush / [🖱] Cancel. Shared by the Rush and Hold previews.
]]

local Theme = require(script.Parent:WaitForChild("Theme"))

local ActionPrompt = {}

ActionPrompt.Confirm = Color3.fromRGB(70, 60, 220)
ActionPrompt.Cancel = Color3.fromRGB(215, 30, 45)

-- rows = { { color, label, key? } }  (key defaults to the mouse glyph)
function ActionPrompt.new(screen: Instance, name: string, rows: { any }): Frame
	local prompt = Theme.create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -40, 0.5, 0),
		Size = UDim2.fromOffset(240, #rows * 60),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
		Parent = screen,
	})
	for i, info in rows do
		local row = Theme.create("Frame", {
			Position = UDim2.fromOffset(0, (i - 1) * 60),
			Size = UDim2.fromOffset(240, 50),
			BackgroundColor3 = Color3.fromRGB(20, 20, 26),
			BackgroundTransparency = 0.25,
			ZIndex = 40,
			Parent = prompt,
		})
		Theme.corner(row, 6)
		local key = Theme.create("Frame", {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = info[1],
			ZIndex = 41,
			Parent = row,
		})
		Theme.corner(key, 5)
		Theme.border(key, Color3.new(0, 0, 0), 2)
		Theme.outlined({
			Size = UDim2.fromScale(1, 1),
			Text = info[3] or "🖱",
			TextSize = if info[3] then 18 else 22,
			ZIndex = 42,
			Parent = key,
		}, 1.5)
		Theme.outlined({
			Position = UDim2.fromOffset(54, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Text = info[2],
			Font = Theme.Bold,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 42,
			Parent = row,
		}, 2)
	end
	return prompt
end

return ActionPrompt

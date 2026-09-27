-- Shared colours, fonts and tiny helpers for building the HUD in code.

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(22, 22, 30),
	Slot = Color3.fromRGB(28, 28, 34),
	SlotStroke = Color3.fromRGB(0, 0, 0),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(175, 175, 190),
	Red = Color3.fromRGB(225, 35, 45),
	KeyRed = Color3.fromRGB(215, 30, 45),
	KeyBlue = Color3.fromRGB(40, 70, 220),
	KeyOrange = Color3.fromRGB(240, 120, 20),
	Gold = Color3.fromRGB(255, 205, 40),
	Green = Color3.fromRGB(70, 200, 100),
	Blue = Color3.fromRGB(45, 95, 215),
	Card = Color3.fromRGB(75, 40, 160),
	Health = Color3.fromRGB(230, 30, 35),
	Morale = Color3.fromRGB(240, 200, 60),
}

Theme.Display = Enum.Font.LuckiestGuy -- big cartoon banner font
Theme.Bold = Enum.Font.GothamBlack
Theme.Semi = Enum.Font.GothamBold
Theme.Body = Enum.Font.Gotham

-- create("TextLabel", { Size = ..., Parent = ... })
function Theme.create(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function Theme.corner(parent: Instance, radius: number?): UICorner
	return Theme.create("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

function Theme.round(parent: Instance): UICorner
	return Theme.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function Theme.stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	return Theme.create("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		Parent = parent,
	})
end

-- Border stroke for frames/buttons (as opposed to text outline)
function Theme.border(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Theme.stroke(parent, color, thickness)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

function Theme.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Semi,
		TextColor3 = Theme.Colors.Text,
		TextSize = 16,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Theme.create("TextLabel", defaults)
end

-- Horizontal bar: returns back frame and fill frame
function Theme.bar(props: { [string]: any }, fillColor: Color3): (Frame, Frame)
	local back = Theme.create("Frame", {
		BackgroundColor3 = Color3.fromRGB(15, 15, 18),
		BorderSizePixel = 0,
	})
	for key, value in props do
		(back :: any)[key] = value
	end
	local fill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Parent = back,
	})
	return back, fill
end

function Theme.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Theme

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
	KeyPink = Color3.fromRGB(225, 40, 150),
	Gold = Color3.fromRGB(255, 205, 40),
	Green = Color3.fromRGB(70, 200, 100),
	Blue = Color3.fromRGB(45, 95, 215),
	Card = Color3.fromRGB(75, 40, 160),
	Health = Color3.fromRGB(230, 30, 35),
	Morale = Color3.fromRGB(240, 200, 60),
}

Theme.Display = Enum.Font.LuckiestGuy -- big cartoon banner font
Theme.Bold = Enum.Font.FredokaOne -- rounded cartoon font used across the HUD
Theme.Semi = Enum.Font.FredokaOne
Theme.Body = Enum.Font.GothamMedium

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

-- Dark rounded tile with a thick black outline and a soft vertical gradient (HUD buttons)
function Theme.tile(props: { [string]: any }): TextButton
	local defaults = {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = false,
		Text = "",
	}
	for key, value in props do
		defaults[key] = value
	end
	local button = Theme.create("TextButton", defaults)
	Theme.corner(button, 7)
	Theme.create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(58, 58, 68), Color3.fromRGB(20, 20, 26)),
		Rotation = 90,
		Parent = button,
	})
	return button
end

-- Coloured key badge (e.g. the red "X" on the Hold button)
function Theme.keyBadge(
	parent: Instance,
	key: string,
	color: Color3,
	position: UDim2,
	anchor: Vector2?,
	size: number?
): Frame
	local s = size or 26
	local badge = Theme.create("Frame", {
		Name = "Key",
		Size = UDim2.fromOffset(s, s),
		Position = position,
		AnchorPoint = anchor or Vector2.zero,
		BackgroundColor3 = color,
		ZIndex = 5,
		Parent = parent,
	})
	Theme.corner(badge, 5)
	Theme.border(badge, Color3.new(0, 0, 0), 2)
	local label = Theme.text({
		Size = UDim2.fromScale(1, 1),
		Text = key,
		Font = Theme.Bold,
		TextSize = s * 0.68,
		ZIndex = 6,
		Parent = badge,
	})
	Theme.stroke(label, Color3.new(0, 0, 0), 1.5)
	return badge
end

-- White label with a black outline (the HUD's main text style)
function Theme.outlined(props: { [string]: any }, thickness: number?): TextLabel
	local label = Theme.text(props)
	Theme.stroke(label, Color3.new(0, 0, 0), thickness or 2)
	return label
end

function Theme.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Theme

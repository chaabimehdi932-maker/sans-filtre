--[[
	IconArt: simple white silhouette icons drawn with UI shapes, so the HUD needs no uploaded
	images and no emoji. (An id in Modules.Icons still takes priority.)
	IconArt.draw(name, props) → Frame, or nil if there is no drawing for that name.
]]

local IconArt = {}

local WHITE = Color3.fromRGB(245, 245, 250)
local SHADOW = Color3.fromRGB(0, 0, 0)

local function shape(parent: Instance, props: { [string]: any }, round: number?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = WHITE
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	for key, value in props do
		(frame :: any)[key] = value
	end
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(round, 0)
		corner.Parent = frame
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = SHADOW
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x, y)
end
local function size(w: number, h: number): UDim2
	return UDim2.fromScale(w, h)
end

local drawings: { [string]: (Frame, number) -> () } = {}

-- Shield: rounded top + pointed bottom, with a centre stripe
function drawings.Shield(icon, z)
	shape(icon, { Position = at(0.5, 0.36), Size = size(0.66, 0.46), ZIndex = z }, 0.18)
	shape(icon, { Position = at(0.5, 0.56), Size = size(0.47, 0.47), Rotation = 45, ZIndex = z }, 0.12)
	shape(
		icon,
		{
			Position = at(0.5, 0.5),
			Size = size(0.1, 0.62),
			BackgroundColor3 = Color3.fromRGB(70, 110, 200),
			ZIndex = z + 1,
		},
		0.5
	)
end

-- Crossed swords
function drawings.Swords(icon, z)
	for _, angle in { 45, -45 } do
		shape(icon, { Position = at(0.5, 0.46), Size = size(0.11, 0.78), Rotation = angle, ZIndex = z }, 0.4)
	end
	for _, spot in { { 0.25, 0.75, 45 }, { 0.75, 0.75, -45 } } do
		shape(
			icon,
			{
				Position = at(spot[1], spot[2]),
				Size = size(0.3, 0.09),
				Rotation = spot[3],
				BackgroundColor3 = Color3.fromRGB(230, 185, 70),
				ZIndex = z + 1,
			},
			0.5
		)
	end
end

-- Lightning bolt: three slanted bars in a zig-zag
function drawings.Lightning(icon, z)
	local gold = Color3.fromRGB(255, 220, 70)
	shape(
		icon,
		{ Position = at(0.57, 0.28), Size = size(0.16, 0.46), Rotation = 25, BackgroundColor3 = gold, ZIndex = z },
		0.2
	)
	shape(
		icon,
		{ Position = at(0.5, 0.5), Size = size(0.46, 0.14), Rotation = -10, BackgroundColor3 = gold, ZIndex = z },
		0.2
	)
	shape(
		icon,
		{ Position = at(0.44, 0.72), Size = size(0.16, 0.46), Rotation = 25, BackgroundColor3 = gold, ZIndex = z },
		0.2
	)
end

-- Soldier following an arrow
function drawings.Follow(icon, z)
	shape(icon, { Position = at(0.38, 0.24), Size = size(0.26, 0.26), ZIndex = z }, 0.5)
	shape(icon, { Position = at(0.38, 0.62), Size = size(0.4, 0.46), ZIndex = z }, 0.3)
	for i, x in { 0.72, 0.86 } do
		shape(icon, { Position = at(x, 0.43), Size = size(0.07, 0.24), Rotation = -40, ZIndex = z + i }, 0.5)
		shape(icon, { Position = at(x, 0.6), Size = size(0.07, 0.24), Rotation = 40, ZIndex = z + i }, 0.5)
	end
end

-- Circular arrow (dodge roll)
function drawings.Roll(icon, z)
	local ring =
		shape(icon, { Position = at(0.5, 0.52), Size = size(0.66, 0.66), BackgroundTransparency = 1, ZIndex = z }, 0.5)
	ring:SetAttribute("Outline", true) -- drawn by its stroke only
	local stroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = WHITE
	stroke.Transparency = 0
	stroke.Thickness = 5
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.62, 0),
		NumberSequenceKeypoint.new(0.63, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Rotation = 45
	gradient.Parent = stroke
	shape(icon, { Position = at(0.8, 0.28), Size = size(0.22, 0.22), Rotation = 45, ZIndex = z + 1 }, 0.1)
end

-- Healing cross
function drawings.Heal(icon, z)
	local green = Color3.fromRGB(110, 230, 110)
	shape(icon, { Position = at(0.5, 0.5), Size = size(0.24, 0.72), BackgroundColor3 = green, ZIndex = z }, 0.25)
	shape(icon, { Position = at(0.5, 0.5), Size = size(0.72, 0.24), BackgroundColor3 = green, ZIndex = z }, 0.25)
end

-- Horseshoe
function drawings.Horseshoe(icon, z)
	local ring =
		shape(icon, { Position = at(0.5, 0.45), Size = size(0.66, 0.66), BackgroundTransparency = 1, ZIndex = z }, 0.5)
	ring:SetAttribute("Outline", true) -- drawn by its stroke only
	local stroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = Color3.fromRGB(215, 175, 90)
	stroke.Transparency = 0
	stroke.Thickness = 7
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.72, 0),
		NumberSequenceKeypoint.new(0.73, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Rotation = 90 -- open at the bottom
	gradient.Parent = stroke
	for _, x in { 0.24, 0.76 } do
		shape(
			icon,
			{
				Position = at(x, 0.74),
				Size = size(0.13, 0.16),
				BackgroundColor3 = Color3.fromRGB(215, 175, 90),
				ZIndex = z,
			},
			0.3
		)
	end
end

-- Heart: two circles and a rotated square
function drawings.Heart(icon, z)
	shape(icon, { Position = at(0.34, 0.38), Size = size(0.4, 0.4), ZIndex = z }, 0.5)
	shape(icon, { Position = at(0.66, 0.38), Size = size(0.4, 0.4), ZIndex = z }, 0.5)
	shape(icon, { Position = at(0.5, 0.56), Size = size(0.42, 0.42), Rotation = 45, ZIndex = z }, 0.08)
end

-- Skull
function drawings.Skull(icon, z)
	local bone = Color3.fromRGB(245, 240, 230)
	shape(icon, { Position = at(0.5, 0.42), Size = size(0.72, 0.62), BackgroundColor3 = bone, ZIndex = z }, 0.5)
	shape(icon, { Position = at(0.5, 0.74), Size = size(0.42, 0.24), BackgroundColor3 = bone, ZIndex = z }, 0.25)
	for _, x in { 0.35, 0.65 } do
		shape(
			icon,
			{
				Position = at(x, 0.45),
				Size = size(0.18, 0.2),
				BackgroundColor3 = Color3.fromRGB(30, 10, 10),
				ZIndex = z + 1,
			},
			0.5
		)
	end
end

-- which drawing each icon slot uses
local ALIASES = {
	OrderHold = "Shield",
	OrderFollow = "Follow",
	OrderAttack = "Swords",
	OrderRush = "Lightning",
	Attack = "Swords",
	Block = "Shield",
	Roll = "Roll",
	Heal = "Heal",
	Mount = "Horseshoe",
	Heart = "Heart",
	Skull = "Skull",
}

function IconArt.draw(name: string, props: { [string]: any }): Frame?
	local drawing = drawings[ALIASES[name] or name]
	if not drawing then
		return nil
	end
	local icon = Instance.new("Frame")
	icon.Name = "Icon_" .. name
	icon.BackgroundTransparency = 1
	for key, value in props do
		if key ~= "TextSize" and key ~= "Text" then
			(icon :: any)[key] = value
		end
	end
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = icon
	drawing(icon, (props.ZIndex or 1))
	return icon
end

return IconArt

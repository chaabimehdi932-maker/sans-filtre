--[[
	ObjectiveMarkers: lettered diamonds (A, B, C…) coloured by owner with the distance in metres,
	for each capture zone. They stay inside a safe rectangle that avoids every HUD region, and
	hide when the zone is on screen and close (its world label is then visible instead, so the
	two never cover each other).
	Minimap (top-right, press M): north-up map of zones, squads and the commander.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local create, text = Theme.create, Theme.text
local player = Players.LocalPlayer

local STUDS_TO_METERS = 0.28
local OWNER_COLORS = {
	Blue = Color3.fromRGB(45, 95, 215),
	Red = Color3.fromRGB(205, 45, 45),
	Neutral = Color3.fromRGB(150, 150, 150),
}

local Markers = {}

-- `root` is the (unscaled) ScreenGui: markers are placed in real screen pixels
function Markers.build(root: Instance, ClientState: any, ClientActions: any, regions: any): any
	local api = {}

	---------------------------------------------------------------- objective markers
	local layer = create("Frame", {
		Name = "ObjectiveMarkers",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local markers: { [string]: any } = {}

	-- One label per zone (the server draws none): letter diamond on top, then name + distance,
	-- a capture bar and the zone bonus. Stacked vertically, so nothing covers the name.
	local function markerFor(name: string, letter: string): any
		local marker = markers[name]
		if marker then
			return marker
		end
		local frame = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(170, 96),
			BackgroundTransparency = 1,
			Parent = layer,
		})
		local scale = create("UIScale", { Parent = frame })
		local diamond = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 22),
			Size = UDim2.fromOffset(28, 28),
			Rotation = 45,
			BackgroundColor3 = OWNER_COLORS.Neutral,
			Parent = frame,
		})
		Theme.corner(diamond, 4)
		Theme.border(diamond, Color3.new(1, 1, 1), 3)
		local ring = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 22),
			Size = UDim2.fromOffset(50, 50),
			BackgroundTransparency = 1,
			Parent = frame,
		})
		Theme.round(ring)
		local ringStroke = Theme.border(ring, Color3.new(1, 1, 1), 2)
		local icon = Theme.outlined({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 22),
			Size = UDim2.fromOffset(30, 30),
			Text = letter,
			Font = Theme.Bold,
			TextSize = 22,
			ZIndex = 2,
			Parent = frame,
		}, 2)
		local title = Theme.outlined({
			Position = UDim2.fromOffset(0, 44),
			Size = UDim2.new(1, 0, 0, 20),
			Font = Theme.Bold,
			TextSize = 18,
			Parent = frame,
		}, 2)
		local barBack, barFill = Theme.bar(
			{ Position = UDim2.new(0.5, -45, 0, 67), Size = UDim2.fromOffset(90, 7), Parent = frame },
			OWNER_COLORS.Neutral
		)
		Theme.corner(barBack, 4)
		Theme.corner(barFill, 4)
		Theme.border(barBack, Color3.new(0, 0, 0), 1.5)
		local bonus = Theme.outlined({
			Position = UDim2.fromOffset(0, 77),
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 13,
			TextColor3 = Color3.fromRGB(215, 225, 255),
			Parent = frame,
		}, 1.5)
		marker = {
			frame = frame,
			scale = scale,
			circle = diamond,
			icon = icon,
			title = title,
			bar = barFill,
			bonus = bonus,
			ring = ringStroke,
		}
		markers[name] = marker
		return marker
	end

	---------------------------------------------------------------- minimap
	local map = create("Frame", {
		Name = "Minimap",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(190, 190),
		BackgroundColor3 = Color3.fromRGB(35, 60, 35),
		BackgroundTransparency = 0.15,
		ClipsDescendants = true,
		Visible = false, -- press M
		Parent = regions.topRight,
	})
	game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.M then
			map.Visible = not map.Visible
		end
	end)
	Theme.corner(map, 8)
	Theme.border(map, Color3.new(0, 0, 0), 3)
	local bounds = { minX = -300, minZ = -300, size = 600 }
	local boundsReady = false

	local function computeBounds()
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		local function include(x: number, z: number, radius: number)
			minX, maxX = math.min(minX, x - radius), math.max(maxX, x + radius)
			minZ, maxZ = math.min(minZ, z - radius), math.max(maxZ, z + radius)
		end
		for _, zone in ClientState.zones do
			include(zone.x, zone.z, zone.radius)
		end
		for _, tag in { "PlayerDeployZone", "EnemyDeployZone" } do
			for _, part in CollectionService:GetTagged(tag) do
				if part:IsA("BasePart") then
					include(part.Position.X, part.Position.Z, math.max(part.Size.X, part.Size.Z) / 2)
				end
			end
		end
		if minX == math.huge then
			return
		end
		local size = math.max(maxX - minX, maxZ - minZ) + 60
		bounds = { minX = (minX + maxX) / 2 - size / 2, minZ = (minZ + maxZ) / 2 - size / 2, size = size }
		boundsReady = true
	end

	local function toMap(x: number, z: number): UDim2
		return UDim2.fromScale((x - bounds.minX) / bounds.size, (z - bounds.minZ) / bounds.size)
	end

	local zoneDots: { [string]: Frame } = {}
	local squadDots: { Frame } = {}
	local arrow = text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		Text = "▲",
		TextSize = 16,
		TextColor3 = C.Gold,
		ZIndex = 5,
		Parent = map,
	})
	Theme.stroke(arrow, Color3.new(0, 0, 0), 1.5)

	function api.onZones()
		if not boundsReady then
			computeBounds()
		end
		for _, zone in ClientState.zones do
			local dot = zoneDots[zone.name]
			if not dot then
				dot = create(
					"Frame",
					{ AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 0.35, ZIndex = 2, Parent = map }
				)
				Theme.round(dot)
				Theme.border(dot, Color3.new(1, 1, 1), 1)
				zoneDots[zone.name] = dot
			end
			local scale = zone.radius * 2 / bounds.size
			dot.Size = UDim2.fromScale(scale, scale)
			dot.Position = toMap(zone.x, zone.z)
			dot.BackgroundColor3 = OWNER_COLORS[zone.owner] or OWNER_COLORS.Neutral
		end
	end

	function api.onSquads()
		for i, squad in ClientState.squads do
			local dot = squadDots[i]
			if not dot then
				dot = create(
					"Frame",
					{ AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 3, Parent = map }
				)
				squadDots[i] = dot
			end
			local isSelected = squad.id == ClientActions.controlledId()
			dot.Visible = true
			dot.Size = UDim2.fromOffset(if isSelected then 9 else 6, if isSelected then 9 else 6)
			dot.Position = toMap(squad.x, squad.z)
			dot.BackgroundColor3 = if isSelected
				then C.Gold
				elseif squad.team == "Blue" then Color3.fromRGB(90, 150, 255)
				else Color3.fromRGB(255, 80, 80)
			dot.BackgroundTransparency = if squad.state == "Routing" then 0.6 else 0
		end
		for i = #ClientState.squads + 1, #squadDots do
			squadDots[i].Visible = false
		end
	end

	---------------------------------------------------------------- per frame
	function api.render()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local rootPosition = if root and root:IsA("BasePart") then root.Position else camera.CFrame.Position

		-- minimap arrow
		arrow.Position = toMap(rootPosition.X, rootPosition.Z)
		local look = camera.CFrame.LookVector
		arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))

		-- objective markers
		-- safe rectangle (pixels) between the HUD regions
		local viewport = camera.ViewportSize
		local function bottomOf(frame: GuiObject): number
			return if frame.Visible then frame.AbsolutePosition.Y + frame.AbsoluteSize.Y else 0
		end
		local left = regions.left.AbsolutePosition.X + regions.left.AbsoluteSize.X + 30
		local right = viewport.X - 60
		local top = math.max(bottomOf(regions.topCenter), bottomOf(regions.topRight)) + 100
		local bottom = regions.bottomCenter.AbsolutePosition.Y - 50
		local seen = {}
		local showMarkers = ClientState.phaseName() == "Battle"
		layer.Visible = showMarkers
		local uiScale = math.clamp(math.min(viewport.X / 1600, viewport.Y / 900), 0.45, 1.35)
		for index, zone in ClientState.zones do
			seen[zone.name] = true
			local marker = markerFor(zone.name, string.char(64 + index))
			local zonePosition = Vector3.new(zone.x, zone.y, zone.z)
			local distance = (rootPosition - zonePosition).Magnitude
			local screen, onScreen = camera:WorldToViewportPoint(zonePosition + Vector3.new(0, 14, 0))
			marker.frame.Visible = showMarkers and right > left and bottom > top
			if marker.frame.Visible then
				marker.scale.Scale = uiScale
				local position = Vector2.new(screen.X, screen.Y)
				local center = Vector2.new((left + right) / 2, (top + bottom) / 2)
				local inside = onScreen
					and position.X >= left
					and position.X <= right
					and position.Y >= top
					and position.Y <= bottom
				if not inside then
					local direction = position - center
					if screen.Z < 0 then
						direction = -direction
					end
					if direction.Magnitude < 1 then
						direction = Vector2.new(0, -1)
					end
					local fit = math.min(
						(right - left) / 2 / math.max(math.abs(direction.X), 0.001),
						(bottom - top) / 2 / math.max(math.abs(direction.Y), 0.001)
					)
					position = center + direction * fit
				end
				marker.frame.Position = UDim2.fromOffset(position.X, position.Y)
				local owner = OWNER_COLORS[zone.owner] or OWNER_COLORS.Neutral
				marker.circle.BackgroundColor3 = owner
				marker.title.Text = string.format("%s  %dm", string.upper(zone.name), distance * STUDS_TO_METERS)
				local leaning = if zone.control > 0 then "Blue" elseif zone.control < 0 then "Red" else "Neutral"
				marker.bar.BackgroundColor3 = OWNER_COLORS[leaning]
				marker.bar.Size = UDim2.fromScale(math.abs(zone.control) / 100, 1)
				marker.bonus.Text = (if zone.contested then "⚔ CONTESTED  " else "")
					.. (if zone.bonus then "+" .. zone.bonus else "")
				-- contested zones pulse
				marker.ring.Transparency = if zone.contested then 0.2 + math.abs(math.sin(os.clock() * 5)) * 0.8 else 1
			end
		end
		for name, marker in markers do
			if not seen[name] then
				marker.frame.Visible = false
			end
		end
	end

	return api
end

return Markers

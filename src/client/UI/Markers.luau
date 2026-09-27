--[[
	ObjectiveMarkers: circular "+" icons with the distance in metres, pinned over each capture
	zone and clamped to the screen edge when the zone is off-screen.
	Minimap (top-right): north-up map of zones, squads and the commander.
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

function Markers.build(root: ScreenGui, ClientState: any): any
	local api = {}

	---------------------------------------------------------------- objective markers
	local layer = create("Frame", {
		Name = "ObjectiveMarkers",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local markers: { [string]: any } = {}

	local function markerFor(name: string): any
		local marker = markers[name]
		if marker then
			return marker
		end
		local frame = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(44, 60),
			BackgroundTransparency = 1,
			Parent = layer,
		})
		local circle = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = OWNER_COLORS.Blue,
			Parent = frame,
		})
		Theme.round(circle)
		Theme.border(circle, Color3.new(1, 1, 1), 3)
		local icon =
			text({ Size = UDim2.fromScale(1, 1), Text = "+", Font = Theme.Bold, TextSize = 32, Parent = circle })
		local distance = text({
			Position = UDim2.fromOffset(-20, 42),
			Size = UDim2.new(1, 40, 0, 18),
			Font = Theme.Bold,
			TextSize = 15,
			Parent = frame,
		})
		Theme.stroke(distance, Color3.new(0, 0, 0), 1.5)
		marker = { frame = frame, circle = circle, icon = icon, distance = distance }
		markers[name] = marker
		return marker
	end

	---------------------------------------------------------------- minimap
	local map = create("Frame", {
		Name = "Minimap",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(190, 190),
		BackgroundColor3 = Color3.fromRGB(35, 60, 35),
		BackgroundTransparency = 0.15,
		ClipsDescendants = true,
		Parent = root,
	})
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
		local selected = ClientState.selectedId()
		for i, squad in ClientState.squads do
			local dot = squadDots[i]
			if not dot then
				dot = create(
					"Frame",
					{ AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 3, Parent = map }
				)
				squadDots[i] = dot
			end
			local isSelected = squad.id == selected
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
		local viewport = camera.ViewportSize
		local center = viewport / 2
		local seen = {}
		local showMarkers = ClientState.phaseName() == "Battle"
		for _, zone in ClientState.zones do
			seen[zone.name] = true
			local marker = markerFor(zone.name)
			marker.frame.Visible = showMarkers
			if showMarkers then
				local world = Vector3.new(zone.x, zone.y + 16, zone.z)
				local screen, onScreen = camera:WorldToViewportPoint(world)
				local position = Vector2.new(screen.X, screen.Y)
				if not onScreen then
					local direction = position - center
					if screen.Z < 0 then
						direction = -direction
					end
					if direction.Magnitude < 1 then
						direction = Vector2.new(0, -1)
					end
					local margin = 60
					local scale = math.min(
						(center.X - margin) / math.max(math.abs(direction.X), 0.001),
						(center.Y - margin) / math.max(math.abs(direction.Y), 0.001)
					)
					position = center + direction * scale
				end
				marker.frame.Position = UDim2.fromOffset(position.X, position.Y)
				marker.circle.BackgroundColor3 = OWNER_COLORS[zone.owner] or OWNER_COLORS.Neutral
				marker.icon.Text = if zone.contested then "⚔" elseif zone.owner == "Blue" then "✓" else "+"
				marker.icon.TextSize = if zone.contested then 22 else 32
				local meters = (rootPosition - Vector3.new(zone.x, zone.y, zone.z)).Magnitude * STUDS_TO_METERS
				marker.distance.Text = string.format("%s · %dm", zone.name, meters)
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

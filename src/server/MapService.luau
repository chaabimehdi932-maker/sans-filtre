--[[
	MapService
	Everything the other services need to know about the battlefield.
	The real map is built by hand in Studio; scripts only look for CollectionService tags:
	  "CaptureZone"      Part (block or flat cylinder). Attributes: ZoneName, Bonus ("Income" |
	                     "Morale" | "ArtilleryRange"), Order (number), Radius (optional)
	  "PlayerDeployZone" Part where the player's army deploys
	  "EnemyDeployZone"  Part where enemy squads spawn
	If no CaptureZone exists, a placeholder map is generated so the game is playable right away.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MapService = {}

MapService.TAG_ZONE = "CaptureZone"
MapService.TAG_PLAYER_DEPLOY = "PlayerDeployZone"
MapService.TAG_ENEMY_DEPLOY = "EnemyDeployZone"

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true -- squads, zones and horses are CanCollide = false
local lastFilterRefresh = -math.huge

local function refreshFilter()
	local now = time()
	if now - lastFilterRefresh < 1 then
		return
	end
	lastFilterRefresh = now
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
end

-- Height of the ground at (x, z), searching around `nearY` first so squads don't climb onto roofs
function MapService.groundY(x: number, z: number, nearY: number?): number
	refreshFilter()
	if nearY then
		local hit = Workspace:Raycast(Vector3.new(x, nearY + 8, z), Vector3.new(0, -60, 0), groundParams)
		if hit then
			return hit.Position.Y
		end
	end
	local hit = Workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), groundParams)
	if hit then
		return hit.Position.Y
	end
	return nearY or 0
end

local function newAnchored(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- Placeholder battlefield: flat field, 3 zones, 2 deployment areas, a few houses
local function buildPlaceholderMap()
	local folder = Workspace:FindFirstChild("Map")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Map"
		folder.Parent = Workspace
	end

	if not Workspace:Raycast(Vector3.new(0, 500, 0), Vector3.new(0, -1000, 0)) then
		newAnchored({
			Name = "Ground",
			Size = Vector3.new(800, 4, 800),
			Position = Vector3.new(0, -2, 0),
			Color = Color3.fromRGB(75, 150, 60),
			Material = Enum.Material.Grass,
			Parent = folder,
		})
	end

	local zones = {
		{ name = "Plains", position = Vector3.new(0, 0, -20), radius = 32, bonus = "Income", order = 1 },
		{ name = "Village", position = Vector3.new(-120, 0, -70), radius = 26, bonus = "Morale", order = 2 },
		{ name = "Ridge", position = Vector3.new(120, 0, -70), radius = 26, bonus = "ArtilleryRange", order = 3 },
	}
	for _, zone in zones do
		local y = MapService.groundY(zone.position.X, zone.position.Z)
		local part = newAnchored({
			Name = "Zone_" .. zone.name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, zone.radius * 2, zone.radius * 2),
			CFrame = CFrame.new(zone.position.X, y + 0.5, zone.position.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = folder,
		})
		part:SetAttribute("ZoneName", zone.name)
		part:SetAttribute("Bonus", zone.bonus)
		part:SetAttribute("Order", zone.order)
		CollectionService:AddTag(part, MapService.TAG_ZONE)
	end

	local function deploy(tag: string, z: number, color: Color3)
		local y = MapService.groundY(0, z)
		local part = newAnchored({
			Name = tag,
			Size = Vector3.new(260, 1, 60),
			Position = Vector3.new(0, y + 0.1, z),
			Color = color,
			Transparency = 0.85,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = folder,
		})
		CollectionService:AddTag(part, tag)
	end
	deploy(MapService.TAG_PLAYER_DEPLOY, 230, Color3.fromRGB(45, 95, 215))
	deploy(MapService.TAG_ENEMY_DEPLOY, -230, Color3.fromRGB(205, 45, 45))

	-- A few houses in the village (they block paths, so PathfindingService has something to do)
	local village = zones[2].position
	for i, offset in
		{ Vector3.new(-14, 0, -12), Vector3.new(12, 0, -16), Vector3.new(-16, 0, 14), Vector3.new(16, 0, 12) }
	do
		local base = village + offset
		local y = MapService.groundY(base.X, base.Z)
		newAnchored({
			Name = "House" .. i,
			Size = Vector3.new(10, 8, 12),
			Position = Vector3.new(base.X, y + 4, base.Z),
			Color = Color3.fromRGB(225, 215, 190),
			Material = Enum.Material.Brick,
			Parent = folder,
		})
		newAnchored({
			Name = "Roof" .. i,
			Size = Vector3.new(11, 3, 13),
			Position = Vector3.new(base.X, y + 9.5, base.Z),
			Color = Color3.fromRGB(150, 60, 45),
			Material = Enum.Material.Slate,
			Parent = folder,
		})
	end
end

function MapService.ensureMap()
	if #CollectionService:GetTagged(MapService.TAG_ZONE) == 0 then
		buildPlaceholderMap()
	end
end

function MapService.getZoneParts(): { BasePart }
	local parts = {}
	for _, instance in CollectionService:GetTagged(MapService.TAG_ZONE) do
		if instance:IsA("BasePart") then
			table.insert(parts, instance)
		end
	end
	table.sort(parts, function(a, b)
		local oa, ob = a:GetAttribute("Order") or 99, b:GetAttribute("Order") or 99
		if oa ~= ob then
			return oa < ob
		end
		return a.Name < b.Name
	end)
	return parts
end

function MapService.getDeployPart(team: string): BasePart?
	local tag = if team == "Blue" then MapService.TAG_PLAYER_DEPLOY else MapService.TAG_ENEMY_DEPLOY
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") then
			return instance
		end
	end
	return nil
end

local function deployCenter(team: string): Vector3
	local part = MapService.getDeployPart(team)
	if part then
		return part.Position
	end
	return Vector3.new(0, 0, if team == "Blue" then 230 else -230)
end

-- Direction a team faces when deployed: towards the enemy deployment zone
function MapService.facingYaw(team: string): number
	local from = deployCenter(team)
	local to = deployCenter(if team == "Blue" then "Red" else "Blue")
	local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if dir.Magnitude < 1 then
		return 0
	end
	return math.atan2(-dir.X, -dir.Z)
end

-- Evenly spread positions for `count` squads inside a team's deployment zone
function MapService.deployPositions(
	team: string,
	count: number,
	spacing: number
): { { position: Vector3, yaw: number } }
	local center = deployCenter(team)
	local part = MapService.getDeployPart(team)
	local width = if part then math.max(part.Size.X, part.Size.Z) else 240
	local yaw = MapService.facingYaw(team)
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local back = -Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local perRow = math.max(1, math.floor((width - 20) / spacing) + 1)
	local spots = {}
	for i = 1, count do
		local row = (i - 1) // perRow
		local inRow = math.min(perRow, count - row * perRow)
		local col = (i - 1) % perRow
		local lateral = (col - (inRow - 1) / 2) * spacing
		local p = center + right * lateral + back * (row * 22)
		table.insert(spots, { position = Vector3.new(p.X, MapService.groundY(p.X, p.Z), p.Z), yaw = yaw })
	end
	return spots
end

-- Where the commander spawns: behind the middle of their deployment zone
function MapService.spawnCFrame(team: string): CFrame
	local center = deployCenter(team)
	local yaw = MapService.facingYaw(team)
	local back = -Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local p = center + back * 30
	return CFrame.new(p.X, MapService.groundY(p.X, p.Z) + 5, p.Z) * CFrame.Angles(0, yaw, 0)
end

return MapService

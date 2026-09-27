--[[
	MapService
	Everything the other services need to know about the battlefield.
	The real map is built by hand in Studio; scripts only look for CollectionService tags:
	  "CaptureZone"      Part (block or flat cylinder). Attributes: ZoneName, Bonus ("Reinforcements" |
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
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	-- squads walk through placeholder scenery instead of climbing onto roofs
	local map = Workspace:FindFirstChild("Map")
	local scenery = map and map:FindFirstChild("Scenery")
	if scenery then
		table.insert(list, scenery)
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

local function newPart(parent: Instance, props: { [string]: any }): Part
	local part = newAnchored(props)
	part.Parent = parent
	return part
end

-- Only in placeholder mode: a sunny, hazy look (your own map keeps its own Lighting)
local function setupLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 15.3 -- afternoon sun: longer shadows
	Lighting.GeographicLatitude = 42
	Lighting.Brightness = 2.6
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(135, 140, 155)
	Lighting.ShadowSoftness = 0.3
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	local function ensure(className: string, props: { [string]: any })
		if Lighting:FindFirstChildOfClass(className) then
			return
		end
		local effect = Instance.new(className)
		for key, value in props do
			(effect :: any)[key] = value
		end
		effect.Parent = Lighting
	end
	ensure("Atmosphere", {
		Density = 0.3,
		Offset = 0.15,
		Color = Color3.fromRGB(200, 218, 240),
		Decay = Color3.fromRGB(110, 120, 140),
		Glare = 0.25,
		Haze = 1.4,
	})
	ensure("ColorCorrectionEffect", { Saturation = 0.18, Contrast = 0.08, TintColor = Color3.fromRGB(255, 250, 240) })
	ensure("BloomEffect", { Intensity = 0.35, Size = 24, Threshold = 1.6 })
	ensure("SunRaysEffect", { Intensity = 0.05, Spread = 0.8 })
	-- slight blur on the far background adds depth (Atmosphere haze replaces classic fog)
	ensure("DepthOfFieldEffect", { FarIntensity = 0.12, FocusDistance = 120, InFocusRadius = 140, NearIntensity = 0 })
	if not Workspace.Terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.6
		clouds.Density = 0.7
		clouds.Parent = Workspace.Terrain
	end
end

local rng = Random.new(1815)

local function tree(parent: Instance, position: Vector3)
	local y = MapService.groundY(position.X, position.Z)
	local height = rng:NextNumber(7, 11)
	newPart(parent, {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 1.1, 1.1),
		CFrame = CFrame.new(position.X, y + height / 2, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(95, 65, 40),
		Material = Enum.Material.Wood,
	})
	local green = Color3.fromRGB(55, 115, 45):Lerp(Color3.fromRGB(95, 145, 55), rng:NextNumber())
	for i = 1, 3 do
		local size = rng:NextNumber(5, 7.5)
		newPart(parent, {
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			Position = Vector3.new(
				position.X + rng:NextNumber(-1.5, 1.5),
				y + height + rng:NextNumber(-1, 2) - (i - 1),
				position.Z + rng:NextNumber(-1.5, 1.5)
			),
			Color = green,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
end

local function house(parent: Instance, position: Vector3, yaw: number)
	local y = MapService.groundY(position.X, position.Z)
	local base = CFrame.new(position.X, y, position.Z) * CFrame.Angles(0, yaw, 0)
	local plaster = Color3.fromRGB(232, 222, 198):Lerp(Color3.fromRGB(210, 190, 160), rng:NextNumber())
	local roof = Color3.fromRGB(150, 62, 45):Lerp(Color3.fromRGB(95, 80, 70), rng:NextNumber())
	newPart(parent, {
		Name = "Walls",
		Size = Vector3.new(10, 7, 13),
		CFrame = base * CFrame.new(0, 3.5, 0),
		Color = plaster,
		Material = Enum.Material.Plaster,
	})
	newPart(parent, {
		Name = "Base",
		Size = Vector3.new(10.6, 1, 13.6),
		CFrame = base * CFrame.new(0, 0.5, 0),
		Color = Color3.fromRGB(120, 115, 105),
		Material = Enum.Material.Cobblestone,
	})
	for _, side in { -1, 1 } do
		newPart(parent, {
			Name = "Roof",
			Size = Vector3.new(6.6, 0.5, 14.2),
			CFrame = base * CFrame.new(side * 2.55, 8.9, 0) * CFrame.Angles(0, 0, math.rad(-side * 38)),
			Color = roof,
			Material = Enum.Material.Slate,
		})
	end
	for _, z in { -6.3, 6.3 } do
		-- gable ends: a stack of shrinking blocks
		for step = 0, 3 do
			local width = 9.4 - step * 2.3
			newPart(parent, {
				Name = "Gable",
				Size = Vector3.new(width, 1, 0.4),
				CFrame = base * CFrame.new(0, 7.5 + step, z),
				Color = plaster,
				Material = Enum.Material.Plaster,
			})
		end
	end
	newPart(parent, {
		Name = "Chimney",
		Size = Vector3.new(1.4, 4, 1.4),
		CFrame = base * CFrame.new(2.5, 10, 3),
		Color = Color3.fromRGB(130, 70, 55),
		Material = Enum.Material.Brick,
	})
	newPart(parent, {
		Name = "Door",
		Size = Vector3.new(2.2, 4, 0.3),
		CFrame = base * CFrame.new(0, 2.5, -6.55),
		Color = Color3.fromRGB(90, 55, 30),
		Material = Enum.Material.WoodPlanks,
	})
	for _, x in { -3.2, 3.2 } do
		newPart(parent, {
			Name = "Window",
			Size = Vector3.new(1.8, 1.8, 0.3),
			CFrame = base * CFrame.new(x, 4.2, -6.55),
			Color = Color3.fromRGB(60, 80, 110),
			Material = Enum.Material.Glass,
			Reflectance = 0.2,
		})
		newPart(parent, {
			Name = "Shutter",
			Size = Vector3.new(0.5, 2, 0.35),
			CFrame = base * CFrame.new(x - 1.2, 4.2, -6.6),
			Color = Color3.fromRGB(60, 95, 60),
			Material = Enum.Material.WoodPlanks,
		})
	end
end

local function stoneWall(parent: Instance, from: Vector3, to: Vector3)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	local y = MapService.groundY(mid.X, mid.Z)
	newPart(parent, {
		Name = "StoneWall",
		Size = Vector3.new(1.6, 2.2, length),
		CFrame = CFrame.lookAt(Vector3.new(mid.X, y + 1.1, mid.Z), Vector3.new(to.X, y + 1.1, to.Z)),
		Color = Color3.fromRGB(125, 120, 110),
		Material = Enum.Material.Cobblestone,
	})
end

-- Placeholder battlefield: grass terrain, hills, road, village, woods, 3 zones, 2 deployment areas
local function buildPlaceholderMap()
	local folder = Workspace:FindFirstChild("Map")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Map"
		folder.Parent = Workspace
	end
	setupLighting()

	-- Replace the grey template Baseplate with grass terrain
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Transparency = 1
		baseplate.CanCollide = false
		baseplate.CanQuery = false
	end
	local terrain = Workspace.Terrain
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(1000, 12, 1000), Enum.Material.Grass)
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(95, 145, 60))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(70, 120, 45))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(120, 95, 65))
	-- texture variation: patches of darker grass, trampled mud and bare earth
	for _ = 1, 90 do
		local x, z = rng:NextNumber(-450, 450), rng:NextNumber(-450, 450)
		local material = ({
			Enum.Material.LeafyGrass,
			Enum.Material.LeafyGrass,
			Enum.Material.Mud,
			Enum.Material.Ground,
		})[rng:NextInteger(1, 4)]
		local size = rng:NextNumber(14, 40)
		terrain:FillCylinder(CFrame.new(x, -1.5, z), 3, size, material)
	end
	-- the Ridge zone sits on high ground (its bonus is artillery range)
	terrain:FillBall(Vector3.new(120, -26, -70), 36, Enum.Material.Grass)
	for _, hill in
		{
			{ -300, -45, 60, 70 },
			{ 310, -55, 180, 80 },
			{ -320, -50, -220, 80 },
			{ 330, -60, -260, 90 },
			{ 0, -70, -420, 110 },
			{ -200, -70, 380, 100 },
		}
	do
		terrain:FillBall(Vector3.new(hill[1], hill[2], hill[3]), hill[4], Enum.Material.Grass)
	end
	-- dirt road through the middle of the battlefield
	terrain:FillBlock(CFrame.new(0, -2, 0), Vector3.new(12, 4, 560), Enum.Material.Ground)
	terrain:FillBlock(
		CFrame.new(-60, -2, -45) * CFrame.Angles(0, math.rad(-62), 0),
		Vector3.new(10, 4, 130),
		Enum.Material.Ground
	)

	local zones = {
		{ name = "Plains", position = Vector3.new(0, 0, -20), radius = 32, bonus = "Reinforcements", order = 1 },
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
			Size = Vector3.new(260, 0.4, 60),
			Position = Vector3.new(0, y + 0.1, z),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.9,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = folder,
		})
		CollectionService:AddTag(part, tag)
	end
	deploy(MapService.TAG_PLAYER_DEPLOY, 230, Color3.fromRGB(45, 95, 215))
	deploy(MapService.TAG_ENEMY_DEPLOY, -230, Color3.fromRGB(205, 45, 45))

	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = folder

	-- Village: houses around a small square, with a well
	local village = zones[2].position
	for _, spot in
		{
			{ -16, -14, 0.3 },
			{ 15, -17, -0.2 },
			{ -18, 15, math.pi + 0.2 },
			{ 17, 14, math.pi - 0.3 },
			{ -30, 0, math.pi / 2 },
		}
	do
		house(scenery, village + Vector3.new(spot[1], 0, spot[2]), spot[3])
	end
	local wellY = MapService.groundY(village.X, village.Z)
	newPart(scenery, {
		Name = "Well",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.5, 4, 4),
		CFrame = CFrame.new(village.X, wellY + 1.25, village.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(130, 125, 115),
		Material = Enum.Material.Cobblestone,
	})

	-- Low stone walls: cover lines in front of the Plains
	stoneWall(scenery, Vector3.new(-50, 0, 25), Vector3.new(-18, 0, 28))
	stoneWall(scenery, Vector3.new(18, 0, 28), Vector3.new(50, 0, 25))
	stoneWall(scenery, Vector3.new(-45, 0, -70), Vector3.new(-10, 0, -75))

	-- Battle-line props: rocks, bushes and broken fences between the two armies
	local function rock(position: Vector3)
		local y = MapService.groundY(position.X, position.Z)
		local size = rng:NextNumber(1.5, 4)
		newPart(scenery, {
			Name = "Rock",
			Size = Vector3.new(size * rng:NextNumber(1, 1.6), size * 0.7, size),
			CFrame = CFrame.new(position.X, y + size * 0.25, position.Z)
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
			Color = Color3.fromRGB(125, 122, 115):Lerp(Color3.fromRGB(95, 92, 88), rng:NextNumber()),
			Material = Enum.Material.Slate,
		})
	end
	local function bush(position: Vector3)
		local y = MapService.groundY(position.X, position.Z)
		local size = rng:NextNumber(2.5, 4.5)
		newPart(scenery, {
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			Position = Vector3.new(position.X, y + size * 0.3, position.Z),
			Color = Color3.fromRGB(60, 110, 45):Lerp(Color3.fromRGB(90, 130, 50), rng:NextNumber()),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
	local function fence(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local posts = math.max(2, math.floor(length / 6))
		for i = 0, posts do
			if rng:NextNumber() < 0.8 then -- some posts are missing
				local p = from:Lerp(to, i / posts)
				local y = MapService.groundY(p.X, p.Z)
				newPart(scenery, {
					Name = "FencePost",
					Size = Vector3.new(0.5, 3.2, 0.5),
					CFrame = CFrame.new(p.X, y + 1.5, p.Z)
						* CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12)),
					Color = Color3.fromRGB(105, 75, 45),
					Material = Enum.Material.Wood,
				})
			end
		end
		for _, height in { 1.2, 2.4 } do
			local mid = (from + to) / 2
			local y = MapService.groundY(mid.X, mid.Z)
			newPart(scenery, {
				Name = "FenceRail",
				Size = Vector3.new(0.25, 0.35, length),
				CFrame = CFrame.lookAt(Vector3.new(mid.X, y + height, mid.Z), Vector3.new(to.X, y + height, to.Z)),
				Color = Color3.fromRGB(120, 88, 55),
				Material = Enum.Material.WoodPlanks,
			})
		end
	end
	for _ = 1, 45 do
		rock(Vector3.new(rng:NextNumber(-170, 170), 0, rng:NextNumber(-200, 200)))
	end
	for _ = 1, 40 do
		bush(Vector3.new(rng:NextNumber(-170, 170), 0, rng:NextNumber(-200, 200)))
	end
	fence(Vector3.new(-160, 0, 110), Vector3.new(-80, 0, 100))
	fence(Vector3.new(80, 0, 100), Vector3.new(160, 0, 110))
	fence(Vector3.new(-150, 0, -140), Vector3.new(-90, 0, -150))
	fence(Vector3.new(90, 0, -150), Vector3.new(150, 0, -140))

	-- Woods on the flanks (kept away from the lanes between the zones)
	for _ = 1, 70 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = side * rng:NextNumber(175, 420)
		local z = rng:NextNumber(-420, 420)
		tree(scenery, Vector3.new(x, 0, z))
	end
	for _ = 1, 12 do
		tree(scenery, Vector3.new(rng:NextNumber(-60, 60) - 140, 0, rng:NextNumber(-150, -110)))
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
): { { position: Vector3, yaw: number, row: number, lateral: number } }
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
		local p = center + right * lateral + back * (row * 30)
		table.insert(spots, {
			position = Vector3.new(p.X, MapService.groundY(p.X, p.Z), p.Z),
			yaw = yaw,
			row = row,
			lateral = lateral, -- distance from the middle of the line (for sorting)
		})
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

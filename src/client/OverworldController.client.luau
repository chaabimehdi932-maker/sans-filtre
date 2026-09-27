--[[
	OverworldController
	The campaign map (view "Overworld"), Bannerlord style: rolling terrain with a coast, lakes,
	a river and snowy mountains (client-side Terrain, far from the battlefield), roads, forests,
	towns / castles / bandit camps under big faction banners, and every party marching on it.
	It has its own top-down camera, distinct from the battle camera.

	Controls: left click the ground or a banner to march · Wheel zoom · Right-drag rotate ·
	WASD / arrows pan · Space recentre on your army.
	The panels (top bar, time controls, contracts, company) are UI/CampaignPanels.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CampaignConfig = require(Modules:WaitForChild("CampaignConfig"))

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local terrain = Workspace.Terrain

-- The map lives far away from the battlefield; 1 map unit = 1 stud
local ORIGIN = Vector3.new(0, 0, -9000)
local SIZE = CampaignConfig.MapSize
local HALF = SIZE / 2
local FLAT = 4 -- height of towns, castles and roads

---------------------------------------------------------------------------
-- Height map (deterministic: the same for everyone)
---------------------------------------------------------------------------

local function riverX(z: number): number
	return 430 + math.sin(z / 95) * 38 + math.sin(z / 37) * 12
end

local LAKES = { { x = 625, z = 470, r = 34 }, { x = 280, z = 450, r = 26 }, { x = 760, z = 200, r = 40 } }

local function smoothstep(a: number, b: number, t: number): number
	local x = math.clamp((t - a) / (b - a), 0, 1)
	return x * x * (3 - 2 * x)
end

-- Height above sea level (sea level = 1). Below 1 = under water.
local function height(x: number, z: number): number
	local h = 5 + math.noise(x / 170, z / 170, 0.3) * 7 + math.noise(x / 55, z / 55, 1.7) * 2.5
	-- mountains along the north edge and the far east
	local north = smoothstep(860, 1000, z)
	local east = smoothstep(930, 1040, x)
	local ridge = math.max(north, east)
	h += ridge * (38 + math.noise(x / 60, z / 60, 4.2) * 18)
	-- the sea: south coast and the south-west bay
	local coast = smoothstep(90, 20, z + math.noise(x / 90, 0, 7) * 25)
	local bay = smoothstep(80, 10, x + math.noise(0, z / 70, 3) * 30) * smoothstep(520, 380, z)
	h -= math.max(coast, bay) * 16
	-- lakes
	for _, lake in LAKES do
		local d = math.sqrt((x - lake.x) ^ 2 + (z - lake.z) ^ 2)
		h -= smoothstep(lake.r + 12, lake.r * 0.4, d) * 12
	end
	-- the river
	local dr = math.abs(x - riverX(z))
	if z > 60 and z < 870 then
		h -= smoothstep(9, 3, dr) * 8
	end
	-- flat ground around places and along roads
	local flatten = 0
	for _, location in CampaignConfig.Locations do
		local d = math.sqrt((x - location.x) ^ 2 + (z - location.z) ^ 2)
		flatten = math.max(flatten, smoothstep(46, 26, d))
	end
	flatten = math.max(flatten, smoothstep(14, 6, CampaignConfig.distanceToRoad(x, z)))
	return h + (FLAT - h) * flatten
end

local function world(x: number, z: number, lift: number?): Vector3
	return ORIGIN + Vector3.new(x - HALF, math.max(1, height(x, z)) + (lift or 0), z - HALF)
end

local function toMap(position: Vector3): (number, number)
	local offset = position - ORIGIN
	return offset.X + HALF, offset.Z + HALF
end

---------------------------------------------------------------------------
-- Scenery parts
---------------------------------------------------------------------------

local folder = Instance.new("Folder")
folder.Name = "Overworld"
folder.Parent = Workspace

local rng = Random.new(1805)

local function block(props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent or folder
	return p
end

local STONE = Color3.fromRGB(150, 145, 140)
local ROOF = Color3.fromRGB(165, 70, 50)
local WOOD = Color3.fromRGB(120, 85, 55)

local function house(position: Vector3, yaw: number)
	local w, d, h = rng:NextNumber(4, 6), rng:NextNumber(5, 8), rng:NextNumber(3, 4.5)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	block({ Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, h / 2, 0), Color = Color3.fromRGB(225, 215, 190) })
	for _, side in { -1, 1 } do
		block({
			ClassName = "WedgePart",
			Size = Vector3.new(w + 0.4, 2.2, d / 2),
			CFrame = cf * CFrame.new(0, h + 1.1, side * d / 4) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			Color = ROOF,
		})
	end
end

local function buildTown(location: any)
	local center = world(location.x, location.z)
	for i = 1, 14 do
		local angle = i / 14 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = rng:NextNumber(8, 20)
		house(center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), angle)
	end
	block({ Size = Vector3.new(4, 13, 4), CFrame = CFrame.new(center + Vector3.new(0, 6.5, 0)), Color = STONE })
	-- low town wall
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * 25, 1.5, math.sin(a) * 25)
		block({
			Size = Vector3.new(1.5, 3, 13.5),
			CFrame = CFrame.lookAt(p, center + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, math.rad(90), 0),
			Color = STONE,
		})
	end
end

local function buildCastle(location: any)
	local center = world(location.x, location.z)
	local s = 16
	for i = 0, 3 do
		local cf = CFrame.new(center) * CFrame.Angles(0, i * math.pi / 2, 0)
		block({ Size = Vector3.new(s, 5, 1.5), CFrame = cf * CFrame.new(0, 2.5, s / 2), Color = STONE })
		block({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(8, 4.5, 4.5),
			CFrame = cf * CFrame.new(s / 2, 4, s / 2) * CFrame.Angles(0, 0, math.rad(90)),
			Color = STONE,
		})
	end
	block({ Size = Vector3.new(7, 11, 7), CFrame = CFrame.new(center + Vector3.new(0, 5.5, 0)), Color = STONE })
end

local function buildCamp(location: any)
	local center = world(location.x, location.z)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
		local cf = CFrame.lookAt(p, center)
		for _, side in { -1, 1 } do
			block({
				ClassName = "WedgePart",
				Size = Vector3.new(4, 3, 2),
				CFrame = cf * CFrame.new(side, 1.5, 0) * CFrame.Angles(0, math.rad(90) * side, 0),
				Color = Color3.fromRGB(125, 105, 80),
				Material = Enum.Material.Fabric,
			})
		end
	end
	block({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		CFrame = CFrame.new(center + Vector3.new(0, 1, 0)),
		Color = Color3.fromRGB(255, 130, 30),
		Material = Enum.Material.Neon,
	})
end

---------------------------------------------------------------------------
-- Terrain generation (runs once, in slices so the game never freezes)
---------------------------------------------------------------------------

local CELL = 12
local BORDER = 140
local generated = false
local generating = false

local function generate()
	if generated or generating then
		return
	end
	generating = true
	local count = 0
	for gx = -BORDER, SIZE + BORDER, CELL do
		for gz = -BORDER, SIZE + BORDER, CELL do
			local x, z = gx + CELL / 2, gz + CELL / 2
			local h = height(x, z)
			local top = math.max(h, -10)
			local material = Enum.Material.Grass
			if h < 1.6 then
				material = Enum.Material.Sand
			elseif h > 36 then
				material = Enum.Material.Snow
			elseif h > 22 then
				material = Enum.Material.Rock
			elseif math.noise(x / 80, z / 80, 9.1) > 0.25 then
				material = Enum.Material.LeafyGrass
			end
			local bottom = -20
			local base = ORIGIN + Vector3.new(x - HALF, 0, z - HALF)
			terrain:FillBlock(
				CFrame.new(base + Vector3.new(0, (bottom + top) / 2, 0)),
				Vector3.new(CELL, top - bottom, CELL),
				material
			)
			if h < 1 then
				terrain:FillBlock(
					CFrame.new(base + Vector3.new(0, (top + 1) / 2, 0)),
					Vector3.new(CELL, 1 - top, CELL),
					Enum.Material.Water
				)
			end
			count += 1
			if count % 250 == 0 then
				task.wait()
			end
		end
	end
	-- roads: a strip of packed earth
	for _, road in CampaignConfig.Roads do
		local a, b = CampaignConfig.getLocation(road[1]), CampaignConfig.getLocation(road[2])
		local pa = ORIGIN + Vector3.new(a.x - HALF, FLAT - 0.6, a.z - HALF)
		local pb = ORIGIN + Vector3.new(b.x - HALF, FLAT - 0.6, b.z - HALF)
		terrain:FillBlock(
			CFrame.lookAt((pa + pb) / 2, pb),
			Vector3.new(7, 1.6, (pb - pa).Magnitude),
			Enum.Material.Ground
		)
	end
	-- forests on the plains
	for _ = 1, 42 do
		local cx, cz = rng:NextNumber(40, 960), rng:NextNumber(60, 900)
		for _ = 1, rng:NextInteger(8, 18) do
			local x, z = cx + rng:NextNumber(-26, 26), cz + rng:NextNumber(-26, 26)
			local h = height(x, z)
			if h > 2.5 and h < 22 and CampaignConfig.distanceToRoad(x, z) > 12 then
				local near = false
				for _, location in CampaignConfig.Locations do
					if (Vector2.new(location.x, location.z) - Vector2.new(x, z)).Magnitude < 40 then
						near = true
					end
				end
				if not near then
					local size = rng:NextNumber(5, 9)
					local base = world(x, z)
					block({
						Size = Vector3.new(1, size * 0.5, 1),
						CFrame = CFrame.new(base + Vector3.new(0, size * 0.25, 0)),
						Color = WOOD,
					})
					block({
						Shape = Enum.PartType.Ball,
						Size = Vector3.one * size * 0.75,
						CFrame = CFrame.new(base + Vector3.new(0, size * 0.72, 0)),
						Color = Color3.fromRGB(45, 95 + rng:NextInteger(-15, 15), 45),
						Material = Enum.Material.Grass,
					})
				end
			end
		end
		task.wait()
	end
	for _, location in CampaignConfig.Locations do
		if location.kind == "Town" then
			buildTown(location)
		elseif location.kind == "Castle" then
			buildCastle(location)
		else
			buildCamp(location)
		end
	end
	generated = true
	generating = false
end

---------------------------------------------------------------------------
-- Banners (Bannerlord style: faction shield + name plate), clickable
---------------------------------------------------------------------------

local function factionInfo(faction: string?): any
	return faction and CampaignConfig.Factions[faction] or CampaignConfig.Factions.Bandits
end

-- A shield-shaped banner with the faction emblem. Returns the frame and a colour setter.
local function shield(parent: Instance, size: number): (Frame, (string?) -> ())
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(size, size * 1.25)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local body = Instance.new("Frame")
	body.Size = UDim2.new(1, 0, 0.78, 0)
	body.BorderSizePixel = 0
	body.ZIndex = 2
	body.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = body
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 15, 10)
	stroke.Parent = body
	-- the point at the bottom
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(0.5, 0.74)
	tip.Size = UDim2.fromOffset(size * 0.7, size * 0.7)
	tip.Rotation = 45
	tip.BorderSizePixel = 0
	tip.ZIndex = 1
	tip.Parent = holder
	local tipStroke = stroke:Clone()
	tipStroke.Parent = tip
	local emblem = Instance.new("TextLabel")
	emblem.Size = UDim2.new(1, 0, 0.8, 0)
	emblem.BackgroundTransparency = 1
	emblem.Font = Enum.Font.Fantasy
	emblem.TextScaled = true
	emblem.TextColor3 = Color3.fromRGB(255, 225, 150)
	emblem.TextStrokeTransparency = 0.4
	emblem.ZIndex = 3
	emblem.Parent = holder
	local function set(faction: string?)
		local info = factionInfo(faction)
		body.BackgroundColor3 = info.color:Lerp(Color3.new(0, 0, 0), 0.15)
		tip.BackgroundColor3 = body.BackgroundColor3
		emblem.Text = info.emblem or "⚑"
	end
	return holder, set
end

local labelGuis: { [string]: any } = {}

local function anchorPart(position: Vector3): BasePart
	return block({ Size = Vector3.one, Transparency = 1, CFrame = CFrame.new(position) })
end

local function placeBanner(location: any)
	local scale = if location.kind == "Town" then 1 elseif location.kind == "Castle" then 0.85 else 0.75
	local gui = Instance.new("BillboardGui")
	gui.Name = "Place_" .. location.id
	gui.Adornee = anchorPart(world(location.x, location.z, 26))
	gui.Size = UDim2.fromOffset(math.floor(250 * scale), math.floor(64 * scale))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 4000
	gui.Active = true
	gui.Enabled = false
	gui.Parent = playerGui
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Parent = gui
	local _, setFaction = shield(button, 46 * scale)
	local plate = Instance.new("TextLabel")
	plate.Position = UDim2.new(0, 38 * scale, 0, 8 * scale)
	plate.Size = UDim2.new(1, -40 * scale, 0, 34 * scale)
	plate.BackgroundColor3 = Color3.fromRGB(40, 34, 28)
	plate.BackgroundTransparency = 0.25
	plate.Font = Enum.Font.Fantasy
	plate.TextScaled = true
	plate.TextColor3 = Color3.fromRGB(245, 235, 215)
	plate.TextStrokeTransparency = 0.5
	plate.Text = "  " .. location.name .. "  "
	plate.Parent = button
	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 4)
	plateCorner.Parent = plate
	button.Activated:Connect(function()
		ClientActions.campaign("Travel", { location = location.id })
	end)
	setFaction(location.faction)
	labelGuis[location.id] = { gui = gui, setFaction = setFaction, plate = plate, location = location }
end

for _, location in CampaignConfig.Locations do
	placeBanner(location)
end

---------------------------------------------------------------------------
-- Parties (army icons)
---------------------------------------------------------------------------

local partyFolder = Instance.new("Folder")
partyFolder.Name = "Parties"
partyFolder.Parent = folder

-- A column of little soldiers (or a wagon) with a standard
local function partyModel(faction: string, big: boolean, kind: string): Model
	local info = factionInfo(faction)
	local color = info.color
	local model = Instance.new("Model")
	local scale = if big then 1.5 else 1
	local base = block({
		Name = "Base",
		Size = Vector3.new(6, 0.3, 6) * scale,
		CFrame = CFrame.new(),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		Parent = model,
	})
	model.PrimaryPart = base
	if kind == "Caravan" then
		block({
			Size = Vector3.new(3, 2.4, 5),
			CFrame = CFrame.new(0, 1.4, 0),
			Color = Color3.fromRGB(230, 220, 190),
			Parent = model,
		})
		block({
			Size = Vector3.new(1.4, 2, 1.4),
			CFrame = CFrame.new(0, 1, -3.4),
			Color = Color3.fromRGB(110, 80, 55),
			Parent = model,
		})
	else
		for _, offset in
			{ Vector3.new(-1.3, 0, 0.4), Vector3.new(1.3, 0, 0.4), Vector3.new(0, 0, 1.8), Vector3.new(0, 0, -1) }
		do
			block({
				Size = Vector3.new(1, 2.2, 0.9) * scale,
				CFrame = CFrame.new((offset + Vector3.new(0, 1.2, 0)) * scale),
				Color = (info.uniform and info.uniform.coat) or color,
				Parent = model,
			})
		end
	end
	block({
		Size = Vector3.new(0.3, 8, 0.3) * scale,
		CFrame = CFrame.new(Vector3.new(0, 4, -1.8) * scale),
		Color = WOOD,
		Parent = model,
	})
	block({
		Size = Vector3.new(0.15, 2.2, 3.2) * scale,
		CFrame = CFrame.new(Vector3.new(0, 6.8, -0.2) * scale),
		Color = color,
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	model.Parent = partyFolder
	return model
end

local function partyTag(model: Model, faction: string, hostile: boolean, big: boolean): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if big then 220 else 190, if big then 40 else 32)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if big then 14 else 11, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 1500
	gui.Adornee = model.PrimaryPart
	gui.Parent = model
	local _, setFaction = shield(gui, if big then 28 else 22)
	setFaction(faction)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(if big then 30 else 25, 2)
	label.Size = UDim2.new(1, if big then -30 else -25, 0, if big then 24 else 20)
	label.BackgroundColor3 = if hostile then Color3.fromRGB(90, 20, 20) else Color3.fromRGB(35, 35, 30)
	label.BackgroundTransparency = 0.3
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = if hostile then Color3.fromRGB(255, 170, 160) else Color3.fromRGB(240, 240, 230)
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label
	return label
end

local playerIcon: any = nil
local icons: { [number]: any } = {}

local destRing = block({
	Name = "Destination",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.3, 10, 10),
	Color = Color3.fromRGB(255, 215, 80),
	Material = Enum.Material.Neon,
	Transparency = 1,
})
local targetRing = block({
	Name = "ContractTarget",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.3, 44, 44),
	Color = Color3.fromRGB(255, 200, 40),
	Material = Enum.Material.Neon,
	Transparency = 1,
})
local FLAT_RING = CFrame.Angles(0, 0, math.rad(90))

local function placeModel(model: Model, position: Vector3, yaw: number)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
end

local function onTick()
	local data = ClientState.world
	if not data then
		return
	end
	local campaign = ClientState.campaign
	local faction = campaign and campaign.faction or "Francia"
	if playerIcon and playerIcon.faction ~= faction then
		playerIcon.model:Destroy()
		playerIcon = nil
	end
	if not playerIcon then
		local model = partyModel(faction, true, "Army")
		local label = partyTag(model, faction, false, true)
		label.Text = "★ " .. player.DisplayName
		label.TextColor3 = Color3.fromRGB(255, 225, 120)
		local start = world(data.x, data.z)
		playerIcon = { model = model, pos = start, target = start, faction = faction, yaw = 0 }
		placeModel(model, start, 0)
	end
	playerIcon.target = world(data.x, data.z)
	destRing.Transparency = if data.dest then 0.35 else 1
	if data.dest then
		destRing.CFrame = CFrame.new(world(data.dest.x, data.dest.z, 0.4)) * FLAT_RING
	end

	local seen = {}
	for _, party in data.parties do
		seen[party.id] = true
		local icon = icons[party.id]
		if not icon then
			local model = partyModel(party.faction, false, party.kind)
			local label = partyTag(model, party.faction, party.hostile, false)
			local start = world(party.x, party.z)
			icon = { model = model, label = label, pos = start, target = start, yaw = 0 }
			icons[party.id] = icon
			placeModel(model, start, 0)
		end
		icon.target = world(party.x, party.z)
		icon.label.Text = party.name
			.. (
				if party.strength and party.strength > 0
					then " " .. string.rep("⚔", math.min(5, party.strength))
					else ""
			)
	end
	for id, icon in icons do
		if not seen[id] then
			icon.model:Destroy()
			icons[id] = nil
		end
	end
end

local function refreshPlaces()
	local campaign = ClientState.campaign
	if not campaign or not campaign.owners then
		return
	end
	for id, entry in labelGuis do
		entry.setFaction(campaign.owners[id] or entry.location.faction)
	end
end

---------------------------------------------------------------------------
-- Camera and input
---------------------------------------------------------------------------

folder.Parent = nil -- shown only on the overworld
local active = false
local zoom = 190
local yaw = 0
local pan = Vector3.zero
local rotating = false
local warned = false

local function getControls(): any
	local ok, controls = pcall(function()
		local scripts = player:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		return if module then (require(module :: any) :: any):GetControls() else nil
	end)
	return if ok then controls else nil
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	print("[Overworld] map " .. (if on then "shown" else "hidden"))
	for _, entry in labelGuis do
		entry.gui.Enabled = on
	end
	folder.Parent = if on then Workspace else nil
	local camera = Workspace.CurrentCamera
	local controls = getControls()
	if on then
		task.spawn(generate)
		camera.CameraType = Enum.CameraType.Scriptable
		pan = Vector3.zero
		if controls then
			controls:Disable()
		end
	else
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		if controls then
			controls:Enable()
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

ClientState.Changed:Connect(function(key)
	if key == "CampaignTick" then
		local ok, err = pcall(onTick)
		if not ok and not warned then
			warned = true
			warn("[Overworld] tick error:", err)
		end
	elseif key == "Campaign" then
		pcall(refreshPlaces)
		setActive(ClientState.view() == "Overworld")
	end
end)
setActive(ClientState.view() == "Overworld")

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.FilterDescendantsInstances = { terrain }

-- map point under the screen position (terrain, or the flat ground level as a fallback)
local function pickMapPoint(screen: Vector2): (number?, number?)
	local camera = Workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 5000, raycastParams)
	local point: Vector3? = hit and hit.Position
	if not point and ray.Direction.Y < 0 then
		local t = (ORIGIN.Y + FLAT - ray.Origin.Y) / ray.Direction.Y
		point = ray.Origin + ray.Direction * t
	end
	if not point then
		return nil, nil
	end
	return toMap(point)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rotating = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	elseif gameProcessed then
		return
	elseif
		input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	then
		local x, z = pickMapPoint(Vector2.new(input.Position.X, input.Position.Y))
		if x and z then
			for _, location in CampaignConfig.Locations do
				if (Vector2.new(location.x, location.z) - Vector2.new(x, z)).Magnitude < 22 then
					ClientActions.campaign("Travel", { location = location.id })
					return
				end
			end
			ClientActions.campaign("Travel", { x = x, z = z })
		end
	elseif input.KeyCode == Enum.KeyCode.Space then
		pan = Vector3.zero
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rotating = false
		if active then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseWheel and not gameProcessed then
		zoom = math.clamp(zoom * (if input.Position.Z > 0 then 0.88 else 1.14), 50, 700)
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and rotating then
		yaw -= input.Delta.X * 0.006
	end
end)

local PAN_KEYS = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.Up] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.Down] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.Left] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.Right] = Vector3.new(1, 0, 0),
}

local pulse = 0

local function animate(dt: number)
	pulse += dt
	local alpha = math.min(1, dt * 8)
	local function step(icon: any)
		local previous = icon.pos
		icon.pos = icon.pos:Lerp(icon.target, alpha)
		local heading = icon.target - previous
		if Vector3.new(heading.X, 0, heading.Z).Magnitude > 0.02 then
			icon.yaw = math.atan2(-heading.X, -heading.Z)
		end
		placeModel(icon.model, icon.pos, icon.yaw)
	end
	if playerIcon then
		step(playerIcon)
	end
	for _, icon in icons do
		step(icon)
	end
	-- contract target ring (a place or a party)
	local campaign = ClientState.campaign
	local contract = campaign and campaign.contract
	local ringAt: Vector3? = nil
	if contract then
		local icon = contract.targetParty and icons[contract.targetParty]
		if icon then
			ringAt = icon.pos
		elseif contract.targetLocation then
			local location = CampaignConfig.getLocation(contract.targetLocation)
			if location then
				ringAt = world(location.x, location.z)
			end
		end
	end
	targetRing.Transparency = if ringAt then 0.45 + math.sin(pulse * 4) * 0.2 else 1
	if ringAt then
		targetRing.CFrame = CFrame.new(ringAt + Vector3.new(0, 0.5, 0)) * FLAT_RING
	end
end

RunService:BindToRenderStep("OverworldCamera", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if not active then
		return
	end
	local ok, err = pcall(animate, dt)
	if not ok and not warned then
		warned = true
		warn("[Overworld] animation error:", err)
	end
	-- the camera always updates, whatever else fails
	local move = Vector3.zero
	if not UserInputService:GetFocusedTextBox() then
		for key, direction in PAN_KEYS do
			if UserInputService:IsKeyDown(key) then
				move += direction
			end
		end
	end
	if move.Magnitude > 0 then
		pan += CFrame.Angles(0, yaw, 0):VectorToWorldSpace(move.Unit) * zoom * 1.2 * dt
	end
	local focus = (if playerIcon then playerIcon.pos else ORIGIN + Vector3.new(0, FLAT, 0)) + pan
	local offset = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(0, zoom, zoom * 0.7))
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(focus + offset, focus)
end)

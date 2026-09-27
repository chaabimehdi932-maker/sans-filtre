--[[
	OverworldController
	The campaign map screen (view "Overworld"): a low-poly map built on the client from
	CampaignConfig (towns, castles, bandit camps, roads, forests, hills), the moving army icons
	from CampaignService's ticks, and its own top-down camera — distinct from the battle camera.

	Controls: left click the map (or a place's name) to march there · Wheel zoom ·
	Right-drag rotate · WASD / arrows pan · Space recentre on your army.
	The panels (top bar, contracts, towns) are drawn by UI/CampaignPanels.
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

-- The map lives far away from the battlefield; 1 map unit = 1 stud
local ORIGIN = Vector3.new(0, 0, -9000)
local HALF = CampaignConfig.MapSize / 2
local GROUND_Y = 2

local function world(x: number, z: number, y: number?): Vector3
	return ORIGIN + Vector3.new(x - HALF, y or GROUND_Y, z - HALF)
end

local function toMap(position: Vector3): (number, number)
	local local_ = position - ORIGIN
	return local_.X + HALF, local_.Z + HALF
end

local folder = Instance.new("Folder")
folder.Name = "Overworld"
folder.Parent = Workspace

local rng = Random.new(1805) -- same scenery for everyone

local function block(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = props.Parent or folder
	return part
end

local function wedge(props: { [string]: any }): WedgePart
	local part = Instance.new("WedgePart")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = props.Parent or folder
	return part
end

---------------------------------------------------------------------------
-- Static map
---------------------------------------------------------------------------

local GRASS = Color3.fromRGB(106, 150, 76)
local GRASS_DARK = Color3.fromRGB(86, 128, 62)
local FIELD = Color3.fromRGB(190, 170, 95)
local ROAD = Color3.fromRGB(170, 135, 90)
local WATER = Color3.fromRGB(70, 130, 190)
local STONE = Color3.fromRGB(150, 145, 140)
local ROOF = Color3.fromRGB(165, 70, 50)
local WOOD = Color3.fromRGB(120, 85, 55)

local ground = block({
	Name = "Ground",
	Size = Vector3.new(CampaignConfig.MapSize + 200, 4, CampaignConfig.MapSize + 200),
	CFrame = CFrame.new(world(HALF, HALF, 0)),
	Color = GRASS,
	Material = Enum.Material.Grass,
	CanQuery = true,
})
ground.CanQuery = true

local function nearAnyLocation(x: number, z: number, radius: number): boolean
	for _, location in CampaignConfig.Locations do
		if (Vector2.new(location.x, location.z) - Vector2.new(x, z)).Magnitude < radius then
			return true
		end
	end
	return CampaignConfig.distanceToRoad(x, z) < 14
end

-- fields and meadows
for _ = 1, 70 do
	local x, z = rng:NextNumber(20, 980), rng:NextNumber(20, 980)
	if not nearAnyLocation(x, z, 40) then
		block({
			Size = Vector3.new(rng:NextNumber(25, 60), 0.3, rng:NextNumber(20, 45)),
			CFrame = CFrame.new(world(x, z, GROUND_Y + 0.05)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color = if rng:NextNumber() < 0.5 then FIELD else GRASS_DARK,
			Material = Enum.Material.Grass,
		})
	end
end

-- a river winding north to south
do
	local x = 430
	for z = 0, 1000, 25 do
		local nextX = x + rng:NextNumber(-18, 18)
		local a, b = world(x, z, GROUND_Y + 0.08), world(nextX, z + 25, GROUND_Y + 0.08)
		block({
			Size = Vector3.new(14, 0.3, (b - a).Magnitude + 2),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = WATER,
			Material = Enum.Material.Glass,
			Transparency = 0.1,
		})
		x = nextX
	end
end

-- hills
for _ = 1, 26 do
	local x, z = rng:NextNumber(20, 980), rng:NextNumber(20, 980)
	if not nearAnyLocation(x, z, 50) then
		local size = rng:NextNumber(30, 70)
		block({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(world(x, z, GROUND_Y - size * 0.32)),
			Color = GRASS_DARK,
			Material = Enum.Material.Grass,
		})
	end
end

-- forests
local function tree(x: number, z: number)
	local height = rng:NextNumber(5, 9)
	block({
		Size = Vector3.new(1, height * 0.5, 1),
		CFrame = CFrame.new(world(x, z, GROUND_Y + height * 0.25)),
		Color = WOOD,
	})
	block({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * height * 0.7,
		CFrame = CFrame.new(world(x, z, GROUND_Y + height * 0.7)),
		Color = Color3.fromRGB(50, 105 + rng:NextInteger(-15, 15), 50),
		Material = Enum.Material.Grass,
	})
end
for _ = 1, 22 do
	local cx, cz = rng:NextNumber(40, 960), rng:NextNumber(40, 960)
	if not nearAnyLocation(cx, cz, 45) then
		for _ = 1, rng:NextInteger(6, 14) do
			local x, z = cx + rng:NextNumber(-22, 22), cz + rng:NextNumber(-22, 22)
			if not nearAnyLocation(x, z, 25) then
				tree(x, z)
			end
		end
	end
end

-- roads
for _, road in CampaignConfig.Roads do
	local a = CampaignConfig.getLocation(road[1])
	local b = CampaignConfig.getLocation(road[2])
	local pa, pb = world(a.x, a.z, GROUND_Y + 0.12), world(b.x, b.z, GROUND_Y + 0.12)
	block({
		Name = "Road",
		Size = Vector3.new(6, 0.3, (pb - pa).Magnitude),
		CFrame = CFrame.lookAt((pa + pb) / 2, pb),
		Color = ROAD,
		Material = Enum.Material.Ground,
	})
end

-- locations
local flags: { [string]: { BasePart } } = {}

local function flag(location: any, base: Vector3, height: number)
	block({
		Size = Vector3.new(0.5, height, 0.5),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)),
		Color = WOOD,
	})
	local cloth = block({
		Size = Vector3.new(0.2, 3, 5),
		CFrame = CFrame.new(base + Vector3.new(0, height - 1.5, 2.5)),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.Fabric,
	})
	flags[location.id] = flags[location.id] or {}
	table.insert(flags[location.id], cloth)
end

local function house(position: Vector3, yaw: number)
	local w, d, h = rng:NextNumber(4, 6), rng:NextNumber(5, 8), rng:NextNumber(3, 4.5)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	block({ Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, h / 2, 0), Color = Color3.fromRGB(225, 215, 190) })
	for _, side in { -1, 1 } do
		wedge({
			Size = Vector3.new(d, 2.2, w / 2),
			CFrame = cf * CFrame.new(side * w / 4, h + 1.1, 0) * CFrame.Angles(0, math.rad(90) * side, 0),
			Color = ROOF,
		})
	end
end

local function buildTown(location: any)
	local center = world(location.x, location.z)
	for i = 1, 9 do
		local angle = i / 9 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = rng:NextNumber(7, 16)
		house(center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), angle)
	end
	-- church
	block({ Size = Vector3.new(4, 12, 4), CFrame = CFrame.new(center + Vector3.new(0, 6, 0)), Color = STONE })
	wedge({
		Size = Vector3.new(4, 4, 2),
		CFrame = CFrame.new(center + Vector3.new(0, 14, 1)),
		Color = ROOF,
	})
	wedge({
		Size = Vector3.new(4, 4, 2),
		CFrame = CFrame.new(center + Vector3.new(0, 14, -1)) * CFrame.Angles(0, math.pi, 0),
		Color = ROOF,
	})
	flag(location, center + Vector3.new(3, 0, 3), 16)
end

local function buildCastle(location: any)
	local center = world(location.x, location.z)
	local size = 16
	for i = 0, 3 do
		local angle = i * math.pi / 2
		local cf = CFrame.new(center) * CFrame.Angles(0, angle, 0)
		block({ Size = Vector3.new(size, 5, 1.5), CFrame = cf * CFrame.new(0, 2.5, size / 2), Color = STONE })
		block({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(8, 4, 4),
			CFrame = cf * CFrame.new(size / 2, 4, size / 2) * CFrame.Angles(0, 0, math.rad(90)),
			Color = STONE,
		})
	end
	block({ Size = Vector3.new(7, 10, 7), CFrame = CFrame.new(center + Vector3.new(0, 5, 0)), Color = STONE })
	flag(location, center + Vector3.new(0, 10, 0), 7)
end

local function buildCamp(location: any)
	local center = world(location.x, location.z)
	for i = 1, 5 do
		local angle = i / 5 * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle) * 8, 0, math.sin(angle) * 8)
		local cf = CFrame.lookAt(pos, center)
		for _, side in { -1, 1 } do
			wedge({
				Size = Vector3.new(4, 3, 2),
				CFrame = cf * CFrame.new(side * 1, 1.5, 0) * CFrame.Angles(0, math.rad(90) * side, 0),
				Color = Color3.fromRGB(125, 105, 80),
				Material = Enum.Material.Fabric,
			})
		end
	end
	block({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(center + Vector3.new(0, 1, 0)),
		Color = Color3.fromRGB(255, 130, 30),
		Material = Enum.Material.Neon,
	})
	flag(location, center + Vector3.new(4, 0, -4), 9)
end

local labelGuis: { [string]: any } = {}

local function locationLabel(location: any)
	local anchor = block({
		Name = location.id,
		Size = Vector3.one,
		Transparency = 1,
		CFrame = CFrame.new(world(location.x, location.z, GROUND_Y + 22)),
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "Place_" .. location.id
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(190, 46)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 2000
	gui.Active = true
	gui.Enabled = false
	gui.Parent = playerGui
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = true
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 17
	button.TextColor3 = Color3.new(1, 1, 1)
	button.RichText = true
	button.Text = location.name
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	button.Activated:Connect(function()
		ClientActions.campaign("Travel", { location = location.id })
	end)
	labelGuis[location.id] = { gui = gui, button = button, stroke = stroke, location = location }
end

for _, location in CampaignConfig.Locations do
	if location.kind == "Town" then
		buildTown(location)
	elseif location.kind == "Castle" then
		buildCastle(location)
	else
		buildCamp(location)
	end
	locationLabel(location)
end

---------------------------------------------------------------------------
-- Parties (army icons)
---------------------------------------------------------------------------

local partyFolder = Instance.new("Folder")
partyFolder.Name = "Parties"
partyFolder.Parent = folder

local function factionColor(faction: string): Color3
	local info = CampaignConfig.Factions[faction]
	return if info then info.color else Color3.new(1, 1, 1)
end

-- A little column of soldiers under a banner
local function partyModel(color: Color3, big: boolean, kind: string): any
	local model = Instance.new("Model")
	local scale = if big then 1.4 else 1
	local base = block({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 7 * scale, 7 * scale),
		CFrame = CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		Parent = model,
	})
	model.PrimaryPart = base
	local offsets = if kind == "Caravan"
		then { Vector3.new(0, 1.2, 0) }
		else { Vector3.new(-1.3, 1.3, 0), Vector3.new(1.3, 1.3, 0), Vector3.new(0, 1.3, 1.4) }
	for _, offset in offsets do
		if kind == "Caravan" then
			block({
				Size = Vector3.new(3, 2.4, 5),
				CFrame = CFrame.new(offset * scale),
				Color = Color3.fromRGB(230, 220, 190),
				Parent = model,
			})
		else
			block({
				Size = Vector3.new(1.2, 2.4, 1) * scale,
				CFrame = CFrame.new(offset * scale),
				Color = color:Lerp(Color3.new(0, 0, 0), 0.25),
				Parent = model,
			})
		end
	end
	block({
		Size = Vector3.new(0.3, 7, 0.3) * scale,
		CFrame = CFrame.new(Vector3.new(0, 3.5, -1.5) * scale),
		Color = WOOD,
		Parent = model,
	})
	block({
		Size = Vector3.new(0.15, 1.8, 2.8) * scale,
		CFrame = CFrame.new(Vector3.new(0, 6, -0.1) * scale),
		Color = color,
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	model.Parent = partyFolder
	return model
end

local function nameTag(model: Model, textColor: Color3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 22)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = model.PrimaryPart
	gui.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 15
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	return label
end

local playerIcon: any = nil
local playerPos: Vector3? = nil
local icons: { [number]: any } = {}

local destRing = block({
	Name = "Destination",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.3, 9, 9),
	Color = Color3.fromRGB(255, 215, 80),
	Material = Enum.Material.Neon,
	Transparency = 1,
})
local targetRing = block({
	Name = "ContractTarget",
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.3, 40, 40),
	Color = Color3.fromRGB(255, 200, 40),
	Material = Enum.Material.Neon,
	Transparency = 1,
})

local function moveModel(model: Model, position: Vector3, yaw: number?)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0) * CFrame.Angles(0, 0, math.rad(90)))
end

local function onTick()
	local data = ClientState.world
	if not data then
		return
	end
	local campaign = ClientState.campaign
	local faction = campaign and campaign.faction or "Francia"
	if not playerIcon then
		local model = partyModel(factionColor(faction), true, "Army")
		playerIcon = { model = model, target = world(data.x, data.z), faction = faction }
		nameTag(model, Color3.fromRGB(255, 225, 120)).Text = "★ " .. player.DisplayName .. "'s company"
		moveModel(model, playerIcon.target)
	end
	playerIcon.target = world(data.x, data.z)
	playerPos = playerPos or playerIcon.target
	destRing.Transparency = if data.dest then 0.35 else 1
	if data.dest then
		destRing.CFrame = CFrame.new(world(data.dest.x, data.dest.z, GROUND_Y + 0.3))
			* CFrame.Angles(0, 0, math.rad(90))
	end

	local seen = {}
	for _, party in data.parties do
		seen[party.id] = true
		local icon = icons[party.id]
		if not icon then
			local model = partyModel(factionColor(party.faction), false, party.kind)
			local label = nameTag(model, if party.hostile then Color3.fromRGB(255, 120, 110) else Color3.new(1, 1, 1))
			icon = { model = model, label = label, pos = world(party.x, party.z) }
			icons[party.id] = icon
			moveModel(model, icon.pos)
		end
		icon.target = world(party.x, party.z)
		icon.label.Text = party.name
			.. (
				if party.strength and party.strength > 0
					then "  " .. string.rep("⚔", math.min(5, party.strength))
					else ""
			)
		icon.contract = party.contract
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
	for id, cloths in flags do
		local color = factionColor(campaign.owners[id] or "Bandits")
		for _, cloth in cloths do
			cloth.Color = color
		end
	end
	for id, entry in labelGuis do
		local owner = campaign.owners[id] or entry.location.faction
		local ownerInfo = CampaignConfig.Factions[owner]
		local kind = if entry.location.kind == "BanditCamp" then "Bandit camp" else entry.location.kind
		entry.button.Text = string.format(
			'%s\n<font size="12" color="#C8C8D2">%s · %s</font>',
			entry.location.name,
			kind,
			if ownerInfo then ownerInfo.short else owner
		)
		entry.stroke.Color = factionColor(owner)
	end
	-- if the faction changed (new campaign), rebuild the player's icon
	if playerIcon and playerIcon.faction ~= campaign.faction then
		playerIcon.model:Destroy()
		playerIcon = nil
	end
end

---------------------------------------------------------------------------
-- Camera and input
---------------------------------------------------------------------------

folder.Parent = nil -- shown only on the overworld
local active = false
local zoom = 170
local yaw = 0
local pan = Vector3.zero
local rotating = false
local controls: any = nil
pcall(function()
	controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any):GetControls()
end)

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	for _, entry in labelGuis do
		entry.gui.Enabled = on
	end
	folder.Parent = if on then Workspace else nil
	local camera = Workspace.CurrentCamera
	if on then
		camera.CameraType = Enum.CameraType.Scriptable
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

local function refreshActive()
	setActive(ClientState.view() == "Overworld")
end

ClientState.Changed:Connect(function(key)
	if key == "CampaignTick" then
		onTick()
	elseif key == "Campaign" then
		refreshPlaces()
		refreshActive()
		onTick()
	end
end)
refreshActive()

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.FilterDescendantsInstances = { ground }

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
		local camera = Workspace.CurrentCamera
		local ray = camera:ViewportPointToRay(input.Position.X, input.Position.Y)
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 3000, raycastParams)
		if hit then
			local x, z = toMap(hit.Position)
			-- snap to a place when clicking next to it
			for _, location in CampaignConfig.Locations do
				if (Vector2.new(location.x, location.z) - Vector2.new(x, z)).Magnitude < 16 then
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
		zoom = math.clamp(zoom * (if input.Position.Z > 0 then 0.88 else 1.14), 50, 520)
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
RunService:BindToRenderStep("OverworldCamera", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if not active then
		return
	end
	pulse += dt
	-- smooth icons
	local alpha = math.min(1, dt * 8)
	if playerIcon then
		playerPos = (playerPos or playerIcon.target):Lerp(playerIcon.target, alpha)
		local heading = playerIcon.target - (playerPos :: Vector3)
		local iconYaw = if heading.Magnitude > 0.05 then math.atan2(-heading.X, -heading.Z) else playerIcon.yaw
		playerIcon.yaw = iconYaw
		moveModel(playerIcon.model, playerPos :: Vector3, iconYaw)
	end
	for _, icon in icons do
		if icon.target then
			icon.pos = icon.pos:Lerp(icon.target, alpha)
			moveModel(icon.model, icon.pos)
		end
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
			for _, location in CampaignConfig.Locations do
				if location.id == contract.targetLocation then
					ringAt = world(location.x, location.z)
				end
			end
		end
	end
	targetRing.Transparency = if ringAt then 0.45 + math.sin(pulse * 4) * 0.2 else 1
	if ringAt then
		targetRing.CFrame = CFrame.new(ringAt.X, ORIGIN.Y + GROUND_Y + 0.25, ringAt.Z)
			* CFrame.Angles(0, 0, math.rad(90))
	end

	-- camera: follows your army, WASD pans, wheel zooms, right-drag rotates
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
	local focus = (playerPos or world(HALF, HALF)) + pan
	local offset = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(0, zoom, zoom * 0.75))
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(focus + offset, focus)
end)

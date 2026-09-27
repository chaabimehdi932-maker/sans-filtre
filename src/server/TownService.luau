--[[
	TownService
	A walkable town (built once, far from the battlefield) that your commander visits on foot
	when you "Enter town" at one of your employer's towns. People to talk to (ProximityPrompt
	"Talk", key E) — the conversation itself is client UI (UI/CampaignPanels), every deal is
	a CampaignAction the server validates:
	  Guildmaster   (town hall steps)   contracts: the quest board
	  Recruiter     (barracks yard)     hire fresh squads
	  Quartermaster (barracks yard)     replenish casualties
	  MercCaptain   (tavern terrace)    veteran free companies (already ★ / ★★)
	  Innkeeper     (tavern terrace)    rumours: where the bandits and your bounty are
	  ArmsMerchant  (market)            new kit and drill: gold → squad XP
	  Gate          (south gate)        back to the map
	Prompts carry the attribute "Role"; the NPC model carries "DisplayName".
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local TownService = {}

local ORIGIN = Vector3.new(3000, 0, 9000)
TownService.Origin = ORIGIN
TownService.SpawnCFrame = CFrame.lookAt(ORIGIN + Vector3.new(0, 5, 78), ORIGIN + Vector3.new(0, 5, 0))

local folder = Instance.new("Folder")
folder.Name = "Town"
folder.Parent = Workspace

local rng = Random.new(1789)

local function part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
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

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(ORIGIN + Vector3.new(x, y, z))
end

local STONE = Color3.fromRGB(160, 155, 145)
local DARK_STONE = Color3.fromRGB(115, 110, 105)
local PLASTER = Color3.fromRGB(232, 220, 195)
local TIMBER = Color3.fromRGB(95, 65, 40)
local ROOF = Color3.fromRGB(160, 65, 45)
local SLATE = Color3.fromRGB(70, 75, 90)

---------------------------------------------------------------------------
-- Ground, walls, gate
---------------------------------------------------------------------------

part({
	Name = "Grass",
	Size = Vector3.new(420, 2, 420),
	CFrame = at(0, -1, 0),
	Color = Color3.fromRGB(96, 140, 70),
	Material = Enum.Material.Grass,
})
part({
	Name = "Cobbles",
	Size = Vector3.new(196, 0.4, 196),
	CFrame = at(0, 0.2, 0),
	Color = Color3.fromRGB(150, 140, 125),
	Material = Enum.Material.Cobblestone,
})

local WALL = 100
for _, side in { { 0, -1 }, { -1, 0 }, { 1, 0 } } do
	part({
		Size = if side[1] == 0 then Vector3.new(WALL * 2 + 8, 18, 4) else Vector3.new(4, 18, WALL * 2 + 8),
		CFrame = at(side[1] * WALL, 9, side[2] * WALL),
		Color = STONE,
		Material = Enum.Material.Slate,
	})
end
-- south wall with the gate gap
for _, x in { -58, 58 } do
	part({
		Size = Vector3.new(92, 18, 4),
		CFrame = at(x, 9, WALL),
		Color = STONE,
		Material = Enum.Material.Slate,
	})
end
part({ Size = Vector3.new(28, 6, 5), CFrame = at(0, 15, WALL), Color = DARK_STONE, Material = Enum.Material.Slate })
for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { -0.14, 1 }, { 0.14, 1 } } do
	part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(26, 12, 12),
		CFrame = at(corner[1] * WALL, 13, corner[2] * WALL) * CFrame.Angles(0, 0, math.rad(90)),
		Color = DARK_STONE,
		Material = Enum.Material.Slate,
	})
end

---------------------------------------------------------------------------
-- Buildings
---------------------------------------------------------------------------

local function sign(host: BasePart, face: Enum.NormalId, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0.3
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(60, 40, 25)
	label.TextColor3 = Color3.fromRGB(255, 225, 150)
	label.Font = Enum.Font.Fantasy
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
end

-- A house: plastered walls, timber frame, pitched roof. Door faces `facing` (+Z local).
local function building(
	cf: CFrame,
	width: number,
	depth: number,
	height: number,
	roof: Color3,
	signText: string?
): BasePart
	local body = part({
		Size = Vector3.new(width, height, depth),
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Color = PLASTER,
	})
	for _, x in { -width / 2, width / 2 } do
		part({
			Size = Vector3.new(0.8, height, 0.8),
			CFrame = cf * CFrame.new(x, height / 2, depth / 2),
			Color = TIMBER,
		})
	end
	part({
		Size = Vector3.new(width + 0.4, 0.8, 0.8),
		CFrame = cf * CFrame.new(0, height * 0.55, depth / 2),
		Color = TIMBER,
	})
	-- door
	part({
		Size = Vector3.new(4, 6.5, 0.4),
		CFrame = cf * CFrame.new(0, 3.25, depth / 2 + 0.1),
		Color = TIMBER,
		Material = Enum.Material.Wood,
	})
	-- roof: two wedges
	for _, side in { -1, 1 } do
		part({
			ClassName = "WedgePart",
			Size = Vector3.new(width + 1, height * 0.45, depth / 2 + 0.6),
			CFrame = cf
				* CFrame.new(0, height + height * 0.225, side * (depth / 4 + 0.3))
				* CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			Color = roof,
		})
	end
	if signText then
		local board = part({
			Size = Vector3.new(math.min(width - 2, 16), 2.4, 0.3),
			CFrame = cf * CFrame.new(0, 8.2, depth / 2 + 0.3),
			Color = TIMBER,
		})
		sign(board, Enum.NormalId.Front, signText)
	end
	return body
end

-- Town hall (north), tavern (east), barracks (west)
local hall = building(at(0, 0, -64), 44, 22, 18, SLATE, "TOWN HALL · CONTRACTS")
part({ Size = Vector3.new(26, 1.2, 8), CFrame = at(0, 0.6, -49), Color = STONE, Material = Enum.Material.Slate })
part({ Size = Vector3.new(26, 0.6, 4), CFrame = at(0, 1.5, -51), Color = STONE, Material = Enum.Material.Slate })
part({ Size = Vector3.new(0.6, 16, 0.6), CFrame = at(0, 30, -64), Color = TIMBER })
part({
	Name = "HallFlag",
	Size = Vector3.new(0.2, 4, 7),
	CFrame = at(0, 36, -60.5),
	Color = Color3.fromRGB(45, 95, 215),
	Material = Enum.Material.Fabric,
})
hall.Name = "TownHall"

building(at(64, 0, -8) * CFrame.Angles(0, math.rad(-90), 0), 30, 22, 14, ROOF, "THE DRUNKEN GRENADIER").Name = "Tavern"
-- tavern terrace: tables and benches
for i, z in { -18, -2, 12 } do
	local table_ = part({
		Size = Vector3.new(6, 0.5, 3),
		CFrame = at(42, 3, z),
		Color = TIMBER,
		Material = Enum.Material.Wood,
	})
	table_.Name = "Table" .. i
	for _, dx in { -2.6, 2.6 } do
		part({
			Size = Vector3.new(1.2, 1.8, 3.4),
			CFrame = at(42 + dx, 0.9, z),
			Color = TIMBER,
			Material = Enum.Material.Wood,
		})
	end
	part({ Size = Vector3.new(0.6, 3, 0.6), CFrame = at(42, 1.5, z), Color = TIMBER })
end

building(at(-64, 0, -6) * CFrame.Angles(0, math.rad(90), 0), 40, 18, 12, SLATE, "BARRACKS · RECRUITS").Name =
	"Barracks"
-- training yard: fence posts and dummies
for i = -3, 3 do
	part({ Size = Vector3.new(0.6, 3, 0.6), CFrame = at(-38, 1.5, i * 8), Color = TIMBER })
end
for _, z in { -12, 0, 12 } do
	part({ Size = Vector3.new(0.6, 5, 0.6), CFrame = at(-48, 2.5, z), Color = TIMBER })
	part({ Size = Vector3.new(3, 0.6, 0.6), CFrame = at(-48, 4, z), Color = TIMBER })
	part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = at(-48, 5.6, z),
		Color = Color3.fromRGB(200, 180, 130),
		Material = Enum.Material.Fabric,
	})
end
-- musket rack
part({ Size = Vector3.new(8, 3, 1), CFrame = at(-54, 1.5, 22), Color = TIMBER, Material = Enum.Material.Wood })

-- market square: stalls with coloured awnings around a well
local AWNINGS = {
	Color3.fromRGB(200, 60, 50),
	Color3.fromRGB(60, 120, 200),
	Color3.fromRGB(230, 180, 50),
	Color3.fromRGB(70, 160, 90),
	Color3.fromRGB(170, 80, 170),
	Color3.fromRGB(230, 120, 40),
}
local stalls = {}
for i = 1, 6 do
	local angle = (i - 0.5) / 6 * math.pi * 2
	local pos = Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24 + 10)
	local cf = CFrame.lookAt(ORIGIN + pos, ORIGIN + Vector3.new(0, 0, 10))
	part({
		Size = Vector3.new(8, 3, 3),
		CFrame = cf * CFrame.new(0, 1.5, 0),
		Color = TIMBER,
		Material = Enum.Material.Wood,
	})
	for _, x in { -3.8, 3.8 } do
		for _, z in { -1.4, 1.4 } do
			part({ Size = Vector3.new(0.4, 7, 0.4), CFrame = cf * CFrame.new(x, 3.5, z), Color = TIMBER })
		end
	end
	part({
		ClassName = "WedgePart",
		Size = Vector3.new(9, 1.5, 4.5),
		CFrame = cf * CFrame.new(0, 7.6, 0) * CFrame.Angles(0, math.pi, 0),
		Color = AWNINGS[i],
		Material = Enum.Material.Fabric,
	})
	-- goods
	for j = 1, 3 do
		part({
			Size = Vector3.new(1.4, 1.2, 1.4),
			CFrame = cf * CFrame.new(-2.4 + j * 1.6, 3.6, 0),
			Color = AWNINGS[(i + j) % #AWNINGS + 1],
		})
	end
	table.insert(stalls, cf)
end
part({
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(3, 8, 8),
	CFrame = at(0, 1.5, 10) * CFrame.Angles(0, 0, math.rad(90)),
	Color = STONE,
	Material = Enum.Material.Slate,
})
part({
	Shape = Enum.PartType.Cylinder,
	Size = Vector3.new(0.3, 6.5, 6.5),
	CFrame = at(0, 2.9, 10) * CFrame.Angles(0, 0, math.rad(90)),
	Color = Color3.fromRGB(70, 130, 190),
	Material = Enum.Material.Glass,
	Transparency = 0.2,
})
local marketSign = part({ Size = Vector3.new(10, 2.4, 0.3), CFrame = at(0, 9, 10), Color = TIMBER })
sign(marketSign, Enum.NormalId.Front, "MARKET")
sign(marketSign, Enum.NormalId.Back, "MARKET")
part({ Size = Vector3.new(0.5, 9, 0.5), CFrame = at(0, 4.5, 10), Color = TIMBER })

-- houses along the walls
local spots = {}
for x = -80, 80, 20 do
	table.insert(spots, { x, -88, 0 })
end
for z = -60, 70, 22 do
	table.insert(spots, { -88, z, math.rad(90) })
	table.insert(spots, { 88, z, math.rad(-90) })
end
for x = -80, 80, 22 do
	if math.abs(x) > 24 then
		table.insert(spots, { x, 84, math.pi })
	end
end
for _, spot in spots do
	local x, z = spot[1], spot[2]
	local blocked = (math.abs(x) < 30 and z < -50) or (x > 50 and math.abs(z) < 30) or (x < -50 and math.abs(z) < 30)
	if not blocked then
		building(
			at(x, 0, z) * CFrame.Angles(0, spot[3], 0),
			rng:NextNumber(12, 16),
			rng:NextNumber(10, 13),
			rng:NextNumber(9, 13),
			if rng:NextNumber() < 0.6 then ROOF else SLATE,
			nil
		)
	end
end

-- lamp posts
for _, pos in { { -14, 60 }, { 14, 60 }, { -14, 30 }, { 14, 30 }, { -30, -30 }, { 30, -30 } } do
	part({ Size = Vector3.new(0.5, 10, 0.5), CFrame = at(pos[1], 5, pos[2]), Color = Color3.fromRGB(35, 35, 40) })
	local lamp = part({
		Size = Vector3.new(1.2, 1.4, 1.2),
		CFrame = at(pos[1], 10.4, pos[2]),
		Color = Color3.fromRGB(255, 210, 120),
		Material = Enum.Material.Neon,
	})
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Parent = lamp
end

---------------------------------------------------------------------------
-- People
---------------------------------------------------------------------------

local NPCS = {
	{
		role = "Guildmaster",
		name = "Master Aubert",
		title = "Guild of Contracts",
		pos = Vector3.new(0, 0, -44),
		coat = Color3.fromRGB(70, 40, 90),
		hat = Color3.fromRGB(20, 20, 20),
	},
	{
		role = "Recruiter",
		name = "Sergeant Dubois",
		title = "Recruiter",
		pos = Vector3.new(-40, 0, -4),
		coat = Color3.fromRGB(34, 54, 140),
		hat = Color3.fromRGB(20, 20, 20),
	},
	{
		role = "Quartermaster",
		name = "Quartermaster Lenoir",
		title = "Replenish casualties",
		pos = Vector3.new(-40, 0, 16),
		coat = Color3.fromRGB(110, 90, 60),
		hat = Color3.fromRGB(60, 45, 30),
	},
	{
		role = "MercCaptain",
		name = "Captain Varga",
		title = "Free company for hire",
		pos = Vector3.new(38, 0, -2),
		coat = Color3.fromRGB(120, 30, 35),
		hat = Color3.fromRGB(30, 30, 30),
	},
	{
		role = "Innkeeper",
		name = "Old Marcel",
		title = "Innkeeper · rumours",
		pos = Vector3.new(46, 0, 18),
		coat = Color3.fromRGB(235, 230, 220),
		hat = Color3.fromRGB(235, 230, 220),
	},
	{
		role = "ArmsMerchant",
		name = "Madame Rosalie",
		title = "Arms merchant · drill",
		pos = Vector3.new(0, 0, 30),
		coat = Color3.fromRGB(60, 110, 70),
		hat = Color3.fromRGB(150, 40, 40),
	},
	{
		role = "Gate",
		name = "Gate guard",
		title = "Back to the map",
		pos = Vector3.new(10, 0, 94),
		coat = Color3.fromRGB(34, 54, 140),
		hat = Color3.fromRGB(20, 20, 20),
	},
}

local SKIN = Color3.fromRGB(234, 184, 146)

-- An R6 townsperson (proper humanoid body when possible, simple blocks otherwise)
local function makeNpc(info: any): Model
	local model: Model
	local ok, result = pcall(function()
		local description = Instance.new("HumanoidDescription")
		description.HeadColor = SKIN
		description.TorsoColor = info.coat
		description.LeftArmColor = info.coat
		description.RightArmColor = info.coat
		description.LeftLegColor = Color3.fromRGB(230, 230, 222)
		description.RightLegColor = Color3.fromRGB(230, 230, 222)
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if ok and result then
		model = result
	else
		model = Instance.new("Model")
		local root = part({ Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), Transparency = 1, Parent = model })
		part({ Name = "Torso", Size = Vector3.new(2, 2, 1), CFrame = root.CFrame, Color = info.coat, Parent = model })
		part({
			Name = "Head",
			Size = Vector3.new(2, 1, 1),
			CFrame = root.CFrame * CFrame.new(0, 1.5, 0),
			Color = SKIN,
			Parent = model,
		})
		model.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
	end
	model.Name = info.name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart?
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Anchored = true
		end
	end
	model.Parent = folder
	-- face the square
	local position = ORIGIN + info.pos + Vector3.new(0, 3, 0)
	local lookAt = ORIGIN + Vector3.new(0, 3, 10)
	if (lookAt - position).Magnitude < 1 then
		lookAt = position + Vector3.new(0, 0, 1)
	end
	model:PivotTo(CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
	-- hat (a shako/tricorne-ish block) so roles are recognisable
	if head then
		local hat = part({
			Name = "Hat",
			Size = Vector3.new(1.3, 0.9, 1.3),
			CFrame = head.CFrame * CFrame.new(0, 0.9, 0),
			Color = info.hat,
			Parent = model,
		})
		hat.CanCollide = false
	end
	-- name tag
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 60
	gui.Adornee = root
	gui.Parent = root
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = info.name
	nameLabel.Parent = gui
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Position = UDim2.fromScale(0, 0.55)
	titleLabel.Size = UDim2.new(1, 0, 0.45, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextStrokeTransparency = 0.3
	titleLabel.Text = info.title
	titleLabel.Parent = gui
	-- the "Talk" prompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if info.role == "Gate" then "Leave town" else "Talk"
	prompt.ObjectText = info.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Role", info.role)
	prompt.Parent = root
	model:SetAttribute("Role", info.role)
	model:SetAttribute("DisplayName", info.name)
	return model
end

for _, info in NPCS do
	local ok, err = pcall(makeNpc, info)
	if not ok then
		warn("TownService: could not create", info.name, err)
	end
end

-- Recolour the town-hall flag for the town being visited (cosmetic, shared by visitors)
function TownService.setFlagColor(color: Color3)
	local flag = folder:FindFirstChild("HallFlag")
	if flag and flag:IsA("BasePart") then
		flag.Color = color
	end
end

return TownService

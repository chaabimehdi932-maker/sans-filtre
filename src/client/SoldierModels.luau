--[[
	SoldierModels
	Full-size R6 soldiers (same proportions as a Roblox R6 character: 2×2×1 torso, 1×2×1 limbs,
	classic head mesh + face) with Napoleonic uniforms, plus horses and cannons.

	Every model is an anchored root part moved by SquadRenderer with BulkMoveTo; the rest hangs
	on Motor6D joints. The body joints use Roblox's STANDARD R6 names and C0/C1 frames
	(RootJoint, Neck, Left/Right Shoulder, Left/Right Hip) so real R6 animations can play on
	them (SoldierAnimationIds). Procedural poses go through SoldierModels.pose(rig, joint, R),
	where R is a rotation in the torso's own axes:
	  CFrame.Angles(x, 0, z)  → +x swings a limb forward, z spreads it sideways.

	Rig table: { model, root, motors = { name = Motor6D }, parts = { visible BaseParts }, kind }
	  Infantry/Crew motors : root, neck, armL, armR, legL, legR, gun (infantry only)
	  Cavalry motors       : legFL, legFR, legBL, legBR, neck, tail, rider, armL, armR, legL, legR
	  Cannon motors        : barrel
]]

local SoldierModels = {}

-- Height of an R6 torso centre above the feet
SoldierModels.TORSO_HEIGHT = 3
-- Height of the horse body centre above the ground
SoldierModels.HORSE_HEIGHT = 4.2

local UNIFORMS = {
	Blue = { -- French line infantry
		coat = Color3.fromRGB(34, 54, 140),
		facing = Color3.fromRGB(200, 35, 35),
		trousers = Color3.fromRGB(236, 236, 230),
		plume = Color3.fromRGB(210, 35, 35),
		saddlecloth = Color3.fromRGB(35, 55, 140),
	},
	Red = { -- British redcoats
		coat = Color3.fromRGB(185, 32, 32),
		facing = Color3.fromRGB(28, 38, 90),
		trousers = Color3.fromRGB(215, 215, 210),
		plume = Color3.fromRGB(240, 240, 240),
		saddlecloth = Color3.fromRGB(150, 30, 30),
	},
}
local SKINS = {
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(215, 160, 120),
	Color3.fromRGB(175, 120, 85),
	Color3.fromRGB(240, 200, 170),
	Color3.fromRGB(125, 85, 60),
}
local HORSES = {
	{ Color3.fromRGB(110, 70, 40), Color3.fromRGB(40, 28, 20) },
	{ Color3.fromRGB(35, 30, 30), Color3.fromRGB(15, 15, 15) },
	{ Color3.fromRGB(195, 190, 180), Color3.fromRGB(115, 110, 105) },
	{ Color3.fromRGB(150, 85, 45), Color3.fromRGB(60, 40, 25) },
	{ Color3.fromRGB(90, 55, 35), Color3.fromRGB(30, 20, 15) },
}
local BLACK = Color3.fromRGB(22, 22, 24)
local BRASS = Color3.fromRGB(205, 165, 60)
local WOOD = Color3.fromRGB(95, 62, 35)
local STEEL = Color3.fromRGB(195, 195, 205)
local LEATHER = Color3.fromRGB(80, 52, 30)
local WHITE = Color3.fromRGB(242, 242, 236)
local IRON = Color3.fromRGB(45, 45, 50)

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinders point along X: stand them up
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinders along Z

local function newRig(parent: Instance, kind: string, rootSize: Vector3, rootVisible: Part?): any
	local model = Instance.new("Model")
	model.Name = kind
	local root = rootVisible or Instance.new("Part")
	if not rootVisible then
		root.Name = "HumanoidRootPart"
		root.Size = rootSize
		root.Transparency = 1
	end
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = parent
	return { model = model, root = root, motors = {}, frames = {}, parts = {}, kind = kind }
end

local function part(
	rig: any,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = rig.model
	table.insert(rig.parts, p)
	return p
end

local function motor(rig: any, name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	rig.motors[name] = m
	return m
end

-- Standard R6 joint frames
local R6 = {
	RootJoint = { CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	Neck = { CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	["Right Shoulder"] = {
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	["Left Shoulder"] = {
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
	["Right Hip"] = {
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	["Left Hip"] = {
		CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
}

local function r6Motor(
	rig: any,
	key: string,
	name: string,
	part0: BasePart,
	part1: BasePart,
	c0Override: CFrame?
): Motor6D
	local frames = R6[name]
	local c0 = c0Override or frames[1]
	local m = motor(rig, key, part0, part1, c0, frames[2])
	m.Name = name
	-- cache the joint's rotation so poses can be given in torso axes
	local rotation = c0 - c0.Position
	rig.frames[key] = { rotation, rotation:Inverse() }
	return m
end

-- Apply a rotation expressed in the parent part's axes to a joint (works for any C0 frame)
function SoldierModels.pose(rig: any, key: string, rotation: CFrame)
	local m = rig.motors[key]
	local frame = rig.frames[key]
	if frame then
		m.Transform = frame[2] * rotation * frame[1]
	else
		m.Transform = rotation
	end
end

local function attach(part0: BasePart, part1: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
end

-- R6 body: torso on the root, head, arms, legs + uniform details. Returns torso, head, armR.
local function body(rig: any, team: string, def: any, torsoParent: BasePart, torsoC0: CFrame, cavalry: boolean)
	local uniform = UNIFORMS[team]
	local skin = SKINS[math.random(1, #SKINS)]
	local coat = def.coatColor or uniform.coat

	local torso = part(rig, "Torso", Vector3.new(2, 2, 1), coat)
	torso.CastShadow = true
	if cavalry then
		motor(rig, "rider", torsoParent, torso, torsoC0, CFrame.new())
	else
		r6Motor(rig, "root", "RootJoint", torsoParent, torso)
	end

	local head = part(rig, "Head", Vector3.new(2, 1, 1), skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	r6Motor(rig, "neck", "Neck", torso, head)

	for _, side in { "L", "R" } do
		local sideName = if side == "L" then "Left" else "Right"
		local arm = part(rig, sideName .. " Arm", Vector3.new(1, 2, 1), coat)
		r6Motor(rig, "arm" .. side, sideName .. " Shoulder", torso, arm)
		attach(arm, part(rig, "Hand", Vector3.new(1.04, 0.45, 1.04), skin), CFrame.new(0, -0.8, 0))
		attach(arm, part(rig, "Cuff", Vector3.new(1.06, 0.2, 1.06), uniform.facing), CFrame.new(0, -0.5, 0))
		attach(
			arm,
			part(rig, "Epaulette", Vector3.new(1.1, 0.25, 1.1), uniform.facing, Enum.Material.Fabric),
			CFrame.new(0, 0.9, 0)
		)
		local leg = part(rig, sideName .. " Leg", Vector3.new(1, 2, 1), uniform.trousers)
		r6Motor(rig, "leg" .. side, sideName .. " Hip", torso, leg)
		local bootHeight = if cavalry then 1.3 else 0.7
		attach(
			leg,
			part(rig, "Boot", Vector3.new(1.04, bootHeight, 1.08), BLACK),
			CFrame.new(0, -1 + bootHeight / 2, -0.02)
		)
	end

	-- crossbelt, collar, buttons, backpack
	attach(torso, part(rig, "Belt", Vector3.new(0.32, 2.7, 1.06), WHITE), CFrame.Angles(0, 0, math.rad(-40)))
	attach(torso, part(rig, "Collar", Vector3.new(2.04, 0.3, 1.04), uniform.facing), CFrame.new(0, 0.85, 0))
	attach(
		torso,
		part(rig, "Buttons", Vector3.new(0.18, 1.5, 1.06), BRASS, Enum.Material.Metal),
		CFrame.new(0.45, 0, 0)
	)
	if not cavalry then
		attach(
			torso,
			part(rig, "Backpack", Vector3.new(1.6, 1.4, 0.6), LEATHER, Enum.Material.Fabric),
			CFrame.new(0, 0.1, 0.8)
		)
		attach(
			torso,
			part(
				rig,
				"Bedroll",
				Vector3.new(1.8, 0.45, 0.45),
				Color3.fromRGB(120, 110, 95),
				Enum.Material.Fabric,
				Enum.PartType.Cylinder
			),
			CFrame.new(0, 0.95, 0.8)
		)
	end

	-- headgear
	if cavalry then
		attach(
			head,
			part(rig, "Helmet", Vector3.new(1.3, 0.85, 1.3), def.hatColor or BRASS, Enum.Material.Metal),
			CFrame.new(0, 0.55, 0)
		)
		attach(
			head,
			part(rig, "Crest", Vector3.new(0.3, 0.6, 1.5), BLACK, Enum.Material.Fabric),
			CFrame.new(0, 1.1, 0.1)
		)
	else
		local hatHeight = (def.hatHeight or 0.7) * 1.4
		local hat = part(
			rig,
			"Shako",
			Vector3.new(hatHeight, 1.2, 1.2),
			def.hatColor or BLACK,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		attach(head, hat, CFrame.new(0, 0.55 + hatHeight / 2, 0) * VERTICAL)
		attach(head, part(rig, "Peak", Vector3.new(1.15, 0.12, 0.45), BLACK), CFrame.new(0, 0.58, -0.62))
		attach(
			head,
			part(rig, "Plate", Vector3.new(0.45, 0.45, 0.1), BRASS, Enum.Material.Metal),
			CFrame.new(0, 0.55 + hatHeight * 0.45, -0.6)
		)
		attach(
			head,
			part(rig, "Plume", Vector3.new(0.28, 0.75, 0.28), def.plumeColor or uniform.plume, Enum.Material.Fabric),
			CFrame.new(0, 0.9 + hatHeight, -0.2)
		)
	end
	return torso
end

-- Line infantry, skirmishers, grenadiers; artillery crew with withGun = false.
-- crewTool: "Rammer" (loader) or "Linstock" (gunner) held in the right hand.
function SoldierModels.infantry(parent: Instance, team: string, def: any, withGun: boolean, crewTool: string?): any
	local rig = newRig(parent, if withGun then "Infantry" else "Crew", Vector3.new(2, 2, 1), nil)
	local torso = body(rig, team, def, rig.root, CFrame.new(), false)
	local hand = rig.motors.armR.Part1
	if crewTool == "Rammer" then
		-- continues the line of the arm, like the cavalry sabre
		attach(hand, part(rig, "Rammer", Vector3.new(0.22, 5, 0.22), WOOD, Enum.Material.Wood), CFrame.new(0, -3.4, 0))
		attach(
			hand,
			part(rig, "RammerHead", Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(60, 45, 30), Enum.Material.Fabric),
			CFrame.new(0, -5.9, 0)
		)
	elseif crewTool == "Linstock" then
		attach(
			hand,
			part(rig, "Linstock", Vector3.new(0.16, 2.6, 0.16), WOOD, Enum.Material.Wood),
			CFrame.new(0, -1.9, -0.3)
		)
		local match =
			part(rig, "Match", Vector3.new(0.26, 0.26, 0.26), Color3.fromRGB(255, 140, 40), Enum.Material.Neon)
		attach(hand, match, CFrame.new(0, -3.2, -0.3))
	end
	if withGun then
		-- musket lies along its own +Y; the "gun" joint's Transform is the pose (butt position)
		local musket = part(rig, "Musket", Vector3.new(0.22, 4.4, 0.3), WOOD, Enum.Material.Wood)
		motor(rig, "gun", torso, musket, CFrame.new(), CFrame.new(0, -2.2, 0))
		attach(
			musket,
			part(rig, "Barrel", Vector3.new(0.16, 2.2, 0.16), STEEL, Enum.Material.Metal),
			CFrame.new(0, 1.1, -0.1)
		)
		attach(
			musket,
			part(rig, "Bayonet", Vector3.new(0.08, 1.1, 0.08), STEEL, Enum.Material.Metal),
			CFrame.new(0, 2.75, -0.12)
		)
	end
	return rig
end

function SoldierModels.cavalry(parent: Instance, team: string, def: any): any
	local uniform = UNIFORMS[team]
	local coatColors = HORSES[math.random(1, #HORSES)]
	local coat, dark = coatColors[1], coatColors[2]

	local horseBody = Instance.new("Part")
	horseBody.Name = "HorseBody"
	horseBody.Size = Vector3.new(2.2, 2.2, 5.6)
	horseBody.Color = coat
	horseBody.Material = Enum.Material.SmoothPlastic
	horseBody.CastShadow = true
	local rig = newRig(parent, "Cavalry", Vector3.one, horseBody)
	table.insert(rig.parts, horseBody)

	attach(horseBody, part(rig, "Chest", Vector3.new(2.1, 2.1, 1.6), coat), CFrame.new(0, 0.1, -2.6))
	attach(horseBody, part(rig, "Rump", Vector3.new(2.25, 2.15, 1.7), coat), CFrame.new(0, 0.12, 2.4))
	attach(
		horseBody,
		part(rig, "Saddlecloth", Vector3.new(2.4, 1.4, 2.4), uniform.saddlecloth, Enum.Material.Fabric),
		CFrame.new(0, 0.45, 0.2)
	)
	attach(horseBody, part(rig, "Saddle", Vector3.new(2.3, 0.35, 1.8), LEATHER), CFrame.new(0, 1.15, 0.2))

	local legLength = SoldierModels.HORSE_HEIGHT - 1.1
	for _, spot in
		{ { "legFL", -0.65, -2.4 }, { "legFR", 0.65, -2.4 }, { "legBL", -0.65, 2.4 }, { "legBR", 0.65, 2.4 } }
	do
		local leg = part(rig, "Leg", Vector3.new(0.6, legLength, 0.65), coat)
		motor(rig, spot[1], horseBody, leg, CFrame.new(spot[2], -1.1, spot[3]), CFrame.new(0, legLength / 2, 0))
		attach(leg, part(rig, "Hoof", Vector3.new(0.66, 0.4, 0.72), dark), CFrame.new(0, -legLength / 2 + 0.2, -0.03))
	end
	local neck = part(rig, "Neck", Vector3.new(1.0, 2.8, 1.3), coat)
	motor(
		rig,
		"neck",
		horseBody,
		neck,
		CFrame.new(0, 0.8, -3.0) * CFrame.Angles(math.rad(-35), 0, 0),
		CFrame.new(0, -1.2, 0)
	)
	attach(neck, part(rig, "Mane", Vector3.new(0.3, 2.6, 0.45), dark, Enum.Material.Fabric), CFrame.new(0, 0.1, 0.7))
	local horseHead = part(rig, "HorseHead", Vector3.new(0.95, 1.05, 2.1), coat)
	attach(neck, horseHead, CFrame.new(0, 1.35, -0.3) * CFrame.Angles(math.rad(5), 0, 0) * CFrame.new(0, 0, -0.7))
	attach(horseHead, part(rig, "Muzzle", Vector3.new(0.8, 0.8, 0.7), dark), CFrame.new(0, -0.15, -1.1))
	attach(horseHead, part(rig, "EarL", Vector3.new(0.2, 0.5, 0.2), coat), CFrame.new(-0.3, 0.7, 0.6))
	attach(horseHead, part(rig, "EarR", Vector3.new(0.2, 0.5, 0.2), coat), CFrame.new(0.3, 0.7, 0.6))
	local tail = part(rig, "Tail", Vector3.new(0.4, 2.4, 0.4), dark, Enum.Material.Fabric)
	motor(
		rig,
		"tail",
		horseBody,
		tail,
		CFrame.new(0, 0.7, 3.2) * CFrame.Angles(math.rad(-25), 0, 0),
		CFrame.new(0, 1.1, 0)
	)

	-- R6 rider sitting in the saddle (the "rider" joint)
	body(rig, team, def, horseBody, CFrame.new(0, 2.35, 0.2), true)
	-- sabre continues the line of the right arm, so raising the arm raises the blade
	local armR = rig.motors.armR.Part1
	attach(
		armR,
		part(rig, "Sabre", Vector3.new(0.12, 3.4, 0.3), STEEL, Enum.Material.Metal),
		CFrame.new(0, -2.75, -0.1)
	)
	attach(armR, part(rig, "Guard", Vector3.new(0.55, 0.14, 0.4), BRASS, Enum.Material.Metal), CFrame.new(0, -1.05, 0))
	return rig
end

-- Field gun drawn in front of an artillery squad (root = axle at wheel-centre height)
SoldierModels.CANNON_AXLE_HEIGHT = 1.8
function SoldierModels.cannon(parent: Instance): any
	local rig = newRig(parent, "Cannon", Vector3.new(0.5, 0.5, 0.5), nil)
	local root = rig.root
	attach(root, part(rig, "Carriage", Vector3.new(1.4, 0.8, 4), WOOD, Enum.Material.Wood), CFrame.new(0, 0.1, 0.4))
	attach(
		root,
		part(rig, "Trail", Vector3.new(0.8, 0.6, 4.2), WOOD, Enum.Material.Wood),
		CFrame.new(0, -0.7, 3.6) * CFrame.Angles(math.rad(25), 0, 0)
	)
	for _, x in { -1.25, 1.25 } do
		attach(
			root,
			part(rig, "Wheel", Vector3.new(0.35, 3.6, 3.6), WOOD, Enum.Material.Wood, Enum.PartType.Cylinder),
			CFrame.new(x, 0, 0)
		)
		attach(
			root,
			part(rig, "Hub", Vector3.new(0.5, 0.8, 0.8), IRON, Enum.Material.Metal, Enum.PartType.Cylinder),
			CFrame.new(x, 0, 0)
		)
	end
	local barrel = part(rig, "Barrel", Vector3.new(5.4, 1.05, 1.05), IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
	motor(rig, "barrel", root, barrel, CFrame.new(0, 0.85, -0.6), ALONG_Z:Inverse())
	attach(
		barrel,
		part(rig, "Breech", Vector3.new(0.8, 1.35, 1.35), IRON, Enum.Material.Metal, Enum.PartType.Cylinder),
		CFrame.new(-2.6, 0, 0)
	)
	-- the barrel's +X points forward
	attach(
		barrel,
		part(rig, "Muzzle", Vector3.new(0.4, 1.3, 1.3), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder),
		CFrame.new(2.6, 0, 0)
	)
	return rig
end

return SoldierModels

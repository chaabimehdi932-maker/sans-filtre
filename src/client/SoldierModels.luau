--[[
	SoldierModels
	Builds the (placeholder, part-based) soldier, horse and cannon models drawn by SquadRenderer.
	A model is a list of pieces { part, bone, offset }: every frame the renderer computes one
	CFrame per bone (root, legs, arms, gun…) and places each part at bone * offset.

	Bones:
	  Infantry / crew : root, legL, legR, armL, armR, gun
	  Cavalry         : horse, legFL, legFR, legBL, legBR, neck, rider, armL, armR
	  Cannon (extras) : carriage, barrel
]]

local SoldierModels = {}

local UNIFORMS = {
	Blue = { -- French line infantry
		coat = Color3.fromRGB(32, 52, 135),
		facing = Color3.fromRGB(200, 35, 35),
		trousers = Color3.fromRGB(236, 236, 230),
		plume = Color3.fromRGB(210, 35, 35),
		saddlecloth = Color3.fromRGB(35, 55, 140),
	},
	Red = { -- British redcoats
		coat = Color3.fromRGB(185, 32, 32),
		facing = Color3.fromRGB(30, 40, 90),
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

-- Joint positions relative to the soldier's feet (shared with SquadRenderer)
SoldierModels.HIP_L = CFrame.new(-0.24, 0.85, 0)
SoldierModels.HIP_R = CFrame.new(0.24, 0.85, 0)
SoldierModels.SHOULDER_L = CFrame.new(-0.66, 1.9, 0)
SoldierModels.SHOULDER_R = CFrame.new(0.66, 1.9, 0)
-- Horse joints relative to the horse bone (body centre)
SoldierModels.HORSE_HEIGHT = 1.95
SoldierModels.HORSE_HIPS = {
	legFL = CFrame.new(-0.4, -0.45, -1.2),
	legFR = CFrame.new(0.4, -0.45, -1.2),
	legBL = CFrame.new(-0.4, -0.45, 1.2),
	legBR = CFrame.new(0.4, -0.45, 1.2),
}
SoldierModels.NECK = CFrame.new(0, 0.45, -1.55)
SoldierModels.SADDLE = CFrame.new(0, 0.72, 0.15)
SoldierModels.RIDER_SHOULDER_L = CFrame.new(-0.55, 1.0, 0)
SoldierModels.RIDER_SHOULDER_R = CFrame.new(0.55, 1.0, 0)

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinders point along X: stand them up

local function builder(parent: Instance)
	local pieces = {}
	local function add(bone: string, p: Part, offset: CFrame): Part
		p.Parent = parent
		table.insert(pieces, { part = p, bone = bone, offset = offset })
		return p
	end
	return pieces, add
end

local function head(add: any, bone: string, at: CFrame, skin: Color3, def: any, uniform: any, cavalry: boolean)
	add(bone, part("Head", Vector3.new(0.55, 0.58, 0.55), skin), at)
	local hatHeight = def.hatHeight or 0.7
	if cavalry then
		-- brass helmet with a black horsehair crest
		add(
			bone,
			part("Helmet", Vector3.new(0.64, 0.45, 0.66), def.hatColor or BRASS, Enum.Material.Metal),
			at * CFrame.new(0, 0.38, 0)
		)
		add(
			bone,
			part("Crest", Vector3.new(0.14, 0.35, 0.75), BLACK, Enum.Material.Fabric),
			at * CFrame.new(0, 0.72, 0.08)
		)
	else
		local hat = part(
			"Hat",
			Vector3.new(hatHeight, 0.62, 0.62),
			def.hatColor or BLACK,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		add(bone, hat, at * CFrame.new(0, 0.27 + hatHeight / 2, 0) * VERTICAL)
		add(
			bone,
			part("Plate", Vector3.new(0.24, 0.22, 0.06), BRASS, Enum.Material.Metal),
			at * CFrame.new(0, 0.27 + hatHeight * 0.45, -0.31)
		)
		add(
			bone,
			part("Plume", Vector3.new(0.13, 0.42, 0.13), def.plumeColor or uniform.plume, Enum.Material.Fabric),
			at * CFrame.new(0, 0.5 + hatHeight, -0.1)
		)
	end
end

-- Line infantry, skirmishers, grenadiers, artillery crew (withGun = false)
function SoldierModels.infantry(parent: Instance, team: string, def: any, withGun: boolean): any
	local uniform = UNIFORMS[team]
	local skin = SKINS[math.random(1, #SKINS)]
	local coat = if def.coatColor then def.coatColor else uniform.coat
	local pieces, add = builder(parent)

	for _, side in { "L", "R" } do
		add("leg" .. side, part("Leg", Vector3.new(0.42, 0.85, 0.45), uniform.trousers), CFrame.new(0, -0.42, 0))
	end
	add("root", part("Torso", Vector3.new(1.0, 1.05, 0.55), coat), CFrame.new(0, 1.45, 0))
	add(
		"root",
		part("Belt", Vector3.new(0.16, 1.25, 0.58), WHITE),
		CFrame.new(0, 1.45, 0) * CFrame.Angles(0, 0, math.rad(-38))
	)
	add("root", part("Backpack", Vector3.new(0.75, 0.72, 0.32), LEATHER), CFrame.new(0, 1.5, 0.42))
	head(add, "root", CFrame.new(0, 2.3, 0), skin, def, uniform, false)
	for _, side in { "L", "R" } do
		add("arm" .. side, part("Arm", Vector3.new(0.3, 0.9, 0.32), coat), CFrame.new(0, -0.42, 0))
		add("arm" .. side, part("Hand", Vector3.new(0.24, 0.22, 0.24), skin), CFrame.new(0, -0.95, 0))
	end
	if withGun then
		-- musket along the gun bone's +Y, origin at the butt
		add("gun", part("Musket", Vector3.new(0.13, 2.5, 0.15), WOOD, Enum.Material.Wood), CFrame.new(0, 1.25, 0))
		add("gun", part("Bayonet", Vector3.new(0.05, 0.6, 0.05), STEEL, Enum.Material.Metal), CFrame.new(0, 2.8, -0.05))
	end
	return { pieces = pieces, kind = "Infantry" }
end

function SoldierModels.cavalry(parent: Instance, team: string, def: any): any
	local uniform = UNIFORMS[team]
	local skin = SKINS[math.random(1, #SKINS)]
	local horse = HORSES[math.random(1, #HORSES)]
	local coat, dark = horse[1], horse[2]
	local pieces, add = builder(parent)

	-- horse
	local body = add("horse", part("Body", Vector3.new(1.3, 1.2, 3.1), coat), CFrame.new())
	body.CastShadow = true
	add("horse", part("Chest", Vector3.new(1.2, 1.15, 0.9), coat), CFrame.new(0, 0.05, -1.45))
	add(
		"horse",
		part("Saddlecloth", Vector3.new(1.4, 0.75, 1.3), uniform.saddlecloth, Enum.Material.Fabric),
		CFrame.new(0, 0.3, 0.15)
	)
	add(
		"horse",
		part("Tail", Vector3.new(0.25, 1.2, 0.25), dark, Enum.Material.Fabric),
		CFrame.new(0, -0.1, 1.75) * CFrame.Angles(math.rad(-20), 0, 0)
	)
	for bone in SoldierModels.HORSE_HIPS do
		add(bone, part("Leg", Vector3.new(0.3, 1.45, 0.32), coat), CFrame.new(0, -0.7, 0))
		add(bone, part("Hoof", Vector3.new(0.34, 0.22, 0.36), dark), CFrame.new(0, -1.4, -0.02))
	end
	add(
		"neck",
		part("Neck", Vector3.new(0.55, 1.3, 0.7), coat),
		CFrame.new(0, 0.45, -0.25) * CFrame.Angles(math.rad(-35), 0, 0)
	)
	add(
		"neck",
		part("Mane", Vector3.new(0.14, 1.2, 0.25), dark, Enum.Material.Fabric),
		CFrame.new(0, 0.5, 0.05) * CFrame.Angles(math.rad(-35), 0, 0)
	)
	add(
		"neck",
		part("HorseHead", Vector3.new(0.5, 0.55, 1.1), coat),
		CFrame.new(0, 1.05, -0.75) * CFrame.Angles(math.rad(-25), 0, 0)
	)
	add(
		"neck",
		part("Muzzle", Vector3.new(0.42, 0.42, 0.35), dark),
		CFrame.new(0, 0.85, -1.25) * CFrame.Angles(math.rad(-25), 0, 0)
	)

	-- rider
	add("rider", part("Torso", Vector3.new(0.9, 1.0, 0.5), uniform.coat), CFrame.new(0, 0.55, 0))
	add(
		"rider",
		part("Belt", Vector3.new(0.14, 1.15, 0.52), WHITE),
		CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(38))
	)
	for _, x in { -0.7, 0.7 } do
		add(
			"rider",
			part("Boot", Vector3.new(0.32, 1.05, 0.38), BLACK),
			CFrame.new(x, -0.25, -0.15) * CFrame.Angles(math.rad(-20), 0, 0)
		)
	end
	head(add, "rider", CFrame.new(0, 1.35, 0), skin, def, uniform, true)
	add("armL", part("Arm", Vector3.new(0.28, 0.85, 0.3), uniform.coat), CFrame.new(0, -0.4, 0))
	add("armR", part("Arm", Vector3.new(0.28, 0.85, 0.3), uniform.coat), CFrame.new(0, -0.4, 0))
	add("armR", part("Hand", Vector3.new(0.22, 0.22, 0.22), skin), CFrame.new(0, -0.88, 0))
	-- the sabre continues the line of the arm, so raising the arm raises the blade
	add("armR", part("Sabre", Vector3.new(0.06, 2.1, 0.14), STEEL, Enum.Material.Metal), CFrame.new(0, -2.0, -0.05))
	add("armR", part("Guard", Vector3.new(0.3, 0.08, 0.2), BRASS, Enum.Material.Metal), CFrame.new(0, -0.98, 0))
	return { pieces = pieces, kind = "Cavalry" }
end

-- Cannon + limber drawn at the front of an artillery squad
function SoldierModels.cannon(parent: Instance): { any }
	local pieces, add = builder(parent)
	add("carriage", part("Carriage", Vector3.new(0.9, 0.55, 2.6), WOOD, Enum.Material.Wood), CFrame.new(0, 1.05, 0.2))
	add(
		"carriage",
		part("Trail", Vector3.new(0.55, 0.4, 2.6), WOOD, Enum.Material.Wood),
		CFrame.new(0, 0.55, 2.2) * CFrame.Angles(math.rad(18), 0, 0)
	)
	for _, x in { -0.8, 0.8 } do
		add(
			"carriage",
			part("Wheel", Vector3.new(0.22, 2.1, 2.1), WOOD, Enum.Material.Wood, Enum.PartType.Cylinder),
			CFrame.new(x, 1.05, 0)
		)
		add(
			"carriage",
			part("Hub", Vector3.new(0.3, 0.5, 0.5), IRON, Enum.Material.Metal, Enum.PartType.Cylinder),
			CFrame.new(x, 1.05, 0)
		)
	end
	-- barrel points to -Z (cylinders point along X → rotate 90° around Y)
	add(
		"barrel",
		part("Barrel", Vector3.new(3.2, 0.62, 0.62), IRON, Enum.Material.Metal, Enum.PartType.Cylinder),
		CFrame.new(0, 0, -0.6) * CFrame.Angles(0, math.rad(90), 0)
	)
	add(
		"barrel",
		part("Breech", Vector3.new(0.5, 0.8, 0.8), IRON, Enum.Material.Metal, Enum.PartType.Cylinder),
		CFrame.new(0, 0, 1.0) * CFrame.Angles(0, math.rad(90), 0)
	)
	add(
		"barrel",
		part("Muzzle", Vector3.new(0.25, 0.75, 0.75), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder),
		CFrame.new(0, 0, -2.15) * CFrame.Angles(0, math.rad(90), 0)
	)
	return pieces
end

return SoldierModels

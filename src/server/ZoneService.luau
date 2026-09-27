--[[
	ZoneService
	Capture zones found through the "CaptureZone" tag (see MapService).

	Every TickInterval (0.5 s, not per frame) each zone sums the "presence weight" of the
	non-routing squads (+ commanders) standing inside it. We test squad centres against the
	zone radius instead of GetPartsInPart: squads are logical objects, so this is cheaper and
	matches the combat math exactly.

	control goes from -100 (Red) to +100 (Blue):
	  • only one team inside → control moves towards that team
	  • both teams inside   → contested, progress freezes
	  • a zone changes hands when control passes through 0 (Neutral) to the other extreme
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MathUtil = require(Modules:WaitForChild("MathUtil"))

local MapService = require(script.Parent:WaitForChild("MapService"))
local SquadService = require(script.Parent:WaitForChild("SquadService"))

local Z = GameConfig.Zones
local Teams = GameConfig.Teams

local ZoneService = {}

ZoneService.hooks = {
	getHeroes = function(): { any }
		return {}
	end,
	onOwnerChanged = function(_zone: any, _newOwner: string, _oldOwner: string) end,
}

local zones: { any } = {}

local visualsFolder = Instance.new("Folder")
visualsFolder.Name = "ZoneVisuals"
visualsFolder.Parent = Workspace

local function newPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function flatDisc(diameter: number, position: Vector3, color: Color3, transparency: number): Part
	return newPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = transparency,
		Material = Enum.Material.SmoothPlastic,
		Parent = visualsFolder,
	})
end

local function zoneRadius(part: BasePart): number
	local attribute = part:GetAttribute("Radius")
	if typeof(attribute) == "number" then
		return attribute
	end
	if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		return math.max(part.Size.Y, part.Size.Z) / 2
	end
	return math.max(part.Size.X, part.Size.Z) / 2
end

local function buildZone(part: BasePart, index: number): any
	local radius = zoneRadius(part)
	local ground = MapService.groundY(part.Position.X, part.Position.Z, part.Position.Y)
	local position = Vector3.new(part.Position.X, ground, part.Position.Z)
	local name = part:GetAttribute("ZoneName") or part.Name
	local bonus = part:GetAttribute("Bonus")

	local ring = flatDisc(radius * 2, position + Vector3.new(0, 0.12, 0), Teams.Neutral.color, 0.75)
	local fill = flatDisc(0.5, position + Vector3.new(0, 0.2, 0), Teams.Neutral.color, 0.5)
	newPart({ -- flag pole
		Name = "FlagPole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(14, 0.4, 0.4),
		CFrame = CFrame.new(position + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 70, 50),
		Parent = visualsFolder,
	})
	local flag = newPart({
		Name = "Flag",
		Size = Vector3.new(0.15, 2.6, 4),
		CFrame = CFrame.new(position + Vector3.new(0, 12.6, 2.1)),
		Color = Teams.Neutral.color,
		Material = Enum.Material.Fabric,
		Parent = visualsFolder,
	})

	-- No BillboardGui here: the client's objective marker (letter, name, distance, capture bar,
	-- bonus) is the single label for a zone, so two labels can never overlap.
	local letter = string.char(64 + index)

	return {
		name = name,
		part = part,
		order = index,
		position = position,
		radius = radius,
		bonus = if typeof(bonus) == "string" then bonus else nil,
		control = 0,
		owner = "Neutral",
		contested = false,
		letter = letter,
		ui = { ring = ring, fill = fill, flag = flag },
		lastVisual = "",
	}
end

local function refreshVisuals(zone: any)
	local key = string.format("%d|%s|%s", math.floor(zone.control), zone.owner, tostring(zone.contested))
	if key == zone.lastVisual then
		return
	end
	zone.lastVisual = key
	local ui = zone.ui
	local ownerColor = Teams[zone.owner].color
	local leaning = if zone.control > 0 then "Blue" elseif zone.control < 0 then "Red" else "Neutral"
	local fraction = math.abs(zone.control) / 100

	ui.ring.Color = ownerColor
	ui.flag.Color = ownerColor
	ui.fill.Color = Teams[leaning].color
	local diameter = math.max(0.5, zone.radius * 2 * fraction)
	ui.fill.Size = Vector3.new(0.2, diameter, diameter)
end

function ZoneService.init()
	visualsFolder:ClearAllChildren()
	table.clear(zones)
	for index, part in MapService.getZoneParts() do
		table.insert(zones, buildZone(part, index))
	end
end

-- Set every zone to an owner at the start of a round ("Blue" | "Red" | "Neutral")
function ZoneService.reset(owner: string)
	for _, zone in zones do
		zone.owner = owner
		zone.control = if owner == "Blue" then 100 elseif owner == "Red" then -100 else 0
		zone.contested = false
		refreshVisuals(zone)
	end
end

function ZoneService.tick(dt: number)
	local squads = SquadService.getAll()
	local heroes = ZoneService.hooks.getHeroes()
	for _, zone in zones do
		local blue, red = 0, 0
		for _, squad in squads do
			if squad.alive and not squad.routing then
				if MathUtil.flatDistance(squad.position, zone.position) <= zone.radius then
					if squad.team == "Blue" then
						blue += squad.def.presenceWeight
					else
						red += squad.def.presenceWeight
					end
				end
			end
		end
		for _, hero in heroes do
			if MathUtil.flatDistance(hero.position, zone.position) <= zone.radius then
				blue += Z.HeroPresenceWeight
			end
		end

		zone.contested = blue > 0 and red > 0
		if not zone.contested then
			local weight = math.max(blue, red)
			local rate = Z.CaptureRate * math.min(Z.MaxRateMult, 1 + (weight - 1) * Z.WeightBonusPerExtra)
			if blue > 0 then
				zone.control = math.min(100, zone.control + rate * dt)
			elseif red > 0 then
				zone.control = math.max(-100, zone.control - rate * dt)
			end
		end

		local previous = zone.owner
		if zone.control >= 100 then
			zone.owner = "Blue"
		elseif zone.control <= -100 then
			zone.owner = "Red"
		elseif (previous == "Blue" and zone.control <= 0) or (previous == "Red" and zone.control >= 0) then
			zone.owner = "Neutral"
		end
		refreshVisuals(zone)
		if zone.owner ~= previous then
			ZoneService.hooks.onOwnerChanged(zone, zone.owner, previous)
		end
	end
end

function ZoneService.getZones(): { any }
	return zones
end

function ZoneService.countOwned(team: string): number
	local count = 0
	for _, zone in zones do
		if zone.owner == team then
			count += 1
		end
	end
	return count
end

function ZoneService.allOwnedBy(team: string): boolean
	return #zones > 0 and ZoneService.countOwned(team) == #zones
end

-- Number of held zones granting `bonus` ("Reinforcements" | "Morale" | "ArtilleryRange") to `team`
function ZoneService.getTeamBonus(team: string, bonus: string): number
	local count = 0
	for _, zone in zones do
		if zone.owner == team and zone.bonus == bonus then
			count += 1
		end
	end
	return count
end

function ZoneService.snapshot(): { any }
	local out = {}
	for _, zone in zones do
		table.insert(out, {
			name = zone.name,
			x = zone.position.X,
			y = zone.position.Y,
			z = zone.position.Z,
			radius = zone.radius,
			control = zone.control,
			owner = zone.owner,
			contested = zone.contested,
			bonus = zone.bonus,
			letter = zone.letter,
		})
	end
	return out
end

return ZoneService

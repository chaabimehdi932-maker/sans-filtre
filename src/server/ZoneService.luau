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
	local pole = newPart({
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

	-- Compact label: letter diamond on its own row ABOVE the name, so it never covers the text.
	-- Pixel-sized (not stud-sized) so it stays readable far away and small up close.
	local letter = string.char(64 + index)
	local teamColor = Teams.Neutral.color
	local gui = Instance.new("BillboardGui")
	gui.Name = "ZoneInfo"
	gui.Size = UDim2.fromOffset(150, 78)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 1500
	gui.LightInfluence = 0
	gui.Adornee = pole
	local function stroked(label: TextLabel, thickness: number)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = thickness
		stroke.Parent = label
	end
	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(0.5, 0)
	diamond.Position = UDim2.new(0.5, 0, 0, 4)
	diamond.Size = UDim2.fromOffset(20, 20)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = teamColor
	diamond.Parent = gui
	local diamondStroke = Instance.new("UIStroke")
	diamondStroke.Color = Color3.new(1, 1, 1)
	diamondStroke.Thickness = 2
	diamondStroke.Parent = diamond
	local letterLabel = Instance.new("TextLabel")
	letterLabel.BackgroundTransparency = 1
	letterLabel.AnchorPoint = Vector2.new(0.5, 0)
	letterLabel.Position = UDim2.new(0.5, 0, 0, 2)
	letterLabel.Size = UDim2.fromOffset(24, 24)
	letterLabel.Font = Enum.Font.FredokaOne
	letterLabel.TextSize = 16
	letterLabel.TextColor3 = Color3.new(1, 1, 1)
	letterLabel.Text = letter
	letterLabel.ZIndex = 2
	letterLabel.Parent = gui
	stroked(letterLabel, 1.5)
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 30)
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 17
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = string.upper(name)
	title.Parent = gui
	stroked(title, 2)
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(25, 50)
	barBack.Size = UDim2.new(1, -50, 0, 7)
	barBack.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	barBack.BorderSizePixel = 0
	barBack.Parent = gui
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 59)
	status.Size = UDim2.new(1, 0, 0, 15)
	status.Font = Enum.Font.FredokaOne
	status.TextSize = 12
	status.TextColor3 = Color3.new(1, 1, 1)
	status.Parent = gui
	stroked(status, 1.5)
	gui.Parent = pole

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
		ui = { ring = ring, fill = fill, flag = flag, barFill = barFill, status = status, diamond = diamond },
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
	ui.diamond.BackgroundColor3 = ownerColor
	ui.fill.Color = Teams[leaning].color
	local diameter = math.max(0.5, zone.radius * 2 * fraction)
	ui.fill.Size = Vector3.new(0.2, diameter, diameter)
	ui.barFill.BackgroundColor3 = Teams[leaning].color
	ui.barFill.Size = UDim2.fromScale(fraction, 1)

	local bonusText = if zone.bonus then "  ·  +" .. zone.bonus else ""
	if zone.contested then
		ui.status.Text = "⚔ CONTESTED" .. bonusText
	else
		ui.status.Text = Teams[zone.owner].displayName .. bonusText
	end
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

-- Number of held zones granting `bonus` ("Income" | "Morale" | "ArtilleryRange") to `team`
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

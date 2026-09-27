--[[
	Hold preview: while Hold mode is on (X), glowing markers show on the ground exactly where
	every soldier of the selected squads will stand, in front of the commander, in the chosen
	formation. Uses FormationDefinitions.placeSquads, the same math the server uses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FormationDefinitions = require(Modules:WaitForChild("FormationDefinitions"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local folder = Instance.new("Folder")
folder.Name = "HoldPreview"
folder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local markers: { Part } = {}
local MARKER_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local function marker(index: number): Part
	local part = markers[index]
	if part then
		return part
	end
	part = Instance.new("Part")
	part.Name = "Marker"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.3, 2, 2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(175, 225, 255)
	part.Transparency = 0.35
	part.Parent = folder
	markers[index] = part
	return part
end

-- floating "Hold Position" label
local labelPart = Instance.new("Part")
labelPart.Anchored = true
labelPart.CanCollide = false
labelPart.CanQuery = false
labelPart.CanTouch = false
labelPart.Transparency = 1
labelPart.Size = Vector3.one
labelPart.Parent = folder
local gui = Instance.new("BillboardGui")
gui.Size = UDim2.fromOffset(260, 60)
gui.AlwaysOnTop = true
gui.LightInfluence = 0
gui.Adornee = labelPart
gui.Enabled = false
gui.Parent = labelPart
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 34)
title.Font = Enum.Font.FredokaOne
title.TextSize = 30
title.TextColor3 = Color3.fromRGB(255, 215, 90)
title.Text = "Hold Position"
title.Parent = gui
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2.5
stroke.Parent = title
local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(0, 34)
subtitle.Size = UDim2.new(1, 0, 0, 22)
subtitle.Font = Enum.Font.FredokaOne
subtitle.TextSize = 16
subtitle.TextColor3 = Color3.new(1, 1, 1)
subtitle.Parent = gui
local stroke2 = Instance.new("UIStroke")
stroke2.Thickness = 1.5
stroke2.Parent = subtitle

local function selectedEntries(): ({ any }, { any })
	local squads = {}
	local squad = ClientState.squadsById[ClientActions.controlledId()]
	if squad and squad.state ~= "Routing" then
		table.insert(squads, squad)
	end
	local entries = {}
	for _, s in squads do
		local def = UnitDefinitions.get(s.unitId)
		table.insert(entries, { soldiers = s.soldiers, spacingMult = def.spacingMult, formations = def.formations })
	end
	return squads, entries
end

local function hideFrom(index: number)
	for i = index, #markers do
		markers[i].Parent = nil
	end
end

local pulse = 0
RunService.RenderStepped:Connect(function(dt)
	local hold = ClientActions.holdState()
	local anchor, yaw = ClientActions.holdAnchor()
	if not hold.active or not anchor or ClientState.phaseName() ~= "Battle" then
		gui.Enabled = false
		hideFrom(1)
		return
	end
	local squads, entries = selectedEntries()
	if #entries == 0 then
		gui.Enabled = true
		labelPart.Position = anchor + Vector3.new(0, 5, 0)
		subtitle.Text = "No squad under your command (Tab)"
		hideFrom(1)
		return
	end

	local exclude: { Instance } = { folder }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(exclude, character)
	end
	local visuals = Workspace:FindFirstChild("SquadVisuals")
	if visuals then
		table.insert(exclude, visuals)
	end
	rayParams.FilterDescendantsInstances = exclude

	pulse += dt
	local transparency = 0.3 + math.sin(pulse * 4) * 0.12
	local placements = FormationDefinitions.placeSquads(entries, anchor, yaw, hold.formation)
	local rotation = CFrame.Angles(0, yaw, 0)
	local count = 0
	for i, placement in placements do
		local entry = entries[i]
		local base = CFrame.new(placement.center) * rotation
		for _, slot in FormationDefinitions.layout(placement.formation, entry.soldiers, entry.spacingMult) do
			count += 1
			local world = (base * CFrame.new(slot.X, 0, slot.Z)).Position
			local hit = Workspace:Raycast(world + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), rayParams)
			local y = if hit then hit.Position.Y else world.Y - 3
			local part = marker(count)
			part.CFrame = CFrame.new(world.X, y + 0.15, world.Z) * MARKER_ROTATION
			part.Transparency = transparency
			part.Parent = folder
		end
	end
	hideFrom(count + 1)
	gui.Enabled = true
	labelPart.Position = anchor + Vector3.new(0, 6, 0)
	subtitle.Text =
		string.format("%d squad%s · %s   [X] confirm", #squads, if #squads > 1 then "s" else "", hold.formation)
end)

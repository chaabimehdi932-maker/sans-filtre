--[[
	RecruitScreen — full-screen, shown ONLY during the Recruitment phase.
	Choose ONE unit (free): that is the squad you command. The rest of your army is AI-led.
	Each card: 3D portrait, rarity border, veteran stars (your experience with that unit),
	stats in the hover tooltip. Then the enemy scouting report, the objectives and READY.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Remotes = require(Modules:WaitForChild("Remotes"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local UnitCard = require(script.Parent:WaitForChild("UnitCard"))

local C = Theme.Colors
local create, outlined = Theme.create, Theme.outlined
local BLACK = Color3.new(0, 0, 0)

local chooseRemote = Remotes.get("RequestRecruit")
local confirmRemote = Remotes.get("ConfirmRecruit")

local RecruitPanel = {}

function RecruitPanel.build(screen: ScreenGui, ClientState: any): any
	local api = {}

	local frame = create("Frame", {
		Name = "RecruitScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 8, 14),
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 10,
		Parent = screen,
	})
	api.frame = frame
	local panel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1060, 620),
		BackgroundColor3 = Color3.fromRGB(22, 22, 30),
		BackgroundTransparency = 0.05,
		ZIndex = 10,
		Parent = frame,
	})
	api.panel = panel
	Theme.corner(panel, 14)
	Theme.border(panel, BLACK, 4)
	create("UIScale", { Name = "FitScale", Parent = panel })

	local title = outlined({
		Position = UDim2.fromOffset(28, 14),
		Size = UDim2.new(0.7, 0, 0, 46),
		Text = "CHOOSE YOUR UNIT",
		Font = Theme.Display,
		TextSize = 42,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = panel,
	}, 3)
	local subtitle = outlined({
		Position = UDim2.fromOffset(28, 60),
		Size = UDim2.new(0.7, 0, 0, 22),
		TextColor3 = Color3.fromRGB(200, 200, 215),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = panel,
	}, 1.5)
	local timerLabel = outlined({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 22),
		Size = UDim2.fromOffset(300, 30),
		TextSize = 22,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 11,
		Parent = panel,
	}, 2)

	local row = create("Frame", {
		Position = UDim2.fromOffset(28, 100),
		Size = UDim2.new(1, -56, 0, 260),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = panel,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 22),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local cards = {}
	for index, unitId in UnitDefinitions.Order do
		local card = UnitCard.new(row, unitId, "Blue", { layoutOrder = index })
		card.button.Activated:Connect(function()
			chooseRemote:FireServer(unitId)
		end)
		cards[unitId] = card
	end

	local function infoLine(y: number, color: Color3?): TextLabel
		return outlined({
			Position = UDim2.new(0, 28, 0, y),
			Size = UDim2.new(1, -330, 0, 40),
			TextSize = 17,
			TextColor3 = color or C.Text,
			TextWrapped = true,
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 11,
			Parent = panel,
		}, 1.5)
	end
	local chosenLabel = infoLine(385)
	local intelLabel = infoLine(432, Color3.fromRGB(255, 150, 140))
	local zonesLabel = infoLine(479, Color3.fromRGB(170, 215, 255))
	local noteLabel = infoLine(530, Color3.fromRGB(175, 175, 190))
	noteLabel.Text = "Units are free. The rest of your army is led by allied officers. "
		.. "★ Your unit earns a star each battle it survives (+8% HP and damage). Hover a card for its stats."

	local readyButton = Theme.tile({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -26),
		Size = UDim2.fromOffset(250, 70),
		ZIndex = 11,
		Parent = panel,
	})
	local readyGradient = readyButton:FindFirstChildOfClass("UIGradient") :: UIGradient
	Theme.border(readyButton, BLACK, 4)
	local readyLabel = outlined(
		{
			Size = UDim2.fromScale(1, 1),
			Text = "READY ✔",
			Font = Theme.Display,
			TextSize = 34,
			ZIndex = 12,
			Parent = readyButton,
		},
		3
	)
	readyButton.Activated:Connect(function()
		confirmRemote:FireServer()
	end)

	function api.onRecruit()
		local state = ClientState.recruit
		if not state then
			return
		end
		for _, unitId in UnitDefinitions.Order do
			local card = cards[unitId]
			local def = UnitDefinitions.get(unitId)
			local unlocked = state.unlocked[unitId] ~= false
			local chosen = state.chosen == unitId
			card:setStars((state.ranks and state.ranks[unitId]) or 0)
			card:setLocked(not unlocked, "🔒\nWin " .. tostring(def.unlockRoundsWon) .. " rounds")
			card:setSelected(chosen)
			card:setSubtitle(
				if chosen then "✔ SELECTED" else def.soldiers .. " soldiers",
				if chosen then C.Gold else nil
			)
			card:setValue(if chosen then "★" else "FREE")
		end
		local chosenDef = state.chosen and UnitDefinitions.get(state.chosen)
		chosenLabel.Text = if chosenDef
			then string.format(
				"<b>YOU COMMAND:</b> %s %s  (%d soldiers)",
				chosenDef.icon or "",
				chosenDef.displayName,
				chosenDef.soldiers
			)
			else "<b>Pick a unit to command.</b>"
		readyLabel.Text = if state.ready then "WAITING…" else "READY ✔"
		readyGradient.Color = if state.ready
			then ColorSequence.new(Color3.fromRGB(90, 90, 100), Color3.fromRGB(50, 50, 58))
			else ColorSequence.new(Color3.fromRGB(80, 210, 110), Color3.fromRGB(30, 130, 60))
	end

	local function refreshZones()
		local parts = {}
		for index, zone in ClientState.zones do
			table.insert(
				parts,
				string.format(
					"%s %s%s",
					string.char(64 + index),
					zone.name,
					if zone.bonus then " (+" .. zone.bonus .. ")" else ""
				)
			)
		end
		zonesLabel.Text = "<b>OBJECTIVES:</b> " .. (if #parts > 0 then table.concat(parts, "  ·  ") else "—")
	end
	api.onZones = refreshZones

	function api.onPhase(info: any)
		if info.phase ~= "Recruitment" then
			return
		end
		title.Text = "ROUND " .. info.round .. " — CHOOSE YOUR UNIT"
		subtitle.Text = if info.side == "Attacker"
			then "You ATTACK: capture every zone and hold it, or destroy the enemy."
			else "You DEFEND: destroy the attackers before they take every zone."
		local parts = {}
		for _, unitId in UnitDefinitions.Order do
			local n = info.enemyPreview and info.enemyPreview[unitId]
			if n then
				table.insert(parts, UnitDefinitions.get(unitId).displayName .. " ×" .. n)
			end
		end
		intelLabel.Text = "<b>ENEMY SCOUTED:</b> "
			.. table.concat(parts, ", ")
			.. (if info.bossName then "  ·  BOSS: " .. info.bossName else "")
		refreshZones()
		api.onRecruit()
	end

	function api.render()
		if frame.Visible and ClientState.phase then
			timerLabel.Text = "Battle in " .. Theme.formatTime(ClientState.phase.endsAt - Workspace:GetServerTimeNow())
		end
	end

	return api
end

return RecruitPanel

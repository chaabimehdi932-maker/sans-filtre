--[[
	DeployScreen — full-screen, shown ONLY during the deployment ("Recruitment") phase.
	Your whole roster marches to battle: one card per squad with its portrait, evolution stars,
	headcount and XP. Then the enemy scouting report, the objectives and READY.
	(Hiring and replenishing happen on the overworld, in your employer's towns.)
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
		Text = "DEPLOY YOUR ARMY",
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
	local cards: { [number]: any } = {}

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
	noteLabel.Text = "Squads wiped out in battle are lost forever. Survivors keep their casualties and earn XP: "
		.. "each ★ is an evolution tier (more HP, damage and morale, better kit). Hover a card for its stats."

	local readyButton = Theme.tile({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -26),
		Size = UDim2.fromOffset(250, 70),
		ZIndex = 11,
		Parent = panel,
	})
	local readyGradient = readyButton:FindFirstChildOfClass("UIGradient") :: UIGradient
	Theme.border(readyButton, BLACK, 4)
	local readyLabel = outlined({
		Size = UDim2.fromScale(1, 1),
		Text = "READY ✔",
		Font = Theme.Display,
		TextSize = 34,
		ZIndex = 12,
		Parent = readyButton,
	}, 3)
	readyButton.Activated:Connect(function()
		confirmRemote:FireServer()
	end)

	function api.onRecruit()
		local state = ClientState.recruit
		if not state or not state.roster then
			return
		end
		local seen = {}
		for index, entry in state.roster do
			seen[entry.id] = true
			local card = cards[entry.id]
			if card and card.def.id ~= entry.unitId then
				card:destroy()
				card = nil
			end
			if not card then
				card = UnitCard.new(row, entry.unitId, "Blue", { layoutOrder = index, compact = #state.roster > 5 })
				cards[entry.id] = card
			end
			card.button.LayoutOrder = index
			card:setName(entry.name)
			card:setStars(entry.stars)
			card:setSubtitle(
				if entry.nextXP
					then string.format("XP %d / %d", entry.xp, entry.nextXP)
					else "XP " .. entry.xp .. " · MAX",
				C.Gold
			)
			card:setValue(string.format("%d/%d", entry.soldiers, entry.maxSoldiers))
			card:setHealth(entry.soldiers / entry.maxSoldiers)
		end
		for id, card in cards do
			if not seen[id] then
				card:destroy()
				cards[id] = nil
			end
		end
		local total = 0
		for _, entry in state.roster do
			total += entry.soldiers
		end
		chosenLabel.Text = string.format(
			"<b>YOUR ARMY:</b> %d squad%s, %d soldiers. You command up to %d at once (reputation), the rest follow your officers.",
			#state.roster,
			if #state.roster == 1 then "" else "s",
			total,
			(game:GetService("Players").LocalPlayer:GetAttribute("MaxControlled") or 1) :: number
		)
		local phase = ClientState.phase
		if phase and phase.enlisted then
			chosenLabel.Text = string.format(
				"<b>YOU SERVE %s:</b> you lead one of his squads. Your own company stays safe in camp.",
				string.upper(phase.enlisted)
			)
		end
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
		title.Text = string.upper(info.title or "Battle")
		subtitle.Text = (if info.battlefield then "⛰ " .. info.battlefield .. "  —  " else "")
			.. (
				if info.side == "Attacker"
					then "You ATTACK: capture every zone and hold it, or destroy the enemy."
					else "You DEFEND: destroy the attackers before they take every zone."
			)
		local parts = {}
		local shown = table.clone(UnitDefinitions.Order)
		for _, unitId in UnitDefinitions.BanditOrder do
			table.insert(shown, unitId)
		end
		for _, unitId in shown do
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

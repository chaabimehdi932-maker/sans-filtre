--[[
	RecruitScreen — full-screen, shown ONLY during the Recruitment phase.
	One UnitCard per unit (portrait, rarity border, veteran stars, cost badge, stats tooltip),
	−/+ under each card, then your army, the enemy scouting report, the zones and their bonuses,
	and the Ready button. Purchases are requests: the server validates points, unlocks and the cap.
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

local requestRemote = Remotes.get("RequestRecruit")
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
		Size = UDim2.fromOffset(1020, 640),
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
		Size = UDim2.new(0.6, 0, 0, 46),
		Text = "RECRUITMENT",
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
	local pointsLabel = outlined({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 14),
		Size = UDim2.fromOffset(300, 44),
		Font = Theme.Display,
		TextSize = 36,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 11,
		Parent = panel,
	}, 3)
	local timerLabel = outlined({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 60),
		Size = UDim2.fromOffset(300, 22),
		TextSize = 17,
		TextColor3 = Color3.fromRGB(200, 200, 215),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 11,
		Parent = panel,
	}, 1.5)

	-- cards row
	local row = create("Frame", {
		Position = UDim2.fromOffset(28, 100),
		Size = UDim2.new(1, -56, 0, 290),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = panel,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local cards = {}
	for index, unitId in UnitDefinitions.Order do
		local column = create("Frame", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(172, 290),
			BackgroundTransparency = 1,
			ZIndex = 11,
			Parent = row,
		})
		local card = UnitCard.new(column, unitId, "Blue", {})
		card.button.Position = UDim2.fromOffset(0, 8)
		local function stepButton(label: string, x: number, color: Color3, delta: number): TextButton
			local button = Theme.tile({
				Position = UDim2.new(0, x, 1, -42),
				Size = UDim2.fromOffset(80, 40),
				ZIndex = 12,
				Parent = column,
			})
			local gradient = button:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = ColorSequence.new(color, color:Lerp(BLACK, 0.4))
			end
			Theme.border(button, BLACK, 3)
			outlined(
				{
					Size = UDim2.fromScale(1, 1),
					Text = label,
					Font = Theme.Bold,
					TextSize = 28,
					ZIndex = 13,
					Parent = button,
				},
				2
			)
			button.Activated:Connect(function()
				requestRemote:FireServer(unitId, delta)
			end)
			return button
		end
		stepButton("−", 0, Color3.fromRGB(190, 55, 55), -1)
		local plus = stepButton("+", 92, Color3.fromRGB(55, 170, 80), 1)
		card.button.Activated:Connect(function()
			requestRemote:FireServer(unitId, 1) -- clicking the card also recruits one
		end)
		cards[unitId] = { card = card, plus = plus, def = UnitDefinitions.get(unitId) }
	end

	-- info lines
	local function infoLine(y: number, color: Color3?): TextLabel
		return outlined({
			Position = UDim2.new(0, 28, 0, y),
			Size = UDim2.new(1, -330, 0, 40),
			TextSize = 16,
			TextColor3 = color or C.Text,
			TextWrapped = true,
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 11,
			Parent = panel,
		}, 1.5)
	end
	local armyLabel = infoLine(410)
	local intelLabel = infoLine(456, Color3.fromRGB(255, 150, 140))
	local zonesLabel = infoLine(502, Color3.fromRGB(170, 215, 255))
	local noteLabel = infoLine(560, Color3.fromRGB(175, 175, 190))
	noteLabel.Text =
		"★ Veterans survived earlier battles: +8% HP and damage per star. Removing a new unit refunds it. Hover a card for its stats."

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
		pointsLabel.Text = "💰 " .. state.points
		local counts, bestRank, veterans = {}, {}, {}
		for _, entry in state.roster do
			counts[entry.unitId] = (counts[entry.unitId] or 0) + 1
			bestRank[entry.unitId] = math.max(bestRank[entry.unitId] or 0, entry.rank or 0)
			if entry.carried then
				veterans[entry.unitId] = (veterans[entry.unitId] or 0) + 1
			end
		end
		local parts = {}
		for _, unitId in UnitDefinitions.Order do
			local entry = cards[unitId]
			local n = counts[unitId] or 0
			local unlocked = state.unlocked[unitId] ~= false
			entry.card:setCount(n)
			entry.card:setStars(bestRank[unitId] or 0)
			entry.card:setSubtitle(if n > 0 then n .. " in your army" else "")
			entry.card:setLocked(not unlocked, "🔒\nWin " .. tostring(entry.def.unlockRoundsWon) .. " rounds")
			local affordable = unlocked and state.points >= entry.def.cost and #state.roster < state.maxSquads
			entry.plus.BackgroundTransparency = if affordable then 0 else 0.5
			if n > 0 then
				local vet = veterans[unitId] or 0
				table.insert(
					parts,
					string.format("%s ×%d%s", entry.def.displayName, n, if vet > 0 then " (" .. vet .. "★)" else "")
				)
			end
		end
		armyLabel.Text = string.format(
			"<b>YOUR ARMY (%d/%d):</b> %s",
			#state.roster,
			state.maxSquads,
			if #parts > 0 then table.concat(parts, ", ") else "nobody yet: pick some units!"
		)
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
		title.Text = "RECRUITMENT — ROUND " .. info.round
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
			timerLabel.Text = "Battle starts in "
				.. Theme.formatTime(ClientState.phase.endsAt - Workspace:GetServerTimeNow())
		end
	end

	return api
end

return RecruitPanel

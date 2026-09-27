--[[
	RecruitPanel: shown during the Recruitment phase.
	Unit cards (name, cost, stats, +/-), current army, enemy scouting report, Ready button.
	All purchases are requests; the server validates points, unlocks and the squad cap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Remotes = require(Modules:WaitForChild("Remotes"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local create, text = Theme.create, Theme.text

local requestRemote = Remotes.get("RequestRecruit")
local confirmRemote = Remotes.get("ConfirmRecruit")

local RecruitPanel = {}

local function statsText(def: any): string
	local lines = { "HP " .. def.health, "Speed " .. def.moveSpeed }
	if def.attackType == "Melee" then
		table.insert(lines, string.format("Melee %d (charge ×%g)", def.meleeDamage, def.chargeMultiplier))
	else
		table.insert(lines, "Damage " .. def.damage)
		table.insert(lines, "Range " .. def.attackRange)
		table.insert(lines, "Reload " .. def.attackCooldown .. "s")
	end
	table.insert(lines, "Morale " .. def.morale)
	table.insert(lines, "Formations: " .. table.concat(def.formations, ", "))
	return table.concat(lines, "\n")
end

function RecruitPanel.build(root: ScreenGui, ClientState: any): any
	local api = {}

	local panel = create("Frame", {
		Name = "RecruitPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(1000, 600),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	Theme.corner(panel, 12)
	Theme.border(panel, Color3.new(0, 0, 0), 3)

	local title = text({
		Position = UDim2.fromOffset(24, 12),
		Size = UDim2.new(0.6, 0, 0, 44),
		Text = "RECRUITMENT",
		Font = Theme.Display,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = panel,
	})
	Theme.stroke(title, Color3.new(0, 0, 0), 2)
	local subtitle = text({
		Position = UDim2.fromOffset(24, 56),
		Size = UDim2.new(0.7, 0, 0, 22),
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = panel,
	})
	local pointsLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 12),
		Size = UDim2.fromOffset(300, 40),
		Font = Theme.Display,
		TextSize = 34,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 11,
		Parent = panel,
	})
	Theme.stroke(pointsLabel, Color3.new(0, 0, 0), 2)
	local timerLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 54),
		Size = UDim2.fromOffset(300, 22),
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 11,
		Parent = panel,
	})

	local grid = create("Frame", {
		Position = UDim2.fromOffset(24, 92),
		Size = UDim2.new(1, -48, 0, 330),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = panel,
	})
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(182, 330),
		CellPadding = UDim2.fromOffset(9, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	local cards = {}
	for index, unitId in UnitDefinitions.Order do
		local def = UnitDefinitions.get(unitId)
		local card = create("Frame", { LayoutOrder = index, BackgroundColor3 = C.Slot, ZIndex = 11, Parent = grid })
		Theme.corner(card, 8)
		local stroke = Theme.border(card, Color3.new(0, 0, 0), 2)
		text({
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 22),
			Text = (def.icon or "") .. "  " .. def.displayName,
			Font = Theme.Bold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
			Parent = card,
		})
		text({
			Position = UDim2.fromOffset(10, 32),
			Size = UDim2.new(1, -20, 0, 20),
			Text = "💰 " .. def.cost .. " pts",
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
			Parent = card,
		})
		text({
			Position = UDim2.fromOffset(10, 58),
			Size = UDim2.new(1, -20, 0, 128),
			Text = statsText(def),
			Font = Theme.Body,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 12,
			Parent = card,
		})
		text({
			Position = UDim2.fromOffset(10, 190),
			Size = UDim2.new(1, -20, 0, 80),
			Text = def.description,
			Font = Theme.Body,
			TextSize = 13,
			TextColor3 = C.Muted,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 12,
			Parent = card,
		})
		local minus = create("TextButton", {
			Position = UDim2.new(0, 10, 1, -48),
			Size = UDim2.fromOffset(44, 38),
			BackgroundColor3 = Color3.fromRGB(150, 45, 45),
			Text = "−",
			Font = Theme.Bold,
			TextSize = 26,
			TextColor3 = C.Text,
			ZIndex = 12,
			Parent = card,
		})
		Theme.corner(minus, 6)
		local count = text({
			Position = UDim2.new(0, 56, 1, -48),
			Size = UDim2.new(1, -112, 0, 38),
			Text = "0",
			Font = Theme.Display,
			TextSize = 28,
			ZIndex = 12,
			Parent = card,
		})
		local plus = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 1, -48),
			Size = UDim2.fromOffset(44, 38),
			BackgroundColor3 = Color3.fromRGB(45, 150, 70),
			Text = "+",
			Font = Theme.Bold,
			TextSize = 26,
			TextColor3 = C.Text,
			ZIndex = 12,
			Parent = card,
		})
		Theme.corner(plus, 6)
		local lock = create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			Text = "🔒\nWin " .. tostring(def.unlockRoundsWon) .. " rounds\nto unlock",
			Font = Theme.Bold,
			TextSize = 18,
			TextColor3 = C.Text,
			Visible = false,
			ZIndex = 14,
			Parent = card,
		})
		Theme.corner(lock, 8)
		minus.Activated:Connect(function()
			requestRemote:FireServer(unitId, -1)
		end)
		plus.Activated:Connect(function()
			requestRemote:FireServer(unitId, 1)
		end)
		cards[unitId] = { card = card, stroke = stroke, count = count, lock = lock, plus = plus, def = def }
	end

	local armyLabel = text({
		Position = UDim2.new(0, 24, 1, -164),
		Size = UDim2.new(1, -300, 0, 44),
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 11,
		Parent = panel,
	})
	local intelLabel = text({
		Position = UDim2.new(0, 24, 1, -112),
		Size = UDim2.new(1, -300, 0, 44),
		TextSize = 15,
		TextColor3 = Color3.fromRGB(255, 140, 130),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 11,
		Parent = panel,
	})
	text({
		Position = UDim2.new(0, 24, 1, -58),
		Size = UDim2.new(1, -300, 0, 40),
		Text = "Veterans (★) survived the last battle and stay in your army. Removing a new unit refunds it.",
		Font = Theme.Body,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = panel,
	})
	local readyButton = create("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -20),
		Size = UDim2.fromOffset(240, 64),
		BackgroundColor3 = C.Green,
		Text = "READY ✔",
		Font = Theme.Display,
		TextSize = 32,
		TextColor3 = C.Text,
		ZIndex = 11,
		Parent = panel,
	})
	Theme.corner(readyButton, 10)
	Theme.border(readyButton, Color3.new(0, 0, 0), 3)
	readyButton.Activated:Connect(function()
		confirmRemote:FireServer()
	end)

	function api.onRecruit()
		local state = ClientState.recruit
		if not state then
			return
		end
		pointsLabel.Text = "💰 " .. state.points .. " pts"
		local counts, veterans = {}, {}
		for _, entry in state.roster do
			counts[entry.unitId] = (counts[entry.unitId] or 0) + 1
			if entry.carried then
				veterans[entry.unitId] = (veterans[entry.unitId] or 0) + 1
			end
		end
		local parts = {}
		for _, unitId in UnitDefinitions.Order do
			local card = cards[unitId]
			local n = counts[unitId] or 0
			local unlocked = state.unlocked[unitId] ~= false
			card.count.Text = tostring(n)
			card.lock.Visible = not unlocked
			local affordable = state.points >= card.def.cost and #state.roster < state.maxSquads
			card.plus.BackgroundColor3 = if affordable and unlocked
				then Color3.fromRGB(45, 150, 70)
				else Color3.fromRGB(70, 70, 75)
			card.stroke.Color = if n > 0 then C.Gold else Color3.new(0, 0, 0)
			if n > 0 then
				local vet = veterans[unitId] or 0
				table.insert(
					parts,
					string.format("%s ×%d%s", card.def.displayName, n, if vet > 0 then " (" .. vet .. "★)" else "")
				)
			end
		end
		armyLabel.Text = string.format(
			"YOUR ARMY (%d/%d): %s",
			#state.roster,
			state.maxSquads,
			if #parts > 0 then table.concat(parts, ", ") else "nobody yet: pick some units!"
		)
		readyButton.Text = if state.ready then "WAITING…" else "READY ✔"
		readyButton.BackgroundColor3 = if state.ready then Color3.fromRGB(80, 80, 85) else C.Green
	end

	function api.onPhase(info: any)
		panel.Visible = info.phase == "Recruitment"
		if not panel.Visible then
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
		intelLabel.Text = "ENEMY SCOUTED: "
			.. table.concat(parts, ", ")
			.. (if info.bossName then "  ·  BOSS: " .. info.bossName else "")
		api.onRecruit()
	end

	function api.render()
		if panel.Visible and ClientState.phase then
			timerLabel.Text = "Battle starts in "
				.. Theme.formatTime(ClientState.phase.endsAt - Workspace:GetServerTimeNow())
		end
	end

	return api
end

return RecruitPanel

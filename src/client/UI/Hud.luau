--[[
	Battle HUD (all inside PlayerGui.MainHUD):
	  ObjectiveBanner (top-centre) · TopBar timer + hold progress · OrdersColumn (left, X/C/V/B)
	  + formation buttons · SquadPanel (right) · CombatHotbar + HealthBar (bottom-centre)
	  · CharacterCard (bottom-left) · XPBar (bottom, full width) · Notifications
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local create, text = Theme.create, Theme.text
local player = Players.LocalPlayer

local Hud = {}

local PHASE_NAMES = { Waiting = "WAITING", Recruitment = "RECRUITMENT", Battle = "BATTLE", Reward = "RESULTS" }
local STATE_COLORS = {
	Idle = C.Muted,
	Advancing = Color3.fromRGB(140, 200, 255),
	Engaging = Color3.fromRGB(255, 150, 80),
	Routing = Color3.fromRGB(255, 70, 70),
	Regrouping = Color3.fromRGB(255, 220, 120),
}

function Hud.build(root: ScreenGui, ClientState: any, ClientActions: any): any
	local api = {}

	local function shiftHeld(): boolean
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	local function keyBadge(parent: Instance, key: string, color: Color3, position: UDim2, anchor: Vector2)
		local badge = create("Frame", {
			Name = "Key",
			Size = UDim2.fromOffset(24, 24),
			Position = position,
			AnchorPoint = anchor,
			BackgroundColor3 = color,
			ZIndex = 3,
			Parent = parent,
		})
		Theme.corner(badge, 4)
		Theme.border(badge, Color3.new(0, 0, 0), 2)
		text({ Size = UDim2.fromScale(1, 1), Text = key, Font = Theme.Bold, TextSize = 14, ZIndex = 4, Parent = badge })
	end

	---------------------------------------------------------------- banner
	local banner = create("Frame", {
		Name = "ObjectiveBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(1000, 180),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	local sideLabel = text({
		Name = "Side",
		Size = UDim2.new(1, 0, 0, 110),
		Font = Theme.Display,
		TextSize = 104,
		TextColor3 = C.Red,
		Parent = banner,
	})
	local sideStroke = Theme.stroke(sideLabel, Color3.new(0, 0, 0), 5)
	local objectiveLabel = text({
		Name = "Objective",
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 0, 64),
		Font = Theme.Display,
		TextSize = 60,
		Parent = banner,
	})
	local objectiveStroke = Theme.stroke(objectiveLabel, Color3.new(0, 0, 0), 4)
	local bannerToken = 0

	local function setBannerTransparency(value: number, duration: number)
		local info = TweenInfo.new(duration)
		for _, target in { sideLabel, objectiveLabel } do
			TweenService:Create(target, info, { TextTransparency = value }):Play()
		end
		for _, target in { sideStroke, objectiveStroke } do
			TweenService:Create(target, info, { Transparency = value }):Play()
		end
	end

	function api.showBanner(side: string, objective: string, color: Color3)
		bannerToken += 1
		local token = bannerToken
		sideLabel.Text = side
		sideLabel.TextColor3 = color
		objectiveLabel.Text = objective
		sideLabel.TextTransparency, objectiveLabel.TextTransparency = 1, 1
		sideStroke.Transparency, objectiveStroke.Transparency = 1, 1
		banner.Visible = true
		setBannerTransparency(0, 0.35)
		task.delay(4, function()
			if token == bannerToken then
				setBannerTransparency(1, 0.8)
				task.delay(0.85, function()
					if token == bannerToken then
						banner.Visible = false
					end
				end)
			end
		end)
	end

	---------------------------------------------------------------- top bar
	local topBar = create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(380, 34),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
		Parent = root,
	})
	Theme.corner(topBar, 8)
	local topLabel = text({ Size = UDim2.fromScale(1, 1), Font = Theme.Bold, TextSize = 17, Parent = topBar })
	local holdBack, holdFill = Theme.bar({
		Name = "HoldBar",
		Position = UDim2.new(0, 0, 1, 6),
		Size = UDim2.new(1, 0, 0, 20),
		Visible = false,
		Parent = topBar,
	}, C.Blue)
	Theme.corner(holdBack, 6)
	Theme.corner(holdFill, 6)
	local holdLabel = text({ Size = UDim2.fromScale(1, 1), TextSize = 13, ZIndex = 2, Parent = holdBack })

	---------------------------------------------------------------- orders column (left)
	local orders = create("Frame", {
		Name = "OrdersColumn",
		Position = UDim2.new(0, 12, 0, 110),
		Size = UDim2.fromOffset(92, 520),
		BackgroundTransparency = 1,
		Parent = root,
	})
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = orders })

	local ORDER_DEFS = {
		{ name = "Hold", key = "X", icon = "🛡️", color = C.KeyRed },
		{ name = "Follow", key = "C", icon = "🏃", color = C.KeyRed },
		{ name = "Attack", key = "V", icon = "⚔️", color = C.KeyRed },
		{ name = "Rush", key = "B", icon = "⏫", color = C.KeyBlue },
	}
	local orderButtons = {}
	for i, def in ORDER_DEFS do
		local button = create("TextButton", {
			Name = def.name,
			LayoutOrder = i,
			Size = UDim2.fromOffset(92, 84),
			BackgroundColor3 = C.Slot,
			AutoButtonColor = true,
			Text = "",
			Parent = orders,
		})
		Theme.corner(button, 6)
		local stroke = Theme.border(button, C.SlotStroke, 2)
		text({
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 44),
			Text = def.icon,
			TextSize = 36,
			Parent = button,
		})
		local title = text({
			Position = UDim2.new(0, 0, 1, -26),
			Size = UDim2.new(1, 0, 0, 22),
			Text = string.upper(def.name),
			Font = Theme.Bold,
			TextSize = 15,
			Parent = button,
		})
		Theme.stroke(title, Color3.new(0, 0, 0), 1.5)
		keyBadge(button, def.key, def.color, UDim2.fromOffset(-6, -6), Vector2.zero)
		button.Activated:Connect(function()
			ClientActions.order(def.name)
		end)
		orderButtons[def.name] = { button = button, stroke = stroke }
	end

	local FORMATION_DEFS =
		{ { name = "Line", key = "1" }, { name = "Column", key = "2" }, { name = "Square", key = "3" } }
	local formationButtons = {}
	for i, def in FORMATION_DEFS do
		local button = create("TextButton", {
			Name = def.name,
			LayoutOrder = 10 + i,
			Size = UDim2.fromOffset(92, 28),
			BackgroundColor3 = C.Slot,
			Text = def.key .. "  " .. string.upper(def.name),
			Font = Theme.Semi,
			TextSize = 13,
			TextColor3 = C.Text,
			Parent = orders,
		})
		Theme.corner(button, 6)
		local stroke = Theme.border(button, C.SlotStroke, 2)
		button.Activated:Connect(function()
			ClientActions.formation(def.name)
		end)
		formationButtons[def.name] = { button = button, stroke = stroke }
	end
	text({
		LayoutOrder = 20,
		Size = UDim2.fromOffset(150, 110),
		Text = "1-9 select squad\nShift+1-9 add/remove\n0 select all · T next\nCtrl+drag box select\nX then 1/2/3 formation\nRight drag camera\nAlt mouse-look",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 12,
		TextColor3 = C.Muted,
		TextStrokeTransparency = 0.5,
		Parent = orders,
	})

	local function flash(button: GuiObject)
		button.BackgroundColor3 = C.Gold
		TweenService:Create(button, TweenInfo.new(0.35), { BackgroundColor3 = C.Slot }):Play()
	end

	-- Formation prompt shown after X (Hold): 1 / 2 / 3 pick the formation
	local prompt = create("Frame", {
		Name = "FormationPrompt",
		Position = UDim2.new(0, 112, 0, 110),
		Size = UDim2.fromOffset(340, 84),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = root,
	})
	Theme.corner(prompt, 8)
	Theme.border(prompt, C.Gold, 2)
	text({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "HOLD · CHOOSE A FORMATION",
		Font = Theme.Bold,
		TextSize = 14,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = prompt,
	})
	for i, def in FORMATION_DEFS do
		local option = create("TextButton", {
			Position = UDim2.fromOffset(12 + (i - 1) * 108, 30),
			Size = UDim2.fromOffset(100, 36),
			BackgroundColor3 = C.Slot,
			Text = def.key .. "  " .. string.upper(def.name),
			Font = Theme.Bold,
			TextSize = 14,
			TextColor3 = C.Text,
			Parent = prompt,
		})
		Theme.corner(option, 6)
		Theme.border(option, Color3.new(0, 0, 0), 2)
		option.Activated:Connect(function()
			ClientActions.formation(def.name)
		end)
	end
	local _, promptFill =
		Theme.bar({ Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 4), Parent = prompt }, C.Gold)

	ClientActions.Changed:Connect(function(what, value)
		if what == "Order" and orderButtons[value] then
			flash(orderButtons[value].button)
		elseif what == "Formation" and formationButtons[value] then
			flash(formationButtons[value].button)
		end
	end)

	---------------------------------------------------------------- squad panel (right)
	local squadPanel = create("Frame", {
		Name = "SquadPanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 214),
		Size = UDim2.fromOffset(230, 30),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.3,
		Parent = root,
	})
	Theme.corner(squadPanel, 8)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		Parent = squadPanel,
	})
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = squadPanel })
	text({
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 18),
		Text = "YOUR ARMY",
		Font = Theme.Bold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = squadPanel,
	})
	local squadRows = {}

	local function squadRow(index: number): any
		local row = squadRows[index]
		if row then
			return row
		end
		local button = create("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = C.Slot,
			Text = "",
			AutoButtonColor = true,
			Parent = squadPanel,
		})
		Theme.corner(button, 6)
		local stroke = Theme.border(button, Color3.new(1, 1, 1), 2)
		local key = text({
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.fromOffset(16, 16),
			Text = tostring(index),
			Font = Theme.Bold,
			TextSize = 12,
			BackgroundColor3 = C.KeyRed,
			BackgroundTransparency = 0,
			Parent = button,
		})
		Theme.corner(key, 3)
		local name = text({
			Position = UDim2.fromOffset(24, 2),
			Size = UDim2.new(0.6, -24, 0, 16),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		})
		local state = text({
			Position = UDim2.new(0.6, 0, 0, 2),
			Size = UDim2.new(0.4, -6, 0, 16),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = button,
		})
		local _, hp =
			Theme.bar({ Position = UDim2.fromOffset(6, 21), Size = UDim2.new(1, -12, 0, 6), Parent = button }, C.Health)
		local _, morale =
			Theme.bar({ Position = UDim2.fromOffset(6, 29), Size = UDim2.new(1, -12, 0, 4), Parent = button }, C.Morale)
		row = {
			button = button,
			stroke = stroke,
			name = name,
			state = state,
			hp = hp,
			morale = morale,
			id = 0,
			key = key,
		}
		button.Activated:Connect(function()
			if shiftHeld() then
				ClientActions.toggleSelected(row.id)
			else
				ClientActions.setSelection({ row.id })
			end
		end)
		squadRows[index] = row
		return row
	end

	function api.onSquads()
		local mine = ClientState.mySquads()
		local selectedSquads = {}
		for i, squad in mine do
			local row = squadRow(i)
			row.id = squad.id
			row.button.Visible = true
			row.name.Text = squad.name
			row.state.Text = if squad.forming then "Forming…" else string.upper(squad.state)
			row.state.TextColor3 = STATE_COLORS[squad.state] or C.Muted
			row.hp.Size = UDim2.fromScale(squad.hp, 1)
			row.morale.Size = UDim2.fromScale(squad.morale, 1)
			local isSelected = ClientActions.isSelected(squad.id)
			row.stroke.Transparency = if isSelected then 0 else 1
			row.stroke.Color = C.Gold
			row.key.Visible = i <= 9
			if isSelected then
				table.insert(selectedSquads, squad)
			end
		end
		for i = #mine + 1, #squadRows do
			squadRows[i].button.Visible = false
		end
		squadPanel.Visible = #mine > 0

		-- Highlight the order / formation shared by every selected squad
		local function shared(field: string): string?
			local value = nil
			for _, squad in selectedSquads do
				if value == nil then
					value = squad[field]
				elseif value ~= squad[field] then
					return nil
				end
			end
			return value
		end
		local order, formation = shared("order"), shared("formation")
		for name, entry in orderButtons do
			local active = order == name
			entry.stroke.Color = if active then C.Gold else C.SlotStroke
			entry.stroke.Thickness = if active then 3 else 2
		end
		for name, entry in formationButtons do
			entry.stroke.Color = if formation == name then C.Gold else C.SlotStroke
		end
		api.refreshArmyCount()
	end

	---------------------------------------------------------------- hotbar + health
	local hotbar = create("Frame", {
		Name = "CombatHotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(520, 96),
		BackgroundTransparency = 1,
		Parent = root,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = hotbar,
	})
	local HOTBAR_DEFS = {
		{ action = "Attack", title = "ATTACK", icon = "⚔️", key = "M1", color = C.KeyRed },
		{ action = "Block", title = "BLOCK", icon = "🛡️", key = "F", color = C.KeyRed },
		{ action = "Roll", title = "ROLL", icon = "💨", key = "Q", color = C.KeyRed },
		{ action = "Heal", title = "HEAL", icon = "✚", key = "H", color = C.KeyBlue },
		{ action = "Mount", title = "MOUNT", icon = "🐎", key = "G", color = C.KeyOrange },
	}
	local slots = {}
	for i, def in HOTBAR_DEFS do
		local button = create("TextButton", {
			Name = def.action,
			LayoutOrder = i,
			Size = UDim2.fromOffset(92, 92),
			BackgroundColor3 = C.Slot,
			Text = "",
			AutoButtonColor = true,
			Parent = hotbar,
		})
		Theme.corner(button, 6)
		local stroke = Theme.border(button, C.SlotStroke, 3)
		local title = text({
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 18),
			Text = def.title,
			Font = Theme.Bold,
			TextSize = 15,
			Parent = button,
		})
		Theme.stroke(title, Color3.new(0, 0, 0), 1.5)
		text({
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 54),
			Text = def.icon,
			TextSize = 42,
			TextColor3 = if def.action == "Heal" then Color3.fromRGB(190, 255, 60) else C.Text,
			Parent = button,
		})
		local overlay = create("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = button,
		})
		Theme.corner(overlay, 6)
		keyBadge(button, def.key, def.color, UDim2.new(1, 6, 1, 6), Vector2.new(1, 1))
		slots[def.action] = { button = button, stroke = stroke, overlay = overlay, title = title }
	end
	slots.Attack.button.Activated:Connect(ClientActions.attack)
	slots.Roll.button.Activated:Connect(ClientActions.roll)
	slots.Heal.button.Activated:Connect(ClientActions.heal)
	slots.Mount.button.Activated:Connect(ClientActions.toggleMount)
	slots.Block.button.MouseButton1Down:Connect(function()
		ClientActions.setBlock(true)
	end)
	slots.Block.button.MouseButton1Up:Connect(function()
		ClientActions.setBlock(false)
	end)
	slots.Block.button.MouseLeave:Connect(function()
		ClientActions.setBlock(false)
	end)

	local health = create("Frame", {
		Name = "HealthBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -138),
		Size = UDim2.fromOffset(540, 30),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local hpBack, hpFill =
		Theme.bar({ Position = UDim2.fromOffset(24, 4), Size = UDim2.new(1, -24, 0, 22), Parent = health }, C.Health)
	Theme.border(hpBack, Color3.new(0, 0, 0), 2)
	for i = 1, 7 do
		create("Frame", {
			Position = UDim2.new(i / 8, 0, 0, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = hpBack,
		})
	end
	local hpText = text({ Size = UDim2.fromScale(1, 1), TextSize = 13, ZIndex = 3, Parent = hpBack })
	Theme.stroke(hpText, Color3.new(0, 0, 0), 1)
	local heart = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(18, 15),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = C.Health,
		ZIndex = 4,
		Parent = health,
	})
	Theme.round(heart)
	Theme.border(heart, Color3.new(0, 0, 0), 3)
	text({ Size = UDim2.fromScale(1, 1), Text = "❤", TextSize = 26, ZIndex = 5, Parent = heart })

	---------------------------------------------------------------- character card (bottom-left)
	local card = create("Frame", {
		Name = "CharacterCard",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -28),
		Size = UDim2.fromOffset(176, 236),
		BackgroundColor3 = C.Card,
		Parent = root,
	})
	Theme.corner(card, 8)
	Theme.border(card, Color3.fromRGB(20, 10, 40), 3)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 80, 220), Color3.fromRGB(55, 25, 120)),
		Rotation = 90,
		Parent = card,
	})
	local rankLabel = text({
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(0.6, 0, 0, 22),
		Text = "Commander",
		Font = Theme.Bold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Theme.stroke(rankLabel, Color3.new(0, 0, 0), 1.5)
	local levelLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.new(0.4, 0, 0, 22),
		Text = "LVL 1",
		Font = Theme.Bold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	Theme.stroke(levelLabel, Color3.new(0, 0, 0), 1.5)
	local portrait = create("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
		Parent = card,
	})
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok then
			portrait.Image = image
		end
	end)
	local armyLabel = text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -8),
		Size = UDim2.new(1, -20, 0, 26),
		Text = "0/8",
		Font = Theme.Display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	Theme.stroke(armyLabel, Color3.new(0, 0, 0), 2)
	text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(0.5, 0, 0, 20),
		Text = "Squads",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	function api.refreshArmyCount()
		local max = if ClientState.recruit then ClientState.recruit.maxSquads else 8
		armyLabel.Text = string.format("%d/%d", #ClientState.mySquads(), max)
	end

	---------------------------------------------------------------- XP bar (bottom)
	local xpBack, xpFill = Theme.bar({
		Name = "XPBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = root,
	}, C.Gold)
	Theme.border(xpBack, Color3.new(0, 0, 0), 2)
	local xpLevel = text({
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(0, 120, 1, 0),
		Text = "Level 1",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = xpBack,
	})
	Theme.stroke(xpLevel, Color3.new(0, 0, 0), 1)
	local xpText = text({ Size = UDim2.fromScale(1, 1), Text = "0/100", TextSize = 13, ZIndex = 2, Parent = xpBack })
	Theme.stroke(xpText, Color3.new(0, 0, 0), 1)

	function api.onProgress(progress: any)
		levelLabel.Text = "LVL " .. progress.level
		xpLevel.Text = "Level " .. progress.level
		xpText.Text = string.format("%d/%d", progress.xp, progress.xpNext)
		xpFill.Size = UDim2.fromScale(math.clamp(progress.xp / math.max(1, progress.xpNext), 0, 1), 1)
	end

	---------------------------------------------------------------- notifications
	local notifications = create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -180),
		Size = UDim2.fromOffset(600, 130),
		BackgroundTransparency = 1,
		Parent = root,
	})
	create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = notifications,
	})
	local toastOrder = 0
	local TONES = { good = Color3.fromRGB(120, 230, 130), bad = Color3.fromRGB(255, 110, 100), info = C.Text }

	function api.notify(message: string, tone: string?)
		toastOrder += 1
		local toast = text({
			LayoutOrder = toastOrder,
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.3,
			Text = "  " .. message .. "  ",
			TextSize = 16,
			TextColor3 = TONES[tone or "info"] or C.Text,
			Parent = notifications,
		})
		Theme.corner(toast, 6)
		local children = notifications:GetChildren()
		if #children > 6 then
			for _, child in children do
				if child:IsA("TextLabel") and child.LayoutOrder <= toastOrder - 5 then
					child:Destroy()
				end
			end
		end
		task.delay(3.5, function()
			if toast.Parent then
				TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
					:Play()
				task.delay(0.5, function()
					toast:Destroy()
				end)
			end
		end)
	end

	---------------------------------------------------------------- phase + per-frame
	function api.onPhase(info: any)
		if info.banner and info.phase == "Battle" then
			local color = if info.side == "Attacker" then C.Red else C.Blue
			api.showBanner(string.upper(info.side or ""), info.objective or "", color)
		end
		local inBattle = info.phase == "Battle"
		hotbar.Visible = inBattle
		health.Visible = inBattle
		orders.Visible = inBattle
	end
	hotbar.Visible, health.Visible, orders.Visible = false, false, false

	function api.render()
		local info = ClientState.phase
		if info then
			local remaining = info.endsAt - Workspace:GetServerTimeNow()
			topLabel.Text = string.format(
				"ROUND %d  ·  %s  ·  %s",
				info.round or 1,
				PHASE_NAMES[info.phase] or info.phase,
				Theme.formatTime(remaining)
			)
		else
			topLabel.Text = "Waiting for the server…"
		end

		local hold = ClientState.hold
		holdBack.Visible = hold ~= nil
		if hold then
			holdFill.Size = UDim2.fromScale(hold.progress, 1)
			holdFill.BackgroundColor3 = if hold.team == "Blue" then C.Blue else C.Red
			holdLabel.Text = if hold.team == "Blue" then "HOLDING ALL ZONES" else "ENEMY HOLDS ALL ZONES!"
		end

		local promptLeft = ClientActions.formationPrompt()
		prompt.Visible = promptLeft > 0 and orders.Visible
		promptFill.Size = UDim2.fromScale(promptLeft, 1)

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local fraction = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
			hpFill.Size = UDim2.fromScale(fraction, 1)
			hpText.Text = string.format("%d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth)
		end

		for action, slot in slots do
			slot.overlay.Size = UDim2.fromScale(1, ClientActions.cooldownFraction(action))
		end
		local mounted = ClientActions.isMounted()
		slots.Mount.title.Text = if mounted then "DISMOUNT" else "MOUNT"
		slots.Mount.stroke.Color = if mounted then C.Gold else C.SlotStroke
		slots.Block.stroke.Color = if ClientActions.blocking then C.Gold else C.SlotStroke
		slots.Roll.button.BackgroundColor3 = if mounted then Color3.fromRGB(18, 18, 20) else C.Slot
	end

	return api
end

return Hud

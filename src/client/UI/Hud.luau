--[[
	Battle HUD (everything lives in PlayerGui.MainHUD):
	  TopBar: big timer, round/phase, objective line, hold-all-zones progress
	  ObjectiveBanner: "ATTACKER / CAPTURE PLAINS" at round start and when the objective changes
	  OrdersColumn (left): Hold X · Follow C · Attack V · Rush B, formation picks 1/2/3 beside Hold
	  ArmyList (right): your squads, number keys, health, selection
	  CombatHotbar + HealthBar (bottom-centre), CharacterCard (bottom-left), XPBar (bottom)
	  XP popups, notifications, F1 controls panel
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FormationDefinitions = require(Modules:WaitForChild("FormationDefinitions"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local create, text, outlined = Theme.create, Theme.text, Theme.outlined
local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)

local Hud = {}

local PHASE_NAMES = { Waiting = "WAITING", Recruitment = "RECRUITMENT", Battle = "BATTLE", Reward = "RESULTS" }
local STATE_COLORS = {
	Idle = Color3.fromRGB(170, 170, 185),
	Advancing = Color3.fromRGB(140, 200, 255),
	Engaging = Color3.fromRGB(255, 150, 80),
	Routing = Color3.fromRGB(255, 70, 70),
	Regrouping = Color3.fromRGB(255, 220, 120),
}

-- Draws a formation as little dots (used for the 1/2/3 formation buttons)
local function formationIcon(parent: GuiObject, formation: string)
	local slots = FormationDefinitions.layout(formation, 12, 1)
	local maxExtent = 0.1
	for _, slot in slots do
		maxExtent = math.max(maxExtent, math.abs(slot.X), math.abs(slot.Z))
	end
	for _, slot in slots do
		local dot = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + slot.X / maxExtent * 0.36, 0.5 + slot.Z / maxExtent * 0.36),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 3,
			Parent = parent,
		})
		Theme.round(dot)
	end
end

function Hud.build(root: ScreenGui, ClientState: any, ClientActions: any): any
	local api = {}

	local function shiftHeld(): boolean
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	---------------------------------------------------------------- objective banner
	local banner = create("Frame", {
		Name = "ObjectiveBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.18),
		Size = UDim2.fromOffset(1000, 180),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	local sideLabel = text({
		Size = UDim2.new(1, 0, 0, 110),
		Font = Theme.Display,
		TextSize = 108,
		TextColor3 = C.Red,
		Parent = banner,
	})
	local sideStroke = Theme.stroke(sideLabel, BLACK, 6)
	local objectiveLabel = text({
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 0, 64),
		Font = Theme.Display,
		TextSize = 62,
		Parent = banner,
	})
	local objectiveStroke = Theme.stroke(objectiveLabel, BLACK, 5)
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
		sideLabel.Text, objectiveLabel.Text = side, objective
		sideLabel.TextColor3 = color
		sideLabel.TextTransparency, objectiveLabel.TextTransparency = 1, 1
		sideStroke.Transparency, objectiveStroke.Transparency = 1, 1
		banner.Size = UDim2.fromOffset(1000, 180)
		banner.Visible = true
		setBannerTransparency(0, 0.3)
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

	---------------------------------------------------------------- top bar: timer + objective
	local timerBox = create("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(150, 46),
		BackgroundColor3 = Color3.fromRGB(18, 18, 22),
		BackgroundTransparency = 0.1,
		Parent = root,
	})
	Theme.corner(timerBox, 6)
	Theme.border(timerBox, BLACK, 3)
	local timerLabel =
		outlined({ Size = UDim2.fromScale(1, 1), Font = Theme.Bold, TextSize = 34, Text = "--:--", Parent = timerBox })
	local phaseLabel = outlined({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 54),
		Size = UDim2.fromOffset(400, 18),
		Font = Theme.Bold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(215, 215, 225),
		Parent = root,
	}, 1.5)
	local objectiveLine = outlined({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(500, 26),
		Font = Theme.Bold,
		TextSize = 24,
		Parent = root,
	}, 2)
	local holdBack, holdFill = Theme.bar({
		Name = "HoldBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(320, 18),
		Visible = false,
		Parent = root,
	}, C.Blue)
	Theme.corner(holdBack, 9)
	Theme.corner(holdFill, 9)
	Theme.border(holdBack, BLACK, 2)
	local holdLabel = outlined({ Size = UDim2.fromScale(1, 1), TextSize = 13, ZIndex = 2, Parent = holdBack }, 1.5)

	---------------------------------------------------------------- orders column (left)
	local orders = create("Frame", {
		Name = "OrdersColumn",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.46, 0),
		Size = UDim2.fromOffset(92, 4 * 96),
		BackgroundTransparency = 1,
		Parent = root,
	})
	create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = orders })

	local ORDER_DEFS = {
		{ name = "Hold", key = "X", icon = "🛡️", color = C.KeyRed },
		{ name = "Follow", key = "C", icon = "🏃", color = C.KeyRed },
		{ name = "Attack", key = "V", icon = "⚔️", color = C.KeyRed },
		{ name = "Rush", key = "B", icon = "⏫", color = C.KeyBlue },
	}
	local orderTiles = {}
	for i, def in ORDER_DEFS do
		local tile = Theme.tile({ Name = def.name, LayoutOrder = i, Size = UDim2.fromOffset(88, 86), Parent = orders })
		local stroke = Theme.border(tile, BLACK, 3)
		text({
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 50),
			Text = def.icon,
			TextSize = 40,
			Parent = tile,
		})
		outlined({
			Position = UDim2.new(0, 0, 1, -26),
			Size = UDim2.new(1, 0, 0, 22),
			Text = string.upper(def.name),
			Font = Theme.Bold,
			TextSize = 17,
			Parent = tile,
		})
		Theme.keyBadge(tile, def.key, def.color, UDim2.fromOffset(-9, -9))
		tile.Activated:Connect(function()
			ClientActions.order(def.name)
		end)
		orderTiles[def.name] = { tile = tile, stroke = stroke }
	end

	-- formation picks beside Hold (visible in Hold mode, like the reference)
	local FORMATION_DEFS =
		{ { name = "Line", key = "1" }, { name = "Column", key = "2" }, { name = "Square", key = "3" } }
	local formationFrame = create("Frame", {
		Name = "HoldFormations",
		Position = UDim2.new(0, 112, 0, 0),
		Size = UDim2.fromOffset(74, 3 * 80),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	create(
		"UIListLayout",
		{ Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = formationFrame }
	)
	local formationTiles = {}
	for i, def in FORMATION_DEFS do
		local tile =
			Theme.tile({ Name = def.name, LayoutOrder = i, Size = UDim2.fromOffset(72, 72), Parent = formationFrame })
		local stroke = Theme.border(tile, BLACK, 3)
		formationIcon(tile, def.name)
		Theme.keyBadge(tile, def.key, C.KeyPink, UDim2.fromOffset(-8, -8), nil, 22)
		tile.Activated:Connect(function()
			ClientActions.setHoldFormation(def.name)
		end)
		formationTiles[def.name] = { tile = tile, stroke = stroke }
	end
	local holdHint = outlined({
		Position = UDim2.new(0, 0, 1, 4),
		Size = UDim2.fromOffset(180, 34),
		Text = "X confirm · Backspace cancel",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = formationFrame,
	}, 1.5)
	local _ = holdHint

	local function flash(tile: GuiObject)
		local gradient = tile:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(C.Gold, Color3.fromRGB(150, 110, 20))
			task.delay(0.25, function()
				gradient.Color = ColorSequence.new(Color3.fromRGB(58, 58, 68), Color3.fromRGB(20, 20, 26))
			end)
		end
	end

	ClientActions.Changed:Connect(function(what, value)
		if what == "Order" and orderTiles[value] then
			flash(orderTiles[value].tile)
		end
	end)

	---------------------------------------------------------------- army list (right)
	local army = create("Frame", {
		Name = "ArmyList",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 130),
		Size = UDim2.fromOffset(220, 30),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	})
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = army })
	outlined({
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 20),
		Text = "ARMY   ·   0 = select all",
		Font = Theme.Bold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = army,
	}, 1.5)
	local rows = {}

	local function row(index: number): any
		local existing = rows[index]
		if existing then
			return existing
		end
		local tile = Theme.tile({ LayoutOrder = index, Size = UDim2.new(1, 0, 0, 46), Parent = army })
		local stroke = Theme.border(tile, BLACK, 3)
		local icon =
			text({ Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(34, 46), TextSize = 26, Parent = tile })
		local name = outlined({
			Position = UDim2.fromOffset(46, 4),
			Size = UDim2.new(1, -96, 0, 18),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = tile,
		}, 1.5)
		local count = outlined({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			Size = UDim2.fromOffset(48, 18),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = tile,
		}, 1.5)
		local hpBack, hp = Theme.bar(
			{ Position = UDim2.fromOffset(46, 25), Size = UDim2.new(1, -56, 0, 7), Parent = tile },
			Color3.fromRGB(90, 160, 255)
		)
		Theme.corner(hpBack, 4)
		Theme.corner(hp, 4)
		local state = outlined({
			Position = UDim2.fromOffset(46, 32),
			Size = UDim2.new(1, -56, 0, 12),
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = tile,
		}, 1)
		local badge = Theme.keyBadge(tile, tostring(index), C.KeyRed, UDim2.fromOffset(-8, -6), nil, 20)
		local entry = {
			tile = tile,
			stroke = stroke,
			icon = icon,
			name = name,
			count = count,
			hp = hp,
			state = state,
			badge = badge,
			id = 0,
		}
		tile.Activated:Connect(function()
			if shiftHeld() then
				ClientActions.toggleSelected(entry.id)
			else
				ClientActions.setSelection({ entry.id })
			end
		end)
		rows[index] = entry
		return entry
	end

	local armyCountLabel: TextLabel

	function api.onSquads()
		local mine = ClientState.mySquads()
		local selected = {}
		local alive, total = 0, 0
		for i, squad in mine do
			local def = UnitDefinitions.get(squad.unitId)
			local entry = row(i)
			entry.id = squad.id
			entry.tile.Visible = true
			entry.icon.Text = def.icon or "⚔️"
			entry.name.Text = squad.name
			entry.count.Text = tostring(squad.soldiers)
			entry.hp.Size = UDim2.fromScale(squad.hp, 1)
			entry.state.Text = if squad.forming
				then "FORMING UP"
				else string.upper(squad.state) .. " · " .. string.upper(squad.order)
			entry.state.TextColor3 = STATE_COLORS[squad.state] or C.Muted
			entry.badge.Visible = i <= 9
			local isSelected = ClientActions.isSelected(squad.id)
			entry.stroke.Color = if isSelected then C.Gold else BLACK
			if isSelected then
				table.insert(selected, squad)
			end
			alive += squad.soldiers
			total += def.soldiers
		end
		for i = #mine + 1, #rows do
			rows[i].tile.Visible = false
		end
		army.Visible = #mine > 0 and orders.Visible

		-- gold outline on the order shared by every selected squad
		local shared = nil
		for _, squad in selected do
			if shared == nil then
				shared = squad.order
			elseif shared ~= squad.order then
				shared = false
			end
		end
		for name, entry in orderTiles do
			entry.stroke.Color = if shared == name then C.Gold else BLACK
		end
		armyCountLabel.Text = string.format("%d/%d", alive, total)
	end

	---------------------------------------------------------------- hotbar + health (bottom centre)
	local hotbar = create("Frame", {
		Name = "CombatHotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(560, 100),
		BackgroundTransparency = 1,
		Parent = root,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = hotbar,
	})
	local HOTBAR_DEFS = {
		{ action = "Attack", title = "ATTACK", icon = "⚔️", key = "🖱", color = C.KeyRed },
		{ action = "Block", title = "BLOCK", icon = "🛡️", key = "F", color = C.KeyRed },
		{ action = "Roll", title = "ROLL", icon = "💨", key = "Q", color = C.KeyRed },
		{ action = "Heal", title = "HEAL", icon = "💚", key = "H", color = C.KeyBlue },
		{ action = "Mount", title = "MOUNT", icon = "🐎", key = "G", color = C.KeyOrange },
	}
	local slots = {}
	for i, def in HOTBAR_DEFS do
		local tile =
			Theme.tile({ Name = def.action, LayoutOrder = i, Size = UDim2.fromOffset(96, 96), Parent = hotbar })
		local stroke = Theme.border(tile, BLACK, 3)
		local title = outlined({
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 20),
			Text = def.title,
			Font = Theme.Bold,
			TextSize = 17,
			Parent = tile,
		})
		local icon = text({
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 60),
			Text = def.icon,
			TextSize = 46,
			Parent = tile,
		})
		local overlay = create("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = tile,
		})
		Theme.corner(overlay, 7)
		local seconds = outlined({ Size = UDim2.fromScale(1, 1), TextSize = 28, ZIndex = 4, Text = "", Parent = tile })
		Theme.keyBadge(tile, def.key, def.color, UDim2.new(1, 8, 1, 8), Vector2.new(1, 1))
		slots[def.action] =
			{ tile = tile, stroke = stroke, overlay = overlay, title = title, icon = icon, seconds = seconds }
	end
	slots.Attack.tile.Activated:Connect(ClientActions.attack)
	slots.Roll.tile.Activated:Connect(ClientActions.roll)
	slots.Heal.tile.Activated:Connect(ClientActions.heal)
	slots.Mount.tile.Activated:Connect(ClientActions.toggleMount)
	slots.Block.tile.MouseButton1Down:Connect(function()
		ClientActions.setBlock(true)
	end)
	for _, signal in { slots.Block.tile.MouseButton1Up, slots.Block.tile.MouseLeave } do
		signal:Connect(function()
			ClientActions.setBlock(false)
		end)
	end

	local health = create("Frame", {
		Name = "HealthBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -142),
		Size = UDim2.fromOffset(560, 34),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local hpBack, hpFill =
		Theme.bar({ Position = UDim2.fromOffset(26, 6), Size = UDim2.new(1, -26, 0, 24), Parent = health }, C.Health)
	Theme.corner(hpBack, 5)
	Theme.corner(hpFill, 5)
	Theme.border(hpBack, BLACK, 3)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 120, 120), Color3.fromRGB(200, 20, 25)),
		Rotation = 90,
		Parent = hpFill,
	})
	for i = 1, 7 do
		create("Frame", {
			Position = UDim2.new(i / 8, 0, 0, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = hpBack,
		})
	end
	local hpText = outlined({ Size = UDim2.fromScale(1, 1), TextSize = 15, ZIndex = 3, Parent = hpBack }, 1.5)
	local heart = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(22, 18),
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = C.Health,
		ZIndex = 4,
		Parent = health,
	})
	Theme.round(heart)
	Theme.border(heart, BLACK, 3)
	create(
		"UIStroke",
		{
			Color = Color3.new(1, 1, 1),
			Thickness = 2,
			Transparency = 0.3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = heart,
		}
	)
	text({ Size = UDim2.fromScale(1, 1), Text = "❤️", TextSize = 28, ZIndex = 5, Parent = heart })

	---------------------------------------------------------------- character card (bottom-left)
	local card = create("Frame", {
		Name = "CharacterCard",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -28),
		Size = UDim2.fromOffset(180, 246),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = root,
	})
	Theme.corner(card, 8)
	Theme.border(card, Color3.fromRGB(15, 5, 35), 3)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(125, 85, 230), Color3.fromRGB(50, 22, 115)),
		Rotation = 90,
		Parent = card,
	})
	outlined(
		{
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(0.6, 0, 0, 22),
			Text = "Commander",
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		},
		2
	)
	local levelLabel = outlined({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.new(0.4, 0, 0, 22),
		Text = "LVL 1",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	}, 2)
	local portrait = create("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(160, 160),
		BackgroundTransparency = 1,
		Parent = card,
	})
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.AvatarBust,
				Enum.ThumbnailSize.Size180x180
			)
		end)
		if ok then
			portrait.Image = image
		end
	end)
	outlined({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(0.5, 0, 0, 18),
		Text = "Soldiers",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	}, 1.5)
	armyCountLabel = outlined({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -6),
		Size = UDim2.fromOffset(110, 32),
		Text = "0/0",
		Font = Theme.Bold,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	}, 2.5)

	function api.refreshArmyCount()
		api.onSquads()
	end

	---------------------------------------------------------------- XP bar (bottom centre)
	local xpBack, xpFill = Theme.bar({
		Name = "XPBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(560, 18),
		Parent = root,
	}, C.Gold)
	Theme.corner(xpBack, 9)
	Theme.corner(xpFill, 9)
	Theme.border(xpBack, BLACK, 2)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 235, 90), Color3.fromRGB(235, 175, 20)),
		Rotation = 90,
		Parent = xpFill,
	})
	local xpLevel = outlined(
		{
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(0, 120, 1, 0),
			Text = "Level 1",
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
			Parent = xpBack,
		},
		1.5
	)
	local xpText =
		outlined({ Size = UDim2.fromScale(1, 1), Text = "0/100", TextSize = 13, ZIndex = 2, Parent = xpBack }, 1.5)

	-- "+10 XP" popups rising on the left
	local lastXp: number? = nil
	local lastLevel: number? = nil
	local function xpPopup(amount: number)
		local label = outlined({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.2, math.random(-30, 30), 0.64, 0),
			Size = UDim2.fromOffset(160, 36),
			Text = "+" .. amount .. " XP",
			Font = Theme.Bold,
			TextSize = 30,
			TextColor3 = Color3.fromRGB(255, 220, 70),
			Rotation = math.random(-8, 4),
			Parent = root,
		}, 2.5)
		TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = label.Position - UDim2.fromOffset(0, 70),
			TextTransparency = 1,
		}):Play()
		local s = label:FindFirstChildOfClass("UIStroke")
		if s then
			TweenService:Create(s, TweenInfo.new(1.4), { Transparency = 1 }):Play()
		end
		task.delay(1.5, function()
			label:Destroy()
		end)
	end

	function api.onProgress(progress: any)
		levelLabel.Text = "LVL " .. progress.level
		xpLevel.Text = "Level " .. progress.level
		xpText.Text = string.format("%d/%d", progress.xp, progress.xpNext)
		xpFill.Size = UDim2.fromScale(math.clamp(progress.xp / math.max(1, progress.xpNext), 0, 1), 1)
		if lastXp and lastLevel then
			local gained = if progress.level == lastLevel then progress.xp - lastXp else progress.xp
			if gained >= 1 then
				xpPopup(gained)
			end
		end
		lastXp, lastLevel = progress.xp, progress.level
	end

	---------------------------------------------------------------- notifications
	local notifications = create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -190),
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
	local TONES = { good = Color3.fromRGB(130, 235, 140), bad = Color3.fromRGB(255, 115, 105), info = C.Text }

	function api.notify(message: string, tone: string?)
		toastOrder += 1
		local toast = outlined({
			LayoutOrder = toastOrder,
			Size = UDim2.fromOffset(600, 24),
			Text = message,
			TextSize = 20,
			TextColor3 = TONES[tone or "info"] or C.Text,
			Parent = notifications,
		}, 2)
		for _, child in notifications:GetChildren() do
			if child:IsA("TextLabel") and child.LayoutOrder <= toastOrder - 5 then
				child:Destroy()
			end
		end
		task.delay(3.5, function()
			if toast.Parent then
				TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
				task.delay(0.5, function()
					toast:Destroy()
				end)
			end
		end)
	end

	---------------------------------------------------------------- controls help (F1)
	local help = create("Frame", {
		Name = "ControlsHelp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(560, 470),
		BackgroundColor3 = Color3.fromRGB(18, 18, 24),
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 30,
		Parent = root,
	})
	Theme.corner(help, 10)
	Theme.border(help, BLACK, 3)
	outlined(
		{
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 36),
			Text = "CONTROLS",
			Font = Theme.Display,
			TextSize = 34,
			ZIndex = 31,
			Parent = help,
		},
		2.5
	)
	outlined({
		Position = UDim2.fromOffset(28, 56),
		Size = UDim2.new(1, -56, 1, -70),
		Text = table.concat({
			"<b>Right mouse drag</b>  rotate camera   ·   <b>Alt</b>  mouse-look",
			"<b>Left click</b>  attack   ·   <b>F</b>  block   ·   <b>Q</b>  roll",
			"<b>H</b>  heal & rally   ·   <b>G</b>  mount / dismount",
			"",
			"<b>1-9</b>  select a squad   ·   <b>Shift+1-9</b>  add / remove",
			"<b>0</b>  select all   ·   <b>T</b>  next squad",
			"<b>Ctrl + drag</b>  box-select squads on screen",
			"",
			"<b>X</b>  Hold: preview on the ground, <b>1 / 2 / 3</b> Line / Column / Square,",
			"      <b>X</b> again to confirm, <b>Backspace</b> to cancel",
			"<b>C</b>  Follow   ·   <b>V</b>  Attack   ·   <b>B</b>  Rush",
			"",
			"<b>M</b>  minimap   ·   <b>F1</b>  close this panel",
		}, "\n"),
		RichText = true,
		TextSize = 17,
		LineHeight = 1.15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 31,
		Parent = help,
	}, 1.5)
	local helpHint = outlined({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -8),
		Size = UDim2.fromOffset(160, 20),
		Text = "F1  Controls",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	}, 1.5)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.F1 then
			help.Visible = not help.Visible
		end
	end)

	---------------------------------------------------------------- phase + per-frame
	function api.onPhase(info: any)
		if info.banner and info.phase == "Battle" then
			local color = if info.side == "Attacker" then C.Red else C.Blue
			api.showBanner(string.upper(info.side or ""), info.objective or "", color)
		end
		local inBattle = info.phase == "Battle"
		hotbar.Visible, health.Visible, orders.Visible = inBattle, inBattle, inBattle
		helpHint.Visible = inBattle
		objectiveLine.Text = if inBattle and info.objective
			then info.objective:sub(1, 1) .. string.lower(info.objective:sub(2))
			else ""
		api.onSquads()
	end
	hotbar.Visible, health.Visible, orders.Visible = false, false, false

	function api.render()
		local info = ClientState.phase
		if info then
			timerLabel.Text = Theme.formatTime(info.endsAt - Workspace:GetServerTimeNow())
			phaseLabel.Text = string.format("ROUND %d  ·  %s", info.round or 1, PHASE_NAMES[info.phase] or info.phase)
		else
			timerLabel.Text = "--:--"
			phaseLabel.Text = "Waiting for the server… (v" .. GameConfig.Version .. ")"
		end

		local hold = ClientState.hold
		holdBack.Visible = hold ~= nil
		if hold then
			holdFill.Size = UDim2.fromScale(hold.progress, 1)
			holdFill.BackgroundColor3 = if hold.team == "Blue" then C.Blue else C.Red
			holdLabel.Text = if hold.team == "Blue" then "HOLDING ALL ZONES" else "ENEMY HOLDS ALL ZONES!"
		end

		-- Hold mode: formation picks beside the Hold tile
		local holdState = ClientActions.holdState()
		formationFrame.Visible = holdState.active and orders.Visible
		if formationFrame.Visible then
			local holdTile = orderTiles.Hold.tile
			formationFrame.Position = UDim2.fromOffset(
				holdTile.AbsolutePosition.X + holdTile.AbsoluteSize.X + 16,
				holdTile.AbsolutePosition.Y - 72
			)
			for name, entry in formationTiles do
				entry.stroke.Color = if holdState.formation == name then C.Gold else BLACK
			end
			orderTiles.Hold.stroke.Color = C.Gold
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local fraction = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
			hpFill.Size = UDim2.fromScale(fraction, 1)
			hpText.Text = string.format("%d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth)
		end

		for action, slot in slots do
			local fraction = ClientActions.cooldownFraction(action)
			slot.overlay.Size = UDim2.fromScale(1, fraction)
			slot.seconds.Text = if fraction > 0
				then tostring(math.ceil(ClientActions.cooldownRemaining(action)))
				else ""
		end
		local mounted = ClientActions.isMounted()
		slots.Mount.title.Text = if mounted then "DISMOUNT" else "MOUNT"
		slots.Mount.stroke.Color = if mounted then C.Gold else BLACK
		slots.Block.stroke.Color = if ClientActions.blocking then C.Gold else BLACK
		slots.Roll.icon.TextTransparency = if mounted then 0.6 else 0
		slots.Roll.title.TextTransparency = if mounted then 0.5 else 0
	end

	return api
end

return Hud

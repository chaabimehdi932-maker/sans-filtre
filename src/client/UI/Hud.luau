--[[
	Battle HUD. Everything sits inside ONE frame (BattleHUD) that is fully hidden outside the
	Battle phase. Inside, each element owns a fixed screen region so nothing can overlap
	(design canvas 1600×900 scaled by a UIScale; api.layout re-flows narrow screens):

	  ┌ TopLeft: SquadSelector ─┬── TopCenter: timer/phase/objective ──┬ TopRight: minimap (M) ┐
	  │                          │   Banner region (staggered BELOW)     │                        │
	  │ LeftColumn: orders       │                                       │                        │
	  │  X C V B + 1/2/3 picks   │                                       │                        │
	  ├ BottomLeft: card ────────┴─ BottomCenter: HP + hotbar ───────────┴ BottomRight: feed ─────┤
	  └──────────────────────────────── XP bar (full width) ─────────────────────────────────────┘
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
local UnitCard = require(script.Parent:WaitForChild("UnitCard"))

local C = Theme.Colors
local create, text, outlined = Theme.create, Theme.text, Theme.outlined
local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)
local DARK_RED = Color3.fromRGB(150, 10, 15)

local Hud = {}

local PHASE_NAMES = { Waiting = "WAITING", Recruitment = "RECRUITMENT", Battle = "BATTLE", Reward = "RESULTS" }
local STATE_COLORS = {
	Idle = Color3.fromRGB(170, 170, 185),
	Advancing = Color3.fromRGB(140, 200, 255),
	Engaging = Color3.fromRGB(255, 150, 80),
	Routing = Color3.fromRGB(255, 70, 70),
	Regrouping = Color3.fromRGB(255, 220, 120),
}

-- Draws a formation as little dots (the 1/2/3 formation buttons)
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

function Hud.build(screen: ScreenGui, ClientState: any, ClientActions: any): any
	local api = {}

	-- the one container for the whole battle HUD
	local root = create("Frame", {
		Name = "BattleHUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	api.frame = root
	local uiScale = create("UIScale", { Parent = root })

	local function region(name: string, anchor: Vector2, position: UDim2, size: Vector2): Frame
		return create("Frame", {
			Name = name,
			AnchorPoint = anchor,
			Position = position,
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundTransparency = 1,
			Parent = root,
		})
	end
	local regions = {
		topLeft = region("TopLeft", Vector2.new(0, 0), UDim2.fromOffset(14, 56), Vector2.new(540, 170)),
		topCenter = region("TopCenter", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4), Vector2.new(420, 136)),
		topRight = region("TopRight", Vector2.new(1, 0), UDim2.new(1, -14, 0, 56), Vector2.new(200, 200)),
		-- below both the top centre AND the squad selector (ends at y 226): staggered, never stacked
		banner = region("BannerRegion", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 236), Vector2.new(1000, 190)),
		left = region("LeftColumn", Vector2.new(0, 0.5), UDim2.new(0, 14, 0.52, 0), Vector2.new(200, 376)),
		bottomLeft = region("BottomLeft", Vector2.new(0, 1), UDim2.new(0, 14, 1, -26), Vector2.new(180, 200)),
		bottomCenter = region("BottomCenter", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -26), Vector2.new(600, 150)),
		bottomRight = region("BottomRight", Vector2.new(1, 1), UDim2.new(1, -14, 1, -26), Vector2.new(380, 190)),
	}
	api.regions = regions

	---------------------------------------------------------------- top centre: timer / phase / objective
	create("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = regions.topCenter,
	})
	local timerBox = create("Frame", {
		Name = "Timer",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(150, 46),
		BackgroundColor3 = Color3.fromRGB(18, 18, 22),
		BackgroundTransparency = 0.1,
		Parent = regions.topCenter,
	})
	Theme.corner(timerBox, 6)
	Theme.border(timerBox, BLACK, 3)
	local timerLabel =
		outlined({ Size = UDim2.fromScale(1, 1), Font = Theme.Bold, TextSize = 34, Text = "--:--", Parent = timerBox })
	local phaseLabel = outlined({
		LayoutOrder = 2,
		Size = UDim2.fromOffset(400, 18),
		Font = Theme.Bold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(215, 215, 225),
		Parent = regions.topCenter,
	}, 1.5)
	local objectiveLine = outlined({
		LayoutOrder = 3,
		Size = UDim2.fromOffset(420, 30),
		Font = Theme.Display,
		TextSize = 27,
		Parent = regions.topCenter,
	}, 2.5)
	local objectiveLineStroke = objectiveLine:FindFirstChildOfClass("UIStroke") :: UIStroke
	objectiveLineStroke.Color = DARK_RED
	local holdBack, holdFill = Theme.bar({
		Name = "HoldBar",
		LayoutOrder = 4,
		Size = UDim2.fromOffset(320, 18),
		Visible = false,
		Parent = regions.topCenter,
	}, C.Blue)
	Theme.corner(holdBack, 9)
	Theme.corner(holdFill, 9)
	Theme.border(holdBack, BLACK, 2)
	local holdLabel = outlined({ Size = UDim2.fromScale(1, 1), TextSize = 13, ZIndex = 2, Parent = holdBack }, 1.5)

	---------------------------------------------------------------- banner (below the top centre)
	local banner = create("Frame", {
		Name = "ObjectiveBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = regions.banner,
	})
	local bannerScale = create("UIScale", { Parent = banner })
	local sideLabel = text({
		Size = UDim2.new(1, 0, 0, 110),
		Font = Theme.Display,
		TextScaled = true,
		TextColor3 = C.Red,
		Parent = banner,
	})
	create("UITextSizeConstraint", { MaxTextSize = 108, Parent = sideLabel })
	local sideStroke = Theme.stroke(sideLabel, BLACK, 6)
	local objectiveLabel = text({
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 0, 72),
		Font = Theme.Display,
		TextScaled = true,
		Parent = banner,
	})
	create("UITextSizeConstraint", { MaxTextSize = 68, Parent = objectiveLabel })
	local objectiveStroke = Theme.stroke(objectiveLabel, DARK_RED, 6) -- red-outlined, as specified
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

	-- Big banner first; then it shrinks up into the small objective line under the timer
	function api.showBanner(side: string, objective: string, color: Color3)
		bannerToken += 1
		local token = bannerToken
		sideLabel.Text, objectiveLabel.Text = side, objective
		sideLabel.TextColor3 = color
		sideLabel.TextTransparency, objectiveLabel.TextTransparency = 1, 1
		sideStroke.Transparency, objectiveStroke.Transparency = 1, 1
		banner.Position = UDim2.fromScale(0.5, 0)
		bannerScale.Scale = 1.35
		banner.Visible = true
		objectiveLine.TextTransparency = 1
		objectiveLineStroke.Transparency = 1
		setBannerTransparency(0, 0.25)
		TweenService
			:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		task.delay(3.6, function()
			if token ~= bannerToken then
				return
			end
			local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(bannerScale, info, { Scale = 0.3 }):Play()
			TweenService:Create(banner, info, { Position = UDim2.new(0.5, 0, 0, -110) }):Play()
			setBannerTransparency(1, 0.7)
			task.delay(0.7, function()
				if token == bannerToken then
					banner.Visible = false
					TweenService:Create(objectiveLine, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
					TweenService:Create(objectiveLineStroke, TweenInfo.new(0.3), { Transparency = 0 }):Play()
				end
			end)
		end)
	end

	---------------------------------------------------------------- left column: orders + hold formations
	local orders = create("Frame", {
		Name = "OrdersColumn",
		Size = UDim2.new(0, 92, 1, 0),
		BackgroundTransparency = 1,
		Parent = regions.left,
	})
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = orders })

	local ORDER_DEFS = {
		{ name = "Hold", key = "X", icon = "🛡️", color = C.KeyRed },
		{ name = "Follow", key = "C", icon = "🏃", color = C.KeyRed },
		{ name = "Attack", key = "V", icon = "⚔️", color = C.KeyRed },
		{ name = "Rush", key = "B", icon = "⚡", color = C.KeyBlue },
	}
	local orderTiles = {}
	for i, def in ORDER_DEFS do
		local tile = Theme.tile({ Name = def.name, LayoutOrder = i, Size = UDim2.fromOffset(88, 86), Parent = orders })
		local stroke = Theme.border(tile, BLACK, 3)
		-- icon in the upper part, label on top of it (higher ZIndex): every label stays readable
		text({
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 50),
			Text = def.icon,
			TextSize = 36,
			ZIndex = 1,
			Parent = tile,
		})
		outlined({
			Position = UDim2.new(0, 0, 1, -25),
			Size = UDim2.new(1, 0, 0, 22),
			Text = string.upper(def.name),
			Font = Theme.Bold,
			TextSize = 17,
			ZIndex = 3,
			Parent = tile,
		})
		Theme.keyBadge(tile, def.key, def.color, UDim2.fromOffset(-9, -9))
		tile.Activated:Connect(function()
			ClientActions.order(def.name)
		end)
		orderTiles[def.name] = { tile = tile, stroke = stroke }
	end

	local FORMATION_DEFS =
		{ { name = "Line", key = "1" }, { name = "Column", key = "2" }, { name = "Square", key = "3" } }
	local formationFrame = create("Frame", {
		Name = "HoldFormations",
		Position = UDim2.fromOffset(104, 0),
		Size = UDim2.fromOffset(90, 3 * 78 + 40),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = regions.left,
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
	outlined({
		LayoutOrder = 4,
		Size = UDim2.fromOffset(90, 34),
		Text = "X confirm\nBackspace cancel",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = formationFrame,
	}, 1.5)

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

	---------------------------------------------------------------- top left: squad selector (one commanded squad)
	outlined({
		Size = UDim2.new(1, 0, 0, 20),
		Text = "COMMANDING  ·  [Tab] switch squad",
		Font = Theme.Bold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = regions.topLeft,
	}, 1.5)
	local selector = create("ScrollingFrame", {
		Name = "SquadSelector",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 1, -26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = regions.topLeft,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = selector,
	})
	create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), Parent = selector })
	local selectorCards: { [number]: any } = {}

	local soldierCountLabel: TextLabel

	function api.onSquads()
		local mine = ClientState.mySquads()
		local controlledId = ClientActions.controlledId()
		local seen = {}
		local alive, total = 0, 0
		for i, squad in mine do
			seen[squad.id] = true
			local card = selectorCards[squad.id]
			if not card then
				card = UnitCard.new(selector, squad.unitId, "Blue", { compact = true })
				local id = squad.id
				card.button.Activated:Connect(function()
					ClientActions.cancelHold()
					ClientActions.selectSquad(id)
				end)
				selectorCards[squad.id] = card
			end
			card.button.LayoutOrder = i
			card:setName(squad.name)
			card:setStars(squad.rank or 0)
			card:setHealth(squad.hp)
			local isControlled = squad.id == controlledId
			card:setSelected(isControlled)
			card:setSubtitle(
				if isControlled then "★ YOUR COMMAND" elseif squad.state == "Routing" then "ROUTING" else "Ally AI",
				if isControlled then C.Gold else STATE_COLORS[squad.state]
			)
			alive += squad.soldiers
			total += UnitDefinitions.get(squad.unitId).soldiers
		end
		for id, card in selectorCards do
			if not seen[id] then
				card:destroy()
				selectorCards[id] = nil
			end
		end
		regions.topLeft.Visible = #mine > 0

		-- gold outline on the commanded squad's current order
		local current = ClientState.squadsById[controlledId]
		for name, entry in orderTiles do
			entry.stroke.Color = if current and current.order == name then C.Gold else BLACK
		end
		soldierCountLabel.Text = string.format("%d/%d", alive, total)
	end

	---------------------------------------------------------------- bottom centre: health bar + hotbar
	create("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = regions.bottomCenter,
	})
	local health = create("Frame", {
		Name = "HealthBar",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(560, 34),
		BackgroundTransparency = 1,
		Parent = regions.bottomCenter,
	})
	local hpBack, hpFill =
		Theme.bar({ Position = UDim2.fromOffset(26, 5), Size = UDim2.new(1, -26, 0, 24), Parent = health }, C.Health)
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
		Position = UDim2.fromOffset(22, 17),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = C.Health,
		ZIndex = 4,
		Parent = health,
	})
	Theme.round(heart)
	Theme.border(heart, BLACK, 3)
	text({ Size = UDim2.fromScale(1, 1), Text = "❤️", TextSize = 26, ZIndex = 5, Parent = heart })

	local hotbar = create("Frame", {
		Name = "CombatHotbar",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(560, 100),
		BackgroundTransparency = 1,
		Parent = regions.bottomCenter,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
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
			Theme.tile({ Name = def.action, LayoutOrder = i, Size = UDim2.fromOffset(94, 94), Parent = hotbar })
		local stroke = Theme.border(tile, BLACK, 3)
		local icon = text({
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 60),
			Text = def.icon,
			TextSize = 44,
			ZIndex = 1,
			Parent = tile,
		})
		local title = outlined({
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 20),
			Text = def.title,
			Font = Theme.Bold,
			TextSize = 16,
			ZIndex = 3,
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
			ZIndex = 4,
			Parent = tile,
		})
		Theme.corner(overlay, 7)
		local seconds = outlined({ Size = UDim2.fromScale(1, 1), TextSize = 28, ZIndex = 5, Text = "", Parent = tile })
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

	---------------------------------------------------------------- bottom left: character card
	local card = create("Frame", {
		Name = "CharacterCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = regions.bottomLeft,
	})
	Theme.corner(card, 8)
	Theme.border(card, Color3.fromRGB(15, 5, 35), 3)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(125, 85, 230), Color3.fromRGB(50, 22, 115)),
		Rotation = 90,
		Parent = card,
	})
	outlined({
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(0.6, 0, 0, 22),
		Text = "Commander",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	}, 2)
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
		Size = UDim2.fromOffset(130, 130),
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
	soldierCountLabel = outlined({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -6),
		Size = UDim2.fromOffset(110, 32),
		Text = "0/0",
		Font = Theme.Bold,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	}, 2.5)

	function api.refreshArmyCount()
		api.onSquads()
	end

	---------------------------------------------------------------- XP bar (full width, very bottom)
	local xpBack, xpFill = Theme.bar({
		Name = "XPBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = root,
	}, C.Gold)
	Theme.border(xpBack, BLACK, 2)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 235, 90), Color3.fromRGB(235, 175, 20)),
		Rotation = 90,
		Parent = xpFill,
	})
	local xpLevel = outlined({
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(0, 120, 1, 0),
		Text = "Level 1",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = xpBack,
	}, 1.5)
	local xpText =
		outlined({ Size = UDim2.fromScale(1, 1), Text = "0/100", TextSize = 13, ZIndex = 2, Parent = xpBack }, 1.5)

	-- "+10 XP" popups rising in the empty centre-left area
	local lastXp: number? = nil
	local lastLevel: number? = nil
	local function xpPopup(amount: number)
		local label = outlined({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.24, math.random(-30, 30), 0.64, 0),
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
		if lastXp and lastLevel and root.Visible then
			local gained = if progress.level == lastLevel then progress.xp - lastXp else progress.xp
			if gained >= 1 then
				xpPopup(gained)
			end
		end
		lastXp, lastLevel = progress.xp, progress.level
	end

	---------------------------------------------------------------- bottom right: notification feed + F1 hint
	local feed = create("Frame", {
		Name = "Notifications",
		Size = UDim2.new(1, 0, 1, -24),
		BackgroundTransparency = 1,
		Parent = regions.bottomRight,
	})
	create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = feed,
	})
	local toastOrder = 0
	local TONES = { good = Color3.fromRGB(130, 235, 140), bad = Color3.fromRGB(255, 115, 105), info = C.Text }

	function api.notify(message: string, tone: string?)
		toastOrder += 1
		local toast = outlined({
			LayoutOrder = toastOrder,
			Size = UDim2.new(1, 0, 0, 22),
			Text = message,
			TextSize = 18,
			TextColor3 = TONES[tone or "info"] or C.Text,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = feed,
		}, 2)
		for _, child in feed:GetChildren() do
			if child:IsA("TextLabel") and child.LayoutOrder <= toastOrder - 6 then
				child:Destroy()
			end
		end
		task.delay(4, function()
			if toast.Parent then
				TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
				task.delay(0.5, function()
					toast:Destroy()
				end)
			end
		end)
	end
	outlined({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(160, 20),
		Text = "F1  Controls",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = regions.bottomRight,
	}, 1.5)

	---------------------------------------------------------------- controls help (F1, modal)
	local help = create("Frame", {
		Name = "ControlsHelp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(560, 440),
		BackgroundColor3 = Color3.fromRGB(18, 18, 24),
		BackgroundTransparency = 0.05,
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
			"<b>Tab / Shift+Tab</b>  switch the squad you command",
			"(click a squad card, top-left, to take command of it)",
			"Your other squads fight on their own (ally AI).",
			"",
			"<b>X</b>  Hold: preview on the ground, <b>1 / 2 / 3</b> Line / Column / Square,",
			"      <b>X</b> again to confirm, <b>Backspace</b> to cancel",
			"<b>C</b>  Follow   ·   <b>V</b>  Attack   ·   <b>B</b>  Rush",
			"",
			"<b>M</b>  minimap   ·   <b>F1</b>  close this panel",
		}, "\n"),
		RichText = true,
		TextSize = 17,
		LineHeight = 1.12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 31,
		Parent = help,
	}, 1.5)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.F1 then
			help.Visible = not help.Visible
		end
	end)

	---------------------------------------------------------------- layout: scale + narrow-screen re-flow
	--[[
		Everything is authored on a 1600×900 canvas. The UIScale keeps proportions; on narrow
		screens (portrait / small phones) the squad selector moves under the top centre, the
		banner is pushed below it, and the character card and minimap are hidden, so no two
		regions ever share space.
	]]
	function api.layout(viewport: Vector2)
		local scale = math.clamp(math.min(viewport.X / 1600, viewport.Y / 900), 0.5, 1.25)
		uiScale.Scale = scale
		local width = viewport.X / scale -- canvas width in design units
		local narrow = width < 1250
		if narrow then
			regions.topLeft.AnchorPoint = Vector2.new(0.5, 0)
			regions.topLeft.Position = UDim2.new(0.5, 0, 0, 140)
			regions.topLeft.Size = UDim2.fromOffset(math.min(540, width - 28), 170)
			regions.banner.Position = UDim2.new(0.5, 0, 0, 320)
			-- keep clear of the left column: the banner text shrinks to fit (TextScaled)
			regions.banner.Size = UDim2.fromOffset(math.max(260, width - 460), 190)
		else
			regions.topLeft.AnchorPoint = Vector2.zero
			regions.topLeft.Position = UDim2.fromOffset(14, 56)
			-- never wider than the gap to the top-centre region
			regions.topLeft.Size = UDim2.fromOffset(math.min(540, width / 2 - 210 - 30), 170)
			regions.banner.Position = UDim2.new(0.5, 0, 0, 236)
			regions.banner.Size = UDim2.fromOffset(math.min(1000, width - 460), 190)
		end
		regions.bottomLeft.Visible = width >= 1100
		regions.topRight.Visible = not narrow
		regions.bottomRight.Visible = width >= 1300
	end

	---------------------------------------------------------------- phase + per-frame
	function api.onPhase(info: any)
		if info.banner and info.phase == "Battle" then
			local color = if info.side == "Attacker" then C.Red else C.Blue
			api.showBanner(string.upper(info.side or ""), info.objective or "", color)
		end
		objectiveLine.Text = info.objective or ""
		api.onSquads()
	end

	function api.render()
		if not root.Visible then
			return
		end
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
		formationFrame.Visible = holdState.active
		if holdState.active then
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

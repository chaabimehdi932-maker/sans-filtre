--[[
	Battle HUD. Everything sits inside ONE full-screen frame (BattleHUD) that is fully hidden
	outside the Battle phase. Each element owns a fixed screen region so nothing can overlap.
	Regions are authored on a 1600×900 canvas; api.layout gives EACH REGION its own UIScale
	and scales its edge offsets, so the HUD always spans the whole screen:

	  ┌ (Roblox buttons) ─────── TopCenter: timer/phase/objective ───── TopRight: minimap (M) ┐
	  │                          Banner region (below the top centre)                          │
	  │ LeftColumn: orders       KillCombo                                                     │
	  │  X C V B + 1/2/3 picks                                                                 │
	  ├ BottomLeft: your unit ─── BottomCenter: HP + hotbar ─────────── BottomRight: feed ─────┤
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
local ROMAN = { "I", "II", "III", "IV", "V" }

local Hud = {}

local PHASE_NAMES = { Waiting = "WAITING", Recruitment = "RECRUITMENT", Battle = "BATTLE", Reward = "RESULTS" }

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

	local root = create("Frame", {
		Name = "BattleHUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	api.frame = root

	-- regions: base layout on the 1600×900 canvas (scaled per region in api.layout)
	local layoutBase: { [Frame]: any } = {}
	local function region(name: string, anchor: Vector2, position: UDim2, size: Vector2): Frame
		local frame = create("Frame", {
			Name = name,
			AnchorPoint = anchor,
			Position = position,
			Size = UDim2.fromOffset(size.X, size.Y),
			BackgroundTransparency = 1,
			Parent = root,
		})
		create("UIScale", { Name = "RegionScale", Parent = frame })
		layoutBase[frame] = { position = position, size = size }
		return frame
	end
	local regions = {
		topCenter = region("TopCenter", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4), Vector2.new(420, 136)),
		topRight = region("TopRight", Vector2.new(1, 0), UDim2.new(1, -14, 0, 66), Vector2.new(200, 200)),
		banner = region("BannerRegion", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 150), Vector2.new(1000, 190)),
		left = region("LeftColumn", Vector2.new(0, 0.5), UDim2.new(0, 14, 0.49, 0), Vector2.new(200, 360)),
		combo = region("KillCombo", Vector2.new(0, 0.5), UDim2.new(0, 240, 0.47, 0), Vector2.new(380, 110)),
		bottomLeft = region("BottomLeft", Vector2.new(0, 1), UDim2.new(0, 14, 1, -26), Vector2.new(180, 250)),
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
	local orders = create(
		"Frame",
		{ Name = "OrdersColumn", Size = UDim2.new(0, 92, 1, 0), BackgroundTransparency = 1, Parent = regions.left }
	)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = orders })
	local ORDER_DEFS = {
		{ name = "Hold", iconName = "OrderHold", key = "X", icon = "🛡️", color = C.KeyRed },
		{ name = "Follow", iconName = "OrderFollow", key = "C", icon = "🏃", color = C.KeyRed },
		{ name = "Attack", iconName = "OrderAttack", key = "V", icon = "⚔️", color = C.KeyRed },
		{ name = "Rush", iconName = "OrderRush", key = "B", icon = "⚡", color = C.KeyBlue },
	}
	local orderTiles = {}
	for i, def in ORDER_DEFS do
		local tile = Theme.tile({ Name = def.name, LayoutOrder = i, Size = UDim2.fromOffset(88, 84), Parent = orders })
		local stroke = Theme.border(tile, BLACK, 3)
		-- icon in the upper part, label above it (higher ZIndex): every label stays readable
		Theme.icon(def.iconName, def.icon, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(50, 48),
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

	---------------------------------------------------------------- bottom left: the unit you command
	local unitCard: any = nil
	local unitCardId: string? = nil
	local playerLevel = 1
	local reinforcementLabel = outlined({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(1, -10, 0, 60),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		Text = "",
		TextSize = 18,
		TextWrapped = true,
		Visible = false,
		ZIndex = 20,
		Parent = regions.bottomLeft,
	}, 2)
	Theme.corner(reinforcementLabel, 8)

	function api.onSquads()
		local squad = ClientState.squadsById[ClientActions.controlledId()]
		-- the card shows your unit type (rebuilt only when it changes)
		local unitId = if squad then squad.unitId elseif ClientState.recruit then ClientState.recruit.chosen else nil
		if unitId and unitId ~= unitCardId then
			if unitCard then
				unitCard:destroy()
			end
			unitCard = UnitCard.new(regions.bottomLeft, unitId, "Blue", {})
			unitCard.button.Position = UDim2.fromOffset(4, 10)
			unitCardId = unitId
		end
		if unitCard and unitCardId then
			local def = UnitDefinitions.get(unitCardId)
			local rank = if squad then squad.rank or 0 else 0
			unitCard:setName(def.displayName .. (if rank > 0 then " " .. ROMAN[math.min(rank, #ROMAN)] else ""))
			unitCard:setStars(rank)
			unitCard:setSubtitle(
				"LVL " .. playerLevel .. (if squad then "  ·  " .. string.upper(squad.order) else ""),
				C.Gold
			)
			unitCard:setValue(
				if squad then string.format("%d/%d", squad.soldiers, def.soldiers) else "0/" .. def.soldiers
			)
			unitCard:setHealth(if squad then squad.hp else 0)
			unitCard:setSelected(squad ~= nil)
		end
		for name, entry in orderTiles do
			entry.stroke.Color = if squad and squad.order == name then C.Gold else BLACK
		end
	end

	function api.refreshArmyCount()
		api.onSquads()
	end

	local function renderReinforcements()
		local recruit = ClientState.recruit
		if ClientState.squadsById[ClientActions.controlledId()] or not recruit then
			reinforcementLabel.Visible = false
			return
		end
		reinforcementLabel.Visible = true
		if recruit.reinforcementAt then
			reinforcementLabel.Text = string.format(
				"Reinforcements in %ds\n(%d left)",
				math.max(0, math.ceil(recruit.reinforcementAt - Workspace:GetServerTimeNow())),
				recruit.reinforcements
			)
		else
			reinforcementLabel.Text = "Your unit is lost.\nNo reinforcements left!"
		end
	end

	---------------------------------------------------------------- kill combo ("💀 KILL x58 · 482 XP")
	local comboFrame = create(
		"Frame",
		{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = regions.combo }
	)
	local comboScale = create("UIScale", { Parent = comboFrame })
	local comboLabel = text({
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(58, 0),
		Text = "KILL x0",
		Font = Theme.Display,
		TextSize = 50,
		TextColor3 = Color3.fromRGB(235, 30, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = comboFrame,
	})
	local comboStroke = Theme.stroke(comboLabel, Color3.new(1, 1, 1), 3)
	Theme.icon(
		"Skull",
		"💀",
		{ Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(52, 52), TextSize = 44, Parent = comboFrame }
	)
	local comboXpLabel = outlined({
		Position = UDim2.fromOffset(58, 60),
		Size = UDim2.new(1, -58, 0, 30),
		Font = Theme.Bold,
		TextSize = 26,
		TextColor3 = Color3.fromRGB(255, 225, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = comboFrame,
	}, 2)
	local comboCount, comboXp, comboUntil = 0, 0, 0

	function api.onKill(data: any)
		local now = os.clock()
		if now > comboUntil then
			comboCount, comboXp = 0, 0
		end
		comboCount += data.kills
		comboXp += data.xp
		comboUntil = now + GameConfig.Rewards.KillComboWindow
		comboLabel.Text = "KILL x" .. comboCount
		comboXpLabel.Text = comboXp .. " XP"
		comboLabel.TextTransparency, comboXpLabel.TextTransparency, comboStroke.Transparency = 0, 0, 0
		comboFrame.Visible = true
		comboScale.Scale = 1.35
		TweenService
			:Create(comboScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end

	local function renderCombo()
		if comboFrame.Visible and os.clock() > comboUntil then
			local fade = math.clamp((os.clock() - comboUntil) / 0.6, 0, 1)
			comboLabel.TextTransparency, comboXpLabel.TextTransparency, comboStroke.Transparency = fade, fade, fade
			if fade >= 1 then
				comboFrame.Visible = false
			end
		end
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
	Theme.icon("Heart", "❤️", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		TextSize = 26,
		ZIndex = 5,
		Parent = heart,
	})

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
		local icon = Theme.icon(def.action, def.icon, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 26),
			Size = UDim2.fromOffset(56, 56),
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

	local lastXp: number? = nil
	local lastLevel: number? = nil
	local function xpPopup(amount: number)
		if comboFrame.Visible then
			return -- the kill combo already shows the XP
		end
		local label = outlined({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, math.random(0, 40), 0.75, 0),
			Size = UDim2.fromOffset(160, 36),
			Text = "+" .. amount .. " XP",
			Font = Theme.Bold,
			TextSize = 30,
			TextColor3 = Color3.fromRGB(255, 220, 70),
			Rotation = math.random(-8, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = regions.combo,
		}, 2.5)
		TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = label.Position - UDim2.fromOffset(0, 60),
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
		playerLevel = progress.level
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
		api.onSquads()
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
		Size = UDim2.fromOffset(580, 430),
		BackgroundColor3 = Color3.fromRGB(18, 18, 24),
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 30,
		Parent = root,
	})
	Theme.corner(help, 10)
	Theme.border(help, BLACK, 3)
	outlined({
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 36),
		Text = "CONTROLS",
		Font = Theme.Display,
		TextSize = 34,
		ZIndex = 31,
		Parent = help,
	}, 2.5)
	outlined({
		Position = UDim2.fromOffset(28, 56),
		Size = UDim2.new(1, -56, 1, -70),
		Text = table.concat({
			"<b>Right mouse drag</b>  rotate camera   ·   <b>Alt</b>  mouse-look",
			"<b>Left click</b>  attack   ·   <b>F</b>  block   ·   <b>Q</b>  roll",
			"<b>H</b>  heal & rally   ·   <b>G</b>  mount / dismount",
			"",
			"You command ONE unit (bottom-left card). The rest of the army",
			"is led by allied officers and fights on its own.",
			"",
			"<b>X</b>  Hold: preview on the ground, <b>1 / 2 / 3</b> Line / Column / Square,",
			"      <b>X</b> again to confirm, <b>Backspace</b> to cancel",
			"<b>C</b>  Follow   ·   <b>V</b>  Attack",
			"<b>B</b>  Rush: aim the path, <b>left click</b> charge, <b>right click</b> cancel",
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

	---------------------------------------------------------------- layout: whole-screen scaling + re-flow
	--[[
		Each region keeps its anchor on its screen edge and gets its own UIScale; edge offsets are
		scaled too. (One UIScale on the full-screen frame would shrink the whole HUD towards the
		top-left corner.) Narrow screens drop the lowest-priority regions instead of overlapping.
	]]
	function api.layout(viewport: Vector2)
		local scale = math.clamp(math.min(viewport.X / 1600, viewport.Y / 900), 0.45, 1.35)
		local width = viewport.X / scale -- screen width in design units
		for frame, base in layoutBase do
			local p = base.position
			frame.Position = UDim2.new(p.X.Scale, p.X.Offset * scale, p.Y.Scale, p.Y.Offset * scale)
			local size = base.size
			if frame == regions.banner then
				size = Vector2.new(math.clamp(width - 480, 300, 1000), size.Y)
			end
			frame.Size = UDim2.fromOffset(size.X, size.Y)
			local regionScale = frame:FindFirstChild("RegionScale") :: UIScale
			regionScale.Scale = scale
		end
		help.Size = UDim2.fromOffset(580 * scale, 430 * scale)
		xpBack.Size = UDim2.new(1, 0, 0, math.max(12, 18 * scale))
		regions.bottomLeft.Visible = width >= 1150
		regions.bottomRight.Visible = width >= 1400
		regions.topRight.Visible = width >= 1000
		regions.combo.Visible = width >= 1000
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
		renderCombo()
		renderReinforcements()
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

		if ClientActions.rushState().aiming then
			orderTiles.Rush.stroke.Color = C.Gold
		end
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
		Theme.setIconTransparency(slots.Roll.icon, if mounted then 0.6 else 0)
		slots.Roll.title.TextTransparency = if mounted then 0.5 else 0
	end

	return api
end

return Hud

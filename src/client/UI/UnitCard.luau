--[[
	UnitCard — the single card component used everywhere a unit is shown for selection
	(recruitment shop, squad selector), so the whole game looks consistent.
	  • portrait: the real soldier model rendered in a ViewportFrame
	  • rarity border coloured by unit tier (grey / blue / purple / gold)
	  • veteran stars bottom-left, value bottom-right (e.g. soldiers 28/28), count badge top-right
	  • stats + description in a hover tooltip instead of always-on text

	UnitCard.new(parent, unitId, team, { compact = bool, layoutOrder = n }) → card
	card:setCount(n) · setStars(n) · setValue(text) · setLocked(bool, text?) · setSelected(bool)
	card:setHealth(fraction?) · setSubtitle(text) · setKey(text?) · card.button.Activated
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local SoldierAnimationService = require(script.Parent.Parent:WaitForChild("SoldierAnimationService"))
local SoldierModels = require(script.Parent.Parent:WaitForChild("SoldierModels"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local create, outlined = Theme.create, Theme.outlined
local BLACK = Color3.new(0, 0, 0)

local UnitCard = {}
UnitCard.__index = UnitCard

UnitCard.TIER_COLORS = {
	Color3.fromRGB(165, 165, 175), -- 1 common
	Color3.fromRGB(70, 145, 255), -- 2 rare
	Color3.fromRGB(175, 85, 245), -- 3 epic
	Color3.fromRGB(255, 200, 50), -- 4 legendary
}

---------------------------------------------------------------------------
-- Shared hover tooltip
---------------------------------------------------------------------------

local tooltip: Frame? = nil
local tooltipText: TextLabel? = nil

function UnitCard.attachTooltipLayer(root: Instance)
	tooltip = create("Frame", {
		Name = "UnitTooltip",
		Size = UDim2.fromOffset(250, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(16, 16, 22),
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 100,
		Parent = root,
	})
	Theme.corner(tooltip :: Frame, 8)
	Theme.border(tooltip :: Frame, BLACK, 3)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = tooltip,
	})
	tooltipText = outlined({
		Size = UDim2.new(1, 0, 0, 10),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 101,
		Parent = tooltip,
	}, 1.5)
end

local function statsText(def: any): string
	local lines = { string.format("<b>%s</b>", def.displayName) }
	table.insert(lines, string.format("HP %d · Speed %d · Morale %d", def.health, def.moveSpeed, def.morale))
	if def.attackType == "Melee" then
		table.insert(lines, string.format("Melee %d · Charge ×%g", def.meleeDamage, def.chargeMultiplier))
	else
		table.insert(
			lines,
			string.format("Damage %d · Range %d · Reload %gs", def.damage, def.attackRange, def.attackCooldown)
		)
	end
	table.insert(lines, "Formations: " .. table.concat(def.formations, ", "))
	table.insert(lines, string.format('<font color="#B4B4C8">%s</font>', def.description))
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Portrait
---------------------------------------------------------------------------

local function portrait(parent: GuiObject, def: any, team: string)
	local viewport = create("ViewportFrame", {
		Name = "Portrait",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
		ZIndex = 2,
		Parent = parent,
	})
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local rig
	if def.visual == "Cavalry" then
		rig = SoldierModels.cavalry(world, team, def)
		SoldierAnimationService.setupRider({ rig = rig })
		rig.root.CFrame = CFrame.Angles(0, math.rad(-60), 0)
		camera.CFrame = CFrame.lookAt(Vector3.new(-4, 5.5, -17), Vector3.new(0, 2.6, 0))
	else
		local isArtillery = def.visual == "Artillery"
		rig = SoldierModels.infantry(world, team, def, not isArtillery, if isArtillery then "Rammer" else nil)
		rig.root.CFrame = CFrame.Angles(0, math.rad(20), 0) -- facing the camera, slightly turned
		if rig.motors.gun then
			rig.motors.gun.Transform = SoldierAnimationService.GUN_SHOULDER
		end
		SoldierModels.pose(rig, "armR", CFrame.Angles(0.3, 0, 0))
		camera.CFrame = CFrame.lookAt(Vector3.new(1.5, 1.4, -8.5), Vector3.new(0, 0.9, 0))
	end
end

---------------------------------------------------------------------------
-- Card
---------------------------------------------------------------------------

function UnitCard.new(parent: Instance, unitId: string, team: string, options: any?): any
	local opts = options or {}
	local def = UnitDefinitions.get(unitId)
	local compact = opts.compact == true
	local tierColor = UnitCard.TIER_COLORS[def.tier or 1]
	local width, height = if compact then 104 else 172, if compact then 132 else 236

	local button = create("TextButton", {
		Name = unitId,
		LayoutOrder = opts.layoutOrder or 0,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	Theme.corner(button, 10)
	create("UIGradient", {
		Color = ColorSequence.new(tierColor:Lerp(Color3.fromRGB(30, 30, 40), 0.55), Color3.fromRGB(16, 16, 22)),
		Rotation = 90,
		Parent = button,
	})
	local border = Theme.border(button, tierColor, if compact then 3 else 4)
	local scale = create("UIScale", { Parent = button })

	local portraitHolder = create("Frame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, if compact then 0.62 else 0.66, 0),
		BackgroundColor3 = Color3.fromRGB(20, 20, 26),
		BackgroundTransparency = 0.3,
		ClipsDescendants = true,
		Parent = button,
	})
	Theme.corner(portraitHolder, 8)
	portrait(portraitHolder, def, team)

	local name = outlined({
		Position = UDim2.new(0, 4, if compact then 0.62 else 0.66, 6),
		Size = UDim2.new(1, -8, 0, if compact then 16 else 22),
		Text = def.displayName,
		Font = Theme.Bold,
		TextSize = if compact then 13 else 19,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = button,
	}, 2)
	local subtitle = outlined({
		Position = UDim2.new(0, 4, if compact then 0.62 else 0.66, if compact then 22 else 30),
		Size = UDim2.new(1, -8, 0, 14),
		Text = "",
		TextSize = if compact then 11 else 13,
		TextColor3 = Color3.fromRGB(200, 200, 215),
		ZIndex = 3,
		Parent = button,
	}, 1.5)

	-- veteran stars (bottom-left)
	local stars = outlined({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -6),
		Size = UDim2.fromOffset(70, 18),
		Text = "",
		TextSize = if compact then 13 else 17,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Parent = button,
	}, 1.5)

	-- value (bottom-right): soldiers alive on the HUD card, "FREE" / stars in the shop
	local value = outlined({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -4),
		Size = UDim2.fromOffset(90, 26),
		Text = "",
		Font = Theme.Bold,
		TextSize = if compact then 15 else 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
		Parent = button,
	}, 2)

	-- count badge (top-right)
	local countBadge = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -6),
		Size = UDim2.fromOffset(34, 26),
		BackgroundColor3 = C.KeyRed,
		Visible = false,
		ZIndex = 6,
		Parent = button,
	})
	Theme.corner(countBadge, 6)
	Theme.border(countBadge, BLACK, 2)
	local countLabel = outlined({ Size = UDim2.fromScale(1, 1), TextSize = 16, ZIndex = 7, Parent = countBadge }, 1.5)

	-- key hint (top-left, compact cards)
	local keyBadge = Theme.keyBadge(button, "", C.KeyBlue, UDim2.fromOffset(-6, -6), nil, 22)
	keyBadge.Visible = false

	-- health bar (compact cards)
	local hpBack, hpFill = Theme.bar({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(1, -16, 0, 6),
		Visible = false,
		ZIndex = 4,
		Parent = button,
	}, Color3.fromRGB(90, 160, 255))
	Theme.corner(hpBack, 3)
	Theme.corner(hpFill, 3)

	-- lock overlay
	local lock = outlined({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.35,
		Text = "🔒",
		TextSize = 20,
		TextWrapped = true,
		Visible = false,
		ZIndex = 8,
		Parent = button,
	}, 1.5)
	Theme.corner(lock, 10)

	local self = setmetatable({
		button = button,
		def = def,
		tierColor = tierColor,
		border = border,
		scale = scale,
		stars = stars,
		value = value,
		name = name,
		subtitle = subtitle,
		countBadge = countBadge,
		countLabel = countLabel,
		keyBadge = keyBadge,
		hpBack = hpBack,
		hpFill = hpFill,
		lock = lock,
		selected = false,
	}, UnitCard)

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
		if tooltip and tooltipText and not compact then
			tooltipText.Text = statsText(def)
			local absolute = button.AbsolutePosition
			tooltip.Position = UDim2.fromOffset(absolute.X + button.AbsoluteSize.X + 10, absolute.Y)
			tooltip.Visible = true
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = if self.selected then 1.04 else 1 }):Play()
		if tooltip then
			tooltip.Visible = false
		end
	end)
	return self
end

function UnitCard:setCount(n: number)
	self.countBadge.Visible = n > 0
	self.countLabel.Text = "×" .. n
end

function UnitCard:setStars(n: number)
	self.stars.Text = string.rep("★", n)
end

function UnitCard:setLocked(locked: boolean, text: string?)
	self.lock.Visible = locked
	if text then
		self.lock.Text = text
	end
end

function UnitCard:setSelected(selected: boolean)
	self.selected = selected
	self.border.Color = if selected then Color3.new(1, 1, 1) else self.tierColor
	self.border.Thickness = if selected then 5 else 3
	self.scale.Scale = if selected then 1.04 else 1
end

function UnitCard:setHealth(fraction: number?)
	self.hpBack.Visible = fraction ~= nil
	if fraction then
		self.hpFill.Size = UDim2.fromScale(fraction, 1)
	end
end

function UnitCard:setSubtitle(text: string, color: Color3?)
	self.subtitle.Text = text
	self.subtitle.TextColor3 = color or Color3.fromRGB(200, 200, 215)
end

function UnitCard:setValue(text: string)
	self.value.Text = text
end

function UnitCard:setName(text: string)
	self.name.Text = text
end

function UnitCard:setKey(text: string?)
	self.keyBadge.Visible = text ~= nil
	local label = self.keyBadge:FindFirstChildOfClass("TextLabel")
	if label and text then
		label.Text = text
	end
end

function UnitCard:destroy()
	self.button:Destroy()
end

return UnitCard

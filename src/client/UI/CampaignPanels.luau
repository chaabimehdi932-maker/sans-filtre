--[[
	CampaignPanels — every screen of the mercenary campaign outside battles.
	  CreationScreen  (view "Creation"): pick the faction you will serve
	  OverworldHUD    (view "Overworld"):
	    top bar       day · gold · reputation rank (how many squads you command)
	    bottom        time controls ❚❚ ▶ ▶▶ (like Bannerlord)
	    left          your company: each squad's stars, headcount and XP
	    right         the active contract (status, deadline, Assault / Abandon)
	    bottom        the place you stand in: ENTER TOWN (walk in on foot), replenish, assault
	    modals        quest board, hiring
	    banners       "Ambush!" before a battle, "waiting for the battlefield"
	  TownHUD          (view "Town"): you walk around a real town and talk to its people
	    (ProximityPrompt → dialogue window): contracts, recruits, free companies,
	    quartermaster, arms merchant, rumours, the gate back to the map
	Everything is display only: every click is a CampaignAction the server validates.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CampaignConfig = require(Modules:WaitForChild("CampaignConfig"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local create, outlined = Theme.create, Theme.outlined
local BLACK = Color3.new(0, 0, 0)

local CampaignPanels = {}

local TONES = {
	good = Color3.fromRGB(120, 230, 130),
	bad = Color3.fromRGB(255, 120, 110),
	info = Color3.fromRGB(235, 235, 245),
}

local function panel(props: { [string]: any }): Frame
	local defaults = {
		BackgroundColor3 = Color3.fromRGB(22, 22, 30),
		BackgroundTransparency = 0.08,
		Active = true, -- clicks on panels don't march the army
	}
	for key, value in props do
		defaults[key] = value
	end
	local frame = create("Frame", defaults)
	Theme.corner(frame, 12)
	Theme.border(frame, BLACK, 3)
	create("UIScale", { Name = "FitScale", Parent = frame })
	return frame
end

-- Coloured cartoon button
local function button(props: { [string]: any }, label: string, color: Color3, onClick: () -> ()): TextButton
	local tile = Theme.tile(props)
	local gradient = tile:FindFirstChildOfClass("UIGradient") :: UIGradient
	gradient.Color = ColorSequence.new(color, color:Lerp(BLACK, 0.45))
	Theme.border(tile, BLACK, 3)
	outlined({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = label,
		Font = Theme.Bold,
		TextSize = props.TextSize or 18,
		ZIndex = (props.ZIndex or 1) + 1,
		Parent = tile,
	}, 2)
	tile.Activated:Connect(onClick)
	return tile
end

local function setButtonText(tile: TextButton, text: string)
	local label = tile:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = text
	end
end

function CampaignPanels.build(screen: ScreenGui, ClientState: any, ClientActions: any): any
	local api = {}
	local fitPanels: { Frame } = {}

	local function send(action: string, arg: any?)
		ClientActions.campaign(action, arg)
	end

	---------------------------------------------------------------------------
	-- Character creation: choose your employer
	---------------------------------------------------------------------------
	local creation = create("Frame", {
		Name = "CreationScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 10, 16),
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 30,
		Parent = screen,
	})
	api.creation = creation
	local creationPanel = panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1080, 600),
		ZIndex = 30,
		Parent = creation,
	})
	table.insert(fitPanels, creationPanel)
	outlined({
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 56),
		Text = "CHOOSE YOUR EMPLOYER",
		Font = Theme.Display,
		TextSize = 50,
		ZIndex = 31,
		Parent = creationPanel,
	}, 3)
	outlined({
		Position = UDim2.fromOffset(40, 80),
		Size = UDim2.new(1, -80, 0, 50),
		Text = "You are a mercenary captain, not a king. Take contracts from the faction you serve, "
			.. "get paid, grow your reputation and your company. Castles you take belong to your employer.",
		TextSize = 18,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(205, 205, 220),
		ZIndex = 31,
		Parent = creationPanel,
	}, 1.5)
	local factionRow = create("Frame", {
		Position = UDim2.fromOffset(30, 150),
		Size = UDim2.new(1, -60, 0, 420),
		BackgroundTransparency = 1,
		ZIndex = 31,
		Parent = creationPanel,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 26),
		Parent = factionRow,
	})
	for index, factionId in CampaignConfig.FactionOrder do
		local faction = CampaignConfig.Factions[factionId]
		local card = create("Frame", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(310, 400),
			BackgroundColor3 = Color3.fromRGB(30, 30, 40),
			ZIndex = 31,
			Parent = factionRow,
		})
		Theme.corner(card, 12)
		Theme.border(card, faction.color, 4)
		local bannerTop = create("Frame", {
			Size = UDim2.new(1, 0, 0, 150),
			BackgroundColor3 = faction.color,
			ZIndex = 32,
			Parent = card,
		})
		Theme.corner(bannerTop, 12)
		-- a little flag: coat colour + facing stripe
		local flag = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(120, 80),
			BackgroundColor3 = faction.uniform.coat,
			ZIndex = 33,
			Parent = bannerTop,
		})
		Theme.border(flag, BLACK, 3)
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, 34, 1, 0),
			BackgroundColor3 = faction.uniform.facing,
			BorderSizePixel = 0,
			ZIndex = 34,
			Parent = flag,
		})
		outlined({
			Position = UDim2.fromOffset(10, 162),
			Size = UDim2.new(1, -20, 0, 60),
			Text = faction.displayName,
			Font = Theme.Display,
			TextSize = 28,
			TextWrapped = true,
			ZIndex = 32,
			Parent = card,
		}, 2)
		outlined({
			Position = UDim2.fromOffset(16, 226),
			Size = UDim2.new(1, -32, 0, 80),
			Text = faction.description,
			TextSize = 17,
			TextWrapped = true,
			TextColor3 = Color3.fromRGB(205, 205, 220),
			ZIndex = 32,
			Parent = card,
		}, 1.5)
		button(
			{
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -18),
				Size = UDim2.fromOffset(220, 58),
				TextSize = 26,
				ZIndex = 32,
				Parent = card,
			},
			"SERVE " .. string.upper(faction.short),
			faction.color,
			function()
				send("ChooseFaction", factionId)
			end
		)
	end

	---------------------------------------------------------------------------
	-- Overworld HUD
	---------------------------------------------------------------------------
	local root = create("Frame", {
		Name = "OverworldHUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	})
	api.frame = root

	-- top bar -----------------------------------------------------------------
	local topBar = panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(1060, 64),
		Parent = root,
	})
	table.insert(fitPanels, topBar)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = topBar,
	})
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = topBar })
	local factionChip = create("Frame", {
		LayoutOrder = 1,
		Size = UDim2.fromOffset(170, 44),
		BackgroundColor3 = C.Blue,
		Parent = topBar,
	})
	Theme.corner(factionChip, 8)
	Theme.border(factionChip, BLACK, 2)
	local factionLabel = outlined({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Font = Theme.Bold,
		TextSize = 19,
		Parent = factionChip,
	}, 2)
	local function stat(order: number, width: number): TextLabel
		return outlined({
			LayoutOrder = order,
			Size = UDim2.fromOffset(width, 44),
			Text = "",
			Font = Theme.Bold,
			TextSize = 20,
			RichText = true,
			Parent = topBar,
		}, 2)
	end
	local dayLabel = stat(2, 110)
	local goldLabel = stat(3, 130)
	local repLabel = stat(4, 380)
	repLabel.TextSize = 16
	repLabel.TextWrapped = true
	local menuButton = button(
		{ LayoutOrder = 6, Size = UDim2.fromOffset(44, 44), TextSize = 22 },
		"☰",
		Color3.fromRGB(70, 70, 80),
		function() end
	)

	-- menu (new campaign) ---------------------------------------------------------
	local menu = panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, 530, 0, 84),
		Size = UDim2.fromOffset(300, 150),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	outlined({
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 50),
		Text = "Retire this company and start a new campaign? (commander level and unlocks are kept)",
		TextSize = 14,
		TextWrapped = true,
		ZIndex = 21,
		Parent = menu,
	}, 1.5)
	local confirmReset = false
	local resetButton: TextButton
	resetButton = button(
		{
			Position = UDim2.fromOffset(20, 76),
			Size = UDim2.new(1, -40, 0, 54),
			ZIndex = 21,
			Parent = menu,
		},
		"NEW CAMPAIGN",
		C.Red,
		function()
			if confirmReset then
				send("NewCampaign")
				menu.Visible = false
				confirmReset = false
				setButtonText(resetButton, "NEW CAMPAIGN")
			else
				confirmReset = true
				setButtonText(resetButton, "CLICK AGAIN TO CONFIRM")
			end
		end
	)
	menuButton.Activated:Connect(function()
		menu.Visible = not menu.Visible
		confirmReset = false
		setButtonText(resetButton, "NEW CAMPAIGN")
	end)

	-- company (left) -------------------------------------------------------------
	local company = panel({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 20),
		Size = UDim2.fromOffset(300, 440),
		Parent = root,
	})
	table.insert(fitPanels, company)
	local companyTitle = outlined({
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 28),
		Text = "YOUR COMPANY",
		Font = Theme.Display,
		TextSize = 22,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = company,
	}, 2)
	-- buttons under the squad list: prisoners, gear, officers
	local companyButtons = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -8),
		Size = UDim2.new(1, -20, 0, 36),
		BackgroundTransparency = 1,
		Parent = company,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = companyButtons,
	})
	local openCompanyModal: (kind: string) -> () = function() end
	button(
		{ LayoutOrder = 2, Size = UDim2.fromOffset(84, 34), TextSize = 13, Parent = companyButtons },
		"⚔ GEAR",
		Color3.fromRGB(90, 110, 150),
		function()
			openCompanyModal("Gear")
		end
	)
	local prisonersButton = button(
		{ LayoutOrder = 1, Size = UDim2.fromOffset(90, 34), TextSize = 13, Parent = companyButtons },
		"⛓ 0",
		Color3.fromRGB(110, 90, 70),
		function()
			openCompanyModal("Prisoners")
		end
	)
	local companyList = create("Frame", {
		Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 1, -94),
		BackgroundTransparency = 1,
		Parent = company,
	})
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = companyList })
	local rows: { [number]: any } = {}

	local function squadRow(entry: any): any
		local row = rows[entry.id]
		if row then
			return row
		end
		local frame = create("Frame", {
			Size = UDim2.new(1, 0, 0, 58),
			BackgroundColor3 = Color3.fromRGB(34, 34, 44),
			Parent = companyList,
		})
		Theme.corner(frame, 8)
		local def = UnitDefinitions.get(entry.unitId)
		local tierColor = ({
			Color3.fromRGB(165, 165, 175),
			Color3.fromRGB(70, 145, 255),
			Color3.fromRGB(175, 85, 245),
			Color3.fromRGB(255, 200, 50),
		})[def.tier or 1]
		Theme.border(frame, tierColor, 2)
		local name = outlined({
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -90, 0, 20),
			Text = "",
			Font = Theme.Bold,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		}, 1.5)
		local stars = outlined({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 4),
			Size = UDim2.fromOffset(80, 20),
			Text = "",
			TextColor3 = C.Gold,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		}, 1.5)
		local men = outlined({
			Position = UDim2.fromOffset(10, 25),
			Size = UDim2.new(1, -20, 0, 14),
			Text = "",
			TextSize = 13,
			TextColor3 = Color3.fromRGB(200, 200, 215),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		}, 1.2)
		local back, fill = Theme.bar({
			Position = UDim2.fromOffset(10, 44),
			Size = UDim2.new(1, -20, 0, 7),
		}, Color3.fromRGB(90, 160, 255))
		back.Parent = frame
		Theme.corner(back, 3)
		Theme.corner(fill, 3)
		-- branching evolution: this squad can choose what it becomes
		local pathButton = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 22),
			Size = UDim2.fromOffset(96, 18),
			BackgroundColor3 = C.Gold,
			Text = "⬆ CHOOSE PATH",
			Font = Theme.Bold,
			TextSize = 11,
			TextColor3 = BLACK,
			Visible = false,
			ZIndex = 3,
			Parent = frame,
		})
		Theme.corner(pathButton, 4)
		local squadId = entry.id
		pathButton.Activated:Connect(function()
			api.openBranch(squadId)
		end)
		row = {
			frame = frame,
			name = name,
			stars = stars,
			men = men,
			fill = fill,
			pathButton = pathButton,
			unitId = entry.unitId,
		}
		rows[entry.id] = row
		return row
	end

	-- contract (right) -----------------------------------------------------------
	local contractPanel = panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 90),
		Size = UDim2.fromOffset(340, 250),
		Parent = root,
	})
	table.insert(fitPanels, contractPanel)
	outlined({
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 28),
		Text = "CONTRACT",
		Font = Theme.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = contractPanel,
	}, 2)
	local contractText = outlined({
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -28, 0, 140),
		Text = "",
		TextSize = 16,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = contractPanel,
	}, 1.5)
	local assaultButton = button(
		{
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -12),
			Size = UDim2.fromOffset(180, 48),
			TextSize = 22,
			Parent = contractPanel,
		},
		"⚔ ASSAULT",
		C.Red,
		function()
			send("Assault")
		end
	)
	local abandonArmed = false
	local abandonButton: TextButton
	abandonButton = button(
		{
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -14, 1, -12),
			Size = UDim2.fromOffset(120, 40),
			TextSize = 14,
			Parent = contractPanel,
		},
		"ABANDON",
		Color3.fromRGB(90, 70, 70),
		function()
			if abandonArmed then
				send("AbandonContract")
				abandonArmed = false
				setButtonText(abandonButton, "ABANDON")
			else
				abandonArmed = true
				setButtonText(abandonButton, "SURE? (−REP)")
			end
		end
	)

	-- place (bottom) ---------------------------------------------------------------
	local placePanel = panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(760, 118),
		Visible = false,
		Parent = root,
	})
	table.insert(fitPanels, placePanel)
	local placeTitle = outlined({
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 32),
		Text = "",
		Font = Theme.Display,
		TextSize = 28,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = placePanel,
	}, 2)
	local placeButtons = create("Frame", {
		Position = UDim2.fromOffset(16, 50),
		Size = UDim2.new(1, -32, 0, 56),
		BackgroundTransparency = 1,
		Parent = placePanel,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = placeButtons,
	})

	-- modals ---------------------------------------------------------------------------
	local modal = create("Frame", {
		Name = "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.45,
		Active = true,
		Visible = false,
		ZIndex = 40,
		Parent = root,
	})
	local modalPanel = panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1000, 600),
		ZIndex = 40,
		Parent = modal,
	})
	table.insert(fitPanels, modalPanel)
	local modalTitle = outlined({
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -120, 0, 44),
		Text = "",
		Font = Theme.Display,
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
		Parent = modalPanel,
	}, 3)
	local modalBody = create("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 70),
		Size = UDim2.new(1, -40, 1, -90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 41,
		Parent = modalPanel,
	})
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(470, 250),
		CellPadding = UDim2.fromOffset(16, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = modalBody,
	})
	local modalKind: string? = nil
	local function closeModal()
		modal.Visible = false
		modalKind = nil
		send("Pause", false)
	end
	button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 16),
		Size = UDim2.fromOffset(48, 44),
		TextSize = 24,
		ZIndex = 42,
		Parent = modalPanel,
	}, "✕", C.Red, closeModal)

	local function clearModal()
		for _, child in modalBody:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function modalCard(order: number): Frame
		local card = create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Color3.fromRGB(34, 34, 44),
			ZIndex = 41,
			Parent = modalBody,
		})
		Theme.corner(card, 10)
		Theme.border(card, BLACK, 2)
		return card
	end

	local function fillBoard()
		clearModal()
		local campaign = ClientState.campaign
		modalTitle.Text = "QUEST BOARD"
		local board = campaign and campaign.board or {}
		if #board == 0 then
			local card = modalCard(1)
			outlined({
				Size = UDim2.fromScale(1, 1),
				Text = "No contracts right now. The board refreshes every "
					.. CampaignConfig.Contracts.BoardRefreshDays
					.. " days.",
				TextSize = 18,
				TextWrapped = true,
				ZIndex = 42,
				Parent = card,
			}, 1.5)
		end
		for index, contract in board do
			local info = CampaignConfig.Contracts.Types[contract.type]
			local card = modalCard(index)
			outlined({
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -28, 0, 26),
				Text = info.icon .. "  " .. string.upper(info.displayName) .. "  ·  " .. contract.title,
				Font = Theme.Bold,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 42,
				Parent = card,
			}, 1.5)
			outlined({
				Position = UDim2.fromOffset(14, 40),
				Size = UDim2.new(1, -28, 0, 84),
				Text = contract.description,
				TextSize = 15,
				TextWrapped = true,
				TextColor3 = Color3.fromRGB(205, 205, 220),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 42,
				Parent = card,
			}, 1.2)
			outlined({
				Position = UDim2.fromOffset(14, 128),
				Size = UDim2.new(1, -28, 0, 44),
				Text = string.format(
					'<font color="#FFCD28">💰 %d gold</font>   <font color="#8CD2FF">★ +%d reputation</font>   <font color="#FF8070">fail: −%d</font>\n%s  ·  danger %s',
					contract.gold,
					contract.reputation,
					contract.failReputation,
					if contract.type == "Garrison"
						then "attack in " .. contract.days .. " days"
						else contract.days .. " days to complete",
					string.rep("⚔", math.clamp(math.ceil((contract.strength or 1) / 2), 1, 6))
				),
				RichText = true,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 42,
				Parent = card,
			}, 1.2)
			button(
				{
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 14, 1, -12),
					Size = UDim2.fromOffset(200, 50),
					TextSize = 22,
					ZIndex = 42,
					Parent = card,
				},
				"✔ ACCEPT",
				C.Green,
				function()
					send("AcceptContract", contract.id)
					closeModal()
				end
			)
			button(
				{
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -14, 1, -12),
					Size = UDim2.fromOffset(150, 44),
					TextSize = 18,
					ZIndex = 42,
					Parent = card,
				},
				"DECLINE",
				Color3.fromRGB(90, 90, 100),
				function()
					send("DeclineContract", contract.id)
				end
			)
		end
	end

	local function fillHire()
		clearModal()
		local campaign = ClientState.campaign
		local recruit = ClientState.recruit
		modalTitle.Text = string.format(
			"HIRE SQUADS  ·  %d / %d",
			recruit and #recruit.roster or 0,
			recruit and recruit.maxRoster or CampaignConfig.Economy.MaxRosterSize
		)
		for index, unitId in UnitDefinitions.Order do
			local def = UnitDefinitions.get(unitId)
			local cost = math.floor((def.cost or 100) * CampaignConfig.Economy.HireCostMult)
			local unlocked = not recruit or recruit.unlocked[unitId] ~= false
			local card = modalCard(index)
			outlined({
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -28, 0, 28),
				Text = (def.icon or "") .. "  " .. def.displayName,
				Font = Theme.Bold,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 42,
				Parent = card,
			}, 1.5)
			outlined({
				Position = UDim2.fromOffset(14, 44),
				Size = UDim2.new(1, -28, 0, 110),
				Text = string.format(
					"%s\n\n%d soldiers · %d HP · speed %d · wage ~%d gold/day",
					def.description,
					def.soldiers,
					def.health,
					def.moveSpeed,
					math.ceil((def.cost or 100) * CampaignConfig.Wages.CostFraction)
				),
				TextSize = 15,
				TextWrapped = true,
				TextColor3 = Color3.fromRGB(205, 205, 220),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 42,
				Parent = card,
			}, 1.2)
			local affordable = campaign and campaign.gold >= cost
			button(
				{
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 14, 1, -12),
					Size = UDim2.fromOffset(260, 50),
					TextSize = 20,
					ZIndex = 42,
					Parent = card,
				},
				if unlocked
					then string.format("HIRE · 💰 %d", cost)
					else "🔒 Win " .. tostring(def.unlockRoundsWon) .. " battles",
				if unlocked and affordable then C.Green else Color3.fromRGB(90, 90, 100),
				function()
					send("Hire", unitId)
				end
			)
		end
	end

	local branchSquad: number? = nil
	local function fillBranch()
		clearModal()
		local recruit = ClientState.recruit
		local entry = nil
		for _, e in (recruit and recruit.roster or {}) do
			if e.id == branchSquad then
				entry = e
			end
		end
		if not entry or not entry.branchOptions then
			modalTitle.Text = "NOTHING TO CHOOSE"
			return
		end
		modalTitle.Text = "CHOOSE A PATH — " .. string.upper(entry.name)
		for index, unitId in entry.branchOptions do
			local def = UnitDefinitions.get(unitId)
			local card = modalCard(index)
			outlined({
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -28, 0, 28),
				Text = (def.icon or "") .. "  " .. def.displayName,
				Font = Theme.Bold,
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 42,
				Parent = card,
			}, 1.5)
			outlined({
				Position = UDim2.fromOffset(14, 44),
				Size = UDim2.new(1, -28, 0, 120),
				Text = string.format(
					"%s\n\n%d men · %d HP · speed %d · %s %d · morale %d",
					def.description,
					def.soldiers,
					def.health,
					def.moveSpeed,
					if def.attackType == "Melee" then "melee" else "volley",
					if def.attackType == "Melee" then def.meleeDamage else def.damage,
					def.morale
				),
				TextSize = 15,
				TextWrapped = true,
				TextColor3 = Color3.fromRGB(205, 205, 220),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 42,
				Parent = card,
			}, 1.2)
			button(
				{
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 14, 1, -12),
					Size = UDim2.fromOffset(280, 50),
					TextSize = 20,
					ZIndex = 42,
					Parent = card,
				},
				"BECOME " .. string.upper(def.displayName),
				C.Green,
				function()
					send("ChooseBranch", { squadId = entry.id, unitId = unitId })
					closeModal()
				end
			)
		end
	end

	local function fillPrisoners()
		clearModal()
		local campaign = ClientState.campaign
		local prisoners = campaign and campaign.prisoners or {}
		modalTitle.Text = string.format(
			"PRISONERS  %d/%d",
			campaign and campaign.prisonerCount or 0,
			campaign and campaign.prisonerCapacity or 0
		)
		local index = 0
		for unitId, count in prisoners do
			index += 1
			local def = UnitDefinitions.get(unitId)
			local card = modalCard(index)
			outlined({
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -28, 0, 28),
				Text = string.format("%s  %s ×%d", def.icon or "⛓", def.displayName, count),
				Font = Theme.Bold,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 42,
				Parent = card,
			}, 1.5)
			outlined({
				Position = UDim2.fromOffset(14, 46),
				Size = UDim2.new(1, -28, 0, 100),
				Text = string.format(
					"Offer them your coin: each has a %d%% chance to join. With %d or more of them you can try to form a squad (up to %d men); the others are let go.\n\nOr sell them to the ransom broker in your employer's town.",
					math.floor(CampaignConfig.Prisoners.RecruitChance * 100),
					CampaignConfig.Prisoners.MinToRecruit,
					def.soldiers
				),
				TextSize = 14,
				TextWrapped = true,
				TextColor3 = Color3.fromRGB(205, 205, 220),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 42,
				Parent = card,
			}, 1.2)
			button(
				{
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 14, 1, -12),
					Size = UDim2.fromOffset(260, 48),
					TextSize = 18,
					ZIndex = 42,
					Parent = card,
				},
				"⚑ TRY TO RECRUIT",
				if count >= CampaignConfig.Prisoners.MinToRecruit then C.Green else Color3.fromRGB(90, 90, 100),
				function()
					send("RecruitPrisoners", unitId)
					closeModal()
				end
			)
		end
		if index == 0 then
			local card = modalCard(1)
			outlined({
				Size = UDim2.fromScale(1, 1),
				Text = "No prisoners. Enemies who flee the field are captured when you win.",
				TextSize = 18,
				TextWrapped = true,
				ZIndex = 42,
				Parent = card,
			}, 1.5)
		end
	end

	local function itemStats(item: any): string
		if item.slot == "weapon" then
			return string.format("damage ×%.2f", item.damageMult)
		elseif item.slot == "armor" then
			return string.format(
				"+%d HP%s",
				item.hp,
				if item.speedMult then string.format(" · speed ×%.2f", item.speedMult) else ""
			)
		end
		return string.format("speed %d · charge ×%.1f", item.speed, item.charge)
	end

	-- Gear (equip what you own) and shops (buy in town): same list, different buttons
	local shopSlots: { string }? = nil
	local function fillItems()
		clearModal()
		local campaign = ClientState.campaign
		if not campaign then
			return
		end
		local owned = {}
		for _, id in campaign.items or {} do
			owned[id] = true
		end
		local gear = campaign.gear or {}
		modalTitle.Text = if shopSlots then "SHOP" else "YOUR GEAR"
		local order = 0
		for _, id in CampaignConfig.ItemOrder do
			local item = CampaignConfig.Items[id]
			local inShop = shopSlots ~= nil
				and table.find(shopSlots :: { string }, item.slot) ~= nil
				and not item.lootOnly
			if (shopSlots == nil and owned[id]) or inShop then
				order += 1
				local card = modalCard(order)
				local equipped = gear[item.slot] == id
				outlined({
					Position = UDim2.fromOffset(14, 10),
					Size = UDim2.new(1, -28, 0, 28),
					Text = string.format(
						"%s  %s%s",
						({ weapon = "⚔", armor = "🛡", horse = "🐎" })[item.slot],
						item.name,
						if equipped then "  (equipped)" else ""
					),
					Font = Theme.Bold,
					TextSize = 22,
					TextColor3 = if equipped then C.Gold else C.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 42,
					Parent = card,
				}, 1.5)
				outlined({
					Position = UDim2.fromOffset(14, 46),
					Size = UDim2.new(1, -28, 0, 60),
					Text = string.upper(item.slot) .. " · " .. itemStats(item),
					TextSize = 17,
					TextColor3 = Color3.fromRGB(205, 205, 220),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 42,
					Parent = card,
				}, 1.2)
				local label, color, action
				if owned[id] then
					label = if equipped then "EQUIPPED" else "EQUIP"
					color = if equipped then Color3.fromRGB(90, 90, 100) else C.Blue
					action = "EquipItem"
				else
					label = string.format("BUY · 💰 %d", item.price)
					color = if campaign.gold >= item.price then C.Green else Color3.fromRGB(90, 90, 100)
					action = "BuyItem"
				end
				button(
					{
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.new(0, 14, 1, -12),
						Size = UDim2.fromOffset(240, 48),
						TextSize = 19,
						ZIndex = 42,
						Parent = card,
					},
					label,
					color,
					function()
						send(action, id)
					end
				)
			end
		end
	end

	local function openModal(kind: string)
		modalKind = kind
		modal.Visible = true
		send("Pause", true)
		if kind == "Board" then
			fillBoard()
		elseif kind == "Prisoners" then
			fillPrisoners()
		elseif kind == "Gear" then
			shopSlots = nil
			fillItems()
		elseif kind == "ShopArms" then
			shopSlots = { "weapon", "armor" }
			fillItems()
		elseif kind == "ShopHorses" then
			shopSlots = { "horse" }
			fillItems()
		elseif kind == "Branch" then
			fillBranch()
		else
			fillHire()
		end
	end

	openCompanyModal = openModal

	function api.openBranch(squadId: number)
		branchSquad = squadId
		openModal("Branch")
	end

	-- place buttons ------------------------------------------------------------------
	local enterButton = button(
		{ LayoutOrder = 0, Size = UDim2.fromOffset(300, 56), TextSize = 22, Parent = placeButtons },
		"🚶 ENTER THE TOWN",
		Color3.fromRGB(190, 140, 60),
		function()
			send("EnterTown")
		end
	)
	local boardButton = button(
		{ LayoutOrder = 1, Size = UDim2.fromOffset(210, 56), TextSize = 20, Parent = placeButtons },
		"📜 QUEST BOARD",
		Color3.fromRGB(190, 140, 60),
		function()
			openModal("Board")
		end
	)
	local hireButton = button(
		{ LayoutOrder = 2, Size = UDim2.fromOffset(170, 56), TextSize = 20, Parent = placeButtons },
		"⚑ HIRE",
		C.Blue,
		function()
			openModal("Hire")
		end
	)
	local replenishButton = button(
		{ LayoutOrder = 3, Size = UDim2.fromOffset(250, 56), TextSize = 18, Parent = placeButtons },
		"✚ REPLENISH",
		C.Green,
		function()
			send("Replenish")
		end
	)
	local placeAssault = button(
		{ LayoutOrder = 4, Size = UDim2.fromOffset(200, 56), TextSize = 22, Parent = placeButtons },
		"⚔ ASSAULT",
		C.Red,
		function()
			send("Assault")
		end
	)

	-- time controls (bottom centre) ------------------------------------------------------
	local timeBar = panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(330, 30),
		Parent = root,
	})
	table.insert(fitPanels, timeBar)
	local timeButtons = {}
	for i, info in { { "Pause", "❚❚" }, { "Play", "▶" }, { "Fast", "▶▶" } } do
		local tile = button(
			{
				Position = UDim2.fromOffset(6 + (i - 1) * 50, 3),
				Size = UDim2.fromOffset(44, 24),
				TextSize = 15,
				Parent = timeBar,
			},
			info[2],
			Color3.fromRGB(80, 80, 95),
			function()
				send("TimeMode", info[1])
			end
		)
		timeButtons[info[1]] = tile
	end
	local timeLabel = outlined({
		Position = UDim2.fromOffset(160, 0),
		Size = UDim2.new(1, -168, 1, 0),
		Text = "",
		Font = Theme.Bold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = timeBar,
	}, 1.5)

	-- enlisting with a general -------------------------------------------------------------
	local enlistPanel = panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -170),
		Size = UDim2.fromOffset(760, 86),
		Visible = false,
		Parent = root,
	})
	table.insert(fitPanels, enlistPanel)
	local enlistText = outlined({
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -250, 1, -16),
		Text = "",
		TextSize = 16,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = enlistPanel,
	}, 1.5)
	local enlistTarget: number? = nil
	local enlistButton: TextButton
	enlistButton = button(
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(220, 56),
			TextSize = 20,
			Parent = enlistPanel,
		},
		"⚑ ENLIST",
		Color3.fromRGB(190, 140, 60),
		function()
			local campaign = ClientState.campaign
			if campaign and campaign.enlisted then
				send("LeaveService")
			elseif enlistTarget then
				send("Enlist", enlistTarget)
			end
		end
	)

	local function refreshEnlist()
		local campaign = ClientState.campaign
		local world = ClientState.world
		if not campaign or campaign.view ~= "Overworld" then
			enlistPanel.Visible = false
			return
		end
		local enlisted = campaign.enlisted
		if enlisted then
			enlistPanel.Visible = true
			enlistText.Text = string.format(
				'<font color="#FFCD28"><b>⚑ Serving %s as %s</b></font> — you lead his %s in battle, your company rests in camp.\n💰 %d gold a day  ·  %d battle%s fought%s',
				enlisted.lordName,
				enlisted.title,
				UnitDefinitions.get(enlisted.unit).displayName,
				enlisted.wage,
				enlisted.battles,
				if enlisted.battles == 1 then "" else "s",
				if enlisted.nextRank
					then string.format("  ·  %s at %d", enlisted.nextTitle, enlisted.nextRank)
					else "  ·  highest rank"
			)
			setButtonText(enlistButton, "LEAVE SERVICE")
			return
		end
		enlistTarget = nil
		local lordName = nil
		if world then
			for _, party in world.parties do
				if party.kind == "Lord" and party.faction == campaign.faction then
					local distance = math.sqrt((party.x - world.x) ^ 2 + (party.z - world.z) ^ 2)
					if distance <= CampaignConfig.Enlist.EnlistRadius then
						enlistTarget = party.id
						lordName = party.name
					end
				end
			end
		end
		enlistPanel.Visible = enlistTarget ~= nil
		if enlistTarget then
			local rank = CampaignConfig.Enlist.Ranks[1]
			enlistText.Text = string.format(
				'<font color="#FFCD28"><b>%s</b></font> is here. Enlist: you march with him and lead one of his squads (%s) in his battles — your own company stays safe.\n💰 %d gold a day + a share of the loot · leave whenever you like',
				lordName,
				UnitDefinitions.get(rank.unit).displayName,
				CampaignConfig.Enlist.WagePerDay * rank.wageMult
			)
			setButtonText(enlistButton, "⚑ ENLIST")
		end
	end

	-- town HUD (view "Town") ------------------------------------------------------------
	local townBar = panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(640, 70),
		Visible = false,
		Parent = root,
	})
	table.insert(fitPanels, townBar)
	local townTitle = outlined({
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -220, 0, 32),
		Text = "",
		Font = Theme.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = townBar,
	}, 2)
	outlined({
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -220, 0, 22),
		Text = "Walk up to people and press E to talk  ·  the gate guard takes you back to the map",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(215, 215, 225),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = townBar,
	}, 1.2)
	button(
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(190, 50),
			TextSize = 20,
			Parent = townBar,
		},
		"🗺 LEAVE TOWN",
		Color3.fromRGB(90, 90, 110),
		function()
			send("LeaveTown")
		end
	)

	-- dialogue window (talking to townspeople) ---------------------------------------------
	local dialogue = panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.fromOffset(720, 330),
		Visible = false,
		ZIndex = 30,
		Parent = root,
	})
	table.insert(fitPanels, dialogue)
	local speaker = outlined({
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -40, 0, 30),
		Text = "",
		Font = Theme.Display,
		TextSize = 26,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
		Parent = dialogue,
	}, 2)
	local speech = outlined({
		Position = UDim2.fromOffset(20, 44),
		Size = UDim2.new(1, -40, 0, 70),
		Text = "",
		TextSize = 17,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 31,
		Parent = dialogue,
	}, 1.5)
	local options = create("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 120),
		Size = UDim2.new(1, -40, 1, -130),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 31,
		Parent = dialogue,
	})
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = options })
	local talkingTo: Instance? = nil
	local talkingRole: string? = nil
	local rumourIndex = 0

	local function closeDialogue()
		dialogue.Visible = false
		talkingTo = nil
		talkingRole = nil
	end

	local function addOption(order: number, text: string, color: Color3, onClick: () -> ())
		button({
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 40),
			TextSize = 17,
			ZIndex = 32,
			Parent = options,
		}, text, color, onClick)
	end

	local function compass(dx: number, dz: number): string
		local names = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
		-- map +z is "north" on screen (the top of the map)
		local angle = math.atan2(dx, dz)
		local index = math.floor((angle / (math.pi * 2)) * 8 + 0.5) % 8 + 1
		return names[index]
	end

	local function rumours(): { string }
		local list = {}
		local world = ClientState.world
		local campaign = ClientState.campaign
		if not world then
			return { "Quiet times, captain. Too quiet." }
		end
		local contract = campaign and campaign.contract
		for _, party in world.parties do
			local dx, dz = party.x - world.x, party.z - world.z
			local distance = math.sqrt(dx * dx + dz * dz)
			local days = distance / CampaignConfig.Travel.ArmySpeed
			if contract and contract.targetParty == party.id then
				table.insert(
					list,
					1,
					string.format(
						"<b>%s</b>? A tinker saw them %s of here, about %.1f days' march. Watch yourself.",
						party.name,
						compass(dx, dz),
						days
					)
				)
			elseif party.hostile and distance < 400 then
				table.insert(
					list,
					string.format(
						"Travellers talk of a <b>%s</b> (%s) to the %s, %.1f days away.",
						party.name,
						string.rep("⚔", math.min(5, party.strength or 1)),
						compass(dx, dz),
						days
					)
				)
			end
		end
		table.insert(list, "Stay on the roads if you can. Bandits love the wild country.")
		table.insert(list, "They say the free companies at my tables have seen more battles than the Emperor.")
		return list
	end

	local function openDialogue(role: string, npc: Instance?)
		local campaign = ClientState.campaign
		local recruit = ClientState.recruit
		if not campaign then
			return
		end
		talkingTo = npc
		talkingRole = role
		dialogue.Visible = true
		for _, child in options:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local name = npc and npc:GetAttribute("DisplayName") or role
		speaker.Text = tostring(name)
		local bye = Color3.fromRGB(80, 80, 90)
		if role == "Guildmaster" then
			speech.Text = "Looking for work, captain? My employers pay well for steel and discretion."
			addOption(1, "📜 Show me the contracts", Color3.fromRGB(190, 140, 60), function()
				closeDialogue()
				openModal("Board")
			end)
			if campaign.contract then
				addOption(2, "✘ I'm giving up my current contract (−reputation)", C.Red, function()
					send("AbandonContract")
					closeDialogue()
				end)
			end
		elseif role == "Recruiter" then
			speech.Text = "Fresh volunteers, drilled on this very square. Pay their bounty and they march with you."
			addOption(1, "⚑ I want to hire soldiers", C.Blue, function()
				closeDialogue()
				openModal("Hire")
			end)
		elseif role == "Quartermaster" then
			local cost = recruit and recruit.replenishCost or 0
			speech.Text = if cost > 0
				then string.format("Your ranks are thin. I can fill them for <b>%d gold</b>.", cost)
				else "Your company is at full strength, captain. Nothing to fill."
			if cost > 0 then
				addOption(1, string.format("✚ Replenish every squad (💰 %d)", cost), C.Green, function()
					send("Replenish")
					closeDialogue()
				end)
			end
		elseif role == "MercCaptain" then
			speech.Text = "My lads have seen a few fields. They don't come cheap — but they don't break either."
			local offers = campaign.mercenaries or {}
			if #offers == 0 then
				speech.Text ..= "\n<i>(Everyone's already hired. Come back in a few days.)</i>"
			end
			for i, offer in offers do
				local def = UnitDefinitions.get(offer.unitId)
				addOption(
					i,
					string.format(
						"%s %s veterans %s · %d men  (💰 %d)",
						def.icon or "",
						def.displayName,
						string.rep("★", offer.stars),
						def.soldiers,
						offer.cost
					),
					if campaign.gold >= offer.cost then C.Green else Color3.fromRGB(90, 90, 100),
					function()
						send("HireMercenary", offer.id)
						closeDialogue()
					end
				)
			end
		elseif role == "ArmsMerchant" then
			addOption(0, "⚔ Swords and armour for myself", Color3.fromRGB(190, 140, 60), function()
				closeDialogue()
				openCompanyModal("ShopArms")
			end)
			speech.Text = string.format(
				"Better muskets, sharper sabres, and a sergeant to drill them. <b>+%d XP</b> to one squad.",
				CampaignConfig.Town.DrillXP
			)
			for i, entry in (recruit and recruit.roster or {}) do
				local cost =
					math.floor(CampaignConfig.Town.DrillCost * (1 + entry.stars * CampaignConfig.Town.DrillCostPerStar))
				addOption(
					i,
					string.format(
						"%s %s  ·  XP %d%s  (💰 %d)",
						entry.name,
						string.rep("★", entry.stars),
						entry.xp,
						if entry.nextXP then "/" .. entry.nextXP else "",
						cost
					),
					if campaign.gold >= cost then C.Green else Color3.fromRGB(90, 90, 100),
					function()
						send("Drill", entry.id)
						task.delay(0.3, function()
							if talkingRole == "ArmsMerchant" then
								openDialogue("ArmsMerchant", talkingTo)
							end
						end)
					end
				)
			end
		elseif role == "Innkeeper" then
			local list = rumours()
			rumourIndex = rumourIndex % #list + 1
			speech.Text = list[rumourIndex]
			addOption(1, "🍺 Heard anything else?", Color3.fromRGB(190, 140, 60), function()
				openDialogue("Innkeeper", talkingTo)
			end)
		elseif role == "HorseTrader" then
			speech.Text = "Good horses, captain. A fast one keeps you alive, a heavy one breaks their lines."
			addOption(1, "🐎 Show me your horses", Color3.fromRGB(190, 140, 60), function()
				closeDialogue()
				openCompanyModal("ShopHorses")
			end)
		elseif role == "RansomBroker" then
			local value = campaign.ransomValue or 0
			speech.Text = if (campaign.prisonerCount or 0) > 0
				then string.format(
					"%d prisoners? Families and regiments pay to get their men back. I'll give you <b>%d gold</b> for the lot.",
					campaign.prisonerCount,
					value
				)
				else "Bring me prisoners, captain. Families and regiments pay well to get their men back."
			if value > 0 then
				addOption(1, string.format("⛓ Ransom every prisoner (💰 %d)", value), C.Green, function()
					send("RansomPrisoners")
					closeDialogue()
				end)
			end
		elseif role == "Gate" then
			speech.Text = "Heading out, captain? The road awaits."
			addOption(1, "🗺 Back to the map", C.Blue, function()
				closeDialogue()
				send("LeaveTown")
			end)
		end
		addOption(99, "Goodbye.", bye, closeDialogue)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local role = prompt:GetAttribute("Role")
		if typeof(role) == "string" and ClientState.view() == "Town" then
			openDialogue(role, prompt.Parent and prompt.Parent.Parent)
		end
	end)

	-- banners / notices / hints -------------------------------------------------------
	local encounterBanner = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(900, 150),
		BackgroundColor3 = Color3.fromRGB(120, 20, 25),
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 50,
		Parent = screen,
	})
	Theme.corner(encounterBanner, 14)
	Theme.border(encounterBanner, BLACK, 4)
	local encounterScale = create("UIScale", { Parent = encounterBanner })
	local encounterTitle = outlined({
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 70),
		Text = "TO ARMS!",
		Font = Theme.Display,
		TextSize = 64,
		TextColor3 = C.Gold,
		ZIndex = 51,
		Parent = encounterBanner,
	}, 4)
	local encounterText = outlined({
		Position = UDim2.fromOffset(20, 90),
		Size = UDim2.new(1, -40, 0, 40),
		Text = "",
		TextSize = 24,
		ZIndex = 51,
		Parent = encounterBanner,
	}, 2)

	local queueNotice = outlined({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(620, 36),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		Text = "⏳ Another commander is using the battlefield — your battle starts right after.",
		TextSize = 17,
		Visible = false,
		Parent = root,
	}, 1.5)
	Theme.corner(queueNotice, 8)

	local hintLine = outlined({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -44),
		Size = UDim2.fromOffset(700, 20),
		Text = "Click the map or a banner to march  ·  Wheel zoom  ·  Right-drag rotate  ·  WASD pan  ·  Space recentre",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(215, 215, 225),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	}, 1.5)

	local feed = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -40),
		Size = UDim2.fromOffset(560, 190),
		BackgroundTransparency = 1,
		Parent = root,
	})
	create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = feed,
	})
	local toastOrder = 0
	function api.notify(message: string, tone: string?)
		toastOrder += 1
		local toast = outlined({
			LayoutOrder = toastOrder,
			Size = UDim2.new(1, 0, 0, 22),
			Text = message,
			TextSize = 17,
			TextColor3 = TONES[tone or "info"] or C.Text,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = feed,
		}, 2)
		for _, child in feed:GetChildren() do
			if child:IsA("TextLabel") and child.LayoutOrder <= toastOrder - 7 then
				child:Destroy()
			end
		end
		task.delay(6, function()
			if toast.Parent then
				TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
				task.delay(0.5, function()
					toast:Destroy()
				end)
			end
		end)
	end

	---------------------------------------------------------------------------
	-- Refresh
	---------------------------------------------------------------------------
	local function refreshCompany()
		local recruit = ClientState.recruit
		if not recruit or not recruit.roster then
			return
		end
		companyTitle.Text = string.format(
			'YOUR COMPANY %d/%d  <font size="15" color="%s">💰 %d/day%s</font>',
			#recruit.roster,
			recruit.maxRoster or 6,
			if (recruit.unpaidDays or 0) > 0 then "#FF8070" else "#FFCD28",
			recruit.dailyWages or 0,
			if (recruit.unpaidDays or 0) > 0 then string.format("  UNPAID %.1f d!", recruit.unpaidDays) else ""
		)
		local seen = {}
		for index, entry in recruit.roster do
			seen[entry.id] = true
			local existing = rows[entry.id]
			if existing and existing.unitId ~= entry.unitId then
				existing.frame:Destroy() -- evolved into another unit: rebuild its row
				rows[entry.id] = nil
			end
			local row = squadRow(entry)
			row.frame.LayoutOrder = index
			row.name.Text = entry.name
			row.stars.Text = if entry.stars > 0 then string.rep("★", entry.stars) else "recruits"
			row.stars.TextColor3 = if entry.stars > 0 then C.Gold else Color3.fromRGB(160, 160, 170)
			row.men.Text = string.format(
				"%d / %d men   ·   XP %d%s",
				entry.soldiers,
				entry.maxSoldiers,
				entry.xp,
				if entry.nextXP then " / " .. entry.nextXP else " (max)"
			)
			row.fill.Size = UDim2.fromScale(entry.soldiers / entry.maxSoldiers, 1)
			row.pathButton.Visible = entry.branchOptions ~= nil
		end
		for id, row in rows do
			if not seen[id] then
				row.frame:Destroy()
				rows[id] = nil
			end
		end
		setButtonText(
			replenishButton,
			if (recruit.replenishCost or 0) > 0
				then string.format("✚ REPLENISH · 💰 %d", recruit.replenishCost)
				else "✚ FULL STRENGTH"
		)
		if modal.Visible and modalKind == "Hire" then
			fillHire()
		end
	end
	api.onRecruit = refreshCompany

	function api.onCampaign()
		local campaign = ClientState.campaign
		if not campaign then
			return
		end
		local faction = campaign.faction and CampaignConfig.Factions[campaign.faction]
		if faction then
			factionChip.BackgroundColor3 = faction.color
			factionLabel.Text = "⚑ " .. faction.short
		end
		goldLabel.Text = string.format('<font color="#FFCD28">💰 %d</font>', campaign.gold or 0)
		local tier, nextTier = campaign.tier, campaign.nextTier
		if tier then
			repLabel.Text = string.format(
				'<font color="#8CD2FF">★ %d reputation · %s</font>  —  command <b>%d</b> squad%s%s',
				campaign.reputation,
				tier.title,
				tier.maxSquads,
				if tier.maxSquads > 1 then "s" else "",
				if nextTier
					then string.format("  (next: %d → %d)", nextTier.reputation, nextTier.maxSquads)
					else "  (max)"
			)
		end

		-- contract
		local contract = campaign.contract
		abandonArmed = false
		setButtonText(abandonButton, "ABANDON")
		if contract then
			local info = CampaignConfig.Contracts.Types[contract.type]
			contractText.Text = string.format(
				'<b>%s %s</b>\n%s\n<font color="#C8C8D2">%s</font>\n<font color="#FFCD28">💰 %d</font>  <font color="#8CD2FF">★ +%d</font>',
				info.icon,
				contract.title,
				contract.status or "",
				if contract.daysLeft
					then string.format("%.1f days left", math.max(0, contract.daysLeft))
					else "no deadline",
				contract.gold,
				contract.reputation
			)
			assaultButton.Visible = contract.canAssault == true
			abandonButton.Visible = true
		else
			local town = nil
			for _, location in CampaignConfig.Locations do
				if location.kind == "Town" and location.faction == campaign.faction then
					town = location
				end
			end
			contractText.Text = "No contract.\nVisit the quest board in "
				.. (if town then town.name else "your employer's town")
				.. " to find work."
			assaultButton.Visible = false
			abandonButton.Visible = false
		end

		-- the place you stand in
		local here = campaign.atLocation and CampaignConfig.getLocation(campaign.atLocation)
		local inTown = campaign.view == "Town"
		placePanel.Visible = here ~= nil and not inTown
		townBar.Visible = inTown
		timeBar.Visible = not inTown
		hintLine.Visible = not inTown
		if not inTown and dialogue.Visible then
			closeDialogue()
		end
		if inTown and here then
			townTitle.Text = string.upper(here.name)
		end
		for mode, tile in timeButtons do
			local stroke = tile:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if campaign.timeMode == mode then C.Gold else BLACK
			end
		end
		if here then
			local owner = campaign.owners and campaign.owners[here.id] or here.faction
			local ownerInfo = CampaignConfig.Factions[owner]
			local friendly = owner == campaign.faction
			placeTitle.Text = string.format(
				'%s  <font size="18" color="#%s">%s · %s</font>',
				here.name,
				(ownerInfo and ownerInfo.color or Color3.new(1, 1, 1)):ToHex(),
				if here.kind == "BanditCamp" then "Bandit camp" else here.kind,
				if ownerInfo then ownerInfo.short else owner
			)
			enterButton.Visible = friendly and here.kind == "Town"
			boardButton.Visible = false -- done by talking to people in town now
			hireButton.Visible = false
			replenishButton.Visible = friendly and here.kind == "Castle"
			placeAssault.Visible = contract ~= nil and contract.canAssault == true
		end
		queueNotice.Visible = campaign.queued == true
		setButtonText(
			prisonersButton,
			string.format("⛓ %d/%d", campaign.prisonerCount or 0, campaign.prisonerCapacity or 0)
		)
		if modal.Visible and modalKind == "Prisoners" then
			fillPrisoners()
		elseif modal.Visible and (modalKind == "Gear" or modalKind == "ShopArms" or modalKind == "ShopHorses") then
			fillItems()
		end
		if campaign.enlisted then
			placePanel.Visible = false
		end
		refreshEnlist()
		if modal.Visible and modalKind == "Board" then
			fillBoard()
		end
		refreshCompany()
	end

	function api.onTick()
		local world = ClientState.world
		if not world then
			return
		end
		dayLabel.Text = string.format("📅 Day %d", math.floor(world.day) + 1)
		refreshEnlist()
		local seasons = { "Spring", "Summer", "Autumn", "Winter" }
		local day = math.floor(world.day)
		timeLabel.Text = string.format(
			"%s, day %d%s",
			seasons[math.floor(day / 21) % 4 + 1],
			day % 21 + 1,
			if world.timeMode == "Pause" then "  ·  PAUSED" else ""
		)
	end

	function api.onEncounter(data: any)
		encounterTitle.Text = if data.faction == "Bandits" then "AMBUSH!" else "TO ARMS!"
		encounterText.Text = data.title or ""
		encounterBanner.Visible = true
		encounterScale.Scale = 0.6
		TweenService:Create(encounterScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(CampaignConfig.Travel.EncounterWarning + 1.5, function()
			encounterBanner.Visible = false
		end)
	end

	-- close the conversation if you walk away
	function api.render()
		if dialogue.Visible and talkingTo then
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local npcRoot = talkingTo:FindFirstChild("HumanoidRootPart")
			if
				root
				and npcRoot
				and root:IsA("BasePart")
				and npcRoot:IsA("BasePart")
				and (root.Position - npcRoot.Position).Magnitude > 16
			then
				closeDialogue()
			end
		end
	end

	function api.hideEncounter()
		encounterBanner.Visible = false
	end

	function api.layout(viewport: Vector2)
		local scale = math.clamp(math.min(viewport.X / 1600, viewport.Y / 900), 0.45, 1.25)
		for _, frame in fitPanels do
			local fit = frame:FindFirstChild("FitScale") :: UIScale?
			if fit then
				fit.Scale = scale
			end
		end
		menu.Position = UDim2.new(0.5, 530 * scale, 0, 84 * scale)
		company.Visible = viewport.X / scale >= 1100
	end

	return api
end

return CampaignPanels

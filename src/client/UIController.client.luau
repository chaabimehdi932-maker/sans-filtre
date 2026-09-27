--[[
	UIController
	Builds every screen inside PlayerGui.MainHUD (one ScreenGui) and routes server state
	(via ClientState) to them. No game state lives in the UI.

	Screen router — exactly one screen is visible at a time (Visible = false on the others,
	never just transparency). The campaign view comes first:
	  Creation  → CreationScreen (choose your employer)
	  Overworld → OverworldHUD (map panels; the map itself is OverworldController)
	  Battle    → by battle phase: Recruitment → DeployScreen · Battle → BattleHUD
	              Reward → SummaryScreen · Waiting → WaitingScreen
	The battle HUD re-flows on every viewport change (Hud.layout), panels fit the screen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local SoldierModels = require(script.Parent:WaitForChild("SoldierModels"))
local UI = script.Parent:WaitForChild("UI")
local CampaignPanels = require(UI:WaitForChild("CampaignPanels"))
local Effects = require(UI:WaitForChild("Effects"))
local Hud = require(UI:WaitForChild("Hud"))
local Markers = require(UI:WaitForChild("Markers"))
local RecruitPanel = require(UI:WaitForChild("RecruitPanel"))
local SummaryPanel = require(UI:WaitForChild("SummaryPanel"))
local Theme = require(UI:WaitForChild("Theme"))
local UnitCard = require(UI:WaitForChild("UnitCard"))

local screen = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MainHUD") :: ScreenGui

print(
	"[Napoleonic Commander] client version "
		.. require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("GameConfig")).Version
)

-- Our own HUD replaces Roblox's health bar and backpack
for _, coreType in { Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreType, false)
	end)
end

local hud = Hud.build(screen, ClientState, ClientActions)
local markers = Markers.build(screen, ClientState, ClientActions, hud.regions)
local recruit = RecruitPanel.build(screen, ClientState)
local summary = SummaryPanel.build(screen, ClientState)
local effects = Effects.build(screen)
local campaign = CampaignPanels.build(screen, ClientState, ClientActions)
local CampaignConfig =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CampaignConfig"))
UnitCard.attachTooltipLayer(screen)

local waiting = Theme.create("Frame", {
	Name = "WaitingScreen",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = true,
	Parent = screen,
})
Theme.outlined({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromOffset(600, 60),
	Text = "Preparing the battlefield…",
	Font = Theme.Display,
	TextSize = 40,
	Parent = waiting,
}, 3)

local SCREENS = {
	Waiting = waiting,
	Recruitment = recruit.frame,
	Battle = hud.frame,
	Reward = summary.frame,
	Creation = campaign.creation,
	Overworld = campaign.frame,
}
local currentPhase = nil

-- the screen to show: the campaign view, or the battle phase while in a battle
local function currentScreen(): string
	local view = ClientState.view()
	if view == "Creation" or view == "Overworld" then
		return view
	end
	return ClientState.phaseName()
end

local function showPhase(_phase: string?)
	local phase = currentScreen()
	if phase == currentPhase then
		return
	end
	currentPhase = phase
	for name, frame in SCREENS do
		frame.Visible = name == phase
	end
	local panel = if phase == "Recruitment" then recruit.panel elseif phase == "Reward" then summary.panel else nil
	if panel then
		effects.popIn(panel)
	end
end

-- Fit panels and re-flow the HUD for the current screen size (16:9 desktop … phone portrait)
local function layout()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	hud.layout(viewport)
	campaign.layout(viewport)
	for _, panel in { recruit.panel, summary.panel } do
		local fit = panel:FindFirstChild("FitScale") :: UIScale?
		if fit then
			fit.Scale = math.min(1, (viewport.X - 24) / panel.Size.X.Offset, (viewport.Y - 24) / panel.Size.Y.Offset)
		end
	end
end
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
layout()

-- battle uniforms: your employer's colours vs the enemy faction's (bandits in brown)
local function applyUniforms(teamFactions: any?)
	local view = ClientState.campaign
	local blue = (teamFactions and teamFactions.Blue) or (view and view.faction)
	local red = teamFactions and teamFactions.Red
	SoldierModels.setTeamUniform(
		"Blue",
		blue and CampaignConfig.Factions[blue] and CampaignConfig.Factions[blue].uniform
	)
	SoldierModels.setTeamUniform("Red", red and CampaignConfig.Factions[red] and CampaignConfig.Factions[red].uniform)
end

local function onPhase(info: any)
	applyUniforms(info.teamFactions)
	showPhase(info.phase)
	hud.onPhase(info)
	recruit.onPhase(info)
	summary.onPhase(info)
end

ClientState.Changed:Connect(function(key, a, b)
	if key == "Phase" then
		onPhase(a)
	elseif key == "Squads" then
		hud.onSquads()
		markers.onSquads()
	elseif key == "Zones" then
		markers.onZones()
		recruit.onZones()
	elseif key == "Recruit" then
		recruit.onRecruit()
		campaign.onRecruit()
		hud.refreshArmyCount()
	elseif key == "Campaign" then
		if not (ClientState.phase and ClientState.phase.teamFactions) then
			applyUniforms(nil)
		end
		campaign.onCampaign()
		showPhase(nil)
		if ClientState.view() ~= "Overworld" then
			campaign.hideEncounter()
		end
	elseif key == "CampaignTick" then
		campaign.onTick()
	elseif key == "Encounter" then
		campaign.onEncounter(a)
	elseif key == "Progress" then
		hud.onProgress(ClientState.progress)
	elseif key == "Summary" then
		summary.onSummary()
	elseif key == "Notify" then
		if ClientState.view() == "Overworld" then
			campaign.notify(a, b)
		else
			hud.notify(a, b)
		end
	elseif key == "Kill" then
		hud.onKill(a)
	end
end)

ClientActions.Changed:Connect(function(what)
	if what == "Controlled" then
		hud.onSquads()
		markers.onSquads()
	end
end)

-- State that may have arrived before this script ran
if ClientState.phase then
	onPhase(ClientState.phase)
end
if ClientState.progress then
	hud.onProgress(ClientState.progress)
end
if ClientState.summary then
	summary.onSummary()
end
recruit.onRecruit()

RunService.RenderStepped:Connect(function()
	hud.render()
	markers.render()
	recruit.render()
end)

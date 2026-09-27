--[[
	UIController
	Builds every screen inside PlayerGui.MainHUD (one ScreenGui) and routes server state
	(via ClientState) to them. No game state lives in the UI.

	Phase router — exactly one screen is visible at a time (Visible = false on the others,
	never just transparency):
	  Waiting → WaitingScreen · Recruitment → RecruitScreen · Battle → BattleHUD
	  Reward → SummaryScreen
	The battle HUD re-flows on every viewport change (Hud.layout), panels fit the screen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = script.Parent:WaitForChild("UI")
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

-- Our own HUD replaces Roblox's health bar / backpack / player list (Tab switches squads)
for _, coreType in { Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.PlayerList } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreType, false)
	end)
end

local hud = Hud.build(screen, ClientState, ClientActions)
local markers = Markers.build(screen, ClientState, ClientActions, hud.regions)
local recruit = RecruitPanel.build(screen, ClientState)
local summary = SummaryPanel.build(screen, ClientState)
local effects = Effects.build(screen)
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
}
local currentPhase = nil

local function showPhase(phase: string)
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
	for _, panel in { recruit.panel, summary.panel } do
		local fit = panel:FindFirstChild("FitScale") :: UIScale?
		if fit then
			fit.Scale = math.min(1, (viewport.X - 24) / panel.Size.X.Offset, (viewport.Y - 24) / panel.Size.Y.Offset)
		end
	end
end
Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
layout()

local function onPhase(info: any)
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
		hud.refreshArmyCount()
	elseif key == "Progress" then
		hud.onProgress(ClientState.progress)
	elseif key == "Summary" then
		summary.onSummary()
	elseif key == "Notify" then
		hud.notify(a, b)
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

--[[
	UIController
	Builds every HUD frame inside PlayerGui.MainHUD (one ScreenGui) and routes server state
	updates (via ClientState) to them. No game state lives in the UI: it only displays.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientActions = require(script.Parent:WaitForChild("ClientActions"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = script.Parent:WaitForChild("UI")
local Hud = require(UI:WaitForChild("Hud"))
local Markers = require(UI:WaitForChild("Markers"))
local RecruitPanel = require(UI:WaitForChild("RecruitPanel"))
local SummaryPanel = require(UI:WaitForChild("SummaryPanel"))

local root = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MainHUD")

local hud = Hud.build(root, ClientState, ClientActions)
local markers = Markers.build(root, ClientState, ClientActions)
local recruit = RecruitPanel.build(root, ClientState)
local summary = SummaryPanel.build(root, ClientState)

local function onPhase(info: any)
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
	if what == "Selection" then
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
recruit.onRecruit()

RunService.RenderStepped:Connect(function()
	hud.render()
	markers.render()
	recruit.render()
end)

-- SummaryScreen — full-screen, shown ONLY during the Reward phase: casualties, zones held,
-- time, XP, then the campaign report (loot, gold lost, contract outcome, squads lost / evolved)
-- and a button back to the overworld map.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Remotes"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors
local create, text = Theme.create, Theme.text

local continueRemote = Remotes.get("ContinueRound")

local SummaryPanel = {}

function SummaryPanel.build(root: ScreenGui, ClientState: any): any
	local api = {}

	local frame = create("Frame", {
		Name = "SummaryScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 8, 14),
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	api.frame = frame
	local panel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 600),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		ZIndex = 20,
		Parent = frame,
	})
	api.panel = panel
	create("UIScale", { Name = "FitScale", Parent = panel })
	Theme.corner(panel, 12)
	Theme.border(panel, Color3.new(0, 0, 0), 3)

	local title = text({
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 80),
		Font = Theme.Display,
		TextSize = 76,
		ZIndex = 21,
		Parent = panel,
	})
	Theme.stroke(title, Color3.new(0, 0, 0), 4)
	local subtitle = text({
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = C.Muted,
		ZIndex = 21,
		Parent = panel,
	})
	local lines = text({
		Position = UDim2.fromOffset(60, 136),
		Size = UDim2.new(1, -120, 0, 360),
		Font = Theme.Semi,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.25,
		RichText = true,
		ZIndex = 21,
		Parent = panel,
	})
	local button = create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(380, 62),
		BackgroundColor3 = C.Green,
		Font = Theme.Display,
		TextSize = 26,
		TextColor3 = C.Text,
		ZIndex = 21,
		Parent = panel,
	})
	Theme.corner(button, 10)
	Theme.border(button, Color3.new(0, 0, 0), 3)

	local voted = false
	button.Activated:Connect(function()
		if not voted then
			voted = true
			continueRemote:FireServer()
			button.Text = "Waiting for other players…"
			button.BackgroundColor3 = Color3.fromRGB(80, 80, 85)
		end
	end)

	function api.onSummary()
		local s = ClientState.summary
		if not s then
			return
		end
		voted = false
		title.Text = if s.victory then "VICTORY" else "DEFEAT"
		title.TextColor3 = if s.victory then C.Gold else C.Red
		subtitle.Text = string.format(
			"%s · %s",
			s.title or ("Round " .. tostring(s.round)),
			if s.side == "Attacker" then "Attack" else "Defence"
		)
		local rows = {
			string.format("Enemy soldiers killed: <b>%d</b>", s.killsDealt),
			string.format("Soldiers lost: <b>%d</b>", s.killsTaken),
			string.format("Zones held: <b>%d / %d</b>", s.zonesHeld, s.zonesTotal),
			string.format("Time: <b>%s</b>", Theme.formatTime(s.timeTaken)),
			string.format('XP earned: <font color="#FFCD28"><b>+%d</b></font>', s.xpEarned),
		}
		if s.campaign and #s.campaign > 0 then
			table.insert(rows, "")
			for _, line in s.campaign do
				table.insert(rows, line)
			end
		end
		lines.Text = table.concat(rows, "\n")
		button.Text = "RETURN TO THE MAP"
		button.BackgroundColor3 = C.Green
	end

	function api.onPhase(_info: any) end

	return api
end

return SummaryPanel

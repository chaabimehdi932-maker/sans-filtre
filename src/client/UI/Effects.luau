--[[
	Screen-space feedback (polish):
	  • red vignette pulse on the screen edges when the commander takes damage
	  • popIn(frame): smooth fade/scale-in when a panel appears instead of popping
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local create = Theme.create

local Effects = {}

function Effects.build(screen: ScreenGui): any
	local api = {}

	-- four edge strips with a transparency gradient towards the centre
	local vignette = create("Frame", {
		Name = "DamageVignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 200,
		Parent = screen,
	})
	local strips = {}
	local function strip(anchor: Vector2, position: UDim2, size: UDim2, rotation: number)
		local frame = create("Frame", {
			AnchorPoint = anchor,
			Position = position,
			Size = size,
			BackgroundColor3 = Color3.fromRGB(200, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 200,
			Parent = vignette,
		})
		create("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = frame,
		})
		table.insert(strips, frame)
	end
	strip(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0) -- left
	strip(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.18, 1), 180) -- right
	strip(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.2), 90) -- top
	strip(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.2), 270) -- bottom

	function api.damagePulse(strength: number)
		local start = math.clamp(0.75 - strength, 0.25, 0.75)
		for _, frame in strips do
			frame.BackgroundTransparency = start
			TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		end
	end

	local function watch(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		local last = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			if health < last - 0.5 then
				api.damagePulse((last - health) / math.max(1, humanoid.MaxHealth) * 4)
			end
			last = health
		end)
	end
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end

	-- fade + scale-in for panels
	function api.popIn(frame: GuiObject)
		local scale = frame:FindFirstChild("PopScale") :: UIScale?
		if not scale then
			local created = Instance.new("UIScale")
			created.Name = "PopScale"
			created.Parent = frame
			scale = created
		end
		local s = scale :: UIScale
		s.Scale = 0.92
		TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end

	return api
end

return Effects

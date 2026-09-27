--[[
	Icons (ReplicatedStorage.Modules.Icons)
	Images used by the HUD instead of emoji. Put a Roblox image id in a slot
	("rbxassetid://1234567890") and the game shows that image; leave "" to keep the emoji.

	How to get the ids (Roblox Studio):
	  View → Asset Manager → Images → "Bulk Import" → select the PNGs from your icon pack
	  → right-click an image → "Copy ID to Clipboard" → paste it below.
]]

local Icons = {
	-- army orders (left column)
	OrderHold = "", -- 🛡️
	OrderFollow = "", -- 🏃
	OrderAttack = "", -- ⚔️
	OrderRush = "", -- ⚡

	-- combat hotbar (bottom)
	Attack = "", -- ⚔️
	Block = "", -- 🛡️
	Roll = "", -- 💨
	Heal = "", -- 💚
	Mount = "", -- 🐎

	-- misc HUD
	Heart = "", -- ❤️ health bar
	Skull = "", -- 💀 kill combo
	Mouse = "", -- 🖱 key badges
	Lock = "", -- 🔒 locked units
}

function Icons.get(name: string): string
	local id = (Icons :: any)[name]
	return if typeof(id) == "string" then id else ""
end

return Icons

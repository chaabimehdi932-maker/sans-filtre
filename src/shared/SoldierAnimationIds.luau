--[[
	SoldierAnimationIds (ReplicatedStorage.Modules.SoldierAnimationIds)
	⚠ PLACEHOLDERS — swap in your own animation asset ids ("rbxassetid://123…").

	Soldiers are R6 rigs with the standard R6 joint names (Torso, Head, Right Shoulder, …), so
	any R6 animation you publish works on them. While an id is "" the built-in procedural pose
	of client/SoldierAnimationService is used instead (every state below already has one).

	Roblox's default R6 animations, if you want to try them:
	  idle  rbxassetid://180435571    walk  rbxassetid://180426354    sit  rbxassetid://178130996
	(R15 animation ids do NOT work on R6 rigs.)
]]

local SoldierAnimationIds = {}

SoldierAnimationIds.States = {
	"Idle",
	"Marching",
	"Running",
	"Aiming",
	"Firing",
	"Reloading",
	"MeleeSwing",
	"HitReact",
	"Death",
	-- artillery crew
	"Loading",
	"GunnerAim",
	"GunnerFire",
}

-- Per soldier type → per state → animation id ("" = procedural placeholder)
SoldierAnimationIds.Infantry = {
	Idle = "",
	Marching = "",
	Running = "",
	Aiming = "",
	Firing = "",
	Reloading = "",
	MeleeSwing = "",
	HitReact = "",
	Death = "",
}
SoldierAnimationIds.Crew = {
	Idle = "",
	Marching = "",
	Running = "",
	Loading = "",
	GunnerAim = "",
	GunnerFire = "",
	HitReact = "",
	Death = "",
}
SoldierAnimationIds.Cavalry = { -- rider only; the horse is always procedural
	Idle = "",
	Running = "",
	MeleeSwing = "",
	Death = "",
}

function SoldierAnimationIds.get(kind: string, state: string): string
	local set = (SoldierAnimationIds :: any)[kind]
	return if set and set[state] then set[state] else ""
end

return SoldierAnimationIds

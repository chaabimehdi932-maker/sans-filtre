--[[
	FormationDefinitions (ReplicatedStorage.Modules.FormationDefinitions)
	Formation modifiers + the soldier layout used to draw each formation.

	⚠ Multipliers are PLACEHOLDERS. ">1" on a "...TakenMult" means the squad takes MORE damage.

	  speedMult          movement speed multiplier
	  firepowerMult      multiplies the squad's volley damage
	  rangedTakenMult    damage taken from musket volleys
	  artilleryTakenMult damage taken from cannon fire
	  chargeTakenMult    damage taken from a cavalry charge hit
	  chargeMoraleMult   morale shock taken from a charge hit
	  flankTakenMult     damage taken when hit from the side
	  rearTakenMult      damage taken when hit from behind
]]

local FormationDefinitions = {}

-- Seconds a squad spends "forming up" when changing formation (can't move or fire, takes extra damage)
FormationDefinitions.FORM_UP_TIME = 3 -- PLACEHOLDER
FormationDefinitions.FORMING_DAMAGE_TAKEN_MULT = 1.3 -- PLACEHOLDER

-- Base distance between soldiers (studs). Soldiers are full-size R6 rigs (2 studs wide).
FormationDefinitions.SPACING_X = 3.2
FormationDefinitions.SPACING_Z = 3.8

FormationDefinitions.Order = { "Line", "Column", "Square" }

FormationDefinitions.Formations = {
	Line = {
		displayName = "Line",
		speedMult = 1,
		firepowerMult = 1,
		rangedTakenMult = 1,
		artilleryTakenMult = 1,
		chargeTakenMult = 1.2,
		chargeMoraleMult = 1,
		flankTakenMult = 1.5, -- wide front, fragile flanks
		rearTakenMult = 2,
	},
	Column = {
		displayName = "Column",
		speedMult = 1.4,
		firepowerMult = 0.5,
		rangedTakenMult = 1.3,
		artilleryTakenMult = 1.5,
		chargeTakenMult = 1.3,
		chargeMoraleMult = 1.2,
		flankTakenMult = 1.25,
		rearTakenMult = 1.5,
	},
	Square = {
		displayName = "Square",
		speedMult = 0.5,
		firepowerMult = 0.7,
		rangedTakenMult = 1.1,
		artilleryTakenMult = 1.6, -- packed target for cannons
		chargeTakenMult = 0.3, -- cavalry breaks on the bayonets
		chargeMoraleMult = 0.2,
		flankTakenMult = 1, -- no flank in a square
		rearTakenMult = 1,
	},
}

--[[
	Returns soldier offsets relative to the squad centre, in squad space
	(X = right, Z = back; the squad faces -Z like every Roblox CFrame).
]]
function FormationDefinitions.layout(formation: string, count: number, spacingMult: number?): { Vector3 }
	local sx = FormationDefinitions.SPACING_X * (spacingMult or 1)
	local sz = FormationDefinitions.SPACING_Z * (spacingMult or 1)
	local slots = {}
	if count <= 0 then
		return slots
	end

	local function grid(perRow: number)
		local rows = math.ceil(count / perRow)
		for i = 0, count - 1 do
			local row = i // perRow
			local col = i % perRow
			local inRow = if row == rows - 1 then count - row * perRow else perRow
			local x = (col - (inRow - 1) / 2) * sx
			local z = (row - (rows - 1) / 2) * sz
			table.insert(slots, Vector3.new(x, 0, z))
		end
	end

	if formation == "Column" then
		grid(math.min(3, count))
	elseif formation == "Square" and count >= 4 then
		-- Hollow square: walk around the perimeter and spread soldiers evenly on it
		local perSide = math.ceil(count / 4)
		local half = perSide * sx / 2
		local perimeter = {}
		for side = 0, 3 do
			for k = 0, perSide - 1 do
				local t = -half + k * sx
				if side == 0 then
					table.insert(perimeter, Vector3.new(t, 0, -half))
				elseif side == 1 then
					table.insert(perimeter, Vector3.new(half, 0, t))
				elseif side == 2 then
					table.insert(perimeter, Vector3.new(-t, 0, half))
				else
					table.insert(perimeter, Vector3.new(-half, 0, -t))
				end
			end
		end
		local total = #perimeter
		for i = 1, count do
			table.insert(slots, perimeter[math.floor((i - 1) * total / count) + 1])
		end
	else
		-- Line: two ranks when there are enough soldiers
		local ranks = if count >= 6 then 2 else 1
		grid(math.ceil(count / ranks))
	end
	return slots
end

--[[
	Side-by-side placement of several squads for a Hold order. Shared by the client preview
	(markers on the ground) and the server, so squads go exactly where the preview showed.
	entries (sorted by squad id): { { soldiers, spacingMult, formations } }
	Returns one { center, formation } per entry (a unit that can't use `formation` keeps its default).
]]
function FormationDefinitions.placeSquads(
	entries: { any },
	anchor: Vector3,
	yaw: number,
	formation: string,
	gap: number?
): { any }
	local spacing = gap or 5
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local widths, formations = {}, {}
	local total = 0
	for i, entry in entries do
		local chosen = if table.find(entry.formations, formation) then formation else entry.formations[1]
		local slots = FormationDefinitions.layout(chosen, entry.soldiers, entry.spacingMult)
		local minX, maxX = 0, 0
		for _, slot in slots do
			minX = math.min(minX, slot.X)
			maxX = math.max(maxX, slot.X)
		end
		widths[i] = maxX - minX + FormationDefinitions.SPACING_X * (entry.spacingMult or 1)
		formations[i] = chosen
		total += widths[i]
	end
	total += spacing * math.max(0, #entries - 1)
	local out = {}
	local cursor = -total / 2
	for i in entries do
		out[i] = { center = anchor + right * (cursor + widths[i] / 2), formation = formations[i] }
		cursor += widths[i] + spacing
	end
	return out
end

return FormationDefinitions

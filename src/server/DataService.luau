--[[
	DataService
	DataStoreService wrapper for meta-progression that survives between sessions:
	commander level/XP, best round reached, total rounds (battles) won, unlocked units,
	and the mercenary campaign (profile.Campaign): employer faction, gold, reputation,
	day, castle owners and the squad roster with each squad's XP (= evolution tier).
	To test saving in Studio: Game Settings > Security > "Enable Studio Access to API Services".
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local UnitDefinitions = require(Modules:WaitForChild("UnitDefinitions"))
local CampaignConfig = require(Modules:WaitForChild("CampaignConfig"))

local progressRemote = Remotes.get("PlayerProgress")

local DataService = {}

DataService.hooks = {
	onLevelUp = function(_player: Player, _level: number) end,
}

-- GetDataStore throws in a place that was never published: the game must still run (no saving)
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn("DataService: saving disabled (publish the place and enable API access to save):", result)
	end
end
local profiles: { [Player]: any } = {}
-- If loading failed we never save, so a DataStore outage can't wipe someone's progress
local loadFailed: { [Player]: boolean } = {}

local function key(player: Player): string
	return "player_" .. player.UserId
end

-- Campaign schema (added in v0.8; older saves get it filled in on load)
--   Roster = { { id, unitId, xp, soldiers } }  soldiers = current headcount
local function defaultCampaign(): any
	return {
		Faction = nil, -- employer, chosen at character creation
		Gold = CampaignConfig.Economy.StartingGold,
		Reputation = {}, -- [factionId] = number
		Day = 0,
		CastleOwners = {}, -- [locationId] = factionId (only castles that changed hands)
		Roster = {},
		NextSquadId = 1,
		BattlesWon = 0,
		ContractsCompleted = 0,
	}
end

local function defaultProfile(): any
	return { Level = 1, XP = 0, BestRound = 0, RoundsWon = 0, Unlocked = {}, Campaign = defaultCampaign() }
end

function DataService.load(player: Player)
	local data, ok = nil, false
	local dataStore = store
	if dataStore then
		for attempt = 1, 3 do
			ok, data = pcall(function()
				return dataStore:GetAsync(key(player))
			end)
			if ok then
				break
			end
			warn("DataService: load attempt", attempt, "failed for", player.Name, data)
			task.wait(0.5 * attempt)
		end
	end
	local profile = defaultProfile()
	if ok and typeof(data) == "table" then
		for field, value in data do
			profile[field] = value
		end
	end
	-- fill campaign fields missing from older saves
	if typeof(profile.Campaign) ~= "table" then
		profile.Campaign = defaultCampaign()
	else
		for field, value in defaultCampaign() do
			if profile.Campaign[field] == nil then
				profile.Campaign[field] = value
			end
		end
	end
	if not ok then
		loadFailed[player] = true
	end
	if player.Parent then
		profiles[player] = profile
	end
end

function DataService.save(player: Player)
	local profile = profiles[player]
	local dataStore = store
	if not profile or loadFailed[player] or not dataStore then
		return
	end
	local ok, err = pcall(function()
		dataStore:SetAsync(key(player), profile)
	end)
	if not ok then
		warn("DataService: save failed for", player.Name, err)
	end
end

function DataService.release(player: Player)
	DataService.save(player)
	profiles[player] = nil
	loadFailed[player] = nil
end

-- The player's campaign table (mutable: changes are saved with the profile). nil until loaded.
function DataService.getCampaign(player: Player): any
	local profile = profiles[player]
	return if profile then profile.Campaign else nil
end

-- Wipe the campaign (new character)
function DataService.resetCampaign(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Campaign = defaultCampaign()
	end
end

function DataService.getLevel(player: Player): number
	local profile = profiles[player]
	return if profile then profile.Level else 1
end

function DataService.sendProgress(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	progressRemote:FireClient(player, {
		level = profile.Level,
		xp = math.floor(profile.XP),
		xpNext = GameConfig.xpForLevel(profile.Level),
		bestRound = profile.BestRound,
		roundsWon = profile.RoundsWon,
	})
end

function DataService.addXP(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.XP += amount
	local leveled = false
	while profile.XP >= GameConfig.xpForLevel(profile.Level) do
		profile.XP -= GameConfig.xpForLevel(profile.Level)
		profile.Level += 1
		leveled = true
	end
	DataService.sendProgress(player)
	if leveled then
		DataService.hooks.onLevelUp(player, profile.Level)
	end
end

function DataService.recordRoundReached(player: Player, round: number)
	local profile = profiles[player]
	if profile and round > profile.BestRound then
		profile.BestRound = round
		DataService.sendProgress(player)
	end
end

-- Returns the display names of units unlocked by this win
function DataService.recordRoundWon(player: Player): { string }
	local profile = profiles[player]
	local unlocked = {}
	if not profile then
		return unlocked
	end
	profile.RoundsWon += 1
	for _, unitId in UnitDefinitions.Order do
		local def = UnitDefinitions.get(unitId)
		if def.unlockRoundsWon and not profile.Unlocked[unitId] and profile.RoundsWon >= def.unlockRoundsWon then
			profile.Unlocked[unitId] = true
			table.insert(unlocked, def.displayName)
		end
	end
	DataService.sendProgress(player)
	return unlocked
end

function DataService.isUnlocked(player: Player, unitId: string): boolean
	local def = UnitDefinitions.get(unitId)
	if not def then
		return false
	end
	if not def.unlockRoundsWon then
		return true
	end
	local profile = profiles[player]
	return profile ~= nil and profile.Unlocked[unitId] == true
end

function DataService.startAutosave()
	task.spawn(function()
		while true do
			task.wait(GameConfig.Data.AutosaveInterval)
			for player in profiles do
				DataService.save(player)
			end
		end
	end)
end

return DataService

--!nonstrict
-- PlayerData: the versioned save format, migration from older versions, and repair of bad values. Pure.
-- Version 2 fields (v1 had no Spirit/Special1/Special2; migrating fills them from the starter loadout):
--   Version, XP, Shards, Owned {itemId = true}, Equipped {Layer, Disc, Driver, Spirit, Special1, Special2},
--   Record {Wins, Losses, Draws},
--   RecentBattles {battleId...} (refuses duplicate rewards), Settings {CameraShake, ReducedEffects, TutorialDone}
-- A save written by a NEWER version is never migrated or overwritten (migrate returns nil, "newer").

local PlayerData = {}
PlayerData.VERSION = 2

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function count(n)
	return finite(n) and n >= 0 and math.floor(n) or 0
end

-- What kind of item an equipped slot holds (Special1 and Special2 both hold specials).
local function slotKind(slot)
	if slot == "Special1" or slot == "Special2" then
		return "Special"
	end
	return slot
end
PlayerData.slotKind = slotKind

-- starter: the starting loadout { Layer, Disc, Driver, Spirit, Special1, Special2 } (item ids)
function PlayerData.new(starter)
	local owned = {}
	for _, id in pairs(starter) do
		owned[id] = true
	end
	return {
		Version = PlayerData.VERSION,
		XP = 0,
		Shards = 0,
		Owned = owned,
		Equipped = table.clone(starter),
		Record = { Wins = 0, Losses = 0, Draws = 0 },
		RecentBattles = {},
		Settings = { CameraShake = true, ReducedEffects = false, TutorialDone = false },
	}
end

-- Repair a table in place: unknown items dropped, starter items always owned, equipped items owned and of the
-- right kind (else the starter item), the two specials different, counters non-negative integers, settings booleans.
local function repair(d, starter, parts, recentMax)
	d.XP = count(d.XP)
	d.Shards = count(d.Shards)
	local owned = {}
	if type(d.Owned) == "table" then
		for id, v in pairs(d.Owned) do
			if v == true and parts[id] then
				owned[id] = true
			end
		end
	end
	for _, id in pairs(starter) do
		owned[id] = true
	end
	d.Owned = owned
	local eq = type(d.Equipped) == "table" and d.Equipped or {}
	local fixed = {}
	for slot, starterId in pairs(starter) do
		local id = eq[slot]
		if type(id) == "string" and owned[id] and parts[id] and parts[id].Slot == slotKind(slot) then
			fixed[slot] = id
		else
			fixed[slot] = starterId
		end
	end
	if fixed.Special1 and fixed.Special1 == fixed.Special2 then
		fixed.Special2 = fixed.Special1 == starter.Special2 and starter.Special1 or starter.Special2
	end
	d.Equipped = fixed
	local rec = type(d.Record) == "table" and d.Record or {}
	d.Record = { Wins = count(rec.Wins), Losses = count(rec.Losses), Draws = count(rec.Draws) }
	local recent = {}
	if type(d.RecentBattles) == "table" then
		for _, id in ipairs(d.RecentBattles) do
			if type(id) == "string" then
				table.insert(recent, id)
			end
		end
	end
	while #recent > recentMax do
		table.remove(recent, 1)
	end
	d.RecentBattles = recent
	local s = type(d.Settings) == "table" and d.Settings or {}
	d.Settings = {
		CameraShake = s.CameraShake ~= false,
		ReducedEffects = s.ReducedEffects == true,
		TutorialDone = s.TutorialDone == true,
	}
	d.Version = PlayerData.VERSION
	return d
end

-- raw: whatever was stored (nil for a new player). Returns data, or nil + reason ("corrupt" | "newer").
function PlayerData.migrate(raw, starter, parts, recentMax)
	recentMax = recentMax or 30
	if raw == nil then
		return PlayerData.new(starter)
	end
	if type(raw) ~= "table" then
		return nil, "corrupt"
	end
	local version = raw.Version
	if version == nil then
		version = 0
	end
	if not finite(version) then
		return nil, "corrupt"
	end
	if version > PlayerData.VERSION then
		return nil, "newer"
	end
	local d = raw
	if version < 1 then
		-- v0 (development saves before versioning): { xp, shards, parts = {id...}, equipped = {...} }
		local owned = {}
		if type(raw.parts) == "table" then
			for _, id in ipairs(raw.parts) do
				owned[id] = true
			end
		end
		d = {
			XP = raw.xp,
			Shards = raw.shards,
			Owned = owned,
			Equipped = raw.equipped,
		}
	end
	return repair(d, starter, parts, recentMax)
end

-- What the client is allowed to see (no battle ids).
function PlayerData.snapshot(d, level, saveStatus)
	local owned = {}
	for id in pairs(d.Owned) do
		table.insert(owned, id)
	end
	table.sort(owned)
	return {
		XP = d.XP,
		Level = level,
		Shards = d.Shards,
		Owned = owned,
		Equipped = table.clone(d.Equipped),
		Record = { Wins = d.Record.Wins, Losses = d.Record.Losses, Draws = d.Record.Draws },
		Settings = { CameraShake = d.Settings.CameraShake, ReducedEffects = d.Settings.ReducedEffects, TutorialDone = d.Settings.TutorialDone },
		SaveStatus = saveStatus,
	}
end

return PlayerData

--!nonstrict
-- DataService: loads, holds and saves each player's data using SessionStore (session locks, retries, never
-- overwriting a real save after a failed load) over Roblox DataStores.
--
-- Save status per player (shown to them):
--   "saving"   loaded normally; autosaves and saves on leave
--   "nosave"   could not load (DataStore error, or Studio without API access): plays with a temporary profile that is
--              NEVER written, so the real save stays safe. Shown as a banner.
--   "locked"   another server still holds this player's session: temporary profile, not saved
--   "newer"    the save came from a newer game version: temporary profile, not saved
-- Live DataStore behaviour is unverified here; the rules are tested against a mock (tools/tests/progression.test.luau).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local PlayerData = require(Shared.Core.PlayerData)
local Progression = require(Shared.Core.Progression)
local SessionStore = require(Shared.Core.SessionStore)

local DataService = {}

local G = GameConfig.Data
local P = GameConfig.Progression
local profiles = {} -- player -> { data, status, dirty }
local remotes
local onReady = {} -- callbacks(player)
-- Studio has no JobId. Use one fixed id there, so a lock left behind by a stopped test session is picked straight
-- back up by the next one instead of locking you out of saving for LockTimeout.
local jobId = (game.JobId ~= "" and game.JobId) or "studio"

-- Adapter: SessionStore's store:update contract over a DataStore.
local function makeAdapter(ds)
	return {
		update = function(_, key, transform)
			local cancelled = false
			local ok, result = pcall(function()
				return ds:UpdateAsync(key, function(old)
					local new = transform(old)
					cancelled = new == nil
					return new
				end)
			end)
			if not ok then
				return false, result
			end
			if cancelled then
				return true, nil
			end
			return true, result
		end,
	}
end

local store
local storeError

local function keyFor(player)
	return "u_" .. player.UserId
end

local function migrate(raw)
	return PlayerData.migrate(raw, BeyConfig.StarterLoadout, BeyConfig.Items, P.RecentBattleMemory)
end

local function sessionOpts()
	return {
		attempts = G.LoadAttempts,
		retryWait = G.RetryWait,
		wait = function(s)
			task.wait(s)
		end,
		now = function()
			return os.time()
		end,
		lockTimeout = G.LockTimeout,
		migrate = migrate,
	}
end

function DataService.levelOf(player)
	local p = profiles[player]
	return p and Progression.levelFromXP(p.data.XP, P) or 1
end

function DataService.get(player)
	local p = profiles[player]
	return p and p.data or nil
end

function DataService.status(player)
	local p = profiles[player]
	return p and p.status or "loading"
end

function DataService.isReady(player)
	return profiles[player] ~= nil
end

-- What the client sees: PlayerData.snapshot plus XP needed for this and the next level (for the XP bar).
function DataService.snapshot(player)
	local p = profiles[player]
	if not p then
		return nil
	end
	local level = DataService.levelOf(player)
	local snap = PlayerData.snapshot(p.data, level, p.status)
	snap.XPThis = Progression.xpForLevel(level, P)
	snap.XPNext = level < P.MaxLevel and Progression.xpForLevel(level + 1, P) or snap.XPThis
	return snap
end

function DataService.sendProfile(player)
	if remotes and player.Parent and profiles[player] then
		remotes.Profile:FireClient(player, DataService.snapshot(player))
	end
end

function DataService.markDirty(player)
	local p = profiles[player]
	if p then
		p.dirty = true
	end
end

local function save(player, release)
	local p = profiles[player]
	if not p or p.status ~= "saving" or not store then
		return "skipped"
	end
	local result, detail = SessionStore.save(store, keyFor(player), jobId, p.data, sessionOpts(), release)
	if result == "ok" then
		p.dirty = false
	elseif result == "lost_lock" then
		-- Another server took over this player's data: stop writing from here so we can't clobber it.
		p.status = "locked"
		warn(("Spinforge: %s's session moved to another server; this server stopped saving it."):format(player.Name))
		DataService.sendProfile(player)
	else
		warn(("Spinforge: saving %s failed (%s). Will retry at the next autosave."):format(player.Name, tostring(detail)))
	end
	return result
end
DataService.save = save

function DataService.onReady(callback)
	table.insert(onReady, callback)
end

local function load(player)
	local status, data, detail = "nosave", nil, storeError
	if store then
		local result
		result, data, detail = SessionStore.load(store, keyFor(player), jobId, sessionOpts())
		if result == "ok" then
			status = "saving"
		elseif result == "unsupported" then
			status = "newer"
		elseif result == "locked" then
			status = "locked"
		else
			status = "nosave"
		end
	end
	if not player.Parent then
		-- Left while loading: release the lock we may have just taken.
		if status == "saving" and data then
			profiles[player] = { data = data, status = status, dirty = false }
			save(player, true)
			profiles[player] = nil
		end
		return
	end
	if status ~= "saving" then
		warn(("Spinforge: %s plays with a temporary profile (%s: %s). It will NOT be saved."):format(player.Name, status, tostring(detail)))
		data = PlayerData.new(BeyConfig.StarterLoadout)
	end
	profiles[player] = { data = data, status = status, dirty = false }
	player:SetAttribute("DataReady", true)
	DataService.sendProfile(player)
	for _, cb in ipairs(onReady) do
		task.spawn(cb, player)
	end
end

function DataService.start(r)
	remotes = r
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(G.StoreName)
	end)
	if ok then
		store = makeAdapter(result)
	else
		storeError = tostring(result)
		warn("Spinforge: DataStores unavailable (" .. storeError .. "). Progress will not save this session." .. (RunService:IsStudio() and " In Studio: Game Settings > Security > Enable Studio Access to API Services." or ""))
	end

	Players.PlayerAdded:Connect(function(player)
		load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			save(player, true)
			profiles[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(G.AutosaveInterval)
			for player, p in pairs(profiles) do
				if p.dirty and p.status == "saving" then
					task.spawn(save, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return DataService

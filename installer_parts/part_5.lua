-- Spinforge installer. Paste into Studio's Command Bar (View > Command Bar, or the code pane with a Run button)
-- and run it while NOT in Play mode. Safe to run again: it only replaces the Spinforge folders.
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local roots = { RS = RS, SSS = SSS, SPS = SPS }
local function folderAt(rootKey, path)
	local node = roots[rootKey]:FindFirstChild("Spinforge")
	if not node then
		node = Instance.new("Folder")
		node.Name = "Spinforge"
		node.Parent = roots[rootKey]
	end
	for name in string.gmatch(path, "[^/]+") do
		local nextNode = node:FindFirstChild(name)
		if not nextNode then
			nextNode = Instance.new("Folder")
			nextNode.Name = name
			nextNode.Parent = node
		end
		node = nextNode
	end
	return node
end
local function install(rootKey, path, class, name, source)
	local parent = folderAt(rootKey, path)
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local s = Instance.new(class)
	s.Name = name
	s.Source = source
	s.Parent = parent
end
install('SSS', '', 'ModuleScript', 'DataService', [=====[
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
]=====])
install('SSS', '', 'Script', 'Main', [=====[
--!nonstrict
-- Spinforge server entry point. Starts everything in a fixed order and prints a startup report to Output.
-- If something required is missing, it stops with a message saying what to do instead of failing silently.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local REQUIRED_SHARED = { "BeyConfig", "BeyDesigns", "BeyMeshData", "BeyVisuals", "GameConfig", "Net", "Core" }
local Shared = ReplicatedStorage:FindFirstChild("Spinforge")
if not Shared then
	error("Spinforge: ReplicatedStorage.Spinforge is missing. Run install_in_studio.lua again (Command Bar).")
end
local missing = {}
for _, name in ipairs(REQUIRED_SHARED) do
	if not Shared:FindFirstChild(name) then
		table.insert(missing, name)
	end
end
if #missing > 0 then
	error("Spinforge: missing shared modules: " .. table.concat(missing, ", ") .. ". Run install_in_studio.lua again.")
end

local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local Net = require(Shared.Net)
local Progression = require(Shared.Core.Progression)

local World = require(script.Parent.World)
local MeshImport = require(script.Parent.MeshImport)
local DataService = require(script.Parent.DataService)
local BeyService = require(script.Parent.BeyService)
local BattleService = require(script.Parent.BattleService)

Workspace.Gravity = BeyConfig.Movement.Gravity
local remotes = Net.setup(ReplicatedStorage)
World.removeLegacy()
local world = World.build(GameConfig.Villain.Name)
World.polishLighting()
local meshes, moved = MeshImport.collect()
local spiritMeshes, spiritsMoved = MeshImport.spirits()
local spiritCount = 0
for _ in pairs(BeyConfig.Spirits) do
	spiritCount += 1
end

DataService.start(remotes)
BeyService.start(remotes, DataService, BattleService.onSlam)
BeyService.onInterrupted = BattleService.onInterrupted
BattleService.start(remotes)

-- Hub prompts.
local function onFootAndReady(player)
	return BeyService.mode(player) == "OnFoot" and DataService.isReady(player)
end
if world.prompts.challenge then
	world.prompts.challenge.Triggered:Connect(function(player)
		if onFootAndReady(player) then
			BattleService.challenge(player)
		end
	end)
end
if world.prompts.practice then
	world.prompts.practice.Triggered:Connect(function(player)
		if onFootAndReady(player) then
			BeyService.startPractice(player)
		end
	end)
end
if world.prompts.workshop then
	world.prompts.workshop.Triggered:Connect(function(player)
		remotes.BattleEvent:FireClient(player, { kind = "openWorkshop" })
	end)
end

-- Workshop: buy and equip parts, spirits and specials, validated on the server. Only allowed on foot.
remotes.Workshop.OnServerInvoke = function(player, req)
	local data = DataService.get(player)
	local function reply(ok, reason)
		return {
			ok = ok,
			reason = reason and (Progression.ReasonText[reason] or reason) or nil,
			profile = DataService.snapshot(player),
		}
	end
	if not data then
		return reply(false, "Your profile is still loading.")
	end
	if type(req) ~= "table" or type(req.action) ~= "string" or type(req.part) ~= "string" then
		return reply(false, "invalid")
	end
	local mode = BeyService.mode(player)
	if mode == "Practice" then
		return reply(false, "Leave practice to change parts.")
	end
	local inBattle = mode ~= "OnFoot"
	local ok, reason
	if req.action == "buy" then
		ok, reason = Progression.buy(data, req.part, BeyConfig.Items, GameConfig.Progression, inBattle)
	elseif req.action == "equip" then
		local slot = (req.slot == "Special1" or req.slot == "Special2") and req.slot or nil
		ok, reason = Progression.equip(data, req.part, BeyConfig.Items, inBattle, slot)
	else
		return reply(false, "invalid")
	end
	if ok then
		DataService.markDirty(player)
		DataService.sendProfile(player)
		return reply(true, nil)
	end
	return reply(false, reason)
end

-- Other requests: settings, tutorial, leaving practice. (Battle requests are handled in BattleService.)
local SETTINGS = { CameraShake = true, ReducedEffects = true }
remotes.Request.OnServerEvent:Connect(function(player, req)
	if type(req) ~= "table" or type(req.action) ~= "string" then
		return
	end
	local data = DataService.get(player)
	if req.action == "setting" and data and SETTINGS[req.key] and type(req.value) == "boolean" then
		data.Settings[req.key] = req.value
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "tutorialDone" and data and not data.Settings.TutorialDone then
		data.Settings.TutorialDone = true
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "tutorialReset" and data then
		data.Settings.TutorialDone = false
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "exitPractice" and BeyService.mode(player) == "Practice" then
		BeyService.exit(player)
	end
end)

print(("Spinforge server ready: world %s, %d of %d bey meshes available%s, %d of %d spirit meshes, crates disabled (paid purchases off)."):format(
	world.built and "built" or "found (custom SpinforgeWorld)",
	meshes,
	66,
	(moved + spiritsMoved) > 0 and (" (moved " .. (moved + spiritsMoved) .. " imported model(s) from Workspace)") or "",
	spiritMeshes,
	spiritCount
))
]=====])
install('SSS', '', 'ModuleScript', 'MeshImport', [=====[
--!nonstrict
-- MeshImport: Studio's 3D importer drops imported models into Workspace. At server start, any bey meshes found
-- there (MeshParts named like "<partId>_P" / "<partId>_A") are moved into ReplicatedStorage.BeyMeshes, where
-- BeyVisuals looks for them. Spirit creature meshes (MeshParts named like "spirit_emberwolf") go to
-- ReplicatedStorage.SpiritMeshes, where the client's Spirits module looks for them.
-- collect() returns how many bey meshes are available afterwards (and how many were moved); spirits() the same
-- for the creatures.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyMeshData = require(Shared.BeyMeshData)
local BeyConfig = require(Shared.BeyConfig)

local MeshImport = {}

function MeshImport.collect()
	local folder = ReplicatedStorage:FindFirstChild("BeyMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BeyMeshes"
		folder.Parent = ReplicatedStorage
	end
	local tops = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("MeshPart") and BeyMeshData[d.Name] then
			local top = d
			while top.Parent and top.Parent ~= Workspace do
				top = top.Parent
			end
			tops[top] = true
		end
	end
	local moved = 0
	for top in pairs(tops) do
		top.Parent = folder
		moved += 1
	end
	local available = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("MeshPart") and BeyMeshData[d.Name] then
			available += 1
		end
	end
	return available, moved
end

function MeshImport.spirits()
	local folder = ReplicatedStorage:FindFirstChild("SpiritMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SpiritMeshes"
		folder.Parent = ReplicatedStorage
	end
	local tops = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("MeshPart") and BeyConfig.Spirits[d.Name] then
			local top = d
			while top.Parent and top.Parent ~= Workspace do
				top = top.Parent
			end
			tops[top] = true
		end
	end
	local moved = 0
	for top in pairs(tops) do
		top.Parent = folder
		moved += 1
	end
	local available = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("MeshPart") and BeyConfig.Spirits[d.Name] then
			available += 1
		end
	end
	return available, moved
end

return MeshImport
]=====])
install('SSS', '', 'ModuleScript', 'VillainAI', [=====[
--!nonstrict
-- VillainAI: drives the villain's bey on the server with the SAME MovementCore rules as the player's bey.
-- Behaviours (one at a time):
--   approach     chase where the player will be (short prediction), keep away from the rim when not attacking
--   windup       TELEGRAPH (red highlight + "!"): slows down, then
--   dash         leans fully in and charges the spot the player was at when the dash started
--   slamWindup   TELEGRAPH (orange highlight + "!!"): hops, then dives onto the player (an air slam)
--   recover      backs off at an angle for a moment after an attack or a hit
--   unstuck      if it barely moves for a while, it pushes back toward the centre
-- Specials (chooseSpecial, asked by BattleService each frame): a dash special fires as a dash attack starts, a quake
-- when the player is close, a guard when the player is empowered or awakened, a heal when low; it awakens as soon
-- as its meter is full. Never more than one special per SPECIAL_GAP seconds, so the player can read them.
-- Difficulty (GameConfig.Difficulty) sets speed, warning time, aggression and damage.
-- Unverified in Roblox: how this feels and whether it gets stuck on the stadium geometry. See HANDOFF checklist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local MC = require(Shared.Core.MovementCore)
local LaunchCore = require(Shared.Core.LaunchCore)

local M = BeyConfig.Movement
local VillainAI = {}
VillainAI.__index = VillainAI

local SPECIAL_GAP = 2.5 -- minimum seconds between the villain's specials
local RIM_SAFE = 31 -- beyond this radius (from the arena centre) it steers back in unless attacking

-- rec: BeyFactory record. diff: GameConfig.Difficulty entry. center: arena centre. ignore: instances the probe ignores.
function VillainAI.new(rec, diff, center, ignore)
	local self = setmetatable({}, VillainAI)
	self.rec = rec
	self.diff = diff
	self.center = center
	self.state = "approach"
	self.stateAt = 0
	self.nextAttackAt = 1.5
	self.ground = MC.newGround()
	self.actions = MC.newActions()
	self.stuck = MC.newStuck()
	self.slowSince = nil
	self.yaw = 0
	self.up = Vector3.yAxis
	self.dashTarget = nil
	self.speedMul = 1 -- spirit passive / awakening (set by BattleService)
	self.dashStartedAt = -math.huge
	self.lastSpecialAt = -math.huge
	self.rng = Random.new()
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.FilterDescendantsInstances = ignore

	local hl = Instance.new("Highlight")
	hl.Name = "Telegraph"
	hl.FillTransparency = 0.35
	hl.OutlineTransparency = 0
	hl.Enabled = false
	hl.Parent = rec.model
	self.highlight = hl
	local bb = Instance.new("BillboardGui")
	bb.Name = "TelegraphMark"
	bb.Size = UDim2.fromOffset(60, 60)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.Adornee = rec.body
	bb.Parent = rec.model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeTransparency = 0
	label.Text = "!"
	label.Parent = bb
	self.mark = bb
	self.markLabel = label
	return self
end

-- The villain's launch boost (from its launch quality): extra top speed that fades over GameConfig.Launch.BoostTime.
function VillainAI:launched(boost, now)
	self.launchBoost = boost
	self.launchAt = now
	self.nextAttackAt = now + 1.0
end

function VillainAI:setTelegraph(kind)
	if kind == nil then
		self.highlight.Enabled = false
		self.mark.Enabled = false
		return
	end
	local color = kind == "dash" and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 160, 40)
	self.highlight.FillColor = color
	self.highlight.OutlineColor = color
	self.highlight.Enabled = true
	self.markLabel.Text = kind == "dash" and "!" or "!!"
	self.markLabel.TextColor3 = color
	self.mark.Enabled = true
end

function VillainAI:go(state, now)
	self.state = state
	self.stateAt = now
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Called every Heartbeat while the battle is active. target: { pos, vel } of the player's bey.
-- onSlamImpact(fallSpeed) is called once when the villain's slam lands.
-- Returns nothing; writes the villain body's velocity and orientation.
function VillainAI:step(dt, now, target, spinFraction, onSlamImpact)
	local body = self.rec.body
	if not body.Parent or body.Anchored then
		return
	end
	dt = MC.safeDt(dt, M)
	local pos = body.Position
	local vel = MC.sanitizeVelocity(body.AssemblyLinearVelocity, M)
	local speed = MC.topSpeed(self.rec.stats, M) * self.diff.Speed * (self.speedMul or 1)
	if self.launchAt then
		speed *= LaunchCore.boostMultiplier(self.launchBoost, now - self.launchAt, GameConfig.Launch)
	end

	-- ground probe (same rules as the player: sphere probe, hysteresis)
	local normal
	if not MC.probeSuppressed(self.actions, now, M) then
		local hit = Workspace:Raycast(pos, Vector3.new(0, -(M.Radius + M.GroundProbe), 0), self.params)
		normal = hit and hit.Normal or nil
	end
	local event = MC.updateGround(self.ground, normal, now, M)
	if MC.resolveActions(self.actions, event, now, M) == "impact" then
		onSlamImpact(MC.finite(vel.Y) and math.max(-vel.Y, 0) or 0)
	end

	local toTarget = flat(target.pos - pos)
	local dist = toTarget.Magnitude
	self.lastDist = dist
	local fromCenter = flat(pos - self.center)
	local wish, tilt = Vector3.zero, 0
	local t = now - self.stateAt
	local s = self.state

	if s == "approach" then
		local predicted = flat(target.pos + target.vel * 0.35 - pos)
		wish = predicted.Magnitude > 0.1 and predicted.Unit or Vector3.zero
		tilt = dist > 18 and -0.4 or 0
		if fromCenter.Magnitude > RIM_SAFE then
			wish = (wish + (-fromCenter.Unit) * 1.2)
			wish = wish.Magnitude > 0.01 and wish.Unit or wish
		end
		if now >= self.nextAttackAt and dist < 20 and self.rng:NextNumber() < self.diff.Aggression then
			if dist < 11 and self.ground.grounded and self.rng:NextNumber() < 0.35 then
				self:go("slamWindup", now)
				self:setTelegraph("slam")
			else
				self:go("windup", now)
				self:setTelegraph("dash")
			end
		elseif now >= self.nextAttackAt then
			self.nextAttackAt = now + 0.6 -- re-roll soon
		end
	elseif s == "windup" then
		wish = dist > 0.1 and toTarget.Unit or Vector3.zero
		tilt = 0.7 -- visibly rears back and slows: the tell
		if t >= self.diff.Windup then
			self.dashTarget = target.pos
			self.dashStartedAt = now
			self:go("dash", now)
		end
	elseif s == "dash" then
		local d = flat(self.dashTarget - pos)
		wish = d.Magnitude > 0.1 and d.Unit or Vector3.zero
		tilt = -1
		if t >= 0.9 or d.Magnitude < 2 then
			self:setTelegraph(nil)
			self:go("recover", now)
		end
	elseif s == "slamWindup" then
		tilt = 0.5
		if t >= self.diff.Windup and MC.canJump(self.actions, self.ground, now, M) then
			vel = MC.jump(self.actions, self.ground, vel, 0.6, now, M)
			-- hop toward the player so the dive lands near them
			local push = dist > 0.1 and toTarget.Unit * math.min(dist * 2.2, 40) or Vector3.zero
			vel = Vector3.new(push.X, vel.Y * 1.15, push.Z)
			self:go("slamAir", now)
		elseif t >= self.diff.Windup + 1 then
			self:setTelegraph(nil)
			self:go("recover", now)
		end
	elseif s == "slamAir" then
		if MC.canSlam(self.actions, self.ground, now, M) and vel.Y < 5 then
			vel = MC.startSlam(self.actions, vel, now, M)
			self:go("slamDive", now)
		elseif t > 2 then
			self:setTelegraph(nil)
			self:go("recover", now)
		end
	elseif s == "slamDive" then
		if self.actions.slam ~= "diving" then
			self:setTelegraph(nil)
			self:go("recover", now)
		end
	elseif s == "recover" then
		local away = dist > 0.1 and -toTarget.Unit or Vector3.new(1, 0, 0)
		local side = Vector3.new(-away.Z, 0, away.X)
		wish = (away + side * 0.8).Unit
		if fromCenter.Magnitude > RIM_SAFE - 4 then
			wish = (-fromCenter).Unit
		end
		tilt = 0.2
		if t >= 1.0 then
			self.nextAttackAt = now + 0.8 + self.rng:NextNumber() * 1.2
			self:go("approach", now)
		end
	elseif s == "unstuck" then
		wish = fromCenter.Magnitude > 0.1 and (-fromCenter).Unit or Vector3.new(1, 0, 0)
		tilt = -0.6
		if t >= 1.2 then
			self:go("approach", now)
		end
	end

	-- movement (shared rules)
	if self.ground.grounded then
		vel = MC.groundVelocity(vel, self.ground.normal, wish, tilt, speed, dt, M)
	else
		if event == "tookoff" then
			vel = vel + Vector3.new(0, MC.takeoffBoost(self.actions, vel, tilt, M), 0)
		end
		vel = MC.airVelocity(vel, wish, tilt, speed, self.actions.slam == "diving", dt, M)
	end

	-- stuck: barely moving on the ground while trying to go somewhere
	if s ~= "windup" and s ~= "slamWindup" and wish.Magnitude > 0.5 and flat(vel).Magnitude < 2 then
		self.slowSince = self.slowSince or now
		if now - self.slowSince > 1.5 then
			self.slowSince = nil
			self:setTelegraph(nil)
			self:go("unstuck", now)
			vel = vel + Vector3.new(0, 25, 0) + (fromCenter.Magnitude > 0.1 and (-fromCenter).Unit * 20 or Vector3.zero)
		end
	else
		self.slowSince = nil
	end

	vel = MC.sanitizeVelocity(vel, M)
	body.AssemblyLinearVelocity = vel

	-- orientation: lean with the surface and its tilt; wobble when low on spin
	self.yaw = MC.noseYaw(self.yaw, vel, dt, M)
	self.up = MC.surfaceUp(self.up, self.ground.grounded and self.ground.normal or nil, dt, M)
	local r, u, b = MC.frame(self.up, self.yaw)
	local wobble = 0
	if spinFraction < GameConfig.Combat.LowSpinFraction then
		wobble = math.sin(now * 9) * 0.25 * (1 - spinFraction / GameConfig.Combat.LowSpinFraction)
	end
	self.rec.align.CFrame = CFrame.fromMatrix(Vector3.zero, r, u, b) * CFrame.Angles(tilt * math.rad(M.MaxTiltDeg) * 0.6, 0, wobble)
end

-- Which special to use now, if any: 1 or 2 (slot), "awaken", or nil.
-- info = { specials = its SpecialsCore side, foe = the player's side, canAwaken = bool, spin = its spin fraction }
function VillainAI:chooseSpecial(now, info)
	if now - self.lastSpecialAt < SPECIAL_GAP then
		return nil
	end
	local function pick(choice)
		self.lastSpecialAt = now
		return choice
	end
	if info.canAwaken then
		return pick("awaken")
	end
	local dist = self.lastDist or math.huge
	local foe = info.foe
	local threatened = (foe.empower ~= nil and now <= foe.empower.untilT) or now < foe.awakenedUntil
	for i, s in ipairs(info.specials.specials) do
		local def = s.def
		if def and now >= s.readyAt then
			local kind, t = def.Kind, def.Tuning
			if kind == "dash" and self.state == "dash" and now - self.dashStartedAt < 0.15 then
				return pick(i)
			elseif kind == "quake" and dist < t.Radius * 0.8 and self.rng:NextNumber() < self.diff.Aggression * 0.05 then
				return pick(i)
			elseif kind == "guard" and threatened and dist < 18 then
				return pick(i)
			elseif kind == "heal" and info.spin < 0.4 then
				return pick(i)
			end
		end
	end
	return nil
end

-- A hit lands on the villain: interrupt a windup sometimes and back off.
function VillainAI:onHit(now)
	if self.state == "approach" or self.state == "windup" then
		self:setTelegraph(nil)
		self:go("recover", now)
	end
end

-- Idle (countdown / finished): brake to a stop, no attacks.
function VillainAI:idle(dt)
	local body = self.rec.body
	if not body.Parent or body.Anchored then
		return
	end
	self:setTelegraph(nil)
	local v = body.AssemblyLinearVelocity
	if MC.finiteVector(v) then
		body.AssemblyLinearVelocity = Vector3.new(v.X * 0.9, v.Y, v.Z * 0.9)
	end
end

function VillainAI:destroy()
	self:setTelegraph(nil)
end

return VillainAI
]=====])
print('Spinforge installer part 5 of 9 done. Now run part 6.')

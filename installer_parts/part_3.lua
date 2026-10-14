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
install('RS', 'Core', 'ModuleScript', 'Progression', [=====[
--!nonstrict
-- Progression: XP, levels, Shards (earned currency), battle rewards, the Workshop and equipping, as pure functions
-- over a player-data table (see PlayerData). The server calls these; the client only ever sees the results.
-- P = GameConfig.Progression, parts = BeyConfig.Parts. Tested in tools/tests/progression.test.luau.
--
-- How free play reaches the cap: rarity budgets differ (Common 8 ... Legendary 30 per part), so leveling alone
-- can NOT turn a Common part into a Legendary one. The free route is the Workshop: every rarity up to Legendary is
-- sold for Shards, and Shards come only from battles. A full Legendary set at level 50 is the grindable cap.
-- Ultra Legendary (+10% over that cap) is never sold for Shards; it is the paid tier (crates are disabled for now).

local Progression = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function Progression.xpForLevel(level, P)
	if level <= 1 then
		return 0
	end
	return math.floor(P.XPCurveBase * (level - 1) ^ P.XPCurvePower + 0.5)
end

function Progression.levelFromXP(xp, P)
	if not finite(xp) or xp <= 0 then
		return 1
	end
	local level = 1
	while level < P.MaxLevel and xp >= Progression.xpForLevel(level + 1, P) do
		level += 1
	end
	return level
end

-- outcome: "win" | "loss" | "draw"; difficulty: a key of GameConfig.Difficulty.
function Progression.battleReward(outcome, difficulty, P, D)
	local base = P.Rewards[outcome]
	if not base then
		return nil
	end
	local mult = (D and D[difficulty] and D[difficulty].Reward) or 1
	return { Outcome = outcome, XP = math.floor(base.XP * mult + 0.5), Shards = math.floor(base.Shards * mult + 0.5) }
end

-- Grants a battle's reward once. battleId must be unique per battle; a repeated id is refused.
-- Returns ok, reason_or_info. info = { levelBefore, levelAfter }.
function Progression.grantBattleReward(data, battleId, reward, P)
	if type(battleId) ~= "string" or battleId == "" or type(reward) ~= "table" then
		return false, "invalid"
	end
	if not (finite(reward.XP) and finite(reward.Shards)) or reward.XP < 0 or reward.Shards < 0 then
		return false, "invalid"
	end
	for _, id in ipairs(data.RecentBattles) do
		if id == battleId then
			return false, "duplicate"
		end
	end
	table.insert(data.RecentBattles, battleId)
	while #data.RecentBattles > P.RecentBattleMemory do
		table.remove(data.RecentBattles, 1)
	end
	local before = Progression.levelFromXP(data.XP, P)
	data.XP += math.floor(reward.XP)
	data.Shards += math.floor(reward.Shards)
	local key = reward.Outcome == "win" and "Wins" or reward.Outcome == "loss" and "Losses" or "Draws"
	data.Record[key] = (data.Record[key] or 0) + 1
	return true, { levelBefore = before, levelAfter = Progression.levelFromXP(data.XP, P) }
end

-- Workshop price in Shards, or nil if the part can't be bought with Shards.
function Progression.price(partId, parts, P)
	local part = parts[partId]
	return part and P.Prices[part.Rarity] or nil
end

function Progression.buy(data, partId, parts, P, inBattle)
	if inBattle then
		return false, "in_battle"
	end
	local part = parts[partId]
	if not part then
		return false, "unknown_part"
	end
	if data.Owned[partId] then
		return false, "owned"
	end
	local cost = Progression.price(partId, parts, P)
	if not cost then
		return false, "not_for_sale"
	end
	if data.Shards < cost then
		return false, "cant_afford"
	end
	data.Shards -= cost
	data.Owned[partId] = true
	return true, cost
end

-- Equip an owned part into its own slot. Never during a battle.
function Progression.equip(data, partId, parts, inBattle)
	if inBattle then
		return false, "in_battle"
	end
	local part = parts[partId]
	if not part then
		return false, "unknown_part"
	end
	if not data.Owned[partId] then
		return false, "not_owned"
	end
	data.Equipped[part.Slot] = partId
	return true
end

-- Human-readable text for the reasons above (shown in the Workshop).
Progression.ReasonText = {
	in_battle = "You can't change parts during a battle.",
	unknown_part = "That part doesn't exist.",
	not_owned = "You don't own that part yet.",
	owned = "You already own that part.",
	not_for_sale = "That part isn't sold in the Workshop.",
	cant_afford = "Not enough Shards yet. Win battles to earn more.",
	invalid = "Something went wrong. Try again.",
	duplicate = "That reward was already given.",
}

return Progression
]=====])
install('RS', 'Core', 'ModuleScript', 'SessionStore', [=====[
--!nonstrict
-- SessionStore: loading and saving player data safely, independent of Roblox. The server passes a store adapter;
-- tests pass a mock. Stored value: { Data = <PlayerData v1>, Lock = { Job = serverId, Time = seconds } | nil }.
--
-- Adapter contract: store:update(key, transform) -> ok (bool), valueOrErr
--   transform(old) returns the new value, or nil to cancel (then ok = true, value = nil). It may run more than once.
--
-- Rules:
--   * A load takes a session lock. If another live server holds it, retry; after LockTimeout the lock is stale and
--     is taken over. If it is still held after all attempts, the result is "locked" and the session must not save.
--   * A failed load NEVER produces a fresh profile that later overwrites the real one: the caller marks the session
--     "nosave" and keeps the player's real data untouched.
--   * Saves only happen while we still hold the lock; if another server took it, the save is refused ("lost_lock").
--   * A save written by a newer game version is never overwritten ("unsupported").

local SessionStore = {}

-- opts: { attempts, wait = function(seconds), now = function() -> seconds, lockTimeout, migrate = function(raw) }
-- Returns status ("ok" | "locked" | "failed" | "unsupported"), data (when ok), detail.
function SessionStore.load(store, key, jobId, opts)
	local lastErr
	local wasLocked = false
	for attempt = 1, opts.attempts do
		local lockedBy, migrateErr = nil, nil
		local ok, value = store:update(key, function(old)
			lockedBy, migrateErr = nil, nil
			local now = opts.now()
			if type(old) == "table" and type(old.Lock) == "table" and old.Lock.Job ~= jobId then
				local t = old.Lock.Time
				if type(t) == "number" and now - t < opts.lockTimeout then
					lockedBy = old.Lock.Job
					return nil
				end
			end
			local raw = type(old) == "table" and old.Data or nil
			local data, err = opts.migrate(raw)
			if not data then
				migrateErr = err
				return nil
			end
			return { Data = data, Lock = { Job = jobId, Time = now } }
		end)
		if ok and value ~= nil then
			return "ok", value.Data
		end
		if ok and migrateErr then
			return "unsupported", nil, migrateErr -- never retried, never overwritten
		end
		if ok and lockedBy then
			wasLocked = true
			lastErr = "locked by " .. tostring(lockedBy)
		else
			lastErr = tostring(value)
		end
		if attempt < opts.attempts then
			opts.wait(opts.retryWait or 1)
		end
	end
	return wasLocked and "locked" or "failed", nil, lastErr
end

-- Returns "ok" | "lost_lock" | "error", detail.
function SessionStore.save(store, key, jobId, data, opts, release)
	local lost = false
	local ok, value = store:update(key, function(old)
		lost = false
		if type(old) == "table" and type(old.Lock) == "table" and old.Lock.Job ~= jobId then
			lost = true
			return nil
		end
		return { Data = data, Lock = (not release) and { Job = jobId, Time = opts.now() } or nil }
	end)
	if not ok then
		return "error", tostring(value)
	end
	if lost then
		return "lost_lock"
	end
	return "ok"
end

return SessionStore
]=====])
install('SSS', '', 'ModuleScript', 'BattleService', [=====[
--!nonstrict
-- BattleService: the player-vs-villain battle in the Arena. The SERVER owns spin, hits, outcomes and rewards.
--   Challenge prompt -> (queue if the arena is busy) -> countdown (both beys frozen) -> active -> finished
--   -> result screen (Rematch / Leave, or it closes itself) -> cleanup (beys removed, avatar restored)
-- What the server trusts from the client: only the player's bey position/velocity (client-owned physics, which a
-- cheater could fake) and a bare "my slam landed" signal, which is checked against the fall the server observed.
-- Clients never send damage, results, XP or Shards. See HANDOFF.md "Residual exploit exposure".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local GameConfig = require(Shared.GameConfig)
local CombatCore = require(Shared.Core.CombatCore)
local BattleCore = require(Shared.Core.BattleCore)
local Progression = require(Shared.Core.Progression)

local BeyFactory = require(script.Parent.BeyFactory)
local BeyService = require(script.Parent.BeyService)
local DataService = require(script.Parent.DataService)
local VillainAI = require(script.Parent.VillainAI)
local World = require(script.Parent.World)

local C, B, V, P = GameConfig.Combat, GameConfig.Battle, GameConfig.Villain, GameConfig.Progression

local BattleService = {}

local remotes
local current = nil -- the one active battle record, or nil
local queue = {} -- players waiting for the arena
local requestLimiter = CombatCore.newRateLimiter(C.RequestsPerSecond)

local function send(player, payload)
	if player and player.Parent then
		remotes.BattleEvent:FireClient(player, payload)
	end
end

local function difficultyFor(player)
	local data = DataService.get(player)
	local wins = data and data.Record.Wins or 0
	return wins >= V.HardAfterWins and "Hard" or V.Difficulty
end

function BattleService.inBattle(player)
	return current ~= nil and current.player == player
end

local function setBattleAttrs(player, state, endsAt)
	if player.Parent then
		player:SetAttribute("BattleState", state)
		player:SetAttribute("BattleEndsAt", endsAt or 0)
	end
end

local function removeFromQueue(player)
	for i = #queue, 1, -1 do
		if queue[i] == player then
			table.remove(queue, i)
		end
	end
end

local startBattle -- forward

local function cleanup(rec, rematch)
	if current ~= rec then
		return
	end
	current = nil
	if rec.ai then
		rec.ai:destroy()
	end
	if rec.villain and rec.villain.model then
		rec.villain.model:Destroy()
	end
	local player = rec.player
	if player.Parent then
		setBattleAttrs(player, "", 0)
		send(player, { kind = "closed" })
		if rematch and #queue == 0 then
			BeyService.removeBey(player)
			player:SetAttribute("Mode", "OnFoot") -- startBattle re-enters bey mode straight away
			startBattle(player)
			if current == nil or current.player ~= player then
				BeyService.exit(player) -- the restart didn't happen: never leave the avatar frozen
			end
		elseif rematch then
			-- Others are waiting: go to the back of the line instead of jumping it.
			BeyService.exit(player)
			table.insert(queue, player)
		else
			BeyService.exit(player)
		end
	end
	-- Next in line.
	while not current and #queue > 0 do
		local nextPlayer = table.remove(queue, 1)
		if nextPlayer.Parent and BeyService.mode(nextPlayer) == "OnFoot" then
			startBattle(nextPlayer)
		elseif nextPlayer.Parent then
			remotes.Toast:FireClient(nextPlayer, "Your turn in the arena came up while you were practicing. Challenge again when you're ready.")
		end
	end
	for i, p in ipairs(queue) do
		send(p, { kind = "queued", position = i })
	end
end

local function finishBattle(rec, result, now)
	local player = rec.player
	setBattleAttrs(player, "finished", 0)
	local outcome = result.outcomes.player
	local rewardText, levelUp = nil, nil
	if BattleCore.claimRewards(rec.battle) and player.Parent then
		local activeFor = now - (rec.startedAt or now)
		local reward = Progression.battleReward(outcome, rec.difficulty, P, GameConfig.Difficulty)
		-- No reward for quitting, and none for a loss that took almost no time (stops farming quick ring-outs).
		if result.reason == "left" or (outcome == "loss" and activeFor < P.MinLossSecondsForReward) then
			reward = { Outcome = outcome, XP = 0, Shards = 0 }
		end
		local data = DataService.get(player)
		if data and reward then
			local ok, info = Progression.grantBattleReward(data, rec.id, reward, P)
			if ok then
				DataService.markDirty(player)
				rewardText = reward
				if info.levelAfter > info.levelBefore then
					levelUp = info.levelAfter
				end
				DataService.sendProfile(player)
			end
		end
	end
	if rec.ai then
		rec.ai:setTelegraph(nil)
	end
	send(player, {
		kind = "finished",
		outcome = outcome,
		reason = result.reason,
		reward = rewardText,
		levelUp = levelUp,
		next = difficultyFor(player),
		closesIn = B.ResultTimeout,
	})
end

startBattle = function(player)
	if not player.Parent or not DataService.isReady(player) then
		return
	end
	if BeyService.mode(player) ~= "OnFoot" then
		return
	end
	if current then
		if not table.find(queue, player) then
			table.insert(queue, player)
		end
		send(player, { kind = "queued", position = table.find(queue, player) })
		return
	end
	local now = os.clock()
	local center = World.ARENA_CENTER
	local difficulty = difficultyFor(player)
	local diff = GameConfig.Difficulty[difficulty]
	local playerAt = CFrame.lookAt(center + Vector3.new(0, 5, B.StartRadius), center + Vector3.new(0, 5, 0))
	local villainAt = CFrame.lookAt(center + Vector3.new(0, 5, -B.StartRadius), center + Vector3.new(0, 5, 0))

	local mine = BeyService.enter(player, "Battle", playerAt, true, center)
	if not mine then
		return
	end
	local villain = BeyFactory.build({
		name = "villain_" .. V.Id,
		partIds = V.Parts,
		level = V.Level,
		cframe = villainAt,
		parent = BeyService.folder(),
	})
	villain.body.Anchored = true
	villain.model:SetAttribute("Villain", true)
	villain.model:SetAttribute("DisplayName", V.Name)

	local rec = {
		id = HttpService:GenerateGUID(false),
		player = player,
		mine = mine,
		villain = villain,
		difficulty = difficulty,
		diff = diff,
		contacts = CombatCore.newContacts(),
		villainFall = CombatCore.newFallTracker(),
		outTimers = {},
		startedAt = nil,
	}
	rec.battle = BattleCore.new(rec.id, {
		{ key = "player", maxSpin = mine.maxSpin, drain = CombatCore.drainPerSecond(mine.stats, C) },
		{ key = "villain", maxSpin = villain.maxSpin, drain = CombatCore.drainPerSecond(villain.stats, C) },
	}, B, now)
	rec.ai = VillainAI.new(villain, diff, center, { BeyService.folder() })
	current = rec
	removeFromQueue(player)
	setBattleAttrs(player, "countdown", 0)
	send(player, { kind = "countdown", seconds = B.Countdown, foe = V.Name, difficulty = difficulty })
end

-- Applies a contact hit between the two beys.
local function resolveContact(rec, now)
	local pb, vb = rec.mine.body, rec.villain.body
	local pPos, vPos = pb.Position, vb.Position
	local dist = (vPos - pPos).Magnitude
	if not CombatCore.contactStep(rec.contacts, "player", "villain", dist, now, C) then
		return
	end
	local pVel, vVel = pb.AssemblyLinearVelocity, vb.AssemblyLinearVelocity
	local n, closing, share = CombatCore.contact(pPos, pVel, vPos, vVel)
	if not n or closing <= C.MinImpactSpeed then
		return
	end
	local dealt = CombatCore.hitDamage(rec.mine.stats, rec.villain.stats, closing, share, C)
	local taken = CombatCore.hitDamage(rec.villain.stats, rec.mine.stats, closing, 1 - share, C) * rec.diff.Damage
	dealt = BattleCore.damage(rec.battle, "villain", dealt)
	taken = BattleCore.damage(rec.battle, "player", taken)
	local kbVillain = CombatCore.knockback(rec.mine.stats, rec.villain.stats, closing, C)
	local kbPlayer = CombatCore.knockback(rec.villain.stats, rec.mine.stats, closing, C)
	vb.AssemblyLinearVelocity += (n + Vector3.new(0, 0.25, 0)).Unit * kbVillain
	remotes.Knockback:FireClient(rec.player, (-n + Vector3.new(0, 0.25, 0)).Unit * kbPlayer)
	rec.ai:onHit(now)
	send(rec.player, { kind = "hit", dealt = dealt, taken = taken, at = (pPos + vPos) / 2, strength = math.clamp(closing / 60, 0.2, 1) })
end

-- The player's slam landed (already validated by BeyService against the observed fall).
local function playerSlam(rec, fall, now)
	local pPos, vPos = rec.mine.body.Position, rec.villain.body.Position
	local d = Vector3.new(vPos.X - pPos.X, 0, vPos.Z - pPos.Z)
	local dmg = CombatCore.slamDamage(rec.mine.stats, rec.villain.stats, fall, d.Magnitude, C)
	local recoil = BattleCore.damage(rec.battle, "player", CombatCore.slamRecoil(rec.mine.stats, C))
	local dealt = 0
	if dmg > 0 then
		dealt = BattleCore.damage(rec.battle, "villain", dmg)
		local dir = (d.Magnitude > 0.01 and d.Unit or Vector3.new(0, 0, -1)) + Vector3.new(0, 0.6, 0)
		rec.villain.body.AssemblyLinearVelocity += dir.Unit * C.SlamKnockback
		rec.ai:onHit(now)
	end
	send(rec.player, { kind = "slam", hit = dmg > 0, dealt = dealt, recoil = recoil })
end

local function villainSlam(rec, fallSeen, now)
	if rec.battle.state ~= "active" then
		return
	end
	local fall = math.max(fallSeen, CombatCore.maxFall(rec.villainFall, now, C.SlamFallWindow))
	local pPos, vPos = rec.mine.body.Position, rec.villain.body.Position
	local d = Vector3.new(pPos.X - vPos.X, 0, pPos.Z - vPos.Z)
	local dmg = CombatCore.slamDamage(rec.villain.stats, rec.mine.stats, fall, d.Magnitude, C) * rec.diff.Damage
	if dmg > 0 then
		local taken = BattleCore.damage(rec.battle, "player", dmg)
		local dir = (d.Magnitude > 0.01 and d.Unit or Vector3.new(0, 0, 1)) + Vector3.new(0, 0.6, 0)
		remotes.Knockback:FireClient(rec.player, dir.Unit * C.SlamKnockback)
		send(rec.player, { kind = "hit", dealt = 0, taken = taken, at = pPos, strength = 1, slam = true })
	end
	send(rec.player, { kind = "villainSlam", at = vPos })
end

local function step(dt)
	local rec = current
	if not rec then
		return
	end
	local now = os.clock()
	local player = rec.player
	-- Interrupted: player gone, bey removed, or the villain model destroyed by something else.
	if not player.Parent or not rec.mine.body.Parent or not rec.villain.body.Parent then
		BattleCore.leave(rec.battle, "player", now)
		cleanup(rec, false)
		return
	end

	local events = BattleCore.update(rec.battle, now, dt)
	for _, ev in ipairs(events) do
		if ev.kind == "started" then
			rec.startedAt = now
			BeyService.release(player)
			rec.villain.body.Anchored = false
			rec.villain.body:SetNetworkOwner(nil)
			setBattleAttrs(player, "active", Workspace:GetServerTimeNow() + B.Duration)
			send(player, { kind = "started", duration = B.Duration })
		elseif ev.kind == "finished" then
			finishBattle(rec, ev.result, now)
		elseif ev.kind == "cleanup" then
			cleanup(rec, false)
			return
		end
	end

	local b = rec.battle
	if b.state == "active" then
		CombatCore.recordFall(rec.villainFall, rec.villain.body.AssemblyLinearVelocity.Y, now, C.SlamFallWindow)
		-- ring-outs (relative to the arena centre)
		local center = World.ARENA_CENTER
		if CombatCore.ringOutStep(rec.outTimers, "player", rec.mine.body.Position - center, now, B) then
			BattleCore.ringOut(b, "player")
		end
		if CombatCore.ringOutStep(rec.outTimers, "villain", rec.villain.body.Position - center, now, B) then
			BattleCore.ringOut(b, "villain")
		end
		resolveContact(rec, now)
		local mine = rec.mine.body
		rec.ai:step(dt, now, { pos = mine.Position, vel = mine.AssemblyLinearVelocity }, BattleCore.fraction(b, "villain"), function(fall)
			villainSlam(rec, fall, now)
		end)
		-- a knockout this frame is resolved on the next update()
	elseif rec.ai then
		rec.ai:idle(dt)
	end

	-- spin for the HUD (attributes replicate) and the cosmetic hub speed
	for key, beyRec in pairs({ player = rec.mine, villain = rec.villain }) do
		local side = b.sides[key]
		if beyRec.body.Parent then
			beyRec.body:SetAttribute("Spin", side.spin)
			beyRec.body:SetAttribute("MaxSpin", side.maxSpin)
			beyRec.hinge.AngularVelocity = CombatCore.visualSpin(side.spin / side.maxSpin, C)
		end
	end
end

function BattleService.onSlam(player)
	local rec = current
	if not rec or rec.player ~= player or rec.battle.state ~= "active" then
		return
	end
	local fall = BeyService.validateSlam(player)
	if fall then
		playerSlam(rec, fall, os.clock())
	end
end

-- Player reset / respawned / was interrupted while in bey mode.
function BattleService.onInterrupted(player)
	local rec = current
	if rec and rec.player == player then
		local ev = BattleCore.leave(rec.battle, "player", os.clock())
		if ev then
			finishBattle(rec, ev.result, os.clock())
		end
		cleanup(rec, false)
	else
		BeyService.exit(player)
	end
end

function BattleService.start(r)
	remotes = r
	RunService.Heartbeat:Connect(step)

	remotes.Request.OnServerEvent:Connect(function(player, req)
		if type(req) ~= "table" or type(req.action) ~= "string" then
			return
		end
		if not CombatCore.allow(requestLimiter, player, os.clock()) then
			return
		end
		local rec = current
		local mine = rec and rec.player == player
		if req.action == "rematch" and mine and rec.battle.state == "finished" then
			BattleCore.requestCleanup(rec.battle, os.clock())
			cleanup(rec, true)
		elseif req.action == "leave" and mine and rec.battle.state == "finished" then
			BattleCore.requestCleanup(rec.battle, os.clock())
			cleanup(rec, false)
		elseif req.action == "forfeit" and mine and (rec.battle.state == "active" or rec.battle.state == "countdown") then
			local ev = BattleCore.leave(rec.battle, "player", os.clock())
			if ev then
				finishBattle(rec, ev.result, os.clock())
			end
		elseif req.action == "leaveQueue" then
			removeFromQueue(player)
			send(player, { kind = "closed" })
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeFromQueue(player)
		CombatCore.forget(requestLimiter, player)
		local rec = current
		if rec and rec.player == player then
			BattleCore.leave(rec.battle, "player", os.clock())
			cleanup(rec, false)
		end
	end)
end

BattleService.challenge = function(player)
	startBattle(player)
end

return BattleService
]=====])
install('SSS', '', 'ModuleScript', 'BeyFactory', [=====[
--!nonstrict
-- BeyFactory: builds one bey model, used for both player and villain beys.
--   Body   invisible 4-stud ball that does the physics (the collider)
--   Align  AlignOrientation that stops the ball rolling and sets the bey's lean (client for players, server for NPCs)
--   Top    small hub, hinge-motored so it spins; BeyVisuals welds the designed parts to it
-- Attributes on Body: Attack, Defense, Stamina, Balance, Level, Spin, MaxSpin (Spin is set by the battle service).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local BeyVisuals = require(Shared.BeyVisuals)
local GameConfig = require(Shared.GameConfig)
local CombatCore = require(Shared.Core.CombatCore)

local BeyFactory = {}

-- opts: { name, partIds, level, cframe, parent }
-- Returns { model, body, top, hinge, align, stats, maxSpin }
function BeyFactory.build(opts)
	local stats = BeyConfig.ComputeStats(opts.partIds, opts.level)
	local maxSpin = CombatCore.maxSpin(stats, GameConfig.Combat)

	local model = Instance.new("Model")
	model.Name = opts.name
	model.Parent = opts.parent -- parented first so the welds capture the layout

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(4, 4, 4)
	body.Transparency = 1
	body.CustomPhysicalProperties = PhysicalProperties.new(1, 0.1, 0.1, 1, 1)
	body.CFrame = opts.cframe
	body.Parent = model
	model.PrimaryPart = body
	for _, stat in ipairs(BeyConfig.StatNames) do
		body:SetAttribute(stat, stats[stat])
	end
	body:SetAttribute("Level", opts.level)
	body:SetAttribute("MaxSpin", maxSpin)
	body:SetAttribute("Spin", maxSpin)

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = body
	local align = Instance.new("AlignOrientation")
	align.Name = "Align"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = center
	align.RigidityEnabled = true
	align.CFrame = opts.cframe.Rotation
	align.Parent = model

	local top = Instance.new("Part")
	top.Name = "Top"
	top.Shape = Enum.PartType.Cylinder
	top.Size = Vector3.new(0.8, 1.2, 1.2)
	top.Color = BeyConfig.RarityColors[BeyConfig.Parts[opts.partIds.Layer].Rarity]
	top.Material = Enum.Material.Metal
	top.CanCollide = false
	top.CanQuery = false
	top.CanTouch = false
	top.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0.1, 0.1, 1, 1)
	top.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(90))
	top.Parent = model
	local topAxis = Instance.new("Attachment")
	topAxis.Name = "Axis"
	topAxis.Parent = top
	local bodyAxis = Instance.new("Attachment")
	bodyAxis.Name = "Axis"
	bodyAxis.CFrame = CFrame.Angles(0, 0, math.rad(90))
	bodyAxis.Parent = body
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "Spin"
	hinge.Attachment0 = bodyAxis
	hinge.Attachment1 = topAxis
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = 50000
	hinge.AngularVelocity = GameConfig.Combat.VisualSpinMax
	hinge.Parent = model

	BeyVisuals.Attach(top, body.CFrame, opts.partIds, model)

	return { model = model, body = body, top = top, hinge = hinge, align = align, stats = stats, maxSpin = maxSpin }
end

return BeyFactory
]=====])
install('SSS', '', 'ModuleScript', 'BeyService', [=====[
--!nonstrict
-- BeyService: puts a player into "bey mode" and back out, safely, whatever happens.
-- Player attribute "Mode": "OnFoot" | "Practice" | "Battle". The client controller binds to the player's bey when
-- it appears in Workspace.Beys and restores the normal camera when it is removed.
-- Entering bey mode parks the avatar (anchored, controls off) at World.PARK; leaving always restores it:
-- after a battle, on reset/death, on leaving practice, or if the player leaves the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local GameConfig = require(Shared.GameConfig)
local CombatCore = require(Shared.Core.CombatCore)

local BeyFactory = require(script.Parent.BeyFactory)
local World = require(script.Parent.World)

local BeyService = {}

local C = GameConfig.Combat
local beysFolder
local beys = {} -- player -> bey record (see BeyFactory) + { fall = fall tracker }
local saved = {} -- player -> { walk, jumpHeight, jumpPower }
local DataService
local remotes
local slamLimiter = CombatCore.newRateLimiter(C.RequestsPerSecond)
local lastSlam = {}

function BeyService.folder()
	return beysFolder
end

function BeyService.get(player)
	return beys[player]
end

local function humanoidAndRoot(player)
	local char = player.Character
	if not char then
		return nil, nil
	end
	return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function parkAvatar(player)
	local hum, root = humanoidAndRoot(player)
	if hum and not saved[player] then
		saved[player] = { walk = hum.WalkSpeed, jumpHeight = hum.JumpHeight, jumpPower = hum.JumpPower }
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
		hum.JumpPower = 0
	end
	if root then
		root.Anchored = true
		root.CFrame = CFrame.new(World.PARK + Vector3.new(math.random(-8, 8), 0, 0))
	end
end

local function restoreAvatar(player)
	local hum, root = humanoidAndRoot(player)
	local s = saved[player]
	saved[player] = nil
	if hum then
		hum.WalkSpeed = (s and s.walk and s.walk > 0) and s.walk or 16
		hum.JumpHeight = (s and s.jumpHeight and s.jumpHeight > 0) and s.jumpHeight or 7.2
		hum.JumpPower = (s and s.jumpPower and s.jumpPower > 0) and s.jumpPower or 50
	end
	if root then
		root.Anchored = false
		root.CFrame = CFrame.new(World.SPAWN + Vector3.new(math.random(-4, 4), 0, math.random(-2, 2)))
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Spawns the player's bey at `cframe` and switches them to `mode`. anchored = frozen (battle countdown).
-- center: the stadium centre (the client uses it to recover a stuck bey; practice resets go to BeySpawn).
function BeyService.enter(player, mode, cframe, anchored, center)
	BeyService.removeBey(player)
	local data = DataService.get(player)
	if not data then
		return nil
	end
	parkAvatar(player)
	local rec = BeyFactory.build({
		name = tostring(player.UserId),
		partIds = data.Equipped,
		level = DataService.levelOf(player),
		cframe = cframe,
		parent = beysFolder,
	})
	rec.fall = CombatCore.newFallTracker()
	beys[player] = rec
	if anchored then
		rec.body.Anchored = true
	else
		rec.body:SetNetworkOwner(player)
	end
	player:SetAttribute("BeySpawn", cframe.Position)
	player:SetAttribute("ArenaCenter", center)
	player:SetAttribute("Mode", mode)
	return rec
end

-- Unfreezes a bey after a countdown and hands physics back to its player.
function BeyService.release(player)
	local rec = beys[player]
	if rec and rec.body.Parent then
		rec.body.Anchored = false
		rec.body:SetNetworkOwner(player)
	end
end

function BeyService.removeBey(player)
	local rec = beys[player]
	beys[player] = nil
	if rec and rec.model then
		rec.model:Destroy()
	end
end

-- Back to walking around, from any state.
function BeyService.exit(player)
	BeyService.removeBey(player)
	if player.Parent then
		player:SetAttribute("Mode", "OnFoot")
		restoreAvatar(player)
	end
end

function BeyService.mode(player)
	return player:GetAttribute("Mode") or "OnFoot"
end

-- Records the downward speed the server sees for every bey (slam claims are checked against this).
local function trackFalls()
	local now = os.clock()
	for _, rec in pairs(beys) do
		if rec.body.Parent then
			CombatCore.recordFall(rec.fall, rec.body.AssemblyLinearVelocity.Y, now, C.SlamFallWindow)
		end
	end
end

-- Practice slams knock the training dummies about (battle slams are handled by BattleService).
local function practiceSlam(player)
	local rec = beys[player]
	if not rec then
		return
	end
	local now = os.clock()
	local fall = CombatCore.maxFall(rec.fall, now, C.SlamFallWindow)
	if fall < C.SlamMinFallSpeed then
		return
	end
	local pos = rec.body.Position
	for _, dummy in ipairs(CollectionService:GetTagged("SpinforgeDummy")) do
		local offset = dummy.Position - pos
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= C.SlamRadius + 3 and math.abs(offset.Y) < 10 then
			local dir = (flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)) + Vector3.new(0, 0.5, 0)
			dummy:ApplyImpulse(dir.Unit * C.SlamKnockback * 3 * dummy.AssemblyMass * math.clamp(fall / 100, 0.5, 1.5))
		end
	end
	remotes.BattleEvent:FireClient(player, { kind = "slam", hit = true })
end

-- Called by BattleService for slams in battle; returns the validated fall speed or nil.
function BeyService.validateSlam(player)
	local rec = beys[player]
	if not rec or not rec.body.Parent then
		return nil
	end
	local now = os.clock()
	if not CombatCore.allow(slamLimiter, player, now) then
		return nil
	end
	if lastSlam[player] and now - lastSlam[player] < C.SlamCooldown then
		return nil
	end
	local fall = CombatCore.maxFall(rec.fall, now, C.SlamFallWindow)
	if fall < C.SlamMinFallSpeed then
		return nil
	end
	lastSlam[player] = now
	return fall
end

local function resetDummies()
	for _, dummy in ipairs(CollectionService:GetTagged("SpinforgeDummy")) do
		local home = dummy:GetAttribute("Home")
		if home and (dummy.Position - home).Magnitude > 60 then
			dummy.AssemblyLinearVelocity = Vector3.zero
			dummy.CFrame = CFrame.new(home) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

function BeyService.startPractice(player)
	if BeyService.mode(player) ~= "OnFoot" then
		return
	end
	local spawnAt = CFrame.new(World.TRAINING_CENTER + Vector3.new(0, 5, 8))
	BeyService.enter(player, "Practice", spawnAt, false, World.TRAINING_CENTER)
	resetDummies()
end

function BeyService.start(r, dataService, onSlam)
	remotes = r
	DataService = dataService
	beysFolder = Workspace:FindFirstChild("Beys")
	if not beysFolder then
		beysFolder = Instance.new("Folder")
		beysFolder.Name = "Beys"
		beysFolder.Parent = Workspace
	end
	game:GetService("RunService").Heartbeat:Connect(trackFalls)

	remotes.SlamLanded.OnServerEvent:Connect(function(player)
		local mode = BeyService.mode(player)
		if mode == "Practice" then
			if BeyService.validateSlam(player) then
				practiceSlam(player)
			end
		elseif mode == "Battle" then
			onSlam(player)
		end
	end)

	-- A character that appears outside the hub (e.g. at a template SpawnLocation inside a stadium) is moved to
	-- the hub spawn, so nobody starts trapped in a bowl.
	local function toHubIfLost(player)
		task.defer(function()
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and BeyService.mode(player) == "OnFoot" and not root.Anchored then
				local flat = Vector3.new(root.Position.X - World.HUB_CENTER.X, 0, root.Position.Z - World.HUB_CENTER.Z)
				if flat.Magnitude > 60 then
					root.CFrame = CFrame.new(World.SPAWN)
				end
			end
		end)
	end
	BeyService.toHubIfLost = toHubIfLost

	local function hookCharacter(player)
		if player.Character then
			World.tagCharacter(player.Character)
		end
		player.CharacterAdded:Connect(function(char)
			World.tagCharacter(char)
			-- A reset or respawn while in bey mode: end it cleanly (BattleService treats it as leaving).
			if BeyService.mode(player) ~= "OnFoot" then
				BeyService.onInterrupted(player)
			end
			toHubIfLost(player)
		end)
		toHubIfLost(player)
	end
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Mode", "OnFoot")
		hookCharacter(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Mode", player:GetAttribute("Mode") or "OnFoot")
		hookCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		BeyService.removeBey(player)
		saved[player] = nil
		lastSlam[player] = nil
		CombatCore.forget(slamLimiter, player)
	end)
end

-- Overridden by Main so BattleService can react (forfeit); default just exits.
function BeyService.onInterrupted(player)
	BeyService.exit(player)
end

return BeyService
]=====])
print('Spinforge installer part 3 of 7 done. Now run part 4.')

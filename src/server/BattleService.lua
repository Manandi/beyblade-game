--!nonstrict
-- BattleService: the player-vs-villain battle in the Arena. The SERVER owns spin, hits, outcomes and rewards.
--   Challenge prompt -> (queue if the arena is busy) -> countdown (both beys frozen) -> active -> finished
--   -> result screen (Rematch / Leave, or it closes itself) -> cleanup (beys removed, avatar restored)
-- What the server trusts from the client: only the player's bey position/velocity (client-owned physics, which a
-- cheater could fake), a bare "my slam landed" signal (checked against the fall the server observed), and the time
-- the player pressed LAUNCH (checked against the meter's window; the server judges the timing itself), and
-- "use special 1/2" / "awaken" requests (the server checks the loadout, cooldowns and meter; see SpecialsCore).
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
local LaunchCore = require(Shared.Core.LaunchCore)
local SpecialsCore = require(Shared.Core.SpecialsCore)
local BeyConfig = require(Shared.BeyConfig)

local BeyFactory = require(script.Parent.BeyFactory)
local BeyService = require(script.Parent.BeyService)
local DataService = require(script.Parent.DataService)
local VillainAI = require(script.Parent.VillainAI)
local World = require(script.Parent.World)

local C, B, V, P, L, A = GameConfig.Combat, GameConfig.Battle, GameConfig.Villain, GameConfig.Progression, GameConfig.Launch, GameConfig.Specials
local SNAPSHOT_EVERY = 0.2 -- seconds between specials/awakening HUD updates sent to the player

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
		-- Skill launch: the meter runs on the shared server clock during the countdown.
		meter = LaunchCore.newMeter(Workspace:GetServerTimeNow(), B.Countdown, Random.new():NextNumber(), L),
		launch = {}, -- side -> { quality, label }
		snapshotAt = 0,
	}
	local equipped = (DataService.get(player) or {}).Equipped or BeyConfig.StarterLoadout
	rec.specials = {
		player = SpecialsCore.newSide(equipped, BeyConfig.Items),
		villain = SpecialsCore.newSide({ Spirit = V.Spirit, Special1 = V.Specials[1], Special2 = V.Specials[2] }, BeyConfig.Items),
	}
	rec.spirits = { player = equipped.Spirit, villain = V.Spirit }
	rec.battle = BattleCore.new(rec.id, {
		{ key = "player", maxSpin = mine.maxSpin, drain = CombatCore.drainPerSecond(mine.stats, C) },
		{ key = "villain", maxSpin = villain.maxSpin, drain = CombatCore.drainPerSecond(villain.stats, C) },
	}, B, now)
	for key, side in pairs(rec.specials) do
		BattleCore.setDrain(rec.battle, key, rec.battle.sides[key].drain * SpecialsCore.drain(side))
	end
	rec.ai = VillainAI.new(villain, diff, center, { BeyService.folder() })
	-- The villain's launch is decided now (its skill depends on difficulty).
	local vq = LaunchCore.villainQuality(diff.Launch or 0.7, Random.new():NextNumber())
	rec.launch.villain = { quality = vq, label = vq >= 0.95 and "PERFECT" or vq >= L.Good and "GOOD" or "WEAK" }
	BattleCore.setStartSpin(rec.battle, "villain", LaunchCore.effects(vq, L).spinFraction)
	current = rec
	removeFromQueue(player)
	setBattleAttrs(player, "countdown", 0)
	local m = rec.meter
	send(player, {
		kind = "countdown",
		seconds = B.Countdown,
		foe = V.Name,
		difficulty = difficulty,
		loadout = { spirit = equipped.Spirit, specials = { equipped.Special1, equipped.Special2 } },
		foeLoadout = { spirit = V.Spirit, specials = V.Specials },
		meter = { start = m.start, finish = m.finish, period = m.period, zoneCenter = m.zoneCenter, greenHalf = m.greenHalf, yellowHalf = m.yellowHalf },
	})
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
	local sp, sv = rec.specials.player, rec.specials.villain
	local pEmpowered = sp.empower ~= nil and now <= sp.empower.untilT
	local vEmpowered = sv.empower ~= nil and now <= sv.empower.untilT
	local pOut, pKbOut = SpecialsCore.outgoing(sp, now, A, true)
	local vOut, vKbOut = SpecialsCore.outgoing(sv, now, A, true)
	local pIn, pKbIn = SpecialsCore.incoming(sp, now, A)
	local vIn, vKbIn = SpecialsCore.incoming(sv, now, A)
	local dealt = CombatCore.hitDamage(rec.mine.stats, rec.villain.stats, closing, share, C) * pOut * vIn
	local taken = CombatCore.hitDamage(rec.villain.stats, rec.mine.stats, closing, 1 - share, C) * rec.diff.Damage * vOut * pIn
	dealt = BattleCore.damage(rec.battle, "villain", dealt)
	taken = BattleCore.damage(rec.battle, "player", taken)
	SpecialsCore.charge(sp, dealt * A.MeterPerDamageDealt + taken * A.MeterPerDamageTaken, A)
	SpecialsCore.charge(sv, taken * A.MeterPerDamageDealt + dealt * A.MeterPerDamageTaken, A)
	local kbVillain = math.min(CombatCore.knockback(rec.mine.stats, rec.villain.stats, closing, C) * pKbOut * vKbIn, C.MaxKnockback * 2)
	local kbPlayer = math.min(CombatCore.knockback(rec.villain.stats, rec.mine.stats, closing, C) * vKbOut * pKbIn, C.MaxKnockback * 2)
	vb.AssemblyLinearVelocity += (n + Vector3.new(0, 0.25, 0)).Unit * kbVillain
	remotes.Knockback:FireClient(rec.player, (-n + Vector3.new(0, 0.25, 0)).Unit * kbPlayer)
	rec.ai:onHit(now)
	local strength = math.clamp(closing / 60, 0.2, 1)
	if pEmpowered or vEmpowered then
		strength = 1
	end
	send(rec.player, {
		kind = "hit",
		dealt = dealt,
		taken = taken,
		at = (pPos + vPos) / 2,
		normal = n,
		strength = strength,
		crit = pEmpowered or nil,
		foeCrit = vEmpowered or nil,
	})
end

-- The player's slam landed (already validated by BeyService against the observed fall).
local function playerSlam(rec, fall, now)
	local pPos, vPos = rec.mine.body.Position, rec.villain.body.Position
	local d = Vector3.new(vPos.X - pPos.X, 0, vPos.Z - pPos.Z)
	local pOut = SpecialsCore.outgoing(rec.specials.player, now, A, false)
	local vIn = SpecialsCore.incoming(rec.specials.villain, now, A)
	local dmg = CombatCore.slamDamage(rec.mine.stats, rec.villain.stats, fall, d.Magnitude, C) * pOut * vIn
	local recoil = BattleCore.damage(rec.battle, "player", CombatCore.slamRecoil(rec.mine.stats, C))
	local dealt = 0
	if dmg > 0 then
		dealt = BattleCore.damage(rec.battle, "villain", dmg)
		SpecialsCore.charge(rec.specials.player, dealt * A.MeterPerDamageDealt, A)
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
	local vOut = SpecialsCore.outgoing(rec.specials.villain, now, A, false)
	local pIn = SpecialsCore.incoming(rec.specials.player, now, A)
	local dmg = CombatCore.slamDamage(rec.villain.stats, rec.mine.stats, fall, d.Magnitude, C) * rec.diff.Damage * vOut * pIn
	if dmg > 0 then
		local taken = BattleCore.damage(rec.battle, "player", dmg)
		SpecialsCore.charge(rec.specials.player, taken * A.MeterPerDamageTaken, A)
		SpecialsCore.charge(rec.specials.villain, taken * A.MeterPerDamageDealt, A)
		local dir = (d.Magnitude > 0.01 and d.Unit or Vector3.new(0, 0, 1)) + Vector3.new(0, 0.6, 0)
		remotes.Knockback:FireClient(rec.player, dir.Unit * C.SlamKnockback)
		send(rec.player, { kind = "hit", dealt = 0, taken = taken, at = pPos, strength = 1, slam = true })
	end
	send(rec.player, { kind = "villainSlam", at = vPos })
end

-- Uses special `index` for `who` ("player" | "villain"). The server applies everything except the player's own dash
-- burst, which the player's client applies to its bey (client-owned physics). Returns true if it was used.
local function useSpecial(rec, who, index, now)
	local b = rec.battle
	if b.state ~= "active" then
		return false
	end
	local side = rec.specials[who]
	local def = SpecialsCore.use(side, index, now)
	if not def then
		return false
	end
	local foeKey = who == "player" and "villain" or "player"
	local selfBody = who == "player" and rec.mine.body or rec.villain.body
	local foeBody = who == "player" and rec.villain.body or rec.mine.body
	local t = def.Tuning
	local toFoe = Vector3.new(foeBody.Position.X - selfBody.Position.X, 0, foeBody.Position.Z - selfBody.Position.Z)
	local dir = toFoe.Magnitude > 0.1 and toFoe.Unit or Vector3.new(0, 0, -1)
	local ev = { kind = "special", who = who, id = def.Id, special = def.Kind, spirit = rec.spirits[who], at = selfBody.Position, dir = dir }
	if def.Kind == "dash" then
		ev.dash = t.DashSpeed
		if who == "villain" then
			selfBody.AssemblyLinearVelocity = Vector3.new(dir.X * t.DashSpeed, selfBody.AssemblyLinearVelocity.Y, dir.Z * t.DashSpeed)
		end
	end
	if (def.Kind == "heal" or def.Kind == "guard") and t.Heal then
		ev.healed = BattleCore.heal(b, who, b.sides[who].maxSpin * t.Heal)
	end
	if def.Kind == "quake" then
		local dist = toFoe.Magnitude
		if dist <= t.Radius then
			local out = SpecialsCore.outgoing(side, now, A, false)
			local inc, kbIn = SpecialsCore.incoming(rec.specials[foeKey], now, A)
			local falloff = 1 - 0.4 * (dist / t.Radius)
			local dmg = t.Damage * falloff * out * inc * (who == "villain" and rec.diff.Damage or 1)
			local applied = BattleCore.damage(b, foeKey, dmg)
			ev.hit, ev.dealt = true, applied
			SpecialsCore.charge(side, applied * A.MeterPerDamageDealt, A)
			SpecialsCore.charge(rec.specials[foeKey], applied * A.MeterPerDamageTaken, A)
			local push = (dir + Vector3.new(0, 0.5, 0)).Unit * t.Knockback * kbIn
			if foeKey == "villain" then
				rec.villain.body.AssemblyLinearVelocity += push
				rec.ai:onHit(now)
			else
				remotes.Knockback:FireClient(rec.player, push)
			end
		end
	end
	send(rec.player, ev)
	return true
end

local function awaken(rec, who, now)
	if rec.battle.state ~= "active" or not SpecialsCore.awaken(rec.specials[who], now, A) then
		return false
	end
	local body = who == "player" and rec.mine.body or rec.villain.body
	send(rec.player, { kind = "awaken", who = who, spirit = rec.spirits[who], at = body.Position, duration = A.AwakenDuration })
	return true
end

local function sendSnapshot(rec, now)
	if now - rec.snapshotAt < SNAPSHOT_EVERY then
		return
	end
	rec.snapshotAt = now
	local you = SpecialsCore.snapshot(rec.specials.player, now, A)
	you.speed = SpecialsCore.speed(rec.specials.player, now, A)
	send(rec.player, { kind = "specials", you = you, foe = SpecialsCore.snapshot(rec.specials.villain, now, A) })
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

	-- Countdown over and the player never pressed LAUNCH: a weak launch.
	if rec.battle.state == "countdown" and now - rec.battle.stateAt >= B.Countdown and not rec.launch.player then
		rec.launch.player = { quality = L.NoPress, label = "TOO LATE" }
		BattleCore.setStartSpin(rec.battle, "player", LaunchCore.effects(L.NoPress, L).spinFraction)
	end

	local events = BattleCore.update(rec.battle, now, dt)
	for _, ev in ipairs(events) do
		if ev.kind == "started" then
			rec.startedAt = now
			BeyService.release(player)
			rec.villain.body.Anchored = false
			rec.villain.body:SetNetworkOwner(nil)
			-- LET IT RIP: the villain launches toward the player; the player's client launches its own bey.
			local pl = rec.launch.player or { quality = L.NoPress, label = "TOO LATE" }
			local vl = rec.launch.villain
			local ve = LaunchCore.effects(vl.quality, L)
			local toPlayer = rec.mine.body.Position - rec.villain.body.Position
			toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
			if toPlayer.Magnitude > 0.1 then
				rec.villain.body.AssemblyLinearVelocity = toPlayer.Unit * ve.speed
			end
			rec.ai:launched(ve.boost, now)
			SpecialsCore.start(rec.specials.player, now, A)
			SpecialsCore.start(rec.specials.villain, now, A)
			local pe = LaunchCore.effects(pl.quality, L)
			setBattleAttrs(player, "active", Workspace:GetServerTimeNow() + B.Duration)
			send(player, {
				kind = "started",
				duration = B.Duration,
				launch = { quality = pl.quality, label = pl.label, speed = pe.speed, boost = pe.boost, spin = pe.spinFraction },
				foeLaunch = vl.label,
			})
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
		SpecialsCore.tick(rec.specials.player, dt, A)
		SpecialsCore.tick(rec.specials.villain, dt, A)
		resolveContact(rec, now)
		local mine = rec.mine.body
		rec.ai.speedMul = SpecialsCore.speed(rec.specials.villain, now, A)
		rec.ai:step(dt, now, { pos = mine.Position, vel = mine.AssemblyLinearVelocity }, BattleCore.fraction(b, "villain"), function(fall)
			villainSlam(rec, fall, now)
		end)
		-- the villain's specials and awakening
		local choice = rec.ai:chooseSpecial(now, {
			specials = rec.specials.villain,
			foe = rec.specials.player,
			canAwaken = SpecialsCore.canAwaken(rec.specials.villain, A),
			spin = BattleCore.fraction(b, "villain"),
		})
		if choice == "awaken" then
			awaken(rec, "villain", now)
		elseif choice then
			useSpecial(rec, "villain", choice, now)
		end
		sendSnapshot(rec, now)
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
		if req.action == "launch" and mine and rec.battle.state == "countdown" and not rec.launch.player then
			-- One press per battle. The server judges where the needle was at the stamped time.
			local t = LaunchCore.acceptPress(rec.meter, req.t, Workspace:GetServerTimeNow(), L)
			local q, label = L.Miss, "WEAK"
			if t then
				q, label = LaunchCore.quality(rec.meter, LaunchCore.needle(rec.meter, t), L)
			end
			rec.launch.player = { quality = q, label = label }
			BattleCore.setStartSpin(rec.battle, "player", LaunchCore.effects(q, L).spinFraction)
			send(player, { kind = "launchLocked", label = label, quality = q })
		elseif req.action == "special" and mine and (req.index == 1 or req.index == 2) then
			if not useSpecial(rec, "player", req.index, os.clock()) then
				send(player, { kind = "specialRefused", index = req.index })
			end
		elseif req.action == "awaken" and mine then
			awaken(rec, "player", os.clock())
		elseif req.action == "rematch" and mine and rec.battle.state == "finished" then
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

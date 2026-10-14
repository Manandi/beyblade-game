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
install('RS', '', 'ModuleScript', 'GameConfig', [=====[
--!nonstrict
-- GameConfig: tuning for combat, battles, the villain, progression and saving. Pure data (no Roblox APIs).
-- Movement tuning stays in BeyConfig.Movement; parts, rarities and crate odds stay in BeyConfig.

local GameConfig = {}

-- What each stat does (bey stats = the three parts' stats x the level multiplier; see BeyConfig.ComputeStats):
--   Attack   more damage dealt per hit (AttackScale per point) and a little more top speed
--   Defense  less damage taken (DefenseScale per point) and less knockback taken
--   Stamina  a bigger spin pool (SpinPerStamina per point) and slower passive spin loss
--   Balance  less knockback taken and less self-damage when your slam lands, and a little more top speed
GameConfig.Combat = {
	BaseSpin = 100, -- spin pool before Stamina
	SpinPerStamina = 4,
	BaseDrain = 0.9, -- spin lost per second just by spinning
	DrainReductionPerStamina = 0.02, -- each Stamina point slows that drain by 2% (capped)
	MaxDrainReduction = 0.6,

	ContactDistance = 4.4, -- centres closer than this = the beys are touching (bodies are 4-stud balls)
	SeparationDistance = 5.4, -- must separate this far before the same pair can register a new hit
	HitCooldown = 0.35, -- and at least this long between hits for the same pair
	MinImpactSpeed = 6, -- closing speeds below this are a nudge, not a hit
	DamagePerSpeed = 0.42, -- damage per stud/s of closing speed above the minimum
	MinHitDamage = 1,
	MaxHitDamage = 22,
	AttackScale = 0.04,
	DefenseScale = 0.04,
	KnockbackPerSpeed = 1.0,
	MaxKnockback = 80,
	KnockbackResistPerPoint = 0.02, -- per point of Defense + Balance, capped
	MaxKnockbackResist = 0.6,

	SlamRadius = 9, -- a landing slam hits beys within this distance
	SlamMinFallSpeed = 45, -- the server must have seen the slammer falling at least this fast
	SlamFallWindow = 0.6, -- ... within this many seconds before the landing report
	SlamBaseDamage = 10,
	SlamDamagePerSpeed = 0.1,
	SlamMaxDamage = 26,
	SlamKnockback = 55,
	SlamRecoil = 3, -- spin the slammer itself loses, reduced by Balance
	SlamCooldown = 1.0, -- server-side minimum between accepted slams (client cooldown is longer)

	RequestsPerSecond = 8, -- rate limit for battle requests from one player
	LowSpinFraction = 0.25, -- below this the HUD warns and the bey wobbles
	VisualSpinMin = 6, -- cosmetic hub spin (rad/s) at 0 spin and at full spin
	VisualSpinMax = 40,
}

GameConfig.Battle = {
	Countdown = 3,
	Duration = 90, -- then the higher spin share wins
	DrawMargin = 0.02, -- spin shares this close at timeout = draw
	ResultTimeout = 45, -- the result screen closes itself after this
	RingOutRadius = 44.5, -- beyond the rim (42) = out of the stadium
	RingOutBelowY = -10,
	StartRadius = 12, -- where the two beys start, either side of the centre
}

GameConfig.Difficulty = {
	-- Speed: villain top-speed multiplier. Windup: seconds of warning before an attack. Aggression: 0..1 how often it
	-- attacks when in range. Damage: multiplier on its hits. Reward: multiplier on rewards for beating it.
	Easy = { Speed = 0.85, Windup = 1.0, Aggression = 0.45, Damage = 0.8, Reward = 0.8 },
	Normal = { Speed = 0.95, Windup = 0.75, Aggression = 0.7, Damage = 1.0, Reward = 1.0 },
	Hard = { Speed = 1.08, Windup = 0.55, Aggression = 0.95, Damage = 1.15, Reward = 1.5 },
}

GameConfig.Villain = {
	Id = "rook",
	Name = "Rook the Grinder",
	Parts = { Layer = "layer_skyrend", Disc = "disc_bulwarkring", Driver = "driver_spikegrip" }, -- all Uncommon
	Level = 3,
	Difficulty = "Normal",
	-- After this many wins against it, the next rematch uses Hard (shown to the player).
	HardAfterWins = 3,
}

GameConfig.Progression = {
	MaxLevel = 50, -- matches BeyConfig.MaxLevel
	XPCurveBase = 60, -- XP needed for level L is XPCurveBase * (L-1)^1.6 (rounded)
	XPCurvePower = 1.6,
	Rewards = { -- per battle outcome, before the difficulty multiplier
		win = { XP = 40, Shards = 30 },
		loss = { XP = 15, Shards = 8 },
		draw = { XP = 25, Shards = 15 },
	},
	-- The Workshop sells parts for Shards (earned only by playing). This is the deterministic route to the cap:
	-- every rarity up to Legendary can be bought, and level 50 gives the full level multiplier. Ultra Legendary is
	-- never sold for Shards (it is the paid tier, and paid crates are disabled for now).
	Prices = { Common = 20, Uncommon = 60, Rare = 150, Epic = 350, Legendary = 800 },
	RecentBattleMemory = 30, -- battle ids remembered per player to refuse duplicate rewards
	MinLossSecondsForReward = 20, -- a loss pays nothing if the battle lasted less than this (stops ring-out farming)
}

GameConfig.Data = {
	StoreName = "SpinforgePlayers_v1",
	AutosaveInterval = 120,
	LockTimeout = 600, -- a session lock older than this (seconds) is treated as abandoned
	LoadAttempts = 4,
	RetryWait = 2,
}

return GameConfig
]=====])
install('RS', '', 'ModuleScript', 'Net', [=====[
--!nonstrict
-- Net: the game's remotes, in one place. The server creates them (idempotent: safe after a re-install or a
-- script restart); clients wait for them with a time limit and a clear error instead of hanging forever.
--
-- Client -> server
--   Request      RemoteEvent    { action = "rematch" | "leave" | "forfeit" | "exitPractice" | "setting" | "tutorialDone", ... }
--   SlamLanded   RemoteEvent    (no arguments: the server checks the fall it observed itself)
--   Workshop     RemoteFunction { action = "buy" | "equip", part = id } -> { ok, reason, profile }
-- Server -> client
--   BattleEvent  RemoteEvent    { kind = "queued" | "countdown" | "started" | "hit" | "slam" | "finished" | "closed" | "openWorkshop", ... }
--   Knockback    RemoteEvent    Vector3 velocity change for the client-owned bey
--   Profile      RemoteEvent    PlayerData.snapshot
--   Toast        RemoteEvent    string

local Net = {}

Net.FOLDER = "SpinforgeRemotes"
Net.EVENTS = { "Request", "SlamLanded", "BattleEvent", "Knockback", "Profile", "Toast" }
Net.FUNCTIONS = { "Workshop" }

function Net.setup(replicatedStorage)
	local folder = replicatedStorage:FindFirstChild(Net.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FOLDER
		folder.Parent = replicatedStorage
	end
	local remotes = {}
	for _, name in ipairs(Net.EVENTS) do
		local r = folder:FindFirstChild(name)
		if not (r and r:IsA("RemoteEvent")) then
			if r then
				r:Destroy()
			end
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
		remotes[name] = r
	end
	for _, name in ipairs(Net.FUNCTIONS) do
		local r = folder:FindFirstChild(name)
		if not (r and r:IsA("RemoteFunction")) then
			if r then
				r:Destroy()
			end
			r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
		remotes[name] = r
	end
	return remotes
end

-- Client side. Returns the remotes table, or nil + message if the server never created them.
function Net.waitFor(replicatedStorage, timeout)
	local folder = replicatedStorage:WaitForChild(Net.FOLDER, timeout)
	if not folder then
		return nil, "the server scripts did not start (no " .. Net.FOLDER .. "). Re-run the installer and check Output for red errors."
	end
	local remotes = {}
	for _, name in ipairs(Net.EVENTS) do
		remotes[name] = folder:WaitForChild(name, timeout)
		if not remotes[name] then
			return nil, "remote " .. name .. " is missing"
		end
	end
	for _, name in ipairs(Net.FUNCTIONS) do
		remotes[name] = folder:WaitForChild(name, timeout)
		if not remotes[name] then
			return nil, "remote " .. name .. " is missing"
		end
	end
	return remotes
end

return Net
]=====])
install('RS', 'Core', 'ModuleScript', 'BattleCore', [=====[
--!nonstrict
-- BattleCore: one battle's lifecycle and outcome as a pure state machine. The server's BattleService owns it.
--   countdown --(Countdown s)--> active --(stopped / ring-out / timeout / left)--> finished --> cleanup
-- Spin only changes while active. A battle finishes exactly once and its rewards can be claimed exactly once.
-- C = GameConfig.Combat, B = GameConfig.Battle. Tested in tools/tests/battle.test.luau.

local BattleCore = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- sides: array of two { key = string, maxSpin = number, drain = number (spin/s) }
function BattleCore.new(id, sides, B, now)
	assert(#sides == 2, "a battle has two sides")
	local b = {
		id = id,
		state = "countdown",
		stateAt = now,
		activeUntil = nil,
		order = { sides[1].key, sides[2].key },
		sides = {},
		result = nil,
		rewardsClaimed = false,
		B = B,
	}
	for _, s in ipairs(sides) do
		local max = finite(s.maxSpin) and math.max(s.maxSpin, 1) or 100
		b.sides[s.key] = { key = s.key, spin = max, maxSpin = max, drain = finite(s.drain) and math.max(s.drain, 0) or 0, out = false }
	end
	return b
end

local function other(b, key)
	return b.order[1] == key and b.order[2] or b.order[1]
end
BattleCore.other = other

function BattleCore.fraction(b, key)
	local s = b.sides[key]
	return s and s.spin / s.maxSpin or 0
end

local function finish(b, now, winner, reason)
	if b.result then
		return nil -- already finished: never twice
	end
	local outcomes = {}
	for _, key in ipairs(b.order) do
		if winner == nil then
			outcomes[key] = "draw"
		else
			outcomes[key] = key == winner and "win" or "loss"
		end
	end
	b.result = { winner = winner, reason = reason, outcomes = outcomes, endedAt = now }
	b.state = "finished"
	b.stateAt = now
	return { kind = "finished", result = b.result }
end

-- Checks stop / ring-out conditions. Both sides losing in the same step is a draw.
local function checkKnockouts(b, now)
	if b.state ~= "active" then
		return nil
	end
	local a, c = b.sides[b.order[1]], b.sides[b.order[2]]
	local aLost = a.out or a.spin <= 0
	local cLost = c.out or c.spin <= 0
	if aLost and cLost then
		return finish(b, now, nil, "both")
	elseif aLost then
		return finish(b, now, c.key, a.out and "ringout" or "stopped")
	elseif cLost then
		return finish(b, now, a.key, c.out and "ringout" or "stopped")
	end
	return nil
end

-- Advance time. Returns a list of events: { kind = "started" }, { kind = "finished", result }, { kind = "cleanup" }.
function BattleCore.update(b, now, dt)
	local events = {}
	if b.state == "countdown" and now - b.stateAt >= b.B.Countdown then
		b.state = "active"
		b.stateAt = now
		b.activeUntil = now + b.B.Duration
		table.insert(events, { kind = "started" })
	end
	if b.state == "active" then
		dt = finite(dt) and math.clamp(dt, 0, 0.5) or 0
		for _, key in ipairs(b.order) do
			local s = b.sides[key]
			s.spin = math.max(s.spin - s.drain * dt, 0)
		end
		local ev = checkKnockouts(b, now)
		if ev then
			table.insert(events, ev)
		elseif now >= b.activeUntil then
			local fa, fc = BattleCore.fraction(b, b.order[1]), BattleCore.fraction(b, b.order[2])
			local winner = nil
			if math.abs(fa - fc) > b.B.DrawMargin then
				winner = fa > fc and b.order[1] or b.order[2]
			end
			table.insert(events, finish(b, now, winner, "time"))
		end
	end
	if b.state == "finished" and now - b.stateAt >= b.B.ResultTimeout then
		b.state = "cleanup"
		b.stateAt = now
		table.insert(events, { kind = "cleanup" })
	end
	return events
end

-- Apply damage to a side. Ignored unless active; never negative or non-finite. Returns the amount applied.
function BattleCore.damage(b, key, amount)
	local s = b.sides[key]
	if b.state ~= "active" or not s or not finite(amount) or amount <= 0 then
		return 0
	end
	local applied = math.min(amount, s.spin)
	s.spin -= applied
	return applied
end

-- Mark a side as rung out (resolved on the next update, so a double ring-out in one step is a draw).
function BattleCore.ringOut(b, key)
	local s = b.sides[key]
	if b.state == "active" and s then
		s.out = true
	end
end

-- A side quit (left the game, reset, disconnected). The other side wins. No effect once finished.
function BattleCore.leave(b, key, now)
	if not b.sides[key] then
		return nil
	end
	if b.state == "countdown" or b.state == "active" then
		return finish(b, now, other(b, key), "left")
	end
	return nil
end

-- True exactly once, after the battle has a result.
function BattleCore.claimRewards(b)
	if b.result and not b.rewardsClaimed then
		b.rewardsClaimed = true
		return true
	end
	return false
end

-- The player chose Rematch or Leave on the result screen.
function BattleCore.requestCleanup(b, now)
	if b.state == "finished" then
		b.state = "cleanup"
		b.stateAt = now
		return true
	end
	return false
end

return BattleCore
]=====])
install('RS', 'Core', 'ModuleScript', 'CombatCore', [=====[
--!nonstrict
-- CombatCore: spin, damage, knockback, contact de-duplication, ring-outs and request validation as pure functions.
-- Used by the server's BattleService; the server owns all spin values and outcomes. C is GameConfig.Combat.
-- Unit-tested in tools/tests/combat.test.luau (rules only; not how Roblox reports positions or velocities).

local CombatCore = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
CombatCore.finite = finite

local function finiteVector(v)
	return v ~= nil and type(v) ~= "number" and finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function stat(stats, name)
	local v = stats and stats[name]
	return finite(v) and math.max(v :: number, 0) or 0
end

-------------------------------------------------------------------------------- spin

function CombatCore.maxSpin(stats, C)
	return C.BaseSpin + stat(stats, "Stamina") * C.SpinPerStamina
end

function CombatCore.drainPerSecond(stats, C)
	local reduction = math.min(stat(stats, "Stamina") * C.DrainReductionPerStamina, C.MaxDrainReduction)
	return C.BaseDrain * (1 - reduction)
end

-- Cosmetic hub spin speed for a spin fraction (0..1). Purely visual; never feeds back into combat.
function CombatCore.visualSpin(fraction, C)
	fraction = finite(fraction) and math.clamp(fraction, 0, 1) or 0
	return C.VisualSpinMin + (C.VisualSpinMax - C.VisualSpinMin) * fraction
end

-------------------------------------------------------------------------------- hits

-- Geometry of a contact between A and B from server-observed positions and velocities.
-- Returns n (unit vector A->B), closing speed (>= 0), and A's share of the closing speed (0..1).
function CombatCore.contact(posA, velA, posB, velB)
	local d = posB - posA
	local dist = d.Magnitude
	if dist < 1e-4 or not finite(dist) then
		return nil, 0, 0.5
	end
	local n = d / dist
	local aIn = math.max(velA:Dot(n), 0) -- how hard A drives into B
	local bIn = math.max(-velB:Dot(n), 0) -- how hard B drives into A
	local closing = aIn + bIn
	if not finite(closing) then
		return n, 0, 0.5
	end
	local share = closing > 1e-6 and aIn / closing or 0.5
	return n, closing, share
end

-- Damage the defender takes in a body contact. attackerShare is the attacker's part of the closing speed;
-- even a stationary bey deals some damage (0.4 of the base), the one driving in deals up to 1.6x.
function CombatCore.hitDamage(attacker, defender, closing, attackerShare, C)
	if not finite(closing) or closing <= C.MinImpactSpeed then
		return 0
	end
	attackerShare = finite(attackerShare) and math.clamp(attackerShare, 0, 1) or 0.5
	local base = (closing - C.MinImpactSpeed) * C.DamagePerSpeed
	local atk = 1 + stat(attacker, "Attack") * C.AttackScale
	local def = 1 + stat(defender, "Defense") * C.DefenseScale
	local dmg = base * (0.4 + 1.2 * attackerShare) * atk / def
	return math.clamp(dmg, C.MinHitDamage, C.MaxHitDamage)
end

-- Knockback speed (studs/s) the defender receives along the contact normal.
function CombatCore.knockback(attacker, defender, closing, C)
	if not finite(closing) or closing <= C.MinImpactSpeed then
		return 0
	end
	local resist = math.min((stat(defender, "Defense") + stat(defender, "Balance")) * C.KnockbackResistPerPoint, C.MaxKnockbackResist)
	local power = 1 + stat(attacker, "Attack") * C.AttackScale
	return math.clamp(closing * C.KnockbackPerSpeed * power * (1 - resist), 0, C.MaxKnockback)
end

-- Slam damage to a defender `distance` away, from the fall speed the server itself observed.
function CombatCore.slamDamage(attacker, defender, fallSpeed, distance, C)
	if not finite(fallSpeed) or not finite(distance) or fallSpeed < C.SlamMinFallSpeed or distance > C.SlamRadius or distance < 0 then
		return 0
	end
	local falloff = 1 - 0.5 * (distance / C.SlamRadius) -- full at the centre, half at the edge
	local atk = 1 + stat(attacker, "Attack") * C.AttackScale
	local def = 1 + stat(defender, "Defense") * C.DefenseScale
	local dmg = (C.SlamBaseDamage + (fallSpeed - C.SlamMinFallSpeed) * C.SlamDamagePerSpeed) * falloff * atk / def
	return math.clamp(dmg, 0, C.SlamMaxDamage)
end

function CombatCore.slamRecoil(attacker, C)
	return C.SlamRecoil * (1 - math.min(stat(attacker, "Balance") * C.KnockbackResistPerPoint, C.MaxKnockbackResist))
end

-------------------------------------------------------------------------------- contact de-duplication

-- Tracks each pair of beys so continuous contact (grinding against each other) only counts once: a pair must
-- separate past SeparationDistance AND wait HitCooldown before it can score again.
function CombatCore.newContacts()
	return {}
end

local function pairKey(a, b)
	a, b = tostring(a), tostring(b)
	if a < b then
		return a .. "|" .. b
	end
	return b .. "|" .. a
end

-- Returns true when this frame's contact should count as a new hit.
function CombatCore.contactStep(tracker, a, b, distance, now, C)
	local key = pairKey(a, b)
	local s = tracker[key]
	if not s then
		s = { touching = false, lastHit = -math.huge }
		tracker[key] = s
	end
	if not finite(distance) then
		return false
	end
	if distance <= C.ContactDistance then
		if not s.touching and now - s.lastHit >= C.HitCooldown then
			s.touching = true
			s.lastHit = now
			return true
		end
		s.touching = true
		return false
	elseif distance >= C.SeparationDistance then
		s.touching = false
	end
	return false
end

-------------------------------------------------------------------------------- ring-out, fall tracking, validation

function CombatCore.isRingOut(pos, B)
	if not finiteVector(pos) then
		return true
	end
	local flat = math.sqrt(pos.X * pos.X + pos.Z * pos.Z)
	return flat > B.RingOutRadius or pos.Y < B.RingOutBelowY
end

-- Rolling record of the fastest downward speed the SERVER saw for a bey, so slam claims are checked against it.
function CombatCore.newFallTracker()
	return { samples = {} }
end

function CombatCore.recordFall(t, vy, now, window)
	if not finite(vy) then
		return
	end
	table.insert(t.samples, { at = now, down = math.max(-vy, 0) })
	while #t.samples > 0 and now - t.samples[1].at > window do
		table.remove(t.samples, 1)
	end
end

function CombatCore.maxFall(t, now, window)
	local best = 0
	for _, s in ipairs(t.samples) do
		if now - s.at <= window and s.down > best then
			best = s.down
		end
	end
	return best
end

-- Simple per-key rate limiter: at most `perSecond` allowed calls in any rolling second.
function CombatCore.newRateLimiter(perSecond)
	return { perSecond = perSecond, hits = {} }
end

function CombatCore.allow(rl, key, now)
	local list = rl.hits[key]
	if not list then
		list = {}
		rl.hits[key] = list
	end
	while #list > 0 and now - list[1] > 1 do
		table.remove(list, 1)
	end
	if #list >= rl.perSecond then
		return false
	end
	table.insert(list, now)
	return true
end

function CombatCore.forget(rl, key)
	rl.hits[key] = nil
end

return CombatCore
]=====])
install('RS', 'Core', 'ModuleScript', 'MovementCore', [=====[
--!nonstrict
-- MovementCore: the bey's movement rules as pure functions, shared by the player's controller (client) and the
-- villain AI (server). No Roblox services or instances: only Vector3 and numbers, so it is unit-tested outside
-- Roblox (tools/tests/movement.test.luau). Tests prove the rules; they do NOT prove how Roblox physics responds.
--
-- State machines here:
--   Ground state  air <-> ground with hysteresis: grounded the moment a probe hits walkable ground, airborne
--                 only after UngroundDelay seconds without a hit (stops seams between slabs from flickering).
--   Actions       one takeoff boost per takeoff, jumps on a cooldown, slam as an explicit state:
--                 ready -> diving -> (one impact on landing) -> ready. Jump, launch and slam never stack.
--
-- M is BeyConfig.Movement. Times are seconds; `now` is any monotonic clock.

local MovementCore = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
MovementCore.finite = finite

local function finiteVector(v)
	return v ~= nil and finite(v.X) and finite(v.Y) and finite(v.Z)
end
MovementCore.finiteVector = finiteVector

local function clampMagnitude(v, max)
	local m = v.Magnitude
	if m > max and m > 0 then
		return v * (max / m)
	end
	return v
end
MovementCore.clampMagnitude = clampMagnitude

-- Clamp a frame time so a hitch (or a bad value) can't launch the bey across the map.
function MovementCore.safeDt(dt, M)
	if not finite(dt) or dt < 0 then
		return 0
	end
	return math.min(dt, M.MaxDt)
end

-- Replace a non-finite velocity with zero and cap absurd speeds. Returns the vector and whether it was repaired.
function MovementCore.sanitizeVelocity(v, M)
	if not finiteVector(v) then
		return Vector3.zero, true
	end
	if v.Magnitude > M.MaxSpeed then
		return clampMagnitude(v, M.MaxSpeed), true
	end
	return v, false
end

-------------------------------------------------------------------------------- ground state

function MovementCore.newGround()
	return {
		grounded = false,
		lastHitAt = -math.huge,
		groundedSince = -math.huge,
		airborneSince = 0,
		normal = Vector3.yAxis,
		flips = 0, -- ground/air changes, for diagnostics
	}
end

-- hitNormal: the probe's surface normal, or nil if nothing walkable was hit this frame.
-- Returns "landed", "tookoff", "ground" or "air".
function MovementCore.updateGround(g, hitNormal, now, M)
	local walkable = hitNormal ~= nil and finiteVector(hitNormal) and hitNormal.Y > M.MinGroundNormalY
	if walkable then
		g.lastHitAt = now
		g.normal = hitNormal
		if not g.grounded then
			g.grounded = true
			g.groundedSince = now
			g.flips += 1
			return "landed"
		end
		return "ground"
	end
	if g.grounded and now - g.lastHitAt > M.UngroundDelay then
		g.grounded = false
		g.airborneSince = now
		g.flips += 1
		return "tookoff"
	end
	return g.grounded and "ground" or "air"
end

-- A jump leaves the ground immediately (no hysteresis wait) so the jump isn't eaten by the next probe.
function MovementCore.forceAirborne(g, now)
	if g.grounded then
		g.grounded = false
		g.airborneSince = now
		g.flips += 1
	end
	g.lastHitAt = -math.huge
end

-------------------------------------------------------------------------------- actions (jump, launch, slam)

function MovementCore.newActions()
	return {
		slam = "ready", -- "ready" | "diving"
		slamStartedAt = -math.huge,
		slamReadyAt = 0,
		lastJumpAt = -math.huge,
		launchUsed = false, -- a takeoff boost was already given since the last landing
	}
end

-- Right after a jump the probe would still touch the floor we are leaving; ignore it briefly.
function MovementCore.probeSuppressed(a, now, M)
	return now - a.lastJumpAt < M.JumpGroundIgnore
end

function MovementCore.canJump(a, g, now, M)
	return g.grounded and a.slam ~= "diving" and now - a.lastJumpAt >= M.JumpCooldown
end

-- Returns the new velocity after a jump. Call only when canJump is true.
function MovementCore.jump(a, g, vel, tilt, now, M)
	a.lastJumpAt = now
	a.launchUsed = true -- a jump is its own takeoff; no ramp boost on top
	MovementCore.forceAirborne(g, now)
	local up = M.JumpSpeed * (1 + M.JumpTiltBonus * math.max(tilt, 0))
	return Vector3.new(vel.X, up, vel.Z)
end

-- Extra upward speed when leaving a rising surface (a ramp or the stadium lip) nose-up. At most once per takeoff.
function MovementCore.takeoffBoost(a, vel, tilt, M)
	if a.launchUsed or vel.Y <= M.MinLaunchVy then
		return 0
	end
	local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if flat <= M.MinLaunchSpeed then
		return 0
	end
	a.launchUsed = true
	local factor = tilt >= 0 and tilt or tilt * M.LaunchDownFactor
	return math.clamp(flat * M.LaunchFactor * factor, -M.MaxLaunchBoost, M.MaxLaunchBoost)
end

function MovementCore.canSlam(a, g, now, M)
	return not g.grounded and a.slam == "ready" and now >= a.slamReadyAt and now - g.airborneSince >= M.SlamMinAirTime
end

-- Starts a slam. Returns the dive velocity. Call only when canSlam is true.
function MovementCore.startSlam(a, vel, now, M)
	a.slam = "diving"
	a.slamStartedAt = now
	a.slamReadyAt = now + M.SlamCooldown
	return Vector3.new(vel.X * 0.4, -M.SlamSpeed, vel.Z * 0.4)
end

-- Call with the ground event each frame. Returns "impact" exactly once when a dive lands, "expired" if a dive
-- ran too long without landing, else nil. Landing also re-arms the takeoff boost.
function MovementCore.resolveActions(a, groundEvent, now, M)
	if groundEvent == "landed" then
		a.launchUsed = false
		if a.slam == "diving" then
			a.slam = "ready"
			return "impact"
		end
	elseif a.slam == "diving" and now - a.slamStartedAt > M.SlamTimeout then
		a.slam = "ready"
		return "expired"
	end
	return nil
end

-------------------------------------------------------------------------------- velocity

-- One ground frame. vel: current velocity; n: surface normal; wish: desired direction (flat, length 0..1);
-- tilt: -1 nose down .. +1 nose up; speed: the bey's base top speed. Returns the new velocity.
function MovementCore.groundVelocity(vel, n, wish, tilt, speed, dt, M)
	-- The surface holds us: remove velocity going into it. Gravity (applied by the engine) keeps acting along the
	-- surface; steering is a limited push, never a velocity target, so steep slopes pull the bey back down.
	local into = vel:Dot(n)
	if into < 0 then
		vel = vel - n * into
	end
	local traction = math.clamp((n.Y - M.MinGroundNormalY) / (1 - M.MinGroundNormalY), M.MinTraction, 1)
	local lean = math.max(-tilt, 0)
	local brakeLean = math.max(tilt, 0)
	-- Leaning back cuts the drive as well as braking, so nose-up actually stops you even while holding forward.
	local topSpeed = speed * (1 + M.LeanSpeedBonus * lean) * (1 - M.BrakeDriveCut * brakeLean)
	local push = M.Accel * (1 + M.LeanAccelBonus * lean) * (1 - M.BrakeDriveCut * brakeLean) * traction
	local wishMag = math.min(wish.Magnitude, 1)
	local hasInput = wishMag > 0.05

	if hasInput then
		local dir = wish - n * wish:Dot(n)
		if dir.Magnitude > 1e-3 then
			dir = dir.Unit
			local along = vel:Dot(dir)
			if along < topSpeed then
				vel = vel + dir * math.min(push * dt * wishMag, topSpeed - along)
			end
			-- Grip: bleed off sideways drift so turns bite (weakly on steep walls, so you still slide).
			local side = vel - dir * vel:Dot(dir)
			vel = vel - side * math.min(1, M.Grip * traction * dt)
		end
	end

	local decel = M.RollingFriction + (hasInput and 0 or M.Brake * traction) + brakeLean * M.LeanBrake * traction
	local spd = vel.Magnitude
	if spd > 0 then
		vel = vel * (math.max(spd - decel * dt, 0) / spd)
	end
	return vel
end

-- One air frame: weak steering that never adds beyond the faster of (current flat speed, top speed), and tilt
-- shaping the flight (nose up glides, nose down dives). No glide/dive while slamming.
function MovementCore.airVelocity(vel, wish, tilt, speed, slamming, dt, M)
	local flat = Vector3.new(vel.X, 0, vel.Z)
	if wish.Magnitude > 0.05 then
		local cap = math.max(flat.Magnitude, speed)
		flat = clampMagnitude(flat + wish * M.AirAccel * dt, cap)
	end
	local vy = vel.Y
	if not slamming then
		vy = vy + (tilt >= 0 and tilt * M.GlideLift or tilt * M.DiveAssist) * dt
	end
	return Vector3.new(flat.X, vy, flat.Z)
end

-- Top speed from stats.
function MovementCore.topSpeed(stats, M)
	return M.BaseSpeed + (stats.Attack or 0) * M.SpeedPerAttack + (stats.Balance or 0) * M.SpeedPerBalance
end

-------------------------------------------------------------------------------- facing and orientation

-- Which way the nose points (a yaw angle). Follows the travel direction when moving; when nearly still it KEEPS
-- the last facing (no snapping to the camera, so it can't flip back and forth at low speed).
function MovementCore.noseYaw(prevYaw, vel, dt, M)
	local flat = Vector3.new(vel.X, 0, vel.Z)
	if flat.Magnitude <= M.NoseMinSpeed or not finiteVector(flat) then
		return prevYaw
	end
	local target = math.atan2(-flat.X, -flat.Z)
	local diff = (target - prevYaw + math.pi) % (2 * math.pi) - math.pi
	return prevYaw + diff * math.min(1, M.NoseTurnRate * dt)
end

-- Smoothed "up" for the bey: the ground normal when grounded, easing back to world up in the air.
function MovementCore.surfaceUp(prevUp, groundNormal, dt, M)
	local target = groundNormal or Vector3.yAxis
	local rate = groundNormal and M.SurfaceAlignRate or M.AirUprightRate
	local up = prevUp:Lerp(target, 1 - math.exp(-rate * dt))
	if up.Magnitude < 1e-3 or not finiteVector(up) then
		return Vector3.yAxis
	end
	return up.Unit
end

-- Orthonormal frame (right, up, back) for a nose yaw on a surface "up". Use with CFrame.fromMatrix(pos, r, u, b).
function MovementCore.frame(up, yaw)
	local flatNose = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local fwd = flatNose - up * flatNose:Dot(up)
	if fwd.Magnitude < 1e-3 then
		fwd = flatNose
	end
	fwd = fwd.Unit
	local back = -fwd
	return up:Cross(back), up, back
end

-------------------------------------------------------------------------------- recovery

function MovementCore.newStuck()
	return { slowSince = nil }
end

-- True when the bey has been airborne-and-motionless (wedged somewhere) for StuckTime seconds.
function MovementCore.isStuck(s, grounded, vel, now, M)
	if not grounded and vel.Magnitude < 1 then
		s.slowSince = s.slowSince or now
		return now - s.slowSince >= M.StuckTime
	end
	s.slowSince = nil
	return false
end

return MovementCore
]=====])
install('RS', 'Core', 'ModuleScript', 'PlayerData', [=====[
--!nonstrict
-- PlayerData: the versioned save format, migration from older versions, and repair of bad values. Pure.
-- Version 1 fields:
--   Version, XP, Shards, Owned {partId = true}, Equipped {Layer, Disc, Driver}, Record {Wins, Losses, Draws},
--   RecentBattles {battleId...} (refuses duplicate rewards), Settings {CameraShake, ReducedEffects, TutorialDone}
-- A save written by a NEWER version is never migrated or overwritten (migrate returns nil, "newer").

local PlayerData = {}
PlayerData.VERSION = 1

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function count(n)
	return finite(n) and n >= 0 and math.floor(n) or 0
end

-- starter: { Layer = id, Disc = id, Driver = id }
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
		Equipped = { Layer = starter.Layer, Disc = starter.Disc, Driver = starter.Driver },
		Record = { Wins = 0, Losses = 0, Draws = 0 },
		RecentBattles = {},
		Settings = { CameraShake = true, ReducedEffects = false, TutorialDone = false },
	}
end

-- Repair a v1 table in place: unknown parts dropped, starter parts always owned, equipped parts owned and in the
-- right slot (else the starter part), counters non-negative integers, settings booleans.
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
		if type(id) == "string" and owned[id] and parts[id] and parts[id].Slot == slot then
			fixed[slot] = id
		else
			fixed[slot] = starterId
		end
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
		Equipped = { Layer = d.Equipped.Layer, Disc = d.Equipped.Disc, Driver = d.Equipped.Driver },
		Record = { Wins = d.Record.Wins, Losses = d.Record.Losses, Draws = d.Record.Draws },
		Settings = { CameraShake = d.Settings.CameraShake, ReducedEffects = d.Settings.ReducedEffects, TutorialDone = d.Settings.TutorialDone },
		SaveStatus = saveStatus,
	}
end

return PlayerData
]=====])
print('Spinforge installer part 2 of 7 done. Now run part 3.')

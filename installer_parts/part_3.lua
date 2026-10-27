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
install('RS', 'Core', 'ModuleScript', 'LaunchCore', [=====[
--!nonstrict
-- LaunchCore: the skill launch ("3, 2, 1, LET IT RIP!") as pure functions. Tested in tools/tests/launch.test.luau.
--
-- During the countdown a needle sweeps back and forth across a bar (0..1). The player presses once to lock it.
-- Where it stops sets the launch quality q (0..1):
--   green zone   perfect  q = 1
--   yellow edge  good     q = Good .. 1 (closer to green = better)
--   elsewhere    weak     q = Miss
--   no press     weak     q = NoPress
-- q then sets: starting spin (stamina), launch speed off the line, and a short top-speed boost that fades.
-- L is GameConfig.Launch.

local LaunchCore = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Meter for one battle. zoneCenter comes from the server's random number so it differs every battle.
function LaunchCore.newMeter(start, duration, zoneRandom, L)
	zoneRandom = finite(zoneRandom) and math.clamp(zoneRandom, 0, 1) or 0.5
	return {
		start = start,
		finish = start + duration,
		period = L.Period,
		zoneCenter = L.ZoneMin + (L.ZoneMax - L.ZoneMin) * zoneRandom,
		greenHalf = L.GreenHalf,
		yellowHalf = L.YellowHalf,
	}
end

-- Needle position (0..1) at time t: a triangle wave, so it slows into neither end and reverses sharply.
function LaunchCore.needle(meter, t)
	if not finite(t) then
		return 0
	end
	local phase = ((t - meter.start) / meter.period) % 1
	return phase < 0.5 and phase * 2 or (1 - phase) * 2
end

-- Quality and a label for a needle position.
function LaunchCore.quality(meter, pos, L)
	if not finite(pos) then
		return L.Miss, "WEAK"
	end
	local d = math.abs(pos - meter.zoneCenter)
	if d <= meter.greenHalf then
		return 1, "PERFECT"
	elseif d <= meter.yellowHalf then
		local t = (d - meter.greenHalf) / (meter.yellowHalf - meter.greenHalf) -- 0 at green edge, 1 at yellow edge
		return 1 - (1 - L.Good) * t, "GOOD"
	end
	return L.Miss, "WEAK"
end

-- Server-side check of a press. pressT: the client's reading of the shared server clock when it pressed.
-- receivedT: when the server got it. Returns the press time to judge, or nil if it isn't acceptable.
-- A press may arrive up to L.MaxLatency late; it may not claim a time after it arrived, or outside the meter.
function LaunchCore.acceptPress(meter, pressT, receivedT, L)
	if not finite(pressT) or not finite(receivedT) then
		return nil
	end
	if pressT > receivedT + 0.05 or receivedT - pressT > L.MaxLatency then
		return nil
	end
	if pressT < meter.start or pressT > meter.finish + 0.05 then
		return nil
	end
	return pressT
end

-- What a launch quality does. Returns { spinFraction, speed, boost }:
--   spinFraction  share of max spin the bey starts the battle with (stamina)
--   speed         launch speed off the line (studs/s)
--   boost         extra top speed right after launch (0.35 = +35%), fading over L.BoostTime
function LaunchCore.effects(q, L)
	q = finite(q) and math.clamp(q, 0, 1) or 0
	return {
		spinFraction = L.SpinAtWorst + (1 - L.SpinAtWorst) * q,
		speed = L.SpeedAtWorst + (L.SpeedAtBest - L.SpeedAtWorst) * q,
		boost = L.BoostAtBest * q,
	}
end

-- Top-speed multiplier `elapsed` seconds after launch (fades linearly to 1).
function LaunchCore.boostMultiplier(boost, elapsed, L)
	if not finite(boost) or not finite(elapsed) or elapsed < 0 or elapsed >= L.BoostTime then
		return 1
	end
	return 1 + boost * (1 - elapsed / L.BoostTime)
end

-- The villain's launch: around its difficulty's skill, with some noise. rand in 0..1.
function LaunchCore.villainQuality(skill, rand)
	rand = finite(rand) and rand or 0.5
	return math.clamp(skill + (rand - 0.5) * 0.2, 0, 1)
end

return LaunchCore
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
]=====])
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

-- Equip an owned item into its slot. Never during a battle. parts = BeyConfig.Items (parts, spirits, specials).
-- Specials have two slots: `slot` picks "Special1" or "Special2" (default Special1). Equipping the special that is
-- already in the other slot swaps the two.
function Progression.equip(data, partId, parts, inBattle, slot)
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
	if part.Slot == "Special" then
		slot = (slot == "Special2") and "Special2" or "Special1"
		local other = slot == "Special1" and "Special2" or "Special1"
		if data.Equipped[other] == partId then
			data.Equipped[other] = data.Equipped[slot]
		end
		data.Equipped[slot] = partId
		return true
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
install('RS', 'Core', 'ModuleScript', 'SpecialsCore', [=====[
--!nonstrict
-- SpecialsCore: special moves, spirit passives and Awakening for one side of a battle, as pure functions.
-- The server's BattleService owns one state per side and asks it for multipliers when hits land.
--   specials   two slots with cooldowns. dash: the mover bursts forward and the NEXT hit within Window deals
--              DamageMul / KnockbackMul. guard: for Duration, damage taken x(1-Block), knockback x(1-KnockbackBlock).
--              heal: get Heal of max spin back. quake: the server hits the foe if within Radius.
--   spirit     always-on multipliers (Attack, Defense, Speed, Drain) from BeyConfig.Spirits[..].Passive
--   awakening  a meter (passive + damage dealt/taken); when full the side may awaken once: Attack/Defense/Speed up
--              for AwakenDuration.
-- items = BeyConfig.Items, A = GameConfig.Specials. Tested in tools/tests/specials.test.luau.

local SpecialsCore = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- loadout: { Spirit = id, Special1 = id, Special2 = id } (unknown ids are ignored: that slot does nothing).
function SpecialsCore.newSide(loadout, items)
	local function special(id)
		local it = items[id]
		return { id = id, def = (it and it.Slot == "Special") and it or nil, readyAt = math.huge }
	end
	local spirit = items[loadout.Spirit]
	return {
		specials = { special(loadout.Special1), special(loadout.Special2) },
		spirit = (spirit and spirit.Slot == "Spirit") and spirit or nil,
		meter = 0,
		awakenUsed = false,
		awakenedUntil = -math.huge,
		guard = nil, -- { untilT, block, knockbackBlock }
		empower = nil, -- { untilT, damage, knockback }
	}
end

-- Battle started: specials unlock after FirstUseDelay.
function SpecialsCore.start(side, now, A)
	for _, s in ipairs(side.specials) do
		s.readyAt = now + A.FirstUseDelay
	end
end

function SpecialsCore.cooldownLeft(side, index, now)
	local s = side.specials[index]
	if not s then
		return math.huge
	end
	return math.max(s.readyAt - now, 0)
end

function SpecialsCore.canUse(side, index, now)
	local s = side.specials[index]
	if not s or not s.def then
		return false, "unknown"
	end
	if now < s.readyAt then
		return false, "cooldown"
	end
	return true
end

-- Uses special `index`. Returns the special's definition (the caller applies dash/heal/quake), or nil + reason.
-- dash and guard set their timed effect here.
function SpecialsCore.use(side, index, now)
	local ok, reason = SpecialsCore.canUse(side, index, now)
	if not ok then
		return nil, reason
	end
	local s = side.specials[index]
	local def, t = s.def, s.def.Tuning
	s.readyAt = now + t.Cooldown
	if def.Kind == "dash" then
		side.empower = { untilT = now + t.Window, damage = t.DamageMul, knockback = t.KnockbackMul }
	elseif def.Kind == "guard" then
		side.guard = { untilT = now + t.Duration, block = t.Block, knockbackBlock = t.KnockbackBlock }
	end
	return def
end

-------------------------------------------------------------------------------- awakening

function SpecialsCore.isAwakened(side, now)
	return now < side.awakenedUntil
end

-- Adds to the Awakening meter (not while awakened, not after it was used).
function SpecialsCore.charge(side, amount, A)
	if side.awakenUsed or not finite(amount) or amount <= 0 then
		return
	end
	side.meter = math.min(side.meter + amount, A.MeterMax)
end

function SpecialsCore.tick(side, dt, A)
	if finite(dt) and dt > 0 then
		SpecialsCore.charge(side, A.MeterPerSecond * math.min(dt, 0.5), A)
	end
end

function SpecialsCore.meterFraction(side, A)
	return side.awakenUsed and 0 or side.meter / A.MeterMax
end

function SpecialsCore.canAwaken(side, A)
	return not side.awakenUsed and side.meter >= A.MeterMax
end

-- Awakens once per battle when the meter is full. Returns true if it happened.
function SpecialsCore.awaken(side, now, A)
	if not SpecialsCore.canAwaken(side, A) then
		return false
	end
	side.awakenUsed = true
	side.meter = 0
	side.awakenedUntil = now + A.AwakenDuration
	return true
end

-------------------------------------------------------------------------------- multipliers

local function passive(side, key)
	local p = side.spirit and side.spirit.Passive
	local v = p and p[key]
	return finite(v) and v > 0 and v or 1
end

-- Multipliers on damage and knockback this side DEALS. consume = true uses up a dash's empowered hit.
function SpecialsCore.outgoing(side, now, A, consume)
	local dmg = passive(side, "Attack")
	local kb = 1
	if SpecialsCore.isAwakened(side, now) then
		dmg *= A.AwakenAttack
	end
	local e = side.empower
	if e then
		if now <= e.untilT then
			dmg *= e.damage
			kb *= e.knockback
			if consume then
				side.empower = nil
			end
		else
			side.empower = nil
		end
	end
	return dmg, kb
end

-- Multipliers on damage and knockback this side TAKES.
function SpecialsCore.incoming(side, now, A)
	local def = passive(side, "Defense")
	if SpecialsCore.isAwakened(side, now) then
		def *= A.AwakenDefense
	end
	local dmg, kb = 1 / def, 1 / def
	local g = side.guard
	if g then
		if now <= g.untilT then
			dmg *= 1 - g.block
			kb *= 1 - g.knockbackBlock
		else
			side.guard = nil
		end
	end
	return dmg, kb
end

function SpecialsCore.speed(side, now, A)
	local m = passive(side, "Speed")
	if SpecialsCore.isAwakened(side, now) then
		m *= A.AwakenSpeed
	end
	return m
end

function SpecialsCore.drain(side)
	return passive(side, "Drain")
end

-- A compact view for the client HUD.
function SpecialsCore.snapshot(side, now, A)
	local out = { meter = SpecialsCore.meterFraction(side, A), awakened = SpecialsCore.isAwakened(side, now), awakenUsed = side.awakenUsed, specials = {} }
	for i, s in ipairs(side.specials) do
		out.specials[i] = { id = s.id, left = SpecialsCore.cooldownLeft(side, i, now), cooldown = s.def and s.def.Tuning.Cooldown or 0 }
	end
	return out
end

return SpecialsCore
]=====])
print('Spinforge installer part 3 of 9 done. Now run part 4.')

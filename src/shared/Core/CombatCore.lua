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

-- Ring-out with a short grace: a bey must stay outside for B.RingOutGrace seconds (a launch that pokes past the
-- rim and steers back in survives). Falling below the floor counts at once. timers: table kept per battle.
function CombatCore.ringOutStep(timers, key, pos, now, B)
	if not finiteVector(pos) or pos.Y < B.RingOutBelowY then
		return true
	end
	if CombatCore.isRingOut(pos, B) then
		timers[key] = timers[key] or now
		return now - timers[key] >= B.RingOutGrace
	end
	timers[key] = nil
	return false
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

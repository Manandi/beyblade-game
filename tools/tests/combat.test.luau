-- CombatCore rules: spin pools, damage bounds, knockback, contact de-duplication, slams, ring-outs, rate limits.
--@use src/shared/GameConfig.lua GameConfig
--@use src/shared/Core/CombatCore.lua CC

local C, B = GameConfig.Combat, GameConfig.Battle
local weak = { Attack = 2, Defense = 2, Stamina = 2, Balance = 2 }
local strong = { Attack = 22, Defense = 22, Stamina = 22, Balance = 22 }

T.test("spin: Stamina raises the pool and slows the drain (capped)", function()
	T.ok(CC.maxSpin(strong, C) > CC.maxSpin(weak, C))
	T.ok(CC.drainPerSecond(strong, C) < CC.drainPerSecond(weak, C))
	local huge = { Stamina = 1e6 }
	T.near(CC.drainPerSecond(huge, C), C.BaseDrain * (1 - C.MaxDrainReduction), 1e-9)
	T.eq(CC.maxSpin({ Stamina = 0 / 0 }, C), C.BaseSpin, "NaN stat treated as 0")
end)

T.test("damage: zero below the impact threshold, bounded above", function()
	T.eq(CC.hitDamage(weak, weak, C.MinImpactSpeed, 1, C), 0)
	T.eq(CC.hitDamage(weak, weak, 3, 1, C), 0)
	local d = CC.hitDamage(strong, weak, 1e9, 1, C)
	T.eq(d, C.MaxHitDamage)
	T.ok(CC.hitDamage(weak, weak, C.MinImpactSpeed + 0.01, 0, C) >= C.MinHitDamage)
	T.eq(CC.hitDamage(weak, weak, 0 / 0, 1, C), 0, "NaN closing")
	T.eq(CC.hitDamage(weak, weak, math.huge, 1, C), 0, "inf closing")
end)

T.test("damage: Attack raises it, Defense lowers it, the driver deals more", function()
	local base = CC.hitDamage(weak, weak, 30, 0.5, C)
	T.ok(CC.hitDamage(strong, weak, 30, 0.5, C) > base)
	T.ok(CC.hitDamage(weak, strong, 30, 0.5, C) < base)
	T.ok(CC.hitDamage(weak, weak, 30, 1, C) > CC.hitDamage(weak, weak, 30, 0, C))
end)

T.test("contact: closing speed and share from positions and velocities", function()
	local n, closing, share = CC.contact(Vector3.new(0, 0, 0), Vector3.new(20, 0, 0), Vector3.new(4, 0, 0), Vector3.new(0, 0, 0))
	T.near(n.X, 1, 1e-9)
	T.near(closing, 20, 1e-9)
	T.near(share, 1, 1e-9)
	local _, c2, s2 = CC.contact(Vector3.zero, Vector3.new(10, 0, 0), Vector3.new(4, 0, 0), Vector3.new(-10, 0, 0))
	T.near(c2, 20, 1e-9)
	T.near(s2, 0.5, 1e-9)
	local _, c3 = CC.contact(Vector3.zero, Vector3.new(-10, 0, 0), Vector3.new(4, 0, 0), Vector3.zero)
	T.eq(c3, 0, "moving apart is not a hit")
	local n4 = CC.contact(Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero)
	T.eq(n4, nil, "same position")
end)

T.test("contact: continuous grinding counts once until the pair separates", function()
	local tr = CC.newContacts()
	local hits = 0
	for i = 0, 120 do -- two seconds pressed together
		if CC.contactStep(tr, "p", "v", 4.0, i / 60, C) then
			hits += 1
		end
	end
	T.eq(hits, 1)
	-- separate only a little: still the same contact
	CC.contactStep(tr, "p", "v", 5.0, 3, C)
	T.ok(not CC.contactStep(tr, "p", "v", 4.0, 3.1, C), "not separated far enough")
	-- separate properly, come back: a new hit
	CC.contactStep(tr, "p", "v", 6.0, 4, C)
	T.ok(CC.contactStep(tr, "v", "p", 4.0, 4.5, C), "new hit, pair order doesn't matter")
end)

T.test("contact: cooldown blocks rapid bounce hits", function()
	local tr = CC.newContacts()
	T.ok(CC.contactStep(tr, "a", "b", 4, 10, C))
	CC.contactStep(tr, "a", "b", 6, 10.05, C)
	T.ok(not CC.contactStep(tr, "a", "b", 4, 10.1, C), "inside cooldown")
	CC.contactStep(tr, "a", "b", 6, 10.2, C)
	T.ok(CC.contactStep(tr, "a", "b", 4, 10 + C.HitCooldown + 0.01, C))
	T.ok(not CC.contactStep(tr, "a", "b", 0 / 0, 20, C), "NaN distance")
end)

T.test("knockback: bounded, resisted by Defense and Balance", function()
	T.ok(CC.knockback(weak, weak, 30, C) > CC.knockback(weak, strong, 30, C))
	T.eq(CC.knockback(strong, weak, 1e9, C), C.MaxKnockback)
	T.eq(CC.knockback(weak, weak, 2, C), 0)
end)

T.test("slam: needs a real fall, falls off with distance, bounded", function()
	T.eq(CC.slamDamage(weak, weak, C.SlamMinFallSpeed - 1, 0, C), 0, "fall too slow")
	T.eq(CC.slamDamage(weak, weak, 100, C.SlamRadius + 0.1, C), 0, "out of range")
	local near = CC.slamDamage(weak, weak, 100, 0, C)
	local far = CC.slamDamage(weak, weak, 100, C.SlamRadius, C)
	T.ok(near > far and far > 0)
	T.eq(CC.slamDamage(strong, weak, 1e9, 0, C), C.SlamMaxDamage)
	T.eq(CC.slamDamage(weak, weak, 0 / 0, 0, C), 0)
	T.ok(CC.slamRecoil(strong, C) < CC.slamRecoil(weak, C))
end)

T.test("fall tracker: only falls inside the window count", function()
	local t = CC.newFallTracker()
	CC.recordFall(t, -90, 1, C.SlamFallWindow)
	CC.recordFall(t, -10, 1.5, C.SlamFallWindow)
	T.near(CC.maxFall(t, 1.5, C.SlamFallWindow), 90, 1e-9)
	CC.recordFall(t, -5, 3, C.SlamFallWindow)
	T.near(CC.maxFall(t, 3, C.SlamFallWindow), 5, 1e-9)
	CC.recordFall(t, 0 / 0, 3.1, C.SlamFallWindow)
	T.near(CC.maxFall(t, 3.1, C.SlamFallWindow), 5, 1e-9)
end)

T.test("ring-out: outside the radius, below the floor, or invalid", function()
	T.ok(not CC.isRingOut(Vector3.new(10, 3, 10), B))
	T.ok(CC.isRingOut(Vector3.new(B.RingOutRadius + 1, 3, 0), B))
	T.ok(CC.isRingOut(Vector3.new(0, B.RingOutBelowY - 1, 0), B))
	T.ok(CC.isRingOut(Vector3.new(0 / 0, 0, 0), B))
end)

T.test("ring-out grace: brief excursions past the rim survive; staying out or falling doesn't", function()
	local timers = {}
	local out = Vector3.new(B.RingOutRadius + 2, 20, 0)
	local inside = Vector3.new(10, 3, 0)
	T.ok(not CC.ringOutStep(timers, "p", out, 0, B), "just crossed")
	T.ok(not CC.ringOutStep(timers, "p", inside, B.RingOutGrace * 0.5, B), "came back")
	T.ok(not CC.ringOutStep(timers, "p", out, 1, B), "crossed again: timer restarted")
	T.ok(CC.ringOutStep(timers, "p", out, 1 + B.RingOutGrace + 0.01, B), "stayed out")
	T.ok(CC.ringOutStep({}, "q", Vector3.new(0, B.RingOutBelowY - 1, 0), 0, B), "fell below: at once")
	T.ok(CC.ringOutStep({}, "q", Vector3.new(0 / 0, 0, 0), 0, B), "invalid position")
end)

T.test("rate limiter: per key, rolling one-second window", function()
	local rl = CC.newRateLimiter(3)
	T.ok(CC.allow(rl, "p", 0) and CC.allow(rl, "p", 0.1) and CC.allow(rl, "p", 0.2))
	T.ok(not CC.allow(rl, "p", 0.3))
	T.ok(CC.allow(rl, "q", 0.3), "other key")
	T.ok(CC.allow(rl, "p", 1.2), "window rolled")
end)

T.test("visual spin follows the fraction and clamps", function()
	T.eq(CC.visualSpin(0, C), C.VisualSpinMin)
	T.eq(CC.visualSpin(1, C), C.VisualSpinMax)
	T.eq(CC.visualSpin(5, C), C.VisualSpinMax)
	T.eq(CC.visualSpin(0 / 0, C), C.VisualSpinMin)
end)

T.done()

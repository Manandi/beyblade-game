-- SpecialsCore: cooldowns, dash empowerment (one hit), guard, spirit passives, Awakening meter (once per battle),
-- plus BattleCore.heal. Rules only; how the specials look and feel in Roblox is untested here.
--@use src/shared/BeyConfig.lua BeyConfig
--@use src/shared/GameConfig.lua GameConfig
--@use src/shared/Core/SpecialsCore.lua SC
--@use src/shared/Core/BattleCore.lua BC

local A, items = GameConfig.Specials, BeyConfig.Items
local function near(a, b, msg)
	T.ok(math.abs(a - b) < 1e-9, (msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a))
end

local function side(loadout)
	local s = SC.newSide(loadout or BeyConfig.StarterLoadout, items)
	SC.start(s, 0, A)
	return s
end

T.test("specials: locked until FirstUseDelay, then cooldown after use", function()
	local s = SC.newSide(BeyConfig.StarterLoadout, items)
	T.eq(select(2, SC.canUse(s, 1, 0)), "cooldown", "not started yet")
	SC.start(s, 10, A)
	T.eq(select(2, SC.canUse(s, 1, 10 + A.FirstUseDelay - 0.01)), "cooldown")
	local now = 10 + A.FirstUseDelay
	local def = SC.use(s, 1, now)
	T.eq(def.Id, BeyConfig.StarterLoadout.Special1)
	T.eq(select(2, SC.use(s, 1, now + 1)), "cooldown")
	T.ok(SC.canUse(s, 2, now + 1), "the other slot has its own cooldown")
	T.ok(SC.canUse(s, 1, now + def.Tuning.Cooldown))
	T.eq(select(2, SC.canUse(s, 3, now)), "unknown")
end)

T.test("dash: boosts exactly one hit inside its window", function()
	local s = side({ Spirit = "missing", Special1 = "special_cometdrive", Special2 = "special_ironshell" })
	local t = BeyConfig.Specials.special_cometdrive.Tuning
	local now = A.FirstUseDelay
	near((SC.outgoing(s, now, A, false)), 1, "no spirit = no passive")
	SC.use(s, 1, now)
	local dmg, kb = SC.outgoing(s, now + 0.5, A, true)
	near(dmg, t.DamageMul)
	near(kb, t.KnockbackMul)
	near((SC.outgoing(s, now + 0.6, A, true)), 1, "consumed by the first hit")
	SC.use(s, 1, now + t.Cooldown)
	near((SC.outgoing(s, now + t.Cooldown + t.Window + 0.1, A, true)), 1, "expired window")
end)

T.test("guard: less damage and knockback for its duration only", function()
	local s = side({ Spirit = "missing", Special1 = "special_cometdrive", Special2 = "special_ironshell" })
	local t = BeyConfig.Specials.special_ironshell.Tuning
	local now = A.FirstUseDelay
	SC.use(s, 2, now)
	local dmg, kb = SC.incoming(s, now + 1, A)
	near(dmg, 1 - t.Block)
	near(kb, 1 - t.KnockbackBlock)
	near((SC.incoming(s, now + t.Duration + 0.01, A)), 1)
end)

T.test("spirit passives apply all the time", function()
	local s = side({ Spirit = "spirit_sunmane", Special1 = "special_cometdrive", Special2 = "special_ironshell" })
	local p = BeyConfig.Spirits.spirit_sunmane.Passive
	near((SC.outgoing(s, 5, A, false)), p.Attack)
	near((SC.incoming(s, 5, A)), 1 / p.Defense)
	local roc = side({ Spirit = "spirit_stormroc", Special1 = "special_cometdrive", Special2 = "special_ironshell" })
	near(SC.speed(roc, 5, A), BeyConfig.Spirits.spirit_stormroc.Passive.Speed)
	near(SC.drain(side({ Spirit = "spirit_thornstag" })), BeyConfig.Spirits.spirit_thornstag.Passive.Drain)
end)

T.test("awakening: fills, awakens once, boosts for its duration, then stays used", function()
	local s = side({ Spirit = "missing", Special1 = "special_cometdrive", Special2 = "special_ironshell" })
	T.ok(not SC.awaken(s, 0, A), "empty meter")
	SC.tick(s, 0.25, A)
	near(s.meter, A.MeterPerSecond * 0.25)
	SC.charge(s, 0 / 0, A)
	SC.charge(s, -5, A)
	near(s.meter, A.MeterPerSecond * 0.25, "bad charges ignored")
	SC.charge(s, 1e9, A)
	near(s.meter, A.MeterMax, "capped")
	T.ok(SC.canAwaken(s, A))
	T.ok(SC.awaken(s, 20, A))
	T.ok(SC.isAwakened(s, 20 + A.AwakenDuration - 0.01))
	near((SC.outgoing(s, 21, A, false)), A.AwakenAttack)
	near((SC.incoming(s, 21, A)), 1 / A.AwakenDefense)
	near(SC.speed(s, 21, A), A.AwakenSpeed)
	T.ok(not SC.isAwakened(s, 20 + A.AwakenDuration))
	SC.charge(s, 1e9, A)
	T.ok(not SC.awaken(s, 40, A), "only once per battle")
	near(SC.meterFraction(s, A), 0)
end)

T.test("snapshot: cooldowns and meter for the HUD", function()
	local s = side()
	local snap = SC.snapshot(s, 0, A)
	T.eq(#snap.specials, 2)
	near(snap.specials[1].left, A.FirstUseDelay)
	T.eq(snap.awakened, false)
end)

T.test("BattleCore.heal: only while active, capped at max, not when stopped", function()
	local B = GameConfig.Battle
	local b = BC.new("h", { { key = "player", maxSpin = 100, drain = 0 }, { key = "villain", maxSpin = 100, drain = 0 } }, B, 0)
	T.eq(BC.heal(b, "player", 10), 0, "countdown")
	BC.update(b, B.Countdown, 0)
	BC.damage(b, "player", 30)
	T.eq(BC.heal(b, "player", 50), 30, "capped at max")
	T.eq(BC.heal(b, "player", 0 / 0), 0)
	BC.setDrain(b, "player", 0.5)
	T.eq(b.sides.player.drain, 0.5)
end)

T.done()

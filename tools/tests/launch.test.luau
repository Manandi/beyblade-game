-- LaunchCore: the 3-2-1 skill launch meter, press validation, and what quality does.
--@use src/shared/GameConfig.lua GameConfig
--@use src/shared/Core/LaunchCore.lua LC

local L = GameConfig.Launch

T.test("needle sweeps 0 -> 1 -> 0 each period and stays in range", function()
	local m = LC.newMeter(10, 3, 0.5, L)
	T.near(LC.needle(m, 10), 0, 1e-9)
	T.near(LC.needle(m, 10 + L.Period / 2), 1, 1e-9)
	T.near(LC.needle(m, 10 + L.Period), 0, 1e-9)
	for i = 0, 300 do
		local p = LC.needle(m, 10 + i * 0.01)
		T.ok(p >= 0 and p <= 1)
	end
	T.eq(LC.needle(m, 0 / 0), 0)
end)

T.test("green zone moves with the battle's random number, inside its range", function()
	local a, b = LC.newMeter(0, 3, 0, L), LC.newMeter(0, 3, 1, L)
	T.near(a.zoneCenter, L.ZoneMin, 1e-9)
	T.near(b.zoneCenter, L.ZoneMax, 1e-9)
	T.ok(LC.newMeter(0, 3, 0 / 0, L).zoneCenter >= L.ZoneMin)
end)

T.test("quality: green perfect, yellow good (better nearer green), else weak", function()
	local m = LC.newMeter(0, 3, 0.5, L)
	local c = m.zoneCenter
	T.eq(LC.quality(m, c, L), 1)
	T.eq(select(2, LC.quality(m, c + m.greenHalf * 0.9, L)), "PERFECT")
	local near = LC.quality(m, c + m.greenHalf + 0.01, L)
	local far = LC.quality(m, c + m.yellowHalf - 0.01, L)
	T.ok(near > far and far >= L.Good, "yellow ramps")
	T.eq(select(2, LC.quality(m, c + m.yellowHalf + 0.01, L)), "WEAK")
	T.eq(LC.quality(m, c + 0.5, L), L.Miss)
	T.eq(LC.quality(m, 0 / 0, L), L.Miss)
end)

T.test("press validation: late arrivals ok within latency, no future or stale stamps", function()
	local m = LC.newMeter(100, 3, 0.5, L)
	T.eq(LC.acceptPress(m, 101.5, 101.7, L), 101.5)
	T.eq(LC.acceptPress(m, 101.5, 101.5 + L.MaxLatency + 0.01, L), nil, "too stale")
	T.eq(LC.acceptPress(m, 102, 101.5, L), nil, "claims a time after it arrived")
	T.eq(LC.acceptPress(m, 99, 99.1, L), nil, "before the meter started")
	T.eq(LC.acceptPress(m, 104, 104.1, L), nil, "after it ended")
	T.eq(LC.acceptPress(m, 0 / 0, 101, L), nil)
end)

T.test("effects: a better launch starts with more spin, goes faster, boosts more", function()
	local bad, good = LC.effects(L.NoPress, L), LC.effects(1, L)
	T.ok(good.spinFraction > bad.spinFraction and good.speed > bad.speed and good.boost > bad.boost)
	T.near(good.spinFraction, 1, 1e-9)
	T.near(LC.effects(0, L).spinFraction, L.SpinAtWorst, 1e-9)
	T.near(LC.effects(5, L).speed, L.SpeedAtBest, 1e-9, "clamped")
	T.near(LC.effects(0 / 0, L).speed, L.SpeedAtWorst, 1e-9)
end)

T.test("boost fades linearly to nothing", function()
	T.near(LC.boostMultiplier(0.3, 0, L), 1.3, 1e-9)
	T.near(LC.boostMultiplier(0.3, L.BoostTime / 2, L), 1.15, 1e-9)
	T.eq(LC.boostMultiplier(0.3, L.BoostTime, L), 1)
	T.eq(LC.boostMultiplier(0.3, -1, L), 1)
	T.eq(LC.boostMultiplier(0 / 0, 1, L), 1)
end)

T.test("villain launch skill stays near its difficulty, within 0..1", function()
	T.near(LC.villainQuality(0.72, 0.5), 0.72, 1e-9)
	T.ok(LC.villainQuality(0.92, 1) <= 1)
	T.ok(LC.villainQuality(0.5, 0) >= 0.39)
	T.ok(LC.villainQuality(0.5, 0 / 0) == 0.5)
end)

T.done()

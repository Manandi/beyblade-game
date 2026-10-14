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

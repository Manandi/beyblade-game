-- MovementCore rules: ground hysteresis, one boost per takeoff, slam state, velocity maths, recovery.
-- These test the RULES. They cannot show how Roblox physics will respond to the velocities.
--@use src/shared/BeyConfig.lua BeyConfig
--@use src/shared/Core/MovementCore.lua MC

local M = BeyConfig.Movement
local UP = Vector3.yAxis
local FLAT_STATS = { Attack = 0, Defense = 0, Stamina = 0, Balance = 0 }

T.test("ground: lands at once, leaves only after the unground delay", function()
	local g = MC.newGround()
	T.eq(MC.updateGround(g, UP, 0, M), "landed")
	T.eq(MC.updateGround(g, UP, 0.016, M), "ground")
	-- a one-frame gap (a seam) does not take off
	T.eq(MC.updateGround(g, nil, 0.032, M), "ground")
	T.eq(MC.updateGround(g, UP, 0.048, M), "ground")
	-- a long gap does
	T.eq(MC.updateGround(g, nil, 0.06, M), "ground")
	T.eq(MC.updateGround(g, nil, 0.048 + M.UngroundDelay + 0.001, M), "tookoff")
	T.eq(MC.updateGround(g, nil, 0.5, M), "air")
end)

T.test("ground: seam flicker at 60 fps never changes state", function()
	local g = MC.newGround()
	MC.updateGround(g, UP, 0, M)
	local flips = g.flips
	local t = 0
	for i = 1, 600 do
		t += 1 / 60
		MC.updateGround(g, (i % 3 == 0) and nil or UP, t, M) -- every third probe misses
	end
	T.eq(g.flips, flips, "flips")
	T.ok(g.grounded)
end)

T.test("ground: steep walls and bad normals are not ground", function()
	local g = MC.newGround()
	T.eq(MC.updateGround(g, Vector3.new(0.95, 0.31, 0), 0, M), "air")
	T.eq(MC.updateGround(g, Vector3.new(0 / 0, 1, 0), 0.1, M), "air")
end)

T.test("takeoff boost: once per takeoff, re-armed by landing", function()
	local a = MC.newActions()
	local vel = Vector3.new(40, 20, 0)
	local b1 = MC.takeoffBoost(a, vel, 1, M)
	T.ok(b1 > 0, "first boost")
	T.eq(MC.takeoffBoost(a, vel, 1, M), 0, "second boost in the same flight")
	MC.resolveActions(a, "landed", 1, M)
	T.ok(MC.takeoffBoost(a, vel, 1, M) > 0, "boost after landing")
end)

T.test("takeoff boost: repeated landing signals while grounded don't re-arm", function()
	local a, g = MC.newActions(), MC.newGround()
	local ev = MC.updateGround(g, UP, 0, M)
	MC.resolveActions(a, ev, 0, M)
	MC.takeoffBoost(a, Vector3.new(40, 20, 0), 1, M)
	for i = 1, 10 do
		ev = MC.updateGround(g, UP, i * 0.01, M) -- "ground", not "landed"
		MC.resolveActions(a, ev, i * 0.01, M)
	end
	T.eq(MC.takeoffBoost(a, Vector3.new(40, 20, 0), 1, M), 0)
end)

T.test("takeoff boost: none walking off a ledge, none when slow, capped", function()
	local a = MC.newActions()
	T.eq(MC.takeoffBoost(a, Vector3.new(40, 0, 0), 1, M), 0, "flat ledge")
	T.eq(MC.takeoffBoost(a, Vector3.new(2, 20, 0), 1, M), 0, "slow")
	local big = MC.takeoffBoost(a, Vector3.new(5000, 50, 0), 1, M)
	T.ok(big <= M.MaxLaunchBoost, "capped")
end)

T.test("jump: blocked mid-air, on cooldown, and during a slam; no boost after", function()
	local a, g = MC.newActions(), MC.newGround()
	MC.updateGround(g, UP, 0, M)
	T.ok(MC.canJump(a, g, 1, M))
	local v = MC.jump(a, g, Vector3.zero, 0, 1, M)
	T.near(v.Y, M.JumpSpeed, 1e-9)
	T.ok(not g.grounded, "airborne after jump")
	T.ok(not MC.canJump(a, g, 1.01, M), "mid-air")
	MC.updateGround(g, UP, 1.05, M) -- lands quickly
	T.ok(not MC.canJump(a, g, 1.05, M), "cooldown")
	T.eq(MC.takeoffBoost(a, Vector3.new(40, 20, 0), 1, M), 0, "jump used the takeoff")
	a.slam = "diving"
	T.ok(not MC.canJump(a, g, 5, M), "while diving")
end)

T.test("jump: probe is ignored right after a jump", function()
	local a, g = MC.newActions(), MC.newGround()
	MC.updateGround(g, UP, 0, M)
	MC.jump(a, g, Vector3.zero, 0, 1, M)
	T.ok(MC.probeSuppressed(a, 1.05, M))
	T.ok(not MC.probeSuppressed(a, 1 + M.JumpGroundIgnore + 0.01, M))
end)

T.test("slam: needs air time, one impact per dive, cooldown", function()
	local a, g = MC.newActions(), MC.newGround()
	MC.updateGround(g, UP, 0, M)
	T.ok(not MC.canSlam(a, g, 0.5, M), "grounded")
	MC.forceAirborne(g, 1)
	T.ok(not MC.canSlam(a, g, 1.01, M), "too soon after takeoff")
	T.ok(MC.canSlam(a, g, 1 + M.SlamMinAirTime + 0.01, M))
	local v = MC.startSlam(a, Vector3.new(10, 5, 0), 1.2, M)
	T.near(v.Y, -M.SlamSpeed, 1e-9)
	T.ok(not MC.canSlam(a, g, 1.25, M), "already diving")
	-- landing: exactly one impact even if the landing is reported several times
	local impacts = 0
	for i = 1, 5 do
		local ev = MC.updateGround(g, UP, 1.3 + i * 0.01, M)
		if MC.resolveActions(a, ev, 1.3 + i * 0.01, M) == "impact" then
			impacts += 1
		end
	end
	T.eq(impacts, 1)
	-- bounce: take off and land again -> no second impact
	MC.forceAirborne(g, 1.5)
	local ev = MC.updateGround(g, UP, 1.6, M)
	T.eq(MC.resolveActions(a, ev, 1.6, M), nil)
	-- cooldown
	MC.forceAirborne(g, 1.7)
	T.ok(not MC.canSlam(a, g, 1.2 + M.SlamCooldown - 0.05, M), "cooldown")
	T.ok(MC.canSlam(a, g, 1.2 + M.SlamCooldown + 0.05, M), "ready again")
end)

T.test("slam: a dive that never lands expires", function()
	local a, g = MC.newActions(), MC.newGround()
	MC.forceAirborne(g, 0)
	MC.startSlam(a, Vector3.zero, 1, M)
	T.eq(MC.resolveActions(a, "air", 1 + M.SlamTimeout + 0.1, M), "expired")
	T.eq(a.slam, "ready")
end)

T.test("velocity: flat ground reaches top speed and stops when released", function()
	local v = Vector3.zero
	local speed = MC.topSpeed(FLAT_STATS, M)
	for _ = 1, 600 do
		v = MC.groundVelocity(v, UP, Vector3.new(1, 0, 0), 0, speed, 1 / 60, M)
	end
	T.near(v.Magnitude, speed, speed * 0.1, "top speed")
	for _ = 1, 300 do
		v = MC.groundVelocity(v, UP, Vector3.zero, 0, speed, 1 / 60, M)
	end
	T.near(v.Magnitude, 0, 0.01, "stopped")
end)

T.test("velocity: leaning in is faster, leaning back brakes", function()
	local speed = MC.topSpeed(FLAT_STATS, M)
	local function run(tilt)
		local v = Vector3.zero
		for _ = 1, 600 do
			v = MC.groundVelocity(v, UP, Vector3.new(0, 0, -1), tilt, speed, 1 / 60, M)
		end
		return v.Magnitude
	end
	T.ok(run(-1) > run(0) * 1.3, "lean faster")
	T.ok(run(1) < run(0) * 0.8, "brake slower")
end)

T.test("velocity: a 45-degree wall pulls you back down (with engine gravity)", function()
	-- Simulate the engine's gravity along the slope ourselves; check net motion is downhill while pushing uphill.
	local slope = math.rad(45)
	local uphill = Vector3.new(0, math.sin(slope), -math.cos(slope)) -- wall rising toward -Z
	local n = Vector3.new(0, math.cos(slope), math.sin(slope)) -- its normal leans back toward +Z
	T.near(uphill:Dot(n), 0, 1e-9, "test geometry")
	local g = Vector3.new(0, -M.Gravity, 0)
	local v = Vector3.zero
	local speed = MC.topSpeed(FLAT_STATS, M)
	for _ = 1, 120 do
		v = v + g * (1 / 60)
		v = MC.groundVelocity(v, n, Vector3.new(0, 0, -1), 0, speed, 1 / 60, M)
	end
	T.ok(v:Dot(uphill) < 0, "sliding downhill: " .. tostring(v:Dot(uphill)))
end)

T.test("velocity: a gentle 12-degree ring can still be climbed", function()
	local slope = math.rad(12)
	local uphill = Vector3.new(0, math.sin(slope), -math.cos(slope))
	local n = Vector3.new(0, math.cos(slope), math.sin(slope))
	local g = Vector3.new(0, -M.Gravity, 0)
	local v = Vector3.zero
	local speed = MC.topSpeed(FLAT_STATS, M)
	for _ = 1, 120 do
		v = v + g * (1 / 60)
		v = MC.groundVelocity(v, n, Vector3.new(0, 0, -1), 0, speed, 1 / 60, M)
	end
	T.ok(v:Dot(uphill) > 5, "climbing: " .. tostring(v:Dot(uphill)))
end)

T.test("velocity: holding forward with the nose fully up comes to a near stop", function()
	local speed = MC.topSpeed(FLAT_STATS, M)
	local v = Vector3.new(0, 0, -speed)
	for _ = 1, 180 do
		v = MC.groundVelocity(v, UP, Vector3.new(0, 0, -1), 1, speed, 1 / 60, M)
	end
	T.ok(v.Magnitude < speed * 0.2, "speed " .. tostring(v.Magnitude))
end)

T.test("velocity: variable timesteps end in similar places", function()
	local speed = MC.topSpeed(FLAT_STATS, M)
	local function run(dt)
		local v, t = Vector3.zero, 0
		while t < 2 do
			v = MC.groundVelocity(v, UP, Vector3.new(1, 0, 0), -0.5, speed, dt, M)
			t += dt
		end
		return v.Magnitude
	end
	local a, b = run(1 / 30), run(1 / 240)
	T.near(a, b, speed * 0.05, "30 vs 240 fps")
end)

T.test("velocity: zero input, zero velocity stays still and finite", function()
	local v = MC.groundVelocity(Vector3.zero, UP, Vector3.zero, 0, 40, 1 / 60, M)
	T.eq(v.Magnitude, 0)
	local a = MC.airVelocity(Vector3.zero, Vector3.zero, 0, 40, false, 1 / 60, M)
	T.ok(T.finite(a.X) and T.finite(a.Y) and T.finite(a.Z))
end)

T.test("velocity: air steering can't exceed the faster of current and top speed", function()
	local v = Vector3.new(10, 0, 0)
	for _ = 1, 600 do
		v = MC.airVelocity(v, Vector3.new(1, 0, 0), 0, 40, false, 1 / 60, M)
		v = Vector3.new(v.X, 0, v.Z)
	end
	T.ok(v.Magnitude <= 40 + 1e-6)
	local fast = MC.airVelocity(Vector3.new(90, 0, 0), Vector3.new(1, 0, 0), 0, 40, false, 1 / 60, M)
	T.ok(Vector3.new(fast.X, 0, fast.Z).Magnitude <= 90 + 1e-6, "keeps but doesn't add to launch speed")
end)

T.test("sanitize: NaN/inf become zero, extreme speed is capped, dt is clamped", function()
	local v, fixed = MC.sanitizeVelocity(Vector3.new(0 / 0, 1, 1), M)
	T.ok(fixed and v.Magnitude == 0)
	v, fixed = MC.sanitizeVelocity(Vector3.new(math.huge, 0, 0), M)
	T.ok(fixed and v.Magnitude == 0)
	v, fixed = MC.sanitizeVelocity(Vector3.new(10000, 0, 0), M)
	T.ok(fixed)
	T.near(v.Magnitude, M.MaxSpeed, 1e-6)
	T.eq(MC.safeDt(0 / 0, M), 0)
	T.eq(MC.safeDt(-1, M), 0)
	T.eq(MC.safeDt(5, M), M.MaxDt)
end)

T.test("facing: keeps its direction when nearly still (no flip)", function()
	local yaw = 1.0
	yaw = MC.noseYaw(yaw, Vector3.new(0.5, 0, -0.1), 1 / 60, M)
	T.eq(yaw, 1.0)
	yaw = MC.noseYaw(yaw, Vector3.new(-0.2, 0, 0.3), 1 / 60, M)
	T.eq(yaw, 1.0)
	yaw = MC.noseYaw(yaw, Vector3.new(0 / 0, 0, 0), 1 / 60, M)
	T.eq(yaw, 1.0)
end)

T.test("facing: turns toward travel when moving, the short way round", function()
	local yaw = math.pi - 0.1
	local target = -math.pi + 0.1 -- just across the wrap
	local v = Vector3.new(-math.sin(target), 0, -math.cos(target)) * 30
	local y2 = MC.noseYaw(yaw, v, 1 / 60, M)
	T.ok(y2 > yaw, "goes forward across the wrap, not all the way round")
end)

T.test("orientation: frame is orthonormal on slopes and flat", function()
	for _, up in ipairs({ UP, Vector3.new(0, 0.7071, 0.7071) }) do
		local r, u, b = MC.frame(up.Unit, 0.7)
		T.near(r.Magnitude, 1, 1e-6)
		T.near(b.Magnitude, 1, 1e-6)
		T.near(r:Dot(u), 0, 1e-6)
		T.near(u:Dot(b), 0, 1e-6)
		T.near(r:Dot(b), 0, 1e-6)
	end
	local up = MC.surfaceUp(Vector3.new(0 / 0, 0, 0), nil, 1 / 60, M)
	T.eq(up, Vector3.yAxis, "bad input recovers to upright")
end)

T.test("stuck: airborne and motionless for StuckTime", function()
	local s = MC.newStuck()
	T.ok(not MC.isStuck(s, false, Vector3.zero, 0, M))
	T.ok(not MC.isStuck(s, false, Vector3.zero, M.StuckTime - 0.1, M))
	T.ok(MC.isStuck(s, false, Vector3.zero, M.StuckTime + 0.1, M))
	T.ok(not MC.isStuck(s, true, Vector3.zero, M.StuckTime + 0.2, M), "grounded resets")
end)

T.done()

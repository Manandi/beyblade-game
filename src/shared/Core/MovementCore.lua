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

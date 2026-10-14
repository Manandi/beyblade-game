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

-- The launch sets how much spin a side starts with (fraction of max). Only during the countdown, only once.
function BattleCore.setStartSpin(b, key, fraction)
	local s = b.sides[key]
	if b.state ~= "countdown" or not s or s.launched or not finite(fraction) then
		return false
	end
	s.spin = s.maxSpin * math.clamp(fraction, 0.05, 1)
	s.launched = true
	return true
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

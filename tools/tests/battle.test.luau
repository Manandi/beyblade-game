-- BattleCore lifecycle: countdown, knockouts, ring-outs, timeout, draws, leaving, one finish, one reward claim.
--@use src/shared/GameConfig.lua GameConfig
--@use src/shared/Core/BattleCore.lua BC

local B = GameConfig.Battle

local function newBattle(now)
	return BC.new("b1", { { key = "player", maxSpin = 100, drain = 1 }, { key = "villain", maxSpin = 120, drain = 1 } }, B, now or 0)
end

local function run(b, from, to, step)
	local events = {}
	local t = from
	while t < to do
		t += step
		for _, e in ipairs(BC.update(b, t, step)) do
			table.insert(events, e)
		end
	end
	return events, t
end

T.test("countdown: no spin changes or damage before it starts", function()
	local b = newBattle(0)
	T.eq(BC.damage(b, "player", 50), 0)
	BC.update(b, 1, 1)
	T.eq(b.sides.player.spin, 100)
	local events = run(b, 1, B.Countdown + 0.1, 0.1)
	T.eq(b.state, "active")
	T.eq(events[1].kind, "started")
end)

T.test("stopped: spin hitting zero ends it, the other side wins", function()
	local b = newBattle(0)
	run(b, 0, B.Countdown + 0.1, 0.1)
	BC.damage(b, "villain", 1e9)
	local ev = BC.update(b, B.Countdown + 0.2, 0.1)
	T.eq(ev[1].kind, "finished")
	T.eq(b.result.winner, "player")
	T.eq(b.result.reason, "stopped")
	T.eq(b.result.outcomes.villain, "loss")
end)

T.test("damage: never negative, never NaN, never above remaining spin", function()
	local b = newBattle(0)
	run(b, 0, B.Countdown + 0.1, 0.1)
	local before = b.sides.player.spin
	T.eq(BC.damage(b, "player", -10), 0)
	T.eq(BC.damage(b, "player", 0 / 0), 0)
	T.eq(BC.damage(b, "player", math.huge), 0)
	T.eq(BC.damage(b, "nobody", 10), 0)
	T.eq(b.sides.player.spin, before, "nothing applied")
end)

T.test("damage: applied amount is capped by remaining spin", function()
	local b = newBattle(0)
	run(b, 0, B.Countdown + 0.1, 0.1)
	local before = b.sides.player.spin
	local applied = BC.damage(b, "player", 1000)
	T.near(applied, before, 1e-9)
	T.eq(b.sides.player.spin, 0)
end)

T.test("ring-out: the side that left the stadium loses; both at once is a draw", function()
	local b = newBattle(0)
	run(b, 0, B.Countdown + 0.1, 0.1)
	BC.ringOut(b, "player")
	BC.update(b, B.Countdown + 0.2, 0.1)
	T.eq(b.result.winner, "villain")
	T.eq(b.result.reason, "ringout")

	local d = newBattle(0)
	run(d, 0, B.Countdown + 0.1, 0.1)
	BC.ringOut(d, "player")
	BC.ringOut(d, "villain")
	BC.update(d, B.Countdown + 0.2, 0.1)
	T.eq(d.result.winner, nil)
	T.eq(d.result.outcomes.player, "draw")
end)

T.test("simultaneous stop is a draw", function()
	local b = newBattle(0)
	run(b, 0, B.Countdown + 0.1, 0.1)
	BC.damage(b, "player", 1e9)
	BC.damage(b, "villain", 1e9)
	BC.update(b, B.Countdown + 0.2, 0.1)
	T.eq(b.result.reason, "both")
	T.eq(b.result.winner, nil)
end)

T.test("timeout: higher spin share wins; near-equal shares draw", function()
	local b = BC.new("t", { { key = "player", maxSpin = 100, drain = 0 }, { key = "villain", maxSpin = 120, drain = 0 } }, B, 0)
	run(b, 0, B.Countdown + 0.1, 0.1)
	BC.damage(b, "villain", 60) -- villain at 60/120 = 0.5 share
	run(b, B.Countdown + 0.1, B.Countdown + B.Duration + 0.5, 0.5)
	T.eq(b.result.reason, "time")
	T.eq(b.result.winner, "player")

	local d = BC.new("d", { { key = "a", maxSpin = 100, drain = 0 }, { key = "b", maxSpin = 100, drain = 0 } }, B, 0)
	run(d, 0, B.Countdown + B.Duration + 1, 0.5)
	T.eq(d.result.winner, nil)
	T.eq(d.result.reason, "time")
end)

T.test("finish happens once; later events change nothing", function()
	local b = newBattle(0)
	run(b, 0, B.Countdown + 0.1, 0.1)
	BC.damage(b, "villain", 1e9)
	local t = B.Countdown + 0.1
	local finishes = 0
	for _, e in ipairs(BC.update(b, t, 0.1)) do
		if e.kind == "finished" then
			finishes += 1
		end
	end
	for _ = 1, 50 do
		t += 0.1
		BC.ringOut(b, "player")
		BC.damage(b, "player", 1e9)
		for _, e in ipairs(BC.update(b, t, 0.1)) do
			if e.kind == "finished" then
				finishes += 1
			end
		end
		BC.leave(b, "player", t)
	end
	T.eq(finishes, 1)
	T.eq(b.result.winner, "player", "result unchanged")
end)

T.test("leaving: during countdown or active the other side wins; ignored after finish", function()
	local b = newBattle(0)
	local ev = BC.leave(b, "player", 1)
	T.eq(ev.kind, "finished")
	T.eq(b.result.winner, "villain")
	T.eq(b.result.reason, "left")
	T.eq(BC.leave(b, "villain", 2), nil)
	T.eq(BC.leave(newBattle(0), "nobody", 1), nil)
end)

T.test("rewards: claimable exactly once, only after a result", function()
	local b = newBattle(0)
	T.ok(not BC.claimRewards(b), "no result yet")
	BC.leave(b, "villain", 1)
	T.ok(BC.claimRewards(b))
	T.ok(not BC.claimRewards(b))
	T.ok(not BC.claimRewards(b))
end)

T.test("cleanup: by request after finish, or automatically after the timeout", function()
	local b = newBattle(0)
	T.ok(not BC.requestCleanup(b, 1), "can't cleanup a live battle")
	BC.leave(b, "villain", 1)
	T.ok(BC.requestCleanup(b, 2))
	T.eq(b.state, "cleanup")

	local c = newBattle(0)
	BC.leave(c, "villain", 1)
	local events = run(c, 1, 1 + B.ResultTimeout + 0.5, 0.5)
	T.eq(c.state, "cleanup")
	T.eq(events[#events].kind, "cleanup")
end)

T.test("drain: spin falls while active and never below zero; bad dt is ignored", function()
	local b = BC.new("x", { { key = "a", maxSpin = 10, drain = 5 }, { key = "b", maxSpin = 100, drain = 0 } }, B, 0)
	run(b, 0, B.Countdown + 0.1, 0.1)
	local before = b.sides.a.spin
	BC.update(b, B.Countdown + 0.2, 0 / 0)
	T.eq(b.sides.a.spin, before, "NaN dt")
	run(b, B.Countdown + 0.2, B.Countdown + 5, 0.1)
	T.eq(b.sides.a.spin, 0)
	T.eq(b.result.winner, "b")
end)

T.done()

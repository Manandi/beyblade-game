-- Progression, PlayerData and SessionStore: rewards once, Workshop, equipping, save format, migration,
-- failed loads, retries, session locks. A mock store stands in for Roblox DataStores (live behaviour unverified).
--@use src/shared/BeyConfig.lua BeyConfig
--@use src/shared/GameConfig.lua GameConfig
--@use src/shared/Core/Progression.lua PR
--@use src/shared/Core/PlayerData.lua PD
--@use src/shared/Core/SessionStore.lua SS

local P, D = GameConfig.Progression, GameConfig.Difficulty
local parts, starter = BeyConfig.Items, BeyConfig.StarterLoadout

local function fresh()
	return PD.new(starter)
end

-------------------------------------------------------------------------------- progression

T.test("levels: monotonic curve, level 1 at 0 XP, capped at MaxLevel", function()
	T.eq(PR.levelFromXP(0, P), 1)
	T.eq(PR.levelFromXP(0 / 0, P), 1)
	local prev = 0
	for l = 2, P.MaxLevel do
		local need = PR.xpForLevel(l, P)
		T.ok(need > prev, "curve rises at " .. l)
		T.eq(PR.levelFromXP(need, P), l)
		T.eq(PR.levelFromXP(need - 1, P), l - 1)
		prev = need
	end
	T.eq(PR.levelFromXP(1e12, P), P.MaxLevel)
end)

T.test("rewards: win > draw > loss, difficulty scales them", function()
	local w, d, l = PR.battleReward("win", "Normal", P, D), PR.battleReward("draw", "Normal", P, D), PR.battleReward("loss", "Normal", P, D)
	T.ok(w.XP > d.XP and d.XP > l.XP)
	T.ok(PR.battleReward("win", "Hard", P, D).Shards > w.Shards)
	T.eq(PR.battleReward("bogus", "Normal", P, D), nil)
end)

T.test("rewards: granted once per battle id, even if reported repeatedly", function()
	local data = fresh()
	local r = PR.battleReward("win", "Normal", P, D)
	T.ok(PR.grantBattleReward(data, "battle-1", r, P))
	for _ = 1, 5 do
		local ok, why = PR.grantBattleReward(data, "battle-1", r, P)
		T.ok(not ok and why == "duplicate")
	end
	T.eq(data.XP, r.XP)
	T.eq(data.Shards, r.Shards)
	T.eq(data.Record.Wins, 1)
end)

T.test("rewards: invalid amounts and ids are refused", function()
	local data = fresh()
	T.ok(not PR.grantBattleReward(data, "", { XP = 1, Shards = 1 }, P))
	T.ok(not PR.grantBattleReward(data, "x", { XP = -5, Shards = 1 }, P))
	T.ok(not PR.grantBattleReward(data, "y", { XP = 0 / 0, Shards = 1 }, P))
	T.ok(not PR.grantBattleReward(data, nil, { XP = 1, Shards = 1 }, P))
	T.eq(data.XP, 0)
end)

T.test("rewards: battle-id memory is bounded", function()
	local data = fresh()
	for i = 1, P.RecentBattleMemory + 20 do
		PR.grantBattleReward(data, "b" .. i, { Outcome = "loss", XP = 1, Shards = 1 }, P)
	end
	T.eq(#data.RecentBattles, P.RecentBattleMemory)
end)

T.test("workshop: buy with Shards, not twice, not Ultra, not mid-battle", function()
	local data = fresh()
	T.eq(select(2, PR.buy(data, "layer_skyrend", parts, P, false)), "cant_afford")
	data.Shards = 1000
	T.ok(PR.buy(data, "layer_skyrend", parts, P, false))
	T.eq(data.Shards, 1000 - P.Prices.Uncommon)
	T.eq(select(2, PR.buy(data, "layer_skyrend", parts, P, false)), "owned")
	T.eq(select(2, PR.buy(data, "layer_eclipsesovereign", parts, P, false)), "not_for_sale")
	T.eq(select(2, PR.buy(data, "layer_ironvane", parts, P, true)), "in_battle")
	T.eq(select(2, PR.buy(data, "nope", parts, P, false)), "unknown_part")
end)

T.test("workshop: every non-Ultra part has a price; a Legendary set is reachable with Shards", function()
	local legendaryCost = 0
	for id, part in pairs(parts) do
		local price = PR.price(id, parts, P)
		if part.Rarity == "UltraLegendary" then
			T.eq(price, nil, id)
		else
			T.ok(price and price > 0, id)
		end
	end
	for _, slot in ipairs(BeyConfig.Slots) do
		legendaryCost += P.Prices.Legendary
	end
	local winsNeeded = math.ceil(legendaryCost / PR.battleReward("win", "Normal", P, D).Shards)
	print("  Shards for a full Legendary set: " .. legendaryCost .. " (~" .. winsNeeded .. " Normal wins)")
	T.ok(winsNeeded < 200)
end)

T.test("equip: only owned parts, slot follows the part, never mid-battle", function()
	local data = fresh()
	T.eq(select(2, PR.equip(data, "layer_skyrend", parts, false)), "not_owned")
	data.Owned.layer_skyrend = true
	T.eq(select(2, PR.equip(data, "layer_skyrend", parts, true)), "in_battle")
	T.ok(PR.equip(data, "layer_skyrend", parts, false))
	T.eq(data.Equipped.Layer, "layer_skyrend")
	T.eq(data.Equipped.Disc, starter.Disc, "other slots unchanged")
	T.eq(select(2, PR.equip(data, "missing", parts, false)), "unknown_part")
end)

-------------------------------------------------------------------------------- save format

T.test("migrate: new player, v0 dev save, corrupt and newer saves", function()
	local d = PD.migrate(nil, starter, parts)
	T.eq(d.Version, PD.VERSION)
	T.ok(d.Owned[starter.Layer])
	local v0 = PD.migrate({ xp = 120, shards = 40, parts = { "layer_skyrend" }, equipped = { Layer = "layer_skyrend" } }, starter, parts)
	T.eq(v0.XP, 120)
	T.eq(v0.Shards, 40)
	T.eq(v0.Equipped.Layer, "layer_skyrend")
	T.eq(select(2, PD.migrate("garbage", starter, parts)), "corrupt")
	T.eq(select(2, PD.migrate({ Version = PD.VERSION + 1 }, starter, parts)), "newer")
end)

T.test("repair: bad values fixed, equipped parts must be owned and in the right slot", function()
	local d = PD.migrate({
		Version = 1,
		XP = -50,
		Shards = 0 / 0,
		Owned = { layer_skyrend = true, fake_part = true, disc_tinplate = "yes" },
		Equipped = { Layer = "disc_tinplate", Disc = "disc_titanballast", Driver = 12 },
		Record = { Wins = 3.7 },
		RecentBattles = { "a", 5, "b" },
		Settings = { CameraShake = false, ReducedEffects = "x" },
	}, starter, parts)
	T.eq(d.XP, 0)
	T.eq(d.Shards, 0)
	T.ok(d.Owned.layer_skyrend and not d.Owned.fake_part and not d.Owned.disc_tinplate)
	T.eq(d.Equipped.Layer, starter.Layer, "a disc in the layer slot")
	T.eq(d.Equipped.Disc, starter.Disc, "unowned part")
	T.eq(d.Equipped.Driver, starter.Driver, "not a string")
	T.eq(d.Record.Wins, 3)
	T.eq(#d.RecentBattles, 2)
	T.eq(d.Settings.CameraShake, false)
	T.eq(d.Settings.ReducedEffects, false)
end)

T.test("loadout: spirits and specials equip by kind; specials swap between their two slots", function()
	local data = fresh()
	T.eq(data.Equipped.Spirit, starter.Spirit)
	T.eq(data.Equipped.Special1, starter.Special1)
	T.eq(data.Equipped.Special2, starter.Special2)
	-- equipping the special that sits in the other slot swaps them
	T.ok(PR.equip(data, starter.Special2, parts, false, "Special1"))
	T.eq(data.Equipped.Special1, starter.Special2)
	T.eq(data.Equipped.Special2, starter.Special1)
	-- a bought special goes into the slot asked for
	data.Shards = 10000
	T.ok(PR.buy(data, "special_quakestomp", parts, P, false))
	T.ok(PR.equip(data, "special_quakestomp", parts, false, "Special2"))
	T.eq(data.Equipped.Special2, "special_quakestomp")
	T.ok(data.Equipped.Special1 ~= data.Equipped.Special2)
	-- spirits go to Spirit; a special can't land in a part slot
	T.ok(PR.buy(data, "spirit_stormroc", parts, P, false))
	T.ok(PR.equip(data, "spirit_stormroc", parts, false))
	T.eq(data.Equipped.Spirit, "spirit_stormroc")
	T.eq(data.Equipped.Layer, starter.Layer)
	T.eq(PR.price("spirit_sunmane", parts, P), P.Prices.Legendary)
end)

T.test("migrate: a v1 save keeps its parts and gains the starter spirit and specials", function()
	local v1 = { Version = 1, XP = 500, Shards = 77, Owned = { layer_skyrend = true }, Equipped = { Layer = "layer_skyrend", Disc = starter.Disc, Driver = starter.Driver }, Record = { Wins = 4, Losses = 1, Draws = 0 }, RecentBattles = {}, Settings = {} }
	local d = PD.migrate(v1, starter, parts)
	T.eq(d.Version, PD.VERSION)
	T.eq(d.Equipped.Layer, "layer_skyrend")
	T.eq(d.Equipped.Spirit, starter.Spirit)
	T.eq(d.Equipped.Special1, starter.Special1)
	T.eq(d.Equipped.Special2, starter.Special2)
	T.ok(d.Owned[starter.Spirit] and d.Owned[starter.Special1] and d.Owned[starter.Special2])
	T.eq(d.Shards, 77)
	-- duplicated specials and wrong-kind items are repaired
	local bad = PD.migrate({ Version = 2, Owned = { special_quakestomp = true }, Equipped = { Special1 = "special_quakestomp", Special2 = "special_quakestomp", Spirit = "layer_cinderlash" } }, starter, parts)
	T.ok(bad.Equipped.Special1 ~= bad.Equipped.Special2)
	T.eq(bad.Equipped.Spirit, starter.Spirit)
	local snap = PD.snapshot(d, 3, "ok")
	T.eq(snap.Equipped.Special2, starter.Special2)
end)

-------------------------------------------------------------------------------- sessions (mock store)

local function deepcopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepcopy(x)
	end
	return out
end

local function mockStore()
	local s = { data = {}, failNext = 0, calls = 0 }
	function s:update(key, transform)
		self.calls += 1
		if self.failNext > 0 then
			self.failNext -= 1
			return false, "simulated DataStore error"
		end
		local new = transform(deepcopy(self.data[key]))
		if new == nil then
			return true, nil
		end
		self.data[key] = deepcopy(new)
		return true, deepcopy(new)
	end
	return s
end

local clock = 1000
local function opts()
	return {
		attempts = GameConfig.Data.LoadAttempts,
		retryWait = 0,
		wait = function() clock += GameConfig.Data.RetryWait end,
		now = function() return clock end,
		lockTimeout = GameConfig.Data.LockTimeout,
		migrate = function(raw) return PD.migrate(raw, starter, parts) end,
	}
end

T.test("session: save/load round trip keeps progress", function()
	local store = mockStore()
	local status, data = SS.load(store, "u1", "jobA", opts())
	T.eq(status, "ok")
	data.XP = 77
	data.Owned.layer_skyrend = true
	T.eq(SS.save(store, "u1", "jobA", data, opts(), true), "ok")
	local s2, d2 = SS.load(store, "u1", "jobB", opts())
	T.eq(s2, "ok")
	T.eq(d2.XP, 77)
	T.ok(d2.Owned.layer_skyrend)
end)

T.test("session: transient errors are retried", function()
	local store = mockStore()
	store.failNext = GameConfig.Data.LoadAttempts - 1
	local status = SS.load(store, "u2", "jobA", opts())
	T.eq(status, "ok")
end)

T.test("session: a failed load returns no profile and leaves stored data untouched", function()
	local store = mockStore()
	local _, data = SS.load(store, "u3", "jobA", opts())
	data.XP = 500
	SS.save(store, "u3", "jobA", data, opts(), true)
	local snapshot = deepcopy(store.data.u3)
	store.failNext = 99
	local status, d = SS.load(store, "u3", "jobB", opts())
	T.eq(status, "failed")
	T.eq(d, nil)
	store.failNext = 0
	T.eq(store.data.u3.Data.XP, snapshot.Data.XP, "real save untouched")
end)

T.test("session: a save from a newer version is never overwritten", function()
	local store = mockStore()
	store.data.u4 = { Data = { Version = PD.VERSION + 1, XP = 999 } }
	local status, d, why = SS.load(store, "u4", "jobA", opts())
	T.eq(status, "unsupported")
	T.eq(why, "newer")
	T.eq(store.data.u4.Data.XP, 999)
end)

T.test("session: a second server can't load while the first holds the lock", function()
	local store = mockStore()
	local _, a = SS.load(store, "u5", "jobA", opts())
	local status = SS.load(store, "u5", "jobB", opts())
	T.eq(status, "locked")
	-- A keeps saving fine
	a.XP = 10
	T.eq(SS.save(store, "u5", "jobA", a, opts(), false), "ok")
	-- A releases on leave; B can load and sees A's save
	T.eq(SS.save(store, "u5", "jobA", a, opts(), true), "ok")
	local s2, b = SS.load(store, "u5", "jobB", opts())
	T.eq(s2, "ok")
	T.eq(b.XP, 10)
end)

T.test("session: a stale lock is taken over; the old server's late save is refused", function()
	local store = mockStore()
	local _, a = SS.load(store, "u6", "jobA", opts())
	clock += GameConfig.Data.LockTimeout + 1 -- jobA crashed / went silent
	local s2, b = SS.load(store, "u6", "jobB", opts())
	T.eq(s2, "ok")
	b.XP = 300
	SS.save(store, "u6", "jobB", b, opts(), false)
	a.XP = 5
	T.eq(SS.save(store, "u6", "jobA", a, opts(), false), "lost_lock")
	T.eq(store.data.u6.Data.XP, 300, "B's data kept")
end)

T.test("session: save errors are reported, not hidden", function()
	local store = mockStore()
	local _, a = SS.load(store, "u7", "jobA", opts())
	store.failNext = 1
	T.eq(SS.save(store, "u7", "jobA", a, opts(), false), "error")
end)

T.done()

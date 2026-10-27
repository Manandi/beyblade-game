--!nonstrict
-- SpecialsCore: special moves, spirit passives and Awakening for one side of a battle, as pure functions.
-- The server's BattleService owns one state per side and asks it for multipliers when hits land.
--   specials   two slots with cooldowns. dash: the mover bursts forward and the NEXT hit within Window deals
--              DamageMul / KnockbackMul. guard: for Duration, damage taken x(1-Block), knockback x(1-KnockbackBlock).
--              heal: get Heal of max spin back. quake: the server hits the foe if within Radius.
--   spirit     always-on multipliers (Attack, Defense, Speed, Drain) from BeyConfig.Spirits[..].Passive
--   awakening  a meter (passive + damage dealt/taken); when full the side may awaken once: Attack/Defense/Speed up
--              for AwakenDuration.
-- items = BeyConfig.Items, A = GameConfig.Specials. Tested in tools/tests/specials.test.luau.

local SpecialsCore = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- loadout: { Spirit = id, Special1 = id, Special2 = id } (unknown ids are ignored: that slot does nothing).
function SpecialsCore.newSide(loadout, items)
	local function special(id)
		local it = items[id]
		return { id = id, def = (it and it.Slot == "Special") and it or nil, readyAt = math.huge }
	end
	local spirit = items[loadout.Spirit]
	return {
		specials = { special(loadout.Special1), special(loadout.Special2) },
		spirit = (spirit and spirit.Slot == "Spirit") and spirit or nil,
		meter = 0,
		awakenUsed = false,
		awakenedUntil = -math.huge,
		guard = nil, -- { untilT, block, knockbackBlock }
		empower = nil, -- { untilT, damage, knockback }
	}
end

-- Battle started: specials unlock after FirstUseDelay.
function SpecialsCore.start(side, now, A)
	for _, s in ipairs(side.specials) do
		s.readyAt = now + A.FirstUseDelay
	end
end

function SpecialsCore.cooldownLeft(side, index, now)
	local s = side.specials[index]
	if not s then
		return math.huge
	end
	return math.max(s.readyAt - now, 0)
end

function SpecialsCore.canUse(side, index, now)
	local s = side.specials[index]
	if not s or not s.def then
		return false, "unknown"
	end
	if now < s.readyAt then
		return false, "cooldown"
	end
	return true
end

-- Uses special `index`. Returns the special's definition (the caller applies dash/heal/quake), or nil + reason.
-- dash and guard set their timed effect here.
function SpecialsCore.use(side, index, now)
	local ok, reason = SpecialsCore.canUse(side, index, now)
	if not ok then
		return nil, reason
	end
	local s = side.specials[index]
	local def, t = s.def, s.def.Tuning
	s.readyAt = now + t.Cooldown
	if def.Kind == "dash" then
		side.empower = { untilT = now + t.Window, damage = t.DamageMul, knockback = t.KnockbackMul }
	elseif def.Kind == "guard" then
		side.guard = { untilT = now + t.Duration, block = t.Block, knockbackBlock = t.KnockbackBlock }
	end
	return def
end

-------------------------------------------------------------------------------- awakening

function SpecialsCore.isAwakened(side, now)
	return now < side.awakenedUntil
end

-- Adds to the Awakening meter (not while awakened, not after it was used).
function SpecialsCore.charge(side, amount, A)
	if side.awakenUsed or not finite(amount) or amount <= 0 then
		return
	end
	side.meter = math.min(side.meter + amount, A.MeterMax)
end

function SpecialsCore.tick(side, dt, A)
	if finite(dt) and dt > 0 then
		SpecialsCore.charge(side, A.MeterPerSecond * math.min(dt, 0.5), A)
	end
end

function SpecialsCore.meterFraction(side, A)
	return side.awakenUsed and 0 or side.meter / A.MeterMax
end

function SpecialsCore.canAwaken(side, A)
	return not side.awakenUsed and side.meter >= A.MeterMax
end

-- Awakens once per battle when the meter is full. Returns true if it happened.
function SpecialsCore.awaken(side, now, A)
	if not SpecialsCore.canAwaken(side, A) then
		return false
	end
	side.awakenUsed = true
	side.meter = 0
	side.awakenedUntil = now + A.AwakenDuration
	return true
end

-------------------------------------------------------------------------------- multipliers

local function passive(side, key)
	local p = side.spirit and side.spirit.Passive
	local v = p and p[key]
	return finite(v) and v > 0 and v or 1
end

-- Multipliers on damage and knockback this side DEALS. consume = true uses up a dash's empowered hit.
function SpecialsCore.outgoing(side, now, A, consume)
	local dmg = passive(side, "Attack")
	local kb = 1
	if SpecialsCore.isAwakened(side, now) then
		dmg *= A.AwakenAttack
	end
	local e = side.empower
	if e then
		if now <= e.untilT then
			dmg *= e.damage
			kb *= e.knockback
			if consume then
				side.empower = nil
			end
		else
			side.empower = nil
		end
	end
	return dmg, kb
end

-- Multipliers on damage and knockback this side TAKES.
function SpecialsCore.incoming(side, now, A)
	local def = passive(side, "Defense")
	if SpecialsCore.isAwakened(side, now) then
		def *= A.AwakenDefense
	end
	local dmg, kb = 1 / def, 1 / def
	local g = side.guard
	if g then
		if now <= g.untilT then
			dmg *= 1 - g.block
			kb *= 1 - g.knockbackBlock
		else
			side.guard = nil
		end
	end
	return dmg, kb
end

function SpecialsCore.speed(side, now, A)
	local m = passive(side, "Speed")
	if SpecialsCore.isAwakened(side, now) then
		m *= A.AwakenSpeed
	end
	return m
end

function SpecialsCore.drain(side)
	return passive(side, "Drain")
end

-- A compact view for the client HUD.
function SpecialsCore.snapshot(side, now, A)
	local out = { meter = SpecialsCore.meterFraction(side, A), awakened = SpecialsCore.isAwakened(side, now), awakenUsed = side.awakenUsed, specials = {} }
	for i, s in ipairs(side.specials) do
		out.specials[i] = { id = s.id, left = SpecialsCore.cooldownLeft(side, i, now), cooldown = s.def and s.def.Tuning.Cooldown or 0 }
	end
	return out
end

return SpecialsCore

-- Spinforge installer. Paste into Studio's Command Bar (View > Command Bar, or the code pane with a Run button)
-- and run it while NOT in Play mode. Safe to run again: it only replaces the Spinforge folders.
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local roots = { RS = RS, SSS = SSS, SPS = SPS }
local function folderAt(rootKey, path)
	local node = roots[rootKey]:FindFirstChild("Spinforge")
	if not node then
		node = Instance.new("Folder")
		node.Name = "Spinforge"
		node.Parent = roots[rootKey]
	end
	for name in string.gmatch(path, "[^/]+") do
		local nextNode = node:FindFirstChild(name)
		if not nextNode then
			nextNode = Instance.new("Folder")
			nextNode.Name = name
			nextNode.Parent = node
		end
		node = nextNode
	end
	return node
end
local function install(rootKey, path, class, name, source)
	local parent = folderAt(rootKey, path)
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local s = Instance.new(class)
	s.Name = name
	s.Source = source
	s.Parent = parent
end
-- Fresh start for project-owned objects only.
for _, key in ipairs({ "RS", "SSS", "SPS" }) do
	local old = roots[key]:FindFirstChild("Spinforge")
	if old then old:Destroy() end
end
-- Scripts from earlier (flat) builds of this project.
for _, n in ipairs({ "BeyConfig", "BeyDesigns", "BeyVisuals", "BeyMeshData" }) do
	local o = RS:FindFirstChild(n)
	if o and o:IsA("ModuleScript") then o:Destroy() end
end
for _, n in ipairs({ "StadiumBuilder", "BeySpawner" }) do
	local o = SSS:FindFirstChild(n)
	if o and o:IsA("Script") then o:Destroy() end
end
local oldCtl = SPS:FindFirstChild("BeyController")
if oldCtl and oldCtl:IsA("LocalScript") then oldCtl:Destroy() end
-- Imported bey meshes live here and are kept between installs.
if not RS:FindFirstChild("BeyMeshes") then
	local f = Instance.new("Folder")
	f.Name = "BeyMeshes"
	f.Parent = RS
end
install('RS', '', 'ModuleScript', 'BeyConfig', [=====[
--!nonstrict
-- BeyConfig: every number the game balances on lives here.
-- Parts are ORIGINAL placeholders (names, stats, rarity). They do not copy any licensed product.
-- Box odds are integers in basis points (1 bp = 0.01%) so they sum to exactly 10000 with no float error.
-- The shop UI must read its displayed odds from GetDisplayOdds(), never from a separate copy.

local BeyConfig = {}

BeyConfig.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "UltraLegendary" }
BeyConfig.RarityColors = {
	Common = Color3.fromRGB(190, 190, 190),
	Uncommon = Color3.fromRGB(110, 210, 110),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(180, 90, 255),
	Legendary = Color3.fromRGB(255, 170, 40),
	UltraLegendary = Color3.fromRGB(255, 70, 90),
}
BeyConfig.Slots = { "Layer", "Disc", "Driver" } -- attack ring, weight disc, tip
BeyConfig.StatNames = { "Attack", "Defense", "Stamina", "Balance" }

BeyConfig.MaxLevel = 50
BeyConfig.UltraMultiplier = 1.10 -- Ultra Legendary is 10% above the best part you can grind

-- Total stat points a part carries, per rarity. Legendary is the grindable maximum.
BeyConfig.PartBudget = { Common = 8, Uncommon = 12, Rare = 17, Epic = 23, Legendary = 30 }
BeyConfig.PartBudget.UltraLegendary = math.floor(BeyConfig.PartBudget.Legendary * BeyConfig.UltraMultiplier + 0.5)

-- Split `budget` points over four weights with no rounding loss (largest remainder).
local function distribute(budget, w)
	local sum = 0
	for _, v in ipairs(w) do
		sum = sum + v
	end
	local out, rem, used = {}, {}, 0
	for i, v in ipairs(w) do
		local exact = budget * v / sum
		out[i] = math.floor(exact)
		rem[i] = { i = i, frac = exact - out[i] }
		used = used + out[i]
	end
	table.sort(rem, function(a, b)
		if a.frac ~= b.frac then
			return a.frac > b.frac
		end
		return a.i < b.i
	end)
	for k = 1, budget - used do
		out[rem[k].i] = out[rem[k].i] + 1
	end
	return { Attack = out[1], Defense = out[2], Stamina = out[3], Balance = out[4] }
end

-- { id, display name, slot, rarity, weights = Attack, Defense, Stamina, Balance }
local PART_ROWS = {
	-- Layers: attack-leaning
	{ "layer_cinderlash", "Cinderlash", "Layer", "Common", { 6, 2, 1, 1 } },
	{ "layer_thornwhirl", "Thornwhirl", "Layer", "Common", { 5, 1, 2, 2 } },
	{ "layer_skyrend", "Skyrend", "Layer", "Uncommon", { 6, 1, 1, 2 } },
	{ "layer_mossback", "Mossback", "Layer", "Uncommon", { 3, 5, 1, 1 } },
	{ "layer_ironvane", "Ironvane", "Layer", "Rare", { 5, 3, 1, 1 } },
	{ "layer_stormcleat", "Stormcleat", "Layer", "Rare", { 6, 1, 1, 2 } },
	{ "layer_voidpetal", "Voidpetal", "Layer", "Epic", { 6, 2, 1, 1 } },
	{ "layer_sunhammer", "Sunhammer", "Layer", "Epic", { 5, 3, 1, 1 } },
	{ "layer_solsticerend", "Solstice Rend", "Layer", "Legendary", { 7, 2, 1, 1 } },
	{ "layer_tempesthalo", "Tempest Halo", "Layer", "Legendary", { 6, 1, 1, 3 } },
	{ "layer_eclipsesovereign", "Eclipse Sovereign", "Layer", "UltraLegendary", { 7, 2, 1, 1 } },
	-- Discs: defense-leaning
	{ "disc_pebbledisc", "Pebbledisc", "Disc", "Common", { 1, 6, 1, 2 } },
	{ "disc_tinplate", "Tinplate", "Disc", "Common", { 2, 5, 2, 1 } },
	{ "disc_bulwarkring", "Bulwark Ring", "Disc", "Uncommon", { 1, 7, 1, 1 } },
	{ "disc_driftweight", "Driftweight", "Disc", "Uncommon", { 2, 4, 2, 2 } },
	{ "disc_granitecore", "Granite Core", "Disc", "Rare", { 1, 7, 1, 1 } },
	{ "disc_hollowanvil", "Hollow Anvil", "Disc", "Rare", { 3, 5, 1, 1 } },
	{ "disc_titanballast", "Titan Ballast", "Disc", "Epic", { 1, 7, 1, 1 } },
	{ "disc_stillwater", "Stillwater", "Disc", "Epic", { 1, 4, 3, 2 } },
	{ "disc_worldrootmass", "Worldroot Mass", "Disc", "Legendary", { 1, 7, 1, 1 } },
	{ "disc_astralflywheel", "Astral Flywheel", "Disc", "Legendary", { 2, 4, 2, 2 } },
	{ "disc_singularityplate", "Singularity Plate", "Disc", "UltraLegendary", { 1, 6, 2, 1 } },
	-- Drivers: stamina / balance-leaning
	{ "driver_flatnub", "Flat Nub", "Driver", "Common", { 1, 1, 5, 3 } },
	{ "driver_roundpeg", "Round Peg", "Driver", "Common", { 1, 1, 3, 5 } },
	{ "driver_glidepin", "Glide Pin", "Driver", "Uncommon", { 1, 1, 6, 2 } },
	{ "driver_spikegrip", "Spike Grip", "Driver", "Uncommon", { 4, 1, 2, 3 } },
	{ "driver_needlefoot", "Needle Foot", "Driver", "Rare", { 1, 1, 7, 1 } },
	{ "driver_orbitball", "Orbit Ball", "Driver", "Rare", { 1, 1, 2, 6 } },
	{ "driver_hoverstud", "Hover Stud", "Driver", "Epic", { 1, 1, 6, 2 } },
	{ "driver_anchorcup", "Anchor Cup", "Driver", "Epic", { 1, 3, 3, 3 } },
	{ "driver_zerofrictiontip", "Zero-Friction Tip", "Driver", "Legendary", { 1, 1, 7, 1 } },
	{ "driver_gyroheart", "Gyro Heart", "Driver", "Legendary", { 1, 1, 3, 5 } },
	{ "driver_perpetualaxis", "Perpetual Axis", "Driver", "UltraLegendary", { 1, 1, 5, 3 } },
}

BeyConfig.Parts = {} -- id -> { Id, Name, Slot, Rarity, Stats }
BeyConfig.PartsBySlotRarity = {} -- slot -> rarity -> { part, ... }
for _, slot in ipairs(BeyConfig.Slots) do
	BeyConfig.PartsBySlotRarity[slot] = {}
	for _, rarity in ipairs(BeyConfig.Rarities) do
		BeyConfig.PartsBySlotRarity[slot][rarity] = {}
	end
end
for _, row in ipairs(PART_ROWS) do
	local id, name, slot, rarity, weights = row[1], row[2], row[3], row[4], row[5]
	assert(BeyConfig.Parts[id] == nil, "duplicate part id " .. id)
	local part = {
		Id = id,
		Name = name,
		Slot = slot,
		Rarity = rarity,
		Stats = distribute(BeyConfig.PartBudget[rarity], weights),
	}
	BeyConfig.Parts[id] = part
	table.insert(BeyConfig.PartsBySlotRarity[slot][rarity], part)
end

-- What a player owns at the start: all Common.
BeyConfig.StarterBey = { Layer = "layer_cinderlash", Disc = "disc_pebbledisc", Driver = "driver_flatnub" }

-- Spirits and special moves are equipped next to the three parts (the "loadout"). What they do in battle is in
-- Core/SpecialsCore.lua; the numbers are here. Every name and creature is ORIGINAL.
--   Spirit   the creature that appears when you use a special or awaken. Passive: small always-on multipliers.
--   Special  two slots (keys 1 and 2). Kinds: dash (burst forward; your next hit hits harder), guard (take less
--            damage and knockback for a while), heal (get spin back), quake (shockwave around you).
local SPIRIT_ROWS = {
	-- id, name, rarity, colour, passive multipliers
	{ "spirit_emberwolf", "Ember Wolf", "Common", Color3.fromRGB(255, 122, 46), { Attack = 1.04 } },
	{ "spirit_tidedrake", "Tide Drake", "Uncommon", Color3.fromRGB(79, 227, 255), { Defense = 1.06 } },
	{ "spirit_thornstag", "Thorn Stag", "Rare", Color3.fromRGB(140, 255, 106), { Defense = 1.03, Drain = 0.92 } },
	{ "spirit_stormroc", "Storm Roc", "Epic", Color3.fromRGB(111, 155, 255), { Attack = 1.04, Speed = 1.06 } },
	{ "spirit_sunmane", "Sunmane Lion", "Legendary", Color3.fromRGB(255, 201, 64), { Attack = 1.07, Defense = 1.05 } },
}
local SPECIAL_ROWS = {
	-- id, name, rarity, colour, kind, tuning (Cooldown seconds; see SpecialsCore for each field)
	{ "special_cometdrive", "Comet Drive", "Common", Color3.fromRGB(255, 150, 60), "dash", { Cooldown = 9, DashSpeed = 95, Window = 1.6, DamageMul = 1.8, KnockbackMul = 1.6 } },
	{ "special_ironshell", "Iron Shell", "Common", Color3.fromRGB(140, 190, 255), "guard", { Cooldown = 14, Duration = 3.5, Block = 0.5, KnockbackBlock = 0.6 } },
	{ "special_secondspin", "Second Spin", "Uncommon", Color3.fromRGB(110, 255, 150), "heal", { Cooldown = 22, Heal = 0.14 } },
	{ "special_quakestomp", "Quake Stomp", "Rare", Color3.fromRGB(255, 196, 70), "quake", { Cooldown = 12, Radius = 14, Damage = 9, Knockback = 60 } },
	{ "special_starbreaker", "Starbreaker Rush", "Epic", Color3.fromRGB(190, 110, 255), "dash", { Cooldown = 11, DashSpeed = 115, Window = 1.8, DamageMul = 2.2, KnockbackMul = 1.9 } },
	{ "special_aegisbloom", "Aegis Bloom", "Legendary", Color3.fromRGB(255, 120, 200), "guard", { Cooldown = 16, Duration = 4.5, Block = 0.65, KnockbackBlock = 0.8, Heal = 0.05 } },
}

BeyConfig.Spirits = {} -- id -> { Id, Name, Slot = "Spirit", Rarity, Color, Passive }
BeyConfig.Specials = {} -- id -> { Id, Name, Slot = "Special", Rarity, Color, Kind, Tuning }
for _, row in ipairs(SPIRIT_ROWS) do
	BeyConfig.Spirits[row[1]] = { Id = row[1], Name = row[2], Slot = "Spirit", Rarity = row[3], Color = row[4], Passive = row[5] }
end
for _, row in ipairs(SPECIAL_ROWS) do
	BeyConfig.Specials[row[1]] = { Id = row[1], Name = row[2], Slot = "Special", Rarity = row[3], Color = row[4], Kind = row[5], Tuning = row[6] }
end

-- Everything a player can own, by id (parts, spirits, specials). Each row has .Slot (its kind of slot).
BeyConfig.Items = {}
for _, list in ipairs({ BeyConfig.Parts, BeyConfig.Spirits, BeyConfig.Specials }) do
	for id, item in pairs(list) do
		assert(BeyConfig.Items[id] == nil, "duplicate item id " .. id)
		BeyConfig.Items[id] = item
	end
end

-- The loadout: equipped slot -> the kind of item it holds. Special1 and Special2 both hold specials (never the same one).
BeyConfig.LoadoutSlots = { "Layer", "Disc", "Driver", "Spirit", "Special1", "Special2" }
function BeyConfig.SlotKind(slot)
	if slot == "Special1" or slot == "Special2" then
		return "Special"
	end
	return slot
end

-- What a new player owns and has equipped.
BeyConfig.StarterLoadout = {
	Layer = BeyConfig.StarterBey.Layer,
	Disc = BeyConfig.StarterBey.Disc,
	Driver = BeyConfig.StarterBey.Driver,
	Spirit = "spirit_emberwolf",
	Special1 = "special_cometdrive",
	Special2 = "special_ironshell",
}

-- A bey at level 1 has half its parts' strength; MaxLevel reaches the full value (grind cap).
function BeyConfig.LevelMultiplier(level)
	level = math.clamp(level, 1, BeyConfig.MaxLevel)
	return 0.5 + 0.5 * (level - 1) / (BeyConfig.MaxLevel - 1)
end

-- partIds = { Layer = id, Disc = id, Driver = id }. Returns Attack/Defense/Stamina/Balance.
function BeyConfig.ComputeStats(partIds, level)
	local stats = { Attack = 0, Defense = 0, Stamina = 0, Balance = 0 }
	for _, slot in ipairs(BeyConfig.Slots) do
		local part = BeyConfig.Parts[partIds[slot]]
		assert(part and part.Slot == slot, "bad part for slot " .. slot)
		for _, stat in ipairs(BeyConfig.StatNames) do
			stats[stat] = stats[stat] + part.Stats[stat]
		end
	end
	local mult = BeyConfig.LevelMultiplier(level or BeyConfig.MaxLevel)
	for _, stat in ipairs(BeyConfig.StatNames) do
		stats[stat] = stats[stat] * mult
	end
	return stats
end

-- Movement and combat tuning. Change numbers here, not in the controller.
BeyConfig.Movement = {
	Radius = 2, -- bey body is a 4-stud ball
	GroundProbe = 1.2, -- extra ray length below the ball that still counts as ground
	MinGroundNormalY = 0.35, -- steeper than this is a wall, not ground
	JumpGroundIgnore = 0.15, -- seconds after a jump before the ground check is trusted
	UngroundDelay = 0.08, -- airborne only after this long with no ground under us (stops seam flicker)
	JumpCooldown = 0.3, -- minimum time between jumps
	SlamMinAirTime = 0.12, -- must be airborne this long before a slam can start
	SlamTimeout = 4, -- a dive that never lands is cancelled after this
	MaxLaunchBoost = 90, -- cap on the takeoff boost (studs/s)
	MaxSpeed = 220, -- any faster is treated as a physics glitch and clamped
	MaxDt = 0.1, -- frame-time cap for movement maths
	AirUprightRate = 3, -- how quickly the bey levels out in the air
	StuckTime = 6, -- airborne and motionless this long = wedged; reset
	ProbeRadius = 1.4, -- radius of the downward ground sphere-probe
	BaseSpeed = 42, -- studs/second
	SpeedPerAttack = 0.5, -- extra speed per Attack point
	SpeedPerBalance = 0.3, -- extra speed per Balance point
	Accel = 110, -- ground acceleration while holding a direction
	Brake = 35, -- ground slow-down when you let go on gentle ground (momentum feels weighty)
	RollingFriction = 4, -- always-on slow-down while on the ground
	MinTraction = 0.15, -- grip left on the steepest walkable slope (so walls pull you back down)
	Grip = 5, -- how fast sideways drift is removed while steering (scaled by traction)
	LeanSpeedBonus = 0.5, -- nose fully down: +50% top speed
	LeanAccelBonus = 0.6, -- nose fully down: +60% acceleration
	LeanBrake = 90, -- nose fully up: this much extra braking (studs/s per second)
	BrakeDriveCut = 0.85, -- nose fully up also removes this share of your drive (push and top speed)
	SurfaceAlignRate = 14, -- how quickly the bey leans to match the slope it is on
	AirAccel = 28,
	JumpSpeed = 55, -- upward speed of a jump
	JumpTiltBonus = 0.35, -- aiming up adds up to this fraction to the jump
	MaxTiltDeg = 40, -- how far the mouse can pitch the bey up or down
	NoseMinSpeed = 4, -- below this speed the nose faces the camera direction instead of the travel direction
	NoseTurnRate = 10, -- how fast the nose swings round to a new travel direction
	LaunchFactor = 1.1, -- ramp takeoff: extra upward speed = flat speed * this * tilt (aiming up)
	LaunchDownFactor = 0.4, -- aiming down at takeoff flattens the launch by this much
	MinLaunchSpeed = 10, -- below this flat speed there is no takeoff boost
	MinLaunchVy = 3, -- you must be rising off the edge (a ramp), not just walking off a ledge
	GlideLift = 18, -- aiming up in the air: upward acceleration at full tilt
	DiveAssist = 70, -- aiming down in the air: extra downward acceleration at full tilt
	Gravity = 140, -- Workspace.Gravity (default 196.2 feels heavy for a flying top)
	SlamSpeed = 120, -- downward speed of the dive-slam
	SlamCooldown = 1.2,
	SlamRadius = 14, -- who a landing slam can hit
	SlamImpulse = 220, -- knockback per unit of mass, before Attack scaling
	SlamAttackScale = 0.04, -- +4% knockback per Attack point
	RespawnY = -60, -- fall below this and the bey resets
	SpawnPosition = Vector3.new(0, 5, 0),
	CameraDistance = 22,
	CameraHeight = 2,
	CameraBasePitch = 0.28, -- radians the camera looks down by default
	CameraMinPitch = 0.06, -- the camera never drops below the bey (this was what broke it at high tilt)
	MouseSensitivity = 0.0028, -- radians per pixel
	TouchSensitivity = 0.0045,
}

-- Paid random item boxes. Roblox requires every outcome and its real odds to be shown before purchase.
-- Odds are basis points: 5000 = 50.00%. Each table MUST total 10000; the check below enforces it.
-- Prices are placeholders to be set at launch.
BeyConfig.Boxes = {
	PartBox = {
		DisplayName = "Part Crate",
		Price = 49, -- Robux (placeholder)
		Kind = "Part", -- gives ONE part; the slot is uniform over Layer/Disc/Driver
		Odds = { Common = 5000, Uncommon = 2800, Rare = 1500, Epic = 550, Legendary = 140, UltraLegendary = 10 },
	},
	BeyBox = {
		DisplayName = "Full Bey Crate",
		Price = 199, -- Robux (placeholder)
		Kind = "Bey", -- gives a Layer + Disc + Driver, all of the rolled rarity
		Odds = { Common = 0, Uncommon = 3500, Rare = 4000, Epic = 2000, Legendary = 450, UltraLegendary = 50 },
	},
}

-- Fail loudly at load time if the data is inconsistent.
local function validate()
	local top = {}
	for _, slot in ipairs(BeyConfig.Slots) do
		top[slot] = 0
	end
	for _, part in pairs(BeyConfig.Parts) do
		if part.Rarity == "Legendary" then
			local total = 0
			for _, stat in ipairs(BeyConfig.StatNames) do
				total = total + part.Stats[stat]
			end
			top[part.Slot] = math.max(top[part.Slot], total)
		end
	end
	for _, part in pairs(BeyConfig.Parts) do
		local total = 0
		for _, stat in ipairs(BeyConfig.StatNames) do
			total = total + part.Stats[stat]
		end
		assert(total == BeyConfig.PartBudget[part.Rarity], part.Id .. ": stats do not match the rarity budget")
		if part.Rarity == "UltraLegendary" then
			assert(total <= top[part.Slot] * BeyConfig.UltraMultiplier + 0.5, part.Id .. ": Ultra Legendary is over +10%")
			assert(total > top[part.Slot], part.Id .. ": Ultra Legendary is not stronger than Legendary")
		end
	end
	for slot, id in pairs(BeyConfig.StarterLoadout) do
		local item = BeyConfig.Items[id]
		assert(item and item.Slot == BeyConfig.SlotKind(slot), "starter loadout: bad " .. slot)
	end
	assert(BeyConfig.StarterLoadout.Special1 ~= BeyConfig.StarterLoadout.Special2, "starter specials must differ")
	for id, sp in pairs(BeyConfig.Specials) do
		local t = sp.Tuning
		assert(type(t.Cooldown) == "number" and t.Cooldown > 0, id .. ": no cooldown")
		if sp.Kind == "dash" then
			assert(t.DashSpeed and t.Window and t.DamageMul and t.KnockbackMul, id .. ": dash tuning")
		elseif sp.Kind == "guard" then
			assert(t.Duration and t.Block and t.KnockbackBlock and t.Block < 1, id .. ": guard tuning")
		elseif sp.Kind == "heal" then
			assert(t.Heal and t.Heal > 0 and t.Heal < 1, id .. ": heal tuning")
		elseif sp.Kind == "quake" then
			assert(t.Radius and t.Damage and t.Knockback, id .. ": quake tuning")
		else
			error(id .. ": unknown special kind " .. tostring(sp.Kind))
		end
	end
	for boxId, box in pairs(BeyConfig.Boxes) do
		local sum = 0
		for _, rarity in ipairs(BeyConfig.Rarities) do
			local bp = box.Odds[rarity]
			assert(bp ~= nil and bp >= 0 and bp == math.floor(bp), boxId .. ": bad odds for " .. rarity)
			sum = sum + bp
			if bp > 0 then
				for _, slot in ipairs(BeyConfig.Slots) do
					assert(#BeyConfig.PartsBySlotRarity[slot][rarity] > 0, boxId .. ": no " .. rarity .. " " .. slot .. " to give")
				end
			end
		end
		assert(sum == 10000, boxId .. ": odds total " .. sum .. " bp, must be 10000")
	end
end
validate()

-- Picks a rarity from the box odds using an integer roll in [1, 10000].
local function rollRarity(box, rng)
	local roll = rng:NextInteger(1, 10000)
	local acc = 0
	for _, rarity in ipairs(BeyConfig.Rarities) do
		acc = acc + box.Odds[rarity]
		if roll <= acc then
			return rarity
		end
	end
	error("unreachable: odds do not total 10000")
end

-- SERVER ONLY. Returns an array of part ids (1 for a Part Crate, 3 for a Full Bey Crate).
function BeyConfig.RollBox(boxId, rng)
	local box = assert(BeyConfig.Boxes[boxId], "unknown box " .. tostring(boxId))
	rng = rng or Random.new()
	local rarity = rollRarity(box, rng)
	local function pick(slot)
		local list = BeyConfig.PartsBySlotRarity[slot][rarity]
		return list[rng:NextInteger(1, #list)].Id
	end
	if box.Kind == "Bey" then
		return { pick("Layer"), pick("Disc"), pick("Driver") }
	end
	return { pick(BeyConfig.Slots[rng:NextInteger(1, #BeyConfig.Slots)]) }
end

-- For the shop UI: every outcome with its exact percent. Rows total 100%.
-- Part Crate rows are single parts; Full Bey Crate rows are rarity tiers (every set of that tier is equally likely per slot).
function BeyConfig.GetDisplayOdds(boxId)
	local box = assert(BeyConfig.Boxes[boxId], "unknown box " .. tostring(boxId))
	local rows = {}
	for _, rarity in ipairs(BeyConfig.Rarities) do
		local bp = box.Odds[rarity]
		if bp > 0 then
			if box.Kind == "Part" then
				for _, slot in ipairs(BeyConfig.Slots) do
					local list = BeyConfig.PartsBySlotRarity[slot][rarity]
					for _, part in ipairs(list) do
						table.insert(rows, {
							Label = part.Name .. " (" .. slot .. ")",
							Rarity = rarity,
							Percent = bp / 100 / #BeyConfig.Slots / #list,
						})
					end
				end
			else
				table.insert(rows, { Label = "Full " .. rarity .. " bey", Rarity = rarity, Percent = bp / 100 })
			end
		end
	end
	return rows
end

return BeyConfig
]=====])
install('RS', '', 'ModuleScript', 'BeyDesigns', [=====[
--!nonstrict
-- Visual design of every part: pure data, one row per part id in BeyConfig.
-- Layer styles:  Spike, Hook, Blade, Petal, Armor      (Count = number of blades or armor segments)
-- Disc styles:   Heavy, Ring, Fly, Stack
-- Driver styles: Flat, Round, Needle, Tripod, Cup
-- Primary = body colour, Accent = trim colour (also the glow colour on Epic and above).
-- All shapes are ORIGINAL and built from basic Roblox parts by BeyVisuals; none copy a licensed design.

local function c(hex)
	return Color3.fromHex(hex)
end

local BeyDesigns = {}

BeyDesigns.Styles = {
	Layer = { Spike = true, Hook = true, Blade = true, Petal = true, Armor = true },
	Disc = { Heavy = true, Ring = true, Fly = true, Stack = true },
	Driver = { Flat = true, Round = true, Needle = true, Tripod = true, Cup = true },
}

-- id = { Style, Count, Primary, Accent }
BeyDesigns.Parts = {
	-- Layers
	layer_cinderlash = { Style = "Spike", Count = 4, Primary = c("#8a2b1c"), Accent = c("#ff7a2e") },
	layer_thornwhirl = { Style = "Hook", Count = 3, Primary = c("#2f5d2a"), Accent = c("#9be15d") },
	layer_skyrend = { Style = "Blade", Count = 4, Primary = c("#3a6ea5"), Accent = c("#bfe3ff") },
	layer_mossback = { Style = "Armor", Count = 8, Primary = c("#4d5b3a"), Accent = c("#b5c76a") },
	layer_ironvane = { Style = "Blade", Count = 5, Primary = c("#6b7078"), Accent = c("#d0d6dd") },
	layer_stormcleat = { Style = "Hook", Count = 4, Primary = c("#2d3f7a"), Accent = c("#6fd0ff") },
	layer_voidpetal = { Style = "Petal", Count = 5, Primary = c("#2a1646"), Accent = c("#b06bff") },
	layer_sunhammer = { Style = "Armor", Count = 6, Primary = c("#a8751b"), Accent = c("#ffd45e") },
	layer_solsticerend = { Style = "Blade", Count = 6, Primary = c("#c47d12"), Accent = c("#fff0a0") },
	layer_tempesthalo = { Style = "Petal", Count = 6, Primary = c("#1f6fa8"), Accent = c("#8ff0ff") },
	layer_eclipsesovereign = { Style = "Spike", Count = 6, Primary = c("#14101c"), Accent = c("#ff3c64") },
	-- Discs
	disc_pebbledisc = { Style = "Stack", Primary = c("#7d7468"), Accent = c("#b9ad9a") },
	disc_tinplate = { Style = "Ring", Primary = c("#8a8f94"), Accent = c("#c9ced3") },
	disc_bulwarkring = { Style = "Heavy", Primary = c("#4a5568"), Accent = c("#8fa3bd") },
	disc_driftweight = { Style = "Fly", Primary = c("#5a6e73"), Accent = c("#9fd4cf") },
	disc_granitecore = { Style = "Heavy", Primary = c("#5b5148"), Accent = c("#a99a88") },
	disc_hollowanvil = { Style = "Ring", Primary = c("#3b3f46"), Accent = c("#e0743c") },
	disc_titanballast = { Style = "Heavy", Primary = c("#2f3a4a"), Accent = c("#6aa7ff") },
	disc_stillwater = { Style = "Fly", Primary = c("#1f4d6b"), Accent = c("#6fe0ff") },
	disc_worldrootmass = { Style = "Heavy", Primary = c("#3b5a2c"), Accent = c("#9cff6a") },
	disc_astralflywheel = { Style = "Fly", Primary = c("#2b2a5a"), Accent = c("#c6b3ff") },
	disc_singularityplate = { Style = "Stack", Primary = c("#0d0b14"), Accent = c("#7a5cff") },
	-- Drivers
	driver_flatnub = { Style = "Flat", Primary = c("#6a6a6a"), Accent = c("#bbbbbb") },
	driver_roundpeg = { Style = "Round", Primary = c("#6a5a48"), Accent = c("#cdb89a") },
	driver_glidepin = { Style = "Needle", Primary = c("#5f7f6f"), Accent = c("#c0f0d8") },
	driver_spikegrip = { Style = "Tripod", Primary = c("#7a3b2c"), Accent = c("#ffb08a") },
	driver_needlefoot = { Style = "Needle", Primary = c("#4a5560"), Accent = c("#a8d0ff") },
	driver_orbitball = { Style = "Round", Primary = c("#4a3a6a"), Accent = c("#d2b8ff") },
	driver_hoverstud = { Style = "Flat", Primary = c("#2e5a6a"), Accent = c("#7fe8ff") },
	driver_anchorcup = { Style = "Cup", Primary = c("#4a4a55"), Accent = c("#ffd070") },
	driver_zerofrictiontip = { Style = "Needle", Primary = c("#c8ccd2"), Accent = c("#ffffff") },
	driver_gyroheart = { Style = "Round", Primary = c("#a02a4a"), Accent = c("#ff9ab8") },
	driver_perpetualaxis = { Style = "Needle", Primary = c("#100c1a"), Accent = c("#ff3c64") },
}

return BeyDesigns
]=====])
install('RS', '', 'ModuleScript', 'BeyMeshData', [=====[
--!nonstrict
-- GENERATED by tools/blender/build_beys.py. Do not edit by hand.
-- Size and Center of every bey mesh in studs, in Roblox axes, relative to the bey's centre.
-- BeyVisuals resizes each imported MeshPart to Size and places it at Center, so the import scale does not matter.
return {
	layer_cinderlash_P = { Center = Vector3.new(0.0001, 0.7300, -0.0000), Size = Vector3.new(4.0644, 0.6200, 4.0646) },
	layer_cinderlash_A = { Center = Vector3.new(0.0000, 0.8000, -0.0000), Size = Vector3.new(3.1250, 0.3600, 3.1250) },
	layer_thornwhirl_P = { Center = Vector3.new(-0.3020, 0.7300, -0.0369), Size = Vector3.new(3.7469, 0.6200, 3.8911) },
	layer_thornwhirl_A = { Center = Vector3.new(-0.1998, 0.8000, 0.1885), Size = Vector3.new(3.2823, 0.3600, 3.1892) },
	layer_skyrend_P = { Center = Vector3.new(0.0000, 0.7300, -0.0000), Size = Vector3.new(3.6439, 0.6200, 3.6439) },
	layer_skyrend_A = { Center = Vector3.new(0.0000, 0.8000, -0.0000), Size = Vector3.new(3.3841, 0.3600, 3.3841) },
	layer_mossback_P = { Center = Vector3.new(0.0000, 0.7300, -0.0000), Size = Vector3.new(4.0952, 0.6200, 4.0953) },
	layer_mossback_A = { Center = Vector3.new(-0.0001, 0.8000, -0.0000), Size = Vector3.new(3.8247, 0.3600, 3.8245) },
	layer_ironvane_P = { Center = Vector3.new(0.0097, 0.7300, -0.1887), Size = Vector3.new(3.9919, 0.6200, 3.8203) },
	layer_ironvane_A = { Center = Vector3.new(0.0082, 0.8000, -0.0694), Size = Vector3.new(2.8182, 0.3600, 2.8244) },
	layer_stormcleat_P = { Center = Vector3.new(0.0000, 0.7300, -0.0000), Size = Vector3.new(3.6123, 0.6200, 3.6123) },
	layer_stormcleat_A = { Center = Vector3.new(0.0000, 0.8000, -0.0000), Size = Vector3.new(3.0251, 0.3600, 3.0251) },
	layer_voidpetal_P = { Center = Vector3.new(-0.0680, 0.7300, -0.0912), Size = Vector3.new(4.0892, 0.6200, 4.0333) },
	layer_voidpetal_A = { Center = Vector3.new(-0.0444, 0.8000, -0.0904), Size = Vector3.new(3.7816, 0.3600, 3.7172) },
	layer_sunhammer_P = { Center = Vector3.new(0.0001, 0.7300, -0.0000), Size = Vector3.new(4.0976, 0.6200, 4.3126) },
	layer_sunhammer_A = { Center = Vector3.new(-0.0001, 0.8000, -0.0000), Size = Vector3.new(3.8258, 0.3600, 3.5438) },
	layer_solsticerend_P = { Center = Vector3.new(0.0001, 0.7300, -0.0000), Size = Vector3.new(3.7834, 0.6200, 4.1863) },
	layer_solsticerend_A = { Center = Vector3.new(0.0000, 0.8000, -0.0000), Size = Vector3.new(2.7667, 0.3600, 3.0203) },
	layer_tempesthalo_P = { Center = Vector3.new(0.0000, 0.7300, -0.0000), Size = Vector3.new(4.0835, 0.6200, 4.0392) },
	layer_tempesthalo_A = { Center = Vector3.new(0.0000, 0.8000, -0.0000), Size = Vector3.new(3.8223, 0.3600, 3.7566) },
	layer_eclipsesovereign_P = { Center = Vector3.new(0.0001, 0.7300, -0.0000), Size = Vector3.new(3.6858, 0.6200, 4.1952) },
	layer_eclipsesovereign_A = { Center = Vector3.new(0.0000, 0.8700, -0.0000), Size = Vector3.new(3.0478, 0.5000, 3.0520) },
	disc_pebbledisc_P = { Center = Vector3.new(0.0000, -0.0200, -0.0000), Size = Vector3.new(3.0434, 0.6400, 3.1864) },
	disc_pebbledisc_A = { Center = Vector3.new(0.0000, -0.0200, -0.0000), Size = Vector3.new(2.5864, 0.2000, 2.4727) },
	disc_tinplate_P = { Center = Vector3.new(0.0000, 0.0200, -0.0000), Size = Vector3.new(3.3200, 0.4800, 3.3200) },
	disc_tinplate_A = { Center = Vector3.new(0.0000, 0.0000, -0.0000), Size = Vector3.new(2.8000, 0.6000, 2.8000) },
	disc_bulwarkring_P = { Center = Vector3.new(0.0000, -0.0100, -0.0000), Size = Vector3.new(3.1600, 0.6200, 3.1600) },
	disc_bulwarkring_A = { Center = Vector3.new(0.0000, 0.0500, -0.0000), Size = Vector3.new(3.3200, 0.3800, 3.3200) },
	disc_driftweight_P = { Center = Vector3.new(0.0000, 0.0500, -0.0000), Size = Vector3.new(4.0400, 0.3000, 4.0400) },
	disc_driftweight_A = { Center = Vector3.new(0.0000, 0.0000, -0.0000), Size = Vector3.new(3.0000, 0.6000, 2.6761) },
	disc_granitecore_P = { Center = Vector3.new(0.0000, -0.0100, -0.0000), Size = Vector3.new(3.0303, 0.6200, 3.0303) },
	disc_granitecore_A = { Center = Vector3.new(0.0000, 0.0500, -0.0000), Size = Vector3.new(3.3200, 0.3800, 3.3200) },
	disc_hollowanvil_P = { Center = Vector3.new(0.0000, 0.0200, -0.0000), Size = Vector3.new(3.3200, 0.4800, 3.3200) },
	disc_hollowanvil_A = { Center = Vector3.new(0.0000, 0.0000, -0.0000), Size = Vector3.new(2.8000, 0.6000, 2.8000) },
	disc_titanballast_P = { Center = Vector3.new(0.0000, -0.0100, -0.0000), Size = Vector3.new(3.1195, 0.6200, 3.1600) },
	disc_titanballast_A = { Center = Vector3.new(0.0000, 0.0500, -0.0000), Size = Vector3.new(3.3200, 0.3800, 3.3200) },
	disc_stillwater_P = { Center = Vector3.new(0.0000, 0.0500, -0.0000), Size = Vector3.new(4.0400, 0.3000, 4.0400) },
	disc_stillwater_A = { Center = Vector3.new(0.0000, 0.0000, -0.0000), Size = Vector3.new(3.0000, 0.6000, 3.0000) },
	disc_worldrootmass_P = { Center = Vector3.new(0.0000, -0.0100, -0.0000), Size = Vector3.new(3.1600, 0.6200, 3.1600) },
	disc_worldrootmass_A = { Center = Vector3.new(0.0000, 0.0500, -0.0000), Size = Vector3.new(3.3200, 0.3800, 3.3200) },
	disc_astralflywheel_P = { Center = Vector3.new(0.0000, 0.0500, -0.0000), Size = Vector3.new(4.0400, 0.3000, 4.0400) },
	disc_astralflywheel_A = { Center = Vector3.new(0.0000, 0.0000, -0.0000), Size = Vector3.new(3.0000, 0.6000, 2.9014) },
	disc_singularityplate_P = { Center = Vector3.new(0.0000, -0.0200, -0.0000), Size = Vector3.new(2.7713, 0.6400, 3.1780) },
	disc_singularityplate_A = { Center = Vector3.new(0.0000, -0.0800, -0.0000), Size = Vector3.new(3.4000, 0.4400, 3.4000) },
	driver_flatnub_P = { Center = Vector3.new(0.0000, -0.6100, -0.0000), Size = Vector3.new(1.4264, 0.5800, 1.3695) },
	driver_flatnub_A = { Center = Vector3.new(0.0000, -1.0000, -0.0000), Size = Vector3.new(1.1808, 0.2000, 1.1808) },
	driver_roundpeg_P = { Center = Vector3.new(0.0000, -0.5450, -0.0000), Size = Vector3.new(1.1456, 0.4500, 1.1456) },
	driver_roundpeg_A = { Center = Vector3.new(0.0000, -1.0900, -0.0000), Size = Vector3.new(0.8000, 0.8000, 0.8000) },
	driver_glidepin_P = { Center = Vector3.new(0.0000, -0.5450, -0.0000), Size = Vector3.new(1.1456, 0.4500, 1.1456) },
	driver_glidepin_A = { Center = Vector3.new(0.0000, -0.9951, -0.0000), Size = Vector3.new(0.3819, 0.4502, 0.3819) },
	driver_spikegrip_P = { Center = Vector3.new(0.0000, -0.6700, 0.0236), Size = Vector3.new(1.1456, 0.7000, 1.1928) },
	driver_spikegrip_A = { Center = Vector3.new(0.0000, -1.1704, 0.1300), Size = Vector3.new(1.0221, 0.3008, 0.8979) },
	driver_needlefoot_P = { Center = Vector3.new(0.0000, -0.5450, -0.0000), Size = Vector3.new(1.1456, 0.4500, 1.1456) },
	driver_needlefoot_A = { Center = Vector3.new(0.0000, -1.0702, -0.0000), Size = Vector3.new(0.3841, 0.6004, 0.3841) },
	driver_orbitball_P = { Center = Vector3.new(0.0000, -0.5450, -0.0000), Size = Vector3.new(1.1456, 0.4500, 1.1456) },
	driver_orbitball_A = { Center = Vector3.new(0.0000, -1.1700, -0.0000), Size = Vector3.new(1.0000, 1.0000, 1.0000) },
	driver_hoverstud_P = { Center = Vector3.new(0.0000, -0.6100, -0.0000), Size = Vector3.new(1.8864, 0.5800, 1.8070) },
	driver_hoverstud_A = { Center = Vector3.new(0.0000, -1.0000, -0.0000), Size = Vector3.new(1.5580, 0.2000, 1.5580) },
	driver_anchorcup_P = { Center = Vector3.new(0.0000, -0.6700, -0.0000), Size = Vector3.new(1.6572, 0.7000, 1.6572) },
	driver_anchorcup_A = { Center = Vector3.new(0.0000, -0.7800, -0.0000), Size = Vector3.new(1.5600, 0.0800, 1.5600) },
	driver_zerofrictiontip_P = { Center = Vector3.new(0.0000, -0.5450, -0.0000), Size = Vector3.new(1.1456, 0.4500, 1.1456) },
	driver_zerofrictiontip_A = { Center = Vector3.new(0.0000, -0.9202, -0.0000), Size = Vector3.new(1.3913, 1.1404, 1.3913) },
	driver_gyroheart_P = { Center = Vector3.new(0.0000, -0.5450, -0.0000), Size = Vector3.new(1.1456, 0.4500, 1.1456) },
	driver_gyroheart_A = { Center = Vector3.new(0.0000, -1.0100, -0.0000), Size = Vector3.new(1.3832, 1.3200, 1.3832) },
	driver_perpetualaxis_P = { Center = Vector3.new(0.0000, -0.5450, -0.0000), Size = Vector3.new(1.1456, 0.4500, 1.1456) },
	driver_perpetualaxis_A = { Center = Vector3.new(0.0000, -0.9602, -0.0000), Size = Vector3.new(1.3913, 1.2204, 1.3913) },
}
]=====])
install('RS', '', 'ModuleScript', 'BeyVisuals', [=====[
--!nonstrict
-- Builds a bey's looks. If the Blender meshes have been imported into ReplicatedStorage.BeyMeshes (see README),
-- each part uses its mesh; otherwise it falls back to a simple shape built from basic Roblox parts (BeyDesigns).
-- Everything is welded to the spinning hub, massless and non-colliding, so the physics body is unchanged.
-- Call BeyVisuals.Attach on the SERVER after the model is parented to Workspace (so welds capture the layout).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BeyConfig = require(script.Parent.BeyConfig)
local BeyDesigns = require(script.Parent.BeyDesigns)
local BeyMeshData = require(script.Parent.BeyMeshData)

local BeyVisuals = {}

local Y_OFFSET = -0.7 -- sits the visual low in the 4-stud collision ball so the tip nearly touches the ground
local RAD90 = math.rad(90)
local TAU = math.pi * 2

local function rarityRank(rarity)
	for i, r in ipairs(BeyConfig.Rarities) do
		if r == rarity then
			return i
		end
	end
	return 1
end

-- ctx = { hub = Part, root = CFrame (the body's CFrame), parent = Instance }
local function addPart(ctx, size, localCF, color, material, shape)
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CFrame = ctx.root * CFrame.new(0, Y_OFFSET, 0) * localCF
	p.Parent = ctx.parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.hub
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function addBlock(ctx, size, localCF, color, material)
	return addPart(ctx, size, localCF, color, material)
end

local function addCyl(ctx, diameter, height, y, color, material)
	return addPart(
		ctx,
		Vector3.new(height, diameter, diameter),
		CFrame.new(0, y, 0) * CFrame.Angles(0, 0, RAD90),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function addBall(ctx, diameter, y, color, material)
	return addPart(ctx, Vector3.new(diameter, diameter, diameter), CFrame.new(0, y, 0), color, material, Enum.PartType.Ball)
end

local function addEllipsoid(ctx, size, localCF, color, material)
	local p = addPart(ctx, size, localCF, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Places something `radius` out along direction angle `a`, then twists it by `swirl` about its own centre.
local function radial(a, y, radius, swirl)
	return CFrame.Angles(0, a, 0) * CFrame.new(0, y, -radius) * CFrame.Angles(0, swirl or 0, 0)
end

local function buildLayer(ctx, d)
	local y = 0.55
	addCyl(ctx, 2.3, 0.16, y, d.Primary)
	local n = d.Count
	for i = 1, n do
		local a = TAU * i / n
		if d.Style == "Spike" then
			addBlock(ctx, Vector3.new(0.28, 0.34, 1.6), radial(a, y + 0.15, 1.25), d.Primary)
			addBlock(ctx, Vector3.new(0.09, 0.1, 1.2), radial(a, y + 0.35, 1.2), d.Accent)
			addBlock(ctx, Vector3.new(0.2, 0.26, 0.4), radial(a, y + 0.13, 2.0), d.Accent)
		elseif d.Style == "Hook" then
			addBlock(ctx, Vector3.new(0.42, 0.3, 1.45), radial(a, y + 0.15, 1.2, -0.45), d.Primary)
			addBlock(ctx, Vector3.new(0.3, 0.26, 0.6), radial(a, y + 0.13, 1.85, -1.0), d.Accent)
		elseif d.Style == "Blade" then
			addBlock(ctx, Vector3.new(0.34, 0.3, 1.85), radial(a, y + 0.15, 1.2, 0.3), d.Primary)
			addBlock(ctx, Vector3.new(0.08, 0.32, 1.85), radial(a, y + 0.16, 1.2, 0.3) * CFrame.new(0.19, 0, 0), d.Accent)
		elseif d.Style == "Petal" then
			addEllipsoid(ctx, Vector3.new(0.95, 0.42, 1.9), radial(a, y + 0.2, 1.15, 0.5), d.Primary)
			addEllipsoid(ctx, Vector3.new(0.3, 0.2, 0.9), radial(a, y + 0.35, 1.2, 0.5), d.Accent)
		elseif d.Style == "Armor" then
			local r = 1.45
			local w = 2 * r * math.tan(math.pi / n) + 0.05
			addBlock(ctx, Vector3.new(w, 0.55, 0.55), radial(a, y + 0.2, r), d.Primary)
			addBlock(ctx, Vector3.new(w * 0.6, 0.1, 0.2), radial(a, y + 0.5, r), d.Accent)
		end
	end
end

local function buildDisc(ctx, d)
	if d.Style == "Heavy" then
		addCyl(ctx, 2.8, 0.7, 0, d.Primary)
		addCyl(ctx, 3.0, 0.16, 0, d.Accent)
	elseif d.Style == "Ring" then
		addCyl(ctx, 3.0, 0.45, 0, d.Primary)
		addCyl(ctx, 1.8, 0.5, 0, d.Accent)
	elseif d.Style == "Fly" then
		addCyl(ctx, 3.8, 0.2, 0, d.Primary)
		addCyl(ctx, 1.6, 0.5, 0, d.Accent)
	elseif d.Style == "Stack" then
		addCyl(ctx, 3.0, 0.3, -0.2, d.Primary)
		addCyl(ctx, 2.4, 0.3, 0.1, d.Accent)
		addCyl(ctx, 1.8, 0.3, 0.35, d.Primary)
	end
end

local function buildDriver(ctx, d)
	if d.Style == "Flat" then
		addCyl(ctx, 1.2, 0.4, -0.6, d.Primary)
		addCyl(ctx, 0.9, 0.12, -0.85, d.Accent)
	elseif d.Style == "Round" then
		addCyl(ctx, 0.55, 0.4, -0.5, d.Primary)
		addBall(ctx, 0.95, -0.85, d.Accent)
	elseif d.Style == "Needle" then
		addCyl(ctx, 0.6, 0.7, -0.6, d.Primary)
		addCyl(ctx, 0.28, 0.6, -1.1, d.Accent)
		addBall(ctx, 0.22, -1.42, d.Accent)
	elseif d.Style == "Tripod" then
		addCyl(ctx, 0.9, 0.3, -0.5, d.Primary)
		for i = 1, 3 do
			local a = TAU * i / 3
			addBlock(ctx, Vector3.new(0.2, 0.7, 0.2), CFrame.Angles(0, a, 0) * CFrame.new(0, -0.95, -0.4) * CFrame.Angles(-0.25, 0, 0), d.Accent)
		end
	elseif d.Style == "Cup" then
		addCyl(ctx, 1.4, 0.5, -0.65, d.Primary)
		addCyl(ctx, 1.5, 0.1, -0.5, d.Accent, Enum.Material.Neon)
	end
end

-- Rarity dressing: Epic+ get a glowing trim ring, Legendary+ sparks, Ultra Legendary a light too.
local function buildRarityEffects(ctx, layerDesign, rarity, meshed)
	local rank = rarityRank(rarity)
	if rank >= rarityRank("Epic") and not meshed then -- the meshes model their own rarity trim
		addCyl(ctx, 2.6, 0.06, 0.42, layerDesign.Accent, Enum.Material.Neon)
	end
	if rank >= rarityRank("Legendary") then
		local at = Instance.new("Attachment")
		at.Parent = ctx.hub
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(layerDesign.Accent)
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(2, 5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = rank >= rarityRank("UltraLegendary") and 40 or 16
		e.Parent = at
	end
	if rank >= rarityRank("UltraLegendary") then
		local light = Instance.new("PointLight")
		light.Color = layerDesign.Accent
		light.Brightness = 2
		light.Range = 12
		light.Parent = ctx.hub
	end
end

-- hub: the spinning Part the visuals attach to. root: the body's CFrame when the hub was placed.
-- partIds: { Layer = id, Disc = id, Driver = id }. The highest rarity among the three sets the dressing.
-- Imported MeshPart named `name` anywhere under ReplicatedStorage.BeyMeshes (the importer may nest them in Models).
local function findMesh(name)
	local folder = ReplicatedStorage:FindFirstChild("BeyMeshes")
	local found = folder and folder:FindFirstChild(name, true)
	if found and found:IsA("MeshPart") and BeyMeshData[name] then
		return found
	end
	return nil
end

-- Clones a mesh, resizes it to the size Blender recorded (so the import scale doesn't matter) and welds it on.
local function addMesh(ctx, template, data, color, material, lift)
	local p = template:Clone()
	for _, child in ipairs(p:GetChildren()) do
		child:Destroy() -- drop anything the importer attached (SurfaceAppearance, welds)
	end
	pcall(function()
		p.TextureID = ""
	end)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Color = color
	p.Material = material
	p.Size = data.Size
	p.CFrame = ctx.root * CFrame.new(0, Y_OFFSET + lift, 0) * CFrame.new(data.Center)
	p.Parent = ctx.parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.hub
	weld.Part1 = p
	weld.Parent = p
end

-- Uses the part's two meshes if both are imported; returns false so the caller can fall back.
-- Lowest and highest point of a part's two meshes (bey-local studs), or nil if it has no mesh data.
local function meshSpan(id)
	local p, a = BeyMeshData[id .. "_P"], BeyMeshData[id .. "_A"]
	if not (p and a) then
		return nil
	end
	local bottom = math.min(p.Center.Y - p.Size.Y / 2, a.Center.Y - a.Size.Y / 2)
	local top = math.max(p.Center.Y + p.Size.Y / 2, a.Center.Y + a.Size.Y / 2)
	return bottom, top
end

-- lift: how far to move the part up or down so it sits flush on the parts next to it.
local function tryMeshes(ctx, id, slot, design, lift)
	local primary, accent = findMesh(id .. "_P"), findMesh(id .. "_A")
	if not (primary and accent) then
		return false
	end
	local rank = rarityRank(BeyConfig.Parts[id].Rarity)
	local body = slot == "Disc" and Enum.Material.Metal or Enum.Material.SmoothPlastic
	addMesh(ctx, primary, BeyMeshData[id .. "_P"], design.Primary, body, lift)
	addMesh(ctx, accent, BeyMeshData[id .. "_A"], design.Accent, rank >= rarityRank("Legendary") and Enum.Material.Neon or Enum.Material.SmoothPlastic, lift)
	return true
end

function BeyVisuals.Attach(hub, root, partIds, parent)
	local ctx = { hub = hub, root = root, parent = parent or hub.Parent }
	local layer, disc, driver = BeyDesigns.Parts[partIds.Layer], BeyDesigns.Parts[partIds.Disc], BeyDesigns.Parts[partIds.Driver]
	assert(layer and disc and driver, "missing design for a part")
	-- Stack the parts flush: the wheel stays put, the layer sits on the wheel's top face and the driver hangs
	-- from its bottom face. Wheels differ in thickness, so fixed heights would leave gaps. A small overlap hides seams.
	local OVERLAP = 0.02
	local discBottom, discTop = meshSpan(partIds.Disc)
	if not (discBottom and findMesh(partIds.Disc .. "_P")) then
		discBottom, discTop = -0.35, 0.35 -- the block-built fallback wheel
	end
	local layerBottom = meshSpan(partIds.Layer)
	local _, driverTop = meshSpan(partIds.Driver)
	local layerLift = layerBottom and (discTop - OVERLAP - layerBottom) or 0
	local driverLift = driverTop and (discBottom + OVERLAP - driverTop) or 0

	if not tryMeshes(ctx, partIds.Disc, "Disc", disc, 0) then
		buildDisc(ctx, disc)
	end
	if not tryMeshes(ctx, partIds.Driver, "Driver", driver, driverLift) then
		buildDriver(ctx, driver)
	end
	local layerMeshed = tryMeshes(ctx, partIds.Layer, "Layer", layer, layerLift)
	if not layerMeshed then
		buildLayer(ctx, layer)
	end

	local best = "Common"
	for _, slot in ipairs(BeyConfig.Slots) do
		local rarity = BeyConfig.Parts[partIds[slot]].Rarity
		if rarityRank(rarity) > rarityRank(best) then
			best = rarity
		end
	end
	buildRarityEffects(ctx, layer, best, layerMeshed)
end

-- For menus (ViewportFrames): a Model of one part (id) or a whole bey (partIds table), centred on the origin,
-- anchored, no physics. Cosmetic only; the client calls this.
function BeyVisuals.Preview(what)
	local model = Instance.new("Model")
	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Anchored = true
	hub.Transparency = 1
	hub.CanCollide = false
	hub.Size = Vector3.new(0.2, 0.2, 0.2)
	hub.CFrame = CFrame.new()
	hub.Parent = model
	model.PrimaryPart = hub
	if type(what) == "table" then
		BeyVisuals.Attach(hub, CFrame.new(), what, model)
	else
		local part = BeyConfig.Parts[what]
		local design = BeyDesigns.Parts[what]
		if part and design then
			local ctx = { hub = hub, root = CFrame.new(), parent = model }
			if not tryMeshes(ctx, what, part.Slot, design, 0) then
				if part.Slot == "Layer" then
					buildLayer(ctx, design)
				elseif part.Slot == "Disc" then
					buildDisc(ctx, design)
				else
					buildDriver(ctx, design)
				end
			end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("WeldConstraint") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	return model
end

return BeyVisuals
]=====])
install('RS', '', 'ModuleScript', 'GameConfig', [=====[
--!nonstrict
-- GameConfig: tuning for combat, battles, the villain, progression and saving. Pure data (no Roblox APIs).
-- Movement tuning stays in BeyConfig.Movement; parts, rarities and crate odds stay in BeyConfig.

local GameConfig = {}

-- What each stat does (bey stats = the three parts' stats x the level multiplier; see BeyConfig.ComputeStats):
--   Attack   more damage dealt per hit (AttackScale per point) and a little more top speed
--   Defense  less damage taken (DefenseScale per point) and less knockback taken
--   Stamina  a bigger spin pool (SpinPerStamina per point) and slower passive spin loss
--   Balance  less knockback taken and less self-damage when your slam lands, and a little more top speed
GameConfig.Combat = {
	BaseSpin = 100, -- spin pool before Stamina
	SpinPerStamina = 4,
	BaseDrain = 0.9, -- spin lost per second just by spinning
	DrainReductionPerStamina = 0.02, -- each Stamina point slows that drain by 2% (capped)
	MaxDrainReduction = 0.6,

	ContactDistance = 4.4, -- centres closer than this = the beys are touching (bodies are 4-stud balls)
	SeparationDistance = 5.4, -- must separate this far before the same pair can register a new hit
	HitCooldown = 0.35, -- and at least this long between hits for the same pair
	MinImpactSpeed = 6, -- closing speeds below this are a nudge, not a hit
	DamagePerSpeed = 0.42, -- damage per stud/s of closing speed above the minimum
	MinHitDamage = 1,
	MaxHitDamage = 22,
	AttackScale = 0.04,
	DefenseScale = 0.04,
	KnockbackPerSpeed = 1.0,
	MaxKnockback = 80,
	KnockbackResistPerPoint = 0.02, -- per point of Defense + Balance, capped
	MaxKnockbackResist = 0.6,

	SlamRadius = 9, -- a landing slam hits beys within this distance
	SlamMinFallSpeed = 45, -- the server must have seen the slammer falling at least this fast
	SlamFallWindow = 0.6, -- ... within this many seconds before the landing report
	SlamBaseDamage = 10,
	SlamDamagePerSpeed = 0.1,
	SlamMaxDamage = 26,
	SlamKnockback = 55,
	SlamRecoil = 3, -- spin the slammer itself loses, reduced by Balance
	SlamCooldown = 1.0, -- server-side minimum between accepted slams (client cooldown is longer)

	RequestsPerSecond = 8, -- rate limit for battle requests from one player
	LowSpinFraction = 0.25, -- below this the HUD warns and the bey wobbles
	VisualSpinMin = 6, -- cosmetic hub spin (rad/s) at 0 spin and at full spin
	VisualSpinMax = 40,
}

GameConfig.Battle = {
	Countdown = 3,
	Duration = 90, -- then the higher spin share wins
	DrawMargin = 0.02, -- spin shares this close at timeout = draw
	ResultTimeout = 45, -- the result screen closes itself after this
	RingOutRadius = 42.5, -- past the rim (42): a bey inside the bowl never gets beyond ~41, one on the rim ledge is out
	RingOutBelowY = -10,
	RingOutGrace = 0.4, -- seconds a bey must stay outside before it counts (falling below the floor counts at once)
	StartRadius = 12, -- where the two beys start, either side of the centre
}

-- The skill launch during the countdown (see Core/LaunchCore.lua).
GameConfig.Launch = {
	Period = 1.1, -- seconds for the needle to sweep there and back
	ZoneMin = 0.55, -- the green zone's centre is somewhere in this range, different each battle
	ZoneMax = 0.85,
	GreenHalf = 0.06, -- half-width of the green (perfect) zone, as a share of the bar
	YellowHalf = 0.15, -- half-width of green + yellow (good)
	Good = 0.6, -- quality at the outer edge of yellow (rises to 1 at the green edge)
	Miss = 0.3, -- quality outside the zone
	NoPress = 0.25, -- quality if you never press
	MaxLatency = 0.6, -- the server accepts a press stamped up to this many seconds before it arrived
	SpinAtWorst = 0.7, -- start with 70% spin at quality 0 ... 100% at a perfect launch
	SpeedAtWorst = 18, -- launch speed off the line at quality 0 ...
	SpeedAtBest = 75, -- ... and at a perfect launch
	BoostAtBest = 0.35, -- +35% top speed right after a perfect launch ...
	BoostTime = 4, -- ... fading to nothing over this many seconds
}

-- Specials and Awakening in battle (per-special numbers live in BeyConfig.Specials; see Core/SpecialsCore.lua).
GameConfig.Specials = {
	FirstUseDelay = 2.5, -- seconds after LET IT RIP before specials can be used
	-- Awakening: a meter that fills during the battle; when full, press R to awaken your spirit (once per battle).
	MeterMax = 100,
	MeterPerSecond = 1.0, -- passive fill
	MeterPerDamageDealt = 2.4, -- per point of spin you knock off the foe
	MeterPerDamageTaken = 1.6, -- per point you lose to hits (comebacks)
	AwakenDuration = 10,
	AwakenAttack = 1.25, -- damage dealt x
	AwakenDefense = 1.25, -- damage and knockback taken / this
	AwakenSpeed = 1.1, -- top speed x
}

GameConfig.Difficulty = {
	-- Speed: villain top-speed multiplier. Windup: seconds of warning before an attack. Aggression: 0..1 how often it
	-- attacks when in range. Damage: multiplier on its hits. Reward: multiplier on rewards for beating it.
	-- Launch: how well it times its launch (0..1, with a little noise).
	Easy = { Speed = 0.85, Windup = 1.0, Aggression = 0.45, Damage = 0.8, Reward = 0.8, Launch = 0.5 },
	Normal = { Speed = 0.95, Windup = 0.75, Aggression = 0.7, Damage = 1.0, Reward = 1.0, Launch = 0.72 },
	Hard = { Speed = 1.08, Windup = 0.55, Aggression = 0.95, Damage = 1.15, Reward = 1.5, Launch = 0.92 },
}

GameConfig.Villain = {
	Id = "rook",
	Name = "Rook the Grinder",
	Parts = { Layer = "layer_skyrend", Disc = "disc_bulwarkring", Driver = "driver_spikegrip" }, -- all Uncommon
	Spirit = "spirit_thornstag",
	Specials = { "special_cometdrive", "special_quakestomp" },
	Level = 3,
	Difficulty = "Normal",
	-- After this many wins against it, the next rematch uses Hard (shown to the player).
	HardAfterWins = 3,
}

GameConfig.Progression = {
	MaxLevel = 50, -- matches BeyConfig.MaxLevel
	XPCurveBase = 60, -- XP needed for level L is XPCurveBase * (L-1)^1.6 (rounded)
	XPCurvePower = 1.6,
	Rewards = { -- per battle outcome, before the difficulty multiplier
		win = { XP = 40, Shards = 30 },
		loss = { XP = 15, Shards = 8 },
		draw = { XP = 25, Shards = 15 },
	},
	-- The Workshop sells parts for Shards (earned only by playing). This is the deterministic route to the cap:
	-- every rarity up to Legendary can be bought, and level 50 gives the full level multiplier. Ultra Legendary is
	-- never sold for Shards (it is the paid tier, and paid crates are disabled for now).
	Prices = { Common = 20, Uncommon = 60, Rare = 150, Epic = 350, Legendary = 800 },
	RecentBattleMemory = 30, -- battle ids remembered per player to refuse duplicate rewards
	MinLossSecondsForReward = 20, -- a loss pays nothing if the battle lasted less than this (stops ring-out farming)
}

GameConfig.Data = {
	StoreName = "SpinforgePlayers_v1",
	AutosaveInterval = 120,
	LockTimeout = 600, -- a session lock older than this (seconds) is treated as abandoned
	LoadAttempts = 4,
	RetryWait = 2,
}

return GameConfig
]=====])
install('RS', '', 'ModuleScript', 'Net', [=====[
--!nonstrict
-- Net: the game's remotes, in one place. The server creates them (idempotent: safe after a re-install or a
-- script restart); clients wait for them with a time limit and a clear error instead of hanging forever.
--
-- Client -> server
--   Request      RemoteEvent    { action = "rematch" | "leave" | "forfeit" | "exitPractice" | "setting" | "tutorialDone", ... }
--   SlamLanded   RemoteEvent    (no arguments: the server checks the fall it observed itself)
--   Workshop     RemoteFunction { action = "buy" | "equip", part = id } -> { ok, reason, profile }
-- Server -> client
--   BattleEvent  RemoteEvent    { kind = "queued" | "countdown" | "started" | "hit" | "slam" | "finished" | "closed" | "openWorkshop", ... }
--   Knockback    RemoteEvent    Vector3 velocity change for the client-owned bey
--   Profile      RemoteEvent    PlayerData.snapshot
--   Toast        RemoteEvent    string

local Net = {}

Net.FOLDER = "SpinforgeRemotes"
Net.EVENTS = { "Request", "SlamLanded", "BattleEvent", "Knockback", "Profile", "Toast" }
Net.FUNCTIONS = { "Workshop" }

function Net.setup(replicatedStorage)
	local folder = replicatedStorage:FindFirstChild(Net.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Net.FOLDER
		folder.Parent = replicatedStorage
	end
	local remotes = {}
	for _, name in ipairs(Net.EVENTS) do
		local r = folder:FindFirstChild(name)
		if not (r and r:IsA("RemoteEvent")) then
			if r then
				r:Destroy()
			end
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
		remotes[name] = r
	end
	for _, name in ipairs(Net.FUNCTIONS) do
		local r = folder:FindFirstChild(name)
		if not (r and r:IsA("RemoteFunction")) then
			if r then
				r:Destroy()
			end
			r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
		remotes[name] = r
	end
	return remotes
end

-- Client side. Returns the remotes table, or nil + message if the server never created them.
function Net.waitFor(replicatedStorage, timeout)
	local folder = replicatedStorage:WaitForChild(Net.FOLDER, timeout)
	if not folder then
		return nil, "the server scripts did not start (no " .. Net.FOLDER .. "). Re-run the installer and check Output for red errors."
	end
	local remotes = {}
	for _, name in ipairs(Net.EVENTS) do
		remotes[name] = folder:WaitForChild(name, timeout)
		if not remotes[name] then
			return nil, "remote " .. name .. " is missing"
		end
	end
	for _, name in ipairs(Net.FUNCTIONS) do
		remotes[name] = folder:WaitForChild(name, timeout)
		if not remotes[name] then
			return nil, "remote " .. name .. " is missing"
		end
	end
	return remotes
end

return Net
]=====])
install('RS', '', 'ModuleScript', 'SpiritMeshData', [=====[
--!nonstrict
-- GENERATED by tools/blender/build_spirits.py. Do not edit by hand.
-- Bounding-box Size of every spirit mesh in Roblox axes (Y up, the creature faces -Z). The game scales them to the
-- height it wants, so only the proportions matter.
return {
	spirit_emberwolf = { Size = Vector3.new(0.5907, 1.0000, 2.0309), Tris = 6000 },
	spirit_tidedrake = { Size = Vector3.new(0.6395, 1.2000, 1.0814), Tris = 5999 },
	spirit_thornstag = { Size = Vector3.new(0.8559, 1.0000, 0.9525), Tris = 6000 },
	spirit_stormroc = { Size = Vector3.new(1.6000, 0.9613, 0.7134), Tris = 5998 },
	spirit_sunmane = { Size = Vector3.new(0.8130, 1.0000, 1.3584), Tris = 5998 },
}
]=====])
install('RS', 'Core', 'ModuleScript', 'BattleCore', [=====[
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

-- Give a side spin back (a heal special), capped at its max. Only while active. Returns the amount applied.
function BattleCore.heal(b, key, amount)
	local s = b.sides[key]
	if b.state ~= "active" or not s or not finite(amount) or amount <= 0 or s.spin <= 0 then
		return 0
	end
	local applied = math.min(amount, s.maxSpin - s.spin)
	s.spin += applied
	return applied
end

-- Changes how fast a side's spin drains (a spirit passive). Before or during the battle.
function BattleCore.setDrain(b, key, drain)
	local s = b.sides[key]
	if s and finite(drain) and drain >= 0 then
		s.drain = drain
	end
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
]=====])
install('RS', 'Core', 'ModuleScript', 'CombatCore', [=====[
--!nonstrict
-- CombatCore: spin, damage, knockback, contact de-duplication, ring-outs and request validation as pure functions.
-- Used by the server's BattleService; the server owns all spin values and outcomes. C is GameConfig.Combat.
-- Unit-tested in tools/tests/combat.test.luau (rules only; not how Roblox reports positions or velocities).

local CombatCore = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
CombatCore.finite = finite

local function finiteVector(v)
	return v ~= nil and type(v) ~= "number" and finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function stat(stats, name)
	local v = stats and stats[name]
	return finite(v) and math.max(v :: number, 0) or 0
end

-------------------------------------------------------------------------------- spin

function CombatCore.maxSpin(stats, C)
	return C.BaseSpin + stat(stats, "Stamina") * C.SpinPerStamina
end

function CombatCore.drainPerSecond(stats, C)
	local reduction = math.min(stat(stats, "Stamina") * C.DrainReductionPerStamina, C.MaxDrainReduction)
	return C.BaseDrain * (1 - reduction)
end

-- Cosmetic hub spin speed for a spin fraction (0..1). Purely visual; never feeds back into combat.
function CombatCore.visualSpin(fraction, C)
	fraction = finite(fraction) and math.clamp(fraction, 0, 1) or 0
	return C.VisualSpinMin + (C.VisualSpinMax - C.VisualSpinMin) * fraction
end

-------------------------------------------------------------------------------- hits

-- Geometry of a contact between A and B from server-observed positions and velocities.
-- Returns n (unit vector A->B), closing speed (>= 0), and A's share of the closing speed (0..1).
function CombatCore.contact(posA, velA, posB, velB)
	local d = posB - posA
	local dist = d.Magnitude
	if dist < 1e-4 or not finite(dist) then
		return nil, 0, 0.5
	end
	local n = d / dist
	local aIn = math.max(velA:Dot(n), 0) -- how hard A drives into B
	local bIn = math.max(-velB:Dot(n), 0) -- how hard B drives into A
	local closing = aIn + bIn
	if not finite(closing) then
		return n, 0, 0.5
	end
	local share = closing > 1e-6 and aIn / closing or 0.5
	return n, closing, share
end

-- Damage the defender takes in a body contact. attackerShare is the attacker's part of the closing speed;
-- even a stationary bey deals some damage (0.4 of the base), the one driving in deals up to 1.6x.
function CombatCore.hitDamage(attacker, defender, closing, attackerShare, C)
	if not finite(closing) or closing <= C.MinImpactSpeed then
		return 0
	end
	attackerShare = finite(attackerShare) and math.clamp(attackerShare, 0, 1) or 0.5
	local base = (closing - C.MinImpactSpeed) * C.DamagePerSpeed
	local atk = 1 + stat(attacker, "Attack") * C.AttackScale
	local def = 1 + stat(defender, "Defense") * C.DefenseScale
	local dmg = base * (0.4 + 1.2 * attackerShare) * atk / def
	return math.clamp(dmg, C.MinHitDamage, C.MaxHitDamage)
end

-- Knockback speed (studs/s) the defender receives along the contact normal.
function CombatCore.knockback(attacker, defender, closing, C)
	if not finite(closing) or closing <= C.MinImpactSpeed then
		return 0
	end
	local resist = math.min((stat(defender, "Defense") + stat(defender, "Balance")) * C.KnockbackResistPerPoint, C.MaxKnockbackResist)
	local power = 1 + stat(attacker, "Attack") * C.AttackScale
	return math.clamp(closing * C.KnockbackPerSpeed * power * (1 - resist), 0, C.MaxKnockback)
end

-- Slam damage to a defender `distance` away, from the fall speed the server itself observed.
function CombatCore.slamDamage(attacker, defender, fallSpeed, distance, C)
	if not finite(fallSpeed) or not finite(distance) or fallSpeed < C.SlamMinFallSpeed or distance > C.SlamRadius or distance < 0 then
		return 0
	end
	local falloff = 1 - 0.5 * (distance / C.SlamRadius) -- full at the centre, half at the edge
	local atk = 1 + stat(attacker, "Attack") * C.AttackScale
	local def = 1 + stat(defender, "Defense") * C.DefenseScale
	local dmg = (C.SlamBaseDamage + (fallSpeed - C.SlamMinFallSpeed) * C.SlamDamagePerSpeed) * falloff * atk / def
	return math.clamp(dmg, 0, C.SlamMaxDamage)
end

function CombatCore.slamRecoil(attacker, C)
	return C.SlamRecoil * (1 - math.min(stat(attacker, "Balance") * C.KnockbackResistPerPoint, C.MaxKnockbackResist))
end

-------------------------------------------------------------------------------- contact de-duplication

-- Tracks each pair of beys so continuous contact (grinding against each other) only counts once: a pair must
-- separate past SeparationDistance AND wait HitCooldown before it can score again.
function CombatCore.newContacts()
	return {}
end

local function pairKey(a, b)
	a, b = tostring(a), tostring(b)
	if a < b then
		return a .. "|" .. b
	end
	return b .. "|" .. a
end

-- Returns true when this frame's contact should count as a new hit.
function CombatCore.contactStep(tracker, a, b, distance, now, C)
	local key = pairKey(a, b)
	local s = tracker[key]
	if not s then
		s = { touching = false, lastHit = -math.huge }
		tracker[key] = s
	end
	if not finite(distance) then
		return false
	end
	if distance <= C.ContactDistance then
		if not s.touching and now - s.lastHit >= C.HitCooldown then
			s.touching = true
			s.lastHit = now
			return true
		end
		s.touching = true
		return false
	elseif distance >= C.SeparationDistance then
		s.touching = false
	end
	return false
end

-------------------------------------------------------------------------------- ring-out, fall tracking, validation

function CombatCore.isRingOut(pos, B)
	if not finiteVector(pos) then
		return true
	end
	local flat = math.sqrt(pos.X * pos.X + pos.Z * pos.Z)
	return flat > B.RingOutRadius or pos.Y < B.RingOutBelowY
end

-- Ring-out with a short grace: a bey must stay outside for B.RingOutGrace seconds (a launch that pokes past the
-- rim and steers back in survives). Falling below the floor counts at once. timers: table kept per battle.
function CombatCore.ringOutStep(timers, key, pos, now, B)
	if not finiteVector(pos) or pos.Y < B.RingOutBelowY then
		return true
	end
	if CombatCore.isRingOut(pos, B) then
		timers[key] = timers[key] or now
		return now - timers[key] >= B.RingOutGrace
	end
	timers[key] = nil
	return false
end

-- Rolling record of the fastest downward speed the SERVER saw for a bey, so slam claims are checked against it.
function CombatCore.newFallTracker()
	return { samples = {} }
end

function CombatCore.recordFall(t, vy, now, window)
	if not finite(vy) then
		return
	end
	table.insert(t.samples, { at = now, down = math.max(-vy, 0) })
	while #t.samples > 0 and now - t.samples[1].at > window do
		table.remove(t.samples, 1)
	end
end

function CombatCore.maxFall(t, now, window)
	local best = 0
	for _, s in ipairs(t.samples) do
		if now - s.at <= window and s.down > best then
			best = s.down
		end
	end
	return best
end

-- Simple per-key rate limiter: at most `perSecond` allowed calls in any rolling second.
function CombatCore.newRateLimiter(perSecond)
	return { perSecond = perSecond, hits = {} }
end

function CombatCore.allow(rl, key, now)
	local list = rl.hits[key]
	if not list then
		list = {}
		rl.hits[key] = list
	end
	while #list > 0 and now - list[1] > 1 do
		table.remove(list, 1)
	end
	if #list >= rl.perSecond then
		return false
	end
	table.insert(list, now)
	return true
end

function CombatCore.forget(rl, key)
	rl.hits[key] = nil
end

return CombatCore
]=====])
install('RS', 'Core', 'ModuleScript', 'LaunchCore', [=====[
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
]=====])
install('RS', 'Core', 'ModuleScript', 'MovementCore', [=====[
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
]=====])
install('RS', 'Core', 'ModuleScript', 'PlayerData', [=====[
--!nonstrict
-- PlayerData: the versioned save format, migration from older versions, and repair of bad values. Pure.
-- Version 2 fields (v1 had no Spirit/Special1/Special2; migrating fills them from the starter loadout):
--   Version, XP, Shards, Owned {itemId = true}, Equipped {Layer, Disc, Driver, Spirit, Special1, Special2},
--   Record {Wins, Losses, Draws},
--   RecentBattles {battleId...} (refuses duplicate rewards), Settings {CameraShake, ReducedEffects, TutorialDone}
-- A save written by a NEWER version is never migrated or overwritten (migrate returns nil, "newer").

local PlayerData = {}
PlayerData.VERSION = 2

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function count(n)
	return finite(n) and n >= 0 and math.floor(n) or 0
end

-- What kind of item an equipped slot holds (Special1 and Special2 both hold specials).
local function slotKind(slot)
	if slot == "Special1" or slot == "Special2" then
		return "Special"
	end
	return slot
end
PlayerData.slotKind = slotKind

-- starter: the starting loadout { Layer, Disc, Driver, Spirit, Special1, Special2 } (item ids)
function PlayerData.new(starter)
	local owned = {}
	for _, id in pairs(starter) do
		owned[id] = true
	end
	return {
		Version = PlayerData.VERSION,
		XP = 0,
		Shards = 0,
		Owned = owned,
		Equipped = table.clone(starter),
		Record = { Wins = 0, Losses = 0, Draws = 0 },
		RecentBattles = {},
		Settings = { CameraShake = true, ReducedEffects = false, TutorialDone = false },
	}
end

-- Repair a table in place: unknown items dropped, starter items always owned, equipped items owned and of the
-- right kind (else the starter item), the two specials different, counters non-negative integers, settings booleans.
local function repair(d, starter, parts, recentMax)
	d.XP = count(d.XP)
	d.Shards = count(d.Shards)
	local owned = {}
	if type(d.Owned) == "table" then
		for id, v in pairs(d.Owned) do
			if v == true and parts[id] then
				owned[id] = true
			end
		end
	end
	for _, id in pairs(starter) do
		owned[id] = true
	end
	d.Owned = owned
	local eq = type(d.Equipped) == "table" and d.Equipped or {}
	local fixed = {}
	for slot, starterId in pairs(starter) do
		local id = eq[slot]
		if type(id) == "string" and owned[id] and parts[id] and parts[id].Slot == slotKind(slot) then
			fixed[slot] = id
		else
			fixed[slot] = starterId
		end
	end
	if fixed.Special1 and fixed.Special1 == fixed.Special2 then
		fixed.Special2 = fixed.Special1 == starter.Special2 and starter.Special1 or starter.Special2
	end
	d.Equipped = fixed
	local rec = type(d.Record) == "table" and d.Record or {}
	d.Record = { Wins = count(rec.Wins), Losses = count(rec.Losses), Draws = count(rec.Draws) }
	local recent = {}
	if type(d.RecentBattles) == "table" then
		for _, id in ipairs(d.RecentBattles) do
			if type(id) == "string" then
				table.insert(recent, id)
			end
		end
	end
	while #recent > recentMax do
		table.remove(recent, 1)
	end
	d.RecentBattles = recent
	local s = type(d.Settings) == "table" and d.Settings or {}
	d.Settings = {
		CameraShake = s.CameraShake ~= false,
		ReducedEffects = s.ReducedEffects == true,
		TutorialDone = s.TutorialDone == true,
	}
	d.Version = PlayerData.VERSION
	return d
end

-- raw: whatever was stored (nil for a new player). Returns data, or nil + reason ("corrupt" | "newer").
function PlayerData.migrate(raw, starter, parts, recentMax)
	recentMax = recentMax or 30
	if raw == nil then
		return PlayerData.new(starter)
	end
	if type(raw) ~= "table" then
		return nil, "corrupt"
	end
	local version = raw.Version
	if version == nil then
		version = 0
	end
	if not finite(version) then
		return nil, "corrupt"
	end
	if version > PlayerData.VERSION then
		return nil, "newer"
	end
	local d = raw
	if version < 1 then
		-- v0 (development saves before versioning): { xp, shards, parts = {id...}, equipped = {...} }
		local owned = {}
		if type(raw.parts) == "table" then
			for _, id in ipairs(raw.parts) do
				owned[id] = true
			end
		end
		d = {
			XP = raw.xp,
			Shards = raw.shards,
			Owned = owned,
			Equipped = raw.equipped,
		}
	end
	return repair(d, starter, parts, recentMax)
end

-- What the client is allowed to see (no battle ids).
function PlayerData.snapshot(d, level, saveStatus)
	local owned = {}
	for id in pairs(d.Owned) do
		table.insert(owned, id)
	end
	table.sort(owned)
	return {
		XP = d.XP,
		Level = level,
		Shards = d.Shards,
		Owned = owned,
		Equipped = table.clone(d.Equipped),
		Record = { Wins = d.Record.Wins, Losses = d.Record.Losses, Draws = d.Record.Draws },
		Settings = { CameraShake = d.Settings.CameraShake, ReducedEffects = d.Settings.ReducedEffects, TutorialDone = d.Settings.TutorialDone },
		SaveStatus = saveStatus,
	}
end

return PlayerData
]=====])
install('RS', 'Core', 'ModuleScript', 'Progression', [=====[
--!nonstrict
-- Progression: XP, levels, Shards (earned currency), battle rewards, the Workshop and equipping, as pure functions
-- over a player-data table (see PlayerData). The server calls these; the client only ever sees the results.
-- P = GameConfig.Progression, parts = BeyConfig.Parts. Tested in tools/tests/progression.test.luau.
--
-- How free play reaches the cap: rarity budgets differ (Common 8 ... Legendary 30 per part), so leveling alone
-- can NOT turn a Common part into a Legendary one. The free route is the Workshop: every rarity up to Legendary is
-- sold for Shards, and Shards come only from battles. A full Legendary set at level 50 is the grindable cap.
-- Ultra Legendary (+10% over that cap) is never sold for Shards; it is the paid tier (crates are disabled for now).

local Progression = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function Progression.xpForLevel(level, P)
	if level <= 1 then
		return 0
	end
	return math.floor(P.XPCurveBase * (level - 1) ^ P.XPCurvePower + 0.5)
end

function Progression.levelFromXP(xp, P)
	if not finite(xp) or xp <= 0 then
		return 1
	end
	local level = 1
	while level < P.MaxLevel and xp >= Progression.xpForLevel(level + 1, P) do
		level += 1
	end
	return level
end

-- outcome: "win" | "loss" | "draw"; difficulty: a key of GameConfig.Difficulty.
function Progression.battleReward(outcome, difficulty, P, D)
	local base = P.Rewards[outcome]
	if not base then
		return nil
	end
	local mult = (D and D[difficulty] and D[difficulty].Reward) or 1
	return { Outcome = outcome, XP = math.floor(base.XP * mult + 0.5), Shards = math.floor(base.Shards * mult + 0.5) }
end

-- Grants a battle's reward once. battleId must be unique per battle; a repeated id is refused.
-- Returns ok, reason_or_info. info = { levelBefore, levelAfter }.
function Progression.grantBattleReward(data, battleId, reward, P)
	if type(battleId) ~= "string" or battleId == "" or type(reward) ~= "table" then
		return false, "invalid"
	end
	if not (finite(reward.XP) and finite(reward.Shards)) or reward.XP < 0 or reward.Shards < 0 then
		return false, "invalid"
	end
	for _, id in ipairs(data.RecentBattles) do
		if id == battleId then
			return false, "duplicate"
		end
	end
	table.insert(data.RecentBattles, battleId)
	while #data.RecentBattles > P.RecentBattleMemory do
		table.remove(data.RecentBattles, 1)
	end
	local before = Progression.levelFromXP(data.XP, P)
	data.XP += math.floor(reward.XP)
	data.Shards += math.floor(reward.Shards)
	local key = reward.Outcome == "win" and "Wins" or reward.Outcome == "loss" and "Losses" or "Draws"
	data.Record[key] = (data.Record[key] or 0) + 1
	return true, { levelBefore = before, levelAfter = Progression.levelFromXP(data.XP, P) }
end

-- Workshop price in Shards, or nil if the part can't be bought with Shards.
function Progression.price(partId, parts, P)
	local part = parts[partId]
	return part and P.Prices[part.Rarity] or nil
end

function Progression.buy(data, partId, parts, P, inBattle)
	if inBattle then
		return false, "in_battle"
	end
	local part = parts[partId]
	if not part then
		return false, "unknown_part"
	end
	if data.Owned[partId] then
		return false, "owned"
	end
	local cost = Progression.price(partId, parts, P)
	if not cost then
		return false, "not_for_sale"
	end
	if data.Shards < cost then
		return false, "cant_afford"
	end
	data.Shards -= cost
	data.Owned[partId] = true
	return true, cost
end

-- Equip an owned item into its slot. Never during a battle. parts = BeyConfig.Items (parts, spirits, specials).
-- Specials have two slots: `slot` picks "Special1" or "Special2" (default Special1). Equipping the special that is
-- already in the other slot swaps the two.
function Progression.equip(data, partId, parts, inBattle, slot)
	if inBattle then
		return false, "in_battle"
	end
	local part = parts[partId]
	if not part then
		return false, "unknown_part"
	end
	if not data.Owned[partId] then
		return false, "not_owned"
	end
	if part.Slot == "Special" then
		slot = (slot == "Special2") and "Special2" or "Special1"
		local other = slot == "Special1" and "Special2" or "Special1"
		if data.Equipped[other] == partId then
			data.Equipped[other] = data.Equipped[slot]
		end
		data.Equipped[slot] = partId
		return true
	end
	data.Equipped[part.Slot] = partId
	return true
end

-- Human-readable text for the reasons above (shown in the Workshop).
Progression.ReasonText = {
	in_battle = "You can't change parts during a battle.",
	unknown_part = "That part doesn't exist.",
	not_owned = "You don't own that part yet.",
	owned = "You already own that part.",
	not_for_sale = "That part isn't sold in the Workshop.",
	cant_afford = "Not enough Shards yet. Win battles to earn more.",
	invalid = "Something went wrong. Try again.",
	duplicate = "That reward was already given.",
}

return Progression
]=====])
install('RS', 'Core', 'ModuleScript', 'SessionStore', [=====[
--!nonstrict
-- SessionStore: loading and saving player data safely, independent of Roblox. The server passes a store adapter;
-- tests pass a mock. Stored value: { Data = <PlayerData v1>, Lock = { Job = serverId, Time = seconds } | nil }.
--
-- Adapter contract: store:update(key, transform) -> ok (bool), valueOrErr
--   transform(old) returns the new value, or nil to cancel (then ok = true, value = nil). It may run more than once.
--
-- Rules:
--   * A load takes a session lock. If another live server holds it, retry; after LockTimeout the lock is stale and
--     is taken over. If it is still held after all attempts, the result is "locked" and the session must not save.
--   * A failed load NEVER produces a fresh profile that later overwrites the real one: the caller marks the session
--     "nosave" and keeps the player's real data untouched.
--   * Saves only happen while we still hold the lock; if another server took it, the save is refused ("lost_lock").
--   * A save written by a newer game version is never overwritten ("unsupported").

local SessionStore = {}

-- opts: { attempts, wait = function(seconds), now = function() -> seconds, lockTimeout, migrate = function(raw) }
-- Returns status ("ok" | "locked" | "failed" | "unsupported"), data (when ok), detail.
function SessionStore.load(store, key, jobId, opts)
	local lastErr
	local wasLocked = false
	for attempt = 1, opts.attempts do
		local lockedBy, migrateErr = nil, nil
		local ok, value = store:update(key, function(old)
			lockedBy, migrateErr = nil, nil
			local now = opts.now()
			if type(old) == "table" and type(old.Lock) == "table" and old.Lock.Job ~= jobId then
				local t = old.Lock.Time
				if type(t) == "number" and now - t < opts.lockTimeout then
					lockedBy = old.Lock.Job
					return nil
				end
			end
			local raw = type(old) == "table" and old.Data or nil
			local data, err = opts.migrate(raw)
			if not data then
				migrateErr = err
				return nil
			end
			return { Data = data, Lock = { Job = jobId, Time = now } }
		end)
		if ok and value ~= nil then
			return "ok", value.Data
		end
		if ok and migrateErr then
			return "unsupported", nil, migrateErr -- never retried, never overwritten
		end
		if ok and lockedBy then
			wasLocked = true
			lastErr = "locked by " .. tostring(lockedBy)
		else
			lastErr = tostring(value)
		end
		if attempt < opts.attempts then
			opts.wait(opts.retryWait or 1)
		end
	end
	return wasLocked and "locked" or "failed", nil, lastErr
end

-- Returns "ok" | "lost_lock" | "error", detail.
function SessionStore.save(store, key, jobId, data, opts, release)
	local lost = false
	local ok, value = store:update(key, function(old)
		lost = false
		if type(old) == "table" and type(old.Lock) == "table" and old.Lock.Job ~= jobId then
			lost = true
			return nil
		end
		return { Data = data, Lock = (not release) and { Job = jobId, Time = opts.now() } or nil }
	end)
	if not ok then
		return "error", tostring(value)
	end
	if lost then
		return "lost_lock"
	end
	return "ok"
end

return SessionStore
]=====])
install('RS', 'Core', 'ModuleScript', 'SpecialsCore', [=====[
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
]=====])
install('SSS', '', 'ModuleScript', 'BattleService', [=====[
--!nonstrict
-- BattleService: the player-vs-villain battle in the Arena. The SERVER owns spin, hits, outcomes and rewards.
--   Challenge prompt -> (queue if the arena is busy) -> countdown (both beys frozen) -> active -> finished
--   -> result screen (Rematch / Leave, or it closes itself) -> cleanup (beys removed, avatar restored)
-- What the server trusts from the client: only the player's bey position/velocity (client-owned physics, which a
-- cheater could fake), a bare "my slam landed" signal (checked against the fall the server observed), and the time
-- the player pressed LAUNCH (checked against the meter's window; the server judges the timing itself), and
-- "use special 1/2" / "awaken" requests (the server checks the loadout, cooldowns and meter; see SpecialsCore).
-- Clients never send damage, results, XP or Shards. See HANDOFF.md "Residual exploit exposure".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local GameConfig = require(Shared.GameConfig)
local CombatCore = require(Shared.Core.CombatCore)
local BattleCore = require(Shared.Core.BattleCore)
local Progression = require(Shared.Core.Progression)
local LaunchCore = require(Shared.Core.LaunchCore)
local SpecialsCore = require(Shared.Core.SpecialsCore)
local BeyConfig = require(Shared.BeyConfig)

local BeyFactory = require(script.Parent.BeyFactory)
local BeyService = require(script.Parent.BeyService)
local DataService = require(script.Parent.DataService)
local VillainAI = require(script.Parent.VillainAI)
local World = require(script.Parent.World)

local C, B, V, P, L, A = GameConfig.Combat, GameConfig.Battle, GameConfig.Villain, GameConfig.Progression, GameConfig.Launch, GameConfig.Specials
local SNAPSHOT_EVERY = 0.2 -- seconds between specials/awakening HUD updates sent to the player

local BattleService = {}

local remotes
local current = nil -- the one active battle record, or nil
local queue = {} -- players waiting for the arena
local requestLimiter = CombatCore.newRateLimiter(C.RequestsPerSecond)

local function send(player, payload)
	if player and player.Parent then
		remotes.BattleEvent:FireClient(player, payload)
	end
end

local function difficultyFor(player)
	local data = DataService.get(player)
	local wins = data and data.Record.Wins or 0
	return wins >= V.HardAfterWins and "Hard" or V.Difficulty
end

function BattleService.inBattle(player)
	return current ~= nil and current.player == player
end

local function setBattleAttrs(player, state, endsAt)
	if player.Parent then
		player:SetAttribute("BattleState", state)
		player:SetAttribute("BattleEndsAt", endsAt or 0)
	end
end

local function removeFromQueue(player)
	for i = #queue, 1, -1 do
		if queue[i] == player then
			table.remove(queue, i)
		end
	end
end

local startBattle -- forward

local function cleanup(rec, rematch)
	if current ~= rec then
		return
	end
	current = nil
	if rec.ai then
		rec.ai:destroy()
	end
	if rec.villain and rec.villain.model then
		rec.villain.model:Destroy()
	end
	local player = rec.player
	if player.Parent then
		setBattleAttrs(player, "", 0)
		send(player, { kind = "closed" })
		if rematch and #queue == 0 then
			BeyService.removeBey(player)
			player:SetAttribute("Mode", "OnFoot") -- startBattle re-enters bey mode straight away
			startBattle(player)
			if current == nil or current.player ~= player then
				BeyService.exit(player) -- the restart didn't happen: never leave the avatar frozen
			end
		elseif rematch then
			-- Others are waiting: go to the back of the line instead of jumping it.
			BeyService.exit(player)
			table.insert(queue, player)
		else
			BeyService.exit(player)
		end
	end
	-- Next in line.
	while not current and #queue > 0 do
		local nextPlayer = table.remove(queue, 1)
		if nextPlayer.Parent and BeyService.mode(nextPlayer) == "OnFoot" then
			startBattle(nextPlayer)
		elseif nextPlayer.Parent then
			remotes.Toast:FireClient(nextPlayer, "Your turn in the arena came up while you were practicing. Challenge again when you're ready.")
		end
	end
	for i, p in ipairs(queue) do
		send(p, { kind = "queued", position = i })
	end
end

local function finishBattle(rec, result, now)
	local player = rec.player
	setBattleAttrs(player, "finished", 0)
	local outcome = result.outcomes.player
	local rewardText, levelUp = nil, nil
	if BattleCore.claimRewards(rec.battle) and player.Parent then
		local activeFor = now - (rec.startedAt or now)
		local reward = Progression.battleReward(outcome, rec.difficulty, P, GameConfig.Difficulty)
		-- No reward for quitting, and none for a loss that took almost no time (stops farming quick ring-outs).
		if result.reason == "left" or (outcome == "loss" and activeFor < P.MinLossSecondsForReward) then
			reward = { Outcome = outcome, XP = 0, Shards = 0 }
		end
		local data = DataService.get(player)
		if data and reward then
			local ok, info = Progression.grantBattleReward(data, rec.id, reward, P)
			if ok then
				DataService.markDirty(player)
				rewardText = reward
				if info.levelAfter > info.levelBefore then
					levelUp = info.levelAfter
				end
				DataService.sendProfile(player)
			end
		end
	end
	if rec.ai then
		rec.ai:setTelegraph(nil)
	end
	send(player, {
		kind = "finished",
		outcome = outcome,
		reason = result.reason,
		reward = rewardText,
		levelUp = levelUp,
		next = difficultyFor(player),
		closesIn = B.ResultTimeout,
	})
end

startBattle = function(player)
	if not player.Parent or not DataService.isReady(player) then
		return
	end
	if BeyService.mode(player) ~= "OnFoot" then
		return
	end
	if current then
		if not table.find(queue, player) then
			table.insert(queue, player)
		end
		send(player, { kind = "queued", position = table.find(queue, player) })
		return
	end
	local now = os.clock()
	local center = World.ARENA_CENTER
	local difficulty = difficultyFor(player)
	local diff = GameConfig.Difficulty[difficulty]
	local playerAt = CFrame.lookAt(center + Vector3.new(0, 5, B.StartRadius), center + Vector3.new(0, 5, 0))
	local villainAt = CFrame.lookAt(center + Vector3.new(0, 5, -B.StartRadius), center + Vector3.new(0, 5, 0))

	local mine = BeyService.enter(player, "Battle", playerAt, true, center)
	if not mine then
		return
	end
	local villain = BeyFactory.build({
		name = "villain_" .. V.Id,
		partIds = V.Parts,
		level = V.Level,
		cframe = villainAt,
		parent = BeyService.folder(),
	})
	villain.body.Anchored = true
	villain.model:SetAttribute("Villain", true)
	villain.model:SetAttribute("DisplayName", V.Name)

	local rec = {
		id = HttpService:GenerateGUID(false),
		player = player,
		mine = mine,
		villain = villain,
		difficulty = difficulty,
		diff = diff,
		contacts = CombatCore.newContacts(),
		villainFall = CombatCore.newFallTracker(),
		outTimers = {},
		startedAt = nil,
		-- Skill launch: the meter runs on the shared server clock during the countdown.
		meter = LaunchCore.newMeter(Workspace:GetServerTimeNow(), B.Countdown, Random.new():NextNumber(), L),
		launch = {}, -- side -> { quality, label }
		snapshotAt = 0,
	}
	local equipped = (DataService.get(player) or {}).Equipped or BeyConfig.StarterLoadout
	rec.specials = {
		player = SpecialsCore.newSide(equipped, BeyConfig.Items),
		villain = SpecialsCore.newSide({ Spirit = V.Spirit, Special1 = V.Specials[1], Special2 = V.Specials[2] }, BeyConfig.Items),
	}
	rec.spirits = { player = equipped.Spirit, villain = V.Spirit }
	rec.battle = BattleCore.new(rec.id, {
		{ key = "player", maxSpin = mine.maxSpin, drain = CombatCore.drainPerSecond(mine.stats, C) },
		{ key = "villain", maxSpin = villain.maxSpin, drain = CombatCore.drainPerSecond(villain.stats, C) },
	}, B, now)
	for key, side in pairs(rec.specials) do
		BattleCore.setDrain(rec.battle, key, rec.battle.sides[key].drain * SpecialsCore.drain(side))
	end
	rec.ai = VillainAI.new(villain, diff, center, { BeyService.folder() })
	-- The villain's launch is decided now (its skill depends on difficulty).
	local vq = LaunchCore.villainQuality(diff.Launch or 0.7, Random.new():NextNumber())
	rec.launch.villain = { quality = vq, label = vq >= 0.95 and "PERFECT" or vq >= L.Good and "GOOD" or "WEAK" }
	BattleCore.setStartSpin(rec.battle, "villain", LaunchCore.effects(vq, L).spinFraction)
	current = rec
	removeFromQueue(player)
	setBattleAttrs(player, "countdown", 0)
	local m = rec.meter
	send(player, {
		kind = "countdown",
		seconds = B.Countdown,
		foe = V.Name,
		difficulty = difficulty,
		loadout = { spirit = equipped.Spirit, specials = { equipped.Special1, equipped.Special2 } },
		foeLoadout = { spirit = V.Spirit, specials = V.Specials },
		meter = { start = m.start, finish = m.finish, period = m.period, zoneCenter = m.zoneCenter, greenHalf = m.greenHalf, yellowHalf = m.yellowHalf },
	})
end

-- Applies a contact hit between the two beys.
local function resolveContact(rec, now)
	local pb, vb = rec.mine.body, rec.villain.body
	local pPos, vPos = pb.Position, vb.Position
	local dist = (vPos - pPos).Magnitude
	if not CombatCore.contactStep(rec.contacts, "player", "villain", dist, now, C) then
		return
	end
	local pVel, vVel = pb.AssemblyLinearVelocity, vb.AssemblyLinearVelocity
	local n, closing, share = CombatCore.contact(pPos, pVel, vPos, vVel)
	if not n or closing <= C.MinImpactSpeed then
		return
	end
	local sp, sv = rec.specials.player, rec.specials.villain
	local pEmpowered = sp.empower ~= nil and now <= sp.empower.untilT
	local vEmpowered = sv.empower ~= nil and now <= sv.empower.untilT
	local pOut, pKbOut = SpecialsCore.outgoing(sp, now, A, true)
	local vOut, vKbOut = SpecialsCore.outgoing(sv, now, A, true)
	local pIn, pKbIn = SpecialsCore.incoming(sp, now, A)
	local vIn, vKbIn = SpecialsCore.incoming(sv, now, A)
	local dealt = CombatCore.hitDamage(rec.mine.stats, rec.villain.stats, closing, share, C) * pOut * vIn
	local taken = CombatCore.hitDamage(rec.villain.stats, rec.mine.stats, closing, 1 - share, C) * rec.diff.Damage * vOut * pIn
	dealt = BattleCore.damage(rec.battle, "villain", dealt)
	taken = BattleCore.damage(rec.battle, "player", taken)
	SpecialsCore.charge(sp, dealt * A.MeterPerDamageDealt + taken * A.MeterPerDamageTaken, A)
	SpecialsCore.charge(sv, taken * A.MeterPerDamageDealt + dealt * A.MeterPerDamageTaken, A)
	local kbVillain = math.min(CombatCore.knockback(rec.mine.stats, rec.villain.stats, closing, C) * pKbOut * vKbIn, C.MaxKnockback * 2)
	local kbPlayer = math.min(CombatCore.knockback(rec.villain.stats, rec.mine.stats, closing, C) * vKbOut * pKbIn, C.MaxKnockback * 2)
	vb.AssemblyLinearVelocity += (n + Vector3.new(0, 0.25, 0)).Unit * kbVillain
	remotes.Knockback:FireClient(rec.player, (-n + Vector3.new(0, 0.25, 0)).Unit * kbPlayer)
	rec.ai:onHit(now)
	local strength = math.clamp(closing / 60, 0.2, 1)
	if pEmpowered or vEmpowered then
		strength = 1
	end
	send(rec.player, {
		kind = "hit",
		dealt = dealt,
		taken = taken,
		at = (pPos + vPos) / 2,
		normal = n,
		strength = strength,
		crit = pEmpowered or nil,
		foeCrit = vEmpowered or nil,
	})
end

-- The player's slam landed (already validated by BeyService against the observed fall).
local function playerSlam(rec, fall, now)
	local pPos, vPos = rec.mine.body.Position, rec.villain.body.Position
	local d = Vector3.new(vPos.X - pPos.X, 0, vPos.Z - pPos.Z)
	local pOut = SpecialsCore.outgoing(rec.specials.player, now, A, false)
	local vIn = SpecialsCore.incoming(rec.specials.villain, now, A)
	local dmg = CombatCore.slamDamage(rec.mine.stats, rec.villain.stats, fall, d.Magnitude, C) * pOut * vIn
	local recoil = BattleCore.damage(rec.battle, "player", CombatCore.slamRecoil(rec.mine.stats, C))
	local dealt = 0
	if dmg > 0 then
		dealt = BattleCore.damage(rec.battle, "villain", dmg)
		SpecialsCore.charge(rec.specials.player, dealt * A.MeterPerDamageDealt, A)
		local dir = (d.Magnitude > 0.01 and d.Unit or Vector3.new(0, 0, -1)) + Vector3.new(0, 0.6, 0)
		rec.villain.body.AssemblyLinearVelocity += dir.Unit * C.SlamKnockback
		rec.ai:onHit(now)
	end
	send(rec.player, { kind = "slam", hit = dmg > 0, dealt = dealt, recoil = recoil })
end

local function villainSlam(rec, fallSeen, now)
	if rec.battle.state ~= "active" then
		return
	end
	local fall = math.max(fallSeen, CombatCore.maxFall(rec.villainFall, now, C.SlamFallWindow))
	local pPos, vPos = rec.mine.body.Position, rec.villain.body.Position
	local d = Vector3.new(pPos.X - vPos.X, 0, pPos.Z - vPos.Z)
	local vOut = SpecialsCore.outgoing(rec.specials.villain, now, A, false)
	local pIn = SpecialsCore.incoming(rec.specials.player, now, A)
	local dmg = CombatCore.slamDamage(rec.villain.stats, rec.mine.stats, fall, d.Magnitude, C) * rec.diff.Damage * vOut * pIn
	if dmg > 0 then
		local taken = BattleCore.damage(rec.battle, "player", dmg)
		SpecialsCore.charge(rec.specials.player, taken * A.MeterPerDamageTaken, A)
		SpecialsCore.charge(rec.specials.villain, taken * A.MeterPerDamageDealt, A)
		local dir = (d.Magnitude > 0.01 and d.Unit or Vector3.new(0, 0, 1)) + Vector3.new(0, 0.6, 0)
		remotes.Knockback:FireClient(rec.player, dir.Unit * C.SlamKnockback)
		send(rec.player, { kind = "hit", dealt = 0, taken = taken, at = pPos, strength = 1, slam = true })
	end
	send(rec.player, { kind = "villainSlam", at = vPos })
end

-- Uses special `index` for `who` ("player" | "villain"). The server applies everything except the player's own dash
-- burst, which the player's client applies to its bey (client-owned physics). Returns true if it was used.
local function useSpecial(rec, who, index, now)
	local b = rec.battle
	if b.state ~= "active" then
		return false
	end
	local side = rec.specials[who]
	local def = SpecialsCore.use(side, index, now)
	if not def then
		return false
	end
	local foeKey = who == "player" and "villain" or "player"
	local selfBody = who == "player" and rec.mine.body or rec.villain.body
	local foeBody = who == "player" and rec.villain.body or rec.mine.body
	local t = def.Tuning
	local toFoe = Vector3.new(foeBody.Position.X - selfBody.Position.X, 0, foeBody.Position.Z - selfBody.Position.Z)
	local dir = toFoe.Magnitude > 0.1 and toFoe.Unit or Vector3.new(0, 0, -1)
	local ev = { kind = "special", who = who, id = def.Id, special = def.Kind, spirit = rec.spirits[who], at = selfBody.Position, dir = dir }
	if def.Kind == "dash" then
		ev.dash = t.DashSpeed
		if who == "villain" then
			selfBody.AssemblyLinearVelocity = Vector3.new(dir.X * t.DashSpeed, selfBody.AssemblyLinearVelocity.Y, dir.Z * t.DashSpeed)
		end
	end
	if (def.Kind == "heal" or def.Kind == "guard") and t.Heal then
		ev.healed = BattleCore.heal(b, who, b.sides[who].maxSpin * t.Heal)
	end
	if def.Kind == "quake" then
		local dist = toFoe.Magnitude
		if dist <= t.Radius then
			local out = SpecialsCore.outgoing(side, now, A, false)
			local inc, kbIn = SpecialsCore.incoming(rec.specials[foeKey], now, A)
			local falloff = 1 - 0.4 * (dist / t.Radius)
			local dmg = t.Damage * falloff * out * inc * (who == "villain" and rec.diff.Damage or 1)
			local applied = BattleCore.damage(b, foeKey, dmg)
			ev.hit, ev.dealt = true, applied
			SpecialsCore.charge(side, applied * A.MeterPerDamageDealt, A)
			SpecialsCore.charge(rec.specials[foeKey], applied * A.MeterPerDamageTaken, A)
			local push = (dir + Vector3.new(0, 0.5, 0)).Unit * t.Knockback * kbIn
			if foeKey == "villain" then
				rec.villain.body.AssemblyLinearVelocity += push
				rec.ai:onHit(now)
			else
				remotes.Knockback:FireClient(rec.player, push)
			end
		end
	end
	send(rec.player, ev)
	return true
end

local function awaken(rec, who, now)
	if rec.battle.state ~= "active" or not SpecialsCore.awaken(rec.specials[who], now, A) then
		return false
	end
	local body = who == "player" and rec.mine.body or rec.villain.body
	send(rec.player, { kind = "awaken", who = who, spirit = rec.spirits[who], at = body.Position, duration = A.AwakenDuration })
	return true
end

local function sendSnapshot(rec, now)
	if now - rec.snapshotAt < SNAPSHOT_EVERY then
		return
	end
	rec.snapshotAt = now
	local you = SpecialsCore.snapshot(rec.specials.player, now, A)
	you.speed = SpecialsCore.speed(rec.specials.player, now, A)
	send(rec.player, { kind = "specials", you = you, foe = SpecialsCore.snapshot(rec.specials.villain, now, A) })
end

local function step(dt)
	local rec = current
	if not rec then
		return
	end
	local now = os.clock()
	local player = rec.player
	-- Interrupted: player gone, bey removed, or the villain model destroyed by something else.
	if not player.Parent or not rec.mine.body.Parent or not rec.villain.body.Parent then
		BattleCore.leave(rec.battle, "player", now)
		cleanup(rec, false)
		return
	end

	-- Countdown over and the player never pressed LAUNCH: a weak launch.
	if rec.battle.state == "countdown" and now - rec.battle.stateAt >= B.Countdown and not rec.launch.player then
		rec.launch.player = { quality = L.NoPress, label = "TOO LATE" }
		BattleCore.setStartSpin(rec.battle, "player", LaunchCore.effects(L.NoPress, L).spinFraction)
	end

	local events = BattleCore.update(rec.battle, now, dt)
	for _, ev in ipairs(events) do
		if ev.kind == "started" then
			rec.startedAt = now
			BeyService.release(player)
			rec.villain.body.Anchored = false
			rec.villain.body:SetNetworkOwner(nil)
			-- LET IT RIP: the villain launches toward the player; the player's client launches its own bey.
			local pl = rec.launch.player or { quality = L.NoPress, label = "TOO LATE" }
			local vl = rec.launch.villain
			local ve = LaunchCore.effects(vl.quality, L)
			local toPlayer = rec.mine.body.Position - rec.villain.body.Position
			toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
			if toPlayer.Magnitude > 0.1 then
				rec.villain.body.AssemblyLinearVelocity = toPlayer.Unit * ve.speed
			end
			rec.ai:launched(ve.boost, now)
			SpecialsCore.start(rec.specials.player, now, A)
			SpecialsCore.start(rec.specials.villain, now, A)
			local pe = LaunchCore.effects(pl.quality, L)
			setBattleAttrs(player, "active", Workspace:GetServerTimeNow() + B.Duration)
			send(player, {
				kind = "started",
				duration = B.Duration,
				launch = { quality = pl.quality, label = pl.label, speed = pe.speed, boost = pe.boost, spin = pe.spinFraction },
				foeLaunch = vl.label,
			})
		elseif ev.kind == "finished" then
			finishBattle(rec, ev.result, now)
		elseif ev.kind == "cleanup" then
			cleanup(rec, false)
			return
		end
	end

	local b = rec.battle
	if b.state == "active" then
		CombatCore.recordFall(rec.villainFall, rec.villain.body.AssemblyLinearVelocity.Y, now, C.SlamFallWindow)
		-- ring-outs (relative to the arena centre)
		local center = World.ARENA_CENTER
		if CombatCore.ringOutStep(rec.outTimers, "player", rec.mine.body.Position - center, now, B) then
			BattleCore.ringOut(b, "player")
		end
		if CombatCore.ringOutStep(rec.outTimers, "villain", rec.villain.body.Position - center, now, B) then
			BattleCore.ringOut(b, "villain")
		end
		SpecialsCore.tick(rec.specials.player, dt, A)
		SpecialsCore.tick(rec.specials.villain, dt, A)
		resolveContact(rec, now)
		local mine = rec.mine.body
		rec.ai.speedMul = SpecialsCore.speed(rec.specials.villain, now, A)
		rec.ai:step(dt, now, { pos = mine.Position, vel = mine.AssemblyLinearVelocity }, BattleCore.fraction(b, "villain"), function(fall)
			villainSlam(rec, fall, now)
		end)
		-- the villain's specials and awakening
		local choice = rec.ai:chooseSpecial(now, {
			specials = rec.specials.villain,
			foe = rec.specials.player,
			canAwaken = SpecialsCore.canAwaken(rec.specials.villain, A),
			spin = BattleCore.fraction(b, "villain"),
		})
		if choice == "awaken" then
			awaken(rec, "villain", now)
		elseif choice then
			useSpecial(rec, "villain", choice, now)
		end
		sendSnapshot(rec, now)
		-- a knockout this frame is resolved on the next update()
	elseif rec.ai then
		rec.ai:idle(dt)
	end

	-- spin for the HUD (attributes replicate) and the cosmetic hub speed
	for key, beyRec in pairs({ player = rec.mine, villain = rec.villain }) do
		local side = b.sides[key]
		if beyRec.body.Parent then
			beyRec.body:SetAttribute("Spin", side.spin)
			beyRec.body:SetAttribute("MaxSpin", side.maxSpin)
			beyRec.hinge.AngularVelocity = CombatCore.visualSpin(side.spin / side.maxSpin, C)
		end
	end
end

function BattleService.onSlam(player)
	local rec = current
	if not rec or rec.player ~= player or rec.battle.state ~= "active" then
		return
	end
	local fall = BeyService.validateSlam(player)
	if fall then
		playerSlam(rec, fall, os.clock())
	end
end

-- Player reset / respawned / was interrupted while in bey mode.
function BattleService.onInterrupted(player)
	local rec = current
	if rec and rec.player == player then
		local ev = BattleCore.leave(rec.battle, "player", os.clock())
		if ev then
			finishBattle(rec, ev.result, os.clock())
		end
		cleanup(rec, false)
	else
		BeyService.exit(player)
	end
end

function BattleService.start(r)
	remotes = r
	RunService.Heartbeat:Connect(step)

	remotes.Request.OnServerEvent:Connect(function(player, req)
		if type(req) ~= "table" or type(req.action) ~= "string" then
			return
		end
		if not CombatCore.allow(requestLimiter, player, os.clock()) then
			return
		end
		local rec = current
		local mine = rec and rec.player == player
		if req.action == "launch" and mine and rec.battle.state == "countdown" and not rec.launch.player then
			-- One press per battle. The server judges where the needle was at the stamped time.
			local t = LaunchCore.acceptPress(rec.meter, req.t, Workspace:GetServerTimeNow(), L)
			local q, label = L.Miss, "WEAK"
			if t then
				q, label = LaunchCore.quality(rec.meter, LaunchCore.needle(rec.meter, t), L)
			end
			rec.launch.player = { quality = q, label = label }
			BattleCore.setStartSpin(rec.battle, "player", LaunchCore.effects(q, L).spinFraction)
			send(player, { kind = "launchLocked", label = label, quality = q })
		elseif req.action == "special" and mine and (req.index == 1 or req.index == 2) then
			if not useSpecial(rec, "player", req.index, os.clock()) then
				send(player, { kind = "specialRefused", index = req.index })
			end
		elseif req.action == "awaken" and mine then
			awaken(rec, "player", os.clock())
		elseif req.action == "rematch" and mine and rec.battle.state == "finished" then
			BattleCore.requestCleanup(rec.battle, os.clock())
			cleanup(rec, true)
		elseif req.action == "leave" and mine and rec.battle.state == "finished" then
			BattleCore.requestCleanup(rec.battle, os.clock())
			cleanup(rec, false)
		elseif req.action == "forfeit" and mine and (rec.battle.state == "active" or rec.battle.state == "countdown") then
			local ev = BattleCore.leave(rec.battle, "player", os.clock())
			if ev then
				finishBattle(rec, ev.result, os.clock())
			end
		elseif req.action == "leaveQueue" then
			removeFromQueue(player)
			send(player, { kind = "closed" })
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeFromQueue(player)
		CombatCore.forget(requestLimiter, player)
		local rec = current
		if rec and rec.player == player then
			BattleCore.leave(rec.battle, "player", os.clock())
			cleanup(rec, false)
		end
	end)
end

BattleService.challenge = function(player)
	startBattle(player)
end

return BattleService
]=====])
install('SSS', '', 'ModuleScript', 'BeyFactory', [=====[
--!nonstrict
-- BeyFactory: builds one bey model, used for both player and villain beys.
--   Body   invisible 4-stud ball that does the physics (the collider)
--   Align  AlignOrientation that stops the ball rolling and sets the bey's lean (client for players, server for NPCs)
--   Top    small hub, hinge-motored so it spins; BeyVisuals welds the designed parts to it
-- Attributes on Body: Attack, Defense, Stamina, Balance, Level, Spin, MaxSpin (Spin is set by the battle service).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local BeyVisuals = require(Shared.BeyVisuals)
local BeyDesigns = require(Shared.BeyDesigns)
local GameConfig = require(Shared.GameConfig)
local CombatCore = require(Shared.Core.CombatCore)

local BeyFactory = {}

-- opts: { name, partIds, level, cframe, parent }
-- Returns { model, body, top, hinge, align, stats, maxSpin }
function BeyFactory.build(opts)
	local stats = BeyConfig.ComputeStats(opts.partIds, opts.level)
	local maxSpin = CombatCore.maxSpin(stats, GameConfig.Combat)

	local model = Instance.new("Model")
	model.Name = opts.name
	model.Parent = opts.parent -- parented first so the welds capture the layout
	local design = BeyDesigns.Parts[opts.partIds.Layer]
	if design then
		model:SetAttribute("Accent", design.Accent) -- trail and glow colour (client effects)
	end

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(4, 4, 4)
	body.Transparency = 1
	body.CustomPhysicalProperties = PhysicalProperties.new(1, 0.1, 0.1, 1, 1)
	body.CFrame = opts.cframe
	body.Parent = model
	model.PrimaryPart = body
	for _, stat in ipairs(BeyConfig.StatNames) do
		body:SetAttribute(stat, stats[stat])
	end
	body:SetAttribute("Level", opts.level)
	body:SetAttribute("MaxSpin", maxSpin)
	body:SetAttribute("Spin", maxSpin)

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = body
	local align = Instance.new("AlignOrientation")
	align.Name = "Align"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = center
	align.RigidityEnabled = true
	align.CFrame = opts.cframe.Rotation
	align.Parent = model

	local top = Instance.new("Part")
	top.Name = "Top"
	top.Shape = Enum.PartType.Cylinder
	top.Size = Vector3.new(0.8, 1.2, 1.2)
	top.Color = BeyConfig.RarityColors[BeyConfig.Parts[opts.partIds.Layer].Rarity]
	top.Material = Enum.Material.Metal
	top.CanCollide = false
	top.CanQuery = false
	top.CanTouch = false
	top.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0.1, 0.1, 1, 1)
	top.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(90))
	top.Parent = model
	local topAxis = Instance.new("Attachment")
	topAxis.Name = "Axis"
	topAxis.Parent = top
	local bodyAxis = Instance.new("Attachment")
	bodyAxis.Name = "Axis"
	bodyAxis.CFrame = CFrame.Angles(0, 0, math.rad(90))
	bodyAxis.Parent = body
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "Spin"
	hinge.Attachment0 = bodyAxis
	hinge.Attachment1 = topAxis
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = 50000
	hinge.AngularVelocity = GameConfig.Combat.VisualSpinMax
	hinge.Parent = model

	BeyVisuals.Attach(top, body.CFrame, opts.partIds, model)

	return { model = model, body = body, top = top, hinge = hinge, align = align, stats = stats, maxSpin = maxSpin }
end

return BeyFactory
]=====])
install('SSS', '', 'ModuleScript', 'BeyService', [=====[
--!nonstrict
-- BeyService: puts a player into "bey mode" and back out, safely, whatever happens.
-- Player attribute "Mode": "OnFoot" | "Practice" | "Battle". The client controller binds to the player's bey when
-- it appears in Workspace.Beys and restores the normal camera when it is removed.
-- Entering bey mode parks the avatar (anchored, controls off) at World.PARK; leaving always restores it:
-- after a battle, on reset/death, on leaving practice, or if the player leaves the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local GameConfig = require(Shared.GameConfig)
local CombatCore = require(Shared.Core.CombatCore)

local BeyFactory = require(script.Parent.BeyFactory)
local World = require(script.Parent.World)

local BeyService = {}

local C = GameConfig.Combat
local beysFolder
local beys = {} -- player -> bey record (see BeyFactory) + { fall = fall tracker }
local saved = {} -- player -> { walk, jumpHeight, jumpPower }
local DataService
local remotes
local slamLimiter = CombatCore.newRateLimiter(C.RequestsPerSecond)
local lastSlam = {}

function BeyService.folder()
	return beysFolder
end

function BeyService.get(player)
	return beys[player]
end

local function humanoidAndRoot(player)
	local char = player.Character
	if not char then
		return nil, nil
	end
	return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function parkAvatar(player)
	local hum, root = humanoidAndRoot(player)
	if hum and not saved[player] then
		saved[player] = { walk = hum.WalkSpeed, jumpHeight = hum.JumpHeight, jumpPower = hum.JumpPower }
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
		hum.JumpPower = 0
	end
	if root then
		root.Anchored = true
		root.CFrame = CFrame.new(World.PARK + Vector3.new(math.random(-8, 8), 0, 0))
	end
end

local function restoreAvatar(player)
	local hum, root = humanoidAndRoot(player)
	local s = saved[player]
	saved[player] = nil
	if hum then
		hum.WalkSpeed = (s and s.walk and s.walk > 0) and s.walk or 16
		hum.JumpHeight = (s and s.jumpHeight and s.jumpHeight > 0) and s.jumpHeight or 7.2
		hum.JumpPower = (s and s.jumpPower and s.jumpPower > 0) and s.jumpPower or 50
	end
	if root then
		root.Anchored = false
		root.CFrame = CFrame.new(World.SPAWN + Vector3.new(math.random(-4, 4), 0, math.random(-2, 2)))
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Spawns the player's bey at `cframe` and switches them to `mode`. anchored = frozen (battle countdown).
-- center: the stadium centre (the client uses it to recover a stuck bey; practice resets go to BeySpawn).
function BeyService.enter(player, mode, cframe, anchored, center)
	BeyService.removeBey(player)
	local data = DataService.get(player)
	if not data then
		return nil
	end
	parkAvatar(player)
	local rec = BeyFactory.build({
		name = tostring(player.UserId),
		partIds = data.Equipped,
		level = DataService.levelOf(player),
		cframe = cframe,
		parent = beysFolder,
	})
	rec.fall = CombatCore.newFallTracker()
	beys[player] = rec
	if anchored then
		rec.body.Anchored = true
	else
		rec.body:SetNetworkOwner(player)
	end
	player:SetAttribute("BeySpawn", cframe.Position)
	player:SetAttribute("ArenaCenter", center)
	player:SetAttribute("Mode", mode)
	return rec
end

-- Unfreezes a bey after a countdown and hands physics back to its player.
function BeyService.release(player)
	local rec = beys[player]
	if rec and rec.body.Parent then
		rec.body.Anchored = false
		rec.body:SetNetworkOwner(player)
	end
end

function BeyService.removeBey(player)
	local rec = beys[player]
	beys[player] = nil
	if rec and rec.model then
		rec.model:Destroy()
	end
end

-- Back to walking around, from any state.
function BeyService.exit(player)
	BeyService.removeBey(player)
	if player.Parent then
		player:SetAttribute("Mode", "OnFoot")
		restoreAvatar(player)
	end
end

function BeyService.mode(player)
	return player:GetAttribute("Mode") or "OnFoot"
end

-- Records the downward speed the server sees for every bey (slam claims are checked against this).
local function trackFalls()
	local now = os.clock()
	for _, rec in pairs(beys) do
		if rec.body.Parent then
			CombatCore.recordFall(rec.fall, rec.body.AssemblyLinearVelocity.Y, now, C.SlamFallWindow)
		end
	end
end

-- Practice slams knock the training dummies about (battle slams are handled by BattleService).
local function practiceSlam(player)
	local rec = beys[player]
	if not rec then
		return
	end
	local now = os.clock()
	local fall = CombatCore.maxFall(rec.fall, now, C.SlamFallWindow)
	if fall < C.SlamMinFallSpeed then
		return
	end
	local pos = rec.body.Position
	for _, dummy in ipairs(CollectionService:GetTagged("SpinforgeDummy")) do
		local offset = dummy.Position - pos
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= C.SlamRadius + 3 and math.abs(offset.Y) < 10 then
			local dir = (flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)) + Vector3.new(0, 0.5, 0)
			dummy:ApplyImpulse(dir.Unit * C.SlamKnockback * 3 * dummy.AssemblyMass * math.clamp(fall / 100, 0.5, 1.5))
		end
	end
	remotes.BattleEvent:FireClient(player, { kind = "slam", hit = true })
end

-- Called by BattleService for slams in battle; returns the validated fall speed or nil.
function BeyService.validateSlam(player)
	local rec = beys[player]
	if not rec or not rec.body.Parent then
		return nil
	end
	local now = os.clock()
	if not CombatCore.allow(slamLimiter, player, now) then
		return nil
	end
	if lastSlam[player] and now - lastSlam[player] < C.SlamCooldown then
		return nil
	end
	local fall = CombatCore.maxFall(rec.fall, now, C.SlamFallWindow)
	if fall < C.SlamMinFallSpeed then
		return nil
	end
	lastSlam[player] = now
	return fall
end

local function resetDummies()
	for _, dummy in ipairs(CollectionService:GetTagged("SpinforgeDummy")) do
		local home = dummy:GetAttribute("Home")
		if home and (dummy.Position - home).Magnitude > 60 then
			dummy.AssemblyLinearVelocity = Vector3.zero
			dummy.CFrame = CFrame.new(home) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

function BeyService.startPractice(player)
	if BeyService.mode(player) ~= "OnFoot" then
		return
	end
	local spawnAt = CFrame.new(World.TRAINING_CENTER + Vector3.new(0, 5, 8))
	BeyService.enter(player, "Practice", spawnAt, false, World.TRAINING_CENTER)
	resetDummies()
end

function BeyService.start(r, dataService, onSlam)
	remotes = r
	DataService = dataService
	beysFolder = Workspace:FindFirstChild("Beys")
	if not beysFolder then
		beysFolder = Instance.new("Folder")
		beysFolder.Name = "Beys"
		beysFolder.Parent = Workspace
	end
	game:GetService("RunService").Heartbeat:Connect(trackFalls)

	remotes.SlamLanded.OnServerEvent:Connect(function(player)
		local mode = BeyService.mode(player)
		if mode == "Practice" then
			if BeyService.validateSlam(player) then
				practiceSlam(player)
			end
		elseif mode == "Battle" then
			onSlam(player)
		end
	end)

	-- A character that appears outside the hub (e.g. at a template SpawnLocation inside a stadium) is moved to
	-- the hub spawn, so nobody starts trapped in a bowl.
	local function toHubIfLost(player)
		task.defer(function()
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and BeyService.mode(player) == "OnFoot" and not root.Anchored then
				local flat = Vector3.new(root.Position.X - World.HUB_CENTER.X, 0, root.Position.Z - World.HUB_CENTER.Z)
				if flat.Magnitude > 60 then
					root.CFrame = CFrame.new(World.SPAWN)
				end
			end
		end)
	end
	BeyService.toHubIfLost = toHubIfLost

	local function hookCharacter(player)
		if player.Character then
			World.tagCharacter(player.Character)
		end
		player.CharacterAdded:Connect(function(char)
			World.tagCharacter(char)
			-- A reset or respawn while in bey mode: end it cleanly (BattleService treats it as leaving).
			if BeyService.mode(player) ~= "OnFoot" then
				BeyService.onInterrupted(player)
			end
			toHubIfLost(player)
		end)
		toHubIfLost(player)
	end
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Mode", "OnFoot")
		hookCharacter(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Mode", player:GetAttribute("Mode") or "OnFoot")
		hookCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		BeyService.removeBey(player)
		saved[player] = nil
		lastSlam[player] = nil
		CombatCore.forget(slamLimiter, player)
	end)
end

-- Overridden by Main so BattleService can react (forfeit); default just exits.
function BeyService.onInterrupted(player)
	BeyService.exit(player)
end

return BeyService
]=====])
install('SSS', '', 'ModuleScript', 'DataService', [=====[
--!nonstrict
-- DataService: loads, holds and saves each player's data using SessionStore (session locks, retries, never
-- overwriting a real save after a failed load) over Roblox DataStores.
--
-- Save status per player (shown to them):
--   "saving"   loaded normally; autosaves and saves on leave
--   "nosave"   could not load (DataStore error, or Studio without API access): plays with a temporary profile that is
--              NEVER written, so the real save stays safe. Shown as a banner.
--   "locked"   another server still holds this player's session: temporary profile, not saved
--   "newer"    the save came from a newer game version: temporary profile, not saved
-- Live DataStore behaviour is unverified here; the rules are tested against a mock (tools/tests/progression.test.luau).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local PlayerData = require(Shared.Core.PlayerData)
local Progression = require(Shared.Core.Progression)
local SessionStore = require(Shared.Core.SessionStore)

local DataService = {}

local G = GameConfig.Data
local P = GameConfig.Progression
local profiles = {} -- player -> { data, status, dirty }
local remotes
local onReady = {} -- callbacks(player)
-- Studio has no JobId. Use one fixed id there, so a lock left behind by a stopped test session is picked straight
-- back up by the next one instead of locking you out of saving for LockTimeout.
local jobId = (game.JobId ~= "" and game.JobId) or "studio"

-- Adapter: SessionStore's store:update contract over a DataStore.
local function makeAdapter(ds)
	return {
		update = function(_, key, transform)
			local cancelled = false
			local ok, result = pcall(function()
				return ds:UpdateAsync(key, function(old)
					local new = transform(old)
					cancelled = new == nil
					return new
				end)
			end)
			if not ok then
				return false, result
			end
			if cancelled then
				return true, nil
			end
			return true, result
		end,
	}
end

local store
local storeError

local function keyFor(player)
	return "u_" .. player.UserId
end

local function migrate(raw)
	return PlayerData.migrate(raw, BeyConfig.StarterLoadout, BeyConfig.Items, P.RecentBattleMemory)
end

local function sessionOpts()
	return {
		attempts = G.LoadAttempts,
		retryWait = G.RetryWait,
		wait = function(s)
			task.wait(s)
		end,
		now = function()
			return os.time()
		end,
		lockTimeout = G.LockTimeout,
		migrate = migrate,
	}
end

function DataService.levelOf(player)
	local p = profiles[player]
	return p and Progression.levelFromXP(p.data.XP, P) or 1
end

function DataService.get(player)
	local p = profiles[player]
	return p and p.data or nil
end

function DataService.status(player)
	local p = profiles[player]
	return p and p.status or "loading"
end

function DataService.isReady(player)
	return profiles[player] ~= nil
end

-- What the client sees: PlayerData.snapshot plus XP needed for this and the next level (for the XP bar).
function DataService.snapshot(player)
	local p = profiles[player]
	if not p then
		return nil
	end
	local level = DataService.levelOf(player)
	local snap = PlayerData.snapshot(p.data, level, p.status)
	snap.XPThis = Progression.xpForLevel(level, P)
	snap.XPNext = level < P.MaxLevel and Progression.xpForLevel(level + 1, P) or snap.XPThis
	return snap
end

function DataService.sendProfile(player)
	if remotes and player.Parent and profiles[player] then
		remotes.Profile:FireClient(player, DataService.snapshot(player))
	end
end

function DataService.markDirty(player)
	local p = profiles[player]
	if p then
		p.dirty = true
	end
end

local function save(player, release)
	local p = profiles[player]
	if not p or p.status ~= "saving" or not store then
		return "skipped"
	end
	local result, detail = SessionStore.save(store, keyFor(player), jobId, p.data, sessionOpts(), release)
	if result == "ok" then
		p.dirty = false
	elseif result == "lost_lock" then
		-- Another server took over this player's data: stop writing from here so we can't clobber it.
		p.status = "locked"
		warn(("Spinforge: %s's session moved to another server; this server stopped saving it."):format(player.Name))
		DataService.sendProfile(player)
	else
		warn(("Spinforge: saving %s failed (%s). Will retry at the next autosave."):format(player.Name, tostring(detail)))
	end
	return result
end
DataService.save = save

function DataService.onReady(callback)
	table.insert(onReady, callback)
end

local function load(player)
	local status, data, detail = "nosave", nil, storeError
	if store then
		local result
		result, data, detail = SessionStore.load(store, keyFor(player), jobId, sessionOpts())
		if result == "ok" then
			status = "saving"
		elseif result == "unsupported" then
			status = "newer"
		elseif result == "locked" then
			status = "locked"
		else
			status = "nosave"
		end
	end
	if not player.Parent then
		-- Left while loading: release the lock we may have just taken.
		if status == "saving" and data then
			profiles[player] = { data = data, status = status, dirty = false }
			save(player, true)
			profiles[player] = nil
		end
		return
	end
	if status ~= "saving" then
		warn(("Spinforge: %s plays with a temporary profile (%s: %s). It will NOT be saved."):format(player.Name, status, tostring(detail)))
		data = PlayerData.new(BeyConfig.StarterLoadout)
	end
	profiles[player] = { data = data, status = status, dirty = false }
	player:SetAttribute("DataReady", true)
	DataService.sendProfile(player)
	for _, cb in ipairs(onReady) do
		task.spawn(cb, player)
	end
end

function DataService.start(r)
	remotes = r
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(G.StoreName)
	end)
	if ok then
		store = makeAdapter(result)
	else
		storeError = tostring(result)
		warn("Spinforge: DataStores unavailable (" .. storeError .. "). Progress will not save this session." .. (RunService:IsStudio() and " In Studio: Game Settings > Security > Enable Studio Access to API Services." or ""))
	end

	Players.PlayerAdded:Connect(function(player)
		load(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			save(player, true)
			profiles[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(G.AutosaveInterval)
			for player, p in pairs(profiles) do
				if p.dirty and p.status == "saving" then
					task.spawn(save, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return DataService
]=====])
install('SSS', '', 'Script', 'Main', [=====[
--!nonstrict
-- Spinforge server entry point. Starts everything in a fixed order and prints a startup report to Output.
-- If something required is missing, it stops with a message saying what to do instead of failing silently.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local REQUIRED_SHARED = { "BeyConfig", "BeyDesigns", "BeyMeshData", "BeyVisuals", "GameConfig", "Net", "Core" }
local Shared = ReplicatedStorage:FindFirstChild("Spinforge")
if not Shared then
	error("Spinforge: ReplicatedStorage.Spinforge is missing. Run install_in_studio.lua again (Command Bar).")
end
local missing = {}
for _, name in ipairs(REQUIRED_SHARED) do
	if not Shared:FindFirstChild(name) then
		table.insert(missing, name)
	end
end
if #missing > 0 then
	error("Spinforge: missing shared modules: " .. table.concat(missing, ", ") .. ". Run install_in_studio.lua again.")
end

local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local Net = require(Shared.Net)
local Progression = require(Shared.Core.Progression)

local World = require(script.Parent.World)
local MeshImport = require(script.Parent.MeshImport)
local DataService = require(script.Parent.DataService)
local BeyService = require(script.Parent.BeyService)
local BattleService = require(script.Parent.BattleService)

Workspace.Gravity = BeyConfig.Movement.Gravity
local remotes = Net.setup(ReplicatedStorage)
World.removeLegacy()
local world = World.build(GameConfig.Villain.Name)
World.polishLighting()
local meshes, moved = MeshImport.collect()
local spiritMeshes, spiritsMoved = MeshImport.spirits()
local spiritCount = 0
for _ in pairs(BeyConfig.Spirits) do
	spiritCount += 1
end

DataService.start(remotes)
BeyService.start(remotes, DataService, BattleService.onSlam)
BeyService.onInterrupted = BattleService.onInterrupted
BattleService.start(remotes)

-- Hub prompts.
local function onFootAndReady(player)
	return BeyService.mode(player) == "OnFoot" and DataService.isReady(player)
end
if world.prompts.challenge then
	world.prompts.challenge.Triggered:Connect(function(player)
		if onFootAndReady(player) then
			BattleService.challenge(player)
		end
	end)
end
if world.prompts.practice then
	world.prompts.practice.Triggered:Connect(function(player)
		if onFootAndReady(player) then
			BeyService.startPractice(player)
		end
	end)
end
if world.prompts.workshop then
	world.prompts.workshop.Triggered:Connect(function(player)
		remotes.BattleEvent:FireClient(player, { kind = "openWorkshop" })
	end)
end

-- Workshop: buy and equip parts, spirits and specials, validated on the server. Only allowed on foot.
remotes.Workshop.OnServerInvoke = function(player, req)
	local data = DataService.get(player)
	local function reply(ok, reason)
		return {
			ok = ok,
			reason = reason and (Progression.ReasonText[reason] or reason) or nil,
			profile = DataService.snapshot(player),
		}
	end
	if not data then
		return reply(false, "Your profile is still loading.")
	end
	if type(req) ~= "table" or type(req.action) ~= "string" or type(req.part) ~= "string" then
		return reply(false, "invalid")
	end
	local mode = BeyService.mode(player)
	if mode == "Practice" then
		return reply(false, "Leave practice to change parts.")
	end
	local inBattle = mode ~= "OnFoot"
	local ok, reason
	if req.action == "buy" then
		ok, reason = Progression.buy(data, req.part, BeyConfig.Items, GameConfig.Progression, inBattle)
	elseif req.action == "equip" then
		local slot = (req.slot == "Special1" or req.slot == "Special2") and req.slot or nil
		ok, reason = Progression.equip(data, req.part, BeyConfig.Items, inBattle, slot)
	else
		return reply(false, "invalid")
	end
	if ok then
		DataService.markDirty(player)
		DataService.sendProfile(player)
		return reply(true, nil)
	end
	return reply(false, reason)
end

-- Other requests: settings, tutorial, leaving practice. (Battle requests are handled in BattleService.)
local SETTINGS = { CameraShake = true, ReducedEffects = true }
remotes.Request.OnServerEvent:Connect(function(player, req)
	if type(req) ~= "table" or type(req.action) ~= "string" then
		return
	end
	local data = DataService.get(player)
	if req.action == "setting" and data and SETTINGS[req.key] and type(req.value) == "boolean" then
		data.Settings[req.key] = req.value
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "tutorialDone" and data and not data.Settings.TutorialDone then
		data.Settings.TutorialDone = true
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "tutorialReset" and data then
		data.Settings.TutorialDone = false
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "exitPractice" and BeyService.mode(player) == "Practice" then
		BeyService.exit(player)
	end
end)

print(("Spinforge server ready: world %s, %d of %d bey meshes available%s, %d of %d spirit meshes, crates disabled (paid purchases off)."):format(
	world.built and "built" or "found (custom SpinforgeWorld)",
	meshes,
	66,
	(moved + spiritsMoved) > 0 and (" (moved " .. (moved + spiritsMoved) .. " imported model(s) from Workspace)") or "",
	spiritMeshes,
	spiritCount
))
]=====])
install('SSS', '', 'ModuleScript', 'MeshImport', [=====[
--!nonstrict
-- MeshImport: Studio's 3D importer drops imported models into Workspace. At server start, any bey meshes found
-- there (MeshParts named like "<partId>_P" / "<partId>_A") are moved into ReplicatedStorage.BeyMeshes, where
-- BeyVisuals looks for them. Spirit creature meshes (MeshParts named like "spirit_emberwolf") go to
-- ReplicatedStorage.SpiritMeshes, where the client's Spirits module looks for them.
-- collect() returns how many bey meshes are available afterwards (and how many were moved); spirits() the same
-- for the creatures.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyMeshData = require(Shared.BeyMeshData)
local BeyConfig = require(Shared.BeyConfig)

local MeshImport = {}

function MeshImport.collect()
	local folder = ReplicatedStorage:FindFirstChild("BeyMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BeyMeshes"
		folder.Parent = ReplicatedStorage
	end
	local tops = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("MeshPart") and BeyMeshData[d.Name] then
			local top = d
			while top.Parent and top.Parent ~= Workspace do
				top = top.Parent
			end
			tops[top] = true
		end
	end
	local moved = 0
	for top in pairs(tops) do
		top.Parent = folder
		moved += 1
	end
	local available = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("MeshPart") and BeyMeshData[d.Name] then
			available += 1
		end
	end
	return available, moved
end

function MeshImport.spirits()
	local folder = ReplicatedStorage:FindFirstChild("SpiritMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SpiritMeshes"
		folder.Parent = ReplicatedStorage
	end
	local tops = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("MeshPart") and BeyConfig.Spirits[d.Name] then
			local top = d
			while top.Parent and top.Parent ~= Workspace do
				top = top.Parent
			end
			tops[top] = true
		end
	end
	local moved = 0
	for top in pairs(tops) do
		top.Parent = folder
		moved += 1
	end
	local available = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("MeshPart") and BeyConfig.Spirits[d.Name] then
			available += 1
		end
	end
	return available, moved
end

return MeshImport
]=====])
install('SSS', '', 'ModuleScript', 'VillainAI', [=====[
--!nonstrict
-- VillainAI: drives the villain's bey on the server with the SAME MovementCore rules as the player's bey.
-- Behaviours (one at a time):
--   approach     chase where the player will be (short prediction), keep away from the rim when not attacking
--   windup       TELEGRAPH (red highlight + "!"): slows down, then
--   dash         leans fully in and charges the spot the player was at when the dash started
--   slamWindup   TELEGRAPH (orange highlight + "!!"): hops, then dives onto the player (an air slam)
--   recover      backs off at an angle for a moment after an attack or a hit
--   unstuck      if it barely moves for a while, it pushes back toward the centre
-- Specials (chooseSpecial, asked by BattleService each frame): a dash special fires as a dash attack starts, a quake
-- when the player is close, a guard when the player is empowered or awakened, a heal when low; it awakens as soon
-- as its meter is full. Never more than one special per SPECIAL_GAP seconds, so the player can read them.
-- Difficulty (GameConfig.Difficulty) sets speed, warning time, aggression and damage.
-- Unverified in Roblox: how this feels and whether it gets stuck on the stadium geometry. See HANDOFF checklist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local MC = require(Shared.Core.MovementCore)
local LaunchCore = require(Shared.Core.LaunchCore)

local M = BeyConfig.Movement
local VillainAI = {}
VillainAI.__index = VillainAI

local SPECIAL_GAP = 2.5 -- minimum seconds between the villain's specials
local RIM_SAFE = 31 -- beyond this radius (from the arena centre) it steers back in unless attacking

-- rec: BeyFactory record. diff: GameConfig.Difficulty entry. center: arena centre. ignore: instances the probe ignores.
function VillainAI.new(rec, diff, center, ignore)
	local self = setmetatable({}, VillainAI)
	self.rec = rec
	self.diff = diff
	self.center = center
	self.state = "approach"
	self.stateAt = 0
	self.nextAttackAt = 1.5
	self.ground = MC.newGround()
	self.actions = MC.newActions()
	self.stuck = MC.newStuck()
	self.slowSince = nil
	self.yaw = 0
	self.up = Vector3.yAxis
	self.dashTarget = nil
	self.speedMul = 1 -- spirit passive / awakening (set by BattleService)
	self.dashStartedAt = -math.huge
	self.lastSpecialAt = -math.huge
	self.rng = Random.new()
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.FilterDescendantsInstances = ignore

	local hl = Instance.new("Highlight")
	hl.Name = "Telegraph"
	hl.FillTransparency = 0.35
	hl.OutlineTransparency = 0
	hl.Enabled = false
	hl.Parent = rec.model
	self.highlight = hl
	local bb = Instance.new("BillboardGui")
	bb.Name = "TelegraphMark"
	bb.Size = UDim2.fromOffset(60, 60)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.Adornee = rec.body
	bb.Parent = rec.model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeTransparency = 0
	label.Text = "!"
	label.Parent = bb
	self.mark = bb
	self.markLabel = label
	return self
end

-- The villain's launch boost (from its launch quality): extra top speed that fades over GameConfig.Launch.BoostTime.
function VillainAI:launched(boost, now)
	self.launchBoost = boost
	self.launchAt = now
	self.nextAttackAt = now + 1.0
end

function VillainAI:setTelegraph(kind)
	if kind == nil then
		self.highlight.Enabled = false
		self.mark.Enabled = false
		return
	end
	local color = kind == "dash" and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 160, 40)
	self.highlight.FillColor = color
	self.highlight.OutlineColor = color
	self.highlight.Enabled = true
	self.markLabel.Text = kind == "dash" and "!" or "!!"
	self.markLabel.TextColor3 = color
	self.mark.Enabled = true
end

function VillainAI:go(state, now)
	self.state = state
	self.stateAt = now
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Called every Heartbeat while the battle is active. target: { pos, vel } of the player's bey.
-- onSlamImpact(fallSpeed) is called once when the villain's slam lands.
-- Returns nothing; writes the villain body's velocity and orientation.
function VillainAI:step(dt, now, target, spinFraction, onSlamImpact)
	local body = self.rec.body
	if not body.Parent or body.Anchored then
		return
	end
	dt = MC.safeDt(dt, M)
	local pos = body.Position
	local vel = MC.sanitizeVelocity(body.AssemblyLinearVelocity, M)
	local speed = MC.topSpeed(self.rec.stats, M) * self.diff.Speed * (self.speedMul or 1)
	if self.launchAt then
		speed *= LaunchCore.boostMultiplier(self.launchBoost, now - self.launchAt, GameConfig.Launch)
	end

	-- ground probe (same rules as the player: sphere probe, hysteresis)
	local normal
	if not MC.probeSuppressed(self.actions, now, M) then
		local hit = Workspace:Raycast(pos, Vector3.new(0, -(M.Radius + M.GroundProbe), 0), self.params)
		normal = hit and hit.Normal or nil
	end
	local event = MC.updateGround(self.ground, normal, now, M)
	if MC.resolveActions(self.actions, event, now, M) == "impact" then
		onSlamImpact(MC.finite(vel.Y) and math.max(-vel.Y, 0) or 0)
	end

	local toTarget = flat(target.pos - pos)
	local dist = toTarget.Magnitude
	self.lastDist = dist
	local fromCenter = flat(pos - self.center)
	local wish, tilt = Vector3.zero, 0
	local t = now - self.stateAt
	local s = self.state

	if s == "approach" then
		local predicted = flat(target.pos + target.vel * 0.35 - pos)
		wish = predicted.Magnitude > 0.1 and predicted.Unit or Vector3.zero
		tilt = dist > 18 and -0.4 or 0
		if fromCenter.Magnitude > RIM_SAFE then
			wish = (wish + (-fromCenter.Unit) * 1.2)
			wish = wish.Magnitude > 0.01 and wish.Unit or wish
		end
		if now >= self.nextAttackAt and dist < 20 and self.rng:NextNumber() < self.diff.Aggression then
			if dist < 11 and self.ground.grounded and self.rng:NextNumber() < 0.35 then
				self:go("slamWindup", now)
				self:setTelegraph("slam")
			else
				self:go("windup", now)
				self:setTelegraph("dash")
			end
		elseif now >= self.nextAttackAt then
			self.nextAttackAt = now + 0.6 -- re-roll soon
		end
	elseif s == "windup" then
		wish = dist > 0.1 and toTarget.Unit or Vector3.zero
		tilt = 0.7 -- visibly rears back and slows: the tell
		if t >= self.diff.Windup then
			self.dashTarget = target.pos
			self.dashStartedAt = now
			self:go("dash", now)
		end
	elseif s == "dash" then
		local d = flat(self.dashTarget - pos)
		wish = d.Magnitude > 0.1 and d.Unit or Vector3.zero
		tilt = -1
		if t >= 0.9 or d.Magnitude < 2 then
			self:setTelegraph(nil)
			self:go("recover", now)
		end
	elseif s == "slamWindup" then
		tilt = 0.5
		if t >= self.diff.Windup and MC.canJump(self.actions, self.ground, now, M) then
			vel = MC.jump(self.actions, self.ground, vel, 0.6, now, M)
			-- hop toward the player so the dive lands near them
			local push = dist > 0.1 and toTarget.Unit * math.min(dist * 2.2, 40) or Vector3.zero
			vel = Vector3.new(push.X, vel.Y * 1.15, push.Z)
			self:go("slamAir", now)
		elseif t >= self.diff.Windup + 1 then
			self:setTelegraph(nil)
			self:go("recover", now)
		end
	elseif s == "slamAir" then
		if MC.canSlam(self.actions, self.ground, now, M) and vel.Y < 5 then
			vel = MC.startSlam(self.actions, vel, now, M)
			self:go("slamDive", now)
		elseif t > 2 then
			self:setTelegraph(nil)
			self:go("recover", now)
		end
	elseif s == "slamDive" then
		if self.actions.slam ~= "diving" then
			self:setTelegraph(nil)
			self:go("recover", now)
		end
	elseif s == "recover" then
		local away = dist > 0.1 and -toTarget.Unit or Vector3.new(1, 0, 0)
		local side = Vector3.new(-away.Z, 0, away.X)
		wish = (away + side * 0.8).Unit
		if fromCenter.Magnitude > RIM_SAFE - 4 then
			wish = (-fromCenter).Unit
		end
		tilt = 0.2
		if t >= 1.0 then
			self.nextAttackAt = now + 0.8 + self.rng:NextNumber() * 1.2
			self:go("approach", now)
		end
	elseif s == "unstuck" then
		wish = fromCenter.Magnitude > 0.1 and (-fromCenter).Unit or Vector3.new(1, 0, 0)
		tilt = -0.6
		if t >= 1.2 then
			self:go("approach", now)
		end
	end

	-- movement (shared rules)
	if self.ground.grounded then
		vel = MC.groundVelocity(vel, self.ground.normal, wish, tilt, speed, dt, M)
	else
		if event == "tookoff" then
			vel = vel + Vector3.new(0, MC.takeoffBoost(self.actions, vel, tilt, M), 0)
		end
		vel = MC.airVelocity(vel, wish, tilt, speed, self.actions.slam == "diving", dt, M)
	end

	-- stuck: barely moving on the ground while trying to go somewhere
	if s ~= "windup" and s ~= "slamWindup" and wish.Magnitude > 0.5 and flat(vel).Magnitude < 2 then
		self.slowSince = self.slowSince or now
		if now - self.slowSince > 1.5 then
			self.slowSince = nil
			self:setTelegraph(nil)
			self:go("unstuck", now)
			vel = vel + Vector3.new(0, 25, 0) + (fromCenter.Magnitude > 0.1 and (-fromCenter).Unit * 20 or Vector3.zero)
		end
	else
		self.slowSince = nil
	end

	vel = MC.sanitizeVelocity(vel, M)
	body.AssemblyLinearVelocity = vel

	-- orientation: lean with the surface and its tilt; wobble when low on spin
	self.yaw = MC.noseYaw(self.yaw, vel, dt, M)
	self.up = MC.surfaceUp(self.up, self.ground.grounded and self.ground.normal or nil, dt, M)
	local r, u, b = MC.frame(self.up, self.yaw)
	local wobble = 0
	if spinFraction < GameConfig.Combat.LowSpinFraction then
		wobble = math.sin(now * 9) * 0.25 * (1 - spinFraction / GameConfig.Combat.LowSpinFraction)
	end
	self.rec.align.CFrame = CFrame.fromMatrix(Vector3.zero, r, u, b) * CFrame.Angles(tilt * math.rad(M.MaxTiltDeg) * 0.6, 0, wobble)
end

-- Which special to use now, if any: 1 or 2 (slot), "awaken", or nil.
-- info = { specials = its SpecialsCore side, foe = the player's side, canAwaken = bool, spin = its spin fraction }
function VillainAI:chooseSpecial(now, info)
	if now - self.lastSpecialAt < SPECIAL_GAP then
		return nil
	end
	local function pick(choice)
		self.lastSpecialAt = now
		return choice
	end
	if info.canAwaken then
		return pick("awaken")
	end
	local dist = self.lastDist or math.huge
	local foe = info.foe
	local threatened = (foe.empower ~= nil and now <= foe.empower.untilT) or now < foe.awakenedUntil
	for i, s in ipairs(info.specials.specials) do
		local def = s.def
		if def and now >= s.readyAt then
			local kind, t = def.Kind, def.Tuning
			if kind == "dash" and self.state == "dash" and now - self.dashStartedAt < 0.15 then
				return pick(i)
			elseif kind == "quake" and dist < t.Radius * 0.8 and self.rng:NextNumber() < self.diff.Aggression * 0.05 then
				return pick(i)
			elseif kind == "guard" and threatened and dist < 18 then
				return pick(i)
			elseif kind == "heal" and info.spin < 0.4 then
				return pick(i)
			end
		end
	end
	return nil
end

-- A hit lands on the villain: interrupt a windup sometimes and back off.
function VillainAI:onHit(now)
	if self.state == "approach" or self.state == "windup" then
		self:setTelegraph(nil)
		self:go("recover", now)
	end
end

-- Idle (countdown / finished): brake to a stop, no attacks.
function VillainAI:idle(dt)
	local body = self.rec.body
	if not body.Parent or body.Anchored then
		return
	end
	self:setTelegraph(nil)
	local v = body.AssemblyLinearVelocity
	if MC.finiteVector(v) then
		body.AssemblyLinearVelocity = Vector3.new(v.X * 0.9, v.Y, v.Z * 0.9)
	end
end

function VillainAI:destroy()
	self:setTelegraph(nil)
end

return VillainAI
]=====])
install('SSS', '', 'ModuleScript', 'World', [=====[
--!nonstrict
-- World: builds the play space at server start (runtime only; nothing is saved into the place file).
--   Arena     battle stadium at the origin. NO fence: leaving the bowl is a ring-out (battle rules).
--   Training  practice stadium at TRAINING_CENTER. Invisible fence above the rim keeps you in (training rules),
--             plus knockable dummies.
--   Hub       on-foot start area between them with the spawn, a Challenge pedestal, a Practice pad and the Workshop.
-- If the place already has a folder named "SpinforgeWorld", nothing is built (you've made your own map).

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local World = {}

World.ARENA_CENTER = Vector3.new(0, 0, 0)
World.TRAINING_CENTER = Vector3.new(0, 0, -130)
World.HUB_CENTER = Vector3.new(0, 0, 95)
World.SPAWN = Vector3.new(0, 3, 108)
World.PARK = Vector3.new(28, 4, 130) -- where avatars wait (anchored) while their bey plays, away from the prompts
World.AVATAR_GROUP = "SpinforgeAvatars"
World.AVATAR_WALL_GROUP = "SpinforgeAvatarWall"

local SEGMENTS = 48
local FLOOR_RADIUS = 14
local RINGS = { -- { outer radius, slope degrees, colour }
	{ 24, 12, Color3.fromRGB(46, 56, 84) },
	{ 33, 26, Color3.fromRGB(40, 70, 120) },
	{ 39, 45, Color3.fromRGB(34, 96, 160) },
	{ 42, 72, Color3.fromRGB(30, 130, 200) },
}
World.RIM_RADIUS = 42
local FENCE_HEIGHT = 60

local function block(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(parent, at, text, color)
	local post = block(parent, "Sign", Vector3.new(0.6, 6, 0.6), CFrame.new(at + Vector3.new(0, 3, 0)), Color3.fromRGB(40, 44, 60))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 60)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Parent = post
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)
	return post
end

-- Builds one bowl stadium. opts: { name, center, fence = bool, dummies = bool }
local function buildBowl(root, opts)
	local folder = Instance.new("Folder")
	folder.Name = opts.name
	folder.Parent = root
	local c = opts.center
	local origin = CFrame.new(c)

	block(folder, "Floor", Vector3.new(1, FLOOR_RADIUS * 2 + 0.6, FLOOR_RADIUS * 2 + 0.6), origin * CFrame.new(0, 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(38, 42, 62)).Shape =
		Enum.PartType.Cylinder
	local mark = block(folder, "CentreMark", Vector3.new(0.1, 6, 6), origin * CFrame.new(0, 1.06, 0) * CFrame.Angles(0, 0, math.rad(90)), opts.accent, Enum.Material.Neon)
	mark.Shape = Enum.PartType.Cylinder
	mark.CanCollide = false

	local height, inner = 1.02, FLOOR_RADIUS
	for ringIndex, ring in ipairs(RINGS) do
		local outer, slope, color = ring[1], math.rad(ring[2]), ring[3]
		local run = outer - inner
		local rise = run * math.tan(slope)
		local length = run / math.cos(slope) + 0.4
		local width = 2 * outer * math.tan(math.pi / SEGMENTS) + 0.25
		local mid = (inner + outer) / 2
		for i = 0, SEGMENTS - 1 do
			local angle = i * 2 * math.pi / SEGMENTS
			local cf = origin * CFrame.new(0, height + rise / 2, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -mid) * CFrame.Angles(slope, 0, 0) * CFrame.new(0, -0.5, 0)
			block(folder, "Ring" .. ringIndex, Vector3.new(width, 1, length), cf, color)
		end
		height += rise
		inner = outer
	end
	local rimHeight = height

	local barrier = Instance.new("Folder")
	barrier.Name = "Barrier" -- the camera ignores this folder
	barrier.Parent = folder
	for i = 0, SEGMENTS - 1 do
		local angle = i * 2 * math.pi / SEGMENTS
		local width = 2 * (inner + 1) * math.tan(math.pi / SEGMENTS) + 0.3
		local base = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -(inner + 0.6))
		block(folder, "Skirt", Vector3.new(width, rimHeight, 1.2), origin * CFrame.new(0, rimHeight / 2, 0) * base, Color3.fromRGB(24, 28, 40))
		block(folder, "Rim", Vector3.new(width, 0.5, 1.4), origin * CFrame.new(0, rimHeight + 0.25, 0) * base, opts.accent, Enum.Material.Neon)
		if opts.fence then
			local fence = block(barrier, "Fence", Vector3.new(width, FENCE_HEIGHT, 1), origin * CFrame.new(0, rimHeight + FENCE_HEIGHT / 2, 0) * base, Color3.new(1, 1, 1))
			fence.Transparency = 1
		end
	end

	-- Avatar-only wall: keeps people on foot out of the bowl (so nobody can wander in and block a battle).
	-- It doesn't collide with beys, so launches and ring-outs are unaffected.
	for i = 0, SEGMENTS - 1 do
		local angle = i * 2 * math.pi / SEGMENTS
		local width = 2 * (inner + 3) * math.tan(math.pi / SEGMENTS) + 0.3
		local wall = block(barrier, "AvatarWall", Vector3.new(width, 50, 1), origin * CFrame.new(0, 25, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -(inner + 3)), Color3.new(1, 1, 1))
		wall.Transparency = 1
		wall.CollisionGroup = World.AVATAR_WALL_GROUP
	end

	if opts.dummies then
		for _, xz in ipairs({ { 9, 0 }, { -5, 8 }, { -5, -8 } }) do
			local p = Instance.new("Part")
			p.Name = "Dummy"
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(2, 6, 6)
			p.CFrame = origin * CFrame.new(xz[1], 4, xz[2]) * CFrame.Angles(0, 0, math.rad(90))
			p.Color = Color3.fromRGB(220, 70, 70)
			p.Material = Enum.Material.SmoothPlastic
			p:SetAttribute("Home", p.CFrame.Position)
			p.Parent = folder
			CollectionService:AddTag(p, "SpinforgeDummy")
		end
	end
	return folder
end

local function prompt(parent, actionText, objectText, name)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = actionText
	pp.ObjectText = objectText
	pp.HoldDuration = 0.25
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.Parent = parent
	return pp
end

local function buildHub(root, villainName)
	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	folder.Parent = root
	local c = World.HUB_CENTER
	block(folder, "Plaza", Vector3.new(70, 1, 60), CFrame.new(c + Vector3.new(0, 1.5, 12)), Color3.fromRGB(58, 64, 82), Enum.Material.Slate)
	-- Walkways to both stadiums (decoration; the beys travel by teleport).
	block(folder, "PathArena", Vector3.new(8, 0.2, 20), CFrame.new(0, 2.05, 62), Color3.fromRGB(90, 200, 255), Enum.Material.Neon).Transparency = 0.6

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpinforgeSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(World.SPAWN - Vector3.new(0, 1, 0))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(90, 200, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Parent = folder

	local challenge = block(folder, "ChallengePedestal", Vector3.new(6, 3, 6), CFrame.new(c + Vector3.new(-14, 3.5, -6)), Color3.fromRGB(200, 60, 70), Enum.Material.Neon)
	sign(folder, c + Vector3.new(-14, 2, -11), "BATTLE: " .. string.upper(villainName), Color3.fromRGB(255, 120, 120))
	local practice = block(folder, "PracticePad", Vector3.new(6, 3, 6), CFrame.new(c + Vector3.new(14, 3.5, -6)), Color3.fromRGB(70, 180, 120), Enum.Material.Neon)
	sign(folder, c + Vector3.new(14, 2, -11), "PRACTICE", Color3.fromRGB(140, 255, 180))
	local workshop = block(folder, "WorkshopKiosk", Vector3.new(8, 4, 4), CFrame.new(c + Vector3.new(0, 4, 26)), Color3.fromRGB(230, 170, 60), Enum.Material.Neon)
	sign(folder, c + Vector3.new(6, 2, 26), "WORKSHOP", Color3.fromRGB(255, 210, 120))

	return {
		challenge = prompt(challenge, "Challenge", villainName, "ChallengePrompt"),
		practice = prompt(practice, "Practice", "Training stadium", "PracticePrompt"),
		workshop = prompt(workshop, "Open", "Workshop", "WorkshopPrompt"),
	}
end

-- Light, optional polish so metal parts and neon rarity accents read well. Only adds what the place lacks;
-- it never replaces lighting effects you've set up yourself.
function World.polishLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.EnvironmentSpecularScale = math.max(Lighting.EnvironmentSpecularScale, 0.8)
	Lighting.EnvironmentDiffuseScale = math.max(Lighting.EnvironmentDiffuseScale, 0.5)
	if not Lighting:FindFirstChildWhichIsA("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "SpinforgeBloom"
		bloom.Intensity = 0.5
		bloom.Size = 24
		bloom.Threshold = 1.4
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildWhichIsA("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "SpinforgeColor"
		cc.Contrast = 0.08
		cc.Saturation = 0.08
		cc.Parent = Lighting
	end
end

-- Collision groups: the avatar-only walls collide with avatars and nothing else.
function World.setupCollisionGroups()
	local PhysicsService = game:GetService("PhysicsService")
	for _, name in ipairs({ World.AVATAR_GROUP, World.AVATAR_WALL_GROUP }) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable(World.AVATAR_WALL_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(World.AVATAR_WALL_GROUP, World.AVATAR_GROUP, true)
end

-- Puts every part of a character in the avatar group (and any part added later, e.g. accessories).
function World.tagCharacter(char)
	local function tag(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = World.AVATAR_GROUP
		end
	end
	for _, d in ipairs(char:GetDescendants()) do
		tag(d)
	end
	char.DescendantAdded:Connect(tag)
end

-- Returns { root, arena, training, prompts, built = bool }.
function World.build(villainName)
	World.setupCollisionGroups()
	local existing = Workspace:FindFirstChild("SpinforgeWorld")
	if existing then
		local prompts = {}
		for _, name in ipairs({ "ChallengePrompt", "PracticePrompt", "WorkshopPrompt" }) do
			local p = existing:FindFirstChild(name, true)
			prompts[(name:gsub("Prompt", "")):lower()] = p
		end
		return { root = existing, arena = existing:FindFirstChild("Arena"), training = existing:FindFirstChild("Training"), prompts = prompts, built = false }
	end
	local root = Instance.new("Folder")
	root.Name = "SpinforgeWorld"
	root.Parent = Workspace
	block(root, "Ground", Vector3.new(400, 2, 400), CFrame.new(0, 0, 0), Color3.fromRGB(70, 74, 86))
	local arena = buildBowl(root, { name = "Arena", center = World.ARENA_CENTER, fence = false, dummies = false, accent = Color3.fromRGB(255, 110, 110) })
	local training = buildBowl(root, { name = "Training", center = World.TRAINING_CENTER, fence = true, dummies = true, accent = Color3.fromRGB(120, 220, 255) })
	local prompts = buildHub(root, villainName)
	-- Players should spawn in the hub, not inside a stadium.
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d.Name ~= "SpinforgeSpawn" then
			d.Enabled = false
		end
	end
	return { root = root, arena = arena, training = training, prompts = prompts, built = true }
end

-- Old builds put a "Stadium" folder in Workspace; remove it so it doesn't overlap the new world.
function World.removeLegacy()
	local old = Workspace:FindFirstChild("Stadium")
	if old and old:IsA("Folder") then
		old:Destroy()
	end
end

return World
]=====])
install('SPS', '', 'ModuleScript', 'Controller', [=====[
--!nonstrict
-- Controller: drives the local player's bey with MovementCore and runs the bey camera.
--   Binds when the player's bey appears in Workspace.Beys (named by UserId); unbinds when it's removed and then
--   ALWAYS restores the normal camera and mouse, so the avatar is playable after a battle, reset or interruption.
--   Physics for the player's bey is client-owned (see HANDOFF.md): this script writes its velocity each frame.
--
-- Input (all platforms):
--   move      WASD / left stick / touch stick (Roblox control module if present, else our own reader)
--   tilt      mouse / right stick / drag on the right half of the screen   (down = lean in, up = brake)
--   jump      Space / gamepad A / JUMP button          slam   click / right trigger / SLAM button (in the air)
--   practice  R or gamepad Y = reset bey, Q or gamepad B = back to the hub
--   camera    V or gamepad D-pad up = switch between the bey camera and the overhead stadium view
--             (overhead: W is always "up the screen", the mouse only tilts)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local MC = require(Shared.Core.MovementCore)
local LaunchCore = require(Shared.Core.LaunchCore)

local M = BeyConfig.Movement
local MAX_TILT = math.rad(M.MaxTiltDeg)
local BASE_FOV = 70
local OVERHEAD = { Height = 58, Back = 34, Follow = 0.35, Blend = 6 } -- overhead view: how high, how far back, how much it follows your bey

local Controller = {}

function Controller.start(ctx)
	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera
	local remotes, hud, effects, tutorial = ctx.remotes, ctx.hud, ctx.effects, ctx.tutorial
	local beysFolder = Workspace:WaitForChild("Beys", 30)
	if not beysFolder then
		hud:showError("Workspace.Beys never appeared: the server scripts did not start. Check Output for red errors.")
		return
	end

	-- state ------------------------------------------------------------------------------------------------
	local model, body, align
	local yaw, pitch, noseYaw = 0, 0, 0
	local up = Vector3.yAxis
	local ground, actions, stuck = MC.newGround(), MC.newActions(), MC.newStuck()
	local jumpQueued, slamQueued = false, false
	local pendingKnockback = Vector3.zero
	local pendingLaunch = nil -- { speed, boost } from the server's "started" event
	local pendingDash = nil -- { speed, dir } from a dash special
	local launchBoost, launchAt = 0, -math.huge
	local focus
	local movedFor, fastAt = 0, -math.huge
	local flipsAt, flipsRate, lastFlips = os.clock(), 0, 0
	local camMode = player:GetAttribute("CameraMode") == "Overhead" and "Overhead" or "Bey"
	local overheadYaw = 0
	local overheadBlend = camMode == "Overhead" and 1 or 0
	local speedMul = 1 -- spirit passive / awakening, from the server's snapshots
	local cine = { untilT = 0, zoom = 1, len = 1 } -- short zoom-in when you use a special
	local zoomNow = 1
	local lastCam

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local cameraParams = RaycastParams.new()
	cameraParams.FilterType = Enum.RaycastFilterType.Exclude
	local function refreshFilters()
		local ignore = { beysFolder }
		if player.Character then
			table.insert(ignore, player.Character)
		end
		local fx = Workspace:FindFirstChild("SpinforgeEffects")
		if fx then
			table.insert(ignore, fx)
		end
		rayParams.FilterDescendantsInstances = ignore
		local camIgnore = table.clone(ignore)
		local worldRoot = Workspace:FindFirstChild("SpinforgeWorld")
		if worldRoot then
			for _, f in ipairs(worldRoot:GetDescendants()) do
				if f.Name == "Barrier" and f:IsA("Folder") then
					table.insert(camIgnore, f)
				end
			end
		end
		cameraParams.FilterDescendantsInstances = camIgnore
	end
	refreshFilters()
	player.CharacterAdded:Connect(refreshFilters)

	-- move input: Roblox's control module if it loads, otherwise our own reader --------------------------------
	local controls = nil
	task.spawn(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if module then
			local ok, result = pcall(function()
				return require(module):GetControls()
			end)
			if ok then
				controls = result
			end
		end
	end)

	local touchStick = { input = nil, origin = Vector2.zero, vec = Vector2.zero }
	local function clearInputs()
		jumpQueued, slamQueued = false, false
		touchStick.input = nil
		touchStick.vec = Vector2.zero
	end
	UserInputService.WindowFocusReleased:Connect(clearInputs)

	UserInputService.TouchStarted:Connect(function(touch, processed)
		if processed or not body or touchStick.input or touch.Position.X > camera.ViewportSize.X * 0.5 then
			return
		end
		touchStick.input = touch
		touchStick.origin = Vector2.new(touch.Position.X, touch.Position.Y)
	end)
	UserInputService.TouchMoved:Connect(function(touch)
		if touch == touchStick.input then
			local d = (Vector2.new(touch.Position.X, touch.Position.Y) - touchStick.origin) / 60
			touchStick.vec = d.Magnitude > 1 and d.Unit or d
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		if touch == touchStick.input then
			touchStick.input = nil
			touchStick.vec = Vector2.zero
		end
	end)

	local function moveVector() -- x = right, z = back
		if UserInputService:GetFocusedTextBox() or hud:mouseFree() then
			return Vector3.zero
		end
		if controls then
			local ok, v = pcall(function()
				return controls:GetMoveVector()
			end)
			if ok and v and v.Magnitude > 0 then
				return v
			end
		end
		local K = Enum.KeyCode
		local x = (UserInputService:IsKeyDown(K.D) and 1 or 0) - (UserInputService:IsKeyDown(K.A) and 1 or 0)
		local z = (UserInputService:IsKeyDown(K.S) and 1 or 0) - (UserInputService:IsKeyDown(K.W) and 1 or 0)
		for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 and state.Position.Magnitude > 0.15 then
				x += state.Position.X
				z -= state.Position.Y
			end
		end
		x += touchStick.vec.X
		z += touchStick.vec.Y
		local v = Vector3.new(x, 0, z)
		return v.Magnitude > 1 and v.Unit or v
	end

	local function mode()
		return player:GetAttribute("Mode") or "OnFoot"
	end

	local function resetBey()
		if not body or body.Anchored then
			return
		end
		local at = player:GetAttribute("BeySpawn")
		if typeof(at) == "Vector3" then
			body.AssemblyLinearVelocity = Vector3.zero
			body.CFrame = CFrame.new(at)
		end
		ground, actions, stuck = MC.newGround(), MC.newActions(), MC.newStuck()
	end

	UserInputService.JumpRequest:Connect(function()
		if body then
			jumpQueued = true
		end
	end)
	hud.touchJump.Activated:Connect(function()
		jumpQueued = true
	end)
	hud.touchSlam.Activated:Connect(function()
		slamQueued = true
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not body or UserInputService:GetFocusedTextBox() then
			return
		end
		local kc = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not hud:mouseFree() then
			slamQueued = true
		elseif kc == Enum.KeyCode.ButtonR2 then
			slamQueued = true
		elseif kc == Enum.KeyCode.Space or kc == Enum.KeyCode.ButtonA then
			jumpQueued = true
		elseif kc == Enum.KeyCode.V or kc == Enum.KeyCode.DPadUp then
			camMode = camMode == "Overhead" and "Bey" or "Overhead"
			player:SetAttribute("CameraMode", camMode)
			if camMode == "Overhead" then
				overheadYaw = yaw
			end
			hud:toast(camMode == "Overhead" and "Overhead view  (V to switch back)" or "Bey view  (V for overhead)")
		elseif (kc == Enum.KeyCode.R or kc == Enum.KeyCode.ButtonY) and mode() == "Practice" then
			resetBey()
		elseif (kc == Enum.KeyCode.Q or kc == Enum.KeyCode.ButtonB) and mode() == "Practice" then
			remotes.Request:FireServer({ action = "exitPractice" })
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if not body or processed or input.UserInputType ~= Enum.UserInputType.Touch or input == touchStick.input then
			return
		end
		yaw -= input.Delta.X * M.TouchSensitivity
		pitch = math.clamp(pitch - input.Delta.Y * M.TouchSensitivity, -MAX_TILT, MAX_TILT)
	end)

	remotes.Knockback.OnClientEvent:Connect(function(v)
		if body and typeof(v) == "Vector3" and MC.finiteVector(v) then
			pendingKnockback = MC.clampMagnitude(pendingKnockback + v, 200)
			effects:shake(math.clamp(v.Magnitude / 80, 0.2, 1))
		end
	end)

	-- bind / unbind -----------------------------------------------------------------------------------------------
	local function unbind()
		model, body, align = nil, nil, nil
		clearInputs()
		pendingKnockback = Vector3.zero
		hud:showTouchButtons(false)
		tutorial:setActive(false)
		-- Always give the normal camera and mouse back.
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = BASE_FOV
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end

	local function bind(newModel)
		local b = newModel:WaitForChild("Body", 5)
		local a = newModel:WaitForChild("Align", 5)
		if not (b and a) or newModel.Parent ~= beysFolder then
			warn("Spinforge: bey model incomplete; not controlling it")
			return
		end
		model, body, align = newModel, b, a
		ground, actions, stuck = MC.newGround(), MC.newActions(), MC.newStuck()
		clearInputs()
		pendingKnockback = Vector3.zero
		pendingLaunch, launchBoost, launchAt = nil, 0, -math.huge
		speedMul, pendingDash = 1, nil
		local look = body.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		noseYaw, pitch, up, focus = yaw, 0, Vector3.yAxis, nil
		overheadYaw = yaw
		camera.CameraSubject = body
		hud:showTouchButtons(true)
		tutorial:setActive(true)
		refreshFilters()
	end

	beysFolder.ChildAdded:Connect(function(child)
		if child.Name == tostring(player.UserId) then
			bind(child)
		end
	end)
	beysFolder.ChildRemoved:Connect(function(child)
		if child == model then
			unbind()
		end
	end)
	for _, child in ipairs(beysFolder:GetChildren()) do
		if child.Name == tostring(player.UserId) then
			task.spawn(bind, child)
		end
	end

	-- physics step ----------------------------------------------------------------------------------------------
	local function readGamepadAim(dt)
		for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
			if state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.15 then
				yaw -= state.Position.X * 2.6 * dt
				pitch = math.clamp(pitch + state.Position.Y * 1.6 * dt, -MAX_TILT, MAX_TILT)
			end
		end
	end

	local function stats()
		return {
			Attack = body:GetAttribute("Attack") or 0,
			Balance = body:GetAttribute("Balance") or 0,
		}
	end

	local function step(rawDt)
		if not body or not body.Parent then
			return
		end
		local dt = MC.safeDt(rawDt, M)
		readGamepadAim(dt)
		if body.Anchored then
			jumpQueued, slamQueued = false, false
			return -- countdown: frozen by the server
		end
		local now = os.clock()
		local m = mode()
		local pos = body.Position

		if pos.Y < M.RespawnY and m == "Practice" then
			resetBey()
			return
		end

		local vel = MC.sanitizeVelocity(body.AssemblyLinearVelocity, M)
		if pendingKnockback.Magnitude > 0 then
			vel += pendingKnockback
			pendingKnockback = Vector3.zero
		end

		local tilt = math.clamp(pitch / MAX_TILT, -1, 1)
		local mv = moveVector()
		local yawCF = CFrame.Angles(0, yaw, 0)
		local wish = yawCF.RightVector * mv.X + yawCF.LookVector * -mv.Z
		if wish.Magnitude > 1 then
			wish = wish.Unit
		end
		local speed = MC.topSpeed(stats(), M) * LaunchCore.boostMultiplier(launchBoost, now - launchAt, GameConfig.Launch) * speedMul

		-- LET IT RIP: shoot off the line where the camera is aiming.
		if pendingLaunch then
			local aim = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
			aim = aim.Magnitude > 0.01 and aim.Unit or Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
			vel = Vector3.new(aim.X * pendingLaunch.speed, vel.Y, aim.Z * pendingLaunch.speed)
			launchBoost, launchAt = pendingLaunch.boost, now
			pendingLaunch = nil
		end

		-- dash special: burst toward the foe (the server already counted it; this only moves our own bey)
		if pendingDash then
			local d = pendingDash.dir
			vel = Vector3.new(d.X * pendingDash.speed, vel.Y, d.Z * pendingDash.speed)
			pendingDash = nil
		end

		-- ground probe: a sphere cast (wider than a ray, so slab seams don't drop us), ray as fallback
		local normal
		if not MC.probeSuppressed(actions, now, M) then
			local dist = M.Radius - M.ProbeRadius + M.GroundProbe
			local ok, hit = pcall(function()
				return Workspace:Spherecast(pos, M.ProbeRadius, Vector3.new(0, -dist, 0), rayParams)
			end)
			if not ok then
				hit = Workspace:Raycast(pos, Vector3.new(0, -(M.Radius + M.GroundProbe), 0), rayParams)
			end
			normal = hit and hit.Normal or nil
		end
		local ev = MC.updateGround(ground, normal, now, M)
		if MC.resolveActions(actions, ev, now, M) == "impact" then
			remotes.SlamLanded:FireServer()
			effects:slamRing(pos - Vector3.new(0, M.Radius - 0.2, 0), math.clamp(-vel.Y / M.SlamSpeed, 0.4, 1))
			effects:shake(0.6)
			tutorial:signal("slammed")
		end

		if ground.grounded then
			vel = MC.groundVelocity(vel, ground.normal, wish, tilt, speed, dt, M)
			if jumpQueued and MC.canJump(actions, ground, now, M) then
				vel = MC.jump(actions, ground, vel, tilt, now, M)
			end
		else
			if ev == "tookoff" then
				local boost = MC.takeoffBoost(actions, vel, tilt, M)
				if boost ~= 0 then
					vel += Vector3.new(0, boost, 0)
					if tilt > 0.25 then
						tutorial:signal("launched")
					end
				end
			end
			vel = MC.airVelocity(vel, wish, tilt, speed, actions.slam == "diving", dt, M)
			if slamQueued and MC.canSlam(actions, ground, now, M) then
				vel = MC.startSlam(actions, vel, now, M)
			end
		end
		jumpQueued, slamQueued = false, false

		-- recovery: wedged somewhere in the air without moving
		if MC.isStuck(stuck, ground.grounded, vel, now, M) then
			if m == "Practice" then
				resetBey()
				return
			end
			local center = player:GetAttribute("ArenaCenter")
			local toCenter = typeof(center) == "Vector3" and Vector3.new(center.X - pos.X, 0, center.Z - pos.Z) or Vector3.zero
			vel = Vector3.new(0, 30, 0) + (toCenter.Magnitude > 0.1 and toCenter.Unit * 20 or Vector3.zero)
			stuck = MC.newStuck()
		end

		vel = MC.sanitizeVelocity(vel, M)
		body.AssemblyLinearVelocity = vel

		-- tutorial signals
		local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		if mv.Magnitude > 0.5 then
			movedFor += dt
			if movedFor > 1 then
				tutorial:signal("moved")
			end
		end
		if flatSpeed > 20 then
			fastAt = now
		end
		if tilt < -0.5 and flatSpeed > speed then
			tutorial:signal("leaned")
		end
		if tilt > 0.5 and flatSpeed < 8 and now - fastAt < 3 then
			tutorial:signal("braked")
		end

		-- orientation: lean with the surface, then the player's tilt; wobble when low on spin
		noseYaw = MC.noseYaw(noseYaw, vel, dt, M)
		up = MC.surfaceUp(up, ground.grounded and ground.normal or nil, dt, M)
		local r, u, b = MC.frame(up, noseYaw)
		local spin, maxSpin = body:GetAttribute("Spin"), body:GetAttribute("MaxSpin")
		local wobble = 0
		local low = GameConfig.Combat.LowSpinFraction
		if spin and maxSpin and maxSpin > 0 and spin / maxSpin < low then
			wobble = math.sin(now * 9) * 0.25 * (1 - (spin / maxSpin) / low)
		end
		align.CFrame = CFrame.fromMatrix(Vector3.zero, r, u, b) * CFrame.Angles(pitch, 0, wobble)

		-- HUD
		local readyFrac = 1 - math.max(actions.slamReadyAt - now, 0) / M.SlamCooldown
		if ground.grounded then
			readyFrac = math.min(readyFrac, 0.99)
		end
		hud:setSlam(readyFrac, actions.slam == "diving")
	end
	RunService.Heartbeat:Connect(step)

	-- camera ----------------------------------------------------------------------------------------------------
	RunService:BindToRenderStep("SpinforgeCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not body or not body.Parent then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		if hud:mouseFree() then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
			local delta = UserInputService:GetMouseDelta()
			if camMode ~= "Overhead" then
				yaw -= delta.X * M.MouseSensitivity
			end
			pitch = math.clamp(pitch - delta.Y * M.MouseSensitivity, -MAX_TILT, MAX_TILT)
		end
		if camMode == "Overhead" then
			yaw = overheadYaw -- W = up the screen
		end
		-- impact freeze: hold the camera for a moment on a hit
		if lastCam and effects:frozen() then
			camera.CFrame = lastCam * effects:shakeOffset(dt)
			return
		end
		local now = os.clock()
		local zoomWanted = 1
		if now < cine.untilT then
			local t = 1 - (cine.untilT - now) / cine.len
			zoomWanted = t < 0.7 and cine.zoom or 1
		end
		zoomNow += (zoomWanted - zoomNow) * (1 - math.exp(-(zoomWanted < zoomNow and 14 or 5) * dt))
		overheadBlend += ((camMode == "Overhead" and 1 or 0) - overheadBlend) * (1 - math.exp(-OVERHEAD.Blend * dt))

		local target = body.Position + Vector3.new(0, M.CameraHeight, 0)
		focus = focus and focus:Lerp(target, 1 - math.exp(-22 * dt)) or target
		local camPitch = math.clamp(M.CameraBasePitch - pitch * 0.8, M.CameraMinPitch, 1.1)
		local beyEye = (CFrame.new(focus) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-camPitch, 0, 0) * CFrame.new(0, 0, M.CameraDistance * zoomNow)).Position
		local hit = Workspace:Raycast(focus, beyEye - focus, cameraParams)
		if hit then
			beyEye = hit.Position + (focus - hit.Position).Unit * 0.8
		end
		local eye, look = beyEye, focus
		if overheadBlend > 0.001 then
			local center = player:GetAttribute("ArenaCenter")
			center = typeof(center) == "Vector3" and center or body.Position
			local follow = OVERHEAD.Follow + (1 - zoomNow) * 1.4 -- a special pulls the view onto your bey
			local lookAt = center:Lerp(body.Position, math.clamp(follow, 0, 1))
			local flatBack = CFrame.Angles(0, overheadYaw, 0).LookVector * -1
			local topEye = lookAt + Vector3.new(0, OVERHEAD.Height * zoomNow, 0) + flatBack * OVERHEAD.Back * zoomNow
			eye = beyEye:Lerp(topEye, overheadBlend)
			look = focus:Lerp(lookAt, overheadBlend)
		end
		lastCam = CFrame.lookAt(eye, look)
		camera.FieldOfView = BASE_FOV + effects:fovOffset(dt)
		camera.CFrame = lastCam * effects:shakeOffset(dt)
	end)

	-- Called by Main when the battle starts. Applied on the first unfrozen frame.
	function Controller.launch(speed, boost)
		if body and MC.finite(speed) and MC.finite(boost) then
			pendingLaunch = { speed = math.clamp(speed, 0, 120), boost = math.clamp(boost, 0, 1) }
		end
	end

	function Controller.isBound()
		return body ~= nil and body.Parent ~= nil
	end

	-- A dash special was used: burst toward dir at speed on the next physics step.
	function Controller.dash(speed, dir)
		if body and MC.finite(speed) and typeof(dir) == "Vector3" and MC.finiteVector(dir) then
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0.01 then
				pendingDash = { speed = math.clamp(speed, 0, 150), dir = flat.Unit }
			end
		end
	end

	-- Top-speed multiplier from the spirit passive / awakening (sent by the server).
	function Controller.setSpeedMultiplier(m)
		if MC.finite(m) then
			speedMul = math.clamp(m, 0.5, 1.5)
		end
	end

	-- Short zoom onto your bey (your special / awakening). zoom < 1 = closer.
	function Controller.cinematic(duration, zoom)
		cine.len = math.max(duration or 1, 0.1)
		cine.untilT = os.clock() + cine.len
		cine.zoom = math.clamp(zoom or 0.7, 0.3, 1)
	end

	function Controller.cameraMode()
		return camMode
	end

	-- diagnostics (F6) ------------------------------------------------------------------------------------------
	function Controller.diag()
		local now = os.clock()
		if now - flipsAt >= 1 then
			flipsRate = (ground.flips - lastFlips) / (now - flipsAt)
			lastFlips, flipsAt = ground.flips, now
		end
		if not body then
			return "bey: none (on foot)"
		end
		local v = body.AssemblyLinearVelocity
		return ("bey: bound%s\nground: %s  flips/s %.1f\nspeed %.0f  vy %.0f\ntilt %+.0f deg  slam %s\nmove src: %s"):format(
			body.Anchored and " (frozen)" or "",
			ground.grounded and "yes" or "no",
			flipsRate,
			Vector3.new(v.X, 0, v.Z).Magnitude,
			v.Y,
			math.deg(pitch),
			actions.slam,
			controls and "control module" or "fallback reader"
		)
	end
end

function Controller.diag()
	return "controller not started"
end

function Controller.isBound()
	return false
end

function Controller.launch() end
function Controller.dash() end
function Controller.setSpeedMultiplier() end
function Controller.cinematic() end
function Controller.cameraMode()
	return "Bey"
end

return Controller
]=====])
install('SPS', '', 'ModuleScript', 'Effects', [=====[
--!nonstrict
-- Effects: client-only visual feedback with hard caps (pooled parts, never more than MAX_* alive at once).
--   impact(pos, normal, strength, opts)  a bey-on-bey hit: white flash, light burst, floor shockwave, streak sparks,
--                                        chips, camera shake, a short impact freeze (hitstop) and an FOV kick.
--                                        opts = { crit = bool (empowered hit: everything bigger), color = Color3 }
--   slamRing(pos, scale, color)          expanding ring where a slam lands
--   sparks(pos, color, n)                small chips flying out
--   burst(pos, color, radius)            a big coloured shockwave + light (specials, quakes)
--   trackBeys(folder)                    gives every bey a motion trail and a soft glow on the floor
--   shake(amount)                        camera shake impulse (off when the player disables it)
--   shakeOffset(dt), fovOffset(dt), frozen()   read by the camera every frame
-- Reduced effects (setting) skips sparks/particles and shrinks rings; camera shake has its own setting.
-- Unverified in Roblox: how strong all of this looks and feels. Tune the numbers in TUNE.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sounds = require(script.Parent.Sounds)

local Effects = {}
Effects.__index = Effects

local MAX_RINGS = 8
local MAX_SPARKS = 32
local MAX_FLASHES = 6
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds" -- ships with every Roblox client

local TUNE = {
	FlashSize = 5, -- white flash ball diameter at strength 1 (x1.6 on a crit)
	ShockRadius = 12, -- floor ring radius at strength 1
	LightBrightness = 7,
	LightRange = 22,
	StreakCount = 18, -- streak sparks per hit at strength 1
	Hitstop = 0.035, -- seconds the camera holds on a hit (+ more for strength and crits)
	HitstopCrit = 0.09,
	FovKick = 7, -- degrees at strength 1
	TrailLife = 0.22,
}
Effects.TUNE = TUNE

function Effects.new(getSettings)
	local self = setmetatable({}, Effects)
	self.getSettings = getSettings
	self.folder = Instance.new("Folder")
	self.folder.Name = "SpinforgeEffects"
	self.folder.Parent = Workspace
	self.rings, self.sparkParts, self.flashes = {}, {}, {}
	self.active = 0
	self.shakeAmount = 0
	self.fov = 0
	self.freezeUntil = 0

	-- one emitter for every streak spark (Emit() bursts are cheap; the part moves to each hit)
	local host = Instance.new("Part")
	host.Name = "SparkHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Parent = self.folder
	local att = Instance.new("Attachment")
	att.Parent = host
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Streaks"
	pe.Enabled = false
	pe.Texture = SPARK_TEXTURE
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Orientation = Enum.ParticleOrientation.VelocityParallel
	pe.Squash = NumberSequence.new(2.2) -- long thin streaks along their flight
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.12, 0.32)
	pe.Speed = NumberRange.new(40, 95)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -70, 0)
	pe.Drag = 3
	pe.Parent = att
	self.streaks = pe
	self.sparkHost = host
	return self
end

local function makePart(folder, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Shape = shape
	p.Transparency = 1
	p.Size = Vector3.new(0.4, 1, 1)
	p.Parent = folder
	return p
end

-- Takes a free part from a pool (or makes one under the cap). Returns nil when the cap is reached.
local function take(pool, max, folder, shape)
	for _, p in ipairs(pool) do
		if not p:GetAttribute("Busy") then
			p:SetAttribute("Busy", true)
			return p
		end
	end
	if #pool < max then
		local p = makePart(folder, shape)
		p:SetAttribute("Busy", true)
		table.insert(pool, p)
		return p
	end
	return nil
end

function Effects:_play(p, goal, time, style)
	self.active += 1
	local tween = TweenService:Create(p, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween.Completed:Connect(function()
		p.Transparency = 1
		p:SetAttribute("Busy", false)
		self.active -= 1
	end)
	tween:Play()
end

-- A flat ring on the floor at pos, growing to `radius`.
function Effects:_ring(pos, radius, color, time, startTransparency)
	local p = take(self.rings, MAX_RINGS, self.folder, Enum.PartType.Cylinder)
	if not p then
		return
	end
	p.Color = color
	p.Size = Vector3.new(0.3, 2, 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Transparency = startTransparency or 0.15
	self:_play(p, { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 }, time)
end

local function light(parent, color, brightness, range, time)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
	TweenService:Create(l, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(l, time + 0.05)
end

-- Bey-on-bey hit. strength 0..1 (closing speed), normal = direction of the hit (A -> B).
function Effects:impact(pos, normal, strength, opts)
	opts = opts or {}
	local s = self.getSettings()
	strength = math.clamp(strength or 0.5, 0.15, 1)
	local crit = opts.crit == true
	local big = crit and 1.6 or 1
	local color = opts.color or Color3.fromRGB(255, 220, 140)

	-- white-hot flash ball
	local f = take(self.flashes, MAX_FLASHES, self.folder, Enum.PartType.Ball)
	if f then
		f.Color = Color3.new(1, 1, 1)
		f.Size = Vector3.new(1, 1, 1)
		f.CFrame = CFrame.new(pos)
		f.Transparency = 0
		local d = TUNE.FlashSize * (0.5 + strength) * big
		self:_play(f, { Size = Vector3.new(d, d, d), Transparency = 1 }, crit and 0.2 or 0.13)
		light(f, color, TUNE.LightBrightness * strength * big, TUNE.LightRange * big, crit and 0.35 or 0.22)
	end
	-- shockwave on the floor (the bowl is ~1.6 below the bey centre)
	local floor = pos - Vector3.new(0, 1.7, 0)
	local radius = TUNE.ShockRadius * (0.4 + 0.6 * strength) * big * (s.ReducedEffects and 0.6 or 1)
	self:_ring(floor, radius, color, crit and 0.4 or 0.28, 0.1)
	if crit then
		self:_ring(floor, radius * 1.6, Color3.new(1, 1, 1), 0.55, 0.4)
	end
	-- streak sparks + chips
	if not s.ReducedEffects then
		self.sparkHost.CFrame = CFrame.new(pos)
		self.streaks.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		self.streaks:Emit(math.floor(TUNE.StreakCount * (0.4 + 0.6 * strength) * big))
		self:sparks(pos, color, crit and 8 or 4)
	end
	-- camera: shake, freeze, FOV kick
	self:shake((0.35 + 0.45 * strength) * big)
	if s.CameraShake then
		local hold = TUNE.Hitstop * (0.5 + strength) + (crit and TUNE.HitstopCrit or 0)
		self.freezeUntil = math.max(self.freezeUntil, os.clock() + hold)
		self.fov = math.max(self.fov, TUNE.FovKick * strength * big)
	end
	Sounds.play(crit and "HitHeavy" or "Hit", 0.5 + 0.5 * strength, 0.9 + math.random() * 0.25)
end

function Effects:slamRing(pos, scale, color)
	local s = self.getSettings()
	local r = (s.ReducedEffects and 10 or 18) * math.clamp(scale or 1, 0.3, 1.5)
	self:_ring(pos, r, color or Color3.fromRGB(255, 120, 60), 0.35, 0.2)
end

-- Big coloured burst: specials, quakes, awakenings.
function Effects:burst(pos, color, radius)
	local s = self.getSettings()
	radius = radius or 16
	self:_ring(pos, radius, color, 0.45, 0.05)
	self:_ring(pos, radius * 0.6, Color3.new(1, 1, 1), 0.3, 0.3)
	local f = take(self.flashes, MAX_FLASHES, self.folder, Enum.PartType.Ball)
	if f then
		f.Color = color
		f.Size = Vector3.new(2, 2, 2)
		f.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0))
		f.Transparency = 0.2
		self:_play(f, { Size = Vector3.new(radius, radius * 0.6, radius), Transparency = 1 }, 0.4)
		light(f, color, 6, radius * 2.2, 0.6)
	end
	if not s.ReducedEffects then
		self.sparkHost.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0))
		self.streaks.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		self.streaks:Emit(24)
	end
end

function Effects:sparks(pos, color, n)
	local s = self.getSettings()
	if s.ReducedEffects then
		return
	end
	for _ = 1, math.min(n or 6, 10) do
		local p = take(self.sparkParts, MAX_SPARKS, self.folder, Enum.PartType.Ball)
		if not p then
			return
		end
		p.Color = color or Color3.fromRGB(255, 230, 150)
		p.Size = Vector3.new(0.5, 0.5, 0.5)
		p.CFrame = CFrame.new(pos)
		p.Transparency = 0
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
		self:_play(p, { CFrame = CFrame.new(pos + dir * (3 + math.random() * 4)), Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 }, 0.35)
	end
end

-------------------------------------------------------------------------------- trails and glow on every bey

local function addTrail(model)
	local body = model:WaitForChild("Body", 5)
	if not body or body:FindFirstChild("SpinTrail") then
		return
	end
	local accent = model:GetAttribute("Accent")
	if typeof(accent) ~= "Color3" then
		accent = model:GetAttribute("Villain") and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(120, 220, 255)
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 0.1, 0)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -1.3, 0)
	a1.Parent = body
	local t = Instance.new("Trail")
	t.Name = "SpinTrail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.FaceCamera = true -- reads from the bey camera and from overhead
	t.Lifetime = TUNE.TrailLife
	t.MinLength = 0.2
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Color = ColorSequence.new(Color3.new(1, 1, 1), accent)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
	t.Parent = body
	local glow = Instance.new("PointLight")
	glow.Name = "FloorGlow"
	glow.Color = accent
	glow.Brightness = 1.4
	glow.Range = 9
	glow.Shadows = false
	glow.Parent = body
end

function Effects:trackBeys(folder)
	if not folder then
		return
	end
	folder.ChildAdded:Connect(function(m)
		task.spawn(addTrail, m)
	end)
	for _, m in ipairs(folder:GetChildren()) do
		task.spawn(addTrail, m)
	end
end

-------------------------------------------------------------------------------- camera feedback

function Effects:shake(amount)
	if self.getSettings().CameraShake then
		self.shakeAmount = math.min(self.shakeAmount + amount, 1.4)
	end
end

-- Camera offset for this frame; decays quickly.
function Effects:shakeOffset(dt)
	if self.shakeAmount <= 0.001 then
		self.shakeAmount = 0
		return CFrame.new()
	end
	local a = self.shakeAmount
	self.shakeAmount = math.max(0, a - dt * 3)
	return CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0) * CFrame.Angles(0, 0, (math.random() - 0.5) * a * 0.03)
end

-- Extra field of view this frame (a quick kick on hits that settles back).
function Effects:fovOffset(dt)
	self.fov = math.max(0, self.fov - dt * 40)
	return self.fov
end

-- True during the short impact freeze after a hit (the camera holds still for a moment).
function Effects:frozen()
	return os.clock() < self.freezeUntil
end

function Effects:count()
	return self.active
end

return Effects
]=====])
install('SPS', '', 'ModuleScript', 'Hud', [=====[
--!nonstrict
-- Hud: everything drawn on screen during play. Created once per client (ResetOnSpawn off), so respawns and
-- re-binds never duplicate it. Other client modules call its methods; it holds no game rules.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent.Ui)
local C = Ui.C

local Hud = {}
Hud.__index = Hud

local REASON = {
	stopped = "stopped spinning",
	ringout = "was knocked out of the stadium",
	time = "time ran out: more spin left wins",
	both = "both beys went down together",
	left = "the battle was abandoned",
}

function Hud.new(player)
	local self = setmetatable({}, Hud)
	self.player = player
	self.panelsOpen = 0
	local gui = Ui.make("ScreenGui", { Name = "SpinforgeHud", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, nil)
	self.gui = gui
	local scale = Ui.make("UIScale", { Scale = 1 }, gui)
	local function rescale()
		local cam = Workspace.CurrentCamera
		local w = cam and cam.ViewportSize.X or 1000
		scale.Scale = math.clamp(w / 1100, 0.62, 1)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- flash overlay (behind everything else)
	self.flashFrame = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bad, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0 }, gui)

	-- profile chip (top left)
	local prof = Ui.panel(gui, { Name = "Profile", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(250, 92) })
	Ui.pad(prof, 10)
	self.levelLabel = Ui.label(prof, { Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBold, TextSize = 18, Text = "Loading..." })
	self.xpFill = Ui.bar(prof, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 8) }, C.accent)
	self.shardLabel = Ui.label(prof, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.gold, TextSize = 15 })
	self.workshopBtn = Ui.button(prof, "Workshop", { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(0.5, -4, 0, 26), TextSize = 14 })
	self.settingsBtn = Ui.button(prof, "Settings", { Position = UDim2.new(0.5, 4, 0, 58), Size = UDim2.new(0.5, -4, 0, 26), TextSize = 14 })
	self.profileFrame = prof

	-- save banner
	self.saveBanner = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(520, 26),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(90, 50, 10),
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Visible = false,
	})
	Ui.corner(self.saveBanner, 6)

	-- battle bar (top centre)
	local bb = Ui.panel(gui, { Name = "Battle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 38), Size = UDim2.fromOffset(620, 74), Visible = false })
	Ui.pad(bb, 10)
	self.youName = Ui.label(bb, { Size = UDim2.new(0.42, 0, 0, 18), Font = Enum.Font.GothamBold, TextSize = 15, Text = "YOU" })
	self.youFill, self.youBack = Ui.bar(bb, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(0.42, 0, 0, 16) }, C.accent)
	self.youText = Ui.label(bb, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(0.42, 0, 0, 16), TextSize = 13, TextColor3 = C.muted })
	self.foeName = Ui.label(bb, { Position = UDim2.new(0.58, 0, 0, 0), Size = UDim2.new(0.42, 0, 0, 18), Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right })
	self.foeFill, self.foeBack = Ui.bar(bb, { Position = UDim2.new(0.58, 0, 0, 22), Size = UDim2.new(0.42, 0, 0, 16) }, C.bad)
	self.foeText = Ui.label(bb, { Position = UDim2.new(0.58, 0, 0, 40), Size = UDim2.new(0.42, 0, 0, 16), TextSize = 13, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Right })
	self.timer = Ui.label(bb, { Position = UDim2.new(0.42, 0, 0, 4), Size = UDim2.new(0.16, 0, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
	self.diffLabel = Ui.label(bb, { Position = UDim2.new(0.42, 0, 0, 36), Size = UDim2.new(0.16, 0, 0, 16), TextSize = 12, TextColor3 = C.warn, TextXAlignment = Enum.TextXAlignment.Center })
	self.battleFrame = bb

	-- big centre text (countdown, GO, queue)
	self.center = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(600, 90),
		Font = Enum.Font.GothamBlack,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Text = "",
	})

	-- slam readiness + low spin (bottom centre)
	local sl = Ui.panel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(220, 34), Visible = false })
	self.slamFill = Ui.bar(sl, { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12) }, C.warn)
	self.slamText = Ui.label(sl, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, TextSize = 14, Text = "SLAM", ZIndex = 3 })
	self.slamFrame = sl
	self.lowSpin = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -158),
		Size = UDim2.fromOffset(300, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = C.bad,
		Text = "LOW SPIN",
		Visible = false,
	})

	-- mode panel (bottom left): practice info / forfeit
	local mp = Ui.panel(gui, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.fromOffset(250, 76), Visible = false })
	Ui.pad(mp, 10)
	self.modeTitle = Ui.label(mp, { Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.GothamBold, TextSize = 15 })
	self.modeHint = Ui.label(mp, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = C.muted })
	self.modeBtn = Ui.button(mp, "Leave", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 26), TextSize = 14 })
	self.modeFrame = mp

	-- result panel
	local rp = Ui.panel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 280), Visible = false, ZIndex = 10 })
	Ui.pad(rp, 18)
	self.resultTitle = Ui.label(rp, { Size = UDim2.new(1, 0, 0, 44), Font = Enum.Font.GothamBlack, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.resultReason = Ui.label(rp, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.resultReward = Ui.label(rp, { Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 48), TextColor3 = C.gold, Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.resultNext = Ui.label(rp, { Position = UDim2.fromOffset(0, 132), Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.warn, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.rematchBtn = Ui.button(rp, "Rematch", { Position = UDim2.new(0, 0, 1, -66), Size = UDim2.new(0.5, -6, 0, 44), BackgroundColor3 = Color3.fromRGB(30, 90, 120), ZIndex = 11 })
	self.leaveBtn = Ui.button(rp, "Back to hub", { Position = UDim2.new(0.5, 6, 1, -66), Size = UDim2.new(0.5, -6, 0, 44), ZIndex = 11 })
	self.resultClose = Ui.label(rp, { Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.muted, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.resultFrame = rp

	-- launch meter (during the countdown): a needle sweeps across; lock it in the green zone
	local lm = Ui.panel(gui, { Name = "Launch", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -160), Size = UDim2.fromOffset(460, 92), Visible = false, ZIndex = 8 })
	Ui.pad(lm, 10)
	self.launchTitle = Ui.label(lm, { Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Text = "LAUNCH: stop the needle in the GREEN", ZIndex = 9 })
	local track = Ui.make("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Color3.fromRGB(70, 30, 30), BorderSizePixel = 0, ZIndex = 9 }, lm)
	Ui.corner(track, 6)
	self.launchYellow = Ui.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = C.warn, BorderSizePixel = 0, ZIndex = 10 }, track)
	self.launchGreen = Ui.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromScale(0.12, 1), BackgroundColor3 = C.good, BorderSizePixel = 0, ZIndex = 11 }, track)
	self.launchNeedle = Ui.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 6, 1, 12), BackgroundColor3 = C.text, BorderSizePixel = 0, ZIndex = 12 }, track)
	Ui.corner(self.launchNeedle, 3)
	self.launchHint = Ui.label(lm, { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 })
	self.launchFrame = lm
	self.touchLaunch = Ui.button(gui, "LAUNCH", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -150), Size = UDim2.fromOffset(120, 120), BackgroundColor3 = Color3.fromRGB(40, 130, 70), TextSize = 22, Visible = false, ZIndex = 9 })
	Ui.corner(self.touchLaunch, 60)

	-- toasts (top centre, under the battle bar)
	self.toastLabel = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(560, 30),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = C.panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Visible = false,
	})
	Ui.corner(self.toastLabel, 8)

	-- tutorial hint card (right side)
	local hint = Ui.panel(gui, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(280, 104), Visible = false })
	Ui.pad(hint, 12)
	self.hintStep = Ui.label(hint, { Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = C.accent, Font = Enum.Font.GothamBold })
	self.hintTitle = Ui.label(hint, { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.GothamBold, TextSize = 18 })
	self.hintBody = Ui.label(hint, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 40), TextSize = 14, TextColor3 = C.muted, TextYAlignment = Enum.TextYAlignment.Top })
	self.hintFrame = hint

	-- touch buttons (shown by the controller while a bey is bound on touch devices)
	self.touchSlam = Ui.button(gui, "SLAM", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -150), Size = UDim2.fromOffset(96, 96), BackgroundColor3 = Color3.fromRGB(150, 50, 50), TextSize = 20, Visible = false })
	Ui.corner(self.touchSlam, 48)
	self.touchJump = Ui.button(gui, "JUMP", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -132, 1, -60), Size = UDim2.fromOffset(80, 80), BackgroundColor3 = Color3.fromRGB(40, 90, 130), TextSize = 18, Visible = false })
	Ui.corner(self.touchJump, 40)

	-- diagnostics (F6) and errors
	self.diag = Ui.label(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(300, 150),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.new(0, 0, 0),
		Font = Enum.Font.Code,
		TextSize = 13,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
	})
	self.errorLabel = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 120),
		BackgroundTransparency = 0.05,
		BackgroundColor3 = Color3.fromRGB(70, 20, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Visible = false,
		ZIndex = 20,
	})
	Ui.corner(self.errorLabel, 10)

	gui.Parent = player:WaitForChild("PlayerGui")
	return self
end

-------------------------------------------------------------------------------- profile, mode

function Hud:setProfile(p)
	self.levelLabel.Text = ("Level %d"):format(p.Level)
	self.shardLabel.Text = ("%d Shards   ·   %dW %dL %dD"):format(p.Shards, p.Record.Wins, p.Record.Losses, p.Record.Draws)
	if p.XPNext and p.XPNext > p.XPThis then
		self.xpFill.Size = UDim2.fromScale(math.clamp((p.XP - p.XPThis) / (p.XPNext - p.XPThis), 0, 1), 1)
	else
		self.xpFill.Size = UDim2.fromScale(1, 1)
	end
	local banner = {
		nosave = "Progress is NOT being saved this session (no DataStore access).",
		locked = "Your save is open on another server: progress here is NOT saved.",
		newer = "Your save is from a newer version: progress here is NOT saved.",
		loading = "Loading your profile...",
	}
	self.saveBanner.Text = banner[p.SaveStatus] or ""
	self.saveBanner.Visible = banner[p.SaveStatus] ~= nil
end

-- mode: "OnFoot" | "Practice" | "Battle"
function Hud:setMode(mode, onLeave)
	self.profileFrame.Visible = mode == "OnFoot"
	self.slamFrame.Visible = mode ~= "OnFoot"
	if mode == "Practice" then
		self.modeTitle.Text = "PRACTICE"
		self.modeHint.Text = "R: reset bey   ·   Q: back to hub"
		self.modeBtn.Text = "Back to hub"
		self.modeFrame.Visible = true
	elseif mode == "Battle" then
		self.modeTitle.Text = "BATTLE"
		self.modeHint.Text = "Knock it out or outlast it"
		self.modeBtn.Text = "Forfeit"
		self.modeFrame.Visible = true
	else
		self.modeFrame.Visible = false
		self.lowSpin.Visible = false
	end
	self.onModeButton = onLeave
end

-------------------------------------------------------------------------------- battle

function Hud:countdown(seconds, foe, difficulty)
	self.battleFrame.Visible = true
	self.youName.Text = "YOU"
	self.foeName.Text = string.upper(foe or "Villain")
	self.diffLabel.Text = string.upper(difficulty or "")
	self.timer.Text = ""
	task.spawn(function()
		for i = seconds, 1, -1 do
			self.center.TextColor3 = C.text
			self.center.Text = tostring(i)
			task.wait(1)
		end
	end)
end

local LAUNCH_COLOR = { PERFECT = C.good, GOOD = C.warn, WEAK = C.bad, ["TOO LATE"] = C.bad }

-- Shows the launch meter for this battle. meter: positions as shares of the bar (see Core/LaunchCore).
function Hud:showLaunch(meter)
	self.launchMeter = meter
	self.launchLocked = false
	self.launchGreen.Position = UDim2.fromScale(meter.zoneCenter, 0)
	self.launchGreen.Size = UDim2.fromScale(meter.greenHalf * 2, 1)
	self.launchYellow.Position = UDim2.fromScale(meter.zoneCenter, 0)
	self.launchYellow.Size = UDim2.fromScale(meter.yellowHalf * 2, 1)
	self.launchTitle.Text = "LAUNCH: stop the needle in the GREEN"
	self.launchTitle.TextColor3 = C.text
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local pad = UserInputService.GamepadEnabled
	self.launchHint.Text = touch and "Tap LAUNCH" or pad and "Press A" or "Press SPACE or click"
	self.launchFrame.Visible = true
	self.touchLaunch.Visible = UserInputService.TouchEnabled
	self.touchSlam.Visible = false
end

-- Moves the needle (pos 0..1) until it is locked.
function Hud:setNeedle(pos)
	if not self.launchLocked then
		self.launchNeedle.Position = UDim2.fromScale(math.clamp(pos, 0, 1), 0.5)
	end
end

function Hud:lockLaunch(pos, label, quality)
	self.launchLocked = true
	if pos then
		self.launchNeedle.Position = UDim2.fromScale(math.clamp(pos, 0, 1), 0.5)
	end
	self.launchTitle.Text = label .. "!" .. (type(quality) == "number" and ("  %d%%"):format(math.floor(math.clamp(quality, 0, 1) * 100 + 0.5)) or "")
	self.launchTitle.TextColor3 = LAUNCH_COLOR[label] or C.text
	self.touchLaunch.Visible = false
end

function Hud:hideLaunch()
	self.launchFrame.Visible = false
	self.touchLaunch.Visible = false
	self.launchMeter = nil
	self.touchSlam.Visible = self.touchButtonsShown == true and UserInputService.TouchEnabled
end

-- "LET IT RIP!" plus how good the launch was and what it gave you.
function Hud:started(launch, foeLaunch)
	self:hideLaunch()
	self.center.TextColor3 = C.good
	self.center.Text = "LET IT RIP!"
	if launch then
		local pct = math.floor((launch.spin or 1) * 100 + 0.5)
		self:toast(("%s launch: %d%% spin, +%d%% speed boost%s"):format(
			launch.label == "TOO LATE" and "Late" or (launch.label:sub(1, 1) .. launch.label:sub(2):lower()),
			pct,
			math.floor((launch.boost or 0) * 100 + 0.5),
			foeLaunch and ("   ·   Rival: " .. foeLaunch:lower()) or ""
		), LAUNCH_COLOR[launch.label])
	end
	task.delay(1, function()
		if self.center.Text == "LET IT RIP!" then
			self.center.Text = ""
		end
	end)
end

-- Called every frame by Main while a battle is shown.
function Hud:updateBattle(youSpin, youMax, foeSpin, foeMax, endsAt, state)
	local yf = youMax > 0 and math.clamp(youSpin / youMax, 0, 1) or 0
	local ff = foeMax > 0 and math.clamp(foeSpin / foeMax, 0, 1) or 0
	self.youFill.Size = UDim2.fromScale(yf, 1)
	self.foeFill.Size = UDim2.fromScale(ff, 1)
	self.youText.Text = ("%d / %d spin"):format(math.ceil(youSpin), math.ceil(youMax))
	self.foeText.Text = ("%d / %d spin"):format(math.ceil(foeSpin), math.ceil(foeMax))
	if state == "active" and endsAt and endsAt > 0 then
		local left = math.max(0, endsAt - Workspace:GetServerTimeNow())
		self.timer.Text = ("%d"):format(math.ceil(left))
		self.timer.TextColor3 = left < 10 and C.bad or C.text
	end
	local low = state == "active" and yf < 0.25
	self.lowSpin.Visible = low
	if low then
		self.youFill.BackgroundColor3 = (math.floor(os.clock() * 4) % 2 == 0) and C.bad or C.accent
	else
		self.youFill.BackgroundColor3 = C.accent
	end
end

function Hud:setSlam(readyFraction, diving)
	if diving then
		self.slamText.Text = "SLAMMING"
		self.slamFill.Size = UDim2.fromScale(1, 1)
	elseif readyFraction >= 1 then
		self.slamText.Text = "SLAM READY (in the air)"
		self.slamFill.Size = UDim2.fromScale(1, 1)
	else
		self.slamText.Text = "SLAM"
		self.slamFill.Size = UDim2.fromScale(math.clamp(readyFraction, 0, 1), 1)
	end
end

function Hud:flash(color, strength)
	self.flashFrame.BackgroundColor3 = color
	self.flashFrame.BackgroundTransparency = 1 - 0.35 * math.clamp(strength or 1, 0, 1)
	TweenService:Create(self.flashFrame, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
end

-- Floating number next to a bar ("-12" in red under yours, "-8" in white under theirs).
function Hud:popup(text, color, onFoe)
	local l = Ui.label(self.battleFrame, {
		Position = onFoe and UDim2.new(0.75, 0, 1, 2) or UDim2.new(0.12, 0, 1, 2),
		Size = UDim2.fromOffset(80, 24),
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Text = text,
	})
	local tween = TweenService:Create(l, TweenInfo.new(0.7), { Position = l.Position + UDim2.fromOffset(0, 26), TextTransparency = 1, TextStrokeTransparency = 1 })
	tween.Completed:Connect(function()
		l:Destroy()
	end)
	tween:Play()
end

function Hud:showResult(e, onRematch, onLeave)
	local title = { win = "VICTORY", loss = "DEFEAT", draw = "DRAW" }
	self.resultTitle.Text = title[e.outcome] or "FINISHED"
	self.resultTitle.TextColor3 = e.outcome == "win" and C.good or e.outcome == "loss" and C.bad or C.warn
	local who = e.outcome == "win" and "Your opponent" or e.outcome == "loss" and "Your bey" or ""
	local reason = REASON[e.reason] or e.reason or ""
	if e.reason == "time" or e.reason == "both" or e.reason == "left" then
		self.resultReason.Text = reason:sub(1, 1):upper() .. reason:sub(2)
	else
		self.resultReason.Text = who .. " " .. reason
	end
	if e.reward and (e.reward.XP > 0 or e.reward.Shards > 0) then
		self.resultReward.Text = ("+%d XP    +%d Shards"):format(e.reward.XP, e.reward.Shards) .. (e.levelUp and ("\nLEVEL UP! Level " .. e.levelUp) or "")
	elseif e.reward then
		self.resultReward.Text = e.reason == "left" and "No reward for forfeiting" or "Too quick for a reward: last 20 seconds to earn one"
	else
		self.resultReward.Text = ""
	end
	self.resultNext.Text = e.next and ("Next opponent difficulty: " .. e.next) or ""
	self.lowSpin.Visible = false
	self.resultFrame.Visible = true
	self:_panel(true)
	if self._rc then
		self._rc:Disconnect()
		self._lc:Disconnect()
	end
	self._rc = self.rematchBtn.Activated:Connect(onRematch)
	self._lc = self.leaveBtn.Activated:Connect(onLeave)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = self.rematchBtn
	end
	local closes = os.clock() + (e.closesIn or 45)
	task.spawn(function()
		while self.resultFrame.Visible do
			self.resultClose.Text = ("Returns to the hub in %ds"):format(math.max(0, math.ceil(closes - os.clock())))
			task.wait(0.25)
		end
	end)
end

function Hud:closeBattle()
	self:hideLaunch()
	if self.resultFrame.Visible then
		self.resultFrame.Visible = false
		self:_panel(false)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.gui) then
			GuiService.SelectedObject = nil
		end
	end
	self.battleFrame.Visible = false
	self.center.Text = ""
	self.lowSpin.Visible = false
end

function Hud:queued(position)
	self.center.TextColor3 = C.warn
	self.center.TextSize = 30
	self.center.Text = ("Arena busy: you're #%d in line"):format(position or 1)
	task.delay(3, function()
		self.center.TextSize = 64
		if self.center.Text:find("Arena busy") then
			self.center.Text = ""
		end
	end)
end

-------------------------------------------------------------------------------- misc

function Hud:toast(text, color)
	self.toastLabel.Text = text
	self.toastLabel.TextColor3 = color or C.text
	self.toastLabel.Visible = true
	local token = {}
	self._toast = token
	task.delay(3, function()
		if self._toast == token then
			self.toastLabel.Visible = false
		end
	end)
end

function Hud:showHint(step, title, body)
	self.hintStep.Text = step or ""
	self.hintTitle.Text = title
	self.hintBody.Text = body
	self.hintFrame.Visible = true
end

function Hud:hideHint()
	self.hintFrame.Visible = false
end

function Hud:showTouchButtons(show)
	local touch = UserInputService.TouchEnabled
	self.touchButtonsShown = show
	-- SLAM shares its spot with LAUNCH, so it waits until the launch meter is gone.
	self.touchSlam.Visible = show and touch and not self.launchMeter
	self.touchJump.Visible = show and touch
end

function Hud:setDiag(text)
	self.diag.Visible = text ~= nil
	if text then
		self.diag.Text = text
	end
end

function Hud:showError(text)
	self.errorLabel.Text = "Spinforge couldn't start:\n" .. text
	self.errorLabel.Visible = true
end

-- Counts open panels so the bey controller frees the mouse while any is open.
function Hud:_panel(open)
	self.panelsOpen = math.max(0, self.panelsOpen + (open and 1 or -1))
end

function Hud:mouseFree()
	return self.panelsOpen > 0
end

return Hud
]=====])
install('SPS', '', 'LocalScript', 'Main', [=====[
--!nonstrict
-- Spinforge client entry point. Builds the HUD first (so problems can be shown on screen), waits a bounded time
-- for the server's remotes, then starts the menus, tutorial, effects and bey controller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Hud = require(script.Parent.Hud)
local hud = Hud.new(player)

local Shared = ReplicatedStorage:WaitForChild("Spinforge", 20)
if not Shared then
	hud:showError("ReplicatedStorage.Spinforge is missing. Run install_in_studio.lua again.")
	return
end
local Net = require(Shared.Net)
local remotes, err = Net.waitFor(ReplicatedStorage, 20)
if not remotes then
	hud:showError(err)
	return
end

local Effects = require(script.Parent.Effects)
local Menus = require(script.Parent.Menus)
local Tutorial = require(script.Parent.Tutorial)
local Controller = require(script.Parent.Controller)
local LaunchCore = require(Shared.Core.LaunchCore)
local GameConfig = require(Shared.GameConfig)
local BeyConfig = require(Shared.BeyConfig)
local Spirits = require(script.Parent.Spirits)
local SpecialsHud = require(script.Parent.SpecialsHud)
local Sounds = require(script.Parent.Sounds)

local profile = nil
local function settings()
	return profile and profile.Settings or { CameraShake = true, ReducedEffects = false, TutorialDone = true }
end

local effects = Effects.new(settings)
local menus = Menus.new(hud, remotes)
local tutorial = Tutorial.new(hud, remotes)
Controller.start({ remotes = remotes, hud = hud, effects = effects, tutorial = tutorial })

-- Specials: keys 1 / 2 (gamepad X / Y), Awakening: R (gamepad LB). Also clickable on the HUD cards.
local function battleActive()
	return player:GetAttribute("Mode") == "Battle" and player:GetAttribute("BattleState") == "active"
end
local function useSpecial(index)
	if battleActive() then
		remotes.Request:FireServer({ action = "special", index = index })
	end
end
local function awaken()
	if battleActive() then
		remotes.Request:FireServer({ action = "awaken" })
	end
end
local specialsHud = SpecialsHud.new(hud, useSpecial, awaken)
local spirits = Spirits.new(effects, {
	cinematic = function(duration, zoom)
		Controller.cinematic(duration, zoom)
	end,
	banner = function(text, color, small)
		specialsHud:showBanner(text, color, small)
	end,
})
-- The game has no tools: hide Roblox's hotbar so it doesn't take the number keys.
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not battleActive() or UserInputService:GetFocusedTextBox() then
		return
	end
	local kc = input.KeyCode
	local numberKey = kc == Enum.KeyCode.One or kc == Enum.KeyCode.Two or kc == Enum.KeyCode.KeypadOne or kc == Enum.KeyCode.KeypadTwo
	if processed and not numberKey then
		return
	end
	if kc == Enum.KeyCode.One or kc == Enum.KeyCode.KeypadOne or kc == Enum.KeyCode.ButtonX then
		useSpecial(1)
	elseif kc == Enum.KeyCode.Two or kc == Enum.KeyCode.KeypadTwo or kc == Enum.KeyCode.ButtonY then
		useSpecial(2)
	elseif kc == Enum.KeyCode.R or kc == Enum.KeyCode.ButtonL1 then
		awaken()
	end
end)
require(script.Parent.OnFootFallback).start({ hud = hud, isBound = function()
	return Controller.isBound()
end })

remotes.Profile.OnClientEvent:Connect(function(p)
	if type(p) ~= "table" then
		return
	end
	profile = p
	hud:setProfile(p)
	menus:setProfile(p)
	tutorial:setProfile(p)
end)
hud:setProfile({ Level = 1, XP = 0, Shards = 0, Record = { Wins = 0, Losses = 0, Draws = 0 }, SaveStatus = "loading" })

remotes.Toast.OnClientEvent:Connect(function(text)
	if type(text) == "string" then
		hud:toast(text)
	end
end)

-- Mode changes (set by the server): HUD layout and the mode button (Forfeit / Back to hub).
local function onMode()
	local m = player:GetAttribute("Mode") or "OnFoot"
	hud:setMode(m, nil)
	if m ~= "OnFoot" then
		menus:close()
		menus:closeSettings()
	end
end
player:GetAttributeChangedSignal("Mode"):Connect(onMode)
onMode()
hud.modeBtn.Activated:Connect(function()
	local m = player:GetAttribute("Mode")
	if m == "Practice" then
		remotes.Request:FireServer({ action = "exitPractice" })
	elseif m == "Battle" and (player:GetAttribute("BattleState") == "active" or player:GetAttribute("BattleState") == "countdown") then
		remotes.Request:FireServer({ action = "forfeit" })
	end
end)

local beys = Workspace:WaitForChild("Beys", 30)
effects:trackBeys(beys)

-- The Body of "player" (yours) or "villain".
local function beyBody(who)
	if not beys then
		return nil
	end
	if who == "player" then
		local m = beys:FindFirstChild(tostring(player.UserId))
		return m and m:FindFirstChild("Body")
	end
	for _, m in ipairs(beys:GetChildren()) do
		if m:GetAttribute("Villain") then
			return m:FindFirstChild("Body")
		end
	end
	return nil
end

-- Battle events.
local inBattle = false
remotes.BattleEvent.OnClientEvent:Connect(function(e)
	if type(e) ~= "table" then
		return
	end
	if e.kind == "queued" then
		hud:queued(e.position)
	elseif e.kind == "countdown" then
		inBattle = true
		hud:closeBattle()
		hud:countdown(e.seconds or 3, e.foe, e.difficulty)
		specialsHud:setLoadout(type(e.loadout) == "table" and e.loadout.specials or nil)
		specialsHud:show(true)
		if type(e.meter) == "table" then
			hud:showLaunch(e.meter)
		end
	elseif e.kind == "launchLocked" then
		-- the server's verdict (normally the same as what we showed)
		hud:lockLaunch(nil, e.label or "WEAK", e.quality)
	elseif e.kind == "started" then
		hud:started(e.launch, e.foeLaunch)
		Sounds.play("Launch", 0.8)
		if type(e.launch) == "table" then
			Controller.launch(e.launch.speed, e.launch.boost)
		end
	elseif e.kind == "hit" then
		if (e.taken or 0) > 0.5 then
			hud:popup(("-%d"):format(math.floor(e.taken + 0.5)), Color3.fromRGB(255, 110, 110), false)
			hud:flash(Color3.fromRGB(255, 60, 60), e.strength or 0.5)
		end
		if (e.dealt or 0) > 0.5 then
			hud:popup(("-%d"):format(math.floor(e.dealt + 0.5)), Color3.fromRGB(255, 255, 255), true)
		end
		if typeof(e.at) == "Vector3" then
			local crit = e.crit == true or e.foeCrit == true
			effects:impact(e.at, typeof(e.normal) == "Vector3" and e.normal or nil, e.strength or 0.5, {
				crit = crit,
				color = crit and Color3.fromRGB(255, 170, 80) or nil,
			})
			if e.crit then
				specialsHud:showBanner("CRITICAL!", Color3.fromRGB(255, 170, 60), true)
			end
		end
	elseif e.kind == "slam" then
		if e.hit then
			hud:toast((e.dealt and e.dealt > 0) and ("SLAM! -%d"):format(math.floor(e.dealt + 0.5)) or "SLAM!", Color3.fromRGB(255, 200, 120))
		end
	elseif e.kind == "villainSlam" then
		if typeof(e.at) == "Vector3" then
			effects:slamRing(e.at - Vector3.new(0, 1.8, 0), 1, Color3.fromRGB(255, 80, 80))
		end
	elseif e.kind == "special" then
		local body = beyBody(e.who)
		local def = BeyConfig.Specials[e.id or ""]
		local color = def and def.Color or Color3.new(1, 1, 1)
		spirits:summon({ spirit = e.spirit, body = body, kind = "special", special = e.special, dir = e.dir, id = e.id, big = e.who == "player" })
		Sounds.play(e.special == "quake" and "Quake" or e.special == "guard" and "Guard" or "Special", 0.8)
		if e.who == "player" and e.dash then
			Controller.dash(e.dash, e.dir)
		end
		if e.special == "quake" and typeof(e.at) == "Vector3" then
			effects:burst(e.at - Vector3.new(0, 1.8, 0), color, def and def.Tuning.Radius or 14)
			effects:shake(0.8)
		end
		if (e.healed or 0) > 0.5 then
			hud:popup(("+%d"):format(math.floor(e.healed + 0.5)), Color3.fromRGB(120, 255, 160), e.who ~= "player")
		end
		if e.hit and (e.dealt or 0) > 0.5 then
			hud:popup(("-%d"):format(math.floor(e.dealt + 0.5)), e.who == "player" and Color3.new(1, 1, 1) or Color3.fromRGB(255, 110, 110), e.who == "player")
		end
	elseif e.kind == "awaken" then
		local def = BeyConfig.Spirits[e.spirit or ""]
		local color = def and def.Color or Color3.new(1, 1, 1)
		spirits:summon({
			spirit = e.spirit,
			body = beyBody(e.who),
			kind = "awaken",
			duration = e.duration,
			big = e.who == "player",
			face = function()
				local other = beyBody(e.who == "player" and "villain" or "player")
				return other and other.Position or nil
			end,
		})
		specialsHud:wash(color, e.who == "player" and 0.45 or 0.25)
		effects:shake(e.who == "player" and 1 or 0.6)
		Sounds.play("Awaken", 1)
	elseif e.kind == "specials" then
		specialsHud:update(e.you, e.foe)
		if type(e.you) == "table" then
			Controller.setSpeedMultiplier(e.you.speed or 1)
		end
	elseif e.kind == "specialRefused" then
		specialsHud:refused(e.index)
	elseif e.kind == "finished" then
		local won = e.outcome == "win"
		specialsHud:showBanner(won and "WINNER!" or e.outcome == "loss" and "DEFEATED" or "DRAW", won and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 110, 110), false)
		Sounds.play(won and "Win" or "Lose", 0.9)
		hud:showResult(e, function()
			remotes.Request:FireServer({ action = "rematch" })
		end, function()
			remotes.Request:FireServer({ action = "leave" })
		end)
	elseif e.kind == "closed" then
		inBattle = false
		hud:closeBattle()
		specialsHud:show(false)
		spirits:clear()
		Controller.setSpeedMultiplier(1)
	elseif e.kind == "openWorkshop" then
		menus:open()
	end
end)

-- Launch meter: the needle runs on the shared server clock; one press locks it and tells the server when.
local function pressLaunch()
	local meter = hud.launchMeter
	if not meter or hud.launchLocked then
		return
	end
	local t = Workspace:GetServerTimeNow()
	local pos = LaunchCore.needle(meter, t)
	local q, label = LaunchCore.quality(meter, pos, GameConfig.Launch)
	hud:lockLaunch(pos, label, q)
	remotes.Request:FireServer({ action = "launch", t = t })
end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not hud.launchMeter then
		return
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.Space or kc == Enum.KeyCode.ButtonA or kc == Enum.KeyCode.ButtonR2 or input.UserInputType == Enum.UserInputType.MouseButton1 then
		pressLaunch()
	end
end)
hud.touchLaunch.Activated:Connect(pressLaunch)
RunService.RenderStepped:Connect(function()
	local meter = hud.launchMeter
	if meter and not hud.launchLocked then
		hud:setNeedle(LaunchCore.needle(meter, Workspace:GetServerTimeNow()))
	end
end)

-- Live battle bars from the beys' Spin attributes (set by the server).
RunService.RenderStepped:Connect(function()
	if not inBattle or not beys then
		return
	end
	local mine = beys:FindFirstChild(tostring(player.UserId))
	local foe
	for _, m in ipairs(beys:GetChildren()) do
		if m:GetAttribute("Villain") then
			foe = m
			break
		end
	end
	local mb = mine and mine:FindFirstChild("Body")
	local fb = foe and foe:FindFirstChild("Body")
	if mb and fb then
		hud:updateBattle(mb:GetAttribute("Spin") or 0, mb:GetAttribute("MaxSpin") or 1, fb:GetAttribute("Spin") or 0, fb:GetAttribute("MaxSpin") or 1, player:GetAttribute("BattleEndsAt"), player:GetAttribute("BattleState"))
	end
end)

-- F6: diagnostics.
local diagOn = false
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F6 then
		diagOn = not diagOn
		if not diagOn then
			hud:setDiag(nil)
		end
	end
end)
local frames, fps, fpsAt = 0, 0, os.clock()
RunService.RenderStepped:Connect(function()
	frames += 1
	local now = os.clock()
	if now - fpsAt >= 0.5 then
		fps = frames / (now - fpsAt)
		frames, fpsAt = 0, now
		if diagOn then
			local beyCount = beys and #beys:GetChildren() or 0
			hud:setDiag(("FPS %.0f\nmode %s  battle %s\nbeys in world %d  effects active %d\nsave %s\n%s"):format(
				fps,
				tostring(player:GetAttribute("Mode")),
				tostring(player:GetAttribute("BattleState") or "-"),
				beyCount,
				effects:count(),
				profile and profile.SaveStatus or "loading",
				Controller.diag()
			))
		end
	end
end)
]=====])
install('SPS', '', 'ModuleScript', 'Menus', [=====[
--!nonstrict
-- Menus: the Loadout (parts, spirit and specials: buy with Shards, equip, see your bey) and Settings.
-- Layout:  [ your bey (3D, turning) | stat bars | the six equipped slots ]  [ tabs | search | card grid | details ]
-- Every action is sent to the server, which validates it (ownership, slot, price, not in battle) and replies
-- with the updated profile. The client never changes its own inventory.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local BeyVisuals = require(Shared.BeyVisuals)
local GameConfig = require(Shared.GameConfig)
local Progression = require(Shared.Core.Progression)
local Spirits = require(script.Parent.Spirits)
local Ui = require(script.Parent.Ui)
local C = Ui.C

local Menus = {}
Menus.__index = Menus

local RARITY_LABEL = { Common = "Common", Uncommon = "Uncommon", Rare = "Rare", Epic = "Epic", Legendary = "Legendary", UltraLegendary = "Ultra Legendary" }
local TABS = {
	{ key = "Layer", label = "LAYERS" },
	{ key = "Disc", label = "DISCS" },
	{ key = "Driver", label = "DRIVERS" },
	{ key = "Spirit", label = "SPIRITS" },
	{ key = "Special", label = "SPECIALS" },
}
local SLOT_LABEL = { Layer = "Layer", Disc = "Disc", Driver = "Driver", Spirit = "Spirit", Special1 = "Special 1", Special2 = "Special 2" }
local STAT_MAX = 30 -- bar length reference (about the best a stat gets at level 50)
local BG = Color3.fromRGB(11, 14, 24)

local function darker(c, k)
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function pct(x)
	return math.floor((x - 1) * 100 + 0.5)
end

-- One line saying what an item does.
local function describe(item)
	if item.Slot == "Special" then
		local t = item.Tuning
		if item.Kind == "dash" then
			return ("Burst at your rival. Your next hit within %.1fs deals x%.1f damage."):format(t.Window, t.DamageMul)
		elseif item.Kind == "guard" then
			return ("For %.1fs take %d%% less damage and %d%% less knockback%s."):format(t.Duration, t.Block * 100, t.KnockbackBlock * 100, t.Heal and (", and get " .. math.floor(t.Heal * 100) .. "% spin back") or "")
		elseif item.Kind == "heal" then
			return ("Get %d%% of your spin back."):format(t.Heal * 100)
		elseif item.Kind == "quake" then
			return ("Shockwave: %d damage and a big knockback within %d studs."):format(t.Damage, t.Radius)
		end
		return ""
	elseif item.Slot == "Spirit" then
		local bits = {}
		local p = item.Passive
		if p.Attack then
			table.insert(bits, ("+%d%% damage"):format(pct(p.Attack)))
		end
		if p.Defense then
			table.insert(bits, ("+%d%% toughness"):format(pct(p.Defense)))
		end
		if p.Speed then
			table.insert(bits, ("+%d%% speed"):format(pct(p.Speed)))
		end
		if p.Drain then
			table.insert(bits, ("%d%% slower spin loss"):format(-pct(p.Drain)))
		end
		return "Always: " .. table.concat(bits, ", ") .. ". Appears with every special; Awakening boosts you for "
			.. GameConfig.Specials.AwakenDuration .. "s."
	end
	local s = item.Stats
	return ("ATK %d   DEF %d   STA %d   BAL %d"):format(s.Attack, s.Defense, s.Stamina, s.Balance)
end

local function shortLine(item)
	if item.Slot == "Special" then
		return ({ dash = "Attack", guard = "Defense", heal = "Recovery", quake = "Shockwave" })[item.Kind] or ""
	elseif item.Slot == "Spirit" then
		local p = item.Passive
		return p.Attack and ("+%d%% dmg"):format(pct(p.Attack)) or p.Defense and ("+%d%% tough"):format(pct(p.Defense)) or ""
	end
	local s = item.Stats
	return ("%d / %d / %d / %d"):format(s.Attack, s.Defense, s.Stamina, s.Balance)
end

-- An icon model for a special: a small neon shape per kind.
local function specialIcon(item)
	local m = Instance.new("Model")
	local function part(shape, size, cf, transparency)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cf
		p.Material = Enum.Material.Neon
		p.Color = item.Color
		p.Transparency = transparency or 0
		p.Parent = m
		return p
	end
	local Cy = Enum.PartType.Cylinder
	if item.Kind == "dash" then
		part(Enum.PartType.Ball, Vector3.new(1.4, 1.4, 1.4), CFrame.new(0.9, 0.5, 0))
		for i = 1, 3 do
			part(nil, Vector3.new(2.6 - i * 0.5, 0.22, 0.22), CFrame.new(-0.6 - i * 0.15, 0.5 - (i - 2) * 0.45, 0), 0.2 * i)
		end
	elseif item.Kind == "guard" then
		part(Cy, Vector3.new(0.25, 2.6, 2.6), CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, 0), 0.35)
		part(Cy, Vector3.new(0.3, 1.5, 1.5), CFrame.Angles(0, math.rad(90), 0))
	elseif item.Kind == "heal" then
		part(nil, Vector3.new(0.5, 2, 0.5), CFrame.new())
		part(nil, Vector3.new(2, 0.5, 0.5), CFrame.new())
		part(Cy, Vector3.new(0.12, 2.9, 2.9), CFrame.Angles(0, math.rad(90), 0), 0.5)
	else
		for i = 1, 3 do
			part(Cy, Vector3.new(0.1, i * 0.95, i * 0.95), CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.15 * i)
		end
		part(nil, Vector3.new(0.5, 1.4, 0.5), CFrame.new(0, 0.2, 0) * CFrame.Angles(0, math.rad(45), 0))
	end
	return m
end

-- Fills a ViewportFrame with a model, camera framed on it. spin = true turns it (only while the menu is open).
local function showModel(vp, model, distance, pitch)
	vp:ClearAllChildren()
	if not model then
		return
	end
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	local d = distance or 7
	local p = pitch or 0.45
	cam.CFrame = CFrame.lookAt(Vector3.new(0, math.sin(p) * d, math.cos(p) * d), Vector3.zero)
	return cam
end

function Menus.new(hud, remotes)
	local self = setmetatable({}, Menus)
	self.hud = hud
	self.remotes = remotes
	self.profile = nil
	self.tab = "Layer"
	self.selected = nil
	self.filter = ""
	self.busy = false

	-- Loadout window (named Workshop: the kiosk in the hub opens it)
	local w = Ui.panel(hud.gui, { Name = "Workshop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(880, 560), Visible = false, ZIndex = 5, BackgroundColor3 = BG, BackgroundTransparency = 0.03 })
	Ui.pad(w, 14)
	Ui.label(w, { Size = UDim2.new(0, 300, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 26, Text = "LOADOUT", ZIndex = 6 })
	self.shards = Ui.label(w, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 4), Size = UDim2.fromOffset(300, 24), TextColor3 = C.gold, Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 })
	Ui.button(w, "X", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(32, 32), ZIndex = 6 }, function()
		self:close()
	end)

	-- left: your bey
	local left = Ui.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(0, 250, 1, -40), BackgroundColor3 = C.panel2, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 6 }, w)
	Ui.corner(left, 10)
	self.beyView = Ui.make("ViewportFrame", { Size = UDim2.new(1, 0, 0, 170), BackgroundTransparency = 1, LightColor = Color3.new(1, 1, 1), Ambient = Color3.fromRGB(150, 150, 170), ZIndex = 7 }, left)
	self.levelLine = Ui.label(left, { Position = UDim2.fromOffset(12, 168), Size = UDim2.new(1, -24, 0, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.muted, ZIndex = 7 })
	self.statBars = {}
	for i, stat in ipairs(BeyConfig.StatNames) do
		local y = 190 + (i - 1) * 22
		Ui.label(left, { Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(40, 16), Font = Enum.Font.GothamBold, TextSize = 12, Text = stat:sub(1, 3):upper(), TextColor3 = C.muted, ZIndex = 7 })
		local fill = Ui.bar(left, { Position = UDim2.fromOffset(52, y + 3), Size = UDim2.new(1, -100, 0, 10), ZIndex = 7 }, ({ C.bad, C.accent, C.good, C.warn })[i])
		fill.ZIndex = 8
		local num = Ui.label(left, { Position = UDim2.new(1, -44, 0, y), Size = UDim2.fromOffset(34, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7 })
		self.statBars[stat] = { fill = fill, num = num }
	end
	self.slotRows = {}
	for i, slot in ipairs(BeyConfig.LoadoutSlots) do
		local row = Ui.button(left, "", { Position = UDim2.fromOffset(8, 284 + (i - 1) * 34), Size = UDim2.new(1, -16, 0, 30), BackgroundColor3 = C.panel, ZIndex = 7, TextXAlignment = Enum.TextXAlignment.Left }, function()
			self.tab = BeyConfig.SlotKind(slot)
			self.selected = self.profile and self.profile.Equipped[slot]
			self:refresh()
		end)
		Ui.label(row, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 70, 1, 0), TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = C.muted, Text = SLOT_LABEL[slot]:upper(), ZIndex = 8 })
		local name = Ui.label(row, { Position = UDim2.fromOffset(80, 0), Size = UDim2.new(1, -86, 1, 0), TextSize = 13, Font = Enum.Font.GothamBold, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8 })
		self.slotRows[slot] = { row = row, name = name }
	end

	-- right: tabs, search, grid, details
	local right = Ui.make("Frame", { Position = UDim2.fromOffset(262, 40), Size = UDim2.new(1, -262, 1, -40), BackgroundTransparency = 1, ZIndex = 6 }, w)
	self.tabs = {}
	for i, t in ipairs(TABS) do
		self.tabs[t.key] = Ui.button(right, t.label, { Position = UDim2.new((i - 1) / #TABS, i > 1 and 3 or 0, 0, 0), Size = UDim2.new(1 / #TABS, -4, 0, 32), TextSize = 13, ZIndex = 7 }, function()
			self.tab = t.key
			self.selected = nil
			self:refresh()
		end)
	end
	self.search = Ui.make("TextBox", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = C.panel2,
		TextColor3 = C.text,
		PlaceholderText = "Search...",
		PlaceholderColor3 = C.muted,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, right)
	Ui.corner(self.search, 6)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, self.search)
	self.search:GetPropertyChangedSignal("Text"):Connect(function()
		self.filter = string.lower(self.search.Text or "")
		self:refresh()
	end)
	self.grid = Ui.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, 0, 1, -76 - 84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 7,
	}, right)
	Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(140, 178), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, self.grid)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }, self.grid)

	local det = Ui.make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 76), BackgroundColor3 = C.panel2, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 7 }, right)
	Ui.corner(det, 10)
	Ui.pad(det, 10)
	self.detName = Ui.label(det, { Size = UDim2.new(1, -200, 0, 22), Font = Enum.Font.GothamBlack, TextSize = 18, ZIndex = 8 })
	self.detText = Ui.label(det, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -200, 0, 32), TextSize = 13, TextColor3 = C.muted, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 8 })
	self.actionA = Ui.button(det, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(180, 26), ZIndex = 8, Visible = false }, function()
		self:_action("A")
	end)
	self.actionB = Ui.button(det, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 30), Size = UDim2.fromOffset(180, 26), ZIndex = 8, Visible = false }, function()
		self:_action("B")
	end)
	self.status = Ui.label(w, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(300, 20), TextSize = 13, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	self.window = w

	-- turn the bey preview while open
	RunService.RenderStepped:Connect(function()
		if w.Visible and self.beyCam then
			local a = os.clock() * 0.6
			self.beyCam.CFrame = CFrame.lookAt(Vector3.new(math.sin(a) * 6.5, 3.2, math.cos(a) * 6.5), Vector3.new(0, -0.4, 0))
		end
	end)

	-- Settings window
	local s = Ui.panel(hud.gui, { Name = "Settings", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(360, 230), Visible = false, ZIndex = 5 })
	Ui.pad(s, 14)
	Ui.label(s, { Size = UDim2.new(1, -40, 0, 26), Font = Enum.Font.GothamBlack, TextSize = 22, Text = "SETTINGS", ZIndex = 6 })
	Ui.button(s, "X", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(32, 32), ZIndex = 6 }, function()
		self:closeSettings()
	end)
	self.shakeBtn = Ui.button(s, "", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 38), ZIndex = 6 }, function()
		self:setting("CameraShake", not (self.profile and self.profile.Settings.CameraShake))
	end)
	self.reducedBtn = Ui.button(s, "", { Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 38), ZIndex = 6 }, function()
		self:setting("ReducedEffects", not (self.profile and self.profile.Settings.ReducedEffects))
	end)
	Ui.button(s, "Show the tutorial again", { Position = UDim2.fromOffset(0, 136), Size = UDim2.new(1, 0, 0, 38), ZIndex = 6 }, function()
		remotes.Request:FireServer({ action = "tutorialReset" })
		hud:toast("The tutorial will show next time you play")
	end)
	self.settingsWindow = s

	hud.workshopBtn.Text = "Loadout"
	hud.workshopBtn.Activated:Connect(function()
		self:open()
	end)
	hud.settingsBtn.Activated:Connect(function()
		self:openSettings()
	end)
	return self
end

function Menus:setProfile(p)
	self.profile = p
	if self.window.Visible then
		self:refresh()
	end
	if p then
		self.shakeBtn.Text = "Camera shake: " .. (p.Settings.CameraShake and "ON" or "OFF")
		self.reducedBtn.Text = "Reduced effects: " .. (p.Settings.ReducedEffects and "ON" or "OFF")
	end
end

function Menus:setting(key, value)
	self.remotes.Request:FireServer({ action = "setting", key = key, value = value })
end

-- Which slot an item is equipped in, if any.
local function equippedSlot(p, id)
	for _, slot in ipairs(BeyConfig.LoadoutSlots) do
		if p.Equipped[slot] == id then
			return slot
		end
	end
	return nil
end

function Menus:_refreshLeft(p)
	local ok, stats = pcall(BeyConfig.ComputeStats, p.Equipped, p.Level)
	if ok then
		for stat, bar in pairs(self.statBars) do
			bar.fill.Size = UDim2.fromScale(math.clamp(stats[stat] / STAT_MAX, 0.02, 1), 1)
			bar.num.Text = ("%d"):format(stats[stat] + 0.5)
		end
	end
	self.levelLine.Text = ("YOUR BEY   ·   LEVEL %d"):format(p.Level)
	for slot, r in pairs(self.slotRows) do
		local item = BeyConfig.Items[p.Equipped[slot] or ""]
		r.name.Text = item and item.Name or "-"
		r.name.TextColor3 = item and (item.Color or BeyConfig.RarityColors[item.Rarity]) or C.muted
		r.row.BackgroundColor3 = BeyConfig.SlotKind(slot) == self.tab and Color3.fromRGB(30, 60, 90) or C.panel
	end
	local key = (p.Equipped.Layer or "") .. (p.Equipped.Disc or "") .. (p.Equipped.Driver or "")
	if key ~= self.beyKey then
		self.beyKey = key
		local okModel, model = pcall(BeyVisuals.Preview, { Layer = p.Equipped.Layer, Disc = p.Equipped.Disc, Driver = p.Equipped.Driver })
		self.beyCam = showModel(self.beyView, okModel and model or nil, 6.5, 0.45)
	end
end

function Menus:_card(item, order, p, owned)
	local rarityColor = BeyConfig.RarityColors[item.Rarity]
	local slot = equippedSlot(p, item.Id)
	local isSel = self.selected == item.Id
	local card = Ui.make("TextButton", {
		Name = item.Id,
		LayoutOrder = order,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		ZIndex = 8,
	}, self.grid)
	Ui.corner(card, 10)
	Ui.make("UIGradient", { Rotation = 90, Color = ColorSequence.new(darker(rarityColor, 0.45), darker(BG, 1.2)) }, card)
	Ui.stroke(card, (isSel or slot) and rarityColor or darker(rarityColor, 0.5), isSel and 3 or 2)
	local vp = Ui.make("ViewportFrame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 100), BackgroundTransparency = 1, LightColor = Color3.new(1, 1, 1), Ambient = Color3.fromRGB(160, 160, 180), ZIndex = 9 }, card)
	local model
	if item.Slot == "Special" then
		model = specialIcon(item)
		showModel(vp, model, 6, 0.1)
	elseif item.Slot == "Spirit" then
		model = Spirits.preview(item.Id)
		showModel(vp, model, 3.4, 0.25)
		if model then
			model:PivotTo(CFrame.new(0, -0.6, 0) * CFrame.Angles(0, math.rad(-35), 0))
		end
	else
		local ok, m = pcall(BeyVisuals.Preview, item.Id)
		showModel(vp, ok and m or nil, 5.5, 0.5)
	end
	if not owned then
		vp.ImageTransparency = 0.55
	end
	Ui.label(card, { Position = UDim2.fromOffset(8, 108), Size = UDim2.new(1, -16, 0, 18), Font = Enum.Font.GothamBold, TextSize = 14, Text = item.Name, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9 })
	Ui.label(card, { Position = UDim2.fromOffset(8, 126), Size = UDim2.new(1, -16, 0, 14), Font = Enum.Font.GothamBold, TextSize = 11, Text = "● " .. RARITY_LABEL[item.Rarity], TextColor3 = rarityColor, ZIndex = 9 })
	Ui.label(card, { Position = UDim2.fromOffset(8, 142), Size = UDim2.new(1, -16, 0, 14), TextSize = 11, Text = shortLine(item), TextColor3 = C.muted, ZIndex = 9 })
	local price = Progression.price(item.Id, BeyConfig.Items, GameConfig.Progression)
	local badgeText, badgeColor
	if slot then
		badgeText, badgeColor = (slot == "Special1" and "SLOT 1") or (slot == "Special2" and "SLOT 2") or "EQUIPPED", C.good
	elseif owned then
		badgeText, badgeColor = "OWNED", C.accent
	elseif price then
		badgeText, badgeColor = ("%d SHARDS"):format(price), C.gold
	else
		badgeText, badgeColor = "CRATE ONLY", C.muted
	end
	local badge = Ui.label(card, {
		Position = UDim2.fromOffset(8, 158),
		Size = UDim2.new(1, -16, 0, 14),
		Font = Enum.Font.GothamBlack,
		TextSize = 11,
		Text = badgeText,
		TextColor3 = badgeColor,
		ZIndex = 9,
	})
	if not owned and price and p.Shards < price then
		badge.TextTransparency = 0.4
	end
	card.Activated:Connect(function()
		self.selected = item.Id
		self:refresh()
	end)
	return card
end

function Menus:_details(p, owned)
	local item = self.selected and BeyConfig.Items[self.selected]
	self.actionA.Visible, self.actionB.Visible = false, false
	self.pending = {}
	if not item or BeyConfig.SlotKind(item.Slot) ~= self.tab then
		self.detName.Text = "Pick a card"
		self.detName.TextColor3 = C.text
		self.detText.Text = self.tab == "Special" and "Specials: keys 1 and 2 in battle. Each summons your spirit." or "Click a card to see it, buy it or equip it."
		return
	end
	self.detName.Text = item.Name .. "   ·   " .. RARITY_LABEL[item.Rarity]
	self.detName.TextColor3 = item.Color or BeyConfig.RarityColors[item.Rarity]
	self.detText.Text = describe(item)
	local price = Progression.price(item.Id, BeyConfig.Items, GameConfig.Progression)
	local function set(btn, text, color, action, slot)
		btn.Text = text
		btn.BackgroundColor3 = color
		btn.Visible = true
		self.pending[btn == self.actionA and "A" or "B"] = action and { action = action, slot = slot } or nil
	end
	if not owned[item.Id] then
		if price then
			set(self.actionA, ("Buy  ·  %d Shards"):format(price), p.Shards >= price and Color3.fromRGB(150, 105, 20) or C.panel, "buy")
		else
			set(self.actionA, "Crate only", C.panel, nil)
		end
	elseif item.Slot == "Special" then
		local s1, s2 = p.Equipped.Special1 == item.Id, p.Equipped.Special2 == item.Id
		set(self.actionA, s1 and "In slot 1" or "Equip to slot 1", s1 and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(30, 90, 120), (not s1) and "equip" or nil, "Special1")
		set(self.actionB, s2 and "In slot 2" or "Equip to slot 2", s2 and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(30, 90, 120), (not s2) and "equip" or nil, "Special2")
	elseif equippedSlot(p, item.Id) then
		set(self.actionA, "Equipped", Color3.fromRGB(30, 80, 50), nil)
	else
		set(self.actionA, "Equip", Color3.fromRGB(30, 90, 120), "equip")
	end
end

function Menus:_action(which)
	local a = self.pending and self.pending[which]
	if a and self.selected then
		self:act(a.action, self.selected, a.slot)
	end
end

function Menus:refresh()
	local p = self.profile
	if not p then
		self.status.Text = "Loading your profile..."
		return
	end
	self.shards.Text = ("%d Shards"):format(p.Shards)
	for key, tab in pairs(self.tabs) do
		tab.BackgroundColor3 = key == self.tab and Color3.fromRGB(30, 90, 120) or C.panel2
	end
	self:_refreshLeft(p)
	for _, child in ipairs(self.grid:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local owned = {}
	for _, id in ipairs(p.Owned) do
		owned[id] = true
	end
	local rows = {}
	for _, item in pairs(BeyConfig.Items) do
		if BeyConfig.SlotKind(item.Slot) == self.tab and (self.filter == "" or string.find(string.lower(item.Name), self.filter, 1, true)) then
			table.insert(rows, item)
		end
	end
	local order = {}
	for i, r in ipairs(BeyConfig.Rarities) do
		order[r] = i
	end
	table.sort(rows, function(a, b)
		local ea, eb = equippedSlot(p, a.Id) ~= nil, equippedSlot(p, b.Id) ~= nil
		if ea ~= eb then
			return ea
		end
		if order[a.Rarity] ~= order[b.Rarity] then
			return order[a.Rarity] < order[b.Rarity]
		end
		return a.Name < b.Name
	end)
	local first
	for i, item in ipairs(rows) do
		local card = self:_card(item, i, p, owned[item.Id] == true)
		first = first or card
	end
	self:_details(p, owned)
	if UserInputService.GamepadEnabled and first and not (GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.window)) then
		GuiService.SelectedObject = first
	end
end

function Menus:act(action, partId, slot)
	if self.busy then
		return
	end
	self.busy = true
	self.status.Text = "..."
	local ok, reply = pcall(function()
		return self.remotes.Workshop:InvokeServer({ action = action, part = partId, slot = slot })
	end)
	self.busy = false
	if not ok or type(reply) ~= "table" then
		self.status.Text = "The server didn't answer. Try again."
		return
	end
	if reply.profile then
		self.profile = reply.profile
	end
	if reply.ok then
		self.status.Text = action == "buy" and "Bought! Equip it to use it." or "Equipped for your next battle."
	else
		self.status.Text = reply.reason or "That didn't work."
	end
	self:refresh()
end

function Menus:open()
	if self.window.Visible then
		return
	end
	self.settingsWindow.Visible = false
	self.window.Visible = true
	self.hud:_panel(true)
	self.status.Text = ""
	self:refresh()
end

function Menus:close()
	if self.window.Visible then
		self.window.Visible = false
		self.hud:_panel(false)
		GuiService.SelectedObject = nil
	end
end

function Menus:openSettings()
	if self.settingsWindow.Visible then
		return
	end
	self:close()
	self.settingsWindow.Visible = true
	self.hud:_panel(true)
end

function Menus:closeSettings()
	if self.settingsWindow.Visible then
		self.settingsWindow.Visible = false
		self.hud:_panel(false)
		GuiService.SelectedObject = nil
	end
end

return Menus
]=====])
install('SPS', '', 'ModuleScript', 'OnFootFallback', [=====[
--!nonstrict
-- OnFootFallback: a backup for walking around the hub, used ONLY if Roblox's own PlayerModule (the default
-- walking + camera scripts) never loads. That happened once in the owner's Studio, and without it you can't walk
-- or move the camera. Provides: WASD / left stick walking (camera-relative), Space / A to jump, and a follow
-- camera (hold right mouse or use the right stick to orbit). Steps aside whenever a bey is being controlled.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local OnFootFallback = {}

function OnFootFallback.start(ctx)
	local player = Players.LocalPlayer
	local hud, isBound = ctx.hud, ctx.isBound
	task.spawn(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if module then
			return -- the normal controls are there; nothing to do
		end
		warn("Spinforge: Roblox's PlayerModule didn't load; using backup on-foot controls.")
		hud:toast("Backup controls on: WASD to walk, Space to jump, hold right mouse to look")
		local camera = Workspace.CurrentCamera
		local yaw, pitch = 0, 0.35

		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or isBound() or UserInputService:GetFocusedTextBox() then
				return
			end
			if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.Jump = true
				end
			end
		end)

		RunService:BindToRenderStep("SpinforgeOnFoot", Enum.RenderPriority.Camera.Value + 2, function(dt)
			if isBound() then
				return
			end
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not (hum and root) then
				return
			end
			-- look around
			local orbiting = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) and not hud:mouseFree()
			UserInputService.MouseBehavior = orbiting and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
			if orbiting then
				local d = UserInputService:GetMouseDelta()
				yaw -= d.X * 0.005
				pitch = math.clamp(pitch + d.Y * 0.005, -0.2, 1.2)
			end
			for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
				if state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.15 then
					yaw -= state.Position.X * 2.5 * dt
					pitch = math.clamp(pitch - state.Position.Y * 1.5 * dt, -0.2, 1.2)
				end
			end
			-- walk (camera-relative)
			local x, z = 0, 0
			if not UserInputService:GetFocusedTextBox() and not hud:mouseFree() then
				local K = Enum.KeyCode
				x = (UserInputService:IsKeyDown(K.D) and 1 or 0) - (UserInputService:IsKeyDown(K.A) and 1 or 0)
				z = (UserInputService:IsKeyDown(K.S) and 1 or 0) - (UserInputService:IsKeyDown(K.W) and 1 or 0)
				for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
					if state.KeyCode == Enum.KeyCode.Thumbstick1 and state.Position.Magnitude > 0.15 then
						x += state.Position.X
						z -= state.Position.Y
					end
				end
			end
			local flat = CFrame.Angles(0, yaw, 0)
			local dir = flat.RightVector * x + flat.LookVector * -z
			hum:Move(dir.Magnitude > 1 and dir.Unit or dir, false)
			-- follow camera
			camera.CameraType = Enum.CameraType.Scriptable
			local focus = root.Position + Vector3.new(0, 2, 0)
			local eye = (CFrame.new(focus) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0) * CFrame.new(0, 0, 16)).Position
			camera.CFrame = CFrame.lookAt(eye, focus)
		end)
	end)
end

return OnFootFallback
]=====])
install('SPS', '', 'ModuleScript', 'Sounds', [=====[
--!nonstrict
-- Sounds: one place for every sound effect id. Empty ids are skipped (silent), so the game runs without any.
-- To add sound: in Studio open the Toolbox > Audio (or the Creator Store), pick Roblox-made or your own uploaded
-- sounds, copy the number from the asset URL and put "rbxassetid://<number>" here. Audio uploaded by other
-- people usually won't play in your game (Roblox audio privacy), so prefer Roblox's own SFX or your uploads.

local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.Ids = {
	Hit = "", -- metal clash, short
	HitHeavy = "", -- bigger clash with a ring (empowered hits)
	Launch = "", -- ripcord whoosh at LET IT RIP
	Special = "", -- whoosh / roar when a special is used
	Awaken = "", -- big roar + choir hit
	Quake = "", -- deep boom
	Guard = "", -- shield hum
	Win = "", -- victory sting
	Lose = "", -- defeat sting
}

-- Plays a sound once (2D, not positional). volume 0..1, pitch ~1.
function Sounds.play(name, volume, pitch)
	local id = Sounds.Ids[name]
	if not id or id == "" then
		return
	end
	local ok = pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume or 0.6
		s.PlaybackSpeed = pitch or 1
		s.Parent = SoundService
		s.Ended:Connect(function()
			s:Destroy()
		end)
		s:Play()
	end)
	return ok
end

return Sounds
]=====])
install('SPS', '', 'ModuleScript', 'SpecialsHud', [=====[
--!nonstrict
-- SpecialsHud: the battle bar for special moves and Awakening, plus the big title banners.
--   [1] Comet Drive  READY      [2] Iron Shell  6s        cards (tap/click to use too)
--   AWAKENING ███████░░░ 64%    full: "AWAKEN READY  [R]" pulsing; awake: "AWAKENED" draining
-- The server sends snapshots (cooldowns, meter) a few times a second; this only draws them.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local Ui = require(script.Parent.Ui)
local C = Ui.C

local SpecialsHud = {}
SpecialsHud.__index = SpecialsHud

local KIND_TEXT = { dash = "ATTACK", guard = "DEFENSE", heal = "RECOVER", quake = "SHOCKWAVE" }

local function keyText(i)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return ""
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return i == 1 and "X" or i == 2 and "Y" or "LB"
	end
	return i == 1 and "1" or i == 2 and "2" or "R"
end

function SpecialsHud.new(hud, onUse, onAwaken)
	local self = setmetatable({}, SpecialsHud)
	self.hud = hud
	local gui = hud.gui
	local root = Ui.make("Frame", {
		Name = "Specials",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.fromOffset(470, 92),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	self.root = root
	self.cards = {}
	for i = 1, 2 do
		local card = Ui.make("TextButton", {
			Position = UDim2.new((i - 1) * 0.5, i == 2 and 5 or 0, 0, 0),
			Size = UDim2.new(0.5, -5, 0, 52),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.08,
			AutoButtonColor = false,
			Text = "",
			Selectable = false,
		}, root)
		Ui.corner(card, 10)
		local stroke = Ui.stroke(card, C.line, 2)
		local fill = Ui.make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 3 }, card)
		Ui.corner(fill, 10)
		local key = Ui.label(card, {
			Position = UDim2.fromOffset(8, 10),
			Size = UDim2.fromOffset(32, 32),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.panel2,
			Font = Enum.Font.GothamBlack,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = keyText(i),
			ZIndex = 4,
		})
		Ui.corner(key, 7)
		local name = Ui.label(card, { Position = UDim2.fromOffset(48, 7), Size = UDim2.new(1, -54, 0, 20), Font = Enum.Font.GothamBlack, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
		local status = Ui.label(card, { Position = UDim2.fromOffset(48, 28), Size = UDim2.new(1, -54, 0, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.muted, ZIndex = 4 })
		card.Activated:Connect(function()
			onUse(i)
		end)
		self.cards[i] = { frame = card, stroke = stroke, fill = fill, key = key, name = name, status = status, ready = false }
	end
	local meterBack = Ui.make("Frame", { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0 }, root)
	Ui.corner(meterBack, 8)
	Ui.stroke(meterBack, C.line, 1)
	self.meterFill = Ui.make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.gold, BorderSizePixel = 0 }, meterBack)
	Ui.corner(self.meterFill, 8)
	Ui.make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 170, 40), Color3.fromRGB(255, 240, 150)) }, self.meterFill)
	self.meterText = Ui.make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextColor3 = C.text,
		TextStrokeTransparency = 0.4,
		Text = "AWAKENING 0%",
		AutoButtonColor = false,
		Selectable = false,
		ZIndex = 3,
	}, meterBack)
	self.meterText.Activated:Connect(onAwaken)
	self.meterStroke = meterBack:FindFirstChildOfClass("UIStroke")

	-- foe's awakening (thin bar under the foe's spin bar)
	self.foeMeter = Ui.bar(hud.battleFrame, { Position = UDim2.new(0.58, 0, 1, -4), Size = UDim2.new(0.42, 0, 0, 4) }, C.gold)

	-- big title banner (special names, AWAKENS!, WINNER)
	local banner = Ui.make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromOffset(900, 80),
		BackgroundTransparency = 1,
		Font = Enum.Font.LuckiestGuy,
		TextSize = 64,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
		Visible = false,
		ZIndex = 15,
	}, gui)
	self.bannerStroke = Ui.make("UIStroke", { Thickness = 4, Color = Color3.fromRGB(20, 10, 30), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, banner)
	self.bannerGradient = Ui.make("UIGradient", { Rotation = 90 }, banner)
	self.banner = banner
	self.bannerScale = Ui.make("UIScale", { Scale = 1 }, banner)

	-- screen tint for awakenings
	self.tint = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)
	return self
end

-- Called when a battle starts: which specials this player brought.
function SpecialsHud:setLoadout(ids)
	for i, card in ipairs(self.cards) do
		local def = BeyConfig.Specials[ids and ids[i] or ""]
		card.def = def
		card.name.Text = def and def.Name or "Empty"
		card.name.TextColor3 = def and def.Color or C.muted
		card.status.Text = def and KIND_TEXT[def.Kind] or ""
		card.key.Text = keyText(i)
		card.fill.Size = UDim2.fromScale(1, 1)
	end
	self.meterFill.Size = UDim2.fromScale(0, 1)
	self.meterText.Text = "AWAKENING 0%   [" .. keyText(3) .. "]"
	self.awakeUntil = nil
end

function SpecialsHud:show(visible)
	self.root.Visible = visible
	if not visible then
		self.tint.BackgroundTransparency = 1
	end
end

-- snap = { specials = { { left, cooldown } x2 }, meter = 0..1, awakened, awakenUsed } from the server.
function SpecialsHud:update(snap, foe)
	if type(snap) == "table" and type(snap.specials) == "table" then
		for i, card in ipairs(self.cards) do
			local s = snap.specials[i]
			if s and card.def then
				local left = tonumber(s.left) or 0
				local cd = math.max(tonumber(s.cooldown) or 1, 0.01)
				local ready = left <= 0.05
				card.fill.Size = UDim2.fromScale(ready and 0 or math.clamp(left / cd, 0, 1), 1)
				card.status.Text = ready and ("READY  ·  " .. KIND_TEXT[card.def.Kind]) or ("%.1fs"):format(left)
				card.status.TextColor3 = ready and C.good or C.muted
				card.stroke.Color = ready and card.def.Color or C.line
				if ready and not card.ready then
					card.frame.Size = UDim2.new(0.5, -5, 0, 58)
					TweenService:Create(card.frame, TweenInfo.new(0.2), { Size = UDim2.new(0.5, -5, 0, 52) }):Play()
				end
				card.ready = ready
			end
		end
		local m = math.clamp(tonumber(snap.meter) or 0, 0, 1)
		if snap.awakened then
			self.meterText.Text = "AWAKENED!"
			self.meterFill.Size = UDim2.fromScale(1, 1)
		elseif snap.awakenUsed then
			self.meterText.Text = "AWAKENING USED"
			self.meterFill.Size = UDim2.fromScale(0, 1)
		elseif m >= 1 then
			self.meterText.Text = "AWAKEN READY!   PRESS [" .. keyText(3) .. "]"
			self.meterFill.Size = UDim2.fromScale(1, 1)
			if self.meterStroke then
				self.meterStroke.Color = (math.floor(os.clock() * 3) % 2 == 0) and C.gold or C.line
				self.meterStroke.Thickness = 2
			end
		else
			self.meterText.Text = ("AWAKENING %d%%   [%s]"):format(math.floor(m * 100), keyText(3))
			self.meterFill.Size = UDim2.fromScale(m, 1)
			if self.meterStroke then
				self.meterStroke.Color = C.line
				self.meterStroke.Thickness = 1
			end
		end
	end
	if type(foe) == "table" then
		self.foeMeter.Size = UDim2.fromScale(foe.awakened and 1 or math.clamp(tonumber(foe.meter) or 0, 0, 1), 1)
	end
end

-- Pressed but refused (cooldown): shake the card.
function SpecialsHud:refused(i)
	local card = self.cards[i]
	if not card then
		return
	end
	local p = card.frame.Position
	card.frame.Position = p + UDim2.fromOffset(6, 0)
	TweenService:Create(card.frame, TweenInfo.new(0.15, Enum.EasingStyle.Elastic), { Position = p }):Play()
end

-- Big title text: special names, "... AWAKENS!", WINNER. small = the foe's (smaller, lower).
function SpecialsHud:showBanner(text, color, small)
	local b = self.banner
	b.Text = text
	b.TextSize = small and 40 or 64
	b.Position = UDim2.fromScale(0.5, small and 0.2 or 0.27)
	color = color or Color3.new(1, 1, 1)
	self.bannerGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	b.TextTransparency = 0
	self.bannerStroke.Transparency = 0
	b.Visible = true
	self.bannerScale.Scale = 1.6
	TweenService:Create(self.bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local token = {}
	self._banner = token
	task.delay(small and 1.0 or 1.3, function()
		if self._banner ~= token then
			return
		end
		TweenService:Create(b, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(self.bannerStroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		task.delay(0.32, function()
			if self._banner == token then
				b.Visible = false
			end
		end)
	end)
end

-- Coloured screen wash (awakening).
function SpecialsHud:wash(color, strength)
	self.tint.BackgroundColor3 = color
	self.tint.BackgroundTransparency = 1 - (strength or 0.35)
	TweenService:Create(self.tint, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

return SpecialsHud
]=====])
install('SPS', '', 'ModuleScript', 'Spirits', [=====[
--!nonstrict
-- Spirits: the giant glowing creature that appears when a bey uses a special or awakens. Client-only visuals.
--   summon(o)  o = { spirit = id, body = the bey's Body part, kind = "special" | "awaken", special = "dash" |
--              "guard" | "heal" | "quake", dir = Vector3 (toward the foe), face = function() -> Vector3 | nil
--              (a point to face while awakened), duration = seconds (awaken), big = bool (your own bey) }
-- The creature uses the Blender mesh from ReplicatedStorage.SpiritMeshes when it has been imported (README), and a
-- simple beast built from parts otherwise. Material ForceField (translucent shimmer) over a faint Neon core, so it
-- glows and you can still see the battle through it.
-- Unverified in Roblox: the look, the timing and the mesh orientation (the mesh should face -Z; see SPIN_FIX).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local meshData = {}
do
	local mod = Shared:FindFirstChild("SpiritMeshData")
	if mod then
		local ok, data = pcall(require, mod)
		if ok and type(data) == "table" then
			meshData = data
		end
	end
end

local Spirits = {}
Spirits.__index = Spirits

local MAX_ACTIVE = 3
local SPIN_FIX = CFrame.new() -- extra rotation if the imported mesh doesn't face -Z (e.g. CFrame.Angles(0, math.pi, 0))
local SPECIAL_HEIGHT = 10 -- studs tall when it appears for a special (a bey is ~4 wide)
local AWAKEN_HEIGHT = 15
local SPECIAL_TIME = 1.4

function Spirits.new(effects, hooks)
	local self = setmetatable({}, Spirits)
	self.effects = effects
	self.hooks = hooks or {} -- { cinematic = function(duration, zoom), banner = function(text, color, small) }
	self.active = {}
	self.folder = Instance.new("Folder")
	self.folder.Name = "SpinforgeSpirits"
	self.folder.Parent = Workspace
	return self
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function easeOutBack(t)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function styled(p, color, material, transparency)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Material = material
	p.Color = color
	p.Transparency = transparency
	p:SetAttribute("BaseTransparency", transparency)
end

-- A beast from basic parts (used until the Blender meshes are imported). About 1 stud tall; scaled later.
local function fallbackBeast(color)
	local m = Instance.new("Model")
	local function part(shape, size, cf)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		styled(p, color, Enum.Material.ForceField, 0)
		p.Parent = m
		return p
	end
	local B, Cy = Enum.PartType.Ball, Enum.PartType.Cylinder
	local body = part(B, Vector3.new(0.55, 0.5, 1.1), CFrame.new(0, 0.62, 0.05))
	part(B, Vector3.new(0.42, 0.4, 0.5), CFrame.new(0, 0.86, -0.55)) -- head, facing -Z
	part(B, Vector3.new(0.2, 0.18, 0.3), CFrame.new(0, 0.8, -0.82)) -- snout
	for _, sx in ipairs({ -1, 1 }) do
		part(Enum.PartType.Block, Vector3.new(0.07, 0.32, 0.07), CFrame.new(0.14 * sx, 1.12, -0.5) * CFrame.Angles(math.rad(-25), 0, math.rad(-20 * sx))) -- horns
		part(Cy, Vector3.new(0.48, 0.13, 0.13), CFrame.new(0.17 * sx, 0.24, -0.32) * CFrame.Angles(0, 0, math.rad(90))) -- front legs
		part(Cy, Vector3.new(0.48, 0.14, 0.14), CFrame.new(0.17 * sx, 0.24, 0.4) * CFrame.Angles(0, 0, math.rad(90))) -- back legs
	end
	part(Enum.PartType.Block, Vector3.new(0.08, 0.08, 0.55), CFrame.new(0, 0.78, 0.78) * CFrame.Angles(math.rad(35), 0, 0)) -- tail
	m.PrimaryPart = body
	return m, Vector3.new(0.6, 1.25, 1.6)
end

-- Returns a Model (pivot at the creature's feet, facing -Z) and its unscaled size.
local function buildCreature(id, color)
	local folder = ReplicatedStorage:FindFirstChild("SpiritMeshes")
	local template = folder and folder:FindFirstChild(id, true)
	local size = meshData[id] and meshData[id].Size
	if template and template:IsA("MeshPart") and size then
		local m = Instance.new("Model")
		local shell = template:Clone()
		for _, child in ipairs(shell:GetChildren()) do
			child:Destroy() -- drop anything the importer attached (SurfaceAppearance, welds)
		end
		pcall(function()
			shell.TextureID = ""
		end)
		shell.Size = size
		shell.CFrame = CFrame.new(0, size.Y / 2, 0) * SPIN_FIX
		styled(shell, color, Enum.Material.ForceField, 0)
		shell.Parent = m
		local core = shell:Clone()
		core.Size = size * 0.97
		core.CFrame = shell.CFrame
		styled(core, color, Enum.Material.Neon, 0.82)
		core.Parent = m
		local base = Instance.new("Part")
		base.Name = "Pivot"
		base.Size = Vector3.new(0.1, 0.1, 0.1)
		base.CFrame = CFrame.new()
		styled(base, color, Enum.Material.SmoothPlastic, 1)
		base.Parent = m
		m.PrimaryPart = base
		return m, size
	end
	local m, s = fallbackBeast(color)
	local base = Instance.new("Part")
	base.Name = "Pivot"
	base.Size = Vector3.new(0.1, 0.1, 0.1)
	base.CFrame = CFrame.new()
	styled(base, color, Enum.Material.SmoothPlastic, 1)
	base.Parent = m
	m.PrimaryPart = base
	return m, s
end

local function setAlpha(model, alpha)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local base = p:GetAttribute("BaseTransparency") or 0
			p.Transparency = base >= 1 and 1 or lerp(1, base, alpha)
		end
	end
end

local function addGlow(model, color, range)
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 0.5, 0)
	att.Parent = model.PrimaryPart
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 3
	light.Shadows = false
	light.Parent = model.PrimaryPart
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.5, 1.1)
	pe.Speed = NumberRange.new(4, 10)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rate = 40
	pe.Parent = att
	return light, pe
end

function Spirits:_retire(entry)
	if entry.conn then
		entry.conn:Disconnect()
	end
	if entry.model then
		entry.model:Destroy()
	end
	for _, extra in ipairs(entry.extras or {}) do
		extra:Destroy()
	end
	for i, e in ipairs(self.active) do
		if e == entry then
			table.remove(self.active, i)
			break
		end
	end
end

function Spirits:summon(o)
	local def = BeyConfig.Spirits[o.spirit]
	local body = o.body
	if not def or not body or not body.Parent then
		return
	end
	while #self.active >= MAX_ACTIVE do
		self:_retire(self.active[1])
	end
	local color = def.Color
	local awaken = o.kind == "awaken"
	local model, size = buildCreature(o.spirit, color)
	local height = awaken and AWAKEN_HEIGHT or SPECIAL_HEIGHT * (o.big and 1 or 0.9)
	local scale = height / math.max(size.Y, 0.01)
	model.Name = o.spirit
	model.Parent = self.folder
	local light = addGlow(model, color, awaken and 40 or 28)
	local entry = { model = model, extras = {} }
	table.insert(self.active, entry)

	local dir = o.dir
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local start = os.clock()
	local total = awaken and (o.duration or 10) + 1.4 or SPECIAL_TIME
	local smoothPos = body.Position

	-- the opening flourish
	local ground = body.Position - Vector3.new(0, 1.8, 0)
	self.effects:burst(ground, color, awaken and 26 or 16)
	if awaken then
		entry.extras = self:_sigil(ground, color)
	end
	if self.hooks.banner then
		local name = BeyConfig.Specials[o.id or ""] and BeyConfig.Specials[o.id].Name or def.Name
		local text = awaken and (string.upper(def.Name) .. " AWAKENS!") or (string.upper(name) .. "!")
		self.hooks.banner(text, color, not o.big)
	end
	if o.big and self.hooks.cinematic then
		self.hooks.cinematic(awaken and 1.6 or 0.9, awaken and 0.5 or 0.7)
	end

	entry.conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - start
		if t >= total or not body.Parent then
			self:_retire(entry)
			return
		end
		smoothPos = smoothPos:Lerp(body.Position, 1 - math.exp(-12 * dt))
		local base = smoothPos - Vector3.new(0, 1.8, 0)
		local facing = dir
		local s, alpha, offset = 1, 1, Vector3.zero
		if awaken then
			local target = o.face and o.face()
			if typeof(target) == "Vector3" then
				local d = Vector3.new(target.X - smoothPos.X, 0, target.Z - smoothPos.Z)
				if d.Magnitude > 0.5 then
					facing = d.Unit
					dir = facing
				end
			end
			local rise = math.clamp(t / 0.6, 0, 1)
			offset = Vector3.new(0, -height * (1 - easeOutBack(rise)) * 0.6, 0) - facing * 2.5
			alpha = t < 1.6 and 1 or 0.6 -- full for the reveal, then lighter so the fight stays readable
			if t > total - 0.6 then
				alpha = 0.6 * (total - t) / 0.6
			end
			offset += Vector3.new(0, math.sin(t * 2.2) * 0.4, 0)
		else
			local k = o.special
			if t < 0.22 then
				local a = t / 0.22
				s = lerp(0.3, 1, easeOutBack(a))
				alpha = a
			elseif t < 0.5 then
				offset = Vector3.new(0, math.sin((t - 0.22) * 18) * 0.3, 0)
			elseif t < 1.05 then
				local a = (t - 0.5) / 0.55
				if k == "dash" or k == "quake" then
					offset = dir * (a * a * 14) -- lunges at the foe
					if k == "quake" then
						offset += Vector3.new(0, math.sin(a * math.pi) * 4, 0)
					end
				elseif k == "heal" then
					offset = Vector3.new(0, a * 4, 0)
				else -- guard: rears up and circles the bey
					facing = (CFrame.Angles(0, a * math.pi * 0.8, 0) * dir)
				end
			else
				local a = (t - 1.05) / (SPECIAL_TIME - 1.05)
				s = 1 + a * 0.15
				alpha = 1 - a
				offset = (k == "dash" or k == "quake") and dir * 14 or Vector3.zero
			end
			offset -= dir * 2
		end
		local pos = base + offset
		model:PivotTo(CFrame.lookAt(pos, pos + facing))
		pcall(function()
			model:ScaleTo(scale * s)
		end)
		setAlpha(model, alpha)
		light.Brightness = 3 * alpha
	end)
end

-- Awakening: a glowing sigil on the floor and a pillar of light. Returns the parts (removed with the creature).
function Spirits:_sigil(ground, color)
	local parts = {}
	local function neon(shape, size, cf, transparency)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		styled(p, color, Enum.Material.Neon, transparency)
		p.Parent = self.folder
		table.insert(parts, p)
		return p
	end
	local ring = neon(Enum.PartType.Cylinder, Vector3.new(0.15, 26, 26), CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)), 0.35)
	local inner = neon(Enum.PartType.Cylinder, Vector3.new(0.16, 18, 18), CFrame.new(ground + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.75)
	local spokes = {}
	for i = 0, 5 do
		local a = i * math.pi / 3
		table.insert(spokes, neon(Enum.PartType.Block, Vector3.new(0.6, 0.18, 24), CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, a, 0), 0.45))
	end
	local pillar = neon(Enum.PartType.Cylinder, Vector3.new(80, 5, 5), CFrame.new(ground + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.25)
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 1.6 or not ring.Parent then
			conn:Disconnect()
			for _, p in ipairs(parts) do
				p:Destroy()
			end
			return
		end
		local spin = CFrame.Angles(0, t * 2.5, 0)
		for i, p in ipairs(spokes) do
			p.CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * spin * CFrame.Angles(0, (i - 1) * math.pi / 3, 0)
			p.Transparency = lerp(0.45, 1, math.clamp((t - 0.9) / 0.7, 0, 1))
		end
		ring.Transparency = lerp(0.35, 1, math.clamp((t - 0.9) / 0.7, 0, 1))
		inner.Transparency = lerp(0.75, 1, math.clamp((t - 0.9) / 0.7, 0, 1))
		local w = 5 + t * 6
		pillar.Size = Vector3.new(80, w, w)
		pillar.Transparency = lerp(0.25, 1, math.clamp(t / 1.2, 0, 1))
	end)
	return parts
end

-- A solid-coloured creature for menu cards (ViewportFrames don't show ForceField well). Height ~2 studs, feet at 0.
function Spirits.preview(id)
	local def = BeyConfig.Spirits[id]
	if not def then
		return nil
	end
	local model, size = buildCreature(id, def.Color)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Pivot" then
			local base = p:GetAttribute("BaseTransparency") or 0
			p.Material = Enum.Material.SmoothPlastic
			p.Transparency = base > 0.5 and 1 or 0
		end
	end
	pcall(function()
		model:ScaleTo(2 / math.max(size.Y, 0.01))
	end)
	return model
end

function Spirits:clear()
	while #self.active > 0 do
		self:_retire(self.active[1])
	end
end

return Spirits
]=====])
install('SPS', '', 'ModuleScript', 'Tutorial', [=====[
--!nonstrict
-- Tutorial: short contextual hints shown while you control a bey, until you've done each thing once:
-- drive, lean in, brake, launch off the lip, slam. Each hint advances when the controller reports the action.
-- Finishing it tells the server (saved in Settings.TutorialDone). Settings can replay it.

local UserInputService = game:GetService("UserInputService")

local Tutorial = {}
Tutorial.__index = Tutorial

local function steps()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local pad = UserInputService.GamepadEnabled
	local aim = touch and "Drag on the right side of the screen" or pad and "Push the right stick" or "Move the mouse"
	return {
		{ id = "moved", title = "Drive", body = touch and "Use the left thumbstick to drive. Your bey goes where the camera faces." or pad and "Left stick drives. Your bey goes where the camera faces." or "W A S D to drive. Your bey goes where the camera faces." },
		{ id = "leaned", title = "Lean in for speed", body = aim .. " DOWN to tip the nose down. You go faster." },
		{ id = "braked", title = "Lean back to brake", body = aim .. " UP to tip the nose back. You slow down and stop." },
		{ id = "launched", title = "Launch off the lip", body = "Drive up the stadium wall and lift the nose just as you reach the steep lip. Nose up = higher." },
		{ id = "slammed", title = "Slam", body = (touch and "Tap SLAM" or pad and "Press the right trigger" or "Click") .. " while in the air to dive down. Land it next to your opponent." },
	}
end

function Tutorial.new(hud, remotes)
	local self = setmetatable({}, Tutorial)
	self.hud = hud
	self.remotes = remotes
	self.done = true -- until the profile says otherwise
	self.index = 1
	self.active = false
	self.steps = steps()
	return self
end

function Tutorial:setProfile(p)
	local wasDone = self.done
	self.done = p.Settings.TutorialDone
	if wasDone and not self.done then
		self.index = 1
		self.steps = steps()
	end
	self:_render()
end

-- Shown only while the player controls a bey.
function Tutorial:setActive(active)
	self.active = active
	self:_render()
end

function Tutorial:signal(id)
	if self.done or not self.active then
		return
	end
	local step = self.steps[self.index]
	if step and step.id == id then
		self.index += 1
		if self.index > #self.steps then
			self.done = true
			self.remotes.Request:FireServer({ action = "tutorialDone" })
			self.hud:hideHint()
			self.hud:toast("Tutorial complete! Challenge the villain from the hub.")
			return
		end
		self:_render()
	end
end

function Tutorial:_render()
	local step = self.steps[self.index]
	if self.done or not self.active or not step then
		self.hud:hideHint()
		return
	end
	self.hud:showHint(("TUTORIAL %d/%d"):format(self.index, #self.steps), step.title, step.body)
end

return Tutorial
]=====])
install('SPS', '', 'ModuleScript', 'Ui', [=====[
--!nonstrict
-- Ui: small helpers so every screen shares one look (dark panels, cyan accent, rarity colours).

local Ui = {}

Ui.C = {
	panel = Color3.fromRGB(14, 18, 28),
	panel2 = Color3.fromRGB(24, 30, 44),
	line = Color3.fromRGB(52, 62, 84),
	text = Color3.fromRGB(232, 238, 248),
	muted = Color3.fromRGB(150, 162, 186),
	accent = Color3.fromRGB(90, 200, 255),
	good = Color3.fromRGB(110, 220, 140),
	bad = Color3.fromRGB(255, 96, 96),
	warn = Color3.fromRGB(255, 186, 72),
	gold = Color3.fromRGB(255, 210, 110),
}

-- Ui.make("TextLabel", { Size = ..., Text = ... }, parent)
function Ui.make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(parent, px)
	return Ui.make("UICorner", { CornerRadius = UDim.new(0, px or 8) }, parent)
end

function Ui.stroke(parent, color, thickness)
	return Ui.make("UIStroke", { Color = color or Ui.C.line, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function Ui.pad(parent, px)
	return Ui.make("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	}, parent)
end

function Ui.panel(parent, props)
	local f = Ui.make("Frame", { BackgroundColor3 = Ui.C.panel, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, nil)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	Ui.corner(f, 10)
	Ui.stroke(f)
	f.Parent = parent
	return f
end

function Ui.label(parent, props)
	local l = Ui.make("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Ui.C.text,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, nil)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function Ui.button(parent, text, props, onClick)
	local b = Ui.make("TextButton", {
		BackgroundColor3 = Ui.C.panel2,
		TextColor3 = Ui.C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Text = text,
		AutoButtonColor = true,
		Selectable = true,
	}, nil)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Ui.corner(b, 8)
	Ui.stroke(b, Ui.C.line)
	b.Parent = parent
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

-- A horizontal bar: returns the fill frame (set fill.Size = UDim2.fromScale(x, 1)).
function Ui.bar(parent, props, color)
	local back = Ui.make("Frame", { BackgroundColor3 = Ui.C.panel2, BorderSizePixel = 0 }, nil)
	for k, v in pairs(props or {}) do
		back[k] = v
	end
	Ui.corner(back, 6)
	back.Parent = parent
	local fill = Ui.make("Frame", { BackgroundColor3 = color or Ui.C.accent, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, back)
	Ui.corner(fill, 6)
	return fill, back
end

return Ui
]=====])
print('Spinforge installed: 34 scripts. Press Play.')

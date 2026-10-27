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
print('Spinforge installer part 1 of 8 done. Now run part 2.')

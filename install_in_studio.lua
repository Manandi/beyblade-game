-- Paste this whole file into Studio's Command Bar (View > Command Bar) and press Enter.
-- It (re)creates every script. Safe to run again after an update. Then press Play.
local SSS = game:GetService('ServerScriptService')
local RS = game:GetService('ReplicatedStorage')
local SPS = game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')
local parents = { ReplicatedStorage = RS, ServerScriptService = SSS, StarterPlayerScripts = SPS }
local function install(class, parentName, name, source)
	local parent = parents[parentName]
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local s = Instance.new(class)
	s.Name = name
	s.Source = source
	s.Parent = parent
end

install('ModuleScript', 'ReplicatedStorage', 'BeyConfig', [=====[
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
	BaseSpeed = 42, -- studs/second
	SpeedPerAttack = 0.5, -- extra speed per Attack point
	SpeedPerBalance = 0.3, -- extra speed per Balance point
	Accel = 110, -- ground acceleration while holding a direction
	Brake = 35, -- ground slow-down when you let go (momentum feels weighty)
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
install('ModuleScript', 'ReplicatedStorage', 'BeyDesigns', [=====[
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
install('ModuleScript', 'ReplicatedStorage', 'BeyVisuals', [=====[
--!nonstrict
-- Builds a bey's looks from its three parts' designs (BeyDesigns) out of basic Roblox parts.
-- Everything is welded to the spinning hub, massless and non-colliding, so the physics body is unchanged.
-- Call BeyVisuals.Attach on the SERVER after the model is parented to Workspace (so welds capture the layout).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BeyConfig = require(ReplicatedStorage:WaitForChild("BeyConfig"))
local BeyDesigns = require(ReplicatedStorage:WaitForChild("BeyDesigns"))

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
local function buildRarityEffects(ctx, layerDesign, rarity)
	local rank = rarityRank(rarity)
	if rank >= rarityRank("Epic") then
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
function BeyVisuals.Attach(hub, root, partIds, parent)
	local ctx = { hub = hub, root = root, parent = parent or hub.Parent }
	local layer, disc, driver = BeyDesigns.Parts[partIds.Layer], BeyDesigns.Parts[partIds.Disc], BeyDesigns.Parts[partIds.Driver]
	assert(layer and disc and driver, "missing design for a part")
	buildDisc(ctx, disc)
	buildDriver(ctx, driver)
	buildLayer(ctx, layer)

	local best = "Common"
	for _, slot in ipairs(BeyConfig.Slots) do
		local rarity = BeyConfig.Parts[partIds[slot]].Rarity
		if rarityRank(rarity) > rarityRank(best) then
			best = rarity
		end
	end
	buildRarityEffects(ctx, layer, best)
end

return BeyVisuals
]=====])
install('Script', 'ServerScriptService', 'StadiumBuilder', [=====[
--!nonstrict
-- Builds the prototype test stadium (floor, launch ramp, target dummies) if the place has none.
-- Replace this with a hand-built map in Studio later; delete the script or name your map "Stadium".
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BeyConfig = require(ReplicatedStorage:WaitForChild("BeyConfig"))
Workspace.Gravity = BeyConfig.Movement.Gravity

if Workspace:FindFirstChild("Stadium") then
	return
end

local stadium = Instance.new("Folder")
stadium.Name = "Stadium"
stadium.Parent = Workspace

local function block(name, size, cframe, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = stadium
	return p
end

-- Floor: top surface at y = 1, 300 x 300 studs.
block("Floor", Vector3.new(300, 2, 300), CFrame.new(0, 0, -60), Color3.fromRGB(60, 64, 80))

-- Launch ramp: 40 studs long, rising 25 degrees toward -Z. Low end at z = -15, top near z = -51.
local angle = math.rad(25)
local length = 40
local rise = length / 2 * math.sin(angle)
local run = length / 2 * math.cos(angle)
block("Ramp", Vector3.new(24, 1, length), CFrame.new(0, 1 + rise, -15 - run) * CFrame.Angles(angle, 0, 0), Color3.fromRGB(230, 170, 60))

-- Target dummies: unanchored discs the slam can knock around. Tagged so the server finds them.
local function dummy(x, z)
	local p = Instance.new("Part")
	p.Name = "Dummy"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(2, 7, 7)
	p.CFrame = CFrame.new(x, 4.5, z) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = Color3.fromRGB(220, 70, 70)
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = stadium
	CollectionService:AddTag(p, "BeyTarget")
end
dummy(-10, -80)
dummy(10, -80)
dummy(0, -92)

local pad = block("SpawnPad", Vector3.new(14, 0.4, 14), CFrame.new(0, 1.2, 0), Color3.fromRGB(90, 200, 255))
pad.CanCollide = false
]=====])
install('Script', 'ServerScriptService', 'BeySpawner', [=====[
--!nonstrict
-- Spawns each player's bey and handles the slam hit. The player's avatar is parked off to the side.
-- Network ownership of the bey body goes to its player (client-authoritative, fine for story/AI fights).
-- BEFORE PvP: move to Server Authority. See PROJECT.md.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local BeyConfig = require(ReplicatedStorage:WaitForChild("BeyConfig"))
local BeyVisuals = require(ReplicatedStorage:WaitForChild("BeyVisuals"))
local M = BeyConfig.Movement

local remotes = Instance.new("Folder")
remotes.Name = "BeyRemotes"
remotes.Parent = ReplicatedStorage
local slamRemote = Instance.new("RemoteEvent")
slamRemote.Name = "Slam"
slamRemote.Parent = remotes

local beysFolder = Instance.new("Folder")
beysFolder.Name = "Beys"
beysFolder.Parent = Workspace

local beyByPlayer = {} -- player -> model
local lastSlam = {} -- player -> os.clock()

local function buildBey(player)
	local partIds = BeyConfig.StarterBey -- TODO: read the equipped bey from player data (DataStore milestone)
	local level = 1
	local stats = BeyConfig.ComputeStats(partIds, level)

	local model = Instance.new("Model")
	model.Name = tostring(player.UserId)
	model.Parent = beysFolder -- parent early so welds capture the layout

	-- Body: an invisible ball that does the physics. AlignOrientation stops it rolling.
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(4, 4, 4)
	body.Transparency = 1
	body.CustomPhysicalProperties = PhysicalProperties.new(1, 0.1, 0.1, 1, 1)
	body.CFrame = CFrame.new(M.SpawnPosition + Vector3.new(0, 0, 0))
	body.Parent = model
	model.PrimaryPart = body

	for _, stat in ipairs(BeyConfig.StatNames) do
		body:SetAttribute(stat, stats[stat])
	end
	body:SetAttribute("Level", level)

	local bodyAttach = Instance.new("Attachment")
	bodyAttach.Name = "Center"
	bodyAttach.Parent = body

	local align = Instance.new("AlignOrientation")
	align.Name = "Align"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = bodyAttach
	align.RigidityEnabled = true
	align.CFrame = CFrame.new()
	align.Parent = model

	-- Hub: the small spinning core. BeyVisuals welds the whole designed bey to it.
	local top = Instance.new("Part")
	top.Name = "Top"
	top.Shape = Enum.PartType.Cylinder
	top.Size = Vector3.new(0.8, 1.2, 1.2) -- cylinder axis is X; rotated to stand upright below
	top.Color = BeyConfig.RarityColors[BeyConfig.Parts[partIds.Layer].Rarity]
	top.Material = Enum.Material.Metal
	top.CanCollide = false
	top.CanQuery = false
	top.CanTouch = false
	top.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0.1, 0.1, 1, 1)
	top.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(90))
	top.Parent = model

	local topAttach = Instance.new("Attachment")
	topAttach.Name = "Axis"
	topAttach.Parent = top -- X axis of the cylinder is already world-up after the rotation above

	local bodyAxis = Instance.new("Attachment")
	bodyAxis.Name = "Axis"
	bodyAxis.CFrame = CFrame.Angles(0, 0, math.rad(90)) -- X axis -> body's up
	bodyAxis.Parent = body

	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "Spin"
	hinge.Attachment0 = bodyAxis
	hinge.Attachment1 = topAttach
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = 50000
	hinge.AngularVelocity = 30 -- rad/s; stamina drain will drive this in milestone 2
	hinge.Parent = model

	BeyVisuals.Attach(top, body.CFrame, partIds, model)

	return model, body
end

local function parkAvatar(character)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
	end
	if root then
		root.CFrame = CFrame.new(0, 4, 24)
		root.Anchored = true
	end
end

local function onCharacter(player, character)
	local old = beyByPlayer[player]
	if old then
		old:Destroy()
	end
	parkAvatar(character)
	local model, body = buildBey(player)
	body:SetNetworkOwner(player)
	beyByPlayer[player] = model
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end)
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local model = beyByPlayer[player]
	if model then
		model:Destroy()
	end
	beyByPlayer[player] = nil
	lastSlam[player] = nil
end)

-- The client reports a landed slam. The server re-checks everything it can before knocking dummies about.
slamRemote.OnServerEvent:Connect(function(player, pos, impactSpeed)
	if typeof(pos) ~= "Vector3" or typeof(impactSpeed) ~= "number" or impactSpeed ~= impactSpeed then
		return
	end
	local model = beyByPlayer[player]
	local body = model and model:FindFirstChild("Body")
	if not body then
		return
	end
	if (body.Position - pos).Magnitude > 25 then
		return -- reported impact is nowhere near the bey
	end
	local now = os.clock()
	if lastSlam[player] and now - lastSlam[player] < M.SlamCooldown * 0.8 then
		return
	end
	lastSlam[player] = now

	local strength = math.clamp(impactSpeed / M.SlamSpeed, 0, 1.2)
	local attack = body:GetAttribute("Attack") or 0
	local impulse = M.SlamImpulse * strength * (1 + attack * M.SlamAttackScale)
	for _, target in ipairs(CollectionService:GetTagged("BeyTarget")) do
		local offset = target.Position - pos
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= M.SlamRadius and math.abs(offset.Y) < 10 then
			local dir = (flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)) + Vector3.new(0, 0.5, 0)
			target:ApplyImpulse(dir.Unit * impulse * target.AssemblyMass)
		end
	end
end)
]=====])
install('LocalScript', 'StarterPlayerScripts', 'BeyController', [=====[
--!nonstrict
-- Drives the local player's bey.
--   Move: WASD / left thumbstick (camera-relative)       Jump: Space / jump button / gamepad A
--   Aim:  mouse X turns, mouse Y tilts the bey up/down   Touch: drag the right side. Gamepad: right stick
--   Slam: click (or the SLAM button / right trigger) while airborne          R: reset
-- Tilt matters: aim up when leaving a ramp to launch higher, aim down to dive. All numbers: BeyConfig.Movement.
-- This script owns the physics (the server gave this player network ownership of the body).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BeyConfig = require(ReplicatedStorage:WaitForChild("BeyConfig"))
local M = BeyConfig.Movement

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local slamRemote = ReplicatedStorage:WaitForChild("BeyRemotes"):WaitForChild("Slam")
local beysFolder = Workspace:WaitForChild("Beys")

-- Move input. Roblox's control module gives one vector for keyboard, thumbstick and gamepad, but it may be
-- missing or slow, so we never block on it: until it loads (or if it never does) our own reader below is used.
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

-- Fallback touch stick: a drag that starts on the left half of the screen moves the bey.
local touchStick = { input = nil, origin = Vector2.zero, vec = Vector2.zero }
UserInputService.TouchStarted:Connect(function(touch, processed)
	if processed or touchStick.input or touch.Position.X > camera.ViewportSize.X * 0.5 then
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

local function getMoveVector() -- x = right, z = back
	if controls then
		return controls:GetMoveVector()
	end
	local x, z = 0, 0
	if not UserInputService:GetFocusedTextBox() then
		local K = Enum.KeyCode
		x = (UserInputService:IsKeyDown(K.D) and 1 or 0) - (UserInputService:IsKeyDown(K.A) and 1 or 0)
		z = (UserInputService:IsKeyDown(K.S) and 1 or 0) - (UserInputService:IsKeyDown(K.W) and 1 or 0)
	end
	for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if state.KeyCode == Enum.KeyCode.Thumbstick1 and state.Position.Magnitude > 0.15 then
			x = x + state.Position.X
			z = z - state.Position.Y
		end
	end
	x = x + touchStick.vec.X
	z = z + touchStick.vec.Y
	local v = Vector3.new(x, 0, z)
	return v.Magnitude > 1 and v.Unit or v
end

local MAX_TILT = math.rad(M.MaxTiltDeg)

local model, align, body
local yaw, pitch = 0, 0
local grounded, wasGrounded = false, false
local slamming, slamStartedAt, slamReadyAt = false, 0, 0
local lastJumpAt = -10
local jumpQueued, slamQueued = false, false
local lastLandSpeed = 0
local focus = nil
local noseYaw = 0 -- which way the bey's nose points: its travel direction, so "tilt up" always means up the way you're going

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { beysFolder }

----------------------------------------------------------------------- HUD

local gui = Instance.new("ScreenGui")
gui.Name = "BeyHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local readout = Instance.new("TextLabel")
readout.Size = UDim2.new(0, 260, 0, 64)
readout.Position = UDim2.new(0, 12, 0, 12)
readout.BackgroundTransparency = 0.5
readout.BackgroundColor3 = Color3.new(0, 0, 0)
readout.TextColor3 = Color3.new(1, 1, 1)
readout.Font = Enum.Font.Code
readout.TextSize = 16
readout.TextXAlignment = Enum.TextXAlignment.Left
readout.TextYAlignment = Enum.TextYAlignment.Top
readout.Text = ""
readout.Parent = gui

local slamButton = Instance.new("TextButton")
slamButton.Size = UDim2.new(0, 110, 0, 110)
slamButton.AnchorPoint = Vector2.new(1, 1)
slamButton.Position = UDim2.new(1, -30, 1, -150)
slamButton.Text = "SLAM"
slamButton.Font = Enum.Font.GothamBold
slamButton.TextSize = 22
slamButton.BackgroundColor3 = Color3.fromRGB(230, 70, 70)
slamButton.Visible = UserInputService.TouchEnabled
slamButton.Parent = gui
Instance.new("UICorner", slamButton).CornerRadius = UDim.new(1, 0)
slamButton.Activated:Connect(function()
	slamQueued = true
end)

----------------------------------------------------------------------- input

UserInputService.JumpRequest:Connect(function()
	jumpQueued = true
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		slamQueued = true
	elseif input.KeyCode == Enum.KeyCode.R then
		if body then
			body.AssemblyLinearVelocity = Vector3.zero
			body.CFrame = CFrame.new(M.SpawnPosition)
			yaw, pitch = 0, 0
		end
	end
end)

-- Touch drags on the game view (not on the thumbstick or buttons) aim the bey.
UserInputService.InputChanged:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Touch or input == touchStick.input then
		return
	end
	yaw = yaw - input.Delta.X * M.TouchSensitivity
	pitch = math.clamp(pitch - input.Delta.Y * M.TouchSensitivity, -MAX_TILT, MAX_TILT)
end)

local function readGamepad(dt)
	for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if state.KeyCode == Enum.KeyCode.Thumbstick2 then
			local p = state.Position
			if p.Magnitude > 0.15 then
				yaw = yaw - p.X * 2.6 * dt
				pitch = math.clamp(pitch + p.Y * 1.6 * dt, -MAX_TILT, MAX_TILT)
			end
		end
	end
end

----------------------------------------------------------------------- physics

local function clampMagnitude(v, max)
	local m = v.Magnitude
	if m > max and m > 0 then
		return v * (max / m)
	end
	return v
end

local function respawn()
	if not body then
		return
	end
	body.AssemblyLinearVelocity = Vector3.zero
	body.CFrame = CFrame.new(M.SpawnPosition)
	slamming = false
end

local function slamRing(pos, scale)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 120, 60)
	ring.Transparency = 0.2
	ring.Parent = Workspace
	local tween = game:GetService("TweenService"):Create(ring, TweenInfo.new(0.35), {
		Size = Vector3.new(0.4, M.SlamRadius * 2 * scale, M.SlamRadius * 2 * scale),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
end

local function step(dt)
	if not body or not body.Parent then
		return
	end
	local now = os.clock()
	readGamepad(dt)

	local pos = body.Position
	if pos.Y < M.RespawnY then
		respawn()
		return
	end

	local vel = body.AssemblyLinearVelocity
	local tilt = math.clamp(pitch / MAX_TILT, -1, 1) -- -1 nose down .. +1 nose up
	local mv = getMoveVector()
	local yawCF = CFrame.Angles(0, yaw, 0)
	local wish = yawCF.RightVector * mv.X + yawCF.LookVector * -mv.Z
	if wish.Magnitude > 1 then
		wish = wish.Unit
	end
	local hasInput = wish.Magnitude > 0.05
	local speed = M.BaseSpeed
		+ (body:GetAttribute("Attack") or 0) * M.SpeedPerAttack
		+ (body:GetAttribute("Balance") or 0) * M.SpeedPerBalance

	-- Ground probe (ignored briefly after a jump so we don't re-detect the floor we just left).
	local hit
	if now - lastJumpAt > M.JumpGroundIgnore then
		hit = Workspace:Raycast(pos, Vector3.new(0, -(M.Radius + M.GroundProbe), 0), rayParams)
	end
	grounded = hit ~= nil and hit.Normal.Y > M.MinGroundNormalY

	if slamming and now - slamStartedAt > 4 then
		slamming = false -- safety: never stay stuck in slam state
	end

	if grounded then
		local n = hit.Normal

		if slamming then
			slamming = false
			lastLandSpeed = math.max(-vel.Y, 0)
			slamRing(hit.Position + Vector3.new(0, 0.3, 0), math.clamp(lastLandSpeed / M.SlamSpeed, 0.4, 1))
			slamRemote:FireServer(pos, lastLandSpeed)
		end

		-- Remove velocity pushing into the surface, then steer along it so ramps carry us up smoothly.
		local into = vel:Dot(n)
		if into < 0 then
			vel = vel - n * into
		end
		local dv = wish * speed
		local target = dv + Vector3.new(0, -dv:Dot(n) / n.Y, 0)
		vel = vel + clampMagnitude(target - vel, (hasInput and M.Accel or M.Brake) * dt)

		if jumpQueued then
			local up = M.JumpSpeed * (1 + M.JumpTiltBonus * math.max(tilt, 0))
			vel = Vector3.new(vel.X, up, vel.Z)
			lastJumpAt = now
			grounded = false
		end
	else
		-- Takeoff: we were on the ground a frame ago and are now rising off an edge (a ramp).
		if wasGrounded and vel.Y > M.MinLaunchVy then
			local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if flat > M.MinLaunchSpeed then
				local factor = tilt >= 0 and tilt or tilt * M.LaunchDownFactor
				vel = vel + Vector3.new(0, flat * M.LaunchFactor * factor, 0)
			end
		end

		-- Air control: weak steering that can't exceed the faster of (current speed, top speed).
		local flatVel = Vector3.new(vel.X, 0, vel.Z)
		if hasInput then
			local cap = math.max(flatVel.Magnitude, speed)
			flatVel = clampMagnitude(flatVel + wish * M.AirAccel * dt, cap)
		end

		-- Tilt shapes the flight: nose up glides, nose down dives.
		local vy = vel.Y
		if not slamming then
			vy = vy + (tilt >= 0 and tilt * M.GlideLift or tilt * M.DiveAssist) * dt
		end

		vel = Vector3.new(flatVel.X, vy, flatVel.Z)

		if slamQueued and now >= slamReadyAt then
			slamming = true
			slamStartedAt = now
			slamReadyAt = now + M.SlamCooldown
			vel = Vector3.new(vel.X * 0.4, -M.SlamSpeed, vel.Z * 0.4)
		end
	end

	jumpQueued = false
	slamQueued = false
	wasGrounded = grounded
	body.AssemblyLinearVelocity = vel

	if align then
		-- Point the nose along the travel direction (the camera's facing when nearly still), turning smoothly.
		local flat = Vector3.new(vel.X, 0, vel.Z)
		local targetYaw = flat.Magnitude > M.NoseMinSpeed and math.atan2(-flat.X, -flat.Z) or yaw
		local diff = (targetYaw - noseYaw + math.pi) % (2 * math.pi) - math.pi
		noseYaw = noseYaw + diff * math.min(1, M.NoseTurnRate * dt)
		align.CFrame = CFrame.Angles(0, noseYaw, 0) * CFrame.Angles(pitch, 0, 0)
	end

	readout.Text = string.format(
		"TILT %+.0f deg   SPEED %.0f\n%s\nATK %.1f DEF %.1f STA %.1f BAL %.1f",
		math.deg(pitch),
		Vector3.new(vel.X, 0, vel.Z).Magnitude,
		slamming and "SLAMMING" or (grounded and "GROUND" or "AIR"),
		body:GetAttribute("Attack") or 0,
		body:GetAttribute("Defense") or 0,
		body:GetAttribute("Stamina") or 0,
		body:GetAttribute("Balance") or 0
	)
end

RunService.Heartbeat:Connect(step)

----------------------------------------------------------------------- camera

RunService:BindToRenderStep("BeyCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	if not body or not body.Parent then
		return
	end

	local delta = UserInputService:GetMouseDelta()
	yaw = yaw - delta.X * M.MouseSensitivity
	pitch = math.clamp(pitch - delta.Y * M.MouseSensitivity, -MAX_TILT, MAX_TILT)

	local target = body.Position + Vector3.new(0, M.CameraHeight, 0)
	focus = focus and focus:Lerp(target, 1 - math.exp(-22 * dt)) or target
	-- Nose up lowers the camera so you look along the flight path; nose down lifts it.
	local camPitch = math.clamp(M.CameraBasePitch - pitch * 0.8, -0.3, 1.1)
	camera.CFrame = CFrame.new(focus)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(-camPitch, 0, 0)
		* CFrame.new(0, 0, M.CameraDistance)
end)

----------------------------------------------------------------------- binding

local function bind(newModel)
	model = newModel
	body = model:WaitForChild("Body")
	align = model:WaitForChild("Align")
	yaw, pitch = 0, 0
	noseYaw = 0
	focus = nil
	slamming = false
	wasGrounded = false
	camera.CameraSubject = body
end

local function tryBind(child)
	if child.Name == tostring(player.UserId) then
		bind(child)
	end
end

beysFolder.ChildAdded:Connect(tryBind)
for _, child in ipairs(beysFolder:GetChildren()) do
	tryBind(child)
end
]=====])
print('Spinforge installed (6 scripts). Press Play.')

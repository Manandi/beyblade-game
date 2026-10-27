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
	spirit_emberwolf = { Size = Vector3.new(0.5719, 1.0000, 2.2043), Tris = 5999 },
	spirit_tidedrake = { Size = Vector3.new(0.6419, 1.2000, 1.0911), Tris = 5999 },
	spirit_thornstag = { Size = Vector3.new(0.7323, 1.0000, 1.0304), Tris = 6000 },
	spirit_stormroc = { Size = Vector3.new(1.6000, 0.8406, 0.6871), Tris = 5999 },
	spirit_sunmane = { Size = Vector3.new(0.7237, 1.0000, 1.3857), Tris = 6000 },
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
print('Spinforge installer part 2 of 9 done. Now run part 3.')

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

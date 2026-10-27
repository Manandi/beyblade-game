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
print('Spinforge installer part 7 of 9 done. Now run part 8.')

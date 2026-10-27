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

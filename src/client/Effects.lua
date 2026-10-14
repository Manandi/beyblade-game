--!nonstrict
-- Effects: client-only visual feedback with hard caps (pooled parts, never more than MAX_* alive at once).
--   slamRing(pos, scale)    expanding ring where a slam lands
--   sparks(pos, color, n)   short burst for hits
--   shake(amount)           camera shake impulse (off when the player disables it)
-- Reduced effects (setting) skips sparks and shrinks rings; camera shake has its own setting.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Effects = {}
Effects.__index = Effects

local MAX_RINGS = 6
local MAX_SPARKS = 24

function Effects.new(getSettings)
	local self = setmetatable({}, Effects)
	self.getSettings = getSettings
	self.folder = Instance.new("Folder")
	self.folder.Name = "SpinforgeEffects"
	self.folder.Parent = Workspace
	self.rings, self.sparkParts = {}, {}
	self.active = 0
	self.shakeAmount = 0
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

function Effects:_play(p, goal, time)
	self.active += 1
	local tween = TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween.Completed:Connect(function()
		p.Transparency = 1
		p:SetAttribute("Busy", false)
		self.active -= 1
	end)
	tween:Play()
end

function Effects:slamRing(pos, scale, color)
	local s = self.getSettings()
	local p = take(self.rings, MAX_RINGS, self.folder, Enum.PartType.Cylinder)
	if not p then
		return
	end
	local r = (s.ReducedEffects and 10 or 18) * math.clamp(scale or 1, 0.3, 1.5)
	p.Color = color or Color3.fromRGB(255, 120, 60)
	p.Size = Vector3.new(0.4, 2, 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Transparency = 0.2
	self:_play(p, { Size = Vector3.new(0.4, r * 2, r * 2), Transparency = 1 }, 0.35)
end

function Effects:sparks(pos, color, n)
	local s = self.getSettings()
	if s.ReducedEffects then
		return
	end
	for _ = 1, math.min(n or 6, 8) do
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
		self:_play(p, { CFrame = CFrame.new(pos + dir * (3 + math.random() * 3)), Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 }, 0.3)
	end
end

function Effects:shake(amount)
	if self.getSettings().CameraShake then
		self.shakeAmount = math.min(self.shakeAmount + amount, 1.2)
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

function Effects:count()
	return self.active
end

return Effects

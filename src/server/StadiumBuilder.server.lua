--!nonstrict
-- Builds the round test stadium if the place has none: a bowl with a flat centre and walls that get steeper toward
-- the rim. The steep last ring is the launch ramp: ride up the wall nose-up to fly, then slam back down.
-- An invisible fence above the rim stops launches from leaving the stadium (ring-outs can come later).
-- Replace this with a hand-built map in Studio later; name your map "Stadium" and this script does nothing.
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BeyConfig = require(ReplicatedStorage:WaitForChild("BeyConfig"))
Workspace.Gravity = BeyConfig.Movement.Gravity

if Workspace:FindFirstChild("Stadium") then
	return
end

local SEGMENTS = 48 -- slabs per ring; more = smoother wall
local FLOOR_RADIUS = 14
-- { outer radius, slope in degrees, colour } going outward from the flat floor
local RINGS = {
	{ 24, 12, Color3.fromRGB(46, 56, 84) },
	{ 33, 26, Color3.fromRGB(40, 70, 120) },
	{ 39, 45, Color3.fromRGB(34, 96, 160) },
	{ 42, 72, Color3.fromRGB(30, 130, 200) }, -- the lip: steep enough to throw you up
}
local FENCE_HEIGHT = 60

local stadium = Instance.new("Folder")
stadium.Name = "Stadium"
stadium.Parent = Workspace
local barrier = Instance.new("Folder")
barrier.Name = "Barrier" -- invisible; the camera ignores it
barrier.Parent = stadium

local function block(name, size, cframe, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or stadium
	return p
end

-- Ground outside the stadium (top at y = 1).
block("Ground", Vector3.new(400, 2, 400), CFrame.new(0, 0, 0), Color3.fromRGB(70, 74, 86))

-- Flat centre floor, a touch above the ground so they don't flicker.
block(
	"Floor",
	Vector3.new(1, FLOOR_RADIUS * 2 + 0.6, FLOOR_RADIUS * 2 + 0.6),
	CFrame.new(0, 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color3.fromRGB(38, 42, 62)
).Shape = Enum.PartType.Cylinder

-- Centre marking.
local mark = block("CentreMark", Vector3.new(0.1, 6, 6), CFrame.new(0, 1.06, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 200, 255), Enum.Material.Neon)
mark.Shape = Enum.PartType.Cylinder
mark.CanCollide = false

-- Sloped rings: each is SEGMENTS slabs whose top surface rises from the ring's inner edge to its outer edge.
local height = 1.02 -- top of the floor
local inner = FLOOR_RADIUS
for ringIndex, ring in ipairs(RINGS) do
	local outer, slope, color = ring[1], math.rad(ring[2]), ring[3]
	local run = outer - inner
	local rise = run * math.tan(slope)
	local length = run / math.cos(slope) + 0.4 -- a little overlap with the next ring
	local width = 2 * outer * math.tan(math.pi / SEGMENTS) + 0.25 -- wide enough to close the gaps at the outer edge
	local midRadius = (inner + outer) / 2
	for i = 0, SEGMENTS - 1 do
		local angle = i * 2 * math.pi / SEGMENTS
		local cf = CFrame.new(0, height + rise / 2, 0)
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, 0, -midRadius) -- out along this segment's direction
			* CFrame.Angles(slope, 0, 0) -- tilt so the outer end is higher
			* CFrame.new(0, -0.5, 0) -- the top face is the riding surface
		block("Ring" .. ringIndex, Vector3.new(width, 1, length), cf, color)
	end
	height = height + rise
	inner = outer
end
local rimHeight = height

-- Outer skirt (looks), glowing rim, and the invisible fence above it.
for i = 0, SEGMENTS - 1 do
	local angle = i * 2 * math.pi / SEGMENTS
	local width = 2 * (inner + 1) * math.tan(math.pi / SEGMENTS) + 0.3
	local base = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -(inner + 0.6))
	block("Skirt", Vector3.new(width, rimHeight, 1.2), CFrame.new(0, rimHeight / 2, 0) * base, Color3.fromRGB(24, 28, 40))
	block("Rim", Vector3.new(width, 0.5, 1.4), CFrame.new(0, rimHeight + 0.25, 0) * base, Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
	local fence = block("Fence", Vector3.new(width, FENCE_HEIGHT, 1), CFrame.new(0, rimHeight + FENCE_HEIGHT / 2, 0) * base, Color3.new(1, 1, 1), nil, barrier)
	fence.Transparency = 1
end

-- Target dummies on the floor: unanchored discs the slam can knock around.
local function dummy(x, z)
	local p = Instance.new("Part")
	p.Name = "Dummy"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(2, 6, 6)
	p.CFrame = CFrame.new(x, 4, z) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = Color3.fromRGB(220, 70, 70)
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = stadium
	CollectionService:AddTag(p, "BeyTarget")
end
dummy(9, 0)
dummy(-5, 8)
dummy(-5, -8)

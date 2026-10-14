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

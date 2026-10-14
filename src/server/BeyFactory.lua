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

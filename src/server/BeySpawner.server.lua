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

-- Studio's 3D importer puts imported models in Workspace. Move any bey meshes found there into
-- ReplicatedStorage.BeyMeshes, where BeyVisuals looks for them (and so they don't litter the stadium).
do
	local BeyMeshData = require(ReplicatedStorage:WaitForChild("BeyMeshData"))
	local meshFolder = ReplicatedStorage:FindFirstChild("BeyMeshes")
	if not meshFolder then
		meshFolder = Instance.new("Folder")
		meshFolder.Name = "BeyMeshes"
		meshFolder.Parent = ReplicatedStorage
	end
	local imported = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("MeshPart") and BeyMeshData[d.Name] then
			local top = d
			while top.Parent and top.Parent ~= Workspace do
				top = top.Parent
			end
			imported[top] = true
		end
	end
	local count = 0
	for top in pairs(imported) do
		top.Parent = meshFolder
		count = count + 1
	end
	if count > 0 then
		print(("Spinforge: moved %d imported bey mesh model(s) from Workspace into ReplicatedStorage.BeyMeshes"):format(count))
	end
end

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
		root.CFrame = CFrame.new(0, 4, 70) -- outside the stadium
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

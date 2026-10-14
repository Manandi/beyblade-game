--!nonstrict
-- BeyService: puts a player into "bey mode" and back out, safely, whatever happens.
-- Player attribute "Mode": "OnFoot" | "Practice" | "Battle". The client controller binds to the player's bey when
-- it appears in Workspace.Beys and restores the normal camera when it is removed.
-- Entering bey mode parks the avatar (anchored, controls off) at World.PARK; leaving always restores it:
-- after a battle, on reset/death, on leaving practice, or if the player leaves the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local GameConfig = require(Shared.GameConfig)
local CombatCore = require(Shared.Core.CombatCore)

local BeyFactory = require(script.Parent.BeyFactory)
local World = require(script.Parent.World)

local BeyService = {}

local C = GameConfig.Combat
local beysFolder
local beys = {} -- player -> bey record (see BeyFactory) + { fall = fall tracker }
local saved = {} -- player -> { walk, jumpHeight, jumpPower }
local DataService
local remotes
local slamLimiter = CombatCore.newRateLimiter(C.RequestsPerSecond)
local lastSlam = {}

function BeyService.folder()
	return beysFolder
end

function BeyService.get(player)
	return beys[player]
end

local function humanoidAndRoot(player)
	local char = player.Character
	if not char then
		return nil, nil
	end
	return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function parkAvatar(player)
	local hum, root = humanoidAndRoot(player)
	if hum and not saved[player] then
		saved[player] = { walk = hum.WalkSpeed, jumpHeight = hum.JumpHeight, jumpPower = hum.JumpPower }
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
		hum.JumpPower = 0
	end
	if root then
		root.Anchored = true
		root.CFrame = CFrame.new(World.PARK + Vector3.new(math.random(-8, 8), 0, 0))
	end
end

local function restoreAvatar(player)
	local hum, root = humanoidAndRoot(player)
	local s = saved[player]
	saved[player] = nil
	if hum then
		hum.WalkSpeed = (s and s.walk and s.walk > 0) and s.walk or 16
		hum.JumpHeight = (s and s.jumpHeight and s.jumpHeight > 0) and s.jumpHeight or 7.2
		hum.JumpPower = (s and s.jumpPower and s.jumpPower > 0) and s.jumpPower or 50
	end
	if root then
		root.Anchored = false
		root.CFrame = CFrame.new(World.SPAWN + Vector3.new(math.random(-4, 4), 0, math.random(-2, 2)))
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Spawns the player's bey at `cframe` and switches them to `mode`. anchored = frozen (battle countdown).
-- center: the stadium centre (the client uses it to recover a stuck bey; practice resets go to BeySpawn).
function BeyService.enter(player, mode, cframe, anchored, center)
	BeyService.removeBey(player)
	local data = DataService.get(player)
	if not data then
		return nil
	end
	parkAvatar(player)
	local rec = BeyFactory.build({
		name = tostring(player.UserId),
		partIds = data.Equipped,
		level = DataService.levelOf(player),
		cframe = cframe,
		parent = beysFolder,
	})
	rec.fall = CombatCore.newFallTracker()
	beys[player] = rec
	if anchored then
		rec.body.Anchored = true
	else
		rec.body:SetNetworkOwner(player)
	end
	player:SetAttribute("BeySpawn", cframe.Position)
	player:SetAttribute("ArenaCenter", center)
	player:SetAttribute("Mode", mode)
	return rec
end

-- Unfreezes a bey after a countdown and hands physics back to its player.
function BeyService.release(player)
	local rec = beys[player]
	if rec and rec.body.Parent then
		rec.body.Anchored = false
		rec.body:SetNetworkOwner(player)
	end
end

function BeyService.removeBey(player)
	local rec = beys[player]
	beys[player] = nil
	if rec and rec.model then
		rec.model:Destroy()
	end
end

-- Back to walking around, from any state.
function BeyService.exit(player)
	BeyService.removeBey(player)
	if player.Parent then
		player:SetAttribute("Mode", "OnFoot")
		restoreAvatar(player)
	end
end

function BeyService.mode(player)
	return player:GetAttribute("Mode") or "OnFoot"
end

-- Records the downward speed the server sees for every bey (slam claims are checked against this).
local function trackFalls()
	local now = os.clock()
	for _, rec in pairs(beys) do
		if rec.body.Parent then
			CombatCore.recordFall(rec.fall, rec.body.AssemblyLinearVelocity.Y, now, C.SlamFallWindow)
		end
	end
end

-- Practice slams knock the training dummies about (battle slams are handled by BattleService).
local function practiceSlam(player)
	local rec = beys[player]
	if not rec then
		return
	end
	local now = os.clock()
	local fall = CombatCore.maxFall(rec.fall, now, C.SlamFallWindow)
	if fall < C.SlamMinFallSpeed then
		return
	end
	local pos = rec.body.Position
	for _, dummy in ipairs(CollectionService:GetTagged("SpinforgeDummy")) do
		local offset = dummy.Position - pos
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= C.SlamRadius + 3 and math.abs(offset.Y) < 10 then
			local dir = (flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)) + Vector3.new(0, 0.5, 0)
			dummy:ApplyImpulse(dir.Unit * C.SlamKnockback * 3 * dummy.AssemblyMass * math.clamp(fall / 100, 0.5, 1.5))
		end
	end
	remotes.BattleEvent:FireClient(player, { kind = "slam", hit = true })
end

-- Called by BattleService for slams in battle; returns the validated fall speed or nil.
function BeyService.validateSlam(player)
	local rec = beys[player]
	if not rec or not rec.body.Parent then
		return nil
	end
	local now = os.clock()
	if not CombatCore.allow(slamLimiter, player, now) then
		return nil
	end
	if lastSlam[player] and now - lastSlam[player] < C.SlamCooldown then
		return nil
	end
	local fall = CombatCore.maxFall(rec.fall, now, C.SlamFallWindow)
	if fall < C.SlamMinFallSpeed then
		return nil
	end
	lastSlam[player] = now
	return fall
end

local function resetDummies()
	for _, dummy in ipairs(CollectionService:GetTagged("SpinforgeDummy")) do
		local home = dummy:GetAttribute("Home")
		if home and (dummy.Position - home).Magnitude > 60 then
			dummy.AssemblyLinearVelocity = Vector3.zero
			dummy.CFrame = CFrame.new(home) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

function BeyService.startPractice(player)
	if BeyService.mode(player) ~= "OnFoot" then
		return
	end
	local spawnAt = CFrame.new(World.TRAINING_CENTER + Vector3.new(0, 5, 8))
	BeyService.enter(player, "Practice", spawnAt, false, World.TRAINING_CENTER)
	resetDummies()
end

function BeyService.start(r, dataService, onSlam)
	remotes = r
	DataService = dataService
	beysFolder = Workspace:FindFirstChild("Beys")
	if not beysFolder then
		beysFolder = Instance.new("Folder")
		beysFolder.Name = "Beys"
		beysFolder.Parent = Workspace
	end
	game:GetService("RunService").Heartbeat:Connect(trackFalls)

	remotes.SlamLanded.OnServerEvent:Connect(function(player)
		local mode = BeyService.mode(player)
		if mode == "Practice" then
			if BeyService.validateSlam(player) then
				practiceSlam(player)
			end
		elseif mode == "Battle" then
			onSlam(player)
		end
	end)

	-- A character that appears outside the hub (e.g. at a template SpawnLocation inside a stadium) is moved to
	-- the hub spawn, so nobody starts trapped in a bowl.
	local function toHubIfLost(player)
		task.defer(function()
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and BeyService.mode(player) == "OnFoot" and not root.Anchored then
				local flat = Vector3.new(root.Position.X - World.HUB_CENTER.X, 0, root.Position.Z - World.HUB_CENTER.Z)
				if flat.Magnitude > 60 then
					root.CFrame = CFrame.new(World.SPAWN)
				end
			end
		end)
	end
	BeyService.toHubIfLost = toHubIfLost

	local function hookCharacter(player)
		if player.Character then
			World.tagCharacter(player.Character)
		end
		player.CharacterAdded:Connect(function(char)
			World.tagCharacter(char)
			-- A reset or respawn while in bey mode: end it cleanly (BattleService treats it as leaving).
			if BeyService.mode(player) ~= "OnFoot" then
				BeyService.onInterrupted(player)
			end
			toHubIfLost(player)
		end)
		toHubIfLost(player)
	end
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Mode", "OnFoot")
		hookCharacter(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Mode", player:GetAttribute("Mode") or "OnFoot")
		hookCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		BeyService.removeBey(player)
		saved[player] = nil
		lastSlam[player] = nil
		CombatCore.forget(slamLimiter, player)
	end)
end

-- Overridden by Main so BattleService can react (forfeit); default just exits.
function BeyService.onInterrupted(player)
	BeyService.exit(player)
end

return BeyService

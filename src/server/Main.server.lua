--!nonstrict
-- Spinforge server entry point. Starts everything in a fixed order and prints a startup report to Output.
-- If something required is missing, it stops with a message saying what to do instead of failing silently.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local REQUIRED_SHARED = { "BeyConfig", "BeyDesigns", "BeyMeshData", "BeyVisuals", "GameConfig", "Net", "Core" }
local Shared = ReplicatedStorage:FindFirstChild("Spinforge")
if not Shared then
	error("Spinforge: ReplicatedStorage.Spinforge is missing. Run install_in_studio.lua again (Command Bar).")
end
local missing = {}
for _, name in ipairs(REQUIRED_SHARED) do
	if not Shared:FindFirstChild(name) then
		table.insert(missing, name)
	end
end
if #missing > 0 then
	error("Spinforge: missing shared modules: " .. table.concat(missing, ", ") .. ". Run install_in_studio.lua again.")
end

local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local Net = require(Shared.Net)
local Progression = require(Shared.Core.Progression)

local World = require(script.Parent.World)
local MeshImport = require(script.Parent.MeshImport)
local DataService = require(script.Parent.DataService)
local BeyService = require(script.Parent.BeyService)
local BattleService = require(script.Parent.BattleService)

Workspace.Gravity = BeyConfig.Movement.Gravity
local remotes = Net.setup(ReplicatedStorage)
World.removeLegacy()
local world = World.build(GameConfig.Villain.Name)
World.polishLighting()
local meshes, moved = MeshImport.collect()

DataService.start(remotes)
BeyService.start(remotes, DataService, BattleService.onSlam)
BeyService.onInterrupted = BattleService.onInterrupted
BattleService.start(remotes)

-- Hub prompts.
local function onFootAndReady(player)
	return BeyService.mode(player) == "OnFoot" and DataService.isReady(player)
end
if world.prompts.challenge then
	world.prompts.challenge.Triggered:Connect(function(player)
		if onFootAndReady(player) then
			BattleService.challenge(player)
		end
	end)
end
if world.prompts.practice then
	world.prompts.practice.Triggered:Connect(function(player)
		if onFootAndReady(player) then
			BeyService.startPractice(player)
		end
	end)
end
if world.prompts.workshop then
	world.prompts.workshop.Triggered:Connect(function(player)
		remotes.BattleEvent:FireClient(player, { kind = "openWorkshop" })
	end)
end

-- Workshop: buy and equip parts, spirits and specials, validated on the server. Only allowed on foot.
remotes.Workshop.OnServerInvoke = function(player, req)
	local data = DataService.get(player)
	local function reply(ok, reason)
		return {
			ok = ok,
			reason = reason and (Progression.ReasonText[reason] or reason) or nil,
			profile = DataService.snapshot(player),
		}
	end
	if not data then
		return reply(false, "Your profile is still loading.")
	end
	if type(req) ~= "table" or type(req.action) ~= "string" or type(req.part) ~= "string" then
		return reply(false, "invalid")
	end
	local mode = BeyService.mode(player)
	if mode == "Practice" then
		return reply(false, "Leave practice to change parts.")
	end
	local inBattle = mode ~= "OnFoot"
	local ok, reason
	if req.action == "buy" then
		ok, reason = Progression.buy(data, req.part, BeyConfig.Items, GameConfig.Progression, inBattle)
	elseif req.action == "equip" then
		local slot = (req.slot == "Special1" or req.slot == "Special2") and req.slot or nil
		ok, reason = Progression.equip(data, req.part, BeyConfig.Items, inBattle, slot)
	else
		return reply(false, "invalid")
	end
	if ok then
		DataService.markDirty(player)
		DataService.sendProfile(player)
		return reply(true, nil)
	end
	return reply(false, reason)
end

-- Other requests: settings, tutorial, leaving practice. (Battle requests are handled in BattleService.)
local SETTINGS = { CameraShake = true, ReducedEffects = true }
remotes.Request.OnServerEvent:Connect(function(player, req)
	if type(req) ~= "table" or type(req.action) ~= "string" then
		return
	end
	local data = DataService.get(player)
	if req.action == "setting" and data and SETTINGS[req.key] and type(req.value) == "boolean" then
		data.Settings[req.key] = req.value
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "tutorialDone" and data and not data.Settings.TutorialDone then
		data.Settings.TutorialDone = true
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "tutorialReset" and data then
		data.Settings.TutorialDone = false
		DataService.markDirty(player)
		DataService.sendProfile(player)
	elseif req.action == "exitPractice" and BeyService.mode(player) == "Practice" then
		BeyService.exit(player)
	end
end)

print(("Spinforge server ready: world %s, %d of %d bey meshes available%s, crates disabled (paid purchases off)."):format(
	world.built and "built" or "found (custom SpinforgeWorld)",
	meshes,
	66,
	moved > 0 and (" (moved " .. moved .. " imported model(s) from Workspace)") or ""
))

--!nonstrict
-- Spinforge client entry point. Builds the HUD first (so problems can be shown on screen), waits a bounded time
-- for the server's remotes, then starts the menus, tutorial, effects and bey controller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Hud = require(script.Parent.Hud)
local hud = Hud.new(player)

local Shared = ReplicatedStorage:WaitForChild("Spinforge", 20)
if not Shared then
	hud:showError("ReplicatedStorage.Spinforge is missing. Run install_in_studio.lua again.")
	return
end
local Net = require(Shared.Net)
local remotes, err = Net.waitFor(ReplicatedStorage, 20)
if not remotes then
	hud:showError(err)
	return
end

local Effects = require(script.Parent.Effects)
local Menus = require(script.Parent.Menus)
local Tutorial = require(script.Parent.Tutorial)
local Controller = require(script.Parent.Controller)
local LaunchCore = require(Shared.Core.LaunchCore)
local GameConfig = require(Shared.GameConfig)

local profile = nil
local function settings()
	return profile and profile.Settings or { CameraShake = true, ReducedEffects = false, TutorialDone = true }
end

local effects = Effects.new(settings)
local menus = Menus.new(hud, remotes)
local tutorial = Tutorial.new(hud, remotes)
Controller.start({ remotes = remotes, hud = hud, effects = effects, tutorial = tutorial })
require(script.Parent.OnFootFallback).start({ hud = hud, isBound = function()
	return Controller.isBound()
end })

remotes.Profile.OnClientEvent:Connect(function(p)
	if type(p) ~= "table" then
		return
	end
	profile = p
	hud:setProfile(p)
	menus:setProfile(p)
	tutorial:setProfile(p)
end)
hud:setProfile({ Level = 1, XP = 0, Shards = 0, Record = { Wins = 0, Losses = 0, Draws = 0 }, SaveStatus = "loading" })

remotes.Toast.OnClientEvent:Connect(function(text)
	if type(text) == "string" then
		hud:toast(text)
	end
end)

-- Mode changes (set by the server): HUD layout and the mode button (Forfeit / Back to hub).
local function onMode()
	local m = player:GetAttribute("Mode") or "OnFoot"
	hud:setMode(m, nil)
	if m ~= "OnFoot" then
		menus:close()
		menus:closeSettings()
	end
end
player:GetAttributeChangedSignal("Mode"):Connect(onMode)
onMode()
hud.modeBtn.Activated:Connect(function()
	local m = player:GetAttribute("Mode")
	if m == "Practice" then
		remotes.Request:FireServer({ action = "exitPractice" })
	elseif m == "Battle" and (player:GetAttribute("BattleState") == "active" or player:GetAttribute("BattleState") == "countdown") then
		remotes.Request:FireServer({ action = "forfeit" })
	end
end)

-- Battle events.
local inBattle = false
remotes.BattleEvent.OnClientEvent:Connect(function(e)
	if type(e) ~= "table" then
		return
	end
	if e.kind == "queued" then
		hud:queued(e.position)
	elseif e.kind == "countdown" then
		inBattle = true
		hud:closeBattle()
		hud:countdown(e.seconds or 3, e.foe, e.difficulty)
		if type(e.meter) == "table" then
			hud:showLaunch(e.meter)
		end
	elseif e.kind == "launchLocked" then
		-- the server's verdict (normally the same as what we showed)
		hud:lockLaunch(nil, e.label or "WEAK")
	elseif e.kind == "started" then
		hud:started(e.launch, e.foeLaunch)
		if type(e.launch) == "table" then
			Controller.launch(e.launch.speed, e.launch.boost)
		end
	elseif e.kind == "hit" then
		if (e.taken or 0) > 0.5 then
			hud:popup(("-%d"):format(math.floor(e.taken + 0.5)), Color3.fromRGB(255, 110, 110), false)
			hud:flash(Color3.fromRGB(255, 60, 60), e.strength or 0.5)
		end
		if (e.dealt or 0) > 0.5 then
			hud:popup(("-%d"):format(math.floor(e.dealt + 0.5)), Color3.fromRGB(255, 255, 255), true)
		end
		if typeof(e.at) == "Vector3" then
			effects:sparks(e.at, Color3.fromRGB(255, 230, 150), 6)
		end
		effects:shake(0.35 * (e.strength or 0.5))
	elseif e.kind == "slam" then
		if e.hit then
			hud:toast((e.dealt and e.dealt > 0) and ("SLAM! -%d"):format(math.floor(e.dealt + 0.5)) or "SLAM!", Color3.fromRGB(255, 200, 120))
		end
	elseif e.kind == "villainSlam" then
		if typeof(e.at) == "Vector3" then
			effects:slamRing(e.at - Vector3.new(0, 1.8, 0), 1, Color3.fromRGB(255, 80, 80))
		end
	elseif e.kind == "finished" then
		hud:showResult(e, function()
			remotes.Request:FireServer({ action = "rematch" })
		end, function()
			remotes.Request:FireServer({ action = "leave" })
		end)
	elseif e.kind == "closed" then
		inBattle = false
		hud:closeBattle()
	elseif e.kind == "openWorkshop" then
		menus:open()
	end
end)

-- Launch meter: the needle runs on the shared server clock; one press locks it and tells the server when.
local function pressLaunch()
	local meter = hud.launchMeter
	if not meter or hud.launchLocked then
		return
	end
	local t = Workspace:GetServerTimeNow()
	local pos = LaunchCore.needle(meter, t)
	local _, label = LaunchCore.quality(meter, pos, GameConfig.Launch)
	hud:lockLaunch(pos, label)
	remotes.Request:FireServer({ action = "launch", t = t })
end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not hud.launchMeter then
		return
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.Space or kc == Enum.KeyCode.ButtonA or kc == Enum.KeyCode.ButtonR2 or input.UserInputType == Enum.UserInputType.MouseButton1 then
		pressLaunch()
	end
end)
hud.touchLaunch.Activated:Connect(pressLaunch)
RunService.RenderStepped:Connect(function()
	local meter = hud.launchMeter
	if meter and not hud.launchLocked then
		hud:setNeedle(LaunchCore.needle(meter, Workspace:GetServerTimeNow()))
	end
end)

-- Live battle bars from the beys' Spin attributes (set by the server).
local beys = Workspace:WaitForChild("Beys", 30)
RunService.RenderStepped:Connect(function()
	if not inBattle or not beys then
		return
	end
	local mine = beys:FindFirstChild(tostring(player.UserId))
	local foe
	for _, m in ipairs(beys:GetChildren()) do
		if m:GetAttribute("Villain") then
			foe = m
			break
		end
	end
	local mb = mine and mine:FindFirstChild("Body")
	local fb = foe and foe:FindFirstChild("Body")
	if mb and fb then
		hud:updateBattle(mb:GetAttribute("Spin") or 0, mb:GetAttribute("MaxSpin") or 1, fb:GetAttribute("Spin") or 0, fb:GetAttribute("MaxSpin") or 1, player:GetAttribute("BattleEndsAt"), player:GetAttribute("BattleState"))
	end
end)

-- F6: diagnostics.
local diagOn = false
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F6 then
		diagOn = not diagOn
		if not diagOn then
			hud:setDiag(nil)
		end
	end
end)
local frames, fps, fpsAt = 0, 0, os.clock()
RunService.RenderStepped:Connect(function()
	frames += 1
	local now = os.clock()
	if now - fpsAt >= 0.5 then
		fps = frames / (now - fpsAt)
		frames, fpsAt = 0, now
		if diagOn then
			local beyCount = beys and #beys:GetChildren() or 0
			hud:setDiag(("FPS %.0f\nmode %s  battle %s\nbeys in world %d  effects active %d\nsave %s\n%s"):format(
				fps,
				tostring(player:GetAttribute("Mode")),
				tostring(player:GetAttribute("BattleState") or "-"),
				beyCount,
				effects:count(),
				profile and profile.SaveStatus or "loading",
				Controller.diag()
			))
		end
	end
end)

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
install('SPS', '', 'ModuleScript', 'Controller', [=====[
--!nonstrict
-- Controller: drives the local player's bey with MovementCore and runs the bey camera.
--   Binds when the player's bey appears in Workspace.Beys (named by UserId); unbinds when it's removed and then
--   ALWAYS restores the normal camera and mouse, so the avatar is playable after a battle, reset or interruption.
--   Physics for the player's bey is client-owned (see HANDOFF.md): this script writes its velocity each frame.
--
-- Input (all platforms):
--   move      WASD / left stick / touch stick (Roblox control module if present, else our own reader)
--   tilt      mouse / right stick / drag on the right half of the screen   (down = lean in, up = brake)
--   jump      Space / gamepad A / JUMP button          slam   click / right trigger / SLAM button (in the air)
--   practice  R or gamepad Y = reset bey, Q or gamepad B = back to the hub
--   camera    V or gamepad D-pad up = switch between the bey camera and the overhead stadium view
--             (overhead: W is always "up the screen", the mouse only tilts)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local MC = require(Shared.Core.MovementCore)
local LaunchCore = require(Shared.Core.LaunchCore)

local M = BeyConfig.Movement
local MAX_TILT = math.rad(M.MaxTiltDeg)
local BASE_FOV = 70
local OVERHEAD = { Height = 58, Back = 34, Follow = 0.35, Blend = 6 } -- overhead view: how high, how far back, how much it follows your bey

local Controller = {}

function Controller.start(ctx)
	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera
	local remotes, hud, effects, tutorial = ctx.remotes, ctx.hud, ctx.effects, ctx.tutorial
	local beysFolder = Workspace:WaitForChild("Beys", 30)
	if not beysFolder then
		hud:showError("Workspace.Beys never appeared: the server scripts did not start. Check Output for red errors.")
		return
	end

	-- state ------------------------------------------------------------------------------------------------
	local model, body, align
	local yaw, pitch, noseYaw = 0, 0, 0
	local up = Vector3.yAxis
	local ground, actions, stuck = MC.newGround(), MC.newActions(), MC.newStuck()
	local jumpQueued, slamQueued = false, false
	local pendingKnockback = Vector3.zero
	local pendingLaunch = nil -- { speed, boost } from the server's "started" event
	local pendingDash = nil -- { speed, dir } from a dash special
	local launchBoost, launchAt = 0, -math.huge
	local focus
	local movedFor, fastAt = 0, -math.huge
	local flipsAt, flipsRate, lastFlips = os.clock(), 0, 0
	local camMode = player:GetAttribute("CameraMode") == "Overhead" and "Overhead" or "Bey"
	local overheadYaw = 0
	local overheadBlend = camMode == "Overhead" and 1 or 0
	local speedMul = 1 -- spirit passive / awakening, from the server's snapshots
	local cine = { untilT = 0, zoom = 1, len = 1 } -- short zoom-in when you use a special
	local zoomNow = 1
	local lastCam

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local cameraParams = RaycastParams.new()
	cameraParams.FilterType = Enum.RaycastFilterType.Exclude
	local function refreshFilters()
		local ignore = { beysFolder }
		if player.Character then
			table.insert(ignore, player.Character)
		end
		local fx = Workspace:FindFirstChild("SpinforgeEffects")
		if fx then
			table.insert(ignore, fx)
		end
		rayParams.FilterDescendantsInstances = ignore
		local camIgnore = table.clone(ignore)
		local worldRoot = Workspace:FindFirstChild("SpinforgeWorld")
		if worldRoot then
			for _, f in ipairs(worldRoot:GetDescendants()) do
				if f.Name == "Barrier" and f:IsA("Folder") then
					table.insert(camIgnore, f)
				end
			end
		end
		cameraParams.FilterDescendantsInstances = camIgnore
	end
	refreshFilters()
	player.CharacterAdded:Connect(refreshFilters)

	-- move input: Roblox's control module if it loads, otherwise our own reader --------------------------------
	local controls = nil
	task.spawn(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if module then
			local ok, result = pcall(function()
				return require(module):GetControls()
			end)
			if ok then
				controls = result
			end
		end
	end)

	local touchStick = { input = nil, origin = Vector2.zero, vec = Vector2.zero }
	local function clearInputs()
		jumpQueued, slamQueued = false, false
		touchStick.input = nil
		touchStick.vec = Vector2.zero
	end
	UserInputService.WindowFocusReleased:Connect(clearInputs)

	UserInputService.TouchStarted:Connect(function(touch, processed)
		if processed or not body or touchStick.input or touch.Position.X > camera.ViewportSize.X * 0.5 then
			return
		end
		touchStick.input = touch
		touchStick.origin = Vector2.new(touch.Position.X, touch.Position.Y)
	end)
	UserInputService.TouchMoved:Connect(function(touch)
		if touch == touchStick.input then
			local d = (Vector2.new(touch.Position.X, touch.Position.Y) - touchStick.origin) / 60
			touchStick.vec = d.Magnitude > 1 and d.Unit or d
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch)
		if touch == touchStick.input then
			touchStick.input = nil
			touchStick.vec = Vector2.zero
		end
	end)

	local function moveVector() -- x = right, z = back
		if UserInputService:GetFocusedTextBox() or hud:mouseFree() then
			return Vector3.zero
		end
		if controls then
			local ok, v = pcall(function()
				return controls:GetMoveVector()
			end)
			if ok and v and v.Magnitude > 0 then
				return v
			end
		end
		local K = Enum.KeyCode
		local x = (UserInputService:IsKeyDown(K.D) and 1 or 0) - (UserInputService:IsKeyDown(K.A) and 1 or 0)
		local z = (UserInputService:IsKeyDown(K.S) and 1 or 0) - (UserInputService:IsKeyDown(K.W) and 1 or 0)
		for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 and state.Position.Magnitude > 0.15 then
				x += state.Position.X
				z -= state.Position.Y
			end
		end
		x += touchStick.vec.X
		z += touchStick.vec.Y
		local v = Vector3.new(x, 0, z)
		return v.Magnitude > 1 and v.Unit or v
	end

	local function mode()
		return player:GetAttribute("Mode") or "OnFoot"
	end

	local function resetBey()
		if not body or body.Anchored then
			return
		end
		local at = player:GetAttribute("BeySpawn")
		if typeof(at) == "Vector3" then
			body.AssemblyLinearVelocity = Vector3.zero
			body.CFrame = CFrame.new(at)
		end
		ground, actions, stuck = MC.newGround(), MC.newActions(), MC.newStuck()
	end

	UserInputService.JumpRequest:Connect(function()
		if body then
			jumpQueued = true
		end
	end)
	hud.touchJump.Activated:Connect(function()
		jumpQueued = true
	end)
	hud.touchSlam.Activated:Connect(function()
		slamQueued = true
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not body or UserInputService:GetFocusedTextBox() then
			return
		end
		local kc = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not hud:mouseFree() then
			slamQueued = true
		elseif kc == Enum.KeyCode.ButtonR2 then
			slamQueued = true
		elseif kc == Enum.KeyCode.Space or kc == Enum.KeyCode.ButtonA then
			jumpQueued = true
		elseif kc == Enum.KeyCode.V or kc == Enum.KeyCode.DPadUp then
			camMode = camMode == "Overhead" and "Bey" or "Overhead"
			player:SetAttribute("CameraMode", camMode)
			if camMode == "Overhead" then
				overheadYaw = yaw
			end
			hud:toast(camMode == "Overhead" and "Overhead view  (V to switch back)" or "Bey view  (V for overhead)")
		elseif (kc == Enum.KeyCode.R or kc == Enum.KeyCode.ButtonY) and mode() == "Practice" then
			resetBey()
		elseif (kc == Enum.KeyCode.Q or kc == Enum.KeyCode.ButtonB) and mode() == "Practice" then
			remotes.Request:FireServer({ action = "exitPractice" })
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if not body or processed or input.UserInputType ~= Enum.UserInputType.Touch or input == touchStick.input then
			return
		end
		yaw -= input.Delta.X * M.TouchSensitivity
		pitch = math.clamp(pitch - input.Delta.Y * M.TouchSensitivity, -MAX_TILT, MAX_TILT)
	end)

	remotes.Knockback.OnClientEvent:Connect(function(v)
		if body and typeof(v) == "Vector3" and MC.finiteVector(v) then
			pendingKnockback = MC.clampMagnitude(pendingKnockback + v, 200)
			effects:shake(math.clamp(v.Magnitude / 80, 0.2, 1))
		end
	end)

	-- bind / unbind -----------------------------------------------------------------------------------------------
	local function unbind()
		model, body, align = nil, nil, nil
		clearInputs()
		pendingKnockback = Vector3.zero
		hud:showTouchButtons(false)
		tutorial:setActive(false)
		-- Always give the normal camera and mouse back.
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = BASE_FOV
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end

	local function bind(newModel)
		local b = newModel:WaitForChild("Body", 5)
		local a = newModel:WaitForChild("Align", 5)
		if not (b and a) or newModel.Parent ~= beysFolder then
			warn("Spinforge: bey model incomplete; not controlling it")
			return
		end
		model, body, align = newModel, b, a
		ground, actions, stuck = MC.newGround(), MC.newActions(), MC.newStuck()
		clearInputs()
		pendingKnockback = Vector3.zero
		pendingLaunch, launchBoost, launchAt = nil, 0, -math.huge
		speedMul, pendingDash = 1, nil
		local look = body.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		noseYaw, pitch, up, focus = yaw, 0, Vector3.yAxis, nil
		overheadYaw = yaw
		camera.CameraSubject = body
		hud:showTouchButtons(true)
		tutorial:setActive(true)
		refreshFilters()
	end

	beysFolder.ChildAdded:Connect(function(child)
		if child.Name == tostring(player.UserId) then
			bind(child)
		end
	end)
	beysFolder.ChildRemoved:Connect(function(child)
		if child == model then
			unbind()
		end
	end)
	for _, child in ipairs(beysFolder:GetChildren()) do
		if child.Name == tostring(player.UserId) then
			task.spawn(bind, child)
		end
	end

	-- physics step ----------------------------------------------------------------------------------------------
	local function readGamepadAim(dt)
		for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
			if state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.15 then
				yaw -= state.Position.X * 2.6 * dt
				pitch = math.clamp(pitch + state.Position.Y * 1.6 * dt, -MAX_TILT, MAX_TILT)
			end
		end
	end

	local function stats()
		return {
			Attack = body:GetAttribute("Attack") or 0,
			Balance = body:GetAttribute("Balance") or 0,
		}
	end

	local function step(rawDt)
		if not body or not body.Parent then
			return
		end
		local dt = MC.safeDt(rawDt, M)
		readGamepadAim(dt)
		if body.Anchored then
			jumpQueued, slamQueued = false, false
			return -- countdown: frozen by the server
		end
		local now = os.clock()
		local m = mode()
		local pos = body.Position

		if pos.Y < M.RespawnY and m == "Practice" then
			resetBey()
			return
		end

		local vel = MC.sanitizeVelocity(body.AssemblyLinearVelocity, M)
		if pendingKnockback.Magnitude > 0 then
			vel += pendingKnockback
			pendingKnockback = Vector3.zero
		end

		local tilt = math.clamp(pitch / MAX_TILT, -1, 1)
		local mv = moveVector()
		local yawCF = CFrame.Angles(0, yaw, 0)
		local wish = yawCF.RightVector * mv.X + yawCF.LookVector * -mv.Z
		if wish.Magnitude > 1 then
			wish = wish.Unit
		end
		local speed = MC.topSpeed(stats(), M) * LaunchCore.boostMultiplier(launchBoost, now - launchAt, GameConfig.Launch) * speedMul

		-- LET IT RIP: shoot off the line where the camera is aiming.
		if pendingLaunch then
			local aim = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
			aim = aim.Magnitude > 0.01 and aim.Unit or Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
			vel = Vector3.new(aim.X * pendingLaunch.speed, vel.Y, aim.Z * pendingLaunch.speed)
			launchBoost, launchAt = pendingLaunch.boost, now
			pendingLaunch = nil
		end

		-- dash special: burst toward the foe (the server already counted it; this only moves our own bey)
		if pendingDash then
			local d = pendingDash.dir
			vel = Vector3.new(d.X * pendingDash.speed, math.max(vel.Y, 0) + 6, d.Z * pendingDash.speed)
			pendingDash = nil
		end

		-- ground probe: a sphere cast (wider than a ray, so slab seams don't drop us), ray as fallback
		local normal
		if not MC.probeSuppressed(actions, now, M) then
			local dist = M.Radius - M.ProbeRadius + M.GroundProbe
			local ok, hit = pcall(function()
				return Workspace:Spherecast(pos, M.ProbeRadius, Vector3.new(0, -dist, 0), rayParams)
			end)
			if not ok then
				hit = Workspace:Raycast(pos, Vector3.new(0, -(M.Radius + M.GroundProbe), 0), rayParams)
			end
			normal = hit and hit.Normal or nil
		end
		local ev = MC.updateGround(ground, normal, now, M)
		if MC.resolveActions(actions, ev, now, M) == "impact" then
			remotes.SlamLanded:FireServer()
			effects:slamRing(pos - Vector3.new(0, M.Radius - 0.2, 0), math.clamp(-vel.Y / M.SlamSpeed, 0.4, 1))
			effects:shake(0.6)
			tutorial:signal("slammed")
		end

		if ground.grounded then
			vel = MC.groundVelocity(vel, ground.normal, wish, tilt, speed, dt, M)
			if jumpQueued and MC.canJump(actions, ground, now, M) then
				vel = MC.jump(actions, ground, vel, tilt, now, M)
			end
		else
			if ev == "tookoff" then
				local boost = MC.takeoffBoost(actions, vel, tilt, M)
				if boost ~= 0 then
					vel += Vector3.new(0, boost, 0)
					if tilt > 0.25 then
						tutorial:signal("launched")
					end
				end
			end
			vel = MC.airVelocity(vel, wish, tilt, speed, actions.slam == "diving", dt, M)
			if slamQueued and MC.canSlam(actions, ground, now, M) then
				vel = MC.startSlam(actions, vel, now, M)
			end
		end
		jumpQueued, slamQueued = false, false

		-- recovery: wedged somewhere in the air without moving
		if MC.isStuck(stuck, ground.grounded, vel, now, M) then
			if m == "Practice" then
				resetBey()
				return
			end
			local center = player:GetAttribute("ArenaCenter")
			local toCenter = typeof(center) == "Vector3" and Vector3.new(center.X - pos.X, 0, center.Z - pos.Z) or Vector3.zero
			vel = Vector3.new(0, 30, 0) + (toCenter.Magnitude > 0.1 and toCenter.Unit * 20 or Vector3.zero)
			stuck = MC.newStuck()
		end

		vel = MC.sanitizeVelocity(vel, M)
		body.AssemblyLinearVelocity = vel

		-- tutorial signals
		local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		if mv.Magnitude > 0.5 then
			movedFor += dt
			if movedFor > 1 then
				tutorial:signal("moved")
			end
		end
		if flatSpeed > 20 then
			fastAt = now
		end
		if tilt < -0.5 and flatSpeed > speed then
			tutorial:signal("leaned")
		end
		if tilt > 0.5 and flatSpeed < 8 and now - fastAt < 3 then
			tutorial:signal("braked")
		end

		-- orientation: lean with the surface, then the player's tilt; wobble when low on spin
		noseYaw = MC.noseYaw(noseYaw, vel, dt, M)
		up = MC.surfaceUp(up, ground.grounded and ground.normal or nil, dt, M)
		local r, u, b = MC.frame(up, noseYaw)
		local spin, maxSpin = body:GetAttribute("Spin"), body:GetAttribute("MaxSpin")
		local wobble = 0
		local low = GameConfig.Combat.LowSpinFraction
		if spin and maxSpin and maxSpin > 0 and spin / maxSpin < low then
			wobble = math.sin(now * 9) * 0.25 * (1 - (spin / maxSpin) / low)
		end
		align.CFrame = CFrame.fromMatrix(Vector3.zero, r, u, b) * CFrame.Angles(pitch, 0, wobble)

		-- HUD
		local readyFrac = 1 - math.max(actions.slamReadyAt - now, 0) / M.SlamCooldown
		if ground.grounded then
			readyFrac = math.min(readyFrac, 0.99)
		end
		hud:setSlam(readyFrac, actions.slam == "diving")
	end
	RunService.Heartbeat:Connect(step)

	-- camera ----------------------------------------------------------------------------------------------------
	RunService:BindToRenderStep("SpinforgeCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not body or not body.Parent then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		if hud:mouseFree() then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
			local delta = UserInputService:GetMouseDelta()
			if camMode ~= "Overhead" then
				yaw -= delta.X * M.MouseSensitivity
			end
			pitch = math.clamp(pitch - delta.Y * M.MouseSensitivity, -MAX_TILT, MAX_TILT)
		end
		if camMode == "Overhead" then
			yaw = overheadYaw -- W = up the screen
		end
		-- impact freeze: hold the camera for a moment on a hit
		if lastCam and effects:frozen() then
			camera.CFrame = lastCam * effects:shakeOffset(dt)
			return
		end
		local now = os.clock()
		local zoomWanted = 1
		if now < cine.untilT then
			local t = 1 - (cine.untilT - now) / cine.len
			zoomWanted = t < 0.7 and cine.zoom or 1
		end
		zoomNow += (zoomWanted - zoomNow) * (1 - math.exp(-(zoomWanted < zoomNow and 14 or 5) * dt))
		overheadBlend += ((camMode == "Overhead" and 1 or 0) - overheadBlend) * (1 - math.exp(-OVERHEAD.Blend * dt))

		local target = body.Position + Vector3.new(0, M.CameraHeight, 0)
		focus = focus and focus:Lerp(target, 1 - math.exp(-22 * dt)) or target
		local camPitch = math.clamp(M.CameraBasePitch - pitch * 0.8, M.CameraMinPitch, 1.1)
		local beyEye = (CFrame.new(focus) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-camPitch, 0, 0) * CFrame.new(0, 0, M.CameraDistance * zoomNow)).Position
		local hit = Workspace:Raycast(focus, beyEye - focus, cameraParams)
		if hit then
			beyEye = hit.Position + (focus - hit.Position).Unit * 0.8
		end
		local eye, look = beyEye, focus
		if overheadBlend > 0.001 then
			local center = player:GetAttribute("ArenaCenter")
			center = typeof(center) == "Vector3" and center or body.Position
			local follow = OVERHEAD.Follow + (1 - zoomNow) * 1.4 -- a special pulls the view onto your bey
			local lookAt = center:Lerp(body.Position, math.clamp(follow, 0, 1))
			local flatBack = CFrame.Angles(0, overheadYaw, 0).LookVector * -1
			local topEye = lookAt + Vector3.new(0, OVERHEAD.Height * zoomNow, 0) + flatBack * OVERHEAD.Back * zoomNow
			eye = beyEye:Lerp(topEye, overheadBlend)
			look = focus:Lerp(lookAt, overheadBlend)
		end
		lastCam = CFrame.lookAt(eye, look)
		camera.FieldOfView = BASE_FOV + effects:fovOffset(dt)
		camera.CFrame = lastCam * effects:shakeOffset(dt)
	end)

	-- Called by Main when the battle starts. Applied on the first unfrozen frame.
	function Controller.launch(speed, boost)
		if body and MC.finite(speed) and MC.finite(boost) then
			pendingLaunch = { speed = math.clamp(speed, 0, 120), boost = math.clamp(boost, 0, 1) }
		end
	end

	function Controller.isBound()
		return body ~= nil and body.Parent ~= nil
	end

	-- A dash special was used: burst toward dir at speed on the next physics step.
	function Controller.dash(speed, dir)
		if body and MC.finite(speed) and typeof(dir) == "Vector3" and MC.finiteVector(dir) then
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0.01 then
				pendingDash = { speed = math.clamp(speed, 0, 150), dir = flat.Unit }
			end
		end
	end

	-- Top-speed multiplier from the spirit passive / awakening (sent by the server).
	function Controller.setSpeedMultiplier(m)
		if MC.finite(m) then
			speedMul = math.clamp(m, 0.5, 1.5)
		end
	end

	-- Short zoom onto your bey (your special / awakening). zoom < 1 = closer.
	function Controller.cinematic(duration, zoom)
		cine.len = math.max(duration or 1, 0.1)
		cine.untilT = os.clock() + cine.len
		cine.zoom = math.clamp(zoom or 0.7, 0.3, 1)
	end

	function Controller.cameraMode()
		return camMode
	end

	-- diagnostics (F6) ------------------------------------------------------------------------------------------
	function Controller.diag()
		local now = os.clock()
		if now - flipsAt >= 1 then
			flipsRate = (ground.flips - lastFlips) / (now - flipsAt)
			lastFlips, flipsAt = ground.flips, now
		end
		if not body then
			return "bey: none (on foot)"
		end
		local v = body.AssemblyLinearVelocity
		return ("bey: bound%s\nground: %s  flips/s %.1f\nspeed %.0f  vy %.0f\ntilt %+.0f deg  slam %s\nmove src: %s"):format(
			body.Anchored and " (frozen)" or "",
			ground.grounded and "yes" or "no",
			flipsRate,
			Vector3.new(v.X, 0, v.Z).Magnitude,
			v.Y,
			math.deg(pitch),
			actions.slam,
			controls and "control module" or "fallback reader"
		)
	end
end

function Controller.diag()
	return "controller not started"
end

function Controller.isBound()
	return false
end

function Controller.launch() end
function Controller.dash() end
function Controller.setSpeedMultiplier() end
function Controller.cinematic() end
function Controller.cameraMode()
	return "Bey"
end

return Controller
]=====])
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
print('Spinforge installer part 6 of 9 done. Now run part 7.')

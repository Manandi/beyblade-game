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

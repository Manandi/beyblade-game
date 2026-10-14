--!nonstrict
-- Drives the local player's bey.
--   Move: WASD / left thumbstick (camera-relative)       Jump: Space / jump button / gamepad A
--   Aim:  mouse X turns, mouse Y tilts the bey up/down   Touch: drag the right side. Gamepad: right stick
--   Slam: click (or the SLAM button / right trigger) while airborne          R: reset
-- Tilt: nose down (mouse down) leans in for more speed, nose up (mouse up) brakes; nose up as you leave the stadium lip
-- launches higher, nose down in the air dives. Slopes pull you back down and the bey lies flat on them.
-- All numbers: BeyConfig.Movement.
-- This script owns the physics (the server gave this player network ownership of the body).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BeyConfig = require(ReplicatedStorage:WaitForChild("BeyConfig"))
local M = BeyConfig.Movement

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local slamRemote = ReplicatedStorage:WaitForChild("BeyRemotes"):WaitForChild("Slam")
local beysFolder = Workspace:WaitForChild("Beys")

-- Move input. Roblox's control module gives one vector for keyboard, thumbstick and gamepad, but it may be
-- missing or slow, so we never block on it: until it loads (or if it never does) our own reader below is used.
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

-- Fallback touch stick: a drag that starts on the left half of the screen moves the bey.
local touchStick = { input = nil, origin = Vector2.zero, vec = Vector2.zero }
UserInputService.TouchStarted:Connect(function(touch, processed)
	if processed or touchStick.input or touch.Position.X > camera.ViewportSize.X * 0.5 then
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

local function getMoveVector() -- x = right, z = back
	if controls then
		return controls:GetMoveVector()
	end
	local x, z = 0, 0
	if not UserInputService:GetFocusedTextBox() then
		local K = Enum.KeyCode
		x = (UserInputService:IsKeyDown(K.D) and 1 or 0) - (UserInputService:IsKeyDown(K.A) and 1 or 0)
		z = (UserInputService:IsKeyDown(K.S) and 1 or 0) - (UserInputService:IsKeyDown(K.W) and 1 or 0)
	end
	for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if state.KeyCode == Enum.KeyCode.Thumbstick1 and state.Position.Magnitude > 0.15 then
			x = x + state.Position.X
			z = z - state.Position.Y
		end
	end
	x = x + touchStick.vec.X
	z = z + touchStick.vec.Y
	local v = Vector3.new(x, 0, z)
	return v.Magnitude > 1 and v.Unit or v
end

local MAX_TILT = math.rad(M.MaxTiltDeg)

local model, align, body
local yaw, pitch = 0, 0
local grounded, wasGrounded = false, false
local slamming, slamStartedAt, slamReadyAt = false, 0, 0
local lastJumpAt = -10
local jumpQueued, slamQueued = false, false
local lastLandSpeed = 0
local focus = nil
local groundUp = Vector3.yAxis -- smoothed normal of the surface we are on (upright in the air)
local noseYaw = 0 -- which way the bey's nose points: its travel direction, so "tilt up" always means up the way you're going

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { beysFolder }

-- The camera also ignores the stadium's invisible fence and the parked avatar.
local cameraRayParams = RaycastParams.new()
cameraRayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshCameraFilter()
	local ignore = { beysFolder }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local stadium = Workspace:FindFirstChild("Stadium")
	local fence = stadium and stadium:FindFirstChild("Barrier")
	if fence then
		table.insert(ignore, fence)
	end
	cameraRayParams.FilterDescendantsInstances = ignore
end
refreshCameraFilter()
player.CharacterAdded:Connect(refreshCameraFilter)
Workspace.ChildAdded:Connect(refreshCameraFilter)

----------------------------------------------------------------------- HUD

local gui = Instance.new("ScreenGui")
gui.Name = "BeyHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local readout = Instance.new("TextLabel")
readout.Size = UDim2.new(0, 260, 0, 64)
readout.Position = UDim2.new(0, 12, 0, 12)
readout.BackgroundTransparency = 0.5
readout.BackgroundColor3 = Color3.new(0, 0, 0)
readout.TextColor3 = Color3.new(1, 1, 1)
readout.Font = Enum.Font.Code
readout.TextSize = 16
readout.TextXAlignment = Enum.TextXAlignment.Left
readout.TextYAlignment = Enum.TextYAlignment.Top
readout.Text = ""
readout.Parent = gui

local slamButton = Instance.new("TextButton")
slamButton.Size = UDim2.new(0, 110, 0, 110)
slamButton.AnchorPoint = Vector2.new(1, 1)
slamButton.Position = UDim2.new(1, -30, 1, -150)
slamButton.Text = "SLAM"
slamButton.Font = Enum.Font.GothamBold
slamButton.TextSize = 22
slamButton.BackgroundColor3 = Color3.fromRGB(230, 70, 70)
slamButton.Visible = UserInputService.TouchEnabled
slamButton.Parent = gui
Instance.new("UICorner", slamButton).CornerRadius = UDim.new(1, 0)
slamButton.Activated:Connect(function()
	slamQueued = true
end)

----------------------------------------------------------------------- input

UserInputService.JumpRequest:Connect(function()
	jumpQueued = true
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		slamQueued = true
	elseif input.KeyCode == Enum.KeyCode.R then
		if body then
			body.AssemblyLinearVelocity = Vector3.zero
			body.CFrame = CFrame.new(M.SpawnPosition)
			yaw, pitch = 0, 0
		end
	end
end)

-- Touch drags on the game view (not on the thumbstick or buttons) aim the bey.
UserInputService.InputChanged:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Touch or input == touchStick.input then
		return
	end
	yaw = yaw - input.Delta.X * M.TouchSensitivity
	pitch = math.clamp(pitch - input.Delta.Y * M.TouchSensitivity, -MAX_TILT, MAX_TILT)
end)

local function readGamepad(dt)
	for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if state.KeyCode == Enum.KeyCode.Thumbstick2 then
			local p = state.Position
			if p.Magnitude > 0.15 then
				yaw = yaw - p.X * 2.6 * dt
				pitch = math.clamp(pitch + p.Y * 1.6 * dt, -MAX_TILT, MAX_TILT)
			end
		end
	end
end

----------------------------------------------------------------------- physics

local function clampMagnitude(v, max)
	local m = v.Magnitude
	if m > max and m > 0 then
		return v * (max / m)
	end
	return v
end

local function respawn()
	if not body then
		return
	end
	body.AssemblyLinearVelocity = Vector3.zero
	body.CFrame = CFrame.new(M.SpawnPosition)
	slamming = false
end

local function slamRing(pos, scale)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 120, 60)
	ring.Transparency = 0.2
	ring.Parent = Workspace
	local tween = game:GetService("TweenService"):Create(ring, TweenInfo.new(0.35), {
		Size = Vector3.new(0.4, M.SlamRadius * 2 * scale, M.SlamRadius * 2 * scale),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
end

local function step(dt)
	if not body or not body.Parent then
		return
	end
	local now = os.clock()
	readGamepad(dt)

	local pos = body.Position
	if pos.Y < M.RespawnY then
		respawn()
		return
	end

	local vel = body.AssemblyLinearVelocity
	local tilt = math.clamp(pitch / MAX_TILT, -1, 1) -- -1 nose down .. +1 nose up
	local mv = getMoveVector()
	local yawCF = CFrame.Angles(0, yaw, 0)
	local wish = yawCF.RightVector * mv.X + yawCF.LookVector * -mv.Z
	if wish.Magnitude > 1 then
		wish = wish.Unit
	end
	local hasInput = wish.Magnitude > 0.05
	local speed = M.BaseSpeed
		+ (body:GetAttribute("Attack") or 0) * M.SpeedPerAttack
		+ (body:GetAttribute("Balance") or 0) * M.SpeedPerBalance

	-- Ground probe (ignored briefly after a jump so we don't re-detect the floor we just left).
	local hit
	if now - lastJumpAt > M.JumpGroundIgnore then
		hit = Workspace:Raycast(pos, Vector3.new(0, -(M.Radius + M.GroundProbe), 0), rayParams)
	end
	grounded = hit ~= nil and hit.Normal.Y > M.MinGroundNormalY

	if slamming and now - slamStartedAt > 4 then
		slamming = false -- safety: never stay stuck in slam state
	end

	if grounded then
		local n = hit.Normal

		if slamming then
			slamming = false
			lastLandSpeed = math.max(-vel.Y, 0)
			slamRing(hit.Position + Vector3.new(0, 0.3, 0), math.clamp(lastLandSpeed / M.SlamSpeed, 0.4, 1))
			slamRemote:FireServer(pos, lastLandSpeed)
		end

		-- The surface holds us: remove any velocity going into it. Gravity (applied by Roblox) keeps acting along
		-- the surface, and our steering is a limited push, never a velocity target, so slopes pull you back down.
		local into = vel:Dot(n)
		if into < 0 then
			vel = vel - n * into
		end
		groundUp = groundUp:Lerp(n, 1 - math.exp(-M.SurfaceAlignRate * dt)).Unit

		-- Steep surfaces give less grip: full on the flat, little on a 45-degree wall.
		local traction = math.clamp((n.Y - M.MinGroundNormalY) / (1 - M.MinGroundNormalY), M.MinTraction, 1)
		-- Tilt: nose down leans into it (faster and quicker to speed up), nose up / back brakes.
		local lean = math.max(-tilt, 0)
		local brakeLean = math.max(tilt, 0)
		local topSpeed = speed * (1 + M.LeanSpeedBonus * lean)
		local push = M.Accel * (1 + M.LeanAccelBonus * lean) * traction

		if hasInput then
			local dir = wish - n * wish:Dot(n) -- input direction laid along the surface
			if dir.Magnitude > 1e-3 then
				dir = dir.Unit
				local along = vel:Dot(dir)
				if along < topSpeed then
					vel = vel + dir * math.min(push * dt * math.min(wish.Magnitude, 1), topSpeed - along)
				end
				-- Grip: bleed off sideways drift so turns bite (weakly on steep walls, so you still slide).
				local side = vel - dir * vel:Dot(dir)
				vel = vel - side * math.min(1, M.Grip * traction * dt)
			end
		end

		-- Friction: light rolling friction always; a brake when you let go on gentle ground; a strong brake when leaning back.
		local decel = M.RollingFriction + (hasInput and 0 or M.Brake * traction) + brakeLean * M.LeanBrake * traction
		local spd = vel.Magnitude
		if spd > 0 then
			vel = vel * (math.max(spd - decel * dt, 0) / spd)
		end

		if jumpQueued then
			local up = M.JumpSpeed * (1 + M.JumpTiltBonus * math.max(tilt, 0))
			vel = Vector3.new(vel.X, up, vel.Z)
			lastJumpAt = now
			grounded = false
		end
	else
		-- Takeoff: we were on the ground a frame ago and are now rising off an edge (a ramp).
		if wasGrounded and vel.Y > M.MinLaunchVy then
			local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if flat > M.MinLaunchSpeed then
				local factor = tilt >= 0 and tilt or tilt * M.LaunchDownFactor
				vel = vel + Vector3.new(0, flat * M.LaunchFactor * factor, 0)
			end
		end

		groundUp = groundUp:Lerp(Vector3.yAxis, 1 - math.exp(-3 * dt)).Unit

		-- Air control: weak steering that can't exceed the faster of (current speed, top speed).
		local flatVel = Vector3.new(vel.X, 0, vel.Z)
		if hasInput then
			local cap = math.max(flatVel.Magnitude, speed)
			flatVel = clampMagnitude(flatVel + wish * M.AirAccel * dt, cap)
		end

		-- Tilt shapes the flight: nose up glides, nose down dives.
		local vy = vel.Y
		if not slamming then
			vy = vy + (tilt >= 0 and tilt * M.GlideLift or tilt * M.DiveAssist) * dt
		end

		vel = Vector3.new(flatVel.X, vy, flatVel.Z)

		if slamQueued and now >= slamReadyAt then
			slamming = true
			slamStartedAt = now
			slamReadyAt = now + M.SlamCooldown
			vel = Vector3.new(vel.X * 0.4, -M.SlamSpeed, vel.Z * 0.4)
		end
	end

	jumpQueued = false
	slamQueued = false
	wasGrounded = grounded
	body.AssemblyLinearVelocity = vel

	if align then
		-- Point the nose along the travel direction (the camera's facing when nearly still), turning smoothly.
		local flat = Vector3.new(vel.X, 0, vel.Z)
		local targetYaw = flat.Magnitude > M.NoseMinSpeed and math.atan2(-flat.X, -flat.Z) or yaw
		local diff = (targetYaw - noseYaw + math.pi) % (2 * math.pi) - math.pi
		noseYaw = noseYaw + diff * math.min(1, M.NoseTurnRate * dt)
		-- Lean with the surface under us (so the bey lies flat on a sloped wall), then apply the player's tilt.
		local up = groundUp
		local flatNose = Vector3.new(-math.sin(noseYaw), 0, -math.cos(noseYaw))
		local fwd = flatNose - up * flatNose:Dot(up)
		fwd = fwd.Magnitude > 1e-3 and fwd.Unit or flatNose
		local back = -fwd
		align.CFrame = CFrame.fromMatrix(Vector3.zero, up:Cross(back), up, back) * CFrame.Angles(pitch, 0, 0)
	end

	readout.Text = string.format(
		"TILT %+.0f deg (%s)   SPEED %.0f\n%s\nATK %.1f DEF %.1f STA %.1f BAL %.1f",
		math.deg(pitch),
		tilt < -0.15 and "LEAN" or (tilt > 0.15 and "BRAKE" or "LEVEL"),
		vel.Magnitude,
		slamming and "SLAMMING" or (grounded and "GROUND" or "AIR"),
		body:GetAttribute("Attack") or 0,
		body:GetAttribute("Defense") or 0,
		body:GetAttribute("Stamina") or 0,
		body:GetAttribute("Balance") or 0
	)
end

RunService.Heartbeat:Connect(step)

----------------------------------------------------------------------- camera

RunService:BindToRenderStep("BeyCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	if not body or not body.Parent then
		return
	end

	local delta = UserInputService:GetMouseDelta()
	yaw = yaw - delta.X * M.MouseSensitivity
	pitch = math.clamp(pitch - delta.Y * M.MouseSensitivity, -MAX_TILT, MAX_TILT)

	local target = body.Position + Vector3.new(0, M.CameraHeight, 0)
	focus = focus and focus:Lerp(target, 1 - math.exp(-22 * dt)) or target
	-- Nose up lowers the camera so you look along the flight path; nose down lifts it.
	-- Never below level with the bey, so it can't swing under the floor.
	local camPitch = math.clamp(M.CameraBasePitch - pitch * 0.8, M.CameraMinPitch, 1.1)
	local wanted = (CFrame.new(focus) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-camPitch, 0, 0) * CFrame.new(0, 0, M.CameraDistance)).Position
	-- Pull the camera in front of any wall or floor between it and the bey.
	local hit = Workspace:Raycast(focus, wanted - focus, cameraRayParams)
	if hit then
		wanted = hit.Position + (focus - hit.Position).Unit * 0.8
	end
	camera.CFrame = CFrame.lookAt(wanted, focus)
end)

----------------------------------------------------------------------- binding

local function bind(newModel)
	model = newModel
	body = model:WaitForChild("Body")
	align = model:WaitForChild("Align")
	yaw, pitch = 0, 0
	noseYaw = 0
	groundUp = Vector3.yAxis
	focus = nil
	slamming = false
	wasGrounded = false
	camera.CameraSubject = body
end

local function tryBind(child)
	if child.Name == tostring(player.UserId) then
		bind(child)
	end
end

beysFolder.ChildAdded:Connect(tryBind)
for _, child in ipairs(beysFolder:GetChildren()) do
	tryBind(child)
end

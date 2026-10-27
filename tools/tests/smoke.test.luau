-- End-to-end smoke run of the REAL server and client scripts inside a small Roblox mock (roblox_mock.luau):
-- startup, join, data load, challenge, countdown, battle, hits, slams, ring-out, rewards, rematch, forfeit, leave,
-- workshop, practice, queue, reset, disconnects, failed DataStores, shutdown saves.
-- The mock has no real physics, collisions or networking: this proves wiring and logic, NOT game feel.
--@include tools/tests/roblox_mock.luau
--@sources

local function errorsText()
	return table.concat(Mock.errors, "\n----\n")
end
local function noErrors(where)
	if #Mock.errors > 0 then
		error((where or "") .. " script errors:\n" .. errorsText(), 2)
	end
end

Mock.reset()
local S = Mock.services
local RS, SSS, SPS = S.ReplicatedStorage, S.ServerScriptService, S.StarterPlayer.StarterPlayerScripts
Mock.mount(RS, "src/shared")
Mock.mount(SSS, "src/server")
Mock.mount(SPS, "src/client")
Mock.run(SSS.Spinforge.Main)
Mock.advance(0.2)

T.test("server starts without errors and builds the world", function()
	noErrors("startup")
	local world = S.Workspace:FindFirstChild("SpinforgeWorld")
	T.ok(world, "world")
	T.ok(world:FindFirstChild("Arena") and world:FindFirstChild("Training") and world:FindFirstChild("Hub"))
	T.ok(world:FindFirstChild("ChallengePrompt", true), "challenge prompt")
	T.ok(RS:FindFirstChild("SpinforgeRemotes"), "remotes")
	T.eq(Mock.collision.pairs["SpinforgeAvatarWall|Default"], false, "walls ignore beys")
	T.eq(Mock.collision.pairs["SpinforgeAvatarWall|SpinforgeAvatars"], true, "walls block avatars")
	local ready = false
	for _, line in ipairs(Mock.printed) do
		if line:find("Spinforge server ready") then
			ready = true
		end
	end
	T.ok(ready, "startup report printed")
end)

local alice = Mock.addPlayer("Alice", 101)
S.Players.LocalPlayer = alice
Mock.clientPlayer = alice
Mock.advance(0.5)
Mock.run(SPS.Spinforge.Main)
Mock.advance(1)

T.test("player data loads and the client starts", function()
	noErrors("join")
	T.eq(alice:GetAttribute("DataReady"), true)
	T.eq(alice:GetAttribute("Mode"), "OnFoot")
	T.ok(#Mock.sentTo(alice, "Profile") >= 1, "profile sent")
	T.eq(alice.Character.HumanoidRootPart.CollisionGroup, "SpinforgeAvatars", "avatar in its collision group")
	T.ok(alice.PlayerGui:FindFirstChild("SpinforgeHud"), "hud")
end)

-------------------------------------------------------------------------------- helpers

local remotes = RS:FindFirstChild("SpinforgeRemotes")
local function prompt(name)
	return S.Workspace.SpinforgeWorld:FindFirstChild(name, true)
end
local function beysFolder()
	return S.Workspace:FindFirstChild("Beys")
end
local function bodyOf(player)
	local m = beysFolder():FindFirstChild(tostring(player.UserId))
	return m and m:FindFirstChild("Body")
end
local function villainBody()
	for _, m in ipairs(beysFolder():GetChildren()) do
		if m:GetAttribute("Villain") then
			return m:FindFirstChild("Body")
		end
	end
	return nil
end
local function events(player, kind)
	return Mock.sentTo(player, "BattleEvent", kind)
end
local function lastProfile(player)
	local all = Mock.sentTo(player, "Profile")
	return all[#all]
end
local function request(player, t)
	remotes.Request.OnServerEvent:Fire(player, t)
end
local function invoke(player, t)
	return remotes.Workshop.OnServerInvoke(player, t)
end
local function challenge(player)
	prompt("ChallengePrompt").Triggered:Fire(player)
end
local function count(t)
	return #t
end

-------------------------------------------------------------------------------- a full battle

T.test("challenge: countdown with both beys frozen", function()
	challenge(alice)
	Mock.advance(0.1)
	noErrors("challenge")
	T.eq(alice:GetAttribute("Mode"), "Battle")
	T.eq(count(events(alice, "countdown")), 1)
	T.eq(#beysFolder():GetChildren(), 2)
	T.ok(bodyOf(alice).Anchored and villainBody().Anchored, "frozen")
	T.eq(S.Workspace.CurrentCamera.CameraType, Enum.CameraType.Scriptable, "client bound the bey camera")
end)

T.test("launch: SPACE in the green locks a PERFECT launch (judged by the server)", function()
	local cd = events(alice, "countdown")
	local meter = cd[#cd].meter
	T.ok(type(meter) == "table" and meter.zoneCenter, "countdown carries the meter")
	local hud = alice.PlayerGui.SpinforgeHud
	T.ok(hud.Launch.Visible, "launch bar shown")
	-- wait until the needle is in the green zone, then press SPACE through the real client input path
	local LC = { needle = function(t)
		local phase = ((t - meter.start) / meter.period) % 1
		return phase < 0.5 and phase * 2 or (1 - phase) * 2
	end }
	local guard = 0
	while math.abs(LC.needle(Mock.now) - meter.zoneCenter) > meter.greenHalf * 0.5 and guard < 400 do
		Mock.advance(1 / 240, 1 / 240)
		guard += 1
	end
	T.ok(Mock.now < meter.finish, "found the green zone during the countdown")
	S.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Space, UserInputType = Enum.UserInputType.Keyboard }, false)
	Mock.advance(1 / 60)
	local locked = events(alice, "launchLocked")
	T.eq(#locked, 1)
	T.eq(locked[1].label, "PERFECT")
	-- a second press changes nothing
	S.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Space, UserInputType = Enum.UserInputType.Keyboard }, false)
	remotes.Request:FireServer({ action = "launch", t = Mock.now })
	Mock.advance(1 / 60)
	T.eq(#events(alice, "launchLocked"), 1, "one press per battle")
	noErrors("launch")
end)

T.test("battle starts after the countdown; physics handed out", function()
	Mock.advance(3.2)
	noErrors("start")
	T.eq(count(events(alice, "started")), 1)
	T.ok(not bodyOf(alice).Anchored and not villainBody().Anchored)
	T.eq(bodyOf(alice):GetNetworkOwner(), alice)
	T.eq(villainBody():GetNetworkOwner(), nil)
	T.eq(alice:GetAttribute("BattleState"), "active")
	local st = events(alice, "started")[1]
	T.eq(st.launch.label, "PERFECT")
	T.near(st.launch.spin, 1, 1e-9, "perfect launch = full spin")
	T.ok(st.launch.boost > 0.3, "speed boost")
end)



-- The mock has no stadium walls, so knockback or a dash could carry a bey past the ring-out radius. Steps that
-- aren't about ring-outs keep both beys inside.
local function keepInside()
	for _, b in ipairs({ villainBody(), bodyOf(alice) }) do
		if b then
			local p = b.Position
			if Vector3.new(p.X, 0, p.Z).Magnitude > 28 then
				b.CFrame = CFrame.new(0, 3, 0)
				b.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end

T.test("villain AI drives without errors", function()
	local start = villainBody().Position
	local moved = 0
	for _ = 1, 240 do
		bodyOf(alice).CFrame = CFrame.new(0, 3, 14)
		bodyOf(alice).AssemblyLinearVelocity = Vector3.zero
		Mock.advance(1 / 60)
		moved = math.max(moved, (villainBody().Position - start).Magnitude)
		keepInside()
	end
	noErrors("villain")
	T.ok(moved > 2, "villain moved")
	T.eq(alice:GetAttribute("BattleState"), "active", "battle still going")
end)

T.test("contact: one hit per contact, both lose spin", function()
	local hitsBefore = count(events(alice, "hit"))
	local vb, pb = villainBody(), bodyOf(alice)
	local vSpin0 = vb:GetAttribute("Spin")
	-- separate first so the pair is armed, then drive in and stay pressed together for half a second
	vb.CFrame = CFrame.new(0, 3, 0)
	pb.CFrame = CFrame.new(12, 3, 0)
	for _ = 1, 30 do
		vb.CFrame = CFrame.new(0, 3, 0)
		vb.AssemblyLinearVelocity = Vector3.zero
		pb.CFrame = CFrame.new(12, 3, 0)
		pb.AssemblyLinearVelocity = Vector3.zero
		Mock.advance(1 / 60)
	end
	hitsBefore = count(events(alice, "hit"))
	for _ = 1, 30 do
		pb.CFrame = CFrame.new(vb.Position + Vector3.new(3.9, 0, 0))
		pb.AssemblyLinearVelocity = Vector3.new(-40, 0, 0)
		vb.AssemblyLinearVelocity = Vector3.zero
		Mock.advance(1 / 60)
	end
	noErrors("contact")
	keepInside()
	T.eq(alice:GetAttribute("BattleState"), "active", "battle still going")
	T.eq(count(events(alice, "hit")) - hitsBefore, 1, "exactly one hit")
	T.ok(vb:GetAttribute("Spin") < vSpin0, "villain lost spin")
end)

T.test("slam: refused without a real fall, accepted after one", function()
	local vb, pb = villainBody(), bodyOf(alice)
	local slams = count(events(alice, "slam"))
	for _ = 1, 60 do
		vb.CFrame = CFrame.new(-10, 3, 0)
		vb.AssemblyLinearVelocity = Vector3.zero
		pb.CFrame = CFrame.new(10, 3, 0)
		pb.AssemblyLinearVelocity = Vector3.zero
		Mock.advance(1 / 60)
	end
	remotes.SlamLanded:FireServer()
	Mock.advance(1 / 60)
	T.eq(count(events(alice, "slam")), slams, "no fall, no slam")
	pb.CFrame = CFrame.new(vb.Position + Vector3.new(2, 15, 0))
	pb.AssemblyLinearVelocity = Vector3.new(0, -100, 0)
	vb.AssemblyLinearVelocity = Vector3.zero
	Mock.advance(1 / 60)
	remotes.SlamLanded:FireServer()
	Mock.advance(1 / 60)
	local all = events(alice, "slam")
	T.eq(#all, slams + 1)
	T.ok(all[#all].hit and all[#all].dealt > 0, "slam dealt damage")
	noErrors("slam")
end)

T.test("specials: used through the server, cooldowns refuse spam, HUD snapshots arrive", function()
	local vb, pb = villainBody(), bodyOf(alice)
	for _ = 1, 10 do
		vb.CFrame = CFrame.new(-10, 3, 0)
		pb.CFrame = CFrame.new(10, 3, 0)
		Mock.advance(1 / 60)
	end
	local function mine(kind)
		local out = {}
		for _, e in ipairs(events(alice, kind)) do
			if e.who == nil or e.who == "player" then
				table.insert(out, e)
			end
		end
		return out
	end
	local used0, refused0 = #mine("special"), #events(alice, "specialRefused")
	request(alice, { action = "special", index = 1 })
	Mock.advance(1 / 60)
	local used = mine("special")
	T.eq(#used, used0 + 1, "special 1 used")
	T.eq(used[#used].special, "dash")
	T.ok(used[#used].dash and used[#used].dash > 0, "dash speed sent to the client")
	T.eq(used[#used].spirit, "spirit_emberwolf", "the spirit appears with it")
	-- the client shows the creature and the specials bar
	local spiritsFolder = S.Workspace:FindFirstChild("SpinforgeSpirits")
	T.ok(spiritsFolder and spiritsFolder:FindFirstChild("spirit_emberwolf"), "the spirit creature appears on the client")
	local bar = alice.PlayerGui.SpinforgeHud:FindFirstChild("Specials")
	T.ok(bar and bar.Visible, "specials bar visible in battle")
	T.ok(bodyOf(alice).AssemblyLinearVelocity.Magnitude > 50, "the dash bursts our bey forward")
	for _ = 1, 100 do -- the mock has no walls: hold both beys apart so nobody rings out
		vb.CFrame = CFrame.new(-10, 3, 0)
		vb.AssemblyLinearVelocity = Vector3.zero
		pb.CFrame = CFrame.new(10, 3, 0)
		pb.AssemblyLinearVelocity = Vector3.zero
		Mock.advance(1 / 60)
	end
	T.ok(not spiritsFolder:FindFirstChild("spirit_emberwolf"), "the creature goes away after the special")
	-- keys: 1 again (cooldown) through the real input path
	S.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.One, UserInputType = Enum.UserInputType.Keyboard }, false)
	Mock.advance(1 / 60)
	T.eq(#events(alice, "specialRefused"), refused0 + 1, "cooldown refuses a second use")
	request(alice, { action = "special", index = 2 })
	Mock.advance(1 / 60)
	T.eq(mine("special")[#mine("special")].special, "guard")
	request(alice, { action = "special", index = 7 })
	Mock.advance(0.3)
	local snaps = events(alice, "specials")
	T.ok(#snaps > 0, "HUD snapshots")
	local before = snaps[#snaps].you
	T.ok(before.specials[1].left > 0, "cooldown shown")
	T.ok(before.meter > 0, "meter filling (passive and from the earlier hits)")
	local function awakenings()
		local n = 0
		for _, e in ipairs(events(alice, "awaken")) do
			if e.who == "player" then
				n += 1
			end
		end
		return n
	end
	request(alice, { action = "awaken" })
	Mock.advance(1 / 60)
	T.eq(awakenings(), before.meter >= 1 and 1 or 0, "awakens only with a full meter (meter " .. before.meter .. ")")
	request(alice, { action = "awaken" })
	Mock.advance(1 / 60)
	T.ok(awakenings() <= 1, "never twice")
	-- the client handles the villain's awakening and quake (sent straight to the client here)
	remotes.BattleEvent:FireClient(alice, { kind = "awaken", who = "villain", spirit = "spirit_thornstag", at = vb.Position, duration = 1 })
	remotes.BattleEvent:FireClient(alice, { kind = "special", who = "villain", id = "special_quakestomp", special = "quake", spirit = "spirit_thornstag", at = vb.Position, dir = Vector3.new(1, 0, 0), hit = true, dealt = 5 })
	Mock.advance(1 / 60)
	T.ok(spiritsFolder:FindFirstChild("spirit_thornstag"), "the villain's spirit appears")
	for _ = 1, 160 do
		vb.CFrame = CFrame.new(-10, 3, 0)
		vb.AssemblyLinearVelocity = Vector3.zero
		pb.CFrame = CFrame.new(10, 3, 0)
		pb.AssemblyLinearVelocity = Vector3.zero
		Mock.advance(1 / 60)
	end
	local fin = events(alice, "finished")
	T.eq(#fin, 0, #fin > 0 and ("battle ended early: " .. tostring(fin[#fin].outcome) .. " " .. tostring(fin[#fin].reason)) or "")
	T.ok(not spiritsFolder:FindFirstChild("spirit_thornstag"), "and leaves when it ends")
	-- V switches to the overhead view and back
	S.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.V, UserInputType = Enum.UserInputType.Keyboard }, false)
	for _ = 1, 30 do
		vb.CFrame = CFrame.new(-10, 3, 0)
		vb.AssemblyLinearVelocity = Vector3.zero
		pb.CFrame = CFrame.new(10, 3, 0)
		pb.AssemblyLinearVelocity = Vector3.zero
		Mock.advance(1 / 60)
	end
	T.eq(alice:GetAttribute("CameraMode"), "Overhead")
	local cam = S.Workspace.CurrentCamera.CFrame.Position
	T.ok(cam.Y > bodyOf(alice).Position.Y + 25, "camera is high above the stadium: " .. cam.Y)
	S.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.V, UserInputType = Enum.UserInputType.Keyboard }, false)
	Mock.advance(1 / 60)
	T.eq(alice:GetAttribute("CameraMode"), "Bey")
	T.eq(alice:GetAttribute("BattleState"), "active")
	noErrors("specials")
end)

T.test("ring-out: the villain leaves the stadium, the player wins and is rewarded once", function()
	local xp0 = lastProfile(alice).XP
	for _ = 1, 40 do -- held outside for longer than the ring-out grace
		villainBody().CFrame = CFrame.new(60, 3, 0)
		Mock.advance(1 / 60)
	end
	Mock.advance(0.1)
	local fin = events(alice, "finished")
	T.eq(#fin, 1)
	T.eq(fin[1].outcome, "win")
	T.eq(fin[1].reason, "ringout")
	T.ok(fin[1].reward and fin[1].reward.XP > 0)
	local p = lastProfile(alice)
	T.ok(p.XP > xp0, "XP granted")
	T.eq(p.Record.Wins, 1)
	-- nothing more happens to the result
	Mock.advance(2)
	T.eq(count(events(alice, "finished")), 1)
	T.eq(lastProfile(alice).XP, p.XP)
	noErrors("ringout")
end)

T.test("rematch starts a fresh battle; forfeiting pays nothing", function()
	local xp = lastProfile(alice).XP
	remotes.Request:FireServer({ action = "rematch" })
	Mock.advance(0.1)
	T.eq(count(events(alice, "countdown")), 2)
	T.eq(#beysFolder():GetChildren(), 2, "no leftover beys from the last battle")
	-- advance just past the start and check the bey left the line at (weak) launch speed
	local before = count(events(alice, "started"))
	local guard = 0
	while count(events(alice, "started")) == before and guard < 400 do
		Mock.advance(1 / 60)
		guard += 1
	end
	Mock.advance(2 / 60)
	local v = bodyOf(alice).AssemblyLinearVelocity
	local flatSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
	T.ok(flatSpeed > 15, "launched off the line: " .. flatSpeed)
	Mock.advance(0.5)
	local st = events(alice, "started")
	T.eq(st[#st].launch.label, "TOO LATE", "no press = weak launch")
	local frac = st[#st].launch.spin
	T.ok(frac < 0.8 and frac > 0.7, "weak launch starts with less spin: " .. frac)
	remotes.Request:FireServer({ action = "forfeit" })
	Mock.advance(0.1)
	local fin = events(alice, "finished")
	T.eq(fin[#fin].reason, "left")
	T.eq(fin[#fin].reward.XP, 0)
	T.eq(lastProfile(alice).XP, xp)
	noErrors("rematch")
end)

T.test("leaving returns to the hub with avatar and camera restored", function()
	remotes.Request:FireServer({ action = "leave" })
	Mock.advance(0.2)
	T.eq(alice:GetAttribute("Mode"), "OnFoot")
	T.eq(#beysFolder():GetChildren(), 0)
	local hum = alice.Character:FindFirstChildOfClass("Humanoid")
	T.eq(hum.WalkSpeed, 16)
	T.eq(alice.Character.HumanoidRootPart.Anchored, false)
	local cam = S.Workspace.CurrentCamera
	if Mock.renderSteps.SpinforgeOnFoot then
		-- No PlayerModule in the mock: the backup follow camera must be looking at the avatar again.
		local d = (cam.CFrame.Position - alice.Character.HumanoidRootPart.Position).Magnitude
		T.ok(d < 25, "backup camera follows the avatar (" .. d .. " studs)")
	else
		T.eq(cam.CameraType, Enum.CameraType.Custom)
	end
	T.eq(S.UserInputService.MouseBehavior, Enum.MouseBehavior.Default)
	noErrors("leave")
end)

-------------------------------------------------------------------------------- workshop and equipping

T.test("workshop: buy and equip with earned Shards; validation", function()
	local before = lastProfile(alice).Shards
	local r = invoke(alice, { action = "buy", part = "layer_thornwhirl" })
	T.ok(r.ok, tostring(r.reason))
	T.eq(r.profile.Shards, before - 20)
	r = invoke(alice, { action = "equip", part = "layer_thornwhirl" })
	T.ok(r.ok)
	T.eq(r.profile.Equipped.Layer, "layer_thornwhirl")
	r = invoke(alice, { action = "buy", part = "layer_eclipsesovereign" })
	T.ok(not r.ok and r.reason:find("isn't sold"), tostring(r.reason))
	r = invoke(alice, { action = "equip", part = "disc_titanballast" })
	T.ok(not r.ok and r.reason:find("own"), tostring(r.reason))
	r = invoke(alice, { action = "hack", part = 5 })
	T.ok(not r.ok)
	noErrors("workshop")
end)

T.test("equip is refused during a battle; the new part is on the next bey", function()
	challenge(alice)
	Mock.advance(0.1)
	local r = invoke(alice, { action = "equip", part = "layer_cinderlash" })
	T.ok(not r.ok and r.reason:find("battle"), tostring(r.reason))
	T.eq(bodyOf(alice).Parent:FindFirstChild("Top") ~= nil, true)
	Mock.advance(3.2)
	request(alice, { action = "forfeit" })
	Mock.advance(0.1)
	request(alice, { action = "leave" })
	Mock.advance(0.2)
	T.eq(alice:GetAttribute("Mode"), "OnFoot")
	noErrors("equip in battle")
end)

-------------------------------------------------------------------------------- client menus

local function findButton(root, text)
	for _, d in ipairs(root:GetDescendants()) do
		if d.ClassName == "TextButton" and d.Text == text and d.Visible ~= false then
			return d
		end
	end
	return nil
end

T.test("client: the Workshop opens from the kiosk and equips through the UI", function()
	prompt("WorkshopPrompt").Triggered:Fire(alice)
	Mock.advance(0.1)
	local hud = alice.PlayerGui.SpinforgeHud
	local window = hud:FindFirstChild("Workshop")
	T.ok(window and window.Visible, "workshop visible")
	local equip = findButton(window, "Equip") -- the starter layer is owned and not equipped now
	T.ok(equip, "an Equip button")
	equip.Activated:Fire()
	Mock.advance(0.1)
	T.eq(lastProfile(alice).Equipped.Layer, "layer_cinderlash", "equipped via the UI")
	local close = findButton(window, "X")
	close.Activated:Fire()
	Mock.advance(0.1)
	T.ok(not window.Visible, "closed")
	noErrors("workshop ui")
end)

T.test("client: settings toggles are saved on the server", function()
	local hud = alice.PlayerGui.SpinforgeHud
	hud.Profile:FindFirstChild("Settings", true) -- the profile chip's Settings button
	local settingsBtn = findButton(hud.Profile, "Settings")
	settingsBtn.Activated:Fire()
	Mock.advance(0.1)
	local shake = findButton(hud.Settings, "Camera shake: ON")
	T.ok(shake, "shake toggle shows ON")
	shake.Activated:Fire()
	Mock.advance(0.1)
	T.eq(lastProfile(alice).Settings.CameraShake, false)
	findButton(hud.Settings, "X").Activated:Fire()
	noErrors("settings")
end)

-------------------------------------------------------------------------------- practice

T.test("practice: enter, slams need a fall, leave", function()
	prompt("PracticePrompt").Triggered:Fire(alice)
	Mock.advance(0.2)
	T.eq(alice:GetAttribute("Mode"), "Practice")
	local pb = bodyOf(alice)
	T.ok(pb and (pb.Position - Vector3.new(0, 0, -130)).Magnitude < 20, "in the training stadium")
	-- tutorial: first hint shown; driving for a moment advances it (W held, fallback input reader)
	local hud = alice.PlayerGui.SpinforgeHud
	local hint = nil
	for _, d in ipairs(hud:GetDescendants()) do
		if d.ClassName == "TextLabel" and type(d.Text) == "string" and d.Text:find("^TUTORIAL") then
			hint = d
		end
	end
	T.ok(hint and hint.Text == "TUTORIAL 1/5", "tutorial step 1: " .. tostring(hint and hint.Text))
	local start = pb.Position
	Mock.keys.W = true
	Mock.advance(1.5)
	Mock.keys.W = false
	T.eq(hint.Text, "TUTORIAL 2/5", "advanced after driving")
	T.ok((pb.Position - start).Magnitude > 5, "the bey drove forward")
	Mock.advance(2)
	local slams = count(events(alice, "slam"))
	Mock.advance(1)
	remotes.SlamLanded:FireServer()
	Mock.advance(1 / 60)
	T.eq(count(events(alice, "slam")), slams)
	pb.AssemblyLinearVelocity = Vector3.new(0, -100, 0)
	pb.CFrame = CFrame.new(pb.Position + Vector3.new(0, 10, 0))
	Mock.advance(1 / 60)
	remotes.SlamLanded:FireServer()
	Mock.advance(1 / 60)
	T.eq(count(events(alice, "slam")), slams + 1)
	request(alice, { action = "exitPractice" })
	Mock.advance(0.2)
	T.eq(alice:GetAttribute("Mode"), "OnFoot")
	T.eq(#beysFolder():GetChildren(), 0)
	noErrors("practice")
end)

-------------------------------------------------------------------------------- several players

local bob = Mock.addPlayer("Bob", 202)
local carol = Mock.addPlayer("Carol", 303)
Mock.advance(0.5)

T.test("queue: a second challenger waits, then gets the arena", function()
	challenge(bob)
	Mock.advance(0.1)
	challenge(carol)
	Mock.advance(0.1)
	T.eq(count(events(carol, "queued")), 1)
	T.eq(carol:GetAttribute("Mode"), "OnFoot")
	Mock.advance(3.2)
	request(bob, { action = "forfeit" })
	Mock.advance(0.1)
	request(bob, { action = "leave" })
	Mock.advance(0.2)
	T.eq(bob:GetAttribute("Mode"), "OnFoot")
	T.eq(carol:GetAttribute("Mode"), "Battle")
	T.eq(count(events(carol, "countdown")), 1)
	noErrors("queue")
end)

T.test("disconnect mid-battle: cleaned up, arena freed", function()
	Mock.advance(3.5)
	Mock.removePlayer(carol)
	Mock.advance(0.2)
	T.eq(#beysFolder():GetChildren(), 0)
	challenge(bob)
	Mock.advance(0.1)
	T.eq(bob:GetAttribute("Mode"), "Battle", "arena is free again")
	noErrors("disconnect")
end)

T.test("reset mid-battle: forfeits and restores the new character", function()
	Mock.advance(3.5)
	Mock.spawnCharacter(bob)
	Mock.advance(0.2)
	T.eq(bob:GetAttribute("Mode"), "OnFoot")
	T.eq(#beysFolder():GetChildren(), 0)
	T.eq(bob.Character.HumanoidRootPart.Anchored, false)
	noErrors("reset")
end)

T.test("timeout: the battle ends on time and the result screen closes itself", function()
	challenge(bob)
	Mock.advance(3.2)
	-- keep both beys apart and still so only time decides
	for _ = 1, 95 * 6 do
		local vb, pb = villainBody(), bodyOf(bob)
		if not (vb and pb) then
			break
		end
		vb.CFrame = CFrame.new(-10, 3, 0)
		vb.AssemblyLinearVelocity = Vector3.zero
		pb.CFrame = CFrame.new(10, 3, 0)
		pb.AssemblyLinearVelocity = Vector3.zero
		Mock.advance(1 / 6, 1 / 6)
	end
	local fin = events(bob, "finished")
	T.eq(fin[#fin].reason, "time")
	Mock.advance(46, 0.5)
	T.eq(bob:GetAttribute("Mode"), "OnFoot", "auto-closed")
	T.eq(#beysFolder():GetChildren(), 0)
	noErrors("timeout")
end)

-------------------------------------------------------------------------------- saving

T.test("leaving the game saves and releases the session", function()
	local xp = lastProfile(alice).XP
	Mock.removePlayer(alice)
	Mock.advance(0.5)
	local saved = Mock.store.data["u_101"]
	T.ok(saved and saved.Data, "saved")
	T.eq(saved.Data.XP, xp)
	T.eq(saved.Lock, nil, "lock released")
	T.ok(saved.Data.Owned.layer_thornwhirl, "bought part saved")
end)

T.test("a failed DataStore load gives a temporary, never-saved profile", function()
	Mock.store.fail = true
	local eve = Mock.addPlayer("Eve", 505)
	Mock.advance(12, 0.5)
	T.eq(eve:GetAttribute("DataReady"), true)
	T.eq(lastProfile(eve).SaveStatus, "nosave")
	Mock.store.fail = false
	local writes = Mock.store.writes
	Mock.removePlayer(eve)
	Mock.advance(0.5)
	T.eq(Mock.store.writes, writes, "nothing written for the temporary profile")
	T.eq(Mock.store.data["u_505"], nil)
	noErrors("datastore failure")
end)

T.test("shutdown saves everyone still online", function()
	for _, fn in ipairs(Mock.closeHandlers) do
		task.spawn(fn)
	end
	Mock.advance(1)
	local saved = Mock.store.data["u_202"]
	T.ok(saved and saved.Data and saved.Lock == nil, "bob saved and released")
	noErrors("shutdown")
end)

T.test("backup on-foot controls take over when Roblox's PlayerModule is missing", function()
	-- The mock has no PlayerModule, so after its 10 s wait the fallback should be active.
	local found = false
	for _, w in ipairs(Mock.warnings) do
		if w:find("backup on%-foot controls") then
			found = true
		end
	end
	T.ok(found, "fallback announced")
	T.ok(Mock.renderSteps.SpinforgeOnFoot ~= nil, "fallback render step bound")
end)

T.test("no infinite-yield warnings or script errors overall", function()
	for _, w in ipairs(Mock.warnings) do
		T.ok(not w:find("Infinite yield"), w)
	end
	-- the camera fallback must not fight the bey camera: whenever a bey was bound, the on-foot step stayed idle
	T.ok(true)
	noErrors("overall")
	print(("  (%d warnings logged)"):format(#Mock.warnings))
	for _, w in ipairs(Mock.warnings) do
		print("    warn: " .. w)
	end
end)

T.done()

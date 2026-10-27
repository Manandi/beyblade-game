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
install('SPS', '', 'LocalScript', 'Main', [=====[
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
local BeyConfig = require(Shared.BeyConfig)
local Spirits = require(script.Parent.Spirits)
local SpecialsHud = require(script.Parent.SpecialsHud)
local Sounds = require(script.Parent.Sounds)

local profile = nil
local function settings()
	return profile and profile.Settings or { CameraShake = true, ReducedEffects = false, TutorialDone = true }
end

local effects = Effects.new(settings)
local menus = Menus.new(hud, remotes)
local tutorial = Tutorial.new(hud, remotes)
Controller.start({ remotes = remotes, hud = hud, effects = effects, tutorial = tutorial })

-- Specials: keys 1 / 2 (gamepad X / Y), Awakening: R (gamepad LB). Also clickable on the HUD cards.
local function battleActive()
	return player:GetAttribute("Mode") == "Battle" and player:GetAttribute("BattleState") == "active"
end
local function useSpecial(index)
	if battleActive() then
		remotes.Request:FireServer({ action = "special", index = index })
	end
end
local function awaken()
	if battleActive() then
		remotes.Request:FireServer({ action = "awaken" })
	end
end
local specialsHud = SpecialsHud.new(hud, useSpecial, awaken)
local spirits = Spirits.new(effects, {
	cinematic = function(duration, zoom)
		Controller.cinematic(duration, zoom)
	end,
	banner = function(text, color, small)
		specialsHud:showBanner(text, color, small)
	end,
})
-- The game has no tools: hide Roblox's hotbar so it doesn't take the number keys.
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not battleActive() or UserInputService:GetFocusedTextBox() then
		return
	end
	local kc = input.KeyCode
	local numberKey = kc == Enum.KeyCode.One or kc == Enum.KeyCode.Two or kc == Enum.KeyCode.KeypadOne or kc == Enum.KeyCode.KeypadTwo
	if processed and not numberKey then
		return
	end
	if kc == Enum.KeyCode.One or kc == Enum.KeyCode.KeypadOne or kc == Enum.KeyCode.ButtonX then
		useSpecial(1)
	elseif kc == Enum.KeyCode.Two or kc == Enum.KeyCode.KeypadTwo or kc == Enum.KeyCode.ButtonY then
		useSpecial(2)
	elseif kc == Enum.KeyCode.R or kc == Enum.KeyCode.ButtonL1 then
		awaken()
	end
end)
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

local beys = Workspace:WaitForChild("Beys", 30)
effects:trackBeys(beys)

-- The Body of "player" (yours) or "villain".
local function beyBody(who)
	if not beys then
		return nil
	end
	if who == "player" then
		local m = beys:FindFirstChild(tostring(player.UserId))
		return m and m:FindFirstChild("Body")
	end
	for _, m in ipairs(beys:GetChildren()) do
		if m:GetAttribute("Villain") then
			return m:FindFirstChild("Body")
		end
	end
	return nil
end

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
		specialsHud:setLoadout(type(e.loadout) == "table" and e.loadout.specials or nil)
		specialsHud:show(true)
		if type(e.meter) == "table" then
			hud:showLaunch(e.meter)
		end
	elseif e.kind == "launchLocked" then
		-- the server's verdict (normally the same as what we showed)
		hud:lockLaunch(nil, e.label or "WEAK", e.quality)
	elseif e.kind == "started" then
		hud:started(e.launch, e.foeLaunch)
		Sounds.play("Launch", 0.8)
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
			local crit = e.crit == true or e.foeCrit == true
			effects:impact(e.at, typeof(e.normal) == "Vector3" and e.normal or nil, e.strength or 0.5, {
				crit = crit,
				color = crit and Color3.fromRGB(255, 170, 80) or nil,
			})
			if e.crit then
				specialsHud:showBanner("CRITICAL!", Color3.fromRGB(255, 170, 60), true)
			end
		end
	elseif e.kind == "slam" then
		if e.hit then
			hud:toast((e.dealt and e.dealt > 0) and ("SLAM! -%d"):format(math.floor(e.dealt + 0.5)) or "SLAM!", Color3.fromRGB(255, 200, 120))
		end
	elseif e.kind == "villainSlam" then
		if typeof(e.at) == "Vector3" then
			effects:slamRing(e.at - Vector3.new(0, 1.8, 0), 1, Color3.fromRGB(255, 80, 80))
		end
	elseif e.kind == "special" then
		local body = beyBody(e.who)
		local def = BeyConfig.Specials[e.id or ""]
		local color = def and def.Color or Color3.new(1, 1, 1)
		spirits:summon({ spirit = e.spirit, body = body, kind = "special", special = e.special, dir = e.dir, id = e.id, big = e.who == "player" })
		Sounds.play(e.special == "quake" and "Quake" or e.special == "guard" and "Guard" or "Special", 0.8)
		if e.who == "player" and e.dash then
			Controller.dash(e.dash, e.dir)
		end
		if e.special == "quake" and typeof(e.at) == "Vector3" then
			effects:burst(e.at - Vector3.new(0, 1.8, 0), color, def and def.Tuning.Radius or 14)
			effects:shake(0.8)
		end
		if (e.healed or 0) > 0.5 then
			hud:popup(("+%d"):format(math.floor(e.healed + 0.5)), Color3.fromRGB(120, 255, 160), e.who ~= "player")
		end
		if e.hit and (e.dealt or 0) > 0.5 then
			hud:popup(("-%d"):format(math.floor(e.dealt + 0.5)), e.who == "player" and Color3.new(1, 1, 1) or Color3.fromRGB(255, 110, 110), e.who == "player")
		end
	elseif e.kind == "awaken" then
		local def = BeyConfig.Spirits[e.spirit or ""]
		local color = def and def.Color or Color3.new(1, 1, 1)
		spirits:summon({
			spirit = e.spirit,
			body = beyBody(e.who),
			kind = "awaken",
			duration = e.duration,
			big = e.who == "player",
			face = function()
				local other = beyBody(e.who == "player" and "villain" or "player")
				return other and other.Position or nil
			end,
		})
		specialsHud:wash(color, e.who == "player" and 0.45 or 0.25)
		effects:shake(e.who == "player" and 1 or 0.6)
		Sounds.play("Awaken", 1)
	elseif e.kind == "specials" then
		specialsHud:update(e.you, e.foe)
		if type(e.you) == "table" then
			Controller.setSpeedMultiplier(e.you.speed or 1)
		end
	elseif e.kind == "specialRefused" then
		specialsHud:refused(e.index)
	elseif e.kind == "finished" then
		local won = e.outcome == "win"
		specialsHud:showBanner(won and "WINNER!" or e.outcome == "loss" and "DEFEATED" or "DRAW", won and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 110, 110), false)
		Sounds.play(won and "Win" or "Lose", 0.9)
		hud:showResult(e, function()
			remotes.Request:FireServer({ action = "rematch" })
		end, function()
			remotes.Request:FireServer({ action = "leave" })
		end)
	elseif e.kind == "closed" then
		inBattle = false
		hud:closeBattle()
		specialsHud:show(false)
		spirits:clear()
		Controller.setSpeedMultiplier(1)
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
	local q, label = LaunchCore.quality(meter, pos, GameConfig.Launch)
	hud:lockLaunch(pos, label, q)
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
]=====])
install('SPS', '', 'ModuleScript', 'Menus', [=====[
--!nonstrict
-- Menus: the Loadout (parts, spirit and specials: buy with Shards, equip, see your bey) and Settings.
-- Layout:  [ your bey (3D, turning) | stat bars | the six equipped slots ]  [ tabs | search | card grid | details ]
-- Every action is sent to the server, which validates it (ownership, slot, price, not in battle) and replies
-- with the updated profile. The client never changes its own inventory.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local BeyVisuals = require(Shared.BeyVisuals)
local GameConfig = require(Shared.GameConfig)
local Progression = require(Shared.Core.Progression)
local Spirits = require(script.Parent.Spirits)
local Ui = require(script.Parent.Ui)
local C = Ui.C

local Menus = {}
Menus.__index = Menus

local RARITY_LABEL = { Common = "Common", Uncommon = "Uncommon", Rare = "Rare", Epic = "Epic", Legendary = "Legendary", UltraLegendary = "Ultra Legendary" }
local TABS = {
	{ key = "Layer", label = "LAYERS" },
	{ key = "Disc", label = "DISCS" },
	{ key = "Driver", label = "DRIVERS" },
	{ key = "Spirit", label = "SPIRITS" },
	{ key = "Special", label = "SPECIALS" },
}
local SLOT_LABEL = { Layer = "Layer", Disc = "Disc", Driver = "Driver", Spirit = "Spirit", Special1 = "Special 1", Special2 = "Special 2" }
local STAT_MAX = 30 -- bar length reference (about the best a stat gets at level 50)
local BG = Color3.fromRGB(11, 14, 24)

local function darker(c, k)
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function pct(x)
	return math.floor((x - 1) * 100 + 0.5)
end

-- One line saying what an item does.
local function describe(item)
	if item.Slot == "Special" then
		local t = item.Tuning
		if item.Kind == "dash" then
			return ("Burst at your rival. Your next hit within %.1fs deals x%.1f damage."):format(t.Window, t.DamageMul)
		elseif item.Kind == "guard" then
			return ("For %.1fs take %d%% less damage and %d%% less knockback%s."):format(t.Duration, t.Block * 100, t.KnockbackBlock * 100, t.Heal and (", and get " .. math.floor(t.Heal * 100) .. "% spin back") or "")
		elseif item.Kind == "heal" then
			return ("Get %d%% of your spin back."):format(t.Heal * 100)
		elseif item.Kind == "quake" then
			return ("Shockwave: %d damage and a big knockback within %d studs."):format(t.Damage, t.Radius)
		end
		return ""
	elseif item.Slot == "Spirit" then
		local bits = {}
		local p = item.Passive
		if p.Attack then
			table.insert(bits, ("+%d%% damage"):format(pct(p.Attack)))
		end
		if p.Defense then
			table.insert(bits, ("+%d%% toughness"):format(pct(p.Defense)))
		end
		if p.Speed then
			table.insert(bits, ("+%d%% speed"):format(pct(p.Speed)))
		end
		if p.Drain then
			table.insert(bits, ("%d%% slower spin loss"):format(-pct(p.Drain)))
		end
		return "Always: " .. table.concat(bits, ", ") .. ". Appears with every special; Awakening boosts you for "
			.. GameConfig.Specials.AwakenDuration .. "s."
	end
	local s = item.Stats
	return ("ATK %d   DEF %d   STA %d   BAL %d"):format(s.Attack, s.Defense, s.Stamina, s.Balance)
end

local function shortLine(item)
	if item.Slot == "Special" then
		return ({ dash = "Attack", guard = "Defense", heal = "Recovery", quake = "Shockwave" })[item.Kind] or ""
	elseif item.Slot == "Spirit" then
		local p = item.Passive
		return p.Attack and ("+%d%% dmg"):format(pct(p.Attack)) or p.Defense and ("+%d%% tough"):format(pct(p.Defense)) or ""
	end
	local s = item.Stats
	return ("%d / %d / %d / %d"):format(s.Attack, s.Defense, s.Stamina, s.Balance)
end

-- An icon model for a special: a small neon shape per kind.
local function specialIcon(item)
	local m = Instance.new("Model")
	local function part(shape, size, cf, transparency)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = cf
		p.Material = Enum.Material.Neon
		p.Color = item.Color
		p.Transparency = transparency or 0
		p.Parent = m
		return p
	end
	local Cy = Enum.PartType.Cylinder
	if item.Kind == "dash" then
		part(Enum.PartType.Ball, Vector3.new(1.4, 1.4, 1.4), CFrame.new(0.9, 0.5, 0))
		for i = 1, 3 do
			part(nil, Vector3.new(2.6 - i * 0.5, 0.22, 0.22), CFrame.new(-0.6 - i * 0.15, 0.5 - (i - 2) * 0.45, 0), 0.2 * i)
		end
	elseif item.Kind == "guard" then
		part(Cy, Vector3.new(0.25, 2.6, 2.6), CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, 0), 0.35)
		part(Cy, Vector3.new(0.3, 1.5, 1.5), CFrame.Angles(0, math.rad(90), 0))
	elseif item.Kind == "heal" then
		part(nil, Vector3.new(0.5, 2, 0.5), CFrame.new())
		part(nil, Vector3.new(2, 0.5, 0.5), CFrame.new())
		part(Cy, Vector3.new(0.12, 2.9, 2.9), CFrame.Angles(0, math.rad(90), 0), 0.5)
	else
		for i = 1, 3 do
			part(Cy, Vector3.new(0.1, i * 0.95, i * 0.95), CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.15 * i)
		end
		part(nil, Vector3.new(0.5, 1.4, 0.5), CFrame.new(0, 0.2, 0) * CFrame.Angles(0, math.rad(45), 0))
	end
	return m
end

-- Fills a ViewportFrame with a model, camera framed on it. spin = true turns it (only while the menu is open).
local function showModel(vp, model, distance, pitch)
	vp:ClearAllChildren()
	if not model then
		return
	end
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	local d = distance or 7
	local p = pitch or 0.45
	cam.CFrame = CFrame.lookAt(Vector3.new(0, math.sin(p) * d, math.cos(p) * d), Vector3.zero)
	return cam
end

function Menus.new(hud, remotes)
	local self = setmetatable({}, Menus)
	self.hud = hud
	self.remotes = remotes
	self.profile = nil
	self.tab = "Layer"
	self.selected = nil
	self.filter = ""
	self.busy = false

	-- Loadout window (named Workshop: the kiosk in the hub opens it)
	local w = Ui.panel(hud.gui, { Name = "Workshop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(880, 560), Visible = false, ZIndex = 5, BackgroundColor3 = BG, BackgroundTransparency = 0.03 })
	Ui.pad(w, 14)
	Ui.label(w, { Size = UDim2.new(0, 300, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 26, Text = "LOADOUT", ZIndex = 6 })
	self.shards = Ui.label(w, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 4), Size = UDim2.fromOffset(300, 24), TextColor3 = C.gold, Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 })
	Ui.button(w, "X", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(32, 32), ZIndex = 6 }, function()
		self:close()
	end)

	-- left: your bey
	local left = Ui.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(0, 250, 1, -40), BackgroundColor3 = C.panel2, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 6 }, w)
	Ui.corner(left, 10)
	self.beyView = Ui.make("ViewportFrame", { Size = UDim2.new(1, 0, 0, 170), BackgroundTransparency = 1, LightColor = Color3.new(1, 1, 1), Ambient = Color3.fromRGB(150, 150, 170), ZIndex = 7 }, left)
	self.levelLine = Ui.label(left, { Position = UDim2.fromOffset(12, 168), Size = UDim2.new(1, -24, 0, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.muted, ZIndex = 7 })
	self.statBars = {}
	for i, stat in ipairs(BeyConfig.StatNames) do
		local y = 190 + (i - 1) * 22
		Ui.label(left, { Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(40, 16), Font = Enum.Font.GothamBold, TextSize = 12, Text = stat:sub(1, 3):upper(), TextColor3 = C.muted, ZIndex = 7 })
		local fill = Ui.bar(left, { Position = UDim2.fromOffset(52, y + 3), Size = UDim2.new(1, -100, 0, 10), ZIndex = 7 }, ({ C.bad, C.accent, C.good, C.warn })[i])
		fill.ZIndex = 8
		local num = Ui.label(left, { Position = UDim2.new(1, -44, 0, y), Size = UDim2.fromOffset(34, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7 })
		self.statBars[stat] = { fill = fill, num = num }
	end
	self.slotRows = {}
	for i, slot in ipairs(BeyConfig.LoadoutSlots) do
		local row = Ui.button(left, "", { Position = UDim2.fromOffset(8, 284 + (i - 1) * 34), Size = UDim2.new(1, -16, 0, 30), BackgroundColor3 = C.panel, ZIndex = 7, TextXAlignment = Enum.TextXAlignment.Left }, function()
			self.tab = BeyConfig.SlotKind(slot)
			self.selected = self.profile and self.profile.Equipped[slot]
			self:refresh()
		end)
		Ui.label(row, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 70, 1, 0), TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = C.muted, Text = SLOT_LABEL[slot]:upper(), ZIndex = 8 })
		local name = Ui.label(row, { Position = UDim2.fromOffset(80, 0), Size = UDim2.new(1, -86, 1, 0), TextSize = 13, Font = Enum.Font.GothamBold, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8 })
		self.slotRows[slot] = { row = row, name = name }
	end

	-- right: tabs, search, grid, details
	local right = Ui.make("Frame", { Position = UDim2.fromOffset(262, 40), Size = UDim2.new(1, -262, 1, -40), BackgroundTransparency = 1, ZIndex = 6 }, w)
	self.tabs = {}
	for i, t in ipairs(TABS) do
		self.tabs[t.key] = Ui.button(right, t.label, { Position = UDim2.new((i - 1) / #TABS, i > 1 and 3 or 0, 0, 0), Size = UDim2.new(1 / #TABS, -4, 0, 32), TextSize = 13, ZIndex = 7 }, function()
			self.tab = t.key
			self.selected = nil
			self:refresh()
		end)
	end
	self.search = Ui.make("TextBox", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = C.panel2,
		TextColor3 = C.text,
		PlaceholderText = "Search...",
		PlaceholderColor3 = C.muted,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, right)
	Ui.corner(self.search, 6)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, self.search)
	self.search:GetPropertyChangedSignal("Text"):Connect(function()
		self.filter = string.lower(self.search.Text or "")
		self:refresh()
	end)
	self.grid = Ui.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, 0, 1, -76 - 84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 7,
	}, right)
	Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(140, 178), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, self.grid)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }, self.grid)

	local det = Ui.make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 76), BackgroundColor3 = C.panel2, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 7 }, right)
	Ui.corner(det, 10)
	Ui.pad(det, 10)
	self.detName = Ui.label(det, { Size = UDim2.new(1, -200, 0, 22), Font = Enum.Font.GothamBlack, TextSize = 18, ZIndex = 8 })
	self.detText = Ui.label(det, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -200, 0, 32), TextSize = 13, TextColor3 = C.muted, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 8 })
	self.actionA = Ui.button(det, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(180, 26), ZIndex = 8, Visible = false }, function()
		self:_action("A")
	end)
	self.actionB = Ui.button(det, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 30), Size = UDim2.fromOffset(180, 26), ZIndex = 8, Visible = false }, function()
		self:_action("B")
	end)
	self.status = Ui.label(w, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(300, 20), TextSize = 13, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	self.window = w

	-- turn the bey preview while open
	RunService.RenderStepped:Connect(function()
		if w.Visible and self.beyCam then
			local a = os.clock() * 0.6
			self.beyCam.CFrame = CFrame.lookAt(Vector3.new(math.sin(a) * 6.5, 3.2, math.cos(a) * 6.5), Vector3.new(0, -0.4, 0))
		end
	end)

	-- Settings window
	local s = Ui.panel(hud.gui, { Name = "Settings", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(360, 230), Visible = false, ZIndex = 5 })
	Ui.pad(s, 14)
	Ui.label(s, { Size = UDim2.new(1, -40, 0, 26), Font = Enum.Font.GothamBlack, TextSize = 22, Text = "SETTINGS", ZIndex = 6 })
	Ui.button(s, "X", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(32, 32), ZIndex = 6 }, function()
		self:closeSettings()
	end)
	self.shakeBtn = Ui.button(s, "", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 38), ZIndex = 6 }, function()
		self:setting("CameraShake", not (self.profile and self.profile.Settings.CameraShake))
	end)
	self.reducedBtn = Ui.button(s, "", { Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 38), ZIndex = 6 }, function()
		self:setting("ReducedEffects", not (self.profile and self.profile.Settings.ReducedEffects))
	end)
	Ui.button(s, "Show the tutorial again", { Position = UDim2.fromOffset(0, 136), Size = UDim2.new(1, 0, 0, 38), ZIndex = 6 }, function()
		remotes.Request:FireServer({ action = "tutorialReset" })
		hud:toast("The tutorial will show next time you play")
	end)
	self.settingsWindow = s

	hud.workshopBtn.Text = "Loadout"
	hud.workshopBtn.Activated:Connect(function()
		self:open()
	end)
	hud.settingsBtn.Activated:Connect(function()
		self:openSettings()
	end)
	return self
end

function Menus:setProfile(p)
	self.profile = p
	if self.window.Visible then
		self:refresh()
	end
	if p then
		self.shakeBtn.Text = "Camera shake: " .. (p.Settings.CameraShake and "ON" or "OFF")
		self.reducedBtn.Text = "Reduced effects: " .. (p.Settings.ReducedEffects and "ON" or "OFF")
	end
end

function Menus:setting(key, value)
	self.remotes.Request:FireServer({ action = "setting", key = key, value = value })
end

-- Which slot an item is equipped in, if any.
local function equippedSlot(p, id)
	for _, slot in ipairs(BeyConfig.LoadoutSlots) do
		if p.Equipped[slot] == id then
			return slot
		end
	end
	return nil
end

function Menus:_refreshLeft(p)
	local ok, stats = pcall(BeyConfig.ComputeStats, p.Equipped, p.Level)
	if ok then
		for stat, bar in pairs(self.statBars) do
			bar.fill.Size = UDim2.fromScale(math.clamp(stats[stat] / STAT_MAX, 0.02, 1), 1)
			bar.num.Text = ("%d"):format(stats[stat] + 0.5)
		end
	end
	self.levelLine.Text = ("YOUR BEY   ·   LEVEL %d"):format(p.Level)
	for slot, r in pairs(self.slotRows) do
		local item = BeyConfig.Items[p.Equipped[slot] or ""]
		r.name.Text = item and item.Name or "-"
		r.name.TextColor3 = item and (item.Color or BeyConfig.RarityColors[item.Rarity]) or C.muted
		r.row.BackgroundColor3 = BeyConfig.SlotKind(slot) == self.tab and Color3.fromRGB(30, 60, 90) or C.panel
	end
	local key = (p.Equipped.Layer or "") .. (p.Equipped.Disc or "") .. (p.Equipped.Driver or "")
	if key ~= self.beyKey then
		self.beyKey = key
		local okModel, model = pcall(BeyVisuals.Preview, { Layer = p.Equipped.Layer, Disc = p.Equipped.Disc, Driver = p.Equipped.Driver })
		self.beyCam = showModel(self.beyView, okModel and model or nil, 6.5, 0.45)
	end
end

function Menus:_card(item, order, p, owned)
	local rarityColor = BeyConfig.RarityColors[item.Rarity]
	local slot = equippedSlot(p, item.Id)
	local isSel = self.selected == item.Id
	local card = Ui.make("TextButton", {
		Name = item.Id,
		LayoutOrder = order,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		ZIndex = 8,
	}, self.grid)
	Ui.corner(card, 10)
	Ui.make("UIGradient", { Rotation = 90, Color = ColorSequence.new(darker(rarityColor, 0.45), darker(BG, 1.2)) }, card)
	Ui.stroke(card, (isSel or slot) and rarityColor or darker(rarityColor, 0.5), isSel and 3 or 2)
	local vp = Ui.make("ViewportFrame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 100), BackgroundTransparency = 1, LightColor = Color3.new(1, 1, 1), Ambient = Color3.fromRGB(160, 160, 180), ZIndex = 9 }, card)
	local model
	if item.Slot == "Special" then
		model = specialIcon(item)
		showModel(vp, model, 6, 0.1)
	elseif item.Slot == "Spirit" then
		model = Spirits.preview(item.Id)
		showModel(vp, model, 3.4, 0.25)
		if model then
			model:PivotTo(CFrame.new(0, -0.6, 0) * CFrame.Angles(0, math.rad(-35), 0))
		end
	else
		local ok, m = pcall(BeyVisuals.Preview, item.Id)
		showModel(vp, ok and m or nil, 5.5, 0.5)
	end
	if not owned then
		vp.ImageTransparency = 0.55
	end
	Ui.label(card, { Position = UDim2.fromOffset(8, 108), Size = UDim2.new(1, -16, 0, 18), Font = Enum.Font.GothamBold, TextSize = 14, Text = item.Name, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9 })
	Ui.label(card, { Position = UDim2.fromOffset(8, 126), Size = UDim2.new(1, -16, 0, 14), Font = Enum.Font.GothamBold, TextSize = 11, Text = "● " .. RARITY_LABEL[item.Rarity], TextColor3 = rarityColor, ZIndex = 9 })
	Ui.label(card, { Position = UDim2.fromOffset(8, 142), Size = UDim2.new(1, -16, 0, 14), TextSize = 11, Text = shortLine(item), TextColor3 = C.muted, ZIndex = 9 })
	local price = Progression.price(item.Id, BeyConfig.Items, GameConfig.Progression)
	local badgeText, badgeColor
	if slot then
		badgeText, badgeColor = (slot == "Special1" and "SLOT 1") or (slot == "Special2" and "SLOT 2") or "EQUIPPED", C.good
	elseif owned then
		badgeText, badgeColor = "OWNED", C.accent
	elseif price then
		badgeText, badgeColor = ("%d SHARDS"):format(price), C.gold
	else
		badgeText, badgeColor = "CRATE ONLY", C.muted
	end
	local badge = Ui.label(card, {
		Position = UDim2.fromOffset(8, 158),
		Size = UDim2.new(1, -16, 0, 14),
		Font = Enum.Font.GothamBlack,
		TextSize = 11,
		Text = badgeText,
		TextColor3 = badgeColor,
		ZIndex = 9,
	})
	if not owned and price and p.Shards < price then
		badge.TextTransparency = 0.4
	end
	card.Activated:Connect(function()
		self.selected = item.Id
		self:refresh()
	end)
	return card
end

function Menus:_details(p, owned)
	local item = self.selected and BeyConfig.Items[self.selected]
	self.actionA.Visible, self.actionB.Visible = false, false
	self.pending = {}
	if not item or BeyConfig.SlotKind(item.Slot) ~= self.tab then
		self.detName.Text = "Pick a card"
		self.detName.TextColor3 = C.text
		self.detText.Text = self.tab == "Special" and "Specials: keys 1 and 2 in battle. Each summons your spirit." or "Click a card to see it, buy it or equip it."
		return
	end
	self.detName.Text = item.Name .. "   ·   " .. RARITY_LABEL[item.Rarity]
	self.detName.TextColor3 = item.Color or BeyConfig.RarityColors[item.Rarity]
	self.detText.Text = describe(item)
	local price = Progression.price(item.Id, BeyConfig.Items, GameConfig.Progression)
	local function set(btn, text, color, action, slot)
		btn.Text = text
		btn.BackgroundColor3 = color
		btn.Visible = true
		self.pending[btn == self.actionA and "A" or "B"] = action and { action = action, slot = slot } or nil
	end
	if not owned[item.Id] then
		if price then
			set(self.actionA, ("Buy  ·  %d Shards"):format(price), p.Shards >= price and Color3.fromRGB(150, 105, 20) or C.panel, "buy")
		else
			set(self.actionA, "Crate only", C.panel, nil)
		end
	elseif item.Slot == "Special" then
		local s1, s2 = p.Equipped.Special1 == item.Id, p.Equipped.Special2 == item.Id
		set(self.actionA, s1 and "In slot 1" or "Equip to slot 1", s1 and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(30, 90, 120), (not s1) and "equip" or nil, "Special1")
		set(self.actionB, s2 and "In slot 2" or "Equip to slot 2", s2 and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(30, 90, 120), (not s2) and "equip" or nil, "Special2")
	elseif equippedSlot(p, item.Id) then
		set(self.actionA, "Equipped", Color3.fromRGB(30, 80, 50), nil)
	else
		set(self.actionA, "Equip", Color3.fromRGB(30, 90, 120), "equip")
	end
end

function Menus:_action(which)
	local a = self.pending and self.pending[which]
	if a and self.selected then
		self:act(a.action, self.selected, a.slot)
	end
end

function Menus:refresh()
	local p = self.profile
	if not p then
		self.status.Text = "Loading your profile..."
		return
	end
	self.shards.Text = ("%d Shards"):format(p.Shards)
	for key, tab in pairs(self.tabs) do
		tab.BackgroundColor3 = key == self.tab and Color3.fromRGB(30, 90, 120) or C.panel2
	end
	self:_refreshLeft(p)
	for _, child in ipairs(self.grid:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local owned = {}
	for _, id in ipairs(p.Owned) do
		owned[id] = true
	end
	local rows = {}
	for _, item in pairs(BeyConfig.Items) do
		if BeyConfig.SlotKind(item.Slot) == self.tab and (self.filter == "" or string.find(string.lower(item.Name), self.filter, 1, true)) then
			table.insert(rows, item)
		end
	end
	local order = {}
	for i, r in ipairs(BeyConfig.Rarities) do
		order[r] = i
	end
	table.sort(rows, function(a, b)
		local ea, eb = equippedSlot(p, a.Id) ~= nil, equippedSlot(p, b.Id) ~= nil
		if ea ~= eb then
			return ea
		end
		if order[a.Rarity] ~= order[b.Rarity] then
			return order[a.Rarity] < order[b.Rarity]
		end
		return a.Name < b.Name
	end)
	local first
	for i, item in ipairs(rows) do
		local card = self:_card(item, i, p, owned[item.Id] == true)
		first = first or card
	end
	self:_details(p, owned)
	if UserInputService.GamepadEnabled and first and not (GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.window)) then
		GuiService.SelectedObject = first
	end
end

function Menus:act(action, partId, slot)
	if self.busy then
		return
	end
	self.busy = true
	self.status.Text = "..."
	local ok, reply = pcall(function()
		return self.remotes.Workshop:InvokeServer({ action = action, part = partId, slot = slot })
	end)
	self.busy = false
	if not ok or type(reply) ~= "table" then
		self.status.Text = "The server didn't answer. Try again."
		return
	end
	if reply.profile then
		self.profile = reply.profile
	end
	if reply.ok then
		self.status.Text = action == "buy" and "Bought! Equip it to use it." or "Equipped for your next battle."
	else
		self.status.Text = reply.reason or "That didn't work."
	end
	self:refresh()
end

function Menus:open()
	if self.window.Visible then
		return
	end
	self.settingsWindow.Visible = false
	self.window.Visible = true
	self.hud:_panel(true)
	self.status.Text = ""
	self:refresh()
end

function Menus:close()
	if self.window.Visible then
		self.window.Visible = false
		self.hud:_panel(false)
		GuiService.SelectedObject = nil
	end
end

function Menus:openSettings()
	if self.settingsWindow.Visible then
		return
	end
	self:close()
	self.settingsWindow.Visible = true
	self.hud:_panel(true)
end

function Menus:closeSettings()
	if self.settingsWindow.Visible then
		self.settingsWindow.Visible = false
		self.hud:_panel(false)
		GuiService.SelectedObject = nil
	end
end

return Menus
]=====])
print('Spinforge installer part 8 of 9 done. Now run part 9.')

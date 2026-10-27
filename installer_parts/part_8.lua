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
install('SPS', '', 'ModuleScript', 'Menus', [=====[
--!nonstrict
-- Menus: the Workshop (buy parts with Shards, equip owned parts, see your bey's stats) and Settings.
-- Every action is sent to the server, which validates it (ownership, slot, price, not in battle) and replies
-- with the updated profile. The client never changes its own inventory.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local GameConfig = require(Shared.GameConfig)
local Progression = require(Shared.Core.Progression)
local Ui = require(script.Parent.Ui)
local C = Ui.C

local Menus = {}
Menus.__index = Menus

local RARITY_LABEL = { Common = "Common", Uncommon = "Uncommon", Rare = "Rare", Epic = "Epic", Legendary = "Legendary", UltraLegendary = "Ultra Legendary" }

function Menus.new(hud, remotes)
	local self = setmetatable({}, Menus)
	self.hud = hud
	self.remotes = remotes
	self.profile = nil
	self.slot = "Layer"
	self.busy = false

	-- Workshop window
	local w = Ui.panel(hud.gui, { Name = "Workshop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 470), Visible = false, ZIndex = 5 })
	Ui.pad(w, 14)
	Ui.label(w, { Size = UDim2.new(1, -40, 0, 26), Font = Enum.Font.GothamBlack, TextSize = 22, Text = "WORKSHOP", ZIndex = 6 })
	self.shards = Ui.label(w, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.gold, TextSize = 15, ZIndex = 6 })
	self.statsLine = Ui.label(w, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.muted, TextSize = 14, ZIndex = 6 })
	Ui.button(w, "X", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(32, 32), ZIndex = 6 }, function()
		self:close()
	end)
	self.tabs = {}
	for i, slot in ipairs(BeyConfig.Slots) do
		self.tabs[slot] = Ui.button(w, slot, { Position = UDim2.new((i - 1) / 3, i > 1 and 4 or 0, 0, 74), Size = UDim2.new(1 / 3, -6, 0, 30), TextSize = 15, ZIndex = 6 }, function()
			self.slot = slot
			self:refresh()
		end)
	end
	self.list = Ui.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 112),
		Size = UDim2.new(1, 0, 1, -140),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 6,
	}, w)
	Ui.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, self.list)
	self.status = Ui.label(w, { Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 20), TextSize = 14, TextColor3 = C.muted, ZIndex = 6 })
	self.window = w

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

local function statText(stats)
	return ("ATK %d   DEF %d   STA %d   BAL %d"):format(stats.Attack + 0.5, stats.Defense + 0.5, stats.Stamina + 0.5, stats.Balance + 0.5)
end

function Menus:refresh()
	local p = self.profile
	if not p then
		self.status.Text = "Loading your profile..."
		return
	end
	self.shards.Text = ("%d Shards   ·   Level %d"):format(p.Shards, p.Level)
	local ok, stats = pcall(BeyConfig.ComputeStats, p.Equipped, p.Level)
	self.statsLine.Text = ok and ("Your bey: " .. statText(stats)) or ""
	for slot, tab in pairs(self.tabs) do
		tab.BackgroundColor3 = slot == self.slot and Color3.fromRGB(30, 90, 120) or C.panel2
	end
	for _, child in ipairs(self.list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local owned = {}
	for _, id in ipairs(p.Owned) do
		owned[id] = true
	end
	local rows = {}
	for id, part in pairs(BeyConfig.Parts) do
		if part.Slot == self.slot then
			table.insert(rows, part)
		end
	end
	local order = {}
	for i, r in ipairs(BeyConfig.Rarities) do
		order[r] = i
	end
	table.sort(rows, function(a, b)
		if order[a.Rarity] ~= order[b.Rarity] then
			return order[a.Rarity] < order[b.Rarity]
		end
		return a.Name < b.Name
	end)
	local firstButton
	for i, part in ipairs(rows) do
		local row = Ui.make("Frame", { Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = C.panel2, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 6 }, self.list)
		Ui.corner(row, 8)
		Ui.make("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = BeyConfig.RarityColors[part.Rarity], BorderSizePixel = 0, ZIndex = 7 }, row)
		Ui.label(row, { Position = UDim2.fromOffset(14, 4), Size = UDim2.new(0.6, 0, 0, 22), Font = Enum.Font.GothamBold, Text = part.Name, ZIndex = 7 })
		Ui.label(row, {
			Position = UDim2.fromOffset(14, 26),
			Size = UDim2.new(0.62, 0, 0, 20),
			TextSize = 13,
			TextColor3 = C.muted,
			Text = RARITY_LABEL[part.Rarity] .. "   " .. statText(part.Stats),
			ZIndex = 7,
		})
		local text, action, color
		local price = Progression.price(part.Id, BeyConfig.Parts, GameConfig.Progression)
		if p.Equipped[part.Slot] == part.Id then
			text, action, color = "Equipped", nil, Color3.fromRGB(30, 80, 50)
		elseif owned[part.Id] then
			text, action, color = "Equip", "equip", Color3.fromRGB(30, 90, 120)
		elseif price then
			text, action, color = ("Buy  %d"):format(price), "buy", p.Shards >= price and Color3.fromRGB(110, 80, 20) or C.panel
		else
			text, action, color = "Crate only", nil, C.panel
		end
		local btn = Ui.button(row, text, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(120, 36), BackgroundColor3 = color, TextSize = 14, ZIndex = 7, Active = action ~= nil }, function()
			if action then
				self:act(action, part.Id)
			end
		end)
		firstButton = firstButton or btn
	end
	if UserInputService.GamepadEnabled and firstButton and not (GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.window)) then
		GuiService.SelectedObject = firstButton
	end
end

function Menus:act(action, partId)
	if self.busy then
		return
	end
	self.busy = true
	self.status.Text = "..."
	local ok, reply = pcall(function()
		return self.remotes.Workshop:InvokeServer({ action = action, part = partId })
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
		self.status.Text = action == "buy" and "Bought! Equip it to use it." or "Equipped. It's on your bey for the next battle."
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
install('SPS', '', 'ModuleScript', 'OnFootFallback', [=====[
--!nonstrict
-- OnFootFallback: a backup for walking around the hub, used ONLY if Roblox's own PlayerModule (the default
-- walking + camera scripts) never loads. That happened once in the owner's Studio, and without it you can't walk
-- or move the camera. Provides: WASD / left stick walking (camera-relative), Space / A to jump, and a follow
-- camera (hold right mouse or use the right stick to orbit). Steps aside whenever a bey is being controlled.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local OnFootFallback = {}

function OnFootFallback.start(ctx)
	local player = Players.LocalPlayer
	local hud, isBound = ctx.hud, ctx.isBound
	task.spawn(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if module then
			return -- the normal controls are there; nothing to do
		end
		warn("Spinforge: Roblox's PlayerModule didn't load; using backup on-foot controls.")
		hud:toast("Backup controls on: WASD to walk, Space to jump, hold right mouse to look")
		local camera = Workspace.CurrentCamera
		local yaw, pitch = 0, 0.35

		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or isBound() or UserInputService:GetFocusedTextBox() then
				return
			end
			if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.Jump = true
				end
			end
		end)

		RunService:BindToRenderStep("SpinforgeOnFoot", Enum.RenderPriority.Camera.Value + 2, function(dt)
			if isBound() then
				return
			end
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not (hum and root) then
				return
			end
			-- look around
			local orbiting = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) and not hud:mouseFree()
			UserInputService.MouseBehavior = orbiting and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
			if orbiting then
				local d = UserInputService:GetMouseDelta()
				yaw -= d.X * 0.005
				pitch = math.clamp(pitch + d.Y * 0.005, -0.2, 1.2)
			end
			for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
				if state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.15 then
					yaw -= state.Position.X * 2.5 * dt
					pitch = math.clamp(pitch - state.Position.Y * 1.5 * dt, -0.2, 1.2)
				end
			end
			-- walk (camera-relative)
			local x, z = 0, 0
			if not UserInputService:GetFocusedTextBox() and not hud:mouseFree() then
				local K = Enum.KeyCode
				x = (UserInputService:IsKeyDown(K.D) and 1 or 0) - (UserInputService:IsKeyDown(K.A) and 1 or 0)
				z = (UserInputService:IsKeyDown(K.S) and 1 or 0) - (UserInputService:IsKeyDown(K.W) and 1 or 0)
				for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
					if state.KeyCode == Enum.KeyCode.Thumbstick1 and state.Position.Magnitude > 0.15 then
						x += state.Position.X
						z -= state.Position.Y
					end
				end
			end
			local flat = CFrame.Angles(0, yaw, 0)
			local dir = flat.RightVector * x + flat.LookVector * -z
			hum:Move(dir.Magnitude > 1 and dir.Unit or dir, false)
			-- follow camera
			camera.CameraType = Enum.CameraType.Scriptable
			local focus = root.Position + Vector3.new(0, 2, 0)
			local eye = (CFrame.new(focus) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0) * CFrame.new(0, 0, 16)).Position
			camera.CFrame = CFrame.lookAt(eye, focus)
		end)
	end)
end

return OnFootFallback
]=====])
install('SPS', '', 'ModuleScript', 'Sounds', [=====[
--!nonstrict
-- Sounds: one place for every sound effect id. Empty ids are skipped (silent), so the game runs without any.
-- To add sound: in Studio open the Toolbox > Audio (or the Creator Store), pick Roblox-made or your own uploaded
-- sounds, copy the number from the asset URL and put "rbxassetid://<number>" here. Audio uploaded by other
-- people usually won't play in your game (Roblox audio privacy), so prefer Roblox's own SFX or your uploads.

local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.Ids = {
	Hit = "", -- metal clash, short
	HitHeavy = "", -- bigger clash with a ring (empowered hits)
	Launch = "", -- ripcord whoosh at LET IT RIP
	Special = "", -- whoosh / roar when a special is used
	Awaken = "", -- big roar + choir hit
	Quake = "", -- deep boom
	Guard = "", -- shield hum
	Win = "", -- victory sting
	Lose = "", -- defeat sting
}

-- Plays a sound once (2D, not positional). volume 0..1, pitch ~1.
function Sounds.play(name, volume, pitch)
	local id = Sounds.Ids[name]
	if not id or id == "" then
		return
	end
	local ok = pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume or 0.6
		s.PlaybackSpeed = pitch or 1
		s.Parent = SoundService
		s.Ended:Connect(function()
			s:Destroy()
		end)
		s:Play()
	end)
	return ok
end

return Sounds
]=====])
install('SPS', '', 'ModuleScript', 'SpecialsHud', [=====[
--!nonstrict
-- SpecialsHud: the battle bar for special moves and Awakening, plus the big title banners.
--   [1] Comet Drive  READY      [2] Iron Shell  6s        cards (tap/click to use too)
--   AWAKENING ███████░░░ 64%    full: "AWAKEN READY  [R]" pulsing; awake: "AWAKENED" draining
-- The server sends snapshots (cooldowns, meter) a few times a second; this only draws them.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local Ui = require(script.Parent.Ui)
local C = Ui.C

local SpecialsHud = {}
SpecialsHud.__index = SpecialsHud

local KIND_TEXT = { dash = "ATTACK", guard = "DEFENSE", heal = "RECOVER", quake = "SHOCKWAVE" }

local function keyText(i)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return ""
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return i == 1 and "X" or i == 2 and "Y" or "LB"
	end
	return i == 1 and "1" or i == 2 and "2" or "R"
end

function SpecialsHud.new(hud, onUse, onAwaken)
	local self = setmetatable({}, SpecialsHud)
	self.hud = hud
	local gui = hud.gui
	local root = Ui.make("Frame", {
		Name = "Specials",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.fromOffset(470, 92),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	self.root = root
	self.cards = {}
	for i = 1, 2 do
		local card = Ui.make("TextButton", {
			Position = UDim2.new((i - 1) * 0.5, i == 2 and 5 or 0, 0, 0),
			Size = UDim2.new(0.5, -5, 0, 52),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.08,
			AutoButtonColor = false,
			Text = "",
			Selectable = false,
		}, root)
		Ui.corner(card, 10)
		local stroke = Ui.stroke(card, C.line, 2)
		local fill = Ui.make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 3 }, card)
		Ui.corner(fill, 10)
		local key = Ui.label(card, {
			Position = UDim2.fromOffset(8, 10),
			Size = UDim2.fromOffset(32, 32),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.panel2,
			Font = Enum.Font.GothamBlack,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = keyText(i),
			ZIndex = 4,
		})
		Ui.corner(key, 7)
		local name = Ui.label(card, { Position = UDim2.fromOffset(48, 7), Size = UDim2.new(1, -54, 0, 20), Font = Enum.Font.GothamBlack, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
		local status = Ui.label(card, { Position = UDim2.fromOffset(48, 28), Size = UDim2.new(1, -54, 0, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.muted, ZIndex = 4 })
		card.Activated:Connect(function()
			onUse(i)
		end)
		self.cards[i] = { frame = card, stroke = stroke, fill = fill, key = key, name = name, status = status, ready = false }
	end
	local meterBack = Ui.make("Frame", { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0 }, root)
	Ui.corner(meterBack, 8)
	Ui.stroke(meterBack, C.line, 1)
	self.meterFill = Ui.make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.gold, BorderSizePixel = 0 }, meterBack)
	Ui.corner(self.meterFill, 8)
	Ui.make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 170, 40), Color3.fromRGB(255, 240, 150)) }, self.meterFill)
	self.meterText = Ui.make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		TextColor3 = C.text,
		TextStrokeTransparency = 0.4,
		Text = "AWAKENING 0%",
		AutoButtonColor = false,
		Selectable = false,
		ZIndex = 3,
	}, meterBack)
	self.meterText.Activated:Connect(onAwaken)
	self.meterStroke = meterBack:FindFirstChildOfClass("UIStroke")

	-- foe's awakening (thin bar under the foe's spin bar)
	self.foeMeter = Ui.bar(hud.battleFrame, { Position = UDim2.new(0.58, 0, 1, -4), Size = UDim2.new(0.42, 0, 0, 4) }, C.gold)

	-- big title banner (special names, AWAKENS!, WINNER)
	local banner = Ui.make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromOffset(900, 80),
		BackgroundTransparency = 1,
		Font = Enum.Font.LuckiestGuy,
		TextSize = 64,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
		Visible = false,
		ZIndex = 15,
	}, gui)
	self.bannerStroke = Ui.make("UIStroke", { Thickness = 4, Color = Color3.fromRGB(20, 10, 30), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, banner)
	self.bannerGradient = Ui.make("UIGradient", { Rotation = 90 }, banner)
	self.banner = banner
	self.bannerScale = Ui.make("UIScale", { Scale = 1 }, banner)

	-- screen tint for awakenings
	self.tint = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)
	return self
end

-- Called when a battle starts: which specials this player brought.
function SpecialsHud:setLoadout(ids)
	for i, card in ipairs(self.cards) do
		local def = BeyConfig.Specials[ids and ids[i] or ""]
		card.def = def
		card.name.Text = def and def.Name or "Empty"
		card.name.TextColor3 = def and def.Color or C.muted
		card.status.Text = def and KIND_TEXT[def.Kind] or ""
		card.key.Text = keyText(i)
		card.fill.Size = UDim2.fromScale(1, 1)
	end
	self.meterFill.Size = UDim2.fromScale(0, 1)
	self.meterText.Text = "AWAKENING 0%   [" .. keyText(3) .. "]"
	self.awakeUntil = nil
end

function SpecialsHud:show(visible)
	self.root.Visible = visible
	if not visible then
		self.tint.BackgroundTransparency = 1
	end
end

-- snap = { specials = { { left, cooldown } x2 }, meter = 0..1, awakened, awakenUsed } from the server.
function SpecialsHud:update(snap, foe)
	if type(snap) == "table" and type(snap.specials) == "table" then
		for i, card in ipairs(self.cards) do
			local s = snap.specials[i]
			if s and card.def then
				local left = tonumber(s.left) or 0
				local cd = math.max(tonumber(s.cooldown) or 1, 0.01)
				local ready = left <= 0.05
				card.fill.Size = UDim2.fromScale(ready and 0 or math.clamp(left / cd, 0, 1), 1)
				card.status.Text = ready and ("READY  ·  " .. KIND_TEXT[card.def.Kind]) or ("%.1fs"):format(left)
				card.status.TextColor3 = ready and C.good or C.muted
				card.stroke.Color = ready and card.def.Color or C.line
				if ready and not card.ready then
					card.frame.Size = UDim2.new(0.5, -5, 0, 58)
					TweenService:Create(card.frame, TweenInfo.new(0.2), { Size = UDim2.new(0.5, -5, 0, 52) }):Play()
				end
				card.ready = ready
			end
		end
		local m = math.clamp(tonumber(snap.meter) or 0, 0, 1)
		if snap.awakened then
			self.meterText.Text = "AWAKENED!"
			self.meterFill.Size = UDim2.fromScale(1, 1)
		elseif snap.awakenUsed then
			self.meterText.Text = "AWAKENING USED"
			self.meterFill.Size = UDim2.fromScale(0, 1)
		elseif m >= 1 then
			self.meterText.Text = "AWAKEN READY!   PRESS [" .. keyText(3) .. "]"
			self.meterFill.Size = UDim2.fromScale(1, 1)
			if self.meterStroke then
				self.meterStroke.Color = (math.floor(os.clock() * 3) % 2 == 0) and C.gold or C.line
				self.meterStroke.Thickness = 2
			end
		else
			self.meterText.Text = ("AWAKENING %d%%   [%s]"):format(math.floor(m * 100), keyText(3))
			self.meterFill.Size = UDim2.fromScale(m, 1)
			if self.meterStroke then
				self.meterStroke.Color = C.line
				self.meterStroke.Thickness = 1
			end
		end
	end
	if type(foe) == "table" then
		self.foeMeter.Size = UDim2.fromScale(foe.awakened and 1 or math.clamp(tonumber(foe.meter) or 0, 0, 1), 1)
	end
end

-- Pressed but refused (cooldown): shake the card.
function SpecialsHud:refused(i)
	local card = self.cards[i]
	if not card then
		return
	end
	local p = card.frame.Position
	card.frame.Position = p + UDim2.fromOffset(6, 0)
	TweenService:Create(card.frame, TweenInfo.new(0.15, Enum.EasingStyle.Elastic), { Position = p }):Play()
end

-- Big title text: special names, "... AWAKENS!", WINNER. small = the foe's (smaller, lower).
function SpecialsHud:showBanner(text, color, small)
	local b = self.banner
	b.Text = text
	b.TextSize = small and 40 or 64
	b.Position = UDim2.fromScale(0.5, small and 0.2 or 0.27)
	color = color or Color3.new(1, 1, 1)
	self.bannerGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	b.TextTransparency = 0
	self.bannerStroke.Transparency = 0
	b.Visible = true
	self.bannerScale.Scale = 1.6
	TweenService:Create(self.bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local token = {}
	self._banner = token
	task.delay(small and 1.0 or 1.3, function()
		if self._banner ~= token then
			return
		end
		TweenService:Create(b, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(self.bannerStroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		task.delay(0.32, function()
			if self._banner == token then
				b.Visible = false
			end
		end)
	end)
end

-- Coloured screen wash (awakening).
function SpecialsHud:wash(color, strength)
	self.tint.BackgroundColor3 = color
	self.tint.BackgroundTransparency = 1 - (strength or 0.35)
	TweenService:Create(self.tint, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

return SpecialsHud
]=====])
install('SPS', '', 'ModuleScript', 'Spirits', [=====[
--!nonstrict
-- Spirits: the giant glowing creature that appears when a bey uses a special or awakens. Client-only visuals.
--   summon(o)  o = { spirit = id, body = the bey's Body part, kind = "special" | "awaken", special = "dash" |
--              "guard" | "heal" | "quake", dir = Vector3 (toward the foe), face = function() -> Vector3 | nil
--              (a point to face while awakened), duration = seconds (awaken), big = bool (your own bey) }
-- The creature uses the Blender mesh from ReplicatedStorage.SpiritMeshes when it has been imported (README), and a
-- simple beast built from parts otherwise. Material ForceField (translucent shimmer) over a faint Neon core, so it
-- glows and you can still see the battle through it.
-- Unverified in Roblox: the look, the timing and the mesh orientation (the mesh should face -Z; see SPIN_FIX).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyConfig = require(Shared.BeyConfig)
local meshData = {}
do
	local mod = Shared:FindFirstChild("SpiritMeshData")
	if mod then
		local ok, data = pcall(require, mod)
		if ok and type(data) == "table" then
			meshData = data
		end
	end
end

local Spirits = {}
Spirits.__index = Spirits

local MAX_ACTIVE = 3
local SPIN_FIX = CFrame.new() -- extra rotation if the imported mesh doesn't face -Z (e.g. CFrame.Angles(0, math.pi, 0))
local SPECIAL_HEIGHT = 10 -- studs tall when it appears for a special (a bey is ~4 wide)
local AWAKEN_HEIGHT = 15
local SPECIAL_TIME = 1.4

function Spirits.new(effects, hooks)
	local self = setmetatable({}, Spirits)
	self.effects = effects
	self.hooks = hooks or {} -- { cinematic = function(duration, zoom), banner = function(text, color, small) }
	self.active = {}
	self.folder = Instance.new("Folder")
	self.folder.Name = "SpinforgeSpirits"
	self.folder.Parent = Workspace
	return self
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function easeOutBack(t)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function styled(p, color, material, transparency)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Material = material
	p.Color = color
	p.Transparency = transparency
	p:SetAttribute("BaseTransparency", transparency)
end

-- A beast from basic parts (used until the Blender meshes are imported). About 1 stud tall; scaled later.
local function fallbackBeast(color)
	local m = Instance.new("Model")
	local function part(shape, size, cf)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		styled(p, color, Enum.Material.ForceField, 0)
		p.Parent = m
		return p
	end
	local B, Cy = Enum.PartType.Ball, Enum.PartType.Cylinder
	local body = part(B, Vector3.new(0.55, 0.5, 1.1), CFrame.new(0, 0.62, 0.05))
	part(B, Vector3.new(0.42, 0.4, 0.5), CFrame.new(0, 0.86, -0.55)) -- head, facing -Z
	part(B, Vector3.new(0.2, 0.18, 0.3), CFrame.new(0, 0.8, -0.82)) -- snout
	for _, sx in ipairs({ -1, 1 }) do
		part(Enum.PartType.Block, Vector3.new(0.07, 0.32, 0.07), CFrame.new(0.14 * sx, 1.12, -0.5) * CFrame.Angles(math.rad(-25), 0, math.rad(-20 * sx))) -- horns
		part(Cy, Vector3.new(0.48, 0.13, 0.13), CFrame.new(0.17 * sx, 0.24, -0.32) * CFrame.Angles(0, 0, math.rad(90))) -- front legs
		part(Cy, Vector3.new(0.48, 0.14, 0.14), CFrame.new(0.17 * sx, 0.24, 0.4) * CFrame.Angles(0, 0, math.rad(90))) -- back legs
	end
	part(Enum.PartType.Block, Vector3.new(0.08, 0.08, 0.55), CFrame.new(0, 0.78, 0.78) * CFrame.Angles(math.rad(35), 0, 0)) -- tail
	m.PrimaryPart = body
	return m, Vector3.new(0.6, 1.25, 1.6)
end

-- Returns a Model (pivot at the creature's feet, facing -Z) and its unscaled size.
local function buildCreature(id, color)
	local folder = ReplicatedStorage:FindFirstChild("SpiritMeshes")
	local template = folder and folder:FindFirstChild(id, true)
	local size = meshData[id] and meshData[id].Size
	if template and template:IsA("MeshPart") and size then
		local m = Instance.new("Model")
		local shell = template:Clone()
		shell.Size = size
		shell.CFrame = CFrame.new(0, size.Y / 2, 0) * SPIN_FIX
		styled(shell, color, Enum.Material.ForceField, 0)
		shell.Parent = m
		local core = template:Clone()
		core.Size = size * 0.97
		core.CFrame = shell.CFrame
		styled(core, color, Enum.Material.Neon, 0.82)
		core.Parent = m
		local base = Instance.new("Part")
		base.Name = "Pivot"
		base.Size = Vector3.new(0.1, 0.1, 0.1)
		base.CFrame = CFrame.new()
		styled(base, color, Enum.Material.SmoothPlastic, 1)
		base.Parent = m
		m.PrimaryPart = base
		return m, size
	end
	local m, s = fallbackBeast(color)
	local base = Instance.new("Part")
	base.Name = "Pivot"
	base.Size = Vector3.new(0.1, 0.1, 0.1)
	base.CFrame = CFrame.new()
	styled(base, color, Enum.Material.SmoothPlastic, 1)
	base.Parent = m
	m.PrimaryPart = base
	return m, s
end

local function setAlpha(model, alpha)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local base = p:GetAttribute("BaseTransparency") or 0
			p.Transparency = base >= 1 and 1 or lerp(1, base, alpha)
		end
	end
end

local function addGlow(model, color, range)
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 0.5, 0)
	att.Parent = model.PrimaryPart
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 3
	light.Shadows = false
	light.Parent = model.PrimaryPart
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.5, 1.1)
	pe.Speed = NumberRange.new(4, 10)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rate = 40
	pe.Parent = att
	return light, pe
end

function Spirits:_retire(entry)
	if entry.conn then
		entry.conn:Disconnect()
	end
	if entry.model then
		entry.model:Destroy()
	end
	for _, extra in ipairs(entry.extras or {}) do
		extra:Destroy()
	end
	for i, e in ipairs(self.active) do
		if e == entry then
			table.remove(self.active, i)
			break
		end
	end
end

function Spirits:summon(o)
	local def = BeyConfig.Spirits[o.spirit]
	local body = o.body
	if not def or not body or not body.Parent then
		return
	end
	while #self.active >= MAX_ACTIVE do
		self:_retire(self.active[1])
	end
	local color = def.Color
	local awaken = o.kind == "awaken"
	local model, size = buildCreature(o.spirit, color)
	local height = awaken and AWAKEN_HEIGHT or SPECIAL_HEIGHT * (o.big and 1 or 0.9)
	local scale = height / math.max(size.Y, 0.01)
	model.Name = o.spirit
	model.Parent = self.folder
	local light = addGlow(model, color, awaken and 40 or 28)
	local entry = { model = model, extras = {} }
	table.insert(self.active, entry)

	local dir = o.dir
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	local start = os.clock()
	local total = awaken and (o.duration or 10) + 1.4 or SPECIAL_TIME
	local smoothPos = body.Position

	-- the opening flourish
	local ground = body.Position - Vector3.new(0, 1.8, 0)
	self.effects:burst(ground, color, awaken and 26 or 16)
	if awaken then
		entry.extras = self:_sigil(ground, color)
	end
	if self.hooks.banner then
		local name = BeyConfig.Specials[o.id or ""] and BeyConfig.Specials[o.id].Name or def.Name
		local text = awaken and (string.upper(def.Name) .. " AWAKENS!") or (string.upper(name) .. "!")
		self.hooks.banner(text, color, not o.big)
	end
	if o.big and self.hooks.cinematic then
		self.hooks.cinematic(awaken and 1.6 or 0.9, awaken and 0.5 or 0.7)
	end

	entry.conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - start
		if t >= total or not body.Parent then
			self:_retire(entry)
			return
		end
		smoothPos = smoothPos:Lerp(body.Position, 1 - math.exp(-12 * dt))
		local base = smoothPos - Vector3.new(0, 1.8, 0)
		local facing = dir
		local s, alpha, offset = 1, 1, Vector3.zero
		if awaken then
			local target = o.face and o.face()
			if typeof(target) == "Vector3" then
				local d = Vector3.new(target.X - smoothPos.X, 0, target.Z - smoothPos.Z)
				if d.Magnitude > 0.5 then
					facing = d.Unit
					dir = facing
				end
			end
			local rise = math.clamp(t / 0.6, 0, 1)
			offset = Vector3.new(0, -height * (1 - easeOutBack(rise)) * 0.6, 0) - facing * 2.5
			alpha = t < 1.6 and 1 or 0.6 -- full for the reveal, then lighter so the fight stays readable
			if t > total - 0.6 then
				alpha = 0.6 * (total - t) / 0.6
			end
			offset += Vector3.new(0, math.sin(t * 2.2) * 0.4, 0)
		else
			local k = o.special
			if t < 0.22 then
				local a = t / 0.22
				s = lerp(0.3, 1, easeOutBack(a))
				alpha = a
			elseif t < 0.5 then
				offset = Vector3.new(0, math.sin((t - 0.22) * 18) * 0.3, 0)
			elseif t < 1.05 then
				local a = (t - 0.5) / 0.55
				if k == "dash" or k == "quake" then
					offset = dir * (a * a * 14) -- lunges at the foe
					if k == "quake" then
						offset += Vector3.new(0, math.sin(a * math.pi) * 4, 0)
					end
				elseif k == "heal" then
					offset = Vector3.new(0, a * 4, 0)
				else -- guard: rears up and circles the bey
					facing = (CFrame.Angles(0, a * math.pi * 0.8, 0) * dir)
				end
			else
				local a = (t - 1.05) / (SPECIAL_TIME - 1.05)
				s = 1 + a * 0.15
				alpha = 1 - a
				offset = (k == "dash" or k == "quake") and dir * 14 or Vector3.zero
			end
			offset -= dir * 2
		end
		local pos = base + offset
		model:PivotTo(CFrame.lookAt(pos, pos + facing))
		pcall(function()
			model:ScaleTo(scale * s)
		end)
		setAlpha(model, alpha)
		light.Brightness = 3 * alpha
	end)
end

-- Awakening: a glowing sigil on the floor and a pillar of light. Returns the parts (removed with the creature).
function Spirits:_sigil(ground, color)
	local parts = {}
	local function neon(shape, size, cf, transparency)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		styled(p, color, Enum.Material.Neon, transparency)
		p.Parent = self.folder
		table.insert(parts, p)
		return p
	end
	local ring = neon(Enum.PartType.Cylinder, Vector3.new(0.15, 26, 26), CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)), 0.35)
	local inner = neon(Enum.PartType.Cylinder, Vector3.new(0.16, 18, 18), CFrame.new(ground + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.75)
	local spokes = {}
	for i = 0, 5 do
		local a = i * math.pi / 3
		table.insert(spokes, neon(Enum.PartType.Block, Vector3.new(0.6, 0.18, 24), CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, a, 0), 0.45))
	end
	local pillar = neon(Enum.PartType.Cylinder, Vector3.new(80, 5, 5), CFrame.new(ground + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.25)
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 1.6 or not ring.Parent then
			conn:Disconnect()
			for _, p in ipairs(parts) do
				p:Destroy()
			end
			return
		end
		local spin = CFrame.Angles(0, t * 2.5, 0)
		for i, p in ipairs(spokes) do
			p.CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * spin * CFrame.Angles(0, (i - 1) * math.pi / 3, 0)
			p.Transparency = lerp(0.45, 1, math.clamp((t - 0.9) / 0.7, 0, 1))
		end
		ring.Transparency = lerp(0.35, 1, math.clamp((t - 0.9) / 0.7, 0, 1))
		inner.Transparency = lerp(0.75, 1, math.clamp((t - 0.9) / 0.7, 0, 1))
		local w = 5 + t * 6
		pillar.Size = Vector3.new(80, w, w)
		pillar.Transparency = lerp(0.25, 1, math.clamp(t / 1.2, 0, 1))
	end)
	return parts
end

function Spirits:clear()
	while #self.active > 0 do
		self:_retire(self.active[1])
	end
end

return Spirits
]=====])
print('Spinforge installer part 8 of 9 done. Now run part 9.')

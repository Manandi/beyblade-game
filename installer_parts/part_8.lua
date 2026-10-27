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
install('SPS', '', 'ModuleScript', 'Tutorial', [=====[
--!nonstrict
-- Tutorial: short contextual hints shown while you control a bey, until you've done each thing once:
-- drive, lean in, brake, launch off the lip, slam. Each hint advances when the controller reports the action.
-- Finishing it tells the server (saved in Settings.TutorialDone). Settings can replay it.

local UserInputService = game:GetService("UserInputService")

local Tutorial = {}
Tutorial.__index = Tutorial

local function steps()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local pad = UserInputService.GamepadEnabled
	local aim = touch and "Drag on the right side of the screen" or pad and "Push the right stick" or "Move the mouse"
	return {
		{ id = "moved", title = "Drive", body = touch and "Use the left thumbstick to drive. Your bey goes where the camera faces." or pad and "Left stick drives. Your bey goes where the camera faces." or "W A S D to drive. Your bey goes where the camera faces." },
		{ id = "leaned", title = "Lean in for speed", body = aim .. " DOWN to tip the nose down. You go faster." },
		{ id = "braked", title = "Lean back to brake", body = aim .. " UP to tip the nose back. You slow down and stop." },
		{ id = "launched", title = "Launch off the lip", body = "Drive up the stadium wall and lift the nose just as you reach the steep lip. Nose up = higher." },
		{ id = "slammed", title = "Slam", body = (touch and "Tap SLAM" or pad and "Press the right trigger" or "Click") .. " while in the air to dive down. Land it next to your opponent." },
	}
end

function Tutorial.new(hud, remotes)
	local self = setmetatable({}, Tutorial)
	self.hud = hud
	self.remotes = remotes
	self.done = true -- until the profile says otherwise
	self.index = 1
	self.active = false
	self.steps = steps()
	return self
end

function Tutorial:setProfile(p)
	local wasDone = self.done
	self.done = p.Settings.TutorialDone
	if wasDone and not self.done then
		self.index = 1
		self.steps = steps()
	end
	self:_render()
end

-- Shown only while the player controls a bey.
function Tutorial:setActive(active)
	self.active = active
	self:_render()
end

function Tutorial:signal(id)
	if self.done or not self.active then
		return
	end
	local step = self.steps[self.index]
	if step and step.id == id then
		self.index += 1
		if self.index > #self.steps then
			self.done = true
			self.remotes.Request:FireServer({ action = "tutorialDone" })
			self.hud:hideHint()
			self.hud:toast("Tutorial complete! Challenge the villain from the hub.")
			return
		end
		self:_render()
	end
end

function Tutorial:_render()
	local step = self.steps[self.index]
	if self.done or not self.active or not step then
		self.hud:hideHint()
		return
	end
	self.hud:showHint(("TUTORIAL %d/%d"):format(self.index, #self.steps), step.title, step.body)
end

return Tutorial
]=====])
install('SPS', '', 'ModuleScript', 'Ui', [=====[
--!nonstrict
-- Ui: small helpers so every screen shares one look (dark panels, cyan accent, rarity colours).

local Ui = {}

Ui.C = {
	panel = Color3.fromRGB(14, 18, 28),
	panel2 = Color3.fromRGB(24, 30, 44),
	line = Color3.fromRGB(52, 62, 84),
	text = Color3.fromRGB(232, 238, 248),
	muted = Color3.fromRGB(150, 162, 186),
	accent = Color3.fromRGB(90, 200, 255),
	good = Color3.fromRGB(110, 220, 140),
	bad = Color3.fromRGB(255, 96, 96),
	warn = Color3.fromRGB(255, 186, 72),
	gold = Color3.fromRGB(255, 210, 110),
}

-- Ui.make("TextLabel", { Size = ..., Text = ... }, parent)
function Ui.make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(parent, px)
	return Ui.make("UICorner", { CornerRadius = UDim.new(0, px or 8) }, parent)
end

function Ui.stroke(parent, color, thickness)
	return Ui.make("UIStroke", { Color = color or Ui.C.line, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function Ui.pad(parent, px)
	return Ui.make("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	}, parent)
end

function Ui.panel(parent, props)
	local f = Ui.make("Frame", { BackgroundColor3 = Ui.C.panel, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, nil)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	Ui.corner(f, 10)
	Ui.stroke(f)
	f.Parent = parent
	return f
end

function Ui.label(parent, props)
	local l = Ui.make("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = Ui.C.text,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, nil)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function Ui.button(parent, text, props, onClick)
	local b = Ui.make("TextButton", {
		BackgroundColor3 = Ui.C.panel2,
		TextColor3 = Ui.C.text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Text = text,
		AutoButtonColor = true,
		Selectable = true,
	}, nil)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Ui.corner(b, 8)
	Ui.stroke(b, Ui.C.line)
	b.Parent = parent
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

-- A horizontal bar: returns the fill frame (set fill.Size = UDim2.fromScale(x, 1)).
function Ui.bar(parent, props, color)
	local back = Ui.make("Frame", { BackgroundColor3 = Ui.C.panel2, BorderSizePixel = 0 }, nil)
	for k, v in pairs(props or {}) do
		back[k] = v
	end
	Ui.corner(back, 6)
	back.Parent = parent
	local fill = Ui.make("Frame", { BackgroundColor3 = color or Ui.C.accent, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, back)
	Ui.corner(fill, 6)
	return fill, back
end

return Ui
]=====])
print('Spinforge installer part 8 of 8 done. Press Play.')

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
install('SPS', '', 'ModuleScript', 'Hud', [=====[
--!nonstrict
-- Hud: everything drawn on screen during play. Created once per client (ResetOnSpawn off), so respawns and
-- re-binds never duplicate it. Other client modules call its methods; it holds no game rules.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent.Ui)
local C = Ui.C

local Hud = {}
Hud.__index = Hud

local REASON = {
	stopped = "stopped spinning",
	ringout = "was knocked out of the stadium",
	time = "time ran out: more spin left wins",
	both = "both beys went down together",
	left = "the battle was abandoned",
}

function Hud.new(player)
	local self = setmetatable({}, Hud)
	self.player = player
	self.panelsOpen = 0
	local gui = Ui.make("ScreenGui", { Name = "SpinforgeHud", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, nil)
	self.gui = gui
	local scale = Ui.make("UIScale", { Scale = 1 }, gui)
	local function rescale()
		local cam = Workspace.CurrentCamera
		local w = cam and cam.ViewportSize.X or 1000
		scale.Scale = math.clamp(w / 1100, 0.62, 1)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- flash overlay (behind everything else)
	self.flashFrame = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bad, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0 }, gui)

	-- profile chip (top left)
	local prof = Ui.panel(gui, { Name = "Profile", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(250, 92) })
	Ui.pad(prof, 10)
	self.levelLabel = Ui.label(prof, { Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamBold, TextSize = 18, Text = "Loading..." })
	self.xpFill = Ui.bar(prof, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 8) }, C.accent)
	self.shardLabel = Ui.label(prof, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.gold, TextSize = 15 })
	self.workshopBtn = Ui.button(prof, "Workshop", { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(0.5, -4, 0, 26), TextSize = 14 })
	self.settingsBtn = Ui.button(prof, "Settings", { Position = UDim2.new(0.5, 4, 0, 58), Size = UDim2.new(0.5, -4, 0, 26), TextSize = 14 })
	self.profileFrame = prof

	-- save banner
	self.saveBanner = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(520, 26),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(90, 50, 10),
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Visible = false,
	})
	Ui.corner(self.saveBanner, 6)

	-- battle bar (top centre)
	local bb = Ui.panel(gui, { Name = "Battle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 38), Size = UDim2.fromOffset(620, 74), Visible = false })
	Ui.pad(bb, 10)
	self.youName = Ui.label(bb, { Size = UDim2.new(0.42, 0, 0, 18), Font = Enum.Font.GothamBold, TextSize = 15, Text = "YOU" })
	self.youFill, self.youBack = Ui.bar(bb, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(0.42, 0, 0, 16) }, C.accent)
	self.youText = Ui.label(bb, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(0.42, 0, 0, 16), TextSize = 13, TextColor3 = C.muted })
	self.foeName = Ui.label(bb, { Position = UDim2.new(0.58, 0, 0, 0), Size = UDim2.new(0.42, 0, 0, 18), Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right })
	self.foeFill, self.foeBack = Ui.bar(bb, { Position = UDim2.new(0.58, 0, 0, 22), Size = UDim2.new(0.42, 0, 0, 16) }, C.bad)
	self.foeText = Ui.label(bb, { Position = UDim2.new(0.58, 0, 0, 40), Size = UDim2.new(0.42, 0, 0, 16), TextSize = 13, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Right })
	self.timer = Ui.label(bb, { Position = UDim2.new(0.42, 0, 0, 4), Size = UDim2.new(0.16, 0, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
	self.diffLabel = Ui.label(bb, { Position = UDim2.new(0.42, 0, 0, 36), Size = UDim2.new(0.16, 0, 0, 16), TextSize = 12, TextColor3 = C.warn, TextXAlignment = Enum.TextXAlignment.Center })
	self.battleFrame = bb

	-- big centre text (countdown, GO, queue)
	self.center = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(600, 90),
		Font = Enum.Font.GothamBlack,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Text = "",
	})

	-- slam readiness + low spin (bottom centre)
	local sl = Ui.panel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(220, 34), Visible = false })
	self.slamFill = Ui.bar(sl, { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12) }, C.warn)
	self.slamText = Ui.label(sl, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, TextSize = 14, Text = "SLAM", ZIndex = 3 })
	self.slamFrame = sl
	self.lowSpin = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -58),
		Size = UDim2.fromOffset(300, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = C.bad,
		Text = "LOW SPIN",
		Visible = false,
	})

	-- mode panel (bottom left): practice info / forfeit
	local mp = Ui.panel(gui, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.fromOffset(250, 76), Visible = false })
	Ui.pad(mp, 10)
	self.modeTitle = Ui.label(mp, { Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.GothamBold, TextSize = 15 })
	self.modeHint = Ui.label(mp, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = C.muted })
	self.modeBtn = Ui.button(mp, "Leave", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 26), TextSize = 14 })
	self.modeFrame = mp

	-- result panel
	local rp = Ui.panel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 280), Visible = false, ZIndex = 10 })
	Ui.pad(rp, 18)
	self.resultTitle = Ui.label(rp, { Size = UDim2.new(1, 0, 0, 44), Font = Enum.Font.GothamBlack, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.resultReason = Ui.label(rp, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.resultReward = Ui.label(rp, { Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 48), TextColor3 = C.gold, Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.resultNext = Ui.label(rp, { Position = UDim2.fromOffset(0, 132), Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.warn, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.rematchBtn = Ui.button(rp, "Rematch", { Position = UDim2.new(0, 0, 1, -66), Size = UDim2.new(0.5, -6, 0, 44), BackgroundColor3 = Color3.fromRGB(30, 90, 120), ZIndex = 11 })
	self.leaveBtn = Ui.button(rp, "Back to hub", { Position = UDim2.new(0.5, 6, 1, -66), Size = UDim2.new(0.5, -6, 0, 44), ZIndex = 11 })
	self.resultClose = Ui.label(rp, { Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.muted, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 })
	self.resultFrame = rp

	-- toasts (top centre, under the battle bar)
	self.toastLabel = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(560, 30),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = C.panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Visible = false,
	})
	Ui.corner(self.toastLabel, 8)

	-- tutorial hint card (right side)
	local hint = Ui.panel(gui, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(280, 104), Visible = false })
	Ui.pad(hint, 12)
	self.hintStep = Ui.label(hint, { Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = C.accent, Font = Enum.Font.GothamBold })
	self.hintTitle = Ui.label(hint, { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.GothamBold, TextSize = 18 })
	self.hintBody = Ui.label(hint, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 40), TextSize = 14, TextColor3 = C.muted, TextYAlignment = Enum.TextYAlignment.Top })
	self.hintFrame = hint

	-- touch buttons (shown by the controller while a bey is bound on touch devices)
	self.touchSlam = Ui.button(gui, "SLAM", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -150), Size = UDim2.fromOffset(96, 96), BackgroundColor3 = Color3.fromRGB(150, 50, 50), TextSize = 20, Visible = false })
	Ui.corner(self.touchSlam, 48)
	self.touchJump = Ui.button(gui, "JUMP", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -132, 1, -60), Size = UDim2.fromOffset(80, 80), BackgroundColor3 = Color3.fromRGB(40, 90, 130), TextSize = 18, Visible = false })
	Ui.corner(self.touchJump, 40)

	-- diagnostics (F6) and errors
	self.diag = Ui.label(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(300, 150),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.new(0, 0, 0),
		Font = Enum.Font.Code,
		TextSize = 13,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
	})
	self.errorLabel = Ui.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 120),
		BackgroundTransparency = 0.05,
		BackgroundColor3 = Color3.fromRGB(70, 20, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Visible = false,
		ZIndex = 20,
	})
	Ui.corner(self.errorLabel, 10)

	gui.Parent = player:WaitForChild("PlayerGui")
	return self
end

-------------------------------------------------------------------------------- profile, mode

function Hud:setProfile(p)
	self.levelLabel.Text = ("Level %d"):format(p.Level)
	self.shardLabel.Text = ("%d Shards   ·   %dW %dL %dD"):format(p.Shards, p.Record.Wins, p.Record.Losses, p.Record.Draws)
	if p.XPNext and p.XPNext > p.XPThis then
		self.xpFill.Size = UDim2.fromScale(math.clamp((p.XP - p.XPThis) / (p.XPNext - p.XPThis), 0, 1), 1)
	else
		self.xpFill.Size = UDim2.fromScale(1, 1)
	end
	local banner = {
		nosave = "Progress is NOT being saved this session (no DataStore access).",
		locked = "Your save is open on another server: progress here is NOT saved.",
		newer = "Your save is from a newer version: progress here is NOT saved.",
		loading = "Loading your profile...",
	}
	self.saveBanner.Text = banner[p.SaveStatus] or ""
	self.saveBanner.Visible = banner[p.SaveStatus] ~= nil
end

-- mode: "OnFoot" | "Practice" | "Battle"
function Hud:setMode(mode, onLeave)
	self.profileFrame.Visible = mode == "OnFoot"
	self.slamFrame.Visible = mode ~= "OnFoot"
	if mode == "Practice" then
		self.modeTitle.Text = "PRACTICE"
		self.modeHint.Text = "R: reset bey   ·   Q: back to hub"
		self.modeBtn.Text = "Back to hub"
		self.modeFrame.Visible = true
	elseif mode == "Battle" then
		self.modeTitle.Text = "BATTLE"
		self.modeHint.Text = "Knock it out or outlast it"
		self.modeBtn.Text = "Forfeit"
		self.modeFrame.Visible = true
	else
		self.modeFrame.Visible = false
		self.lowSpin.Visible = false
	end
	self.onModeButton = onLeave
end

-------------------------------------------------------------------------------- battle

function Hud:countdown(seconds, foe, difficulty)
	self.battleFrame.Visible = true
	self.youName.Text = "YOU"
	self.foeName.Text = string.upper(foe or "Villain")
	self.diffLabel.Text = string.upper(difficulty or "")
	self.timer.Text = ""
	task.spawn(function()
		for i = seconds, 1, -1 do
			self.center.TextColor3 = C.text
			self.center.Text = tostring(i)
			task.wait(1)
		end
	end)
end

function Hud:started()
	self.center.TextColor3 = C.good
	self.center.Text = "GO!"
	task.delay(0.8, function()
		if self.center.Text == "GO!" then
			self.center.Text = ""
		end
	end)
end

-- Called every frame by Main while a battle is shown.
function Hud:updateBattle(youSpin, youMax, foeSpin, foeMax, endsAt, state)
	local yf = youMax > 0 and math.clamp(youSpin / youMax, 0, 1) or 0
	local ff = foeMax > 0 and math.clamp(foeSpin / foeMax, 0, 1) or 0
	self.youFill.Size = UDim2.fromScale(yf, 1)
	self.foeFill.Size = UDim2.fromScale(ff, 1)
	self.youText.Text = ("%d / %d spin"):format(math.ceil(youSpin), math.ceil(youMax))
	self.foeText.Text = ("%d / %d spin"):format(math.ceil(foeSpin), math.ceil(foeMax))
	if state == "active" and endsAt and endsAt > 0 then
		local left = math.max(0, endsAt - Workspace:GetServerTimeNow())
		self.timer.Text = ("%d"):format(math.ceil(left))
		self.timer.TextColor3 = left < 10 and C.bad or C.text
	end
	local low = state == "active" and yf < 0.25
	self.lowSpin.Visible = low
	if low then
		self.youFill.BackgroundColor3 = (math.floor(os.clock() * 4) % 2 == 0) and C.bad or C.accent
	else
		self.youFill.BackgroundColor3 = C.accent
	end
end

function Hud:setSlam(readyFraction, diving)
	if diving then
		self.slamText.Text = "SLAMMING"
		self.slamFill.Size = UDim2.fromScale(1, 1)
	elseif readyFraction >= 1 then
		self.slamText.Text = "SLAM READY (in the air)"
		self.slamFill.Size = UDim2.fromScale(1, 1)
	else
		self.slamText.Text = "SLAM"
		self.slamFill.Size = UDim2.fromScale(math.clamp(readyFraction, 0, 1), 1)
	end
end

function Hud:flash(color, strength)
	self.flashFrame.BackgroundColor3 = color
	self.flashFrame.BackgroundTransparency = 1 - 0.35 * math.clamp(strength or 1, 0, 1)
	TweenService:Create(self.flashFrame, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
end

-- Floating number next to a bar ("-12" in red under yours, "-8" in white under theirs).
function Hud:popup(text, color, onFoe)
	local l = Ui.label(self.battleFrame, {
		Position = onFoe and UDim2.new(0.75, 0, 1, 2) or UDim2.new(0.12, 0, 1, 2),
		Size = UDim2.fromOffset(80, 24),
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Text = text,
	})
	local tween = TweenService:Create(l, TweenInfo.new(0.7), { Position = l.Position + UDim2.fromOffset(0, 26), TextTransparency = 1, TextStrokeTransparency = 1 })
	tween.Completed:Connect(function()
		l:Destroy()
	end)
	tween:Play()
end

function Hud:showResult(e, onRematch, onLeave)
	local title = { win = "VICTORY", loss = "DEFEAT", draw = "DRAW" }
	self.resultTitle.Text = title[e.outcome] or "FINISHED"
	self.resultTitle.TextColor3 = e.outcome == "win" and C.good or e.outcome == "loss" and C.bad or C.warn
	local who = e.outcome == "win" and "Your opponent" or e.outcome == "loss" and "Your bey" or ""
	local reason = REASON[e.reason] or e.reason or ""
	if e.reason == "time" or e.reason == "both" or e.reason == "left" then
		self.resultReason.Text = reason:sub(1, 1):upper() .. reason:sub(2)
	else
		self.resultReason.Text = who .. " " .. reason
	end
	if e.reward and (e.reward.XP > 0 or e.reward.Shards > 0) then
		self.resultReward.Text = ("+%d XP    +%d Shards"):format(e.reward.XP, e.reward.Shards) .. (e.levelUp and ("\nLEVEL UP! Level " .. e.levelUp) or "")
	elseif e.reward then
		self.resultReward.Text = e.reason == "left" and "No reward for forfeiting" or "Too quick for a reward: last 20 seconds to earn one"
	else
		self.resultReward.Text = ""
	end
	self.resultNext.Text = e.next and ("Next opponent difficulty: " .. e.next) or ""
	self.lowSpin.Visible = false
	self.resultFrame.Visible = true
	self:_panel(true)
	if self._rc then
		self._rc:Disconnect()
		self._lc:Disconnect()
	end
	self._rc = self.rematchBtn.Activated:Connect(onRematch)
	self._lc = self.leaveBtn.Activated:Connect(onLeave)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = self.rematchBtn
	end
	local closes = os.clock() + (e.closesIn or 45)
	task.spawn(function()
		while self.resultFrame.Visible do
			self.resultClose.Text = ("Returns to the hub in %ds"):format(math.max(0, math.ceil(closes - os.clock())))
			task.wait(0.25)
		end
	end)
end

function Hud:closeBattle()
	if self.resultFrame.Visible then
		self.resultFrame.Visible = false
		self:_panel(false)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.gui) then
			GuiService.SelectedObject = nil
		end
	end
	self.battleFrame.Visible = false
	self.center.Text = ""
	self.lowSpin.Visible = false
end

function Hud:queued(position)
	self.center.TextColor3 = C.warn
	self.center.TextSize = 30
	self.center.Text = ("Arena busy: you're #%d in line"):format(position or 1)
	task.delay(3, function()
		self.center.TextSize = 64
		if self.center.Text:find("Arena busy") then
			self.center.Text = ""
		end
	end)
end

-------------------------------------------------------------------------------- misc

function Hud:toast(text, color)
	self.toastLabel.Text = text
	self.toastLabel.TextColor3 = color or C.text
	self.toastLabel.Visible = true
	local token = {}
	self._toast = token
	task.delay(3, function()
		if self._toast == token then
			self.toastLabel.Visible = false
		end
	end)
end

function Hud:showHint(step, title, body)
	self.hintStep.Text = step or ""
	self.hintTitle.Text = title
	self.hintBody.Text = body
	self.hintFrame.Visible = true
end

function Hud:hideHint()
	self.hintFrame.Visible = false
end

function Hud:showTouchButtons(show)
	local touch = UserInputService.TouchEnabled
	self.touchSlam.Visible = show and touch
	self.touchJump.Visible = show and touch
end

function Hud:setDiag(text)
	self.diag.Visible = text ~= nil
	if text then
		self.diag.Text = text
	end
end

function Hud:showError(text)
	self.errorLabel.Text = "Spinforge couldn't start:\n" .. text
	self.errorLabel.Visible = true
end

-- Counts open panels so the bey controller frees the mouse while any is open.
function Hud:_panel(open)
	self.panelsOpen = math.max(0, self.panelsOpen + (open and 1 or -1))
end

function Hud:mouseFree()
	return self.panelsOpen > 0
end

return Hud
]=====])
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
	elseif e.kind == "started" then
		hud:started()
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
]=====])
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
print('Spinforge installer part 6 of 7 done. Now run part 7.')

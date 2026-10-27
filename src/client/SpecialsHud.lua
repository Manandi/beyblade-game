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

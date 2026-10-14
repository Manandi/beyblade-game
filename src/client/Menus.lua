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

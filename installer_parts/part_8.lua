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
print('Spinforge installer part 8 of 9 done. Now run part 9.')

-- A deliberately small fake of the Roblox engine, so the real server AND client scripts can run end to end
-- under the plain `luau` CLI. It covers the instance tree, attributes, events, a virtual clock with task.*,
-- CFrame maths, remotes (delivered instantly, one process), a flat-floor raycast, and an in-memory DataStore.
-- It does NOT simulate physics, collisions, rendering, replication or networking. Passing here means the scripts
-- start, wire up and run their logic without errors; it says nothing about game feel. Used by smoke.test.luau.

Mock = { now = 0, threads = {}, warnings = {}, printed = {}, errors = {}, keys = {}, sent = {} }

-------------------------------------------------------------------------------- scheduler (virtual time)

local function resumeThread(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(Mock.errors, tostring(err) .. "\n" .. debug.traceback(co))
	end
end

task = {}
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	resumeThread(co, ...)
	return co
end
function task.defer(f, ...)
	return task.spawn(f, ...)
end
function task.delay(t, f, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		f(table.unpack(args, 1, args.n))
	end)
	table.insert(Mock.threads, { at = Mock.now + (t or 0), co = co })
	return co
end
function task.wait(t)
	t = t or 0
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		Mock.now += t -- called from the main test thread: just move time on
		return t
	end
	table.insert(Mock.threads, { at = Mock.now + t, co = co })
	coroutine.yield()
	return t
end

local realOs = os
os = setmetatable({
	clock = function()
		return Mock.now
	end,
	time = function()
		return 1700000000 + math.floor(Mock.now)
	end,
}, { __index = realOs })

-------------------------------------------------------------------------------- signals

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
	local h = { fn = fn, connected = true }
	table.insert(self.handlers, h)
	return {
		Disconnect = function()
			h.connected = false
		end,
		Connected = true,
	}
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Fire(...)
	for _, h in ipairs(table.clone(self.handlers)) do
		if h.connected then
			task.spawn(h.fn, ...)
		end
	end
end
function Signal:Wait()
	local co = coroutine.running()
	self:Once(function(...)
		resumeThread(co, ...)
	end)
	return coroutine.yield()
end
Mock.Signal = Signal

-------------------------------------------------------------------------------- datatypes

-- Vector3 comes from stubs.luau.
local V3new = Vector3.new

Vector2 = { new = function(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, {
		__index = function(v, k)
			if k == "Magnitude" then
				return math.sqrt(v.X * v.X + v.Y * v.Y)
			elseif k == "Unit" then
				local m = math.sqrt(v.X * v.X + v.Y * v.Y)
				return Vector2.new(v.X / m, v.Y / m)
			end
		end,
		__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end,
		__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end,
		__div = function(a, b) return Vector2.new(a.X / b, a.Y / b) end,
		__mul = function(a, b) return Vector2.new(a.X * b, a.Y * b) end,
		__type = "Vector2",
	})
end }
Vector2.zero = Vector2.new(0, 0)

-- CFrame: position + rotation columns (right, up, back), Roblox conventions.
local CF = {}
local function cf(p, rx, ry, rz)
	return setmetatable({ p = p, rx = rx, ry = ry, rz = rz }, CF)
end
local function rotate(c, v) -- rotation only
	return c.rx * v.X + c.ry * v.Y + c.rz * v.Z
end
CF.__index = function(c, k)
	if k == "Position" or k == "p" then
		return rawget(c, "p")
	elseif k == "X" then
		return c.p.X
	elseif k == "Y" then
		return c.p.Y
	elseif k == "Z" then
		return c.p.Z
	elseif k == "Rotation" then
		return cf(V3new(0, 0, 0), c.rx, c.ry, c.rz)
	elseif k == "LookVector" then
		return -c.rz
	elseif k == "RightVector" then
		return c.rx
	elseif k == "UpVector" then
		return c.ry
	end
	return nil
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then
		return cf(a.p + rotate(a, b.p), rotate(a, b.rx), rotate(a, b.ry), rotate(a, b.rz))
	end
	return a.p + rotate(a, b) -- CFrame * Vector3 = point
end
CF.__add = function(a, v) return cf(a.p + v, a.rx, a.ry, a.rz) end
CF.__sub = function(a, v) return cf(a.p - v, a.rx, a.ry, a.rz) end
local X, Y, Z = V3new(1, 0, 0), V3new(0, 1, 0), V3new(0, 0, 1)
CFrame = {}
function CFrame.new(x, y, z)
	if type(x) == "table" and x.X then
		return cf(x, X, Y, Z)
	end
	return cf(V3new(x or 0, y or 0, z or 0), X, Y, Z)
end
local function axisAngle(axis, a)
	local c, s = math.cos(a), math.sin(a)
	if axis == "x" then
		return cf(V3new(0, 0, 0), V3new(1, 0, 0), V3new(0, c, s), V3new(0, -s, c))
	elseif axis == "y" then
		return cf(V3new(0, 0, 0), V3new(c, 0, -s), V3new(0, 1, 0), V3new(s, 0, c))
	end
	return cf(V3new(0, 0, 0), V3new(c, s, 0), V3new(-s, c, 0), V3new(0, 0, 1))
end
function CFrame.Angles(rx, ry, rz)
	return axisAngle("x", rx or 0) * axisAngle("y", ry or 0) * axisAngle("z", rz or 0)
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromMatrix(p, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return cf(p, vx, vy, vz)
end
function CFrame.lookAt(eye, target)
	local look = (target - eye)
	look = look.Magnitude > 0 and look.Unit or V3new(0, 0, -1)
	local right = look:Cross(Y)
	right = right.Magnitude > 1e-6 and right.Unit or X
	local up = right:Cross(look)
	return cf(eye, right, up, -look)
end

Color3 = {
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255, __c = true } end,
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0, __c = true } end,
	fromHex = function(h) return { hex = h, __c = true } end,
}
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
local UD2 = {}
UD2.__add = function(a, b) return setmetatable({ X = a.X, Y = a.Y }, UD2) end
UDim2 = {
	new = function(xs, xo, ys, yo) return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UD2) end,
	fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end,
	fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end,
}
PhysicalProperties = { new = function(...) return { ... } end }
TweenInfo = { new = function(...) return { ... } end }
ColorSequence = { new = function(...) return { ... } end }
NumberSequence = { new = function(...) return { ... } end }
NumberSequenceKeypoint = { new = function(...) return { ... } end }
NumberRange = { new = function(...) return { ... } end }
RaycastParams = { new = function() return { FilterDescendantsInstances = {} } end }

local rngSeed = 7
Random = { new = function()
	return {
		NextNumber = function(_, a, b)
			rngSeed = (rngSeed * 1103515245 + 12345) % 2147483648
			local r = rngSeed / 2147483648
			if a then return a + (b - a) * r end
			return r
		end,
		NextInteger = function(_, lo, hi)
			rngSeed = (rngSeed * 1103515245 + 12345) % 2147483648
			return lo + math.floor(rngSeed / 2147483648 * (hi - lo + 1))
		end,
	}
end }

local enumMeta = {}
enumMeta.__index = function(t, k)
	local v = setmetatable({ Name = k, path = rawget(t, "path") .. "." .. k }, enumMeta)
	rawset(t, k, v)
	return v
end
enumMeta.__tostring = function(t) return rawget(t, "path") end
Enum = setmetatable({ path = "Enum" }, enumMeta)
Enum.RenderPriority.Camera.Value = 200

-------------------------------------------------------------------------------- instances

local Inst = {}
local instanceMeta = {}
Mock.instanceMeta = instanceMeta

local BASES = {
	Part = { "BasePart", "PVInstance" },
	MeshPart = { "BasePart", "PVInstance" },
	SpawnLocation = { "Part", "BasePart", "PVInstance" },
	WedgePart = { "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	Script = { "BaseScript", "LuaSourceContainer" },
	LocalScript = { "Script", "BaseScript", "LuaSourceContainer" },
	ModuleScript = { "LuaSourceContainer" },
	TextLabel = { "GuiObject", "GuiBase2d" },
	TextButton = { "GuiButton", "GuiObject", "GuiBase2d" },
	Frame = { "GuiObject", "GuiBase2d" },
	ScrollingFrame = { "GuiObject", "GuiBase2d" },
	ScreenGui = { "LayerCollector", "GuiBase2d" },
	BillboardGui = { "LayerCollector", "GuiBase2d" },
}

local DEFAULTS = {
	BasePart = function(i)
		i._p.CFrame = CFrame.new(0, 0, 0)
		i._p.Size = V3new(1, 1, 1)
		i._p.AssemblyLinearVelocity = V3new(0, 0, 0)
		i._p.Anchored = false
		i._p.AssemblyMass = 1
		i._p.Transparency = 0
	end,
}

local EVENT_NAMES = {
	ChildAdded = true, ChildRemoved = true, DescendantAdded = true, AncestryChanged = true, Changed = true,
	Triggered = true, OnServerEvent = true, OnClientEvent = true, Activated = true, Completed = true,
	PlayerAdded = true, PlayerRemoving = true, CharacterAdded = true, Heartbeat = true, RenderStepped = true,
	Stepped = true, InputBegan = true, InputEnded = true, InputChanged = true, TouchStarted = true, TouchMoved = true,
	TouchEnded = true, JumpRequest = true, WindowFocusReleased = true, MouseButton1Click = true, Died = true,
}

local function isA(i, class)
	if class == "Instance" or i.ClassName == class then
		return true
	end
	for _, b in ipairs(BASES[i.ClassName] or {}) do
		if b == class then
			return true
		end
	end
	return false
end

local methods = {}
function methods:IsA(class) return isA(self, class) end
function methods:FindFirstChild(name, recursive)
	for _, c in ipairs(self._children) do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(self._children) do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods:FindFirstChildOfClass(class)
	for _, c in ipairs(self._children) do
		if c.ClassName == class then
			return c
		end
	end
	return nil
end
function methods:FindFirstChildWhichIsA(class)
	for _, c in ipairs(self._children) do
		if isA(c, class) then
			return c
		end
	end
	return nil
end
function methods:WaitForChild(name, timeout)
	local found = self:FindFirstChild(name)
	if found or not coroutine.isyieldable() then
		if not found and not timeout then
			table.insert(Mock.warnings, "Infinite yield possible on " .. self:GetFullName() .. ":WaitForChild(\"" .. name .. "\")")
		end
		return found
	end
	local deadline = Mock.now + (timeout or 5)
	while Mock.now < deadline do
		task.wait(1 / 60)
		found = self:FindFirstChild(name)
		if found then
			return found
		end
	end
	if not timeout then
		table.insert(Mock.warnings, "Infinite yield possible on " .. self:GetFullName() .. ":WaitForChild(\"" .. name .. "\")")
	end
	return nil
end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in ipairs(i._children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:IsDescendantOf(other)
	local p = self.Parent
	while p do
		if p == other then
			return true
		end
		p = p.Parent
	end
	return false
end
function methods:GetFullName()
	local names, i = {}, self
	while i and i ~= Mock.game do
		table.insert(names, 1, i.Name)
		i = i.Parent
	end
	return table.concat(names, ".")
end
function methods:Destroy()
	for _, c in ipairs(table.clone(self._children)) do
		c:Destroy()
	end
	self.Parent = nil
	self._destroyed = true
end
function methods:ClearAllChildren()
	for _, c in ipairs(table.clone(self._children)) do
		c:Destroy()
	end
end
function methods:Clone()
	local c = Instance.new(self.ClassName)
	for k, v in pairs(self._p) do
		if k ~= "Parent" then
			c._p[k] = v
		end
	end
	for k, v in pairs(self._attr) do
		c._attr[k] = v
	end
	for _, ch in ipairs(self._children) do
		ch:Clone().Parent = c
	end
	return c
end
function methods:SetAttribute(k, v)
	if self._attr[k] ~= v then
		self._attr[k] = v
		local sig = self._attrSignals[k]
		if sig then
			sig:Fire()
		end
	end
end
function methods:GetAttribute(k) return self._attr[k] end
function methods:GetAttributes() return table.clone(self._attr) end
function methods:GetAttributeChangedSignal(k)
	self._attrSignals[k] = self._attrSignals[k] or Signal.new()
	return self._attrSignals[k]
end
function methods:GetPropertyChangedSignal(k)
	self._propSignals[k] = self._propSignals[k] or Signal.new()
	return self._propSignals[k]
end
function methods:SetNetworkOwner(owner)
	if self._p.Anchored then
		error("Can only call SetNetworkOwner on unanchored parts", 2)
	end
	self._owner = owner
end
function methods:GetNetworkOwner() return self._owner end
function methods:ApplyImpulse(impulse)
	self._p.AssemblyLinearVelocity = self._p.AssemblyLinearVelocity + impulse / (self._p.AssemblyMass or 1)
end
function methods:GetPivot() return self._p.CFrame or CFrame.new() end
function methods:PivotTo(c) self.CFrame = c end
-- RemoteEvent / RemoteFunction (one process: delivered immediately)
function methods:FireClient(player, ...)
	table.insert(Mock.sent, { remote = self.Name, player = player, args = table.pack(...) })
	if Mock.clientPlayer == player then
		self.OnClientEvent:Fire(...)
	end
end
function methods:FireAllClients(...)
	table.insert(Mock.sent, { remote = self.Name, args = table.pack(...) })
	if Mock.clientPlayer then
		self.OnClientEvent:Fire(...)
	end
end
function methods:FireServer(...)
	self.OnServerEvent:Fire(Mock.clientPlayer, ...)
end
function methods:InvokeServer(...)
	return self.OnServerInvoke(Mock.clientPlayer, ...)
end
-- Tween
function methods:Play()
	if self._tween then
		for k, v in pairs(self._tween.goal) do
			self._tween.target[k] = v
		end
		self.Completed:Fire(Enum.PlaybackState.Completed)
	end
end
function methods:Cancel() end
function methods:Emit(n) Mock.emitted = (Mock.emitted or 0) + (n or 0) end

instanceMeta.__index = function(i, k)
	local m = methods[k]
	if m then
		return m
	end
	if k == "Position" and i._p.CFrame then
		return i._p.CFrame.Position
	end
	if k == "Rotation" and i._p.CFrame then
		return i._p.CFrame.Rotation
	end
	local v = i._p[k]
	if v ~= nil then
		return v
	end
	if EVENT_NAMES[k] then
		local s = Signal.new()
		i._p[k] = s
		return s
	end
	-- Roblox lets you index a child by name (parent.ChildName).
	for _, c in ipairs(rawget(i, "_children")) do
		if c.Name == k then
			return c
		end
	end
	return nil
end

instanceMeta.__newindex = function(i, k, v)
	if k == "Parent" then
		local old = i._p.Parent
		if old == v then
			return
		end
		if old then
			for idx, c in ipairs(old._children) do
				if c == i then
					table.remove(old._children, idx)
					break
				end
			end
			old.ChildRemoved:Fire(i)
		end
		i._p.Parent = v
		if v then
			table.insert(v._children, i)
			v.ChildAdded:Fire(i)
		end
		return
	end
	if k == "Position" and i._p.CFrame then
		local c = i._p.CFrame
		i._p.CFrame = CFrame.new(v) * c.Rotation
		return
	end
	if k == "Anchored" and v == true then
		i._owner = nil
	end
	i._p[k] = v
	local sig = i._propSignals[k]
	if sig then
		sig:Fire()
	end
end
instanceMeta.__tostring = function(i) return i.Name end

Instance = {}
function Instance.new(class, parent)
	local i = setmetatable({ _p = { ClassName = class, Name = class }, _children = {}, _attr = {}, _attrSignals = {}, _propSignals = {} }, instanceMeta)
	if isA(i, "BasePart") then
		DEFAULTS.BasePart(i)
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local realTypeof = typeof
function typeof(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt == instanceMeta then
			return "Instance"
		elseif mt == CF then
			return "CFrame"
		elseif mt and mt.__type then
			return mt.__type
		elseif rawget(v, "X") ~= nil and rawget(v, "Z") ~= nil then
			return "Vector3"
		elseif rawget(v, "__c") then
			return "Color3"
		end
	end
	return realTypeof(v)
end

-------------------------------------------------------------------------------- services and game

local function service(class, name)
	local s = Instance.new(class)
	s.Name = name or class
	return s
end

function Mock.reset()
	Mock.now, Mock.threads, Mock.warnings, Mock.errors, Mock.sent = 0, {}, {}, {}, {}
	local game = service("DataModel", "Game")
	Mock.game = game
	game.JobId = ""
	game.PlaceId = 0
	local services = {}
	for _, n in ipairs({ "Workspace", "Players", "ReplicatedStorage", "ServerScriptService", "StarterPlayer", "RunService", "HttpService", "CollectionService", "DataStoreService", "TweenService", "UserInputService", "GuiService", "Lighting", "PhysicsService", "Debris", "SoundService" }) do
		services[n] = service(n == "Workspace" and "Workspace" or n, n)
		services[n].Parent = game
	end
	Mock.services = services
	local sps = Instance.new("Folder")
	sps.Name = "StarterPlayerScripts"
	sps.Parent = services.StarterPlayer
	function game:GetService(n)
		return services[n] or error("mock has no service " .. n)
	end
	game.BindToClose = function(_, fn)
		Mock.closeHandlers = Mock.closeHandlers or {}
		table.insert(Mock.closeHandlers, fn)
	end
	Mock.closeHandlers = {}

	Mock.collision = { groups = {}, pairs = {} }
	services.PhysicsService.RegisterCollisionGroup = function(_, name) Mock.collision.groups[name] = true end
	services.PhysicsService.CollisionGroupSetCollidable = function(_, a, b, v)
		assert(a == "Default" or Mock.collision.groups[a], "unregistered collision group " .. a)
		assert(b == "Default" or Mock.collision.groups[b], "unregistered collision group " .. b)
		Mock.collision.pairs[a .. "|" .. b] = v
	end
	services.Debris.AddItem = function(_, inst, t)
		task.delay(t or 10, function()
			inst:Destroy()
		end)
	end
	services.Lighting.EnvironmentSpecularScale = 0
	services.Lighting.EnvironmentDiffuseScale = 0

	-- Workspace
	local ws = services.Workspace
	ws.Gravity = 196.2
	local camera = Instance.new("Camera")
	camera.ViewportSize = Vector2.new(1280, 720)
	camera.CFrame = CFrame.new(0, 10, 10)
	camera.Parent = ws
	ws.CurrentCamera = camera
	-- Floor model for probes: flat ground at y = 1 everywhere (the stadium's slopes aren't simulated).
	local function floorHit(origin, dir)
		local reach = origin.Y + math.min(dir.Y, 0)
		if dir.Y < 0 and origin.Y >= 1 and reach <= 1 then
			return { Position = V3new(origin.X, 1, origin.Z), Normal = V3new(0, 1, 0), Instance = ws, Distance = origin.Y - 1 }
		end
		return nil
	end
	function ws:Raycast(origin, dir) return floorHit(origin, dir) end
	function ws:Spherecast(origin, radius, dir) return floorHit(origin - V3new(0, radius, 0), dir) end
	function ws:GetServerTimeNow() return Mock.now end

	-- RunService
	local rs = services.RunService
	rs.IsStudio = function() return true end
	rs.IsServer = function() return true end
	rs.IsClient = function() return true end
	Mock.renderSteps = {}
	rs.BindToRenderStep = function(_, name, _, fn) Mock.renderSteps[name] = fn end
	rs.UnbindFromRenderStep = function(_, name) Mock.renderSteps[name] = nil end

	-- HttpService
	local guid = 0
	services.HttpService.GenerateGUID = function() guid += 1 return "guid-" .. guid end

	-- CollectionService
	local tags = {}
	services.CollectionService.AddTag = function(_, inst, tag) tags[tag] = tags[tag] or {} table.insert(tags[tag], inst) end
	services.CollectionService.GetTagged = function(_, tag)
		local out = {}
		for _, inst in ipairs(tags[tag] or {}) do
			if not inst._destroyed then
				table.insert(out, inst)
			end
		end
		return out
	end

	-- TweenService: completes instantly
	services.TweenService.Create = function(_, target, info, goal)
		local t = Instance.new("Tween")
		t._tween = { target = target, goal = goal }
		return t
	end

	-- DataStoreService: in-memory, with failure injection
	Mock.store = { data = {}, fail = false, writes = 0 }
	services.DataStoreService.GetDataStore = function(_, name)
		if Mock.storeUnavailable then
			error("DataStoreService: StudioAccessToApisNotAllowed (mock)")
		end
		return {
			UpdateAsync = function(_, key, transform)
				if Mock.store.fail then
					error("mock DataStore failure")
				end
				local new = transform(Mock.store.data[key])
				if new ~= nil then
					Mock.store.data[key] = new
					Mock.store.writes += 1
				end
				return new
			end,
		}
	end

	-- UserInputService
	local uis = services.UserInputService
	uis.TouchEnabled = false
	uis.KeyboardEnabled = true
	uis.GamepadEnabled = false
	uis.MouseBehavior = Enum.MouseBehavior.Default
	uis.MouseIconEnabled = true
	uis.GetFocusedTextBox = function() return nil end
	uis.IsKeyDown = function(_, key) return Mock.keys[key.Name] == true end
	uis.GetGamepadState = function() return {} end
	uis.GetMouseDelta = function() return Mock.mouseDelta or Vector2.new(0, 0) end
	uis.IsMouseButtonPressed = function() return false end

	services.GuiService.SelectedObject = nil
	return game
end

-- Adds a player with a character. Fires PlayerAdded.
function Mock.addPlayer(name, userId)
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = userId
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = p
	local scripts = Instance.new("PlayerScripts")
	scripts.Name = "PlayerScripts"
	scripts.Parent = p
	p.Parent = Mock.services.Players
	Mock.spawnCharacter(p)
	Mock.services.Players.PlayerAdded:Fire(p)
	return p
end

function Mock.spawnCharacter(p)
	local char = Instance.new("Model")
	char.Name = p.Name
	local hum = Instance.new("Humanoid")
	hum.Move = function(self, dir) self._moveDir = dir end
	hum.WalkSpeed = 16
	hum.JumpHeight = 7.2
	hum.JumpPower = 50
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	char.Parent = Mock.services.Workspace
	p.Character = char
	p.CharacterAdded:Fire(char)
	return char
end

function Mock.removePlayer(p)
	Mock.services.Players.PlayerRemoving:Fire(p)
	p.Parent = nil
end

Mock.services = nil
-- Players:GetPlayers()
methods.GetPlayers = function(self) return self:GetChildren() end

-------------------------------------------------------------------------------- running scripts

-- Builds ModuleScript/Script instances from SOURCES (path -> text) under `root` mirroring a src/ folder.
function Mock.mount(root, srcPrefix)
	local folder = Instance.new("Folder")
	folder.Name = "Spinforge"
	folder.Parent = root
	local scripts = {}
	local paths = {}
	for path in pairs(SOURCES) do
		if path:sub(1, #srcPrefix + 1) == srcPrefix .. "/" then
			table.insert(paths, path)
		end
	end
	table.sort(paths)
	for _, path in ipairs(paths) do
		local rel = path:sub(#srcPrefix + 2)
		local parent = folder
		local parts = string.split(rel, "/")
		for idx = 1, #parts - 1 do
			local f = parent:FindFirstChild(parts[idx])
			if not f then
				f = Instance.new("Folder")
				f.Name = parts[idx]
				f.Parent = parent
			end
			parent = f
		end
		local file = parts[#parts]
		local class, name = "ModuleScript", file:gsub("%.lua$", "")
		if file:match("%.server%.lua$") then
			class, name = "Script", file:gsub("%.server%.lua$", "")
		elseif file:match("%.client%.lua$") then
			class, name = "LocalScript", file:gsub("%.client%.lua$", "")
		end
		local s = Instance.new(class)
		s.Name = name
		s.Source = SOURCES[path]
		s.Parent = parent
		table.insert(scripts, s)
	end
	return folder, scripts
end

local moduleCache = {}
local function makeEnv(scriptInst)
	local env = setmetatable({}, { __index = getfenv(0) })
	env.script = scriptInst
	env.game = Mock.game
	env.workspace = Mock.services.Workspace
	env.os = os
	env.task = task
	env.typeof = typeof
	env.warn = function(...)
		local parts = {}
		for _, v in ipairs({ ... }) do
			table.insert(parts, tostring(v))
		end
		table.insert(Mock.warnings, table.concat(parts, " "))
	end
	env.print = function(...)
		local parts = {}
		for _, v in ipairs({ ... }) do
			table.insert(parts, tostring(v))
		end
		table.insert(Mock.printed, table.concat(parts, " "))
	end
	env.require = function(m)
		if moduleCache[m] ~= nil then
			return moduleCache[m]
		end
		assert(type(m) == "table" and m.ClassName == "ModuleScript", "require of a non-ModuleScript: " .. tostring(m))
		local fn, err = loadstring(m.Source, "=" .. m:GetFullName())
		assert(fn, err)
		setfenv(fn, makeEnv(m))
		local result = fn()
		moduleCache[m] = result
		return result
	end
	return env
end

function Mock.run(scriptInst)
	local fn, err = loadstring(scriptInst.Source, "=" .. scriptInst:GetFullName())
	assert(fn, err)
	setfenv(fn, makeEnv(scriptInst))
	task.spawn(fn)
end

function Mock.clearModules()
	moduleCache = {}
end

-- Moves time forward in frames: fires Heartbeat, runs render steps, resumes due threads, and moves unanchored
-- beys by their velocity (no collisions; a flat floor at y = 1 keeps them up).
function Mock.advance(seconds, dt)
	dt = dt or 1 / 60
	local target = Mock.now + seconds
	while Mock.now < target - 1e-9 do
		Mock.now += dt
		local ws = Mock.services.Workspace
		local beys = ws:FindFirstChild("Beys")
		if beys then
			for _, m in ipairs(beys:GetChildren()) do
				local body = m:FindFirstChild("Body")
				if body and not body.Anchored then
					local v = body.AssemblyLinearVelocity
					v = v + V3new(0, -ws.Gravity * dt, 0)
					local p = body.Position + v * dt
					if p.Y < 3 then -- ball radius 2 resting on the y = 1 floor
						p = V3new(p.X, 3, p.Z)
						if v.Y < 0 then
							v = V3new(v.X, 0, v.Z)
						end
					end
					body._p.AssemblyLinearVelocity = v
					body._p.CFrame = CFrame.new(p)
				end
			end
		end
		Mock.services.RunService.Heartbeat:Fire(dt)
		Mock.services.RunService.RenderStepped:Fire(dt)
		for _, fn in pairs(Mock.renderSteps) do
			task.spawn(fn, dt)
		end
		local due = {}
		for idx = #Mock.threads, 1, -1 do
			if Mock.threads[idx].at <= Mock.now then
				table.insert(due, table.remove(Mock.threads, idx))
			end
		end
		for _, t in ipairs(due) do
			if coroutine.status(t.co) == "suspended" then
				resumeThread(t.co)
			end
		end
	end
end

-- Remote messages the server sent to a player, filtered by remote name (and BattleEvent kind).
function Mock.sentTo(player, remote, kind)
	local out = {}
	for _, s in ipairs(Mock.sent) do
		if s.remote == remote and (s.player == player or s.player == nil) then
			local a = s.args[1]
			if not kind or (type(a) == "table" and a.kind == kind) then
				table.insert(out, a)
			end
		end
	end
	return out
end

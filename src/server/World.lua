--!nonstrict
-- World: builds the play space at server start (runtime only; nothing is saved into the place file).
--   Arena     battle stadium at the origin. NO fence: leaving the bowl is a ring-out (battle rules).
--   Training  practice stadium at TRAINING_CENTER. Invisible fence above the rim keeps you in (training rules),
--             plus knockable dummies.
--   Hub       on-foot start area between them with the spawn, a Challenge pedestal, a Practice pad and the Workshop.
-- If the place already has a folder named "SpinforgeWorld", nothing is built (you've made your own map).

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local World = {}

World.ARENA_CENTER = Vector3.new(0, 0, 0)
World.TRAINING_CENTER = Vector3.new(0, 0, -130)
World.HUB_CENTER = Vector3.new(0, 0, 95)
World.SPAWN = Vector3.new(0, 3, 108)
World.PARK = Vector3.new(0, 4, 128) -- where avatars wait (anchored) while their bey plays

local SEGMENTS = 48
local FLOOR_RADIUS = 14
local RINGS = { -- { outer radius, slope degrees, colour }
	{ 24, 12, Color3.fromRGB(46, 56, 84) },
	{ 33, 26, Color3.fromRGB(40, 70, 120) },
	{ 39, 45, Color3.fromRGB(34, 96, 160) },
	{ 42, 72, Color3.fromRGB(30, 130, 200) },
}
World.RIM_RADIUS = 42
local FENCE_HEIGHT = 60

local function block(parent, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(parent, at, text, color)
	local post = block(parent, "Sign", Vector3.new(0.6, 6, 0.6), CFrame.new(at + Vector3.new(0, 3, 0)), Color3.fromRGB(40, 44, 60))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 60)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Parent = post
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)
	return post
end

-- Builds one bowl stadium. opts: { name, center, fence = bool, dummies = bool }
local function buildBowl(root, opts)
	local folder = Instance.new("Folder")
	folder.Name = opts.name
	folder.Parent = root
	local c = opts.center
	local origin = CFrame.new(c)

	block(folder, "Floor", Vector3.new(1, FLOOR_RADIUS * 2 + 0.6, FLOOR_RADIUS * 2 + 0.6), origin * CFrame.new(0, 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(38, 42, 62)).Shape =
		Enum.PartType.Cylinder
	local mark = block(folder, "CentreMark", Vector3.new(0.1, 6, 6), origin * CFrame.new(0, 1.06, 0) * CFrame.Angles(0, 0, math.rad(90)), opts.accent, Enum.Material.Neon)
	mark.Shape = Enum.PartType.Cylinder
	mark.CanCollide = false

	local height, inner = 1.02, FLOOR_RADIUS
	for ringIndex, ring in ipairs(RINGS) do
		local outer, slope, color = ring[1], math.rad(ring[2]), ring[3]
		local run = outer - inner
		local rise = run * math.tan(slope)
		local length = run / math.cos(slope) + 0.4
		local width = 2 * outer * math.tan(math.pi / SEGMENTS) + 0.25
		local mid = (inner + outer) / 2
		for i = 0, SEGMENTS - 1 do
			local angle = i * 2 * math.pi / SEGMENTS
			local cf = origin * CFrame.new(0, height + rise / 2, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -mid) * CFrame.Angles(slope, 0, 0) * CFrame.new(0, -0.5, 0)
			block(folder, "Ring" .. ringIndex, Vector3.new(width, 1, length), cf, color)
		end
		height += rise
		inner = outer
	end
	local rimHeight = height

	local barrier = Instance.new("Folder")
	barrier.Name = "Barrier" -- the camera ignores this folder
	barrier.Parent = folder
	for i = 0, SEGMENTS - 1 do
		local angle = i * 2 * math.pi / SEGMENTS
		local width = 2 * (inner + 1) * math.tan(math.pi / SEGMENTS) + 0.3
		local base = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -(inner + 0.6))
		block(folder, "Skirt", Vector3.new(width, rimHeight, 1.2), origin * CFrame.new(0, rimHeight / 2, 0) * base, Color3.fromRGB(24, 28, 40))
		block(folder, "Rim", Vector3.new(width, 0.5, 1.4), origin * CFrame.new(0, rimHeight + 0.25, 0) * base, opts.accent, Enum.Material.Neon)
		if opts.fence then
			local fence = block(barrier, "Fence", Vector3.new(width, FENCE_HEIGHT, 1), origin * CFrame.new(0, rimHeight + FENCE_HEIGHT / 2, 0) * base, Color3.new(1, 1, 1))
			fence.Transparency = 1
		end
	end

	if opts.dummies then
		for _, xz in ipairs({ { 9, 0 }, { -5, 8 }, { -5, -8 } }) do
			local p = Instance.new("Part")
			p.Name = "Dummy"
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(2, 6, 6)
			p.CFrame = origin * CFrame.new(xz[1], 4, xz[2]) * CFrame.Angles(0, 0, math.rad(90))
			p.Color = Color3.fromRGB(220, 70, 70)
			p.Material = Enum.Material.SmoothPlastic
			p:SetAttribute("Home", p.CFrame.Position)
			p.Parent = folder
			CollectionService:AddTag(p, "SpinforgeDummy")
		end
	end
	return folder
end

local function prompt(parent, actionText, objectText, name)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = actionText
	pp.ObjectText = objectText
	pp.HoldDuration = 0.25
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.Parent = parent
	return pp
end

local function buildHub(root, villainName)
	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	folder.Parent = root
	local c = World.HUB_CENTER
	block(folder, "Plaza", Vector3.new(70, 1, 60), CFrame.new(c + Vector3.new(0, 1.5, 12)), Color3.fromRGB(58, 64, 82), Enum.Material.Slate)
	-- Walkways to both stadiums (decoration; the beys travel by teleport).
	block(folder, "PathArena", Vector3.new(8, 0.2, 20), CFrame.new(0, 2.05, 62), Color3.fromRGB(90, 200, 255), Enum.Material.Neon).Transparency = 0.6

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpinforgeSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(World.SPAWN - Vector3.new(0, 1, 0))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(90, 200, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Parent = folder

	local challenge = block(folder, "ChallengePedestal", Vector3.new(6, 3, 6), CFrame.new(c + Vector3.new(-14, 3.5, -6)), Color3.fromRGB(200, 60, 70), Enum.Material.Neon)
	sign(folder, c + Vector3.new(-14, 2, -11), "BATTLE: " .. string.upper(villainName), Color3.fromRGB(255, 120, 120))
	local practice = block(folder, "PracticePad", Vector3.new(6, 3, 6), CFrame.new(c + Vector3.new(14, 3.5, -6)), Color3.fromRGB(70, 180, 120), Enum.Material.Neon)
	sign(folder, c + Vector3.new(14, 2, -11), "PRACTICE", Color3.fromRGB(140, 255, 180))
	local workshop = block(folder, "WorkshopKiosk", Vector3.new(8, 4, 4), CFrame.new(c + Vector3.new(0, 4, 26)), Color3.fromRGB(230, 170, 60), Enum.Material.Neon)
	sign(folder, c + Vector3.new(6, 2, 26), "WORKSHOP", Color3.fromRGB(255, 210, 120))

	return {
		challenge = prompt(challenge, "Challenge", villainName, "ChallengePrompt"),
		practice = prompt(practice, "Practice", "Training stadium", "PracticePrompt"),
		workshop = prompt(workshop, "Open", "Workshop", "WorkshopPrompt"),
	}
end

-- Returns { root, arena, training, prompts, built = bool }.
function World.build(villainName)
	local existing = Workspace:FindFirstChild("SpinforgeWorld")
	if existing then
		local prompts = {}
		for _, name in ipairs({ "ChallengePrompt", "PracticePrompt", "WorkshopPrompt" }) do
			local p = existing:FindFirstChild(name, true)
			prompts[(name:gsub("Prompt", "")):lower()] = p
		end
		return { root = existing, arena = existing:FindFirstChild("Arena"), training = existing:FindFirstChild("Training"), prompts = prompts, built = false }
	end
	local root = Instance.new("Folder")
	root.Name = "SpinforgeWorld"
	root.Parent = Workspace
	block(root, "Ground", Vector3.new(400, 2, 400), CFrame.new(0, 0, 0), Color3.fromRGB(70, 74, 86))
	local arena = buildBowl(root, { name = "Arena", center = World.ARENA_CENTER, fence = false, dummies = false, accent = Color3.fromRGB(255, 110, 110) })
	local training = buildBowl(root, { name = "Training", center = World.TRAINING_CENTER, fence = true, dummies = true, accent = Color3.fromRGB(120, 220, 255) })
	local prompts = buildHub(root, villainName)
	-- Players should spawn in the hub, not inside a stadium.
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d.Name ~= "SpinforgeSpawn" then
			d.Enabled = false
		end
	end
	return { root = root, arena = arena, training = training, prompts = prompts, built = true }
end

-- Old builds put a "Stadium" folder in Workspace; remove it so it doesn't overlap the new world.
function World.removeLegacy()
	local old = Workspace:FindFirstChild("Stadium")
	if old and old:IsA("Folder") then
		old:Destroy()
	end
end

return World

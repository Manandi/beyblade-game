--!nonstrict
-- Builds a bey's looks. If the Blender meshes have been imported into ReplicatedStorage.BeyMeshes (see README),
-- each part uses its mesh; otherwise it falls back to a simple shape built from basic Roblox parts (BeyDesigns).
-- Everything is welded to the spinning hub, massless and non-colliding, so the physics body is unchanged.
-- Call BeyVisuals.Attach on the SERVER after the model is parented to Workspace (so welds capture the layout).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BeyConfig = require(script.Parent.BeyConfig)
local BeyDesigns = require(script.Parent.BeyDesigns)
local BeyMeshData = require(script.Parent.BeyMeshData)

local BeyVisuals = {}

local Y_OFFSET = -0.7 -- sits the visual low in the 4-stud collision ball so the tip nearly touches the ground
local RAD90 = math.rad(90)
local TAU = math.pi * 2

local function rarityRank(rarity)
	for i, r in ipairs(BeyConfig.Rarities) do
		if r == rarity then
			return i
		end
	end
	return 1
end

-- ctx = { hub = Part, root = CFrame (the body's CFrame), parent = Instance }
local function addPart(ctx, size, localCF, color, material, shape)
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CFrame = ctx.root * CFrame.new(0, Y_OFFSET, 0) * localCF
	p.Parent = ctx.parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.hub
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function addBlock(ctx, size, localCF, color, material)
	return addPart(ctx, size, localCF, color, material)
end

local function addCyl(ctx, diameter, height, y, color, material)
	return addPart(
		ctx,
		Vector3.new(height, diameter, diameter),
		CFrame.new(0, y, 0) * CFrame.Angles(0, 0, RAD90),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function addBall(ctx, diameter, y, color, material)
	return addPart(ctx, Vector3.new(diameter, diameter, diameter), CFrame.new(0, y, 0), color, material, Enum.PartType.Ball)
end

local function addEllipsoid(ctx, size, localCF, color, material)
	local p = addPart(ctx, size, localCF, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Places something `radius` out along direction angle `a`, then twists it by `swirl` about its own centre.
local function radial(a, y, radius, swirl)
	return CFrame.Angles(0, a, 0) * CFrame.new(0, y, -radius) * CFrame.Angles(0, swirl or 0, 0)
end

local function buildLayer(ctx, d)
	local y = 0.55
	addCyl(ctx, 2.3, 0.16, y, d.Primary)
	local n = d.Count
	for i = 1, n do
		local a = TAU * i / n
		if d.Style == "Spike" then
			addBlock(ctx, Vector3.new(0.28, 0.34, 1.6), radial(a, y + 0.15, 1.25), d.Primary)
			addBlock(ctx, Vector3.new(0.09, 0.1, 1.2), radial(a, y + 0.35, 1.2), d.Accent)
			addBlock(ctx, Vector3.new(0.2, 0.26, 0.4), radial(a, y + 0.13, 2.0), d.Accent)
		elseif d.Style == "Hook" then
			addBlock(ctx, Vector3.new(0.42, 0.3, 1.45), radial(a, y + 0.15, 1.2, -0.45), d.Primary)
			addBlock(ctx, Vector3.new(0.3, 0.26, 0.6), radial(a, y + 0.13, 1.85, -1.0), d.Accent)
		elseif d.Style == "Blade" then
			addBlock(ctx, Vector3.new(0.34, 0.3, 1.85), radial(a, y + 0.15, 1.2, 0.3), d.Primary)
			addBlock(ctx, Vector3.new(0.08, 0.32, 1.85), radial(a, y + 0.16, 1.2, 0.3) * CFrame.new(0.19, 0, 0), d.Accent)
		elseif d.Style == "Petal" then
			addEllipsoid(ctx, Vector3.new(0.95, 0.42, 1.9), radial(a, y + 0.2, 1.15, 0.5), d.Primary)
			addEllipsoid(ctx, Vector3.new(0.3, 0.2, 0.9), radial(a, y + 0.35, 1.2, 0.5), d.Accent)
		elseif d.Style == "Armor" then
			local r = 1.45
			local w = 2 * r * math.tan(math.pi / n) + 0.05
			addBlock(ctx, Vector3.new(w, 0.55, 0.55), radial(a, y + 0.2, r), d.Primary)
			addBlock(ctx, Vector3.new(w * 0.6, 0.1, 0.2), radial(a, y + 0.5, r), d.Accent)
		end
	end
end

local function buildDisc(ctx, d)
	if d.Style == "Heavy" then
		addCyl(ctx, 2.8, 0.7, 0, d.Primary)
		addCyl(ctx, 3.0, 0.16, 0, d.Accent)
	elseif d.Style == "Ring" then
		addCyl(ctx, 3.0, 0.45, 0, d.Primary)
		addCyl(ctx, 1.8, 0.5, 0, d.Accent)
	elseif d.Style == "Fly" then
		addCyl(ctx, 3.8, 0.2, 0, d.Primary)
		addCyl(ctx, 1.6, 0.5, 0, d.Accent)
	elseif d.Style == "Stack" then
		addCyl(ctx, 3.0, 0.3, -0.2, d.Primary)
		addCyl(ctx, 2.4, 0.3, 0.1, d.Accent)
		addCyl(ctx, 1.8, 0.3, 0.35, d.Primary)
	end
end

local function buildDriver(ctx, d)
	if d.Style == "Flat" then
		addCyl(ctx, 1.2, 0.4, -0.6, d.Primary)
		addCyl(ctx, 0.9, 0.12, -0.85, d.Accent)
	elseif d.Style == "Round" then
		addCyl(ctx, 0.55, 0.4, -0.5, d.Primary)
		addBall(ctx, 0.95, -0.85, d.Accent)
	elseif d.Style == "Needle" then
		addCyl(ctx, 0.6, 0.7, -0.6, d.Primary)
		addCyl(ctx, 0.28, 0.6, -1.1, d.Accent)
		addBall(ctx, 0.22, -1.42, d.Accent)
	elseif d.Style == "Tripod" then
		addCyl(ctx, 0.9, 0.3, -0.5, d.Primary)
		for i = 1, 3 do
			local a = TAU * i / 3
			addBlock(ctx, Vector3.new(0.2, 0.7, 0.2), CFrame.Angles(0, a, 0) * CFrame.new(0, -0.95, -0.4) * CFrame.Angles(-0.25, 0, 0), d.Accent)
		end
	elseif d.Style == "Cup" then
		addCyl(ctx, 1.4, 0.5, -0.65, d.Primary)
		addCyl(ctx, 1.5, 0.1, -0.5, d.Accent, Enum.Material.Neon)
	end
end

-- Rarity dressing: Epic+ get a glowing trim ring, Legendary+ sparks, Ultra Legendary a light too.
local function buildRarityEffects(ctx, layerDesign, rarity, meshed)
	local rank = rarityRank(rarity)
	if rank >= rarityRank("Epic") and not meshed then -- the meshes model their own rarity trim
		addCyl(ctx, 2.6, 0.06, 0.42, layerDesign.Accent, Enum.Material.Neon)
	end
	if rank >= rarityRank("Legendary") then
		local at = Instance.new("Attachment")
		at.Parent = ctx.hub
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(layerDesign.Accent)
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(2, 5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = rank >= rarityRank("UltraLegendary") and 40 or 16
		e.Parent = at
	end
	if rank >= rarityRank("UltraLegendary") then
		local light = Instance.new("PointLight")
		light.Color = layerDesign.Accent
		light.Brightness = 2
		light.Range = 12
		light.Parent = ctx.hub
	end
end

-- hub: the spinning Part the visuals attach to. root: the body's CFrame when the hub was placed.
-- partIds: { Layer = id, Disc = id, Driver = id }. The highest rarity among the three sets the dressing.
-- Imported MeshPart named `name` anywhere under ReplicatedStorage.BeyMeshes (the importer may nest them in Models).
local function findMesh(name)
	local folder = ReplicatedStorage:FindFirstChild("BeyMeshes")
	local found = folder and folder:FindFirstChild(name, true)
	if found and found:IsA("MeshPart") and BeyMeshData[name] then
		return found
	end
	return nil
end

-- Clones a mesh, resizes it to the size Blender recorded (so the import scale doesn't matter) and welds it on.
local function addMesh(ctx, template, data, color, material, lift)
	local p = template:Clone()
	for _, child in ipairs(p:GetChildren()) do
		child:Destroy() -- drop anything the importer attached (SurfaceAppearance, welds)
	end
	pcall(function()
		p.TextureID = ""
	end)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Color = color
	p.Material = material
	p.Size = data.Size
	p.CFrame = ctx.root * CFrame.new(0, Y_OFFSET + lift, 0) * CFrame.new(data.Center)
	p.Parent = ctx.parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.hub
	weld.Part1 = p
	weld.Parent = p
end

-- Uses the part's two meshes if both are imported; returns false so the caller can fall back.
-- Lowest and highest point of a part's two meshes (bey-local studs), or nil if it has no mesh data.
local function meshSpan(id)
	local p, a = BeyMeshData[id .. "_P"], BeyMeshData[id .. "_A"]
	if not (p and a) then
		return nil
	end
	local bottom = math.min(p.Center.Y - p.Size.Y / 2, a.Center.Y - a.Size.Y / 2)
	local top = math.max(p.Center.Y + p.Size.Y / 2, a.Center.Y + a.Size.Y / 2)
	return bottom, top
end

-- lift: how far to move the part up or down so it sits flush on the parts next to it.
local function tryMeshes(ctx, id, slot, design, lift)
	local primary, accent = findMesh(id .. "_P"), findMesh(id .. "_A")
	if not (primary and accent) then
		return false
	end
	local rank = rarityRank(BeyConfig.Parts[id].Rarity)
	local body = slot == "Disc" and Enum.Material.Metal or Enum.Material.SmoothPlastic
	addMesh(ctx, primary, BeyMeshData[id .. "_P"], design.Primary, body, lift)
	addMesh(ctx, accent, BeyMeshData[id .. "_A"], design.Accent, rank >= rarityRank("Legendary") and Enum.Material.Neon or Enum.Material.SmoothPlastic, lift)
	return true
end

function BeyVisuals.Attach(hub, root, partIds, parent)
	local ctx = { hub = hub, root = root, parent = parent or hub.Parent }
	local layer, disc, driver = BeyDesigns.Parts[partIds.Layer], BeyDesigns.Parts[partIds.Disc], BeyDesigns.Parts[partIds.Driver]
	assert(layer and disc and driver, "missing design for a part")
	-- Stack the parts flush: the wheel stays put, the layer sits on the wheel's top face and the driver hangs
	-- from its bottom face. Wheels differ in thickness, so fixed heights would leave gaps. A small overlap hides seams.
	local OVERLAP = 0.02
	local discBottom, discTop = meshSpan(partIds.Disc)
	if not (discBottom and findMesh(partIds.Disc .. "_P")) then
		discBottom, discTop = -0.35, 0.35 -- the block-built fallback wheel
	end
	local layerBottom = meshSpan(partIds.Layer)
	local _, driverTop = meshSpan(partIds.Driver)
	local layerLift = layerBottom and (discTop - OVERLAP - layerBottom) or 0
	local driverLift = driverTop and (discBottom + OVERLAP - driverTop) or 0

	if not tryMeshes(ctx, partIds.Disc, "Disc", disc, 0) then
		buildDisc(ctx, disc)
	end
	if not tryMeshes(ctx, partIds.Driver, "Driver", driver, driverLift) then
		buildDriver(ctx, driver)
	end
	local layerMeshed = tryMeshes(ctx, partIds.Layer, "Layer", layer, layerLift)
	if not layerMeshed then
		buildLayer(ctx, layer)
	end

	local best = "Common"
	for _, slot in ipairs(BeyConfig.Slots) do
		local rarity = BeyConfig.Parts[partIds[slot]].Rarity
		if rarityRank(rarity) > rarityRank(best) then
			best = rarity
		end
	end
	buildRarityEffects(ctx, layer, best, layerMeshed)
end

-- For menus (ViewportFrames): a Model of one part (id) or a whole bey (partIds table), centred on the origin,
-- anchored, no physics. Cosmetic only; the client calls this.
function BeyVisuals.Preview(what)
	local model = Instance.new("Model")
	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Anchored = true
	hub.Transparency = 1
	hub.CanCollide = false
	hub.Size = Vector3.new(0.2, 0.2, 0.2)
	hub.CFrame = CFrame.new()
	hub.Parent = model
	model.PrimaryPart = hub
	if type(what) == "table" then
		BeyVisuals.Attach(hub, CFrame.new(), what, model)
	else
		local part = BeyConfig.Parts[what]
		local design = BeyDesigns.Parts[what]
		if part and design then
			local ctx = { hub = hub, root = CFrame.new(), parent = model }
			if not tryMeshes(ctx, what, part.Slot, design, 0) then
				if part.Slot == "Layer" then
					buildLayer(ctx, design)
				elseif part.Slot == "Disc" then
					buildDisc(ctx, design)
				else
					buildDriver(ctx, design)
				end
			end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("WeldConstraint") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	return model
end

return BeyVisuals

--!nonstrict
-- MeshImport: Studio's 3D importer drops imported models into Workspace. At server start, any bey meshes found
-- there (MeshParts named like "<partId>_P" / "<partId>_A") are moved into ReplicatedStorage.BeyMeshes, where
-- BeyVisuals looks for them. Returns how many meshes are available afterwards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Spinforge")
local BeyMeshData = require(Shared.BeyMeshData)

local MeshImport = {}

function MeshImport.collect()
	local folder = ReplicatedStorage:FindFirstChild("BeyMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BeyMeshes"
		folder.Parent = ReplicatedStorage
	end
	local tops = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("MeshPart") and BeyMeshData[d.Name] then
			local top = d
			while top.Parent and top.Parent ~= Workspace do
				top = top.Parent
			end
			tops[top] = true
		end
	end
	local moved = 0
	for top in pairs(tops) do
		top.Parent = folder
		moved += 1
	end
	local available = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("MeshPart") and BeyMeshData[d.Name] then
			available += 1
		end
	end
	return available, moved
end

return MeshImport

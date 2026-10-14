#!/usr/bin/env python3
"""Regenerates the Studio installer from src/ (run after every change to src/, then commit the output).

  install_in_studio.lua        everything in one paste (Command Bar)
  installer_parts/part_N.lua   the same, split into smaller pastes for when one big paste fails; run them in order

What it installs (project-owned objects only; it never touches anything else in the place):
  src/shared -> ReplicatedStorage.Spinforge          (ModuleScripts; folders kept)
  src/server -> ServerScriptService.Spinforge        (*.server.lua = Script, others ModuleScript)
  src/client -> StarterPlayer.StarterPlayerScripts.Spinforge (*.client.lua = LocalScript, others ModuleScript)
It replaces those three Spinforge folders wholesale, removes the old flat scripts from earlier builds, and keeps
ReplicatedStorage.BeyMeshes (your imported meshes). Running it twice gives the same result.
"""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TREES = [("src/shared", "RS"), ("src/server", "SSS"), ("src/client", "SPS")]
PART_LIMIT = 38000  # characters per split part

HEADER = """-- Spinforge installer. Paste into Studio's Command Bar (View > Command Bar, or the code pane with a Run button)
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
"""

CLEAN = """-- Fresh start for project-owned objects only.
for _, key in ipairs({ "RS", "SSS", "SPS" }) do
	local old = roots[key]:FindFirstChild("Spinforge")
	if old then old:Destroy() end
end
-- Scripts from earlier (flat) builds of this project.
for _, n in ipairs({ "BeyConfig", "BeyDesigns", "BeyVisuals", "BeyMeshData" }) do
	local o = RS:FindFirstChild(n)
	if o and o:IsA("ModuleScript") then o:Destroy() end
end
for _, n in ipairs({ "StadiumBuilder", "BeySpawner" }) do
	local o = SSS:FindFirstChild(n)
	if o and o:IsA("Script") then o:Destroy() end
end
local oldCtl = SPS:FindFirstChild("BeyController")
if oldCtl and oldCtl:IsA("LocalScript") then oldCtl:Destroy() end
-- Imported bey meshes live here and are kept between installs.
if not RS:FindFirstChild("BeyMeshes") then
	local f = Instance.new("Folder")
	f.Name = "BeyMeshes"
	f.Parent = RS
end
"""


def collect():
    items = []
    for rel, key in TREES:
        base = os.path.join(ROOT, rel)
        for dirpath, _, files in sorted(os.walk(base)):
            for fname in sorted(files):
                if not fname.endswith(".lua"):
                    continue
                full = os.path.join(dirpath, fname)
                sub = os.path.relpath(dirpath, base)
                sub = "" if sub == "." else sub.replace(os.sep, "/")
                if fname.endswith(".server.lua"):
                    cls, name = "Script", fname[: -len(".server.lua")]
                elif fname.endswith(".client.lua"):
                    cls, name = "LocalScript", fname[: -len(".client.lua")]
                else:
                    cls, name = "ModuleScript", fname[: -len(".lua")]
                src = open(full).read()
                assert "]=====]" not in src, full
                items.append((key, sub, cls, name, src, os.path.relpath(full, ROOT)))
    return items


def stmt(item):
    key, sub, cls, name, src, _ = item
    return f"install('{key}', '{sub}', '{cls}', '{name}', [=====[\n{src}]=====])\n"


def main():
    items = collect()
    count = len(items)
    full = HEADER + CLEAN + "".join(stmt(i) for i in items)
    full += f"print('Spinforge installed: {count} scripts. Press Play.')\n"
    open(os.path.join(ROOT, "install_in_studio.lua"), "w").write(full)

    parts_dir = os.path.join(ROOT, "installer_parts")
    os.makedirs(parts_dir, exist_ok=True)
    for f in os.listdir(parts_dir):
        os.remove(os.path.join(parts_dir, f))
    parts, cur = [], CLEAN
    for item in items:
        s = stmt(item)
        if len(cur) + len(s) > PART_LIMIT and cur.strip():
            parts.append(cur)
            cur = ""
        cur += s
    parts.append(cur)
    total = len(parts)
    for i, body in enumerate(parts, 1):
        tail = f"print('Spinforge installer part {i} of {total} done.{' Press Play.' if i == total else ' Now run part ' + str(i + 1) + '.'}')\n"
        open(os.path.join(parts_dir, f"part_{i}.lua"), "w").write(HEADER + body + tail)
    print(f"wrote install_in_studio.lua ({len(full) // 1024} KB, {count} scripts) and {total} parts in installer_parts/")


if __name__ == "__main__":
    main()

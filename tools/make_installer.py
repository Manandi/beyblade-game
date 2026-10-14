#!/usr/bin/env python3
"""Regenerates install_in_studio.lua: ONE script to paste into Roblox Studio's Command Bar that creates
every game script in the right place (no Rojo needed). Re-run after changing anything in src/."""
import os
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
files = [  # (path, class, service, name)
    ("src/shared/BeyConfig.lua", "ModuleScript", "ReplicatedStorage", "BeyConfig"),
    ("src/shared/BeyDesigns.lua", "ModuleScript", "ReplicatedStorage", "BeyDesigns"),
    ("src/shared/BeyVisuals.lua", "ModuleScript", "ReplicatedStorage", "BeyVisuals"),
    ("src/server/StadiumBuilder.server.lua", "Script", "ServerScriptService", "StadiumBuilder"),
    ("src/server/BeySpawner.server.lua", "Script", "ServerScriptService", "BeySpawner"),
    ("src/client/BeyController.client.lua", "LocalScript", "StarterPlayerScripts", "BeyController"),
]
out = ["-- Paste this whole file into Studio's Command Bar (View > Command Bar) and press Enter.",
       "-- It (re)creates every script. Safe to run again after an update. Then press Play.",
       "local SSS = game:GetService('ServerScriptService')",
       "local RS = game:GetService('ReplicatedStorage')",
       "local SPS = game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')",
       "local parents = { ReplicatedStorage = RS, ServerScriptService = SSS, StarterPlayerScripts = SPS }",
       "local function install(class, parentName, name, source)",
       "\tlocal parent = parents[parentName]",
       "\tlocal old = parent:FindFirstChild(name)",
       "\tif old then old:Destroy() end",
       "\tlocal s = Instance.new(class)",
       "\ts.Name = name",
       "\ts.Source = source",
       "\ts.Parent = parent",
       "end", ""]
for path, cls, svc, name in files:
    src = open(os.path.join(root, path)).read()
    assert "]=====]" not in src
    out.append(f"install('{cls}', '{svc}', '{name}', [=====[\n{src}]=====])")
out.append("print('Spinforge installed: ' .. #" + str(len(files)) + " .. ' scripts. Press Play.')".replace("#" + str(len(files)) + " .. ' scripts", str(len(files)) + " .. ' scripts") if False else "print('Spinforge installed (" + str(len(files)) + " scripts). Press Play.')")
open(os.path.join(root, "install_in_studio.lua"), "w").write("\n".join(out) + "\n")
print("wrote install_in_studio.lua")

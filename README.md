# Spinforge

A Roblox spinning-top battle game (working title). You explore an open world as your character; in a fight
you **become your bey** and steer it with WASD, jump with Space and **tilt it with the mouse**: aim up leaving
a ramp to launch higher, aim down in the air to dive, then slam. Beys level up through the story and by
grinding villains. Revenue comes from crates that drop bey parts, with every outcome and its exact odds shown.

**Status: a complete, replayable PvE fight** on branch `pve-loop` (see [HANDOFF.md](HANDOFF.md)): walk the hub,
practice, challenge **Rook the Grinder**, win or lose, earn XP and Shards, buy and equip parts in the Workshop,
rematch. Every automated check passes, but it has **not been run in Roblox Studio yet**. Design, decisions and
milestones: [PROJECT.md](PROJECT.md). Read it before changing anything.

## Try it in Studio

1. Open [`install_in_studio.lua`](install_in_studio.lua), copy all of it, paste it into Studio's **Command Bar**
   (not in Play mode) and run it. It prints `Spinforge installed: 29 scripts.`
   If the big paste fails, run `installer_parts/part_1.lua` to `part_7.lua` in order instead.
2. Press **Play**. You start on foot in the hub: **Practice** (green), **Battle** (red), **Workshop** (gold).
3. To test saving, publish the place and turn on Game Settings > Security > Enable Studio Access to API Services.

Re-run the installer after any update. It only replaces the `Spinforge` folders and keeps your imported meshes.
**With Rojo:** run `rojo serve` here and connect from the Studio plugin.

### Better-looking beys (one-time mesh import)
The bey parts are modelled in Blender ([previews](assets/previews/)). Without the meshes the game still runs,
using simple block shapes. To get the real models:
1. Download the three files in [`assets/meshes/`](assets/meshes/): `layers.fbx`, `discs.fbx` and `drivers.fbx`
   (open each on GitHub and click **Download raw file**).
2. In Studio, click **Import** (Home tab) or **File > Import 3D**, pick `layers.fbx`, and click **Import** with the default options.
3. A model named `layers` appears in the stadium area (Workspace). You can leave it there: when you press Play the game moves it
   into **ReplicatedStorage > BeyMeshes** by itself. To keep the edit view tidy, drag it there yourself.
4. Repeat for `discs.fbx` and `drivers.fbx`, then press **Play**.

Save the place (File > Save) so you don't have to import again. Re-running the installer keeps the BeyMeshes folder.
After the meshes are regenerated (`tools/blender/build_beys.py`), delete the three models in BeyMeshes and import the new files.

### Controls
| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Drive | WASD | Left stick | Drag on the left half |
| Tilt (down = lean in and go faster, up = brake) | Mouse | Right stick | Drag on the right half |
| Launch (during 3-2-1: stop the needle in the green) | Space / click | A / right trigger | LAUNCH |
| Jump | Space | A | JUMP |
| Slam (in the air) | Click | Right trigger | SLAM |
| Practice: reset / back to hub | R / Q | Y / B | Back to hub |
| Diagnostics | F6 | | |

Nose up as you leave the stadium lip to launch higher. Every tuning number is in `BeyConfig.Movement` and
`GameConfig`.

## What is in here
| Path | What |
|---|---|
| `src/shared/Core/` | The rules, as pure tested modules: `MovementCore`, `CombatCore`, `BattleCore`, `Progression`, `PlayerData`, `SessionStore` |
| `src/shared/` | `BeyConfig` (parts, stats, crate odds, movement tuning), `GameConfig` (combat, battle, villain, progression, saving), designs, visuals, `Net` (remotes) |
| `src/server/` | `Main` (startup), `World` (arena, training bowl, hub), `BeyService` (modes), `BattleService`, `VillainAI`, `DataService`, `BeyFactory`, `MeshImport` |
| `src/client/` | `Main`, `Controller` (bey + camera), `Hud`, `Menus` (Workshop, Settings), `Tutorial`, `Effects`, `OnFootFallback` |
| `tools/run_tests.py` | All tests: unit tests for the rules plus a smoke run of the real scripts in a Roblox mock (`tools/tests/`) |
| `tools/make_installer.py` | Regenerates the installer from `src/` (the tests check it's up to date) |
| `tools/blender/build_beys.py`, `assets/` | Blender modelling of all 33 parts (FBX to import, `BeyMeshData.lua`, previews) |

## Ground rules
- **Original designs only.** No Beyblade part names, designs or wiki data. A licence means a deal with the rights
  holder. The shipped title must not use "Beyblade".
- **Crates must show every outcome and its exact odds** before purchase (Roblox paid-random-items policy).
- **PvP needs Server Authority**; client-owned physics is only for fights against AI.

See [PROJECT.md](PROJECT.md) for the reasoning and the milestone list.

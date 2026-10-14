# Spinforge

A Roblox spinning-top battle game (working title). You explore an open world as your character; in a fight
you **become your bey** and steer it with WASD, jump with Space and **tilt it with the mouse**: aim up leaving
a ramp to launch higher, aim down in the air to dive, then slam. Beys level up through the story and by
grinding villains. Revenue comes from crates that drop bey parts, with every outcome and its exact odds shown.

**Status: milestone 1 (tilt, launch and slam feel).** Written but **not yet run in Roblox Studio**, so the feel
is untested. The design, decisions and milestones are in [PROJECT.md](PROJECT.md). Read it before changing anything.

## Try it in Studio

**Fastest, no tools needed**
1. Open [`install_in_studio.lua`](install_in_studio.lua) and copy all of it.
2. In Studio: **View > Command Bar**, paste, press Enter. It should print `Spinforge installed (6 scripts)`.
3. Press **Play**.

Run the paste again after any update; it replaces the old scripts.

**With Rojo:** install [Rojo](https://rojo.space), run `rojo serve` here, and connect from the Studio plugin.

### Controls
| Input | Action |
|---|---|
| WASD / left thumbstick | Move (relative to the camera) |
| Mouse / touch drag / right stick | Turn and **tilt** the bey |
| Space / jump button | Jump |
| Click / SLAM button / right trigger | Dive-slam (in the air) |
| R | Reset the bey |

A small readout (top left) shows tilt, speed and state. Every tuning number is in `BeyConfig.Movement`.

## What is in here
| Path | What |
|---|---|
| `src/shared/BeyConfig.lua` | 33 original parts, stats, level scaling, movement tuning, crate odds and rolls |
| `src/shared/BeyDesigns.lua`, `BeyVisuals.lua` | Look of every part, built in-engine from basic shapes |
| `src/server/` | Test stadium and bey spawner (slam validation) |
| `src/client/BeyController.client.lua` | Movement, tilt, launch, slam, camera, touch and gamepad |
| `tools/run_tests.sh` | Checks the config under the plain `luau` CLI: odds total exactly 100%, Ultra Legendary is +10%, simulated rolls, every part has a distinct design |
| `tools/make_installer.py` | Regenerates `install_in_studio.lua` after you change `src/` |

## Ground rules
- **Original designs only.** No Beyblade part names, designs or wiki data. A licence means a deal with the rights
  holder. The shipped title must not use "Beyblade".
- **Crates must show every outcome and its exact odds** before purchase (Roblox paid-random-items policy).
- **PvP needs Server Authority**; client-owned physics is only for fights against AI.

See [PROJECT.md](PROJECT.md) for the reasoning and the milestone list.

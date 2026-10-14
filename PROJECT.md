# Spinforge (working title) — Roblox spinning-top battle game

Read this before changing anything. Update it after each meaningful change.
This repo started inside the owner's `Manandi/god` repo (the Hollow Roots game) and was moved out on 2026-10-14; it is a separate project.

## The idea (owner, 2026-10-14)

- Open-world story mode in the style of popular Roblox games. You walk around as your character.
- In battle you **become your bey** (third or first person). Beys level up through the story and by grinding villains.
- **Controls:** WASD to move, Space to jump. The **mouse sets the bey's tilt angle**, and the tilt changes how it moves.
  Leaving a ramp aimed up launches it higher; coming down you can slam the other bey.
- **Profit:** classic Roblox crates. A cheaper crate gives a part, a dearer one gives a full bey.
- Part rarity and stats use the Attack / Defense / Stamina / Balance structure.
- Ultra Legendary parts are 10% above the best grindable part.
- Mobile and console controls are required (thumbstick tilt), not an afterthought.

## Decisions made

| Topic | Decision |
|---|---|
| Names and designs | **Original.** No real Beyblade part names, designs or wiki stat data. The stat *structure* (attack/defense/stamina/balance) is generic and fine. The owner suspects renaming is enough, but renamed copies of designs can still infringe, and licensed Roblox games get their rights by a deal with the owner of the brand. A real licence means emailing the rights holder first. "Beyblade" is also a trademark, so the shipped title must not use it. |
| Crates | Every outcome and its **exact odds** must be shown before purchase (Roblox paid-random-items policy), including indirect purchases (items bought with currency that Robux can buy). Anything that boosts odds must be explained and the displayed odds update live. Odds must total 100%. See [policy](https://create.roblox.com/docs/en-us/production/monetization/paid-random-items). Trading paid-random results has extra rules for ineligible users; design trading with that in mind. |
| Pay-to-win | Owner's call: rare parts raise stats, the grind reaches the same cap, and only the Ultra Legendary tier is 10% above it. **Open question:** in PvP that tier is a straight purchase advantage. Options are to keep Ultra Legendary out of ranked/matchmade PvP, or give it its own bracket. |
| Physics authority | Story fights vs AI villains use **client-owned physics** (cheap, no one is competing). **PvP must move to Server Authority** (Roblox's opt-in prediction system) because a client that owns a part has full say over its physics and exploiters can fake hits. Test fast spinning collisions early; mispredictions have been reported. |
| Wiki stats (owner asked 2026-10-14 to copy them for rare parts) | **Not copied.** The wiki's part catalog (real names tied to real numbers) is someone else's work, and the owner has no licence. The wiki is used only to learn the *trade-offs* (attack types give up stamina, defense types are heavy, balance types sit between). Stat weights in `BeyConfig` follow those archetypes with original numbers. If a licence deal happens, real data can be added then. |
| Fan-made 3D models (owner asked 2026-10-14) | Fan **recreations** of official beys copy Takara Tomy's designs and are not usable, whatever the uploader's licence. Fan **original** designs are usable only with a commercial licence (CC-BY/CC0 or purchased), no Beyblade branding, and not a lightly altered official bey. |
| Rarity data | `src/shared/BeyConfig.lua` is the single source. The shop UI reads odds from `GetDisplayOdds()`, never a copy. |
| Model | Sonnet 5.5 for step-by-step scripting and tuning. Opus 5.5 is worth switching to for the Server Authority move and netcode debugging. |

## What exists (milestone 1: the tilt-and-launch feel)

| File | Does |
|---|---|
| `default.project.json` | [Rojo](https://rojo.space) project: `rojo serve`, then connect from Studio. |
| `src/shared/BeyConfig.lua` | 33 original parts (3 slots × 6 rarities), level scaling, movement tuning, two crate odds tables, `RollBox`, `GetDisplayOdds`. Validates at load: odds total exactly 10000 bp, stats match each rarity's budget, Ultra Legendary is +10% of the best Legendary. |
| `src/shared/BeyDesigns.lua` | Looks of every part, as data: style, blade count, primary and accent colours. |
| `src/shared/BeyVisuals.lua` | Builds the bey from those designs out of basic parts, welded to the spinning hub: 5 layer styles (Spike, Hook, Blade, Petal, Armor), 4 disc styles, 5 driver styles. Epic+ get a glowing trim ring, Legendary+ sparks, Ultra Legendary a light. |
| `src/server/StadiumBuilder.server.lua` | Builds a round bowl stadium (flat centre, steepening rings, 72° launch lip, invisible fence) and three knockable dummies if there is no `Stadium` in Workspace. Sets gravity to 140. |
| `tools/blender/build_beys.py` | Models all 33 parts in Blender, hard-surface style (runs headless with `pip install bpy shapely mapbox_earcut`): writes `assets/meshes/*.fbx`, `src/shared/BeyMeshData.lua` and `assets/previews/*.png`. |
| `src/server/BeySpawner.server.lua` | Builds each player's bey (invisible ball body + hinged spinning disc), gives them network ownership, parks the avatar, and handles the slam hit with basic checks (distance, cooldown, value types). |
| `src/client/BeyController.client.lua` | Camera-relative movement, jump, mouse/touch/stick tilt, ramp takeoff boost, glide and dive from tilt, dive-slam, scriptable third-person camera, debug HUD, touch SLAM button. |
| `tools/run_tests.sh` | Runs `BeyConfig` under the plain `luau` CLI: validation, odds, 800k simulated rolls, and a bad-odds rejection. |

### Setup in Studio

**Fastest (no Rojo):** open `install_in_studio.lua`, copy all of it, paste into Studio's Command Bar (View > Command Bar), press Enter, then Play. It recreates every script, so run it again after each update. It is generated by `tools/make_installer.py`; re-run that after editing anything in `src/` and commit the result.

1. New Baseplate place (you can delete the default baseplate; the stadium builds its own).
2. Install Rojo, run `rojo serve`, and connect from the Studio plugin.
   Without Rojo, copy each file into: `BeyConfig` → ReplicatedStorage (ModuleScript),
   `BeySpawner` and `StadiumBuilder` → ServerScriptService (Script), `BeyController` → StarterPlayerScripts (LocalScript).
3. Press Play. WASD, hold the mouse still to keep the tilt, move it up/down to tilt.
   Run up the orange ramp with the mouse pushed forward (nose up) to launch; click in the air to slam the red dummies.
   R resets.

### Playtest log

- **2026-10-14, first Studio run:** the installer worked, and the stadium (floor, ramp, dummies) and the bey with its design
  built correctly. The controller then blocked forever on `PlayerModule:WaitForChild` (line 23), so there was no movement or camera.
  Fixed: it no longer waits on it; it uses `PlayerModule` if it loads within 10 s and otherwise its own keyboard, gamepad and touch-stick reader.
  Movement, tilt, launch and slam are still unverified.
- **2026-10-14, second run:** owner: physics "not bad", but tilt up sometimes leaned the bey down. Cause: the tilt was relative to the
  camera, not the travel direction. Fixed: the nose now points along the travel direction (camera facing when nearly still;
  `NoseMinSpeed`, `NoseTurnRate`), so nose up always means up the way the bey is going.

- **2026-10-14, third run:** owner: physics "pretty solid"; the camera broke at some tilts (it swung under the floor),
  the bey "looks terrible", and the stadium should be round. Fixed: the camera never drops below the bey and is pulled
  in front of walls; the stadium is now a bowl (flat centre, rings at 12/26/45 degrees, a 72-degree launch lip, glowing rim,
  invisible fence above it); every part now has a Blender mesh (`tools/blender/build_beys.py`, previews in
  `assets/previews/`) imported once by the owner (README). None of this has been seen in Studio yet.

- **2026-10-14, models v2:** owner said the first Blender models "look so bad" and pointed at Beyblade fan models on
  Sketchfab and stlfinder. Those are mostly recreations of official designs (not usable; see Decisions), and no usable
  original, commercially licensed models turned up. So the modeler was rewritten in a hard-surface style: each part is
  a stack of extruded 2D outlines with chamfered edges (attack rings with an inlay plate, faceted hub and emblem; machined
  metal wheels with weight holes; faceted drivers). Previews are Cycles renders. Hiring a 3D artist for hero beys remains
  the route to top quality; their meshes drop into the same import system.

### Status: untested in Studio

Nothing here has run in Roblox. It was syntax-checked with `luau-analyze` (only Roblox-type "unknown" messages),
and `BeyConfig` is covered by `tools/run_tests.sh`. Expect to tune the feel:
every number is in `BeyConfig.Movement` (launch strength, speed, glide, dive, slam, camera).

Known first-guess weak spots to look at when playtesting:
- Ground following uses one downward ray; fast sideways motion over bumps may lose ground contact.
- The avatar is anchored off to the side, so default Roblox character controls do nothing. The open world will need an on-foot mode and a bey mode.
- Body orientation (tilt) is set from the client's local `AlignOrientation`; other players see the body position and the spinning disc but not necessarily the tilt. This is solved properly by the Server Authority move.
- The slam only affects dummies. Bey-vs-bey hits, damage and spin/stamina are milestone 2.

### Designs: where they stand

Every part has a Blender mesh in two pieces (`<id>_P` primary, `<id>_A` accent) that Roblox tints from `BeyDesigns`.
The owner imports the three FBX files once into ReplicatedStorage.BeyMeshes (README). `BeyVisuals` resizes each MeshPart to
the size Blender recorded (`BeyMeshData`), so the import scale doesn't matter. **Unverified:** whether Studio's importer keeps
the orientation; if parts come in rotated, fix the export axes in `build_beys.py` or rotate in `addMesh`. If the meshes are
missing, the old block-built shapes are used. Check the previews in `assets/previews/` after changing the modelling.

## Milestones

1. **Tilt, launch and slam feel** on one stadium. *(code written, needs a Studio playtest)*
2. **Spin and stamina:** spin rate drains, collisions cost it, a bey that stops or leaves the stadium loses. Stats start to matter.
3. **One AI villain** and a battle win/lose flow, with an on-foot mode in a small area.
4. **Crates:** shop UI that displays the odds table from `BeyConfig`, server-side purchase and roll, inventory (DataStore), equip parts.
5. **Leveling:** beys gain levels from story and villain grinding (`LevelMultiplier`).
6. **Open world and story**, then PvP on Server Authority, then a ranked bracket decision.

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
| Free progression route (review, 2026-10-14) | Rarity budgets differ (Common 8 ... Legendary 30 per part), so leveling alone can't make a Common part Legendary. The free route is the **Workshop**: every rarity up to Legendary is sold for **Shards**, earned only by battling (a Legendary set is 2400 Shards, about 80 Normal wins). Level 50 gives the full level multiplier. Ultra Legendary is never sold for Shards. Budgets unchanged. |
| Paid crates (review, 2026-10-14) | **Disabled.** There is no purchase code at all. Before turning them on: per-player restrictions (ineligible users), paid-item trading rules, indirect Robux purchases, final outcomes of full-bey bundles shown, and durable, duplicate-safe granting (receipt processing with a purchase-id ledger in the player's save). |
| Competitive stats (review, 2026-10-14) | Reviewer recommends **normalised stats in ranked play** (rarity mostly cosmetic there), because a 10% budget increase can compound across speed, attack, defense and stamina, and brackets would split a small player pool. A recommendation to decide before PvP, not built. |
| Server trust (review, 2026-10-14) | Server owns spin, damage, outcomes and rewards. Client sends only "rematch / leave / forfeit", Workshop requests and a bare "slam landed" (checked against the fall the server observed). Player bey physics stays client-owned for PvE (residual exposure listed in HANDOFF.md). |
| Rarity data | `src/shared/BeyConfig.lua` is the single source. The shop UI reads odds from `GetDisplayOdds()`, never a copy. |
| Model | Sonnet 5.5 for step-by-step scripting and tuning. Opus 5.5 is worth switching to for the Server Authority move and netcode debugging. |

## What exists (PvE loop, branch `pve-loop`)

See [HANDOFF.md](HANDOFF.md) for the full change log, test results, Studio checklist and what is unverified.

| Where | Does |
|---|---|
| `src/shared/Core/MovementCore.lua` | Movement rules shared by the player and the villain: ground hysteresis, one takeoff boost per takeoff, slam state, jump cooldown, slope traction, lean/brake, sanitising, facing, recovery. |
| `src/shared/Core/CombatCore.lua` | Spin pools and drain, stat roles, bounded hit damage and knockback, contact de-duplication, slam checks against server-observed falls, ring-out with grace, rate limits. |
| `src/shared/Core/BattleCore.lua` | Battle lifecycle: countdown → active → finished (once) → cleanup; outcomes; rewards claimable once. |
| `src/shared/Core/Progression.lua`, `PlayerData.lua`, `SessionStore.lua` | XP, Shards, Workshop, equip rules; versioned save format with migration and repair; session-locked load/save that never overwrites a real save after a failed load. |
| `src/shared/BeyConfig.lua`, `GameConfig.lua` | All tuning: parts, crate odds, movement; combat, battle, villain, difficulty, progression, saving. |
| `src/server/` | `Main` (startup + checks), `World` (arena without fence, fenced training bowl, hub with prompts), `BeyService` (on foot / practice / battle modes, avatar park and restore), `BattleService`, `VillainAI`, `DataService`, `BeyFactory`, `MeshImport`. |
| `src/client/` | `Controller` (bey + camera, restores everything on unbind), `Hud`, `Menus` (Workshop, Settings), `Tutorial`, `Effects` (pooled, capped), `OnFootFallback` (if Roblox's PlayerModule is missing), `Main`. |
| `tools/run_tests.py` | Unit tests for every Core module and a smoke run of the real scripts in `tools/tests/roblox_mock.luau`; also checks the installer matches `src/`. |
| `tools/make_installer.py` | Builds `install_in_studio.lua` and `installer_parts/` (only replaces the Spinforge folders; keeps imported meshes). |
| `tools/blender/build_beys.py` | Models all 33 parts (hard-surface) → FBX, `BeyMeshData.lua`, previews. |

### Stat roles
- **Attack:** more damage dealt and a little more top speed.
- **Defense:** less damage taken and less knockback.
- **Stamina:** a bigger spin pool and slower passive spin loss.
- **Balance:** less knockback, less slam self-damage, and a little more top speed.

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

- **2026-10-14, first mesh import:** the meshes imported lying flat (orientation looks right) but stayed in Workspace,
  so the bey kept its block shapes and the parts littered the stadium. Fixed: BeySpawner moves any imported bey
  meshes from Workspace into ReplicatedStorage.BeyMeshes at start.

- **2026-10-14, night (owner asleep, asked to fix everything):** owner: gaps between parts; the bey could cruise
  upright along the steep wall; tilt should change speed (down faster, back to stop); the stadium should "collide based on
  the tilt". Fixed: parts stack flush (layer on the wheel's top, driver under its bottom, per combo); ground steering is now a
  limited push with traction falling on steep slopes, so gravity pulls you back down walls; nose-down lean adds top speed
  and acceleration, nose-up brakes; the bey leans to match the surface it is on (then the player's tilt on top), so it lies
  flat on slopes. Collision is still the 4-stud ball, which is orientation-independent. Unverified in Studio.

- **2026-10-14, overnight (owner asleep; brief from an outside review):** built the full PvE loop on branch `pve-loop`
  (see HANDOFF.md). Main changes: pure tested Core modules, hardened movement (one boost per takeoff, seam hysteresis,
  explicit slam state; nose-up now really stops you), server-owned spin/combat/outcomes/rewards, Rook the Grinder with
  telegraphed attacks, hub + practice + arena (no fence = ring-outs), Workshop progression, session-locked saving, new HUD,
  tutorial, settings, backup on-foot controls. Not yet run in Studio.

### Status

Everything automated passes (see HANDOFF.md). Nothing on `pve-loop` has been run in Roblox Studio yet.

### Designs: where they stand

Every part has a Blender mesh in two pieces (`<id>_P` primary, `<id>_A` accent) that Roblox tints from `BeyDesigns`.
The owner imports the three FBX files once into ReplicatedStorage.BeyMeshes (README). `BeyVisuals` resizes each MeshPart to
the size Blender recorded (`BeyMeshData`), so the import scale doesn't matter. **Unverified:** whether Studio's importer keeps
the orientation; if parts come in rotated, fix the export axes in `build_beys.py` or rotate in `addMesh`. If the meshes are
missing, the old block-built shapes are used. Check the previews in `assets/previews/` after changing the modelling.

## Milestones

1. **Tilt, launch and slam feel** on one stadium. *(playtested; feel tuned twice)*
2. **Spin and stamina**, meaningful stats, ring-outs. *(built on `pve-loop`, needs a Studio playtest)*
3. **One AI villain**, battle win/lose flow, on-foot hub, practice, rematch. *(built on `pve-loop`, needs a playtest)*
4. **Earnable progression and saving:** XP, Shards, Workshop, equip, DataStore with session locks. *(built on `pve-loop`; live saving unverified)*
5. **Tilt-aware combat hit geometry** (keep the ball for movement). *(next experiment; see HANDOFF.md)*
6. **Paid crates**, only after the checklist in Decisions. *(deferred)*
7. **Open world and story**, more villains; then PvP on Server Authority and the ranked-stats decision. *(deferred)*

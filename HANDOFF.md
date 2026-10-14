# Morning handoff — PvE loop (branch `pve-loop`)

**Goal tonight:** one complete, replayable fight: enter the arena → fight a villain → win or lose → earn progress →
equip an upgrade → rematch. `main` is untouched and still holds your last working version.

**Status:** built and passing every automated check below. **Nothing in this branch has been run in Roblox Studio.**
Physics, camera feel, collisions, villain behaviour on the real stadium, replication and live saving are unverified
until you playtest (checklist below).

## Install (about 1 minute)

1. Open your test place in Studio (not in Play mode).
2. Paste `install_in_studio.lua` (215 KB) into the Command Bar and click Run.
   If that paste fails, run `installer_parts/part_1.lua` … `part_7.lua` instead, **in order**. Each one is under 40 KB.
3. Output should say `Spinforge installed: 29 scripts. Press Play.`
4. Optional, to test **saving**: the place must be published (File > Publish to Roblox, private is fine), then
   Game Settings > Security > **Enable Studio Access to API Services**. Without this the game runs and shows a
   "Progress is NOT being saved" banner; that's expected.

The installer only replaces the three `Spinforge` folders. It removes the old flat scripts from earlier builds and
keeps `ReplicatedStorage.BeyMeshes`, so your imported meshes survive. Running it twice gives the same result.

## What changed (change log)

- **Structure.** Game rules now live in pure modules (`src/shared/Core/*`) with no Roblox APIs, so they're unit-tested.
  Roblox scripts are thin glue around them: server in `ServerScriptService.Spinforge`, client in
  `StarterPlayerScripts.Spinforge`, shared in `ReplicatedStorage.Spinforge`.
- **Movement hardened** (`MovementCore`, same feel and numbers):
  - Ground detection uses a sphere probe plus 0.08 s hysteresis, so slab seams don't flicker.
  - One takeoff boost per takeoff, re-armed only by landing. A jump never also gets a ramp boost.
  - Slam is an explicit state: ready → diving → exactly one impact on landing (or it expires).
  - Jump cooldown; jump, launch and slam can't stack.
  - Facing holds steady when nearly still, so it no longer flips at low speed.
  - NaN/inf velocities are repaired, extreme speeds and frame times are clamped, and a wedged bey recovers.
  - **Behaviour change:** nose-up now also cuts drive, so it actually stops you while holding W. The tests showed the
    old version never stopped.
- **Spin, stamina, combat (server-owned):**
  - Spin pool and passive drain depend on Stamina.
  - Body hits use server-observed closing speed. Damage and knockback are bounded and scale with Attack vs Defense.
  - One hit per contact: a pair must separate and wait out a cooldown before it can score again.
  - Slams are checked against the fall speed the *server* saw; the client only says "landed".
  - Ring-outs have a 0.4 s grace; falling below the floor counts at once.
  - The cosmetic hub spin follows the spin fraction and is never fed back into combat.
- **One villain battle** (`BattleService`, `VillainAI`):
  - Hub with a Challenge pedestal, a Practice pad and a Workshop kiosk (ProximityPrompts).
  - Battle flow: 3 s countdown (both beys frozen) → 90 s battle → result → Rematch / Back to hub, or it auto-closes
    after 45 s → cleanup.
  - **Rook the Grinder** drives with the same movement rules. It telegraphs a dash (red highlight and "!") and a jump
    slam (orange highlight and "!!"), recovers after attacks, avoids the rim and unsticks itself.
  - Difficulty is Normal, switching to Hard after 3 wins (Easy is also defined).
  - Outcomes: win, loss, draw (both down, or close on time), timeout, forfeit, disconnect, reset. One arena with a
    queue.
- **Training vs battle rules:** the **Training** stadium keeps the invisible fence plus dummies, with free practice,
  R to reset and Q to leave. The **Arena** has no fence: leaving it is a ring-out.
- **Progression:**
  - XP and levels (curve to 50) plus **Shards**, earned only by battling.
  - Win 40 XP / 30 Shards, draw 25 / 15, loss 15 / 8, multiplied by difficulty.
  - A loss under 20 s or a forfeit pays nothing, so quick ring-outs can't be farmed.
  - The **Workshop** sells every rarity up to Legendary for Shards. Ultra Legendary is never sold for Shards.
  - Equipping checks ownership and slot, and is blocked in battle and practice.
- **Saving (`DataService` + `SessionStore`):**
  - Versioned format (v1) with migration and repair.
  - Session lock; another live server can't load or clobber your data, and a stale lock times out.
  - Bounded retries, autosave every 2 min, save on leave and on shutdown.
  - **A failed load never overwrites the real save:** you get a temporary profile and a "not saved" banner.
- **Client:** HUD covers the spin bars, timer, countdown, hit flash and numbers, slam readiness, LOW SPIN warning,
  result screen and toasts. Also new:
  - Workshop and Settings windows (camera shake on/off, reduced effects, replay tutorial).
  - A five-step contextual tutorial.
  - Pooled, capped effects (at most 6 rings and 24 sparks).
  - F6 diagnostics.
  - JUMP and SLAM touch buttons.
  - Held input is cleared when the window loses focus.
  - The camera and mouse are **always** restored when the bey goes away.
  - **Backup on-foot controls** if Roblox's PlayerModule never loads, as in your earlier playtest.
- **Robustness:**
  - Startup checks with clear messages; bounded waits that show an on-screen error instead of hanging.
  - Characters that spawn outside the hub (e.g. a template spawn inside a stadium) are moved to the hub.
  - Light lighting polish (bloom and specular), only added if the place has none.

- **Late review fixes:**
  - An avatar-only invisible wall around each bowl (collision groups) stops people on foot from walking into the
    arena and blocking a battle. Beys pass through it, so ring-outs still work.
  - Parked avatars now wait away from the hub prompts.
  - Studio reuses one session-lock id, so a stopped test run doesn't lock saving for 10 minutes.
  - A queued player who went off to practice gets a message instead of being silently dropped.

- **Skill launch ("3, 2, 1, LET IT RIP!")** (owner request, after the night's work):
  - During the countdown a needle sweeps across a launch bar. Press once (Space / click / A / LAUNCH on touch) to
    lock it: green = PERFECT, yellow = GOOD, elsewhere or no press = weak.
  - The green zone moves every battle.
  - Quality sets three things:
    - **starting spin** (stamina): 100% at perfect, about 77% if you never press, 70% at worst
    - **launch speed** off the line, toward where the camera aims (18 to 75 studs/s)
    - a **speed boost** of up to +35%, fading over 4 s
  - The server judges the timing from the press time (stamps more than 0.6 s stale or in the future are rejected),
    and only one press counts.
  - The villain launches too, with skill set by difficulty (Easy 0.5, Normal 0.72, Hard 0.92, plus a little noise).
  - Tuning is in `GameConfig.Launch`; rules in `Core/LaunchCore.lua` (`launch.test.luau`).

## Tests: commands and actual results

```
pip install bpy shapely mapbox_earcut   # only for tools/blender/build_beys.py, not for the tests
python3 tools/run_tests.py               # needs `luau` on PATH (https://github.com/luau-lang/luau/releases)
```

Actual run, 2026-10-14:

| Suite | Result | What it covers |
|---|---|---|
| `movement.test.luau` | 23 passed | ground hysteresis and seam flicker, one boost per takeoff, repeated landing signals, jump/slam rules and cooldowns, a dive that never lands, flat/lean/brake speeds, 45° slope pulls you down, 12° slope climbable, nose-up stops you, variable timesteps (30 vs 240 fps), zero input, NaN/inf/extreme values, facing at near-zero speed, orthonormal frames, stuck detection |
| `combat.test.luau` | 13 passed | spin pools and drain, damage bounds and stat roles, contact geometry, continuous-contact de-duplication, hit cooldown, knockback bounds, slam fall/range checks, fall tracker window, ring-out and its grace, rate limiter, invalid numbers |
| `battle.test.luau` | 13 passed | countdown, stop, ring-out, simultaneous defeat = draw, timeout win/draw, finish happens once, leaving, rewards claimable once, cleanup by request and by timeout, drain with bad dt |
| `progression.test.luau` | 17 passed | level curve, rewards (and once per battle id), invalid rewards, bounded memory, Workshop buying rules, a Legendary set is reachable (2400 Shards ≈ 80 Normal wins), equip rules, save migration (new/v0/corrupt/newer), repair of bad values, save/load round trip, retries, failed load leaves the save untouched, newer save never overwritten, session locks, stale-lock takeover with the old server's save refused, save errors reported |
| `smoke.test.luau` | 25 passed | **real server + client scripts** in a small Roblox mock: startup, join, data load, client start, challenge → countdown (frozen) → start (ownership) → villain AI runs → one hit per contact → slam refused without a fall / accepted after one → ring-out win with one reward → rematch → forfeit pays nothing → leave restores avatar and camera → Workshop UI equip → settings saved → practice (tutorial advances when you drive) → queue → disconnect mid-battle → reset mid-battle → timeout and auto-close → save on leave → failed DataStore = unsaved temporary profile → shutdown saves → backup on-foot controls → no infinite-yield warnings or script errors |
| `launch.test.luau` | 7 passed | needle sweep, moving green zone, perfect/good/weak quality, press validation (stale, future, outside the meter), effects on spin/speed/boost, boost fade, villain launch skill |
| `config.test.luau` | passed | crate odds total 100%, 400k simulated rolls, Ultra = +10%, designs and mesh data for every part |
| bad crate odds | passed | a crate whose odds total 100.01% refuses to load |
| installer check | passed | the committed installer matches `src/` |

**Known failures:** none.

**What the tests do NOT prove:**
- The mock has no physics, collisions, stadium slopes, rendering, replication or network delay.
- Passing means the scripts start, wire up and follow their rules. It says nothing about how it *feels* or how
  Roblox physics reacts.

## Automatically tested vs engine-unverified vs deferred

| Automatically tested | Implemented, unverified in Roblox | Deferred |
|---|---|---|
| All rules in `Core/*` (movement maths, combat, battle lifecycle, rewards, Workshop, equip, save format, sessions) | How movement *feels*; the sphere probe on the real stadium seams; slope physics with real gravity | Open world, story, more villains |
| Script wiring end to end in the mock (server + client) | Villain behaviour on the real bowl (does it get stuck, fall out, feel fair?) | Paid crates, purchases, trading (off: no purchase code exists) |
| Rewards at most once per battle; no reward for forfeits/quick losses | Knockback strength, hit damage and spin numbers in real fights | Ranked PvP, Server Authority |
| Failed loads never overwrite; locks; retries | Live DataStore behaviour (needs a published place + API access) | Wholesale physics rewrite |
| Installer reproducible | Mobile/console controls and UI layout on real devices | Tilt-aware collider (see below) |
| | Camera behaviour on slopes and near walls; backup on-foot controls | Server-side movement validation |
| | Multiplayer replication (other players see your tilt? see risks) | |

## Ten-minute Studio checklist

Note the result of each step (✓ / ✗ + a screenshot of anything red in Output).

1. **Install** (Command Bar). Output: `Spinforge installed: 29 scripts.` Press Play.
2. **Startup.** Output shows `Spinforge server ready: world built, N of 66 bey meshes available…` with no red text.
   You spawn on the blue pad in the hub. The arena is right beside it; the training bowl is further out (you are teleported to both).
3. **Walk.** WASD moves your avatar and the camera follows. If you see "Backup controls on", note it: your
   PlayerModule is missing.
4. **Practice** (green pad, hold E). You become your bey in the fenced training bowl, and tutorial step 1 appears.
   Drive, lean down (faster) and lean back (stops?). Step through the tutorial.
5. **Seams.** Drive in circles across the ring boundaries and press F6. Does "ground" stay "yes" while you're
   clearly on the floor? Does flips/s stay near 0?
6. **Launch.** Ride up the wall, nose up at the lip, and fly. Does the fence catch you? Land a **slam** near a red
   dummy (click in the air): it should get knocked away.
7. **Back to hub** (Q). Is the avatar back on the pad, walking, with the normal camera? Try walking into the arena
   bowl on foot: an invisible wall should stop you at the rim.
8. **Villain fight** (red pedestal). Countdown 3-2-1 with the launch bar: press Space when the needle is in the
   green. Does it say PERFECT, and do you shoot off the line where you're aiming? Try a fight without pressing
   (TOO LATE, less spin).
   - Rook shows a red "!" before dashing and an orange "!!" before jumping.
   - Hit it: your number pops on its bar. Get hit: red flash.
   - LOW SPIN warns near the end.
9. **Ring-out.** Launch off the arena lip and keep going: you should lose by ring-out after about 0.4 s outside.
   Then try knocking Rook out.
10. **Result.** Check that the rewards show, then press **Rematch**: a fresh countdown with no leftover beys.
    Then **Forfeit**: "No reward for forfeiting". Then **Back to hub**.
11. **Workshop** (gold kiosk). Buy a Common part (20 Shards) and equip it. Start a fight and check the bey looks
    different. Try equipping mid-battle: it's refused.
12. **Reset** (Esc > Reset Character) during a battle. You should be back in the hub with controls working.
13. **Saving** (only if published with API access). Leave and rejoin: your level, Shards and parts are still there,
    and there's no "not saved" banner.
14. **Controls.** On a gamepad: right stick tilts, A jumps, right trigger slams, Y/B in practice. With Studio's
    device emulator (phone): left-half drag drives, right-half drag tilts, JUMP and SLAM buttons work, and nothing
    overlaps.

## Device input checklist

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Drive | WASD | Left stick | Drag on the left half (or Roblox's thumbstick) |
| Tilt (down = lean in, up = brake) | Mouse | Right stick | Drag on the right half |
| Launch (during 3-2-1) | Space or click | A or right trigger | LAUNCH button |
| Jump | Space | A | JUMP button |
| Slam (in the air) | Left click | Right trigger | SLAM button |
| Challenge / Practice / Workshop | Hold E at the prompt | Prompt button (X) | Tap the prompt |
| Rematch / Back to hub | Click | Selected button + A | Tap |
| Practice reset / leave | R / Q | Y / B | "Back to hub" button |
| Diagnostics | F6 | — | — |

## Residual exploit exposure (client-owned physics)

The player's bey uses client-owned physics, so a cheater can move their bey and fake its velocity. Server-side
checks limit the damage:
- Hit damage is bounded.
- Each contact counts once.
- A slam needs a fall the server saw.
- Rewards come only from server-decided outcomes, once per battle id.
- Forfeits and quick losses pay nothing.
- Requests are rate limited.

A cheater could still teleport into the villain or out of the ring-out zone. That affects PvE rewards, which are
small and bounded per battle. Before PvP, or before Shards matter for anything paid, move to Server Authority and add
server-side movement validation.

## Remaining blockers and decisions for you

1. **Playtest in Studio** (checklist above). It's the only way to check feel, villain fairness and physics.
2. **Saving needs a published place** with Studio API access to verify live; otherwise it runs "not saved" by design.
3. **Tilt-aware collision** is still unanswered. The collider is still the 4-stud ball, and only the visual leans.
   Suggested next experiment: keep the ball for movement, but make *combat* hit geometry tilt-aware (a flattened
   disc oriented by the bey's lean). It isn't built, because changing the physical collider without Studio testing
   is risky.
4. **Ultra Legendary in PvP:** the reviewer recommends normalised stats in ranked play. That's a decision for later,
   not tonight.
5. **Other players may not see your tilt** (it's set client-side on a server-created constraint). The fix is part of
   the Server Authority move.

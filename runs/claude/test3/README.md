# Island Royale: Stage 3 (Godot 4.5)

A 50-player third-person battle royale built in Godot 4.5 (GL Compatibility renderer, Jolt physics). You play against
49 bots on an 800 m island with forest, snow and desert biomes. Playable builds are in the repo root under `builds/`:
`IslandRoyale-windows.zip` and `IslandRoyale-android.apk`.

```
runs/claude/test3/
├── game/          the Godot project (open project.godot)
├── assets_src/    Blender build scripts for the guns and the upgrade bench (see assets_src/README.md)
├── tools/         icon / app-art generators, reference images
└── captures/      screenshots produced by the test and screenshot runs
```

## What's in a match

| | |
|---|---|
| **Front end** | Battle-royale style lobby: PLAY / LOCKER / CAREER / SETTINGS tabs, spinning character stage with emotes, level and XP bar, matchmaking then countdown, lobby music. 16 outfits on two bodies. |
| **Warm-up** | A 20 s warm-up on the island before the bus: no damage, looting or building. It can be skipped in Settings. |
| **Drop** | A blimp crosses the island for 50 s. Skydive, then **E** deploys the glider (an on-screen prompt shows the key). |
| **Island** | 800 m, chunked terrain, rivers, towns, mesas, snow in the north and desert in the south. Minimap (900 m) and a full map on **M**. |
| **Bosses and vaults** | Three bosses guard their own named locations: **Weaver** (web-slinger) at Frostpeak, **Ravage** (tendril creature) at Sandbar Depot, **Tinker** (mech pilot) at Gearworks Yard. Each has a boss health bar and drops its mythic weapons, gold and a **keycard** that opens the vault beside the lair, which holds three golden chests of top loot. |
| **Mythic weapons** | Weaver's Web Shooters (swing on web lines), Ravage's Grasp (yank and slam an enemy, or pull yourself to a wall), Tinker's Charge Shotgun (hold to charge, up to 2x damage) and Tinker's Shockwave Launcher (launches players, wrecks builds). They only come from bosses. |
| **Named places** | Ten locations named on both maps, with an "ENTERING" banner as you walk in, and skulls on the map where bosses are alive. |
| **Weapons** | Nine guns with five rarities: pistol, pump and tactical shotguns, SMG, assault, burst and hunting rifles, bolt sniper, rocket launcher. Also grenades and launch pads. Reloads are animated (the magazine comes out). First shots are accurate after a short rest. |
| **Heals** | Bandages, med kit, healing drink, small and big shields, hydro juice (health and shield), mega flask. |
| **Building** | Wall, floor, stairs and cone in wood, brick or metal, with edits and weak points. The material switches automatically to one you have. Every structure, houses included, can be farmed and collapses, and the loot inside drops to the ground. |
| **Combat feedback** | Damage numbers on every hit. The crosshair turns red on an enemy's head, and headshots show yellow numbers and a HEADSHOT tag. |
| **Movement** | Tactical sprint (hold Shift: faster, gun lowered), hurdle low fences and crates at a run, crouch, slide, mantle, swim, step-up onto ledges, zip lines (8), rifts (10) and launch pads. |
| **Gold** | A fourth collectible, dropped by floor loot, chests and supply drops. |
| **Upgrade benches** | Raise a weapon's rarity for 100 / 150 / 200 / 250 gold. |
| **NPCs** | Six characters at points of interest. Talk to one (**E**) and hire them for gold, and they fight beside you. |
| **Storm** | A shrinking circle with scaled phases that starts at a 620 m radius. |
| **Bots** | Easy / normal / sweaty. They loot first, look for ammo and swap out junk, build cover, ramps and box-ups, farm, breach, use upgrade benches, and take rifts, pads and zip lines to beat the storm. |
| **After the match** | A summary screen ("LAST ONE STANDING"), XP and career stats. |
| **Settings** | Graphics (including **Show FPS**), audio (including music volume), controls (including phone **auto fire**). The pause menu has the same settings. |

## Controls

**Keyboard and mouse**

| Action | Key |
|---|---|
| Move / jump | WASD / Space |
| Walk (you run by default) | hold right mouse |
| Tactical sprint | hold Shift |
| Hurdle / mantle | Space while running at a low obstacle / a ledge |
| Crouch / slide | Ctrl |
| Fire / aim | left / right mouse |
| Weapon slots | 1–5, mouse wheel |
| Pickaxe | F |
| Reload | R |
| Interact (loot, doors, glider, zip lines, benches, NPCs) | E |
| Build wall / floor / stairs / cone | Q / Z / C / V |
| Change building material | right mouse while building |
| Edit | G |
| Inventory / drop item | Tab / X |
| Map / emote | M / B |
| Mark a spot (landing, rotation) | M, then click the map (click it again or right-click to clear) |
| Pause | Esc |

**Phone:** a joystick, drag-to-look and icon buttons laid out like a mobile battle royale. The buttons are fire on both
sides, jump, crouch, aim, build/weapons toggle, the build pieces, edit, reload, material, inventory, emote, map/menu, and
an auto-fire toggle. A "use" button appears only when there's something to interact with.

## Running it

Open `game/project.godot` in Godot 4.5 and press Play, or use an exported build. Useful command-line flags
(after `--`): `--profile` prints per-system frame timings, `--demo` lets a bot drive the player, and `--autotest` plays a whole
match headless and prints match stats (add `--trace` to log bot decisions).

## Tests

Each suite is headless and prints one `PASS`/`FAIL` line per check:

```bash
godot --headless --path game -- --buildtest
```
```bash
godot --headless --path game -- --movetest
```
```bash
godot --headless --path game -- --eventtest
```
```bash
godot --headless --path game -- --invtest
```
```bash
godot --headless --path game -s scripts/flowtest.gd
```

| Suite | Checks | Covers |
|---|---|---|
| buildtest | 45 | Placing, editing, collapse, harvesting, explosions |
| movetest | 45 | Crouch, slide, mantle, swim, step-up, tactical sprint, hurdle |
| eventtest | 151 | Consumables, pads, zips, rifts, supply drops, spare ammo, auto material, walking out of houses, house collapse and loot fall, gold, benches, reloads, hiring, mythic weapons, bosses, keycards, vaults, named places |
| invtest | 22 | Inventory screen |
| flowtest | 22 | Menu → lobby → warm-up → match → summary → play again → pause → leave |

## How it was built

- **Island:** `scripts/build_island.gd` generates the terrain, biomes, towns, props and minimap into
  `scenes/island.tscn`. `scripts/bake_nav.gd` bakes the bots' 1 m navigation grid, which marks walls, water and
  doorways.
- **Models:** the guns and the upgrade bench are modelled in Blender from Python scripts in `assets_src/`, with
  vertex colours. The builder converts them into `game/meshes/`. Characters are Mixamo models; see
  `game/assets/characters/CREDITS.md`, and replace them with your own Adobe downloads before publishing.
- **Audio:** the lobby and battle music, the sound effects and the trailer voice-over were generated with ElevenLabs.
- **Art:** the app icon and splash were generated by an image model and then cleaned up by `tools/make_app_art.py`.
- **Trailer:** recorded from real gameplay with `game/tools/trailer_director.gd` and `trailer_flyover.gd`.
- **Performance:** with 50 players on screen, the game uses distance-based character LOD, a baked height grid instead
  of physics rays, throttled bot searches and adaptive path re-planning. Use `--profile` to see the cost of each
  system.

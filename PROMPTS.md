# AI Battle Royale: the prompts

Plain-text extract of `brief.html` (the Brief tab of the report). The reference images each asset card points to are in `images/references/`.

The prompts as the models received them. \<MODEL> stands for each model's own short id, and the paths are the ones used on the machine that ran the test. Asset messages combine the shared prompt with one spec card.

3D assetsMap creationGame

## 3D assets

## Shared prompt

## TOOLS

Blender 5.1 is installed at: C:\Program Files\Blender Foundation\Blender 5.1\blender.exe
Work only by writing Python (bpy) scripts and running them headless: blender.exe --background --python \<script.py>
Everything must be built procedurally from scratch in your script: primitives, modifiers, bmesh, curves, geometry nodes are all fine.
Forbidden: downloading models or textures, image-to-3D or text-to-3D tools, add-ons that generate assets, tracing the reference image as a texture on a plane. You may look at the reference image as much as you want.

## WORK FOLDER

C:\Users\\<USER>\Documents\work\videos\ai-battle-royale\runs\\<MODEL>\test1
  Replace \<MODEL> with a short lowercase id of the AI model you are (for example claude-opus-5-5, gpt-6-sol, grok-4-7, muse-wonder).
Create a subfolder named after the asset id, containing:
  build_\<id>.py    the script that builds the asset from an empty scene
  \<id>.blend       the saved scene
  \<id>.glb         glTF binary export
  preview_\<id>.png one image with 4 views side by side: side, 3/4, front, back (or the views named in the asset message)
  report_\<id>.md   short report
Re-running build_\<id>.py must rebuild everything from zero and overwrite the outputs.

## ART STYLE (match the reference image)

Stylized cartoon battle royale look: chunky, slightly exaggerated proportions, big readable shapes, soft rounded bevels on every hard edge, low amount of small detail.
Clean surfaces, no dirt. Hand-painted feel is achieved with flat base colors plus soft gradients (vertex colors or a simple gradient in the material), lighter top surfaces and slightly darker bottoms.
Take colors from the reference image. Use Principled BSDF materials only, roughness about 0.6-0.8, metallic 0 for painted parts and up to 0.6 for bare metal. No image textures unless you generate them procedurally in the script and pack them into the .glb.

## TECHNICAL RULES

Units: meters. Z is up. The front of the asset faces -Y (Blender front view). Weapons: barrel points to -Y.
Real-world scale as given in the asset message (tolerance 10%).
Origin: bottom center at Z=0 for props and buildings; for weapons and hand-held items the origin is at the grip where the hand holds it.
Apply all modifiers and transforms before export. Clean meshes: no loose vertices, no zero-area faces, normals facing outward, smooth or flat shading chosen per part so it looks clean.
Name every object and material meaningfully (e.g. rifle_body, rifle_magazine, mat_tan).
Parts that move in a game (lids, doors, triggers when asked) must be separate objects with the pivot placed where they rotate.
Stay under the triangle budget given in the asset message.
Export .glb with +Y up (default glTF settings), modifiers applied, materials included.

## PROCESS

Look at the reference image first and write a short plan: parts list, dimensions, colors.
Build, render the preview, then LOOK at your own preview and compare it with the reference. Fix obvious differences in proportions, colors and missing parts before you report. At most 3 self-correction loops per asset.
When done, reply with: the path to preview_\<id>.png, the triangle count, and one sentence on what is weakest.

## Grenade

Size: about 0.11 m tall, body diameter 0.08 m.

Triangle budget: 2,500.

## Bushes

Size: Each bush: about 1.4 m wide and 1.1 m tall.

Triangle budget: 4,000 per bush.

## Rocks

Size: Five rocks: about 0.4, 1.0, 2.2, 1.0 (wide and flat), and 0.7 m tall.

Triangle budget: 1,500 per rock.

## Farm props

Size: Fence: 2.0 m long, 1.1 m tall; barrel: 0.9 m tall, 0.65 m wide; crate: 0.8 m cube.

Triangle budget: 2,000 per prop.

## Ammo box

Size: about 0.50 m wide (X), 0.25 m deep (Y), 0.25 m tall without the handle.

Triangle budget: 5,000.

## Medkit

Size: case about 0.45 m wide (X), 0.30 m deep (Y), 0.15 m tall; bandage roll 0.08 m diameter, 0.10 m tall.

Triangle budget: 4,000.

## Shield potion

Size: about 0.25 m tall, 0.22 m wide.

Triangle budget: 4,000.

## Chest

Size: about 1.00 m wide (X), 0.65 m deep (Y), 0.75 m tall with the lid closed.

Triangle budget: 8,000.

## Pistol

Size: about 0.24 m long (Y), 0.16 m tall.

Triangle budget: 3,000.

## Shotgun

Size: about 0.95 m long (Y).

Triangle budget: 6,000.

## Assault rifle

Size: about 0.85 m long (Y), 0.25 m tall including the sight.

Triangle budget: 8,000.

## Sniper rifle

Size: about 1.25 m long (Y).

Triangle budget: 9,000.

## Rocket launcher

Size: about 1.30 m long (Y), tube diameter about 0.16 m, front flare about 0.26 m.

Triangle budget: 8,000.

## Supply drop

Size: crate about 1.20 m cube; parachute canopy about 4 m in diameter, its top about 5 m above the crate.

Triangle budget: 15,000 for everything.

## Trees

Size: Oak: about 6 m tall; pine: about 9 m; palm: about 6 m.

Triangle budget: 6,000 per tree.

## Building modules

Size: every piece fits a 4 m x 4 m cell. Wall: 4 m wide, 4 m tall, 0.25 m thick. Floor: 4 x 4 m, 0.25 m thick. Ramp: rises 4 m over 4 m. Pyramid roof: 4 x 4 m base, about 2 m tall.

Triangle budget: 2,500 per piece.

## Lookout tower

Size: about 10 m tall to the roof tip, platform about 3 m x 3 m at 7 m height, legs spread to about 4 m x 4 m at the base.

Triangle budget: 12,000.

## Warehouse

Size: about 14 m wide (X), 10 m deep (Y), 5 m walls, gabled roof ridge about 7 m.

Triangle budget: 20,000.

## House

Size: footprint about 8 m x 7 m, two floors of 3 m each, gabled roof ridge about 9 m above the ground.

Triangle budget: 30,000.

## Pickaxe

Size: about 1.0 m tall (handle along Z), head about 0.6 m wide.

Triangle budget: 4,000.

## Drop vehicle

Size: bus about 10 m long (Y), 2.6 m wide, 3.2 m tall; balloon about 8 m wide and 6 m tall, its bottom about 3 m above the bus roof; total height about 13 m.

Triangle budget: 30,000.

## Map creation

Build one game level in Unity, fully on your own, starting right now. Do not ask for confirmation and do not wait for further messages: plan, build, capture, self-check and report in this one turn.

YOUR MODEL ID: \<MODEL>
(Use it in every path below. Never read or use another model's folders.)

## TOOLS

Unity 6000.5.6f1: C:\Program Files\Unity\Hub\Editor\6000.5.6f1\Editor\Unity.exe
Work only through C# editor scripts run in batch mode, for example: Unity.exe -batchmode -projectPath \<project> -executeMethod \<Class.Method> -quit -logFile \<log>. Add -nographics only for steps that do not render; screenshots and video capture need graphics. Read the log after every run.
Create the project with: Unity.exe -batchmode -nographics -createProject \<project> -quit -logFile \<log>. Keep the default Built-in Render Pipeline.
Unity does not import .glb out of the box. Either add the official glTFast package (com.unity.cloud.gltfast) to Packages/manifest.json, or convert the .glb files to FBX with a Blender script. Make sure materials and colors survive the import.
Also available: Blender 5.1 at C:\Program Files\Blender Foundation\Blender 5.1\blender.exe and ffmpeg on PATH.
Allowed: official Unity packages from the Unity registry. Forbidden: Asset Store or downloaded models, textures, terrains or prefabs, and any AI image or 3D generation. Every object in the level comes from your own test 1 assets or is built procedurally by your scripts (terrain, water, roads, bridges).

## PATHS

Unity project (short path on purpose, keep it): C:\Users\\<USER>\unity-br\\<MODEL>-test2
Your test 1 assets: C:\Users\\<USER>\Documents\work\videos\ai-battle-royale\runs\\<MODEL>\test1\\<asset_id>\ (21 assets, .glb files)
Map reference: C:\Users\\<USER>\Documents\work\videos\ai-battle-royale\references\test2-map\island-map-topdown.png
Asset reference sheets: C:\Users\\<USER>\Documents\work\videos\ai-battle-royale\references\test1-assets\
Outputs: C:\Users\\<USER>\Documents\work\videos\ai-battle-royale\runs\\<MODEL>\test2\

## SCALE AND LAYOUT

The island is about 400 x 400 m inside a 600 x 600 m ocean area. The map has a 6 x 6 grid over the whole image, so one grid cell is about 67 m in this level.
Take from the map: zone positions, coastline shape, lake, river, road network, bridge and tower positions.
Do NOT take building sizes from the map: buildings there are drawn about 4 times too large. Every asset keeps its real test 1 size. Trees and rocks may vary in scale by up to 25 percent for variety.

## TERRAIN AND WATER (procedural)

Unity Terrain with a scripted heightmap: hills and the lake basin in the north, a flat village center, gentle farm fields, a sandy east beach, rocky cliffs on the south point, high ground under the towers, a river channel from the lake to the south coast.
Terrain layers made in code (grass, sand, dirt road, rock): generate their textures as Texture2D colors or noise and save them as assets.
Ocean at sea level around the island, water surfaces for the lake and the river, two wooden bridges over the river.

## ZONES (positions from the map)

North: pine forest of at least 150 pines, the lake, rock clusters including the moss rocks.
North-east: farm with crop fields, fence lines made of tiled fence segments, barrels, crates, one house as the farmhouse.
East: beach with at least 30 palms.
Center: village of 6 to 8 houses around a plaza, at least 4 treasure chests inside the houses.
South-west: industrial yard with the 3 warehouses, crates, ammo boxes, a paved yard, and one small fort built from the modular kit (walls, floors, ramps, roofs).
West: oak forest of at least 120 oaks with a few clearings.
South cliff point and two other hilltops: the 3 lookout towers.
Everywhere: bushes and rocks; loot spread across the island (treasure chests, ammo boxes, med kits, shield potions, and every weapon type lying on the ground at least 3 times); one landed supply drop; the cargo blimp flying 80 m above the island.

## GAME READINESS

Colliders on the terrain, buildings, rocks, tree trunks and props: a player must not fall through anything or walk through walls. Doors and interiors of the test 1 assets stay usable.
30 player spawn points: empty GameObjects named Spawn_01 to Spawn_30, spread over the island on walkable ground, never inside objects.
Hierarchy grouped by zone, one prefab per asset, static batching or GPU instancing for vegetation.
Performance target: 60+ FPS at 1920x1080 on this PC. Measure the average frame time over at least 600 frames of the flythrough, in a Windows build or in play mode, and report the method.
Save the scene as Assets/Scenes/Island.unity. Re-running your build method must rebuild the whole level from zero.

## Game

## Battle royale core

One player against 24 bots, with the full match loop. Fortnite is the main reference: the goal is to make the game as close to Fortnite as possible in gameplay, visuals, movement, combat, building, UI and overall feel.

Drop: the bus is the cargo blimp. It crosses the island 150 m up and covers 600 m in 40 s.

The player jumps whenever they want. Skydiving lets you steer and dive.

The glider opens on its own 42 m above the ground.

Storm: five phases with timers. Each new safe circle lies inside the previous one.

Damage outside the circle goes around shields and grows from 1 to 10 HP per second.

The storm wall is animated purple; the screen turns purple when you are inside the storm.

Inventory: five slots plus the pickaxe.

Five rarities from grey to gold. Each step adds 6 % damage and makes reloads 5 % faster.

Ammo types: light, medium, heavy, shells, rockets.

Grenades stack. Heals and shields take time to use.

Loot:

118 loot spots, chests and ammo boxes.

Items on the ground glow in their rarity colour; ammo and free-slot items are picked up by walking over them.

Eliminated players drop everything.

Bots: they move on a navigation mesh with line-of-sight perception and skill-based reaction and aim. They:

arm up first, pick a weapon by range, strafe and fire in bursts;

heal, loot and leave the storm in time;

hunt other players late in the match.

HUD in the Fortnite layout:

health and shield, hotbar, ammo, compass, minimap and full map with the storm;

kill feed, damage numbers, hit markers, arcs showing the direction of incoming damage;

spectating after elimination and the Victory Royale screen.

## Building, harvesting, destruction

Building: the 12 modular_kit pieces (wall, floor, stairs, cone in wood, brick and metal).

Pieces snap to a 4 m grid with 4 m storeys. Keys are Q / Z / C / V.

A see-through preview shows where the piece goes. RMB cycles the material; holding LMB keeps placing (turbo build).

A piece costs 10 of a material. Its hit points climb while it builds: wood 150, brick 300, metal 450.

Harvesting: the pickaxe hits the point under the crosshair.

A blue weak point appears after each hit and gives double damage and double materials.

Material counters with +N popups.

Destruction: 1,791 level parts break (trees, rocks, crates, doors, roofs and more).

Explosions do 2.5 times their damage to structures.

When a piece breaks, everything that loses its connection to the ground collapses in a chain.

Bots: they harvest when they run short of materials and drop a wall towards whoever is shooting them.

## Movement

Crouch: Left Ctrl toggles it. The character gets lower, slower and steadier, and a crouched player can hide behind low cover.

Slide: Ctrl while sprinting. The slide speeds up downhill, slows down on flat ground and ends in a crouch.

Mantle: Space at a ledge from 0.75 to 2.3 m high pulls the character up onto it. It also works from the water onto a steep bank.

Swimming: in the lake, the river and the sea.

The weapon is put away. Standing still treads water; moving swims.

Entering the water makes a splash, swimming leaves foam, and a fall into deep water does no damage.

Bots: they crouch while healing and sometimes in fights at range, cross rivers by swimming, and mantle when they jump at a ledge.

## Build fights and smarter bots

This is what makes Fortnite fights look like Fortnite.

Piece editing:

An edit grid on a wall, floor, stairs or cone.

Selected tiles are cut out to make windows, doors, half walls, turned ramps and cones with an opening.

A reset key restores the piece.

Bot build fighting:

a ramp rush to take height on an enemy;

a quick 1x1 box when healing or under fire;

replacing walls that get shot out;

peeking out of an edited window.

Bot difficulty: easy, normal and sweaty, from aim, reaction time and build speed.

Material economy: bots harvest early in the match so they have materials for fights.

## Items, traversal and world events

Supply drops: they fall from the sky under a balloon, using the existing supply_drop asset. They have a smoke trail and better loot.

Mobility items:

launch pads, placed and thrown;

zip lines between hills and towers;

a rift that sends you back into skydiving.

More consumables: small and big shield potions, a healing drink, and an apple or mushroom picked up from the ground.

## Front end and presentation

Menus:

a main menu with the character on a podium;

a pre-match lobby with a ready button;

pause and settings (sensitivity, key bindings, graphics);

an end-of-match summary.

Emotes and dances from Mixamo, with an emote wheel.

Sound: a proper sound pass.

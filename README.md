# AI Battle Royale gallery (partial mirror)

A copy of the public "AI Battle Royale" comparison folder: Claude Opus 5.5, GPT-6.1 Sol, Gemini 4 Argon and Muse Wonder given the same Fortnite-style brief in three stages (Blender assets, Unity island, battle royale against 24 bots).

Open `index.html` in a browser. `README.txt` is the original note from the folder.

## What is here

| Path | Contents |
| --- | --- |
| `index.html`, `brief.html`, `assets.html`, `map.html`, `gameplay.html`, `verdict.html`, `costs.html`, `app/` | The report viewer and its data |
| `PROMPTS.md` | Plain-text extract of the prompts on the Brief tab |
| `images/` | 534 reference sheets, posters and review screenshots |
| `blender/` | 84 `.blend` asset sets, 21 per model (Blender 5.1) |
| `videos/<model>/assets/` | 220 asset turntable recordings |

## Godot replication (`runs/claude/`)

This repo also contains a replication of the challenge, built in Godot 4.5 instead of Unity. The Stage 3 game (50 players,
an island with snow and desert biomes, building, gold, upgrade benches, NPCs for hire, three bosses with keycard vaults and mythic weapons) is in `runs/claude/test3/`.
Its README covers the features, controls and tests. Ready-to-play builds are `builds/IslandRoyale-windows.zip` and
`builds/IslandRoyale-android.apk`.

## What is not here

The remaining 187 recordings (`videos/<model>/maps`, `mechanics`, `manual`, `archive`, about 23 GB) and the four Unity project archives (`Unity-Projects-2026-11-01/`, about 1.3 GB) are left out: 86 of those files are over GitHub's 100 MB per-file limit. The Map and Gameplay tabs therefore show posters but their videos will not play from this copy. Get them from the original Drive folder and place them next to `index.html`:

https://drive.google.com/drive/folders/1m8i97CRq840_Z82H2fnhUNzWnGTythow

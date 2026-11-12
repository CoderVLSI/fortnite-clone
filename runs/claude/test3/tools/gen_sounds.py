#!/usr/bin/env python3
"""Generate game sound effects with ElevenLabs sound-generation. Skips existing files.
Usage: ELEVENLABS_API_KEY=... python3 gen_sounds.py"""
import os, sys, json, time, urllib.request, urllib.error

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "sounds")
URL = "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128"

# (name, prompt, duration_seconds, loop)
SOUNDS = [
    ("shot_pistol", "cartoon pistol shot, short punchy bang, arcade shooter", 0.6, False),
    ("shot_shotgun", "cartoon shotgun blast with pump action, loud boom, arcade shooter", 1.0, False),
    ("shot_rifle", "cartoon assault rifle single shot, sharp crack, arcade shooter", 0.6, False),
    ("shot_sniper", "big sniper rifle crack with long echo, arcade shooter", 1.5, False),
    ("shot_rocket", "rocket launcher firing, whoosh launch, cartoon", 1.2, False),
    ("explosion", "cartoon explosion boom, big blast with debris, not gory", 1.8, False),
    ("grenade_throw", "short throw whoosh, light swing", 0.6, False),
    ("reload_light", "light gun magazine reload clicks, quick", 1.0, False),
    ("reload_heavy", "heavy gun reload, metallic clunks and slide", 1.5, False),
    ("shell_pump", "pump action shotgun pump chunk-chick", 0.7, False),
    ("empty_click", "empty gun dry fire click", 0.5, False),
    ("pickaxe_hit_wood", "pickaxe hitting wood, hollow thunk", 0.5, False),
    ("pickaxe_hit_stone", "pickaxe hitting stone, sharp chink with rock crunch", 0.5, False),
    ("pickaxe_hit_metal", "pickaxe hitting metal, bright clang", 0.6, False),
    ("weak_point", "bright cartoon ding, short sparkly bell hit", 0.5, False),
    ("break_wood", "wooden wall breaking apart, planks cracking and falling, cartoon", 1.2, False),
    ("break_stone", "stone wall crumbling, rocks collapsing, cartoon", 1.2, False),
    ("build_place", "wooden thunk of a building piece placed, short", 0.5, False),
    ("footstep_grass_1", "single footstep on grass, soft", 0.5, False),
    ("footstep_grass_2", "single footstep on grass and dirt, soft rustle", 0.5, False),
    ("footstep_wood", "single footstep on wooden floor, creak thud", 0.5, False),
    ("jump", "short cartoon jump effort whoosh, no voice", 0.5, False),
    ("land", "soft landing thud on ground", 0.5, False),
    ("swim_stroke", "single swimming stroke splash in water", 0.8, False),
    ("splash", "big water splash, jumping into water", 1.0, False),
    ("glider_open", "glider fabric opening, flapping whoosh", 1.0, False),
    ("skydive_wind", "strong wind rushing while skydiving, seamless loop", 4.0, True),
    ("storm_loop", "eerie low rumble ominous storm drone, seamless loop", 6.0, True),
    ("storm_enter", "ominous warning sting, low dark swell", 1.5, False),
    ("pickup", "light pop item pickup, cartoon", 0.5, False),
    ("chest_open", "treasure chest opening with sparkly magical chime", 1.5, False),
    ("heal_use", "gentle healing sound, soft bandage and rising chime", 1.2, False),
    ("shield_use", "magical shimmer shield potion drink, glittery", 1.5, False),
    ("hit_marker", "short tick hit marker feedback click", 0.5, False),
    ("elimination", "satisfying bright ding elimination confirmation, arcade", 0.8, False),
    ("hurt", "light body hit thud, no voice, short", 0.5, False),
    ("victory", "short triumphant fanfare, brass, cartoon victory", 3.0, False),
    ("launch_pad", "spring boing whoosh launch pad, cartoon", 1.0, False),
    ("zip_line", "metal cable pulley whirring, zip line, seamless loop", 3.0, True),
    ("rift", "magical warp teleport rift whoosh", 1.5, False),
    ("supply_drop_land", "heavy crate landing thud with dust", 1.0, False),
    ("ui_click", "soft ui button click", 0.5, False),
    ("ui_ready", "short positive ui confirm chime", 0.6, False),
]


def gen(key, name, prompt, dur):
    body = json.dumps({"text": prompt, "duration_seconds": dur, "prompt_influence": 0.5}).encode()
    req = urllib.request.Request(URL, data=body, method="POST",
                                 headers={"xi-api-key": key, "Content-Type": "application/json"})
    last = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.read(), r.headers
        except urllib.error.HTTPError as e:
            if e.code in (401, 402, 403, 422, 429):
                print("FATAL %s on %s: %s" % (e.code, name, e.read()[:300]))
                sys.exit(2)
            last = e
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            last = e
        time.sleep(2 * (attempt + 1))
    print("FAILED %s: %s" % (name, last))
    return None, None


def main():
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        sys.exit("ELEVENLABS_API_KEY not set")
    os.makedirs(OUT, exist_ok=True)
    for name, prompt, dur, loop in SOUNDS:
        path = os.path.join(OUT, name + ".mp3")
        if os.path.exists(path):
            continue
        data, hdr = gen(key, name, prompt, dur)
        if data is None:
            continue
        with open(path, "wb") as f:
            f.write(data)
        used = hdr.get("character-cost") or hdr.get("x-character-count") or ""
        print("saved", name, len(data), "bytes", ("cost=" + used) if used else "", flush=True)


if __name__ == "__main__":
    main()

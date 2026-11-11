"""Generates the HUD and inventory icons with an image model on OpenRouter.

Each item icon is drawn from a render of the game's own 3D asset, so it matches the model in the game.
The model is asked for a flat magenta background, which is keyed out to transparency here.

    OPENROUTER_API_KEY=... python3 gen_icons.py [name ...]
"""
import base64, io, json, os, sys, time, urllib.request
from PIL import Image

MODEL = "google/gemini-3.1-flash-lite-image"
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(HERE, "..", "game")
TEST1 = os.path.join(HERE, "..", "..", "test1")
OUT = os.path.join(GAME, "textures", "icons")
STYLE = ("Stylized cartoon battle royale video game inventory icon. Chunky shapes, bold dark outline, soft hand-painted "
         "shading, bright clean colours, three-quarter view, centred, filling about 80 percent of the square frame. "
         "Flat solid pure magenta background (#FF00FF) and nothing else behind the object: no shadow, no glow, no border, "
         "no text, no letters, no numbers.")

# name -> (asset render to use as reference or None, description)
ICONS = {
    "pistol": ("pistol", "this pistol: tan frame and dark grey slide"),
    "shotgun": ("shotgun", "this pump shotgun: tan stock and receiver, olive pump grip, dark barrels"),
    "assault_rifle": ("assault_rifle", "this assault rifle: tan body, olive magazine and grip, small red dot sight"),
    "sniper_rifle": ("sniper_rifle", "this bolt-action sniper rifle with an olive scope and a folded bipod"),
    "rocket_launcher": ("rocket_launcher", "this rocket launcher: olive tube with tan flared muzzle and collars"),
    "grenade": ("grenade", "this olive hand grenade with a grey lever and pull ring"),
    "medkit": ("medkit", "this tan medical kit case with a red cross on the lid"),
    "shield_potion": ("shield_potion", "this round glass flask of glowing blue liquid with a cork and a dark strap"),
    "pickaxe": ("pickaxe", "this pickaxe with a black handle, grey head and a yellow band"),
    "ammo_light": (None, "a small stack of three short brass pistol bullets with light yellow tips"),
    "ammo_medium": (None, "a small stack of three medium brass rifle bullets with orange tips"),
    "ammo_heavy": (None, "two long heavy sniper rifle bullets with blue-grey tips"),
    "ammo_shells": (None, "three red shotgun shells with brass bases"),
    "ammo_rockets": (None, "one small olive green rocket with fins"),
    "mat_wood": (None, "a neat stack of three orange-brown wooden planks"),
    "mat_brick": (None, "a small stack of red bricks"),
    "mat_metal": (None, "a stack of two grey-blue corrugated metal sheets with rivets"),
    "build_wall": (None, "a single square wooden building wall panel with a frame and rivets, front view"),
    "build_floor": (None, "a single square wooden floor tile seen from above at an angle"),
    "build_stairs": (None, "a single wooden ramp, seen from the side, rising to the right"),
    "build_cone": (None, "a single wooden pyramid roof piece"),
    "storm": (None, "a swirling purple storm cloud with a lightning bolt"),
    "alive": (None, "a simple white person silhouette symbol, head and shoulders"),
    "elims": (None, "a simple white skull symbol"),
    "shield": (None, "a glossy blue shield symbol"),
    "health": (None, "a glossy green plus sign medical cross symbol"),
    "edit": (None, "a simple white grid of three by three squares with the middle square highlighted blue"),
    "small_shield": (None, "a small round glass bottle of glowing light blue liquid with a cork, a little shield potion"),
    "healing_drink": (None, "a tall glass bottle of glowing green healing drink with a cork and a white label with a red cross"),
    "launch_pad": (None, "a round blue launch pad platform with yellow upward chevron arrows on top, seen from above at an angle"),
    "supply_drop": ("supply_drop", "this olive armoured supply crate with glowing blue strips, hanging under an orange and cream striped parachute"),
}


def reference(asset):
    """The first view (side) of the asset's 4-view preview, as a PNG data URL."""
    if asset is None:
        return None
    im = Image.open(os.path.join(TEST1, asset, "preview_%s.png" % asset)).convert("RGB")
    w, h = im.size
    n = max(1, round(w / h))
    side = im.crop((0, 0, w // n, h)) if asset not in ("medkit", "shield_potion", "grenade", "pickaxe") else im.crop((w // n, 0, 2 * w // n, h))
    buf = io.BytesIO()
    side.resize((512, 512)).save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def generate(name):
    asset, desc = ICONS[name]
    text = STYLE + " The object: " + desc + "."
    content = [{"type": "text", "text": text + (" Draw the object shown in the reference image, keeping its shape and colours." if asset else "")}]
    ref = reference(asset)
    if ref:
        content.append({"type": "image_url", "image_url": {"url": ref}})
    body = json.dumps({"model": MODEL, "messages": [{"role": "user", "content": content}], "modalities": ["image", "text"]}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
                                 headers={"Authorization": "Bearer " + os.environ["OPENROUTER_API_KEY"], "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                res = json.loads(r.read())
            break
        except Exception as e:
            print("  retry", name, e)
            time.sleep(5 * (attempt + 1))
    else:
        return None
    msg = res["choices"][0]["message"]
    imgs = msg.get("images") or []
    if not imgs:
        print("  no image for", name, str(msg.get("content"))[:200])
        return None
    data = imgs[0]["image_url"]["url"].split(",", 1)[1]
    raw = os.path.join(OUT, "raw", name + ".png")
    open(raw, "wb").write(base64.b64decode(data))
    usage = res.get("usage", {})
    return raw, usage.get("cost"), usage.get("completion_tokens")


def key_out(raw, dst, size=128):
    """Magenta background -> transparent, trimmed and fitted into a square."""
    im = Image.open(raw).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            # distance from magenta: magenta has high red and blue and low green
            m = min(r, b) - g
            if m > 90 and abs(r - b) < 90:
                px[x, y] = (0, 0, 0, 0)
            elif m > 40 and abs(r - b) < 100:
                k = (m - 40) / 50.0                      # soft edge, and pull the pink tint out of it
                px[x, y] = (int(r - (r - g) * k * 0.6), g, int(b - (b - g) * k * 0.6), int(255 * (1 - k)))
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    side = max(im.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(im, ((side - im.size[0]) // 2, (side - im.size[1]) // 2))
    sq = sq.resize((int(size * 0.92),) * 2, Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(sq, ((size - sq.size[0]) // 2, (size - sq.size[1]) // 2))
    out.save(dst)


if __name__ == "__main__":
    names = sys.argv[1:] or list(ICONS)
    total = 0.0
    for n in names:
        r = generate(n)
        if r is None:
            continue
        raw, cost, toks = r
        key_out(raw, os.path.join(OUT, n + ".png"))
        total += cost or 0.0
        print("ICON", n, "cost", cost, "tokens", toks)
    print("TOTAL cost %.4f USD for %d icons" % (total, len(names)))

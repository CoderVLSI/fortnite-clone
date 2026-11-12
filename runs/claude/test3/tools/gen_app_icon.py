"""App icon candidates for Island Royale from the same cheap image model as the item icons (OpenRouter,
google/gemini-3.1-flash-lite-image), with a render of the real island as the reference.
Writes raw candidates to the folder given as the first argument; make_app_art.py turns the chosen one into icons."""
import base64, json, os, sys, time, urllib.request

MODEL = "google/gemini-3.1-flash-lite-image"
PROMPT = ("Mobile game app icon for a cartoon battle royale game set on an island. Show a small tropical island seen at an "
          "angle from above, floating in a bright turquoise ocean: green hills in the middle, a snowy mountain on one side, "
          "a golden desert with a red mesa on the other side, a winding blue river. A glowing purple storm ring circles the "
          "island. Above it flies a small blimp with an orange-and-white striped balloon. Bold, vibrant, glossy, chunky "
          "low-poly cartoon style like the reference render, strong contrast, centred composition that fills a square "
          "icon, simple sky gradient behind. Absolutely no text, no letters, no numbers, no logos, no characters.")


def ref(path):
    data = open(path, "rb").read()
    return "data:image/jpeg;base64," + base64.b64encode(data).decode()


def main(out, reference, n=2):
    os.makedirs(out, exist_ok=True)
    total = 0.0
    for i in range(n):
        content = [{"type": "text", "text": PROMPT}, {"type": "image_url", "image_url": {"url": ref(reference)}}]
        body = json.dumps({"model": MODEL, "messages": [{"role": "user", "content": content}], "modalities": ["image", "text"]}).encode()
        req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
                                     headers={"Authorization": "Bearer " + os.environ["OPENROUTER_API_KEY"], "Content-Type": "application/json"})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    res = json.loads(r.read())
                break
            except Exception as e:
                print("retry", e)
                time.sleep(5 * (attempt + 1))
        else:
            continue
        imgs = res["choices"][0]["message"].get("images") or []
        if not imgs:
            print("no image", str(res["choices"][0]["message"].get("content"))[:200])
            continue
        open(os.path.join(out, "icon_%d.png" % i), "wb").write(base64.b64decode(imgs[0]["image_url"]["url"].split(",", 1)[1]))
        cost = res.get("usage", {}).get("cost") or 0.0
        total += cost
        print("candidate", i, "cost", cost)
    print("TOTAL %.4f USD" % total)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 2)

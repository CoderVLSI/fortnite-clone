"""Turns the chosen icon (tools/app_icon_source.png, made by gen_app_icon.py) and a render of the island into the
game's branding: the app icon in every size the Windows and Android exports want, and the boot splash screen.
  python make_app_art.py <island render.jpg>"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "game", "branding")
FONTS = "/usr/share/fonts/opentype/inter/"
ACCENT = (250, 158, 36)

os.makedirs(OUT, exist_ok=True)
src = Image.open(os.path.join(HERE, "app_icon_source.png")).convert("RGB")
side = min(src.size)
src = src.crop(((src.width - side) // 2, (src.height - side) // 2, (src.width + side) // 2, (src.height + side) // 2))
src.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))                       # project / window icon
src.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "icon_192.png"))                   # Android launcher
src.resize((432, 432), Image.LANCZOS).save(os.path.join(OUT, "icon_adaptive_bg.png"))           # Android adaptive: the art is the layer
Image.new("RGBA", (432, 432), (0, 0, 0, 0)).save(os.path.join(OUT, "icon_adaptive_fg.png"))     # (nothing on top: the launcher crops the art)
src.save(os.path.join(OUT, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

# splash: the island from the air, darkened, with the title
W, H = 1920, 1080
bg = Image.open(sys.argv[1]).convert("RGB").resize((W, H), Image.LANCZOS)
bg = ImageEnhance.Brightness(bg).enhance(0.62)
shade = Image.new("L", (W, H), 0)
d = ImageDraw.Draw(shade)
for y in range(H):                                         # darker towards the bottom
    d.line([(0, y), (W, y)], fill=int(150 * (y / H) ** 1.6))
bg = Image.composite(Image.new("RGB", (W, H), (8, 10, 20)), bg, shade)
img = bg.convert("RGBA")


def text_layer(lines):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(layer)
    for txt, font, size, col, y, track in lines:
        f = ImageFont.truetype(font, size)
        widths = [dr.textlength(c, font=f) for c in txt]
        x = (W - (sum(widths) + track * (len(txt) - 1))) / 2
        for c, w in zip(txt, widths):
            dr.text((x, y), c, font=f, fill=col)
            x += w + track
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.putalpha(layer.split()[3].point(lambda v: int(v * 0.75)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(shadow, (6, 10))
    out.alpha_composite(layer)
    return out


img.alpha_composite(text_layer([("ISLAND", FONTS + "InterDisplay-Black.otf", 190, (255, 255, 255, 255), 270, 14),
                                ("ROYALE", FONTS + "InterDisplay-Black.otf", 190, ACCENT + (255,), 475, 14),
                                ("DROP IN.  BUILD UP.  BE THE LAST ONE STANDING.", FONTS + "InterDisplay-SemiBold.otf", 40, (255, 255, 255, 235), 735, 4),
                                ("Made with Godot", FONTS + "InterDisplay-SemiBold.otf", 24, (255, 255, 255, 150), 1000, 3)]))
img.convert("RGB").save(os.path.join(OUT, "splash.png"))
print("branding written to", os.path.abspath(OUT))

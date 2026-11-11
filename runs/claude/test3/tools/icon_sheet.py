"""Lays every icon out on one sheet, on a dark and a light tile, for review."""
import os, sys
from PIL import Image, ImageDraw
d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "textures", "icons")
names = sorted(f[:-4] for f in os.listdir(d) if f.endswith(".png"))
cols = 7
cell = 150
sheet = Image.new("RGBA", (cols * cell, ((len(names) + cols - 1) // cols) * (cell + 18)), (30, 34, 40, 255))
draw = ImageDraw.Draw(sheet)
for i, n in enumerate(names):
    x, y = (i % cols) * cell, (i // cols) * (cell + 18)
    tile = Image.new("RGBA", (cell - 10, cell - 10), (55, 75, 110, 255) if i % 2 == 0 else (150, 150, 150, 255))
    ic = Image.open(os.path.join(d, n + ".png")).convert("RGBA").resize((cell - 22, cell - 22))
    tile.alpha_composite(ic, (6, 6))
    sheet.alpha_composite(tile, (x + 5, y + 5))
    draw.text((x + 8, y + cell - 2), n, fill=(230, 230, 230, 255))
sheet.save(sys.argv[1])
print(len(names), "icons")

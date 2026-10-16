"""Generates assets/nature/grass_short.png: a strip of short grass blades on a transparent background,
colored to match grass_clump.png, with some dried-out yellow blades for winter.

Run from the project root:  python3 tools/make_short_grass.py
"""
import math
import random

from PIL import Image, ImageDraw

W, H = 512, 256
SS = 4  # supersampling for smooth blade edges
OUT = "assets/nature/grass_short.png"

rng = random.Random(1717)
img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

GREENS = [(38, 50, 26), (52, 72, 30), (61, 85, 37), (74, 104, 38), (86, 121, 40)]
DRY = [(112, 104, 58), (128, 118, 66), (96, 88, 52)]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def blade(x0, height, lean, width, base, tip):
    # a tapered, slightly curved blade drawn as stacked quads from the root up to a point
    steps = 14
    pts_l, pts_r = [], []
    for k in range(steps + 1):
        t = k / steps
        x = x0 + lean * height * t * t
        y = H * SS - height * t
        half = width * (1.0 - t) ** 0.8 / 2.0
        # blade's sideways direction follows the curve
        dx = 2.0 * lean * height * t
        dy = -height
        n = math.hypot(dx, dy)
        nx, ny = -dy / n, dx / n
        pts_l.append((x - nx * half, y - ny * half))
        pts_r.append((x + nx * half, y + ny * half))
    for k in range(steps):
        t = k / steps
        col = lerp(base, tip, t)
        draw.polygon([pts_l[k], pts_r[k], pts_r[k + 1], pts_l[k + 1]], fill=col + (255,))


# a handful of separate tufts with gaps between them, so the strip's outline is ragged, not a flat hedge
TUFTS = [(rng.uniform(0.1, 0.9), rng.uniform(0.06, 0.13), rng.uniform(0.55, 1.0)) for _ in range(6)]


def pick_root():
    cx, spread, peak = rng.choice(TUFTS)
    x = min(0.97, max(0.03, rng.gauss(cx, spread)))
    # blades are tallest at a tuft's middle and short at its edges
    falloff = math.exp(-((x - cx) / (spread * 1.3)) ** 2)
    return x, peak * (0.3 + 0.7 * falloff)


# back rows darker and taller, front rows lighter and shorter
for layer in range(3):
    for _ in range(200):
        x, tall = pick_root()
        x0 = x * W * SS
        height = rng.uniform(0.45, 1.0) * tall * H * SS * (1.0 - 0.15 * layer)
        lean = rng.uniform(-0.35, 0.35)
        width = rng.uniform(2.5, 5.5) * SS
        if rng.random() < 0.22:
            base, tip = rng.choice(DRY), rng.choice(DRY)
            tip = lerp(tip, (170, 160, 110), 0.3)
        else:
            base = lerp(rng.choice(GREENS[:2]), (0, 0, 0), 0.15 * (2 - layer))
            tip = rng.choice(GREENS[2:])
        blade(x0, height, lean, width, base, tip)

img = img.resize((W, H), Image.LANCZOS)
img.save(OUT) # Godot's importer bleeds the edge colors into the clear pixels (fix_alpha_border)
print("wrote", OUT)

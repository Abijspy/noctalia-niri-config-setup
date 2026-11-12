#!/usr/bin/env python3
# Regenerate the bundled wallpapers:  python3 tools/gen-wallpapers.py configs/wallpapers
# Needs numpy and Pillow.
# Original wallpapers in Noctalia's built-in palette. Procedurally generated.
import numpy as np
from PIL import Image, ImageFilter
import sys
W, H = 3840, 2160
OUT = sys.argv[1]
rng = np.random.default_rng(7)
def hexc(h): return np.array([int(h[i:i+2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255
SURF, OUTL, SEC, PRI, TER, ERR, DIM = map(hexc, ["070722", "21215f", "a9aefe", "fff59b", "9bfece", "fd4663", "7c80b4"])
y, x = np.mgrid[0:H, 0:W].astype(np.float32)
u, v = x / W, y / H
def vgrad(top, bot, power=1.0):
    t = (v ** power)[..., None]; return top * (1 - t) + bot * t
def glow(cx, cy, r, col, strength=1.0):
    d = np.sqrt(((x - cx * W) / W) ** 2 + ((y - cy * H) / W) ** 2)
    return (np.exp(-(d / r) ** 2) * strength)[..., None] * col
def stars(img, n, maxb=1.0):
    xs = rng.integers(0, W, n); ys = rng.integers(0, int(H * 0.75), n); b = rng.random(n) ** 3 * maxb
    for xx, yy, bb in zip(xs, ys, b):
        img[yy, xx] = np.clip(img[yy, xx] + bb, 0, 1)
        if bb > 0.5 and 1 <= xx < W - 1 and 1 <= yy < H - 1:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)): img[yy + dy, xx + dx] = np.clip(img[yy + dy, xx + dx] + bb * 0.35, 0, 1)
    return img
def finish(img, name, grain=0.012):
    img = img + rng.normal(0, grain, img.shape).astype(np.float32)   # grain: no banding
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(f"{OUT}/{name}.jpg", quality=90, optimize=True, progressive=True)
    print("wrote", name)

# 1. Moonrise — crescent moon with a soft yellow halo over deep navy
img = vgrad(SURF * 0.6, OUTL * 0.9, 1.4)
img += glow(0.72, 0.32, 0.12, PRI * 0.16) + glow(0.72, 0.32, 0.35, SEC * 0.10)
mx, my, mr = 0.72 * W, 0.32 * H, 0.085 * H * 1.9
disc = np.sqrt((x - mx) ** 2 + (y - my) ** 2) < mr
cut = np.sqrt((x - (mx + mr * 0.42)) ** 2 + (y - (my - mr * 0.18)) ** 2) < mr * 0.95
moon = (disc & ~cut).astype(np.float32)
moon = np.array(Image.fromarray((moon * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.5)), dtype=np.float32) / 255
img = img * (1 - moon[..., None]) + (PRI * 0.97)[None, None, :] * moon[..., None]
img = stars(img, 1800, 0.9)
finish(img, "noctalia-moonrise")

# 2. Aurora — mint and lavender ribbons
img = vgrad(SURF * 0.5, SURF * 1.3, 1.0)
for i, (col, amp, freq, phase, yc, wdt, s) in enumerate([
        (TER, 0.06, 2.2, 0.0, 0.34, 0.035, 0.55), (SEC, 0.05, 1.7, 1.3, 0.42, 0.05, 0.45),
        (TER, 0.04, 3.1, 2.1, 0.28, 0.02, 0.35), (SEC, 0.07, 1.2, 0.7, 0.50, 0.07, 0.25)]):
    center = yc + amp * np.sin(freq * 2 * np.pi * u + phase) + 0.02 * np.sin(7 * np.pi * u + i)
    band = np.exp(-((v - center) / wdt) ** 2)
    below = v - center                                   # soft curtain hanging under the ribbon
    curtain = np.exp(-np.clip(below, 0, None) / 0.06) * (below > 0)
    rays = 0.75 + 0.25 * np.sin(u * 140 + i * 3) ** 2
    img += ((band * 0.9 + curtain * 0.22 * rays) * s)[..., None] * col
img = stars(img, 1400, 0.7)
img += vgrad(np.zeros(3), OUTL * 0.25, 3.0)
finish(img, "noctalia-aurora")

# 3. Dunes — layered hills under a low moon
img = vgrad(SURF * 0.7, SEC * 0.35, 1.8)
img += glow(0.28, 0.40, 0.18, PRI * 0.35)
mdisc = np.sqrt((x - 0.28 * W) ** 2 + (y - 0.40 * H) ** 2) < 0.07 * H
img[mdisc] = PRI * 0.95
img = stars(img, 900, 0.6)
layers = [(0.58, OUTL * 1.1, 0.045, 1.3, 0.4), (0.66, OUTL * 0.8, 0.04, 2.0, 1.7),
          (0.75, SURF * 1.6, 0.035, 2.6, 3.1), (0.86, SURF * 1.0, 0.03, 3.3, 0.9)]
for base, col, amp, freq, ph in layers:
    ridge = base + amp * np.sin(freq * 2 * np.pi * u + ph) + amp * 0.5 * np.sin(freq * 4.7 * np.pi * u + ph * 2)
    mask = (v > ridge)
    shade = np.clip((v - ridge) * 3, 0, 1)[..., None]
    img = np.where(mask[..., None], col * (1 - shade * 0.35) + SURF * shade * 0.2, img)
finish(img, "noctalia-dunes")

# 4. Waves — flowing lavender/mint lines
img = vgrad(SURF * 0.8, OUTL * 0.7, 1.0)
for k in range(46):
    t = k / 45
    center = 0.25 + 0.55 * t + 0.08 * np.sin(2 * np.pi * (u * 1.3 + t * 0.9)) + 0.03 * np.sin(2 * np.pi * (u * 3.1 - t))
    line = np.exp(-((v - center) / 0.0016) ** 2)
    col = SEC * (1 - t) + TER * t
    fade = 0.25 + 0.75 * np.sin(np.pi * u) ** 1.5
    img += (line * fade * 0.22)[..., None] * col
img += glow(0.5, 0.55, 0.45, SEC * 0.08)
img = 1 - np.exp(-img * 1.6)                         # soft tone-map: no white hot spots
finish(img, "noctalia-waves", 0.01)

# 5. Nebula — soft colour clouds
small = np.zeros((H // 8, W // 8, 3), np.float32) + SURF
sy, sx = np.mgrid[0:H // 8, 0:W // 8].astype(np.float32)
for col, n, s in [(OUTL, 10, 0.55), (SEC, 7, 0.16), (TER, 4, 0.12), (ERR, 3, 0.07), (PRI, 2, 0.05)]:
    for _ in range(n):
        cx, cy, r = rng.random() * W / 8, (0.15 + rng.random() * 0.7) * H / 8, (0.04 + rng.random() * 0.12) * W / 8
        small += (np.exp(-(((sx - cx) ** 2 + (sy - cy) ** 2) / r ** 2)) * s)[..., None] * col
small = np.array(Image.fromarray((np.clip(small, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)).resize((W, H), Image.BICUBIC), np.float32) / 255
img = 1 - np.exp(-(small * 0.95 + SURF * 0.05) * 1.4)
img = stars(img, 2600, 0.8)
finish(img, "noctalia-nebula", 0.014)

# 6. Orbit — minimal concentric rings
img = vgrad(SURF * 0.9, SURF * 1.25, 1.0) + glow(0.62, 0.5, 0.3, OUTL * 0.5)
d = np.sqrt((x - 0.62 * W) ** 2 + (y - 0.5 * H) ** 2) / H
for i, r in enumerate(np.linspace(0.12, 0.95, 11)):
    ring = np.exp(-((d - r) / 0.0011) ** 2)
    ang = (np.arctan2(y - 0.5 * H, x - 0.62 * W) + np.pi) / (2 * np.pi)
    arc = ((ang * (1 + i % 3) + i * 0.13) % 1 < 0.72).astype(np.float32)
    img += (ring * (0.55 if i % 4 else 0.85) * (0.35 + 0.65 * arc))[..., None] * (SEC if i % 4 else PRI)
pdx, pdy = 0.62 * W + 0.47 * H * np.cos(2.2), 0.5 * H + 0.47 * H * np.sin(2.2)
img[np.sqrt((x - pdx) ** 2 + (y - pdy) ** 2) < 0.012 * H] = TER
img += glow(pdx / W, pdy / H, 0.02, TER * 0.6)
finish(img, "noctalia-orbit", 0.01)

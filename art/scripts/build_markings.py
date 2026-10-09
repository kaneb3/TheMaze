"""Procedural wall markings for Ring 1 (decals): the marks people really leave on old walls.

  python art/scripts/build_markings.py <out dir>

For each mark writes <name>_albedo.png (RGBA; alpha = where the mark is) and <name>_normal.png
(OpenGL, from a carved-groove height field so the lantern rakes across it):
  tally   - scratched tally marks, groups of five (prisoners, lost walkers counting days)
  daisy   - an apotropaic "daisy wheel" (hexafoil) scribed with compasses
  initials- carved initials and a date
  burn    - teardrop taper-burn marks (another protective mark found in old buildings)
  arrow   - a chalk arrow (a hook for player-made wayfinding later)
"""

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
S = 512
rng = random.Random(7)


def noise_layer(scale, seed):
    r = random.Random(seed)
    small = Image.new("L", (S // scale, S // scale))
    small.putdata([r.randint(0, 255) for _ in range(small.size[0] * small.size[1])])
    return small.resize((S, S), Image.BICUBIC)


def jitter_line(d, p0, p1, width, fill, wobble=2.0):
    n = 12
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((p0[0] + (p1[0] - p0[0]) * t + rng.uniform(-wobble, wobble),
                    p0[1] + (p1[1] - p0[1]) * t + rng.uniform(-wobble, wobble)))
    d.line(pts, fill=fill, width=width, joint="curve")


def normal_from_height(h, strength=3.0):
    px = h.load()
    out = Image.new("RGB", h.size)
    po = out.load()
    for y in range(S):
        for x in range(S):
            dx = (px[min(S - 1, x + 1), y] - px[max(0, x - 1), y]) / 255.0 * strength
            dy = (px[x, min(S - 1, y + 1)] - px[x, max(0, y - 1)]) / 255.0 * strength
            nx, ny, nz = -dx, dy, 1.0  # OpenGL: +Y up in tangent space, image rows run down
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            po[x, y] = (int((nx / ln * 0.5 + 0.5) * 255), int((ny / ln * 0.5 + 0.5) * 255), int((nz / ln * 0.5 + 0.5) * 255))
    return out


def save(name, mask, height, color, roughen=0.0, write_normal=True):
    """mask: L (where the mark shows), height: L (128 flat, lower = carved), color: RGB tint."""
    grain = noise_layer(4, hash(name) & 0xFFFF)
    a = Image.composite(mask, Image.new("L", (S, S)), grain.point(lambda v: 255 if v > 255 * roughen else 0)) if roughen else mask
    alb = Image.new("RGBA", (S, S), (*color, 0))
    alb.putalpha(a.filter(ImageFilter.GaussianBlur(0.8)))
    alb.save(os.path.join(OUT, f"mark_{name}_albedo.png"))
    if write_normal:
        normal_from_height(height.filter(ImageFilter.GaussianBlur(2.5)), strength=6.0).save(
            os.path.join(OUT, f"mark_{name}_normal.png"))


def stroke(d, pts, w, fill):
    """A hand-cut stroke along a polyline: width wanders 60-140%, the ends taper, and now and then
    the cut skips where the chisel slipped or the stone has flaked."""
    dense = []
    for a, b in zip(pts, pts[1:]):
        n = max(2, int(math.dist(a, b) / 2))
        for i in range(n):
            t = i / n
            dense.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    dense.append(pts[-1])
    phase = rng.uniform(0, 6.3)
    gap_at = rng.uniform(0.2, 0.8) if rng.random() < 0.35 else -1.0
    for i, (x, y) in enumerate(dense):
        t = i / max(1, len(dense) - 1)
        if gap_at >= 0 and abs(t - gap_at) < 0.04:
            continue
        taper = min(1.0, t / 0.12, (1 - t) / 0.12)
        r = w * 0.5 * (1.0 + 0.4 * math.sin(phase + t * 9.0) * rng.uniform(0.6, 1.0)) * (0.35 + 0.65 * taper)
        d.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def carved(draw_fn, name, depth=150):
    """A carved mark in two ages, sharing one groove normal map: fresh (a dull pale scratch through
    the grime, ~15-25% lighter than the stone) and old (filled with grime, darker than the stone)."""
    state = rng.getstate()
    mask = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(mask), 255)
    rng.setstate(state)
    height = Image.new("L", (S, S), 128)
    draw_fn(ImageDraw.Draw(height), 128 - depth // 2)
    m = mask.point(lambda v: int(v * 0.85))
    save(name + "_fresh", m, height, (214, 204, 184), roughen=0.14, write_normal=False)
    save(name + "_old", m, height, (22, 18, 14), roughen=0.1, write_normal=False)
    normal_from_height(height.filter(ImageFilter.GaussianBlur(2.5)), strength=6.0).save(
        os.path.join(OUT, f"mark_{name}_normal.png"))


def tally(d, fill):
    x = 70
    for group in range(3):
        n = 5 if group < 2 else 3
        xs = []
        for i in range(4 if n == 5 else n):
            top = 150 + rng.uniform(-12, 12)
            length = 200 * rng.uniform(0.85, 1.15)
            tilt = math.radians(rng.uniform(-5, 5))
            bottom = (x + math.sin(tilt) * length, top + math.cos(tilt) * length)
            mid = ((x + bottom[0]) / 2 + rng.uniform(-3, 3), (top + bottom[1]) / 2)
            stroke(d, [(x, top), mid, bottom], 12, fill)
            xs.append(x)
            x += 26 + rng.uniform(-4, 6)
        if n == 5:  # the gate slash: uneven and off-centre
            y0 = rng.uniform(290, 345)
            stroke(d, [(xs[0] - rng.uniform(8, 22), y0), (xs[-1] + rng.uniform(10, 26), y0 - rng.uniform(110, 160))], 11, fill)
        x += 40


def daisy(d, fill):
    c = (S / 2 + rng.uniform(-5, 5), S / 2 + rng.uniform(-5, 5))
    r = 170.0
    wob = [rng.uniform(-0.03, 0.03) for _ in range(8)]

    def rad(a):  # slightly out of round, as scribed freehand around a wandering compass point
        return r * (1.0 + sum(w * math.sin((k + 1) * a + k) for k, w in enumerate(wob)) / 2.5)

    def arc(cx, cy, rr, a0, a1, w):
        pts = []
        steps = 40
        for i in range(steps + 1):
            a = a0 + (a1 - a0) * i / steps
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        # a flaked gap or two along the arc
        cut = rng.randint(0, 1)
        if cut:
            k = rng.randint(8, steps - 8)
            stroke(d, pts[:k], w, fill)
            stroke(d, pts[k + rng.randint(2, 5):], w, fill)
        else:
            stroke(d, pts, w, fill)

    ring = [(c[0] + rad(a) * math.cos(a), c[1] + rad(a) * math.sin(a)) for a in [i * math.tau / 120 for i in range(121)]]
    k = rng.randint(20, 100)
    stroke(d, ring[:k], 10, fill)
    stroke(d, ring[k + 4:], 10, fill)
    for j in range(6):
        a = j * math.pi / 3
        ox, oy = c[0] + r * math.cos(a), c[1] + r * math.sin(a)
        arc(ox, oy, r * rng.uniform(0.98, 1.02), a + math.radians(120), a + math.radians(240), 8)
    d.ellipse((c[0] - 5, c[1] - 5, c[0] + 5, c[1] + 5), fill=fill)


def initials(d, fill):
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", 120)
    except OSError:
        font = ImageFont.load_default()
    d.text((70, 110), "W · H", font=font, fill=fill)
    try:
        small = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", 86)
    except OSError:
        small = font
    d.text((120, 270), "1791", font=small, fill=fill)


carved(tally, "tally")
carved(daisy, "daisy", depth=120)
carved(initials, "initials", depth=150)

# taper burns: soot teardrops, slightly scooped, with a lighter scorched halo
mask = Image.new("L", (S, S), 0)
height = Image.new("L", (S, S), 128)
dm, dh = ImageDraw.Draw(mask), ImageDraw.Draw(height)
for cx, cy, s in ((180, 300, 1.0), (300, 250, 0.8), (360, 340, 0.6)):
    w, h = 46 * s, 120 * s
    dm.ellipse((cx - w, cy - h * 0.25, cx + w, cy + h * 0.75), fill=255)
    dm.polygon([(cx - w * 0.9, cy), (cx, cy - h), (cx + w * 0.9, cy)], fill=255)
    dh.ellipse((cx - w * 0.8, cy - h * 0.15, cx + w * 0.8, cy + h * 0.7), fill=100)
mask = mask.filter(ImageFilter.GaussianBlur(14))
save("burn", mask, height, (24, 18, 14), roughen=0.15)

# chalk arrow: pale, dry, broken by the stone's texture
mask = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(mask)
jitter_line(d, (90, 280), (380, 250), 22, 255, wobble=5)
jitter_line(d, (380, 250), (300, 170), 20, 255, wobble=5)
jitter_line(d, (380, 250), (310, 340), 20, 255, wobble=5)
save("arrow", mask, Image.new("L", (S, S), 128), (214, 210, 196), roughen=0.45)
print("markings written to", OUT)

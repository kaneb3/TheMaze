"""Build the Ring 1 foliage atlas from CC0 ambientCG leaf scans (LeafSet017 English ivy, LeafSet022
laurel/privet-like, LeafSet024 beech-like) and report each leaf's rectangle for card generation.

  python art/scripts/build_leaf_atlas.py <dl_textures dir> <out dir>

Quadrants of a 2048 atlas: TL ivy (017), TR laurel (022), BL beech (024), BR ivy aged (017, darker
and yellower). Writes leaf_albedo.png (RGBA, colour bled into the transparent area so mips and
alpha-to-coverage don't halo), leaf_normal.png (OpenGL), leaf_rough.png and leaf_rects.json
(u0, v0, u1, v1 per leaf in atlas UV space, v down, with the quadrant's species).
"""

import json
import os
import sys
from collections import deque

from PIL import Image, ImageEnhance, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
Q = 1024
QUADS = [  # (set, species, (qx, qy), tint)
    ("LeafSet017", "ivy", (0, 0), None),
    ("LeafSet022", "laurel", (1, 0), None),
    ("LeafSet024", "beech", (0, 1), None),
    ("LeafSet017", "ivy_old", (1, 1), (0.82, 0.86, 0.62)),
]


def load(asset, kind):
    d = os.path.join(SRC, asset)
    for f in os.listdir(d):
        if f"_{kind}." in f:
            return Image.open(os.path.join(d, f))
    raise FileNotFoundError(f"{asset} {kind}")


def bleed(rgb, alpha):
    """Pull-push fill: premultiply by coverage, average down a pyramid, then push back up filling
    uncovered texels (and blending partially covered ones) with nearby leaf colour, so
    mips and alpha-to-coverage edges pick up leaf colour instead of a dark or light fringe."""
    from PIL import ImageChops
    levels = [(ImageChops.multiply(rgb, Image.merge("RGB", [alpha] * 3)), alpha)]
    while levels[-1][0].size[0] > 1:
        p, a = levels[-1]
        n = (p.size[0] // 2, p.size[1] // 2)
        levels.append((p.resize(n, Image.BOX), a.resize(n, Image.BOX)))
    p, a = levels[-1]
    k = 255.0 / max(1, a.getpixel((0, 0)))
    result = p.point(lambda v: min(255, int(v * k)))
    for p, a in reversed(levels[:-1]):
        up = result.resize(p.size, Image.BILINEAR)
        result = ImageChops.add(p, ImageChops.multiply(up, Image.merge("RGB", [ImageChops.invert(a)] * 3)))
    return result


def components(alpha, scale=8):
    """Bounding boxes of the leaves (connected opaque regions) on a downsampled mask."""
    w, h = alpha.size[0] // scale, alpha.size[1] // scale
    m = alpha.resize((w, h), Image.BOX).load()
    seen = [[False] * w for _ in range(h)]
    boxes = []
    for y in range(h):
        for x in range(w):
            if seen[y][x] or m[x, y] < 60:
                continue
            q = deque([(x, y)])
            seen[y][x] = True
            x0 = x1 = x
            y0 = y1 = y
            n = 0
            while q:
                cx, cy = q.popleft()
                n += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and m[nx, ny] >= 60:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if n > 40:
                pad = 1
                boxes.append(((x0 - pad) * scale, (y0 - pad) * scale, (x1 + 1 + pad) * scale, (y1 + 1 + pad) * scale))
    return boxes


albedo = Image.new("RGBA", (2 * Q, 2 * Q), (40, 60, 30, 0))
normal = Image.new("RGB", (2 * Q, 2 * Q), (128, 128, 255))
rough = Image.new("L", (2 * Q, 2 * Q), 160)
rects = []
for asset, species, (qx, qy), tint in QUADS:
    col = load(asset, "Color").convert("RGB").resize((Q, Q), Image.LANCZOS)
    alp = load(asset, "Opacity").convert("L").resize((Q, Q), Image.LANCZOS)
    nor = load(asset, "NormalGL").convert("RGB").resize((Q, Q), Image.LANCZOS)
    rgh = load(asset, "Roughness").convert("L").resize((Q, Q), Image.LANCZOS)
    if tint:
        r, g, b = col.split()
        col = Image.merge("RGB", [c.point(lambda v, k=k: int(v * k)) for c, k in zip((r, g, b), tint)])
        col = ImageEnhance.Contrast(col).enhance(0.9)
    col = bleed(col, alp)
    ox, oy = qx * Q, qy * Q
    albedo.paste(Image.merge("RGBA", (*col.split(), alp)), (ox, oy))
    normal.paste(nor, (ox, oy))
    rough.paste(rgh, (ox, oy))
    for x0, y0, x1, y1 in components(alp):
        x0, y0, x1, y1 = max(0, x0), max(0, y0), min(Q, x1), min(Q, y1)
        rects.append({"species": species, "u0": (ox + x0) / (2 * Q), "v0": (oy + y0) / (2 * Q),
                      "u1": (ox + x1) / (2 * Q), "v1": (oy + y1) / (2 * Q)})

os.makedirs(OUT, exist_ok=True)
albedo.save(os.path.join(OUT, "leaf_albedo.png"))
normal.save(os.path.join(OUT, "leaf_normal.png"))
rough.save(os.path.join(OUT, "leaf_rough.png"))
with open(os.path.join(OUT, "leaf_rects.json"), "w") as f:
    json.dump(rects, f, indent=1)
print(len(rects), "leaves:", {s: sum(r["species"] == s for r in rects) for s in ("ivy", "laurel", "beech", "ivy_old")})

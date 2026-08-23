# -*- coding: utf-8 -*-
from pathlib import Path
from PIL import Image, ImageOps

assets = Path(__file__).resolve().parent.parent / "assets"
src = Image.open(assets / "_oi-source.png").convert("RGBA")
fav = Image.open(assets / "_oi-favicon.png").convert("RGBA")


def trim_white(im, thr=245):
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    l, t, r, b = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[0] < thr or p[1] < thr or p[2] < thr:
                l, t = min(l, x), min(t, y)
                r, b = max(r, x), max(b, y)
    if r <= l or b <= t:
        return im
    pad = 8
    return im.crop((max(0, l - pad), max(0, t - pad), min(w, r + 1 + pad), min(h, b + 1 + pad)))


oi = trim_white(src)


def on_canvas(fg, size, bg=(0, 0, 0, 255)):
    canvas = Image.new("RGBA", (size, size), bg)
    max_side = int(size * 0.72)
    f = fg.copy()
    f.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    r, g, b, a = f.split()
    gray = Image.merge("RGB", (r, g, b)).convert("L")
    alpha = ImageOps.invert(gray)
    white = Image.new("L", f.size, 255)
    f = Image.merge("RGBA", (white, white, white, alpha))
    x = (size - f.size[0]) // 2
    y = (size - f.size[1]) // 2
    canvas.alpha_composite(f, (x, y))
    return canvas


def transparent_white_icon(fg, size):
    f = fg.copy()
    max_side = int(size * 0.85)
    f.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    r, g, b, a = f.split()
    gray = Image.merge("RGB", (r, g, b)).convert("L")
    alpha = ImageOps.invert(gray)
    white = Image.new("L", f.size, 255)
    out = Image.merge("RGBA", (white, white, white, alpha))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - out.size[0]) // 2
    y = (size - out.size[1]) // 2
    canvas.alpha_composite(out, (x, y))
    return canvas


on_canvas(oi, 512).save(assets / "logo.png", optimize=True)
on_canvas(oi, 512).save(assets / "logo-white.png", optimize=True)
transparent_white_icon(oi, 512).save(assets / "logo-icon.png", optimize=True)
transparent_white_icon(oi, 64).save(assets / "logo-icon-64.png", optimize=True)
transparent_white_icon(oi, 32).save(assets / "logo-icon-32.png", optimize=True)
fav.resize((64, 64), Image.Resampling.LANCZOS).save(assets / "favicon.png", optimize=True)
transparent_white_icon(oi, 256).save(assets / "logo-pattern.png", optimize=True)

print("done")
for p in ["logo.png", "logo-white.png", "logo-icon.png", "favicon.png", "logo-pattern.png"]:
    print(p, (assets / p).stat().st_size)

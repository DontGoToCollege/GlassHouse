"""Draws the GlassHouse logo: logo.svg (used by the themes) plus logo_512.png and icon256.ico (exe/window icon).
Run: python make-icon.py   (needs Pillow). Both outputs come from the same shapes below, on a 48-unit grid."""
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
STOPS = [(0.0, (45, 212, 191)), (0.5, (59, 130, 246)), (1.0, (139, 92, 246))]  # teal, blue, violet
ROOF = [(24, 8.5), (38, 20.5), (10, 20.5)]
PANES = [(13, 22.5, 22.75, 29), (25.25, 22.5, 35, 29), (13, 31.5, 22.75, 38), (25.25, 31.5, 35, 38)]


def hexc(c): return "#%02x%02x%02x" % c


def svg():
    stops = "".join(f'<stop offset="{o}" stop-color="{hexc(c)}"/>' for o, c in STOPS)
    roof = " ".join(f"{x},{y}" for x, y in ROOF)
    panes = "".join(f'<rect x="{a}" y="{b}" width="{c-a}" height="{d-b}" rx="1.5" fill="url(#p)"/>' for a, b, c, d in PANES)
    return ('<!-- GlassHouse logo, GPLv3, see LICENSE -->\n'
            '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">'
            f'<defs><linearGradient id="t" x1="0" y1="0" x2="1" y2="1">{stops}</linearGradient>'
            '<linearGradient id="p" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="1"/>'
            '<stop offset="1" stop-color="#fff" stop-opacity="0.72"/></linearGradient></defs>'
            '<rect width="48" height="48" rx="11" fill="url(#t)"/>'
            f'<polygon points="{roof}" fill="url(#p)"/>'
            f'{panes}</svg>\n')


def png(size):
    S = 1024; k = S / 48
    t = (lambda v: v * k)
    # diagonal three-stop gradient tile
    grad = Image.new("RGB", (S, S))
    px = grad.load()
    for y in range(S):
        for x in range(S):
            f = (x + y) / (2 * S - 2)
            (o0, c0), (o1, c1) = (STOPS[0], STOPS[1]) if f <= 0.5 else (STOPS[1], STOPS[2])
            u = (f - o0) / (o1 - o0)
            px[x, y] = tuple(round(a + (b - a) * u) for a, b in zip(c0, c1))
    tile = Image.new("L", (S, S)); ImageDraw.Draw(tile).rounded_rectangle([0, 0, S - 1, S - 1], radius=t(11), fill=255)
    img = Image.new("RGBA", (S, S)); img.paste(grad, mask=tile)
    # glass panes: white fading from 100% to 72% top to bottom
    shapes = Image.new("L", (S, S)); d = ImageDraw.Draw(shapes)
    d.polygon([(t(x), t(y)) for x, y in ROOF], fill=255)
    for a, b, c, e in PANES: d.rounded_rectangle([t(a), t(b), t(c), t(e)], radius=t(1.5), fill=255)
    fade = Image.linear_gradient("L").resize((S, S)).point(lambda v: 255 - round(v * 0.28))
    glass = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    glass.putalpha(Image.composite(fade, Image.new("L", (S, S)), shapes))
    img.alpha_composite(glass)
    return img.resize((size, size), Image.LANCZOS)


(HERE / "logo.svg").write_text(svg(), encoding="utf-8")
big = png(512); big.save(HERE / "logo_512.png")
big.save(HERE / "icon256.ico", sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
print("wrote logo.svg, logo_512.png, icon256.ico")

"""Draws the Torment UI art (assets/torment_*.tga) from the validated mockup.

The pieces the stock FrameXML has no equivalent for (the validate buttons and the arrows
stay the client's own). Every file is a 32-bit uncompressed TGA with power-of-two sides.

    python tools/torment_assets.py        (from the addon root)

Pieces:
  torment_banner        256x32  title pill: dark gradient, gold / black / brown rings, round ends
  torment_plate         256x32  reward name plate: brown gradient, light top-left, dark bottom-right
  torment_btn_{up,down,disabled}  32x32  ladder rung faces, used 3-sliced (8 px ends)
  torment_glow          32x32  gold ring + halo marking the tier in force
"""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets")
SS = 4  # supersampling factor for smooth edges


def hexrgb(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def vgradient(w, h, top, bottom):
    img = Image.new("RGBA", (w, h))
    px = img.load()
    t, b = hexrgb(top), hexrgb(bottom)
    for y in range(h):
        f = y / max(1, h - 1)
        c = tuple(int(t[i] + (b[i] - t[i]) * f) for i in range(3)) + (255,)
        for x in range(w):
            px[x, y] = c
    return img


def save(img, name):
    path = os.path.join(OUT, name + ".tga")
    img.save(path)
    print("wrote", os.path.relpath(path, os.path.join(HERE, "..")), img.size)


def down(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


# ---------------------------------------------------------------- banner
def banner():
    w, h = 256, 32
    W, H = w * SS, h * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = H // 2
    # gold ring, black ring, brown ring, then the fill
    d.rounded_rectangle((0, 0, W - 1, H - 1), r, fill=hexrgb("#c39a45"))
    d.rounded_rectangle((SS, SS, W - 1 - SS, H - 1 - SS), r - SS, fill=hexrgb("#000000"))
    d.rounded_rectangle((2 * SS, 2 * SS, W - 1 - 2 * SS, H - 1 - 2 * SS), r - 2 * SS, fill=hexrgb("#6b4d1a"))
    fill = vgradient(W, H, "#1d140c", "#0b0806")
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((3 * SS, 3 * SS, W - 1 - 3 * SS, H - 1 - 3 * SS), r - 3 * SS, fill=255)
    img.paste(fill, (0, 0), mask)
    save(down(img, w, h), "torment_banner")


# ---------------------------------------------------------------- reward plate
def plate():
    w, h = 256, 32
    img = vgradient(w, h, "#3b2a14", "#22170b")
    d = ImageDraw.Draw(img)
    hi, lo = hexrgb("#6f5528"), hexrgb("#2a1d0c")
    d.line((0, 0, w - 1, 0), fill=hi)          # top
    d.line((0, 0, 0, h - 1), fill=hi)          # left
    d.line((0, h - 1, w - 1, h - 1), fill=lo)  # bottom
    d.line((w - 1, 0, w - 1, h - 1), fill=lo)  # right
    save(img, "torment_plate")


# ---------------------------------------------------------------- ladder rung
def button(name, top, bottom, edge_hi, edge_lo, inset=False):
    w, h = 32, 32
    W, H = w * SS, h * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = 3 * SS
    # drop line under the button (box-shadow 0 1px 0 #000)
    d.rounded_rectangle((0, SS, W - 1, H - 1), r, fill=hexrgb("#000000"))
    # bevel: light ring, then dark ring drawn over its bottom-right half
    d.rounded_rectangle((0, 0, W - 1, H - 1 - SS), r, fill=hexrgb(edge_hi))
    d.rounded_rectangle((SS, SS, W - 1, H - 1 - SS), r, fill=hexrgb(edge_lo))
    fill = vgradient(W, H, top, bottom)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((SS, SS, W - 1 - SS, H - 1 - 2 * SS), r - SS, fill=255)
    img.paste(fill, (0, 0), mask)
    if inset:
        # pressed: a dark inner shadow along the top
        shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shade)
        for i in range(3 * SS):
            a = int(140 * (1 - i / (3 * SS)))
            sd.line((SS, SS + i, W - 1 - SS, SS + i), fill=(0, 0, 0, a))
        img = Image.alpha_composite(img, Image.composite(shade, Image.new("RGBA", (W, H), (0, 0, 0, 0)), mask))
    save(down(img, w, h), name)


def buttons():
    button("torment_btn_up", "#6a2411", "#3c130a", "#d8b56a", "#5b3d16")
    button("torment_btn_down", "#3c130a", "#24090a", "#d8b56a", "#5b3d16", inset=True)
    button("torment_btn_disabled", "#3a3532", "#221f1c", "#5a544c", "#2e2a26")


# ---------------------------------------------------------------- glow
def glow():
    w, h = 32, 32
    W, H = w * SS, h * SS
    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(halo).rounded_rectangle((3 * SS, 3 * SS, W - 1 - 3 * SS, H - 1 - 3 * SS), 3 * SS,
                                           outline=hexrgb("#ffd100", 200), width=2 * SS)
    halo = halo.filter(ImageFilter.GaussianBlur(2.2 * SS))
    ring = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle((3 * SS, 3 * SS, W - 1 - 3 * SS, H - 1 - 3 * SS), 3 * SS,
                                           outline=hexrgb("#ffd100"), width=SS)
    img = Image.alpha_composite(halo, ring)
    save(down(img, w, h), "torment_glow")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    banner()
    plate()
    buttons()
    glow()

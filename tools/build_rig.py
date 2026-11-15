"""Build the rig textures for a character.

    python3 tools/build_rig.py dumbledore

Reads characters/<name>/rig.json and writes, next to it:
  rig.png    red   = figure mask (white where the character is, slightly generous)
             green = head weight (white moves fully with the head, black stays put)
  plate.jpg  the painting with the head painted out, shown where the head moves away
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

name = sys.argv[1]
folder = Path(__file__).resolve().parent.parent / "characters" / name
cfg = json.loads((folder / "rig.json").read_text())
img = Image.open(folder / cfg["image"]).convert("RGB")
W, H = img.size

def poly(points):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon([tuple(p) for p in points], fill=255)
    return m

figure = poly(cfg["figure"])
head = poly(cfg["head"])

# Head weight: 1 inside the head outline, fading smoothly to 0 around it.
blur = np.asarray(head.filter(ImageFilter.GaussianBlur(cfg["headFalloff"])), dtype=np.float32) / 255
u = np.clip(blur / 0.5, 0, 1)
weight = u * u * (3 - 2 * u)

rig = np.zeros((H, W, 3), dtype=np.uint8)
# The figure mask is drawn a little generous and soft, so no fringe of hair is left behind.
grown_img = figure.filter(ImageFilter.MaxFilter(2 * cfg["plateGrow"] + 1))
rig[..., 0] = np.asarray(grown_img.filter(ImageFilter.GaussianBlur(3)))
rig[..., 1] = (weight * 255).astype(np.uint8)
Image.fromarray(rig).save(folder / "rig.png")

# Background plate: remove the figure above the shoulder line and fill the hole
# using only true background pixels around it, nearest surroundings first.
grown = np.asarray(grown_img.filter(ImageFilter.MaxFilter(9))) > 127
hole = grown.copy()
hole[cfg["plateFillAbove"]:, :] = False
src = np.asarray(img, dtype=np.float32)
# Fill from the darker background only: what sits behind a head is usually in shadow.
lum = src @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
known = (~grown & (lum < cfg.get("plateMaxBrightness", 255))).astype(np.float32)

def blur(a, sigma):
    return np.asarray(Image.fromarray(a).filter(ImageFilter.GaussianBlur(sigma)), dtype=np.float32)

fill = src.copy()
todo = hole.copy()
for sigma in (4, 8, 16, 32, 64, 128, 256):
    den = blur((known * 255).astype(np.uint8), sigma) / 255
    num = np.stack([blur((src[..., c] * known).astype(np.uint8), sigma) for c in range(3)], axis=-1)
    ok = todo & (den > 0.2)
    fill[ok] = num[ok] / den[ok][:, None]
    todo &= ~ok
# Smooth away the steps between passes without letting the figure below bleed in.
valid = (~(grown & ~hole)).astype(np.float32)
for _ in range(30):
    den = blur((valid * 255).astype(np.uint8), 7) / 255
    num = np.stack([blur((fill[..., c] * valid).astype(np.uint8), 7) for c in range(3)], axis=-1)
    fill[hole] = num[hole] / np.maximum(den[hole], 0.05)[:, None]
Image.fromarray(np.clip(fill, 0, 255).astype(np.uint8)).save(folder / "plate.jpg", quality=92)
print("wrote rig.png and plate.jpg in", folder)

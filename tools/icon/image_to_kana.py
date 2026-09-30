"""Turns a high-contrast image (a light shape on dark) into a one-frame .kana
grid for render_icon.swift: a cell is lit when the shape covers enough of it,
denser glyphs inside, lighter ones at the edge, keeping the image's colour.

    python3 tools/icon/image_to_kana.py <image> <out.kana> [columns] [coverage]

columns defaults to 28, coverage (0-1, how much of a cell the shape must
fill) to 0.45. Cells are 0.83 wide to 1 tall, like render_icon's tiles.
Standard library, numpy and OpenCV only (tools/ascii/requirements.txt).
"""
import base64
import json
import math
import sys

import cv2
import numpy as np

INSIDE = "@#%&$8BWM0QOZXYUJCLkbdhpqwm"
EDGE = "?)(|/\\{}[]1tfjrxnuvcz"


def main():
    path, out = sys.argv[1], sys.argv[2]
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 28
    need = float(sys.argv[4]) if len(sys.argv) > 4 else 0.45
    image = cv2.imread(path)
    if image is None:
        sys.exit(f"Couldn't read image: {path}")
    # the brightest channel, so a saturated red shape counts as "light" too
    mask = image.max(axis=2) > 110
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        sys.exit("The image has no light shape in it")
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    cw = (x1 - x0) / cols
    ch = cw / 0.83
    rows_n = max(1, math.ceil((y1 - y0) / ch))  # cover the whole shape
    rng = np.random.default_rng(7)  # same glyphs every run
    rows, colors = [], bytearray()
    for r in range(rows_n):
        line = ""
        for c in range(cols):
            ya, yb = int(y0 + r * ch), min(y1, int(y0 + (r + 1) * ch))
            xa, xb = int(x0 + c * cw), min(x1, int(x0 + (c + 1) * cw))
            cell = mask[ya:yb, xa:xb]
            cover = cell.mean() if cell.size else 0.0
            if cover < need or not cell.any():
                line += " "
                colors += bytes(3)
                continue
            pool = INSIDE if cover > 0.9 else EDGE
            line += pool[int(rng.integers(len(pool)))]
            b, g, red = image[ya:yb, xa:xb][cell].mean(axis=0)
            colors += bytes((int(red), int(g), int(b)))
        rows.append(line)
    clip = {"format": "kana-ascii", "version": 1, "width": cols, "height": rows_n, "fps": 0,
            "color": True, "portrait": 0,
            "frames": [{"rows": rows, "colors": base64.b64encode(bytes(colors)).decode("ascii")}]}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(clip, f)
    print(f"{out}: {cols}x{rows_n}")


if __name__ == "__main__":
    main()

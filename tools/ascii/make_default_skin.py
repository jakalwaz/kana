#!/usr/bin/env python3
"""Draw Kana's original default skin; no source images, video, or randomness.

Run from the repo root with Python 3.9+ and numpy:
    python3 tools/ascii/make_default_skin.py [--out PATH]

The light is an analytic capsule with an upturned tip. Delayed copies make
its motion trail; cubic ease-out brings it to rest before a short hold.
Compact, timestamp-free JSON makes repeated runs byte-identical.
"""

import argparse
import base64
import json
from pathlib import Path

import numpy as np


SCALE = 2.25
# Fit the thresholded halo with at most two blank rows above and below.
WIDTH, HEIGHT = round(48 * SCALE), round(11.5 * SCALE)
FPS, FRAME_COUNT = 20, 48
MOVE_SECONDS = 1.8
TRAIL_SECONDS = 0.22
ACCENT = "#e0262f"
# Same standard density ramp as convert.py; importing it would require OpenCV.
RAMP = " .:-=+*#%@"
DEFAULT_OUT = Path(__file__).resolve().parents[2] / "Resources/skins/default"


def position(seconds):
    progress = min(1.0, max(0.0, seconds / MOVE_SECONDS))
    # The resting halo reaches both horizontal boundaries. Entry from the
    # left therefore adds no extra span when the banner trims the whole clip.
    resting_center = (WIDTH - 1) / 2.0
    entry = -26.0 * SCALE
    return entry + (resting_center - entry) * (1.0 - (1.0 - progress) ** 3)


def light(x, y, center):
    """A rounded ribbon with a gentle rising tip, measured in character cells."""
    local_x = x - center
    along = np.clip(local_x, -17.0 * SCALE, 17.0 * SCALE)
    tip = np.clip((along - 5.0 * SCALE) / (12.0 * SCALE), 0.0, 1.0)
    center_y = (HEIGHT - 1) / 2.0 + 1.5 * SCALE - 3.0 * SCALE * tip * tip * (3.0 - 2.0 * tip)
    # Rows are approximately twice as tall as columns in a terminal font.
    distance_sq = (local_x - along) ** 2 + ((y - center_y) * 2.0) ** 2
    core = np.exp(-distance_sq / (2.0 * (1.65 * SCALE) ** 2))
    halo = np.exp(-distance_sq / (2.0 * (4.8 * SCALE) ** 2))
    return 0.82 * core + 0.18 * halo


def draw_frame(index, x, y):
    seconds = index / FPS
    center = position(seconds)
    intensity = light(x, y, center)
    # Older light sits to the left. Its strength vanishes as velocity falls,
    # so the held portrait has no residual smear or flickering particles.
    for sample in range(1, 10):
        age = TRAIL_SECONDS * sample / 9.0
        earlier = position(seconds - age)
        separation = min(1.0, (center - earlier) / (7.0 * SCALE))
        intensity += light(x, y, earlier) * separation * (1.0 - sample / 10.0) * 0.11
    intensity = np.clip(intensity, 0.0, 1.0)
    indices = np.rint(intensity * (len(RAMP) - 1)).astype(np.int32)
    indices[intensity < 0.065] = 0
    chars = np.array(list(RAMP))[indices]
    # Preserve the accent hue. Blank cells have exactly black RGB, including
    # the infinite Gaussian tails cut off by the character density threshold.
    rgb = np.rint(
        np.array([224, 38, 47]) * (0.35 + 0.65 * intensity[..., None])
    ).astype(np.uint8)
    rgb[indices == 0] = 0
    return {
        "rows": ["".join(row) for row in chars],
        "colors": base64.b64encode(rgb.tobytes(order="C")).decode("ascii"),
    }


def clip(frames, fps):
    return {
        "format": "kana-ascii",
        "version": 1,
        "width": WIDTH,
        "height": HEIGHT,
        "fps": fps,
        "color": True,
        "portrait": len(frames) - 1,
        "frames": frames,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help="output skin directory (default: Resources/skins/default)")
    args = parser.parse_args()
    output = args.out.expanduser()
    output.mkdir(parents=True, exist_ok=True)
    y, x = np.mgrid[:HEIGHT, :WIDTH]
    frames = [draw_frame(index, x, y) for index in range(FRAME_COUNT)]
    files = {
        "intro.kana": clip(frames, FPS),
        "portrait.kana": clip([frames[-1]], 0),
        "skin.json": {
            "name": "Default",
            "accent": ACCENT,
            "intro": "intro.kana",
            "portrait": "portrait.kana",
            "portrait_opacity": 0.35,
        },
    }
    for name, data in files.items():
        encoded = (json.dumps(data, ensure_ascii=True, separators=(",", ":")) + "\n").encode("ascii")
        (output / name).write_bytes(encoded)
        print("Wrote {} ({} bytes)".format(output / name, len(encoded)))


if __name__ == "__main__":
    main()

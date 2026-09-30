#!/usr/bin/env python3
"""Kana ASCII converter.

Turns a video clip or still image into a .kana frames file for Kana's intro
and portrait, and plays .kana files right in the terminal so you can tune
the look without the app.

Commands:
  convert INPUT -o OUT.kana [options]   make a .kana file (add --preview to watch it)
  play FILE.kana [--loop] [--frame N]   play a .kana file, or show one frame
  info FILE.kana                        print what's inside a .kana file
  snapshot FILE.kana -o OUT.svg         render a frame as an SVG window screenshot (termframe)

Run any command with -h for the full list of options.
"""

import argparse
import base64
import json
import math
import os
import shutil
import sys
import time

try:
    import cv2
    import numpy as np
except ImportError:
    sys.exit("convert.py needs OpenCV and numpy: pip install -r tools/ascii/requirements.txt")

FORMAT = "kana-ascii"
VERSION = 1

RAMPS = {
    "standard": " .:-=+*#%@",
    "detailed": " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$",
    "blocks": " ░▒▓█",
    "dots": " ·•●",
}

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}


# ---------------------------------------------------------------- reading


def parse_crop(value):
    """'x,y,w,h' as fractions of the frame, e.g. 0,0.15,1,0.7"""
    if not value:
        return None
    try:
        x, y, w, h = (float(v) for v in value.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError("--crop needs four numbers: x,y,w,h (fractions 0 to 1)")
    if not (0 <= x < 1 and 0 <= y < 1 and 0 < w <= 1 and 0 < h <= 1):
        raise argparse.ArgumentTypeError("--crop values must be fractions between 0 and 1")
    return x, y, min(w, 1 - x), min(h, 1 - y)


def read_frames(path, start, duration, fps, max_frames):
    """Returns (list of BGR frames, output fps). A still image gives one frame and fps 0."""
    if not os.path.exists(path):
        sys.exit(f"No such file: {path}")

    if os.path.splitext(path)[1].lower() in IMAGE_EXTS:
        img = cv2.imread(path, cv2.IMREAD_COLOR)
        if img is None:
            sys.exit(f"Couldn't read image: {path}")
        return [img], 0

    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        sys.exit(f"Couldn't open video: {path}")

    src_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    if src_fps <= 0 or math.isnan(src_fps):
        src_fps = 30.0
    out_fps = fps or min(round(src_fps), 15)
    out_fps = min(out_fps, src_fps)

    if start > 0:
        cap.set(cv2.CAP_PROP_POS_MSEC, start * 1000.0)

    end = start + duration if duration else float("inf")
    frames = []
    n = 0
    next_t = start
    step = 1.0 / out_fps
    while len(frames) < max_frames:
        ok, frame = cap.read()
        if not ok:
            break
        t = start + n / src_fps
        n += 1
        if t >= end:
            break
        if t + 1e-6 >= next_t:
            frames.append(frame)
            next_t += step
    cap.release()

    if not frames:
        sys.exit("No frames read. Check --start and --duration against the clip length.")
    return frames, out_fps


# ---------------------------------------------------------------- converting


def crop_frame(frame, crop):
    if not crop:
        return frame
    h, w = frame.shape[:2]
    x, y, cw, ch = crop
    # the epsilon stops float noise (0.4999...) flooring a pixel early
    x0, y0 = int(x * w + 1e-6), int(y * h + 1e-6)
    x1, y1 = max(x0 + 1, int((x + cw) * w + 1e-6)), max(y0 + 1, int((y + ch) * h + 1e-6))
    return frame[y0:y1, x0:x1]


def parse_move(value):
    """'START,END' seconds from the clip start"""
    try:
        t0, t1 = (float(v) for v in value.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError("--crop-move needs two numbers: start,end (seconds)")
    if t1 <= t0:
        raise argparse.ArgumentTypeError("--crop-move end must come after start")
    return t0, t1


def moving_crops(frames, fps, start, end, move):
    """One crop per frame, easing from `start` to `end` over the `move`
    window, like a camera pushing in. `end` is reshaped to `start`'s aspect
    (around its own centre) so every frame fills the same grid undistorted."""
    h, w = frames[0].shape[:2]
    sx, sy, sw, sh = start or (0.0, 0.0, 1.0, 1.0)
    ex, ey, ew, eh = end
    aspect = (sw * w) / (sh * h)
    fixed_h = (ew * w) / aspect / h
    if abs(fixed_h - eh) > 1e-3:
        cy = ey + eh / 2
        eh = min(fixed_h, 1.0)
        ey = min(max(0.0, cy - eh / 2), 1.0 - eh)
        print(f"--crop-end height set to {eh:.3f} to match --crop's shape", file=sys.stderr)
    t0, t1 = move
    crops = []
    for i in range(len(frames)):
        t = i / fps if fps else 0.0
        k = min(1.0, max(0.0, (t - t0) / (t1 - t0)))
        k = k * k * (3 - 2 * k)  # smoothstep
        crops.append(tuple(a + (b - a) * k for a, b in zip((sx, sy, sw, sh), (ex, ey, ew, eh))))
    return crops


def grid_size(frame, width, height, char_aspect):
    h, w = frame.shape[:2]
    if height:
        return width, height
    rows = max(1, round(width * (h / w) * char_aspect))
    return width, rows


def convert_frame(frame, cols, rows, args, ramp):
    """One BGR frame -> (list of row strings, RGB bytes)."""
    small = cv2.resize(frame, (cols, rows), interpolation=cv2.INTER_AREA)
    rgb = cv2.cvtColor(small, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0

    if args.luma == "value":
        # brightest channel: a saturated red counts as bright as it looks,
        # instead of nearly black the way Rec. 709 luma rates it
        lum = rgb.max(axis=2)
    else:
        lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    lum = (lum - 0.5) * args.contrast + 0.5 + args.brightness
    lum = np.clip(lum, 0.0, 1.0) ** args.gamma

    # Colour-keyed subjects (a red bike on a grey street): push dull greys
    # back and pull saturated colour forward, so the subject reads first.
    keep = None
    if args.grey_dim < 1.0 or args.sat_lift > 0:
        hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV).astype(np.float32) / 255.0
        sat, val = hsv[..., 1], hsv[..., 2]
        # tinted greys (a bluish street sits around 0.25 to 0.35) don't count
        colourful = np.clip((sat - 0.45) / 0.3, 0.0, 1.0)
        bright = np.clip((val - 0.75) / 0.15, 0.0, 1.0)
        keep = args.grey_dim + (1.0 - args.grey_dim) * np.maximum(colourful, bright)
        # sqrt(val) so a deep red in a dark shot still gets lifted
        lum = np.clip(lum * keep + args.sat_lift * colourful * np.sqrt(val), 0.0, 1.0)

    if args.edges > 0:
        # edges from a 2x grid so outlines stay crisp, then pooled down
        big = cv2.resize(frame, (cols * 2, rows * 2), interpolation=cv2.INTER_AREA)
        gray = cv2.cvtColor(big, cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
        gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
        gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
        mag = cv2.resize(np.hypot(gx, gy), (cols, rows), interpolation=cv2.INTER_AREA)
        scale = np.percentile(mag, 99) or 1.0
        lum = np.clip(lum + np.clip(mag / scale, 0, 1) * args.edges, 0.0, 1.0)

    if args.normalize:
        # stretch so the brightest 1% of cells hit the top of the ramp
        top = float(np.percentile(lum, 99))
        if top > 1e-3:
            lum = np.clip(lum / top, 0.0, 1.0)

    if args.invert:
        lum = 1.0 - lum

    idx = np.rint(lum * (len(ramp) - 1)).astype(np.int32)
    blank = lum < args.bg_cut
    idx[blank] = 0

    lut = np.array(list(ramp))
    chars = lut[idx]
    row_strings = ["".join(r) for r in chars]

    color = rgb
    if args.saturation != 1.0:
        hsv = cv2.cvtColor((color * 255).astype(np.uint8), cv2.COLOR_RGB2HSV).astype(np.float32)
        hsv[..., 1] = np.clip(hsv[..., 1] * args.saturation, 0, 255)
        color = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2RGB).astype(np.float32) / 255.0
    if args.vivid:
        # keep the hue, but make the colour as bright as the character is, so
        # a dark red bike prints as a readable red instead of near black
        peak = np.maximum(color.max(axis=2, keepdims=True), 1e-3)
        color = color / peak * np.clip(0.3 + 0.8 * lum, 0.0, 1.0)[..., None]
    if keep is not None:
        color = color * keep[..., None]
    color = np.clip(color * args.color_gain, 0.0, 1.0)
    color[blank] = 0.0
    color_bytes = (color * 255).astype(np.uint8).tobytes()

    return row_strings, color_bytes


def cmd_convert(args):
    ramp = args.ramp_chars or RAMPS[args.ramp]
    if ramp[0] != " ":
        ramp = " " + ramp

    frames, fps = read_frames(args.input, args.start, args.duration, args.fps, args.max_frames)
    if args.crop_end and fps:
        crops = moving_crops(frames, fps, args.crop, args.crop_end, args.crop_move)
        frames = [crop_frame(f, c) for f, c in zip(frames, crops)]
    else:
        frames = [crop_frame(f, args.crop) for f in frames]
    cols, rows = grid_size(frames[0], args.width, args.height, args.char_aspect)

    out_frames = []
    for f in frames:
        row_strings, color_bytes = convert_frame(f, cols, rows, args, ramp)
        entry = {"rows": row_strings}
        if not args.no_color:
            entry["colors"] = base64.b64encode(color_bytes).decode("ascii")
        out_frames.append(entry)

    count = len(out_frames)
    if args.portrait_time is not None and fps:
        portrait = round(args.portrait_time * fps)
    else:
        portrait = args.portrait
    if portrait < 0:
        portrait += count
    portrait = max(0, min(count - 1, portrait))

    data = {
        "format": FORMAT,
        "version": VERSION,
        "width": cols,
        "height": rows,
        "fps": fps,
        "color": not args.no_color,
        "portrait": portrait,
        "frames": out_frames,
    }

    out = os.path.expanduser(args.output)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))

    size_kb = os.path.getsize(out) / 1024
    length = f"{count / fps:.2f}s at {fps} fps" if fps else "still image"
    print(f"Wrote {out}: {count} frame(s), {cols}x{rows}, {length}, portrait = frame {portrait}, {size_kb:.0f} KB")

    if args.preview:
        play(data, loop=False, speed=1.0, use_color=not args.no_color)


# ---------------------------------------------------------------- playing


def load_kana(path):
    path = os.path.expanduser(path)
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        sys.exit(f"Couldn't read {path}. Is it a .kana file made by convert.py?")
    if data.get("format") != FORMAT:
        sys.exit(f"{path} isn't a .kana file")
    if data.get("version", 0) > VERSION:
        sys.exit(f"{path} is format version {data['version']}, this script reads up to {VERSION}")
    return data


def render(frame, width, use_color):
    rows = frame["rows"]
    if not use_color or "colors" not in frame:
        return "\n".join(rows)
    colors = base64.b64decode(frame["colors"])
    out = []
    for y, row in enumerate(rows):
        line = []
        last = None
        base = y * width * 3
        for x, ch in enumerate(row):
            if ch == " ":
                line.append(" ")
                continue
            i = base + x * 3
            rgb = (colors[i], colors[i + 1], colors[i + 2])
            if rgb != last:
                line.append(f"\x1b[38;2;{rgb[0]};{rgb[1]};{rgb[2]}m")
                last = rgb
            line.append(ch)
        line.append("\x1b[0m")
        out.append("".join(line))
    return "\n".join(out)


def play(data, loop=False, speed=1.0, use_color=True, only_frame=None):
    width, height = data["width"], data["height"]
    frames = data["frames"]
    fps = data.get("fps") or 0
    tty = sys.stdout.isatty()
    out = sys.stdout

    if tty:
        cols, lines = shutil.get_terminal_size((80, 24))
        if width > cols or height > lines:
            print(f"Heads up: this is {width}x{height} but the terminal is {cols}x{lines}. Make the window bigger or use a smaller --width.", file=sys.stderr)
            time.sleep(1.5)

    if only_frame is not None:
        i = only_frame if only_frame >= 0 else len(frames) + only_frame
        i = max(0, min(len(frames) - 1, i))
        out.write(render(frames[i], width, use_color) + "\n")
        return

    if fps == 0 or len(frames) == 1:
        out.write(render(frames[0], width, use_color) + "\n")
        return

    rendered = [render(f, width, use_color) for f in frames]
    delay = 1.0 / (fps * speed)
    try:
        if tty:
            out.write("\x1b[?25l\x1b[2J")
        while True:
            t0 = time.perf_counter()
            for n, text in enumerate(rendered):
                if tty:
                    out.write("\x1b[H")
                out.write(text + "\n")
                out.flush()
                wait = t0 + (n + 1) * delay - time.perf_counter()
                if wait > 0:
                    time.sleep(wait)
            if not loop:
                break
        # land on the portrait frame, like the app will
        portrait = data.get("portrait", len(frames) - 1)
        if tty:
            out.write("\x1b[H")
        out.write(rendered[portrait] + "\n")
    except KeyboardInterrupt:
        pass
    finally:
        if tty:
            out.write("\x1b[0m\x1b[?25h")
        out.flush()


def cmd_play(args):
    data = load_kana(args.file)
    play(data, loop=args.loop, speed=args.speed, use_color=not args.no_color, only_frame=args.frame)


def cmd_snapshot(args):
    """Render one frame to an SVG window screenshot with termframe."""
    termframe = shutil.which("termframe")
    if not termframe:
        sys.exit("snapshot needs termframe: brew install termframe (or cargo install termframe)")
    data = load_kana(args.file)
    count = len(data["frames"])
    i = args.frame if args.frame is not None else data.get("portrait", count - 1)
    if i < 0:
        i += count
    i = max(0, min(count - 1, i))
    out = os.path.abspath(os.path.expanduser(args.output))
    title = args.title or f"kana · {os.path.basename(args.file)} · frame {i}"
    cmd = [
        termframe,
        "--width", str(data["width"] + 2),
        "--height", str(data["height"] + 1),
        "--mode", "dark",
        "--theme", args.theme,
        "--title", title,
        "--timeout", "15",
        "-o", out,
        "--",
        sys.executable, os.path.abspath(__file__), "play", os.path.abspath(os.path.expanduser(args.file)),
        "--frame", str(i),
    ]
    if args.no_color:
        cmd.append("--no-color")
    import subprocess
    result = subprocess.run(cmd)
    if result.returncode != 0:
        sys.exit(f"termframe failed with exit code {result.returncode}")
    print(f"Wrote {out}: frame {i} of {count}")


def cmd_info(args):
    data = load_kana(args.file)
    count = len(data["frames"])
    fps = data.get("fps") or 0
    length = f"{count / fps:.2f}s" if fps else "still"
    print(f"{args.file}")
    print(f"  grid      {data['width']}x{data['height']}")
    print(f"  frames    {count} ({length}, {fps} fps)")
    print(f"  color     {'yes' if data.get('color') else 'no'}")
    print(f"  portrait  frame {data.get('portrait', count - 1)}")


# ---------------------------------------------------------------- cli


def main():
    parser = argparse.ArgumentParser(description="Kana ASCII converter", formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    c = sub.add_parser("convert", help="video or image to .kana")
    c.add_argument("input", help="video (mp4, mov, mkv, webm, gif) or image (png, jpg, webp)")
    c.add_argument("-o", "--output", required=True, help="where to write the .kana file")
    clip = c.add_argument_group("clip")
    clip.add_argument("--start", type=float, default=0.0, help="start time in seconds (default 0)")
    clip.add_argument("--duration", type=float, default=None, help="length in seconds (default: to the end)")
    clip.add_argument("--fps", type=int, default=None, help="output fps (default: source fps, capped at 15)")
    clip.add_argument("--max-frames", type=int, default=600, help="safety cap on frame count (default 600)")
    clip.add_argument("--crop", type=parse_crop, default=None, help="x,y,w,h as fractions, e.g. 0,0.15,1,0.7")
    clip.add_argument("--crop-end", type=parse_crop, default=None, help="push in: the crop to end on, x,y,w,h (reshaped to --crop's aspect)")
    clip.add_argument("--crop-move", type=parse_move, default=(0.0, 1.0), help="when the push-in happens, start,end in seconds (default 0,1)")
    grid = c.add_argument_group("grid")
    grid.add_argument("--width", type=int, default=100, help="characters wide (default 100)")
    grid.add_argument("--height", type=int, default=None, help="characters tall (default: from aspect ratio)")
    grid.add_argument("--char-aspect", type=float, default=0.5, help="character width/height ratio (default 0.5)")
    look = c.add_argument_group("look")
    look.add_argument("--ramp", choices=sorted(RAMPS), default="detailed", help="character ramp preset (default detailed)")
    look.add_argument("--ramp-chars", default=None, help="custom ramp, darkest to brightest")
    look.add_argument("--contrast", type=float, default=1.2, help="default 1.2")
    look.add_argument("--brightness", type=float, default=0.0, help="-0.5 to 0.5, default 0")
    look.add_argument("--gamma", type=float, default=1.0, help="below 1 brightens midtones, above 1 darkens (default 1)")
    look.add_argument("--edges", type=float, default=0.0, help="edge boost strength, try 0.3 to 0.8 (default off)")
    look.add_argument("--bg-cut", type=float, default=0.06, help="brightness below this becomes empty space (default 0.06)")
    look.add_argument("--grey-dim", type=float, default=1.0, help="scale dull, unsaturated pixels by this, e.g. 0.35 to push a grey street back (default 1, off)")
    look.add_argument("--sat-lift", type=float, default=0.0, help="brighten saturated colour, try 0.4 to 0.8 for a red bike on a dark street (default 0, off)")
    look.add_argument("--luma", choices=["rec709", "value"], default="rec709", help="how brightness is measured: rec709 (default) or value (brightest channel, keeps saturated reds dense)")
    look.add_argument("--normalize",action="store_true", help="stretch each frame so its brightest cells use the full ramp")
    look.add_argument("--vivid",action="store_true", help="colour brightness follows character brightness, so dark subjects print in readable colour")
    look.add_argument("--invert", action="store_true", help="for light backgrounds")
    look.add_argument("--no-color", action="store_true", help="characters only, no RGB")
    look.add_argument("--saturation", type=float, default=1.15, help="color saturation multiplier (default 1.15)")
    look.add_argument("--color-gain", type=float, default=1.1, help="color brightness multiplier (default 1.1)")
    port = c.add_argument_group("portrait")
    port.add_argument("--portrait", type=int, default=-1, help="frame index to rest on, negative counts from the end (default -1, the last frame)")
    port.add_argument("--portrait-time", type=float, default=None, help="pick the portrait by time in seconds from the clip start instead")
    c.add_argument("--preview", action="store_true", help="play the result in this terminal after converting")
    c.set_defaults(func=cmd_convert)

    p = sub.add_parser("play", help="play a .kana file in the terminal")
    p.add_argument("file")
    p.add_argument("--loop", action="store_true", help="loop until Ctrl-C")
    p.add_argument("--speed", type=float, default=1.0, help="playback speed multiplier")
    p.add_argument("--frame", type=int, default=None, help="show just this frame (negative counts from the end)")
    p.add_argument("--no-color", action="store_true")
    p.set_defaults(func=cmd_play)

    s = sub.add_parser("snapshot", help="render a frame to an SVG window screenshot (needs termframe)")
    s.add_argument("file")
    s.add_argument("-o", "--output", required=True, help="where to write the .svg")
    s.add_argument("--frame", type=int, default=None, help="frame to render (default: the portrait frame)")
    s.add_argument("--theme", default="ir-black", help="termframe colour theme (default ir-black, pure black like Kana)")
    s.add_argument("--title", default=None, help="window title")
    s.add_argument("--no-color", action="store_true")
    s.set_defaults(func=cmd_snapshot)

    i = sub.add_parser("info", help="show what's in a .kana file")
    i.add_argument("file")
    i.set_defaults(func=cmd_info)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

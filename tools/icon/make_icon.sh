#!/usr/bin/env bash
# Rebuilds Kana's app icon, Resources/icon/Kana.icns, from scratch:
# the カナ mark (draw_mark.swift) -> tiles (image_to_kana.py) -> icon PNGs
# (render_icon.swift) -> .icns (iconutil). Small sizes use coarser tiles so
# the mark still reads at 16 and 32 px.
#
#   tools/icon/make_icon.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
# PYTHON wins; otherwise the project venv (it has OpenCV), else python3
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
    PY=.venv/bin/python
    [ -x "$PY" ] || PY=python3
fi
command -v "$PY" >/dev/null || { echo "no python: $PY" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift tools/icon/draw_mark.swift "$WORK/mark.png"
# fine tiles for 128 px and up, coarse for the Finder's small sizes
"$PY" tools/icon/image_to_kana.py "$WORK/mark.png" "$WORK/fine.kana" 38 0.5 >/dev/null
"$PY" tools/icon/image_to_kana.py "$WORK/mark.png" "$WORK/coarse.kana" 16 0.5 >/dev/null
swift tools/icon/render_icon.swift "$WORK/fine.kana" "$WORK/fine.png" - source >/dev/null
swift tools/icon/render_icon.swift "$WORK/coarse.kana" "$WORK/coarse.png" - source >/dev/null

SET="$WORK/Kana.iconset"
mkdir -p "$SET"
for px in 16 32 64 128 256 512 1024; do
    src="$WORK/fine.png"
    [ "$px" -le 64 ] && src="$WORK/coarse.png"
    sips -z "$px" "$px" "$src" --out "$WORK/$px.png" >/dev/null
done
cp "$WORK/16.png" "$SET/icon_16x16.png"
cp "$WORK/32.png" "$SET/icon_16x16@2x.png"
cp "$WORK/32.png" "$SET/icon_32x32.png"
cp "$WORK/64.png" "$SET/icon_32x32@2x.png"
cp "$WORK/128.png" "$SET/icon_128x128.png"
cp "$WORK/256.png" "$SET/icon_128x128@2x.png"
cp "$WORK/256.png" "$SET/icon_256x256.png"
cp "$WORK/512.png" "$SET/icon_256x256@2x.png"
cp "$WORK/512.png" "$SET/icon_512x512.png"
cp "$WORK/1024.png" "$SET/icon_512x512@2x.png"

mkdir -p Resources/icon
iconutil -c icns "$SET" -o Resources/icon/Kana.icns
cp "$WORK/1024.png" Resources/icon/Kana.png
echo "wrote Resources/icon/Kana.icns and Kana.png"

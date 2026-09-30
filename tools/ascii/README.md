# ASCII converter

`convert.py` turns a video clip or a still image into a `.kana` file for Kana's intro and portrait. It can also play `.kana` files in any terminal with truecolor, so you can tune the look without building the app.

## Setup

```
pip install -r tools/ascii/requirements.txt
```

ffmpeg is optional. The script can trim and crop on its own.

## Commands

```
python3 tools/ascii/convert.py convert INPUT -o OUT.kana [options] [--preview]
python3 tools/ascii/convert.py play FILE.kana [--loop] [--speed 0.5] [--frame N]
python3 tools/ascii/convert.py info FILE.kana
python3 tools/ascii/convert.py snapshot FILE.kana -o OUT.svg [--frame N]
```

## Making the Akira skin

Source clips live in `assets/private/` (gitignored). Output goes straight into your skins folder, so nothing copyrighted ever touches the repo.

```
mkdir -p ~/.config/kana/skins/akira

python3 tools/ascii/convert.py convert assets/private/akira.mp4 \
  --start 83 --duration 3.5 --width 110 --fps 15 \
  --crop 0,0.15,1,0.75 --contrast 1.4 --bg-cut 0.08 \
  -o ~/.config/kana/skins/akira/intro.kana --preview
```

Then check the frame it lands on:

```
python3 tools/ascii/convert.py play ~/.config/kana/skins/akira/intro.kana --frame -1
```

If the last frame isn't a clean stand-up pose, either end the clip a bit later with `--duration`, or pick a different resting frame with `--portrait-time 3.2` (seconds from the clip start).

The current Akira intro (from the trimmed `assets/private/0929.mp4`) is a faithful full-scene conversion at 180 wide and 30 fps:

```
python3 tools/ascii/convert.py convert assets/private/0929.mp4 \
  --width 180 --fps 30 --ramp detailed --luma value --normalize --vivid \
  --contrast 1.2 --bg-cut 0.05 --saturation 1.3 \
  -o ~/.config/kana/skins/akira/intro.kana
```

For Kana's welcome screen, convert it at several widths. `kana` loads the conversion closest to the window size, which looks much better than shrinking one big file.

This one also pushes in. Most of each frame is smoke under the bike: at rest the bike takes up only x 0.30 to 0.60 and y 0.14 to 0.33 of the frame. So the crop starts as a wide 2.4:1 band with the bottom smoke cut off, then eases in to a crop centred on the bike between 0.4 s and 1.6 s. It rests with the rider filling the picture:

```
for w in 60 72 84 96 108 120 132 144 160 180 200 220 240; do
  python3 tools/ascii/convert.py convert assets/private/0929-v2.mp4 \
    --width $w --fps 30 --ramp detailed --luma value --vivid \
    --contrast 1.25 --gamma 0.9 --edges 0.35 --bg-cut 0.07 --saturation 1.4 \
    --crop 0,0.17,1,0.74 --crop-end 0.255,0.08,0.46,0.341 --crop-move 0.4,1.6 \
    -o ~/.config/kana/skins/akira/intro-$w.kana
done
```

`--crop-end` is reshaped to `--crop`'s aspect, so no frame is stretched. To centre on a subject, measure its bounding box in the last frame, then put equal margins on both sides.

`--luma value` is what makes the red bike read: Rec. 709 luma rates a deep red as nearly black, so the bike came out thinner than the grey street.

A skin can also use a still for its portrait, which works well for Guts:

```
python3 tools/ascii/convert.py convert assets/private/guts.png \
  --width 70 --contrast 1.5 --edges 0.5 \
  -o ~/.config/kana/skins/guts/portrait.kana
```

## Options that matter most

| Option | What it does | Try |
|---|---|---|
| `--start`, `--duration` | Trim, in seconds | Start just before the slide, end once he's standing |
| `--crop x,y,w,h` | Crop as fractions of the frame | Cut empty sky and street so the bike fills the grid |
| `--width` | Characters wide. Height follows the aspect ratio | 80 to 120. Bigger looks sharper but needs a bigger window |
| `--fps` | Output frame rate | 12 to 15. More only makes the file bigger |
| `--contrast`, `--brightness`, `--gamma` | Tone | Anime is often low contrast, so start at 1.3 to 1.5 |
| `--bg-cut` | Anything darker becomes empty space | 0.05 to 0.12. Raise it if the background looks noisy |
| `--edges` | Outline boost | 0.3 to 0.6 for line art like Berserk |
| `--ramp` | Character set: `detailed`, `standard`, `blocks`, `dots` | `standard` looks cleaner at small widths |
| `--no-color` | Characters only | Good for a monochrome portrait |
| `--saturation`, `--color-gain` | Color punch | Bump saturation if the red bike looks washed out |
| `--portrait`, `--portrait-time` | Which frame to rest on | Default is the last frame |
| `--luma value` | Density from the brightest channel instead of Rec. 709 luma | Saturated reds and blues on a dark scene |
| `--normalize` | Stretch each frame so its brightest cells use the whole ramp | Dark clips |
| `--vivid` | Colour brightness follows character brightness | Dark subjects that print too dim |
| `--grey-dim`, `--sat-lift` | Push dull greys back, pull strong colour forward | A stylised look where only the subject shows |

## Snapshots with termframe

`snapshot` renders one frame as an SVG window screenshot through [termframe](https://github.com/pamburus/termframe), on a pure black theme by default. Good for checking a frame outside the app, or for a README image of your own (only for the default skin, since Akira frames stay out of the repo).

```
brew install termframe
python3 tools/ascii/convert.py snapshot ~/.config/kana/skins/akira/intro.kana --frame 24 -o assets/private/previews/frame24.svg
```

Leave out `--frame` to render the portrait frame. `--theme` takes any `termframe --list-themes` name.

## Tips

- Preview in the same font and window size you'll actually use, since characters look different in different fonts
- If it looks like static, the clip is too busy. Crop tighter, raise `--bg-cut`, or pick a calmer shot
- Size is about 20 KB per frame at 110 wide with color, so a 3.5 second clip at 15 fps lands around 1 MB. That's fine to load at launch
- `play` needs a terminal that supports truecolor. Ghostty, iTerm2 and Wezterm all do. macOS Terminal.app doesn't, so use `--no-color` there

## `.kana` format

Plain JSON, documented in `docs/KANA.md` section 7. Version 1 fields: `format`, `version`, `width`, `height`, `fps` (0 for a still), `color`, `portrait`, and `frames`, where each frame has `rows` (one string per line) and, when color is on, `colors` (base64 of `width * height * 3` RGB bytes, row by row).

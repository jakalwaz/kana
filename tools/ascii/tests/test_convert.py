"""Exercise the real argparse entry point and validate serialized .kana files."""

import base64

import pytest


def test_video_contract_for_every_ramp(convert, video, ramp_name, ramp):
    data = convert(video, "--ramp", ramp_name)
    assert (data["width"], data["height"], data["fps"]) == (16, 6, 10)
    assert len(data["frames"]) == 16
    assert data["portrait"] == 15
    assert data["color"] is True
    chars = set("".join(row for f in data["frames"] for row in f["rows"]))
    assert chars <= set(ramp)
    assert len(chars) > 1
    if ramp_name in ("blocks", "dots"):
        assert any(len(ch.encode("utf-8")) > 1 for ch in chars)
    assert data["frames"][0]["rows"] != data["frames"][-1]["rows"]


@pytest.mark.parametrize("options,fps,indices", [
    (("--duration", "0.8", "--fps", "5"), 5, [0, 2, 4, 6]),
    (("--fps", "20"), 10, list(range(16))),
    (("--max-frames", "3"), 10, [0, 1, 2]),
    (("--start", "0.4", "--duration", "0.6", "--fps", "5"), 5, [4, 6, 8]),
])
def test_video_sampling(convert, video, options, fps, indices):
    original = convert(video)
    sampled = convert(video, *options)
    assert sampled["fps"] == fps
    assert sampled["frames"] == [original["frames"][i] for i in indices]
    assert sampled["portrait"] == len(indices) - 1


def test_still_for_every_ramp(convert, still, ramp_name):
    data = convert(still, "--ramp", ramp_name, "--fps", "5")
    assert len(data["frames"]) == 1
    assert data["fps"] == 0
    assert data["portrait"] == 0
    assert data["color"] is True


@pytest.mark.parametrize("options,expected", [
    (("--portrait", "2"), 2),
    (("--portrait", "-2"), 6),
    (("--portrait", "100"), 7),
    (("--portrait", "-100"), 0),
    (("--portrait-time", "0.6"), 3),
    (("--portrait", "1", "--portrait-time", "0.6"), 3),
    (("--portrait-time", "100"), 7),
])
def test_portrait_selection_and_clamping(convert, video, options, expected):
    baseline = convert(video, "--fps", "5")
    data = convert(video, "--fps", "5", *options)
    assert data["portrait"] == expected
    assert data["frames"] == baseline["frames"]
    assert data["frames"][expected] != data["frames"][(expected + 1) % 8]


@pytest.mark.parametrize("options,size", [
    (("--width", "24"), (24, 9)),
    (("--height", "11"), (16, 11)),
    (("--width", "20", "--height", "7"), (20, 7)),
])
def test_grid_dimensions(convert, still, options, size):
    data = convert(still, *options)
    assert (data["width"], data["height"]) == size


@pytest.mark.parametrize("source_name", ["still", "video"])
def test_no_color(convert, request, source_name):
    source = request.getfixturevalue(source_name)
    colored = convert(source)
    plain = convert(source, "--no-color")
    assert plain["color"] is False
    assert [f["rows"] for f in plain["frames"]] == [f["rows"] for f in colored["frames"]]
    assert all(f.get("colors") is None for f in plain["frames"])


def test_crop_samples_requested_region(convert, still):
    # A 32x48 crop -> 16x12 cells. The top-left cell is uniform background;
    # neutral color options make its RGB bytes an independent spatial oracle.
    neutral = ("--saturation", "1", "--color-gain", "1")
    left = convert(still, "--crop", "0,0,0.5,1", *neutral)
    right = convert(still, "--crop", "0.5,0,0.5,1", *neutral)
    assert (left["width"], left["height"]) == (16, 12)
    assert (right["width"], right["height"]) == (16, 12)
    assert base64.b64decode(left["frames"][0]["colors"])[:3] == bytes((100, 40, 30))
    assert base64.b64decode(right["frames"][0]["colors"])[:3] == bytes((40, 160, 120))
    assert left["frames"][0]["rows"] != right["frames"][0]["rows"]
    clipped = convert(still, "--crop", "0.5,0,1,1", *neutral)
    assert clipped == right


@pytest.mark.parametrize("window,start,middle,end", [
    ("0,1", 0, 5, 10),
    ("0.5,1.5", 5, 10, 15),
])
def test_moving_crop_samples_start_middle_and_end(convert, video, window, start, middle, end):
    left = convert(video, "--crop", "0,0,0.5,1")
    center = convert(video, "--crop", "0.25,0,0.5,1")
    right = convert(video, "--crop", "0.5,0,0.5,1")
    moving = convert(video, "--crop", "0,0,0.5,1", "--crop-end", "0.5,0,0.5,1",
                     "--crop-move", window)
    assert (moving["width"], moving["height"]) == (16, 12)
    assert moving["frames"][:start + 1] == left["frames"][:start + 1]
    assert moving["frames"][middle] == center["frames"][middle]
    assert moving["frames"][middle] != left["frames"][middle]
    assert moving["frames"][end:] == right["frames"][end:]
    assert moving["frames"][-1] != left["frames"][-1]


def test_decimal_crop_window_midpoint(convert, video):
    center = convert(video, "--crop", "0.25,0,0.5,1")
    moving = convert(video, "--crop", "0,0,0.5,1", "--crop-end", "0.5,0,0.5,1",
                     "--crop-move", "0.2,0.8")
    # t=0.5 is halfway through 0.2..0.8; smoothstep's midpoint is also 0.5.
    assert moving["frames"][5] == center["frames"][5]


@pytest.mark.parametrize("source_name,details", [
    ("video", ("16 (1.60s, 10 fps)", "frame 15")),
    ("still", ("1 (still, 0 fps)", "frame 0")),
])
def test_info(convert, cli, tmp_path, request, source_name, details):
    convert(request.getfixturevalue(source_name))
    result = cli("info", tmp_path / "output.kana")
    assert result.code == 0, result.stderr
    for expected in ("grid      16x6", "color     yes") + details:
        assert expected in result.stdout


@pytest.mark.parametrize("kind,message", [
    ("missing", "No such file:"),
    ("image", "Couldn't read image:"),
    ("video", "Couldn't open video:"),
])
def test_unreadable_input(cli, tmp_path, kind, message):
    source = tmp_path / ("bad.png" if kind == "image" else "bad.avi")
    if kind != "missing":
        source.write_bytes(b"not an image or video")
    output = tmp_path / "bad.kana"
    result = cli("convert", source, "-o", output)
    assert result.code == 1
    assert message in result.stderr
    assert not output.exists()


@pytest.mark.parametrize("crop,message", [
    ("0,0,1", "--crop needs four numbers"),
    ("a,0,1,1", "--crop needs four numbers"),
    ("0,0,0,1", "--crop values must be fractions"),
    ("1,0,0.5,1", "--crop values must be fractions"),
    ("0,0,2,1", "--crop values must be fractions"),
])
def test_bad_crop(cli, still, tmp_path, crop, message):
    output = tmp_path / "bad.kana"
    result = cli("convert", still, "-o", output, "--crop", crop)
    assert result.code == 2
    assert message in result.stderr
    assert not output.exists()


def test_missing_input_argument(cli, tmp_path):
    result = cli("convert", "-o", tmp_path / "bad.kana")
    assert result.code == 2
    assert "required: input" in result.stderr


def test_start_beyond_clip(cli, video, tmp_path):
    output = tmp_path / "bad.kana"
    result = cli("convert", video, "-o", output, "--start", "99")
    assert result.code == 1
    assert "No frames read" in result.stderr
    assert not output.exists()

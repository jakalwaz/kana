"""Tiny generated media and CLI fixtures; no checked-in binary assets."""

import base64
import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace

import cv2
import numpy as np
import pytest


CONVERTER = Path(__file__).resolve().parents[1] / "convert.py"
SPEC = importlib.util.spec_from_file_location("kana_ascii_converter", CONVERTER)
converter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(converter)


def pytest_generate_tests(metafunc):
    if "ramp_name" in metafunc.fixturenames:
        metafunc.parametrize("ramp_name", sorted(converter.RAMPS))


def assert_kana(data):
    """C1 validates character counts, not UTF-8 byte counts."""
    assert data["format"] == "kana-ascii"
    assert data["version"] == 1
    width, height = data["width"], data["height"]
    assert width > 0 and height > 0
    assert data["frames"]
    assert 0 <= data["portrait"] < len(data["frames"])
    for frame in data["frames"]:
        assert len(frame["rows"]) == height
        assert all(len(row) == width for row in frame["rows"])
        if data["color"]:
            colors = base64.b64decode(frame["colors"], validate=True)
            assert len(colors) == width * height * 3
        else:
            assert frame.get("colors") is None


@pytest.fixture
def cli(monkeypatch, capsys):
    def run(*args):
        monkeypatch.setattr(sys, "argv", [str(CONVERTER)] + [str(a) for a in args])
        code = 0
        try:
            converter.main()
        except SystemExit as exc:
            code = exc.code if isinstance(exc.code, int) else 1
            if isinstance(exc.code, str):
                print(exc.code, file=sys.stderr)
        captured = capsys.readouterr()
        return SimpleNamespace(code=code, stdout=captured.out, stderr=captured.err)
    return run


@pytest.fixture
def convert(cli, tmp_path):
    def run(source, *options):
        output = tmp_path / "output.kana"
        result = cli("convert", source, "-o", output, "--width", 16, *options)
        assert result.code == 0, result.stderr
        data = json.loads(output.read_text(encoding="utf-8"))
        assert_kana(data)
        return data
    return run


def synthetic_frame(index):
    frame = np.empty((48, 64, 3), dtype=np.uint8)
    frame[:, :32] = (30, 40, 100)
    frame[:, 32:] = (120, 160, 40)
    x = 2 + 3 * index
    frame[16:32, x:x + 10] = (255, 255, 255)
    return frame


@pytest.fixture
def still(tmp_path):
    path = tmp_path / "still.png"
    assert cv2.imwrite(str(path), synthetic_frame(0))
    return path


@pytest.fixture
def video(tmp_path):
    """16 frames at 10 fps, with MJPG fallback if mp4v is unavailable."""
    for codec, extension in (("mp4v", ".mp4"), ("MJPG", ".avi")):
        path = tmp_path / ("moving" + extension)
        writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*codec), 10, (64, 48))
        opened = writer.isOpened()
        try:
            if opened:
                for index in range(16):
                    writer.write(synthetic_frame(index))
        finally:
            writer.release()
        if not opened:
            continue
        capture = cv2.VideoCapture(str(path))
        try:
            decoded = 0
            while capture.read()[0]:
                decoded += 1
            fps = capture.get(cv2.CAP_PROP_FPS)
        finally:
            capture.release()
        if decoded == 16 and abs(fps - 10) < 0.01:
            return path
    pytest.fail("Neither mp4v nor MJPG could create a readable 16-frame test clip")


@pytest.fixture
def ramp(ramp_name):
    return converter.RAMPS[ramp_name]

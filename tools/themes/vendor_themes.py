#!/usr/bin/env python3
"""Vendor Ghostty themes with Python 3.9+ and the standard library only.

Run from any directory: python3 tools/themes/vendor_themes.py
For offline checks: --archive /path/to/source.tar.gz --output /tmp/themes
The destination is replaced only after the archive has been validated.
"""

# The upstream release of 2026-09-28 (tag release-20260928-151043-99d9701,
# checked with git ls-remote). Bump on purpose, then re-run this script.
COMMIT_SHA = "99d9701ba3cf4a06d24eea6ca4f25a64656b446b"

import argparse
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
from typing import Tuple
import urllib.error
import urllib.request

ARCHIVE_URL = (
    "https://codeload.github.com/mbadolato/iTerm2-Color-Schemes/tar.gz/" + COMMIT_SHA
)
ARCHIVE_ROOT = "iTerm2-Color-Schemes-" + COMMIT_SHA
DEFAULT_OUTPUT = Path(__file__).resolve().parents[2] / "Resources" / "themes"


def extract_themes(archive: Path, destination: Path) -> Tuple[int, int]:
    """Replace destination with just the pinned archive's themes and LICENSE.

    Never use extractall: reject links and unsafe paths, and copy regular files
    explicitly. Staging protects an existing theme set from download/archive
    errors. Return the theme count and total bytes (including LICENSE).
    """
    destination = Path(destination)
    if destination.is_symlink():
        raise ValueError("destination must not be a symlink")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".kana-themes-", dir=destination.parent) as temporary:
        stage = Path(temporary) / "themes"
        stage.mkdir()
        seen = set()
        count = total = 0
        with tarfile.open(archive, mode="r:gz") as source:
            for member in source:
                parts = member.name.split("/")
                if not parts or parts[0] != ARCHIVE_ROOT:
                    raise ValueError("archive has an unexpected root: " + member.name)
                if any(part in (".", "..") for part in parts) or "\\" in member.name:
                    raise ValueError("unsafe archive path: " + member.name)
                relative = parts[1:]
                is_license = relative == ["LICENSE"]
                is_theme = len(relative) >= 2 and relative[0] == "ghostty"
                if not (is_license or is_theme) or member.isdir():
                    continue
                if not member.isfile():
                    raise ValueError("archive entry is not a regular file: " + member.name)
                # Upstream themes are flat files. Reject an unexpected layout
                # rather than silently changing theme names or overwriting files.
                if is_theme and (len(relative) != 2 or not relative[1]):
                    raise ValueError("unexpected theme path: " + member.name)
                name = "LICENSE" if is_license else relative[1]
                if name.casefold() in seen:
                    raise ValueError("duplicate destination filename: " + name)
                seen.add(name.casefold())
                extracted = source.extractfile(member)
                if extracted is None:
                    raise ValueError("cannot read archive member: " + member.name)
                with extracted, (stage / name).open("wb") as output:
                    shutil.copyfileobj(extracted, output)
                total += member.size
                count += int(is_theme)
        if "license" not in seen or count == 0:
            raise ValueError("archive must contain LICENSE and at least one Ghostty theme")
        if destination.exists():
            shutil.rmtree(destination)
        stage.rename(destination)
    return count, total


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="use a local pinned source tarball")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="directory to replace")
    args = parser.parse_args(argv)
    try:
        if args.archive is not None:
            count, total = extract_themes(args.archive, args.output)
        else:
            with tempfile.TemporaryDirectory(prefix="kana-theme-download-") as temporary:
                archive = Path(temporary) / "themes.tar.gz"
                request = urllib.request.Request(ARCHIVE_URL, headers={"User-Agent": "Kana-theme-vendor"})
                with urllib.request.urlopen(request, timeout=60) as response, archive.open("wb") as output:
                    shutil.copyfileobj(response, output)
                count, total = extract_themes(archive, args.output)
    except (OSError, ValueError, tarfile.TarError, urllib.error.URLError) as error:
        print("Theme vendoring failed: " + str(error), file=sys.stderr)
        return 1
    print("Vendored {} themes; {} bytes including LICENSE; commit {}".format(count, total, COMMIT_SHA))
    return 0


if __name__ == "__main__":
    sys.exit(main())

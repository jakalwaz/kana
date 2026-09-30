"""Offline checks: python3 -m unittest discover -s tools/themes -v"""

import contextlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

import vendor_themes as vendor


class VendorThemesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kana-vendor-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / "source.tar.gz"
        self.output = self.root / "themes"

    def make_archive(self, entries=None):
        if entries is None:
            entries = [("LICENSE", b"test license\n"),
                       ("ghostty/Day Theme", b"background = ffffff\n"),
                       ("ghostty/Night", b"background = 000000\n"),
                       ("kitty/Ignore", b"not a ghostty theme"),
                       ("README.md", b"not a theme")]
        with tarfile.open(self.archive, "w:gz") as archive:
            for name, data in entries:
                info = tarfile.TarInfo(vendor.ARCHIVE_ROOT + "/" + name)
                if data is None:
                    info.type = tarfile.SYMTYPE
                    info.linkname = "/tmp/outside"
                    archive.addfile(info)
                else:
                    info.size = len(data)
                    archive.addfile(info, io.BytesIO(data))

    def test_only_themes_and_license_are_copied_byte_for_byte(self):
        self.make_archive()
        count, size = vendor.extract_themes(self.archive, self.output)
        self.assertEqual(count, 2)
        self.assertEqual(sorted(path.name for path in self.output.iterdir()), ["Day Theme", "LICENSE", "Night"])
        self.assertEqual((self.output / "LICENSE").read_bytes(), b"test license\n")
        self.assertEqual((self.output / "Day Theme").read_bytes(), b"background = ffffff\n")
        self.assertEqual(size, sum(path.stat().st_size for path in self.output.iterdir()))

    def test_repeated_run_removes_stale_files_and_is_identical(self):
        self.make_archive()
        vendor.extract_themes(self.archive, self.output)
        expected = {path.name: path.read_bytes() for path in self.output.iterdir()}
        (self.output / "stale").mkdir()
        (self.output / "stale" / "old").write_text("remove me")
        (self.output / "Day Theme").write_text("changed")
        vendor.extract_themes(self.archive, self.output)
        self.assertEqual({path.name: path.read_bytes() for path in self.output.iterdir()}, expected)

    def test_bad_archives_leave_existing_themes_untouched(self):
        self.output.mkdir()
        (self.output / "keep").write_bytes(b"original")
        cases = [
            [("ghostty/Only", b"no license")],
            [("LICENSE", b"no themes")],
            [("LICENSE", b"license"), ("ghostty/../../escape", b"escape")],
            [("LICENSE", b"license"), ("ghostty/link", None)],
            [("LICENSE", b"license"), ("ghostty/nested/theme", b"unexpected")],
            [("LICENSE", b"license"), ("ghostty/Duplicate", b"a"), ("ghostty/duplicate", b"b")],
            [("LICENSE", b"license"), ("ghostty/LICENSE", b"collision")],
        ]
        for entries in cases:
            with self.subTest(entries=entries):
                self.make_archive(entries)
                with self.assertRaises(ValueError):
                    vendor.extract_themes(self.archive, self.output)
                self.assertEqual((self.output / "keep").read_bytes(), b"original")
                self.assertEqual(list(self.root.glob(".kana-themes-*")), [])
        self.assertFalse((self.root / "escape").exists())

    def test_unexpected_archive_root_is_rejected(self):
        with tarfile.open(self.archive, "w:gz") as archive:
            info = tarfile.TarInfo("different-commit/LICENSE")
            archive.addfile(info, io.BytesIO())
        with self.assertRaisesRegex(ValueError, "unexpected root"):
            vendor.extract_themes(self.archive, self.output)
        self.assertFalse(self.output.exists())

    def test_destination_symlink_is_rejected(self):
        target = self.root / "outside"
        target.mkdir()
        self.output.symlink_to(target, target_is_directory=True)
        self.make_archive()
        with self.assertRaisesRegex(ValueError, "symlink"):
            vendor.extract_themes(self.archive, self.output)
        self.assertEqual(list(target.iterdir()), [])

    def test_cli_local_archive(self):
        self.make_archive()
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result = vendor.main(["--archive", str(self.archive), "--output", str(self.output)])
        self.assertEqual(result, 0)
        self.assertIn("Vendored 2 themes", stdout.getvalue())
        self.assertIn(vendor.COMMIT_SHA, stdout.getvalue())

    def test_download_uses_pinned_url(self):
        self.make_archive()
        with patch.object(vendor.urllib.request, "urlopen", return_value=io.BytesIO(self.archive.read_bytes())) as download:
            with contextlib.redirect_stdout(io.StringIO()):
                result = vendor.main(["--output", str(self.output)])
        self.assertEqual(result, 0)
        request = download.call_args.args[0]
        self.assertEqual(request.full_url, vendor.ARCHIVE_URL)
        self.assertIn(vendor.COMMIT_SHA, request.full_url)

    def test_failed_download_keeps_existing_files(self):
        self.output.mkdir()
        (self.output / "keep").write_bytes(b"original")
        stderr = io.StringIO()
        with patch.object(vendor.urllib.request, "urlopen", side_effect=urllib.error.URLError("offline")):
            with contextlib.redirect_stderr(stderr):
                result = vendor.main(["--output", str(self.output)])
        self.assertEqual(result, 1)
        self.assertIn("offline", stderr.getvalue())
        self.assertEqual((self.output / "keep").read_bytes(), b"original")


if __name__ == "__main__":
    unittest.main()

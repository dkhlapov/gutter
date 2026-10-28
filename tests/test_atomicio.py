import os, stat, sys, tempfile, unittest
from pathlib import Path
from unittest import mock
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import atomicio

class WriteAtomic(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def test_creates_parents_and_sets_the_mode(self):
        path = self.dir / "a" / "b" / "f.txt"
        atomicio.write_atomic(path, "hello", ".t-", mode=0o600)
        self.assertEqual(path.read_text(), "hello")
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual([f.name for f in path.parent.iterdir()], ["f.txt"])

    def test_replaces_an_existing_file(self):
        path = self.dir / "f.txt"
        path.write_text("old")
        atomicio.write_atomic(path, "new", ".t-")
        self.assertEqual((path.read_text(), stat.S_IMODE(path.stat().st_mode)), ("new", 0o644))

    def test_failure_removes_the_temp_file_and_keeps_the_target(self):
        path = self.dir / "f.txt"
        path.write_text("old")
        with self.assertRaises(TypeError):
            atomicio.write_atomic(path, None, ".t-")        # f.write(None)
        with mock.patch("os.replace", side_effect=OSError("boom")), self.assertRaises(OSError):
            atomicio.write_atomic(path, "new", ".t-")
        self.assertEqual(path.read_text(), "old")
        self.assertEqual([f.name for f in self.dir.iterdir()], ["f.txt"])

    def test_syncs_the_file_before_replacing_and_the_directory_after(self):
        calls = []
        real_fsync, real_replace = os.fsync, os.replace
        def fsync(fd):
            calls.append("fsync dir" if stat.S_ISDIR(os.fstat(fd).st_mode) else "fsync file")
            real_fsync(fd)
        with mock.patch("os.fsync", side_effect=fsync), \
                mock.patch("os.replace", side_effect=lambda a, b: calls.append("replace") or real_replace(a, b)):
            atomicio.write_atomic(self.dir / "f.txt", "x", ".t-")
        self.assertEqual(calls, ["fsync file", "replace", "fsync dir"])

    def test_a_directory_that_cannot_be_synced_is_not_an_error(self):
        real_fsync = os.fsync
        def fsync(fd):
            if stat.S_ISDIR(os.fstat(fd).st_mode):
                raise OSError("no")
            real_fsync(fd)
        with mock.patch("os.fsync", side_effect=fsync):
            atomicio.write_atomic(self.dir / "f.txt", "x", ".t-")
        self.assertEqual((self.dir / "f.txt").read_text(), "x")

    def test_a_symlink_is_kept_and_written_through(self):
        real = self.dir / "dotfiles" / "real.lua"
        real.parent.mkdir()
        real.write_text("old")
        link = self.dir / "state" / "link.lua"
        link.parent.mkdir()
        link.symlink_to(real)
        atomicio.write_atomic(link, "new", ".t-")
        self.assertTrue(link.is_symlink())
        self.assertEqual((os.readlink(link), real.read_text()), (str(real), "new"))
        self.assertEqual([f.name for f in link.parent.iterdir()], ["link.lua"])
        self.assertEqual([f.name for f in real.parent.iterdir()], ["real.lua"])

    def test_a_dangling_symlink_creates_its_target(self):
        real = self.dir / "dotfiles" / "real.lua"
        link = self.dir / "link.lua"
        link.symlink_to(real)
        atomicio.write_atomic(link, "new", ".t-")
        self.assertTrue(link.is_symlink())
        self.assertEqual(real.read_text(), "new")

if __name__ == "__main__":
    unittest.main()

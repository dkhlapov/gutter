import os, shutil, subprocess, sys, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
HYPR = ROOT / "hypr"


class HyprConfig(unittest.TestCase):
    @unittest.skipUnless(shutil.which("Hyprland"), "Hyprland is not installed")
    def test_verify_config(self):
        with tempfile.TemporaryDirectory() as d:
            # Nothing of the live session is read or written: HOME and the XDG folders are all empty temp folders.
            env = dict(os.environ, HOME=d, XDG_CONFIG_HOME=d + "/config", XDG_STATE_HOME=d + "/state",
                       XDG_CACHE_HOME=d + "/cache", XDG_DATA_HOME=d + "/data", XDG_RUNTIME_DIR=d)
            loader = Path(d) / "hyprland.lua"
            loader.write_text('package.path = "%s/?.lua;" .. package.path\nrequire("gutter")\n' % HYPR)
            r = subprocess.run(["Hyprland", "--verify-config", "-c", str(loader)], env=env, capture_output=True,
                               text=True, timeout=60)
            out = r.stdout + r.stderr
            self.assertEqual(r.returncode, 0, out)
            self.assertNotIn("error", out.lower(), out)


if __name__ == "__main__":
    unittest.main()

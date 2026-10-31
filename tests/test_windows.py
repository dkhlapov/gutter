import re, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

# A layer-shell PanelWindow is destroyed when `visible` goes false and made again when it goes true. The
# window's content is moved out of the old window and into the new one, and a TrayIcon inside it keeps a
# ShaderEffectSource on an image, which holds on to the old window ("QQuickItem: Cannot use same item on different
# windows at the same time") and crashes Qt with a SIGSEGV in QQuickItemPrivate::deliveryAgent. The bars hit it
# every time a fullscreen window ended. So a window never unmaps for a fullscreen window.
#
# Nor does its layer follow fullscreen. Hyprland hides a top-layer surface under a fullscreen window and shows it
# again after, by itself. Moving a surface below the overlay layer under a fullscreen window instead sets its alpha
# to 0 with nothing to restore it, and a hidden surface gets no frame callbacks, so the window never commits the
# move back: the bar or pill stayed gone, on one monitor, until the shell restarted.
class Windows(unittest.TestCase):
    def windows(self):
        # Not the tests, and not hidden folders (`.claude/worktrees` holds other checkouts of this repo).
        files = [p for p in ROOT.rglob("*.qml") if not {"tests"} & set(p.relative_to(ROOT).parts) and not any(x.startswith(".") for x in p.relative_to(ROOT).parts) and re.search(r"^PanelWindow \{", p.read_text(), re.M)]
        self.assertTrue(files)
        return files

    def test_no_window_unmaps_for_fullscreen(self):
        for p in self.windows():
            # Only the window's own `visible` (one indent, to the next property); a nested item may have its own.
            for block in re.findall(r"^    visible:.*?(?=^    \w|\Z)", p.read_text(), re.M | re.S):
                self.assertNotRegex(block, r"(?i)fullscreen", f"{p.relative_to(ROOT)}: PanelWindow.visible follows fullscreen; use WlrLayershell.layer")

    def test_layer_does_not_follow_fullscreen(self):
        for p in self.windows():
            for line in re.findall(r"WlrLayershell\.layer:[^\n]*", p.read_text()):
                self.assertNotRegex(line, r"hasFullscreen|WlrLayer\.Bottom", f"{p.relative_to(ROOT)}: the layer follows fullscreen; the top layer hides under it by itself")

if __name__ == "__main__":
    unittest.main()

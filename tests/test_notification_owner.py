import json, os, re, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The fake busctl: BUSCTL_STATUS and BUSCTL_LIST name what `status` and `list` do (ok: print BUSCTL_OUT, fail: exit 1).
BUSCTL = """#!/bin/sh
case "$2" in
    status) mode="$BUSCTL_STATUS" ;;
    list) mode="$BUSCTL_LIST" ;;
esac
[ "$mode" = ok ] || exit 1
[ "$2" = status ] && printf '%s\\n' "$BUSCTL_OUT"
exit 0
"""


def owner_command():
    # The command is one string literal in lib/notifications.js, JSON-compatible.
    src = (ROOT / "lib/notifications.js").read_text()
    literal = re.search(r'function ownerCommand\(\) \{\s*return \["sh", "-c", ("(?:[^"\\]|\\.)*")\];', src)
    return json.loads(literal.group(1))


class OwnerCommand(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        stub = Path(tmp.name) / "busctl"
        stub.write_text(BUSCTL)
        stub.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{tmp.name}:{os.environ['PATH']}"}

    def run_check(self, status, listing, out=""):
        env = {**self.env, "BUSCTL_STATUS": status, "BUSCTL_LIST": listing, "BUSCTL_OUT": out}
        return subprocess.run(["sh", "-c", owner_command()], env=env, capture_output=True, text=True, check=True).stdout

    def test_other_holder(self):
        out = self.run_check("ok", "ok", "Name=org.freedesktop.Notifications\nPID=4242\nUID=1000")
        self.assertRegex(out, r"(?m)^self=\d+$")
        self.assertIn("owner=4242\n", out)
        self.assertNotIn("failed=1", out)

    # Nobody holds the name: status fails, but the bus answers.
    def test_nobody_holds_the_name(self):
        out = self.run_check("fail", "ok")
        self.assertRegex(out, r"(?m)^self=\d+$")
        self.assertNotIn("owner=", out)
        self.assertNotIn("failed=1", out)

    # busctl is there but the bus cannot be asked: the check could not tell.
    def test_failing_busctl_is_unknown(self):
        out = self.run_check("fail", "fail")
        self.assertIn("failed=1\n", out)
        self.assertNotIn("owner=", out)

    # A holder with no pid in the answer cannot be told from nobody, so it is not taken as nobody.
    def test_status_without_a_pid_is_unknown(self):
        out = self.run_check("ok", "ok", "Name=org.freedesktop.Notifications\nUID=1000")
        self.assertIn("failed=1\n", out)


if __name__ == "__main__":
    unittest.main()

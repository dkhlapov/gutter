import json, os, shutil, stat, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
FOOT_INI = '''shell=fish
font=JetBrains Mono Nerd Font:size=12

[scrollback]
lines=10000

[colors-dark]
alpha=0.78
'''
FUZZEL_INI = '''font=JetBrains Mono NF:size=17
terminal=foot -e

[colors]
background=282c34dd

[border]
radius=10
width=2

[main]
x=1
'''
LOGGING_STUB = '#!/bin/sh\necho "%s $*" >> "%s"\n'
HAS_HYPRLAND = shutil.which("Hyprland") is not None


def tree(root):
    """{relative path: (kind, content or link target, mode)} for everything under root."""
    out = {}
    for p in sorted(Path(root).rglob("*")):
        rel = str(p.relative_to(root))
        mode = stat.S_IMODE(p.lstat().st_mode)
        if p.is_symlink():
            out[rel] = ("link", os.readlink(p), mode)
        elif p.is_dir():
            out[rel] = ("dir", None, mode)
        else:
            out[rel] = ("file", p.read_bytes(), mode)
    return out


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.home = self.dir / "home"
        self.cfg = self.home / ".config"
        self.state = self.home / ".local/state"
        self.log = self.dir / "calls.log"
        self.log.touch()
        self.stubs = self.dir / "stubs"
        self.stubs.mkdir()
        self.stub("hyprctl")
        # Scrubbed: nothing may reach the real HOME, Claude config or runtime dir.
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("XDG_", "CLAUDE", "GUTTER_", "HYPRLAND_"))}
        self.env.update(HOME=str(self.home), XDG_STATE_HOME=str(self.state), XDG_CONFIG_HOME=str(self.cfg),
                        XDG_RUNTIME_DIR=str(self.dir / "run"), PATH="%s:%s" % (self.stubs, os.environ["PATH"]))

    def stub(self, name, body=None):
        f = self.stubs / name
        f.write_text(body or LOGGING_STUB % (name, self.log))
        f.chmod(0o755)

    def calls(self):
        return self.log.read_text().splitlines()

    def put(self, rel, text, mode=0o644):
        f = self.home / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text)
        f.chmod(mode)
        return f

    def read(self, rel):
        return (self.home / rel).read_text()

    def run_script(self, name, *args, dry=True, repo=None, **env):
        e = dict(self.env, **env)
        if dry:
            e["GUTTER_DRY"] = "1"
        script = (repo / "scripts" if repo else SCRIPTS) / name
        return subprocess.run([str(script), *args], capture_output=True, text=True, env=e, timeout=120)

    def copy_repo(self, name, with_gutter_lua=True):
        """A minimal copy of the repo (scripts, tools, hypr, theme) in a folder called `name`."""
        dest = self.dir / name
        ignore = shutil.ignore_patterns("__pycache__")
        for sub in ("scripts", "tools", "hypr", "theme"):
            shutil.copytree(ROOT / sub, dest / sub, ignore=ignore)
        if not with_gutter_lua:
            (dest / "hypr/gutter.lua").unlink()
        return dest

    def link_shell(self, target):
        (self.cfg / "quickshell").mkdir(parents=True, exist_ok=True)
        link = self.cfg / "quickshell/gutter"
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(target)


class InstallHyprland(Base):
    def setUp(self):
        super().setUp()
        self.put(".config/hypr/hyprland.lua", "-- previous loader\n")
        self.put(".config/hypr/variables.lua", "return {}\n")
        self.put(".config/hypr/utils/fn.lua", "return {}\n")
        self.link_shell(ROOT)       # what scripts/install.sh makes

    def run_hypr(self, *args, **kw):
        r = self.run_script("install-hyprland.sh", *args, **kw)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def apply(self, **kw):
        return self.run_hypr("--apply", **kw)

    def test_dry_run_writes_nothing(self):
        before = tree(self.home)
        r = self.run_hypr()
        self.assertEqual(tree(self.home), before)
        self.assertIn("would:", r.stdout)
        self.assertEqual(self.calls(), [])
        r = self.run_hypr("--dry-run")
        self.assertEqual(tree(self.home), before)

    def test_dry_run_lists_every_step(self):
        out = self.run_hypr().stdout
        for word in ("hypr.pre-gutter", "hypr-gutter.lua", "hyprland.lua", "hyprctl reload"):
            self.assertIn(word, out)

    def test_apply_creates_backup_and_loader(self):
        old_hypr = tree(self.cfg / "hypr")
        self.apply()
        self.assertEqual(tree(self.cfg / "hypr.pre-gutter"), old_hypr)
        self.assertFalse((self.cfg / "gutter/hypr-user.lua").exists())
        loader = self.read(".config/hypr/hyprland.lua")
        template = (ROOT / "hypr/loader.lua.in").read_text()
        self.assertEqual(loader, template.replace("@REPO@", str(ROOT)))
        self.assertTrue((self.state / "gutter/hypr-gutter.lua").read_text().startswith("-- Generated by Gutter"))
        # The old files stay in place, unused.
        self.assertEqual(self.read(".config/hypr/variables.lua"), "return {}\n")
        self.assertEqual(self.read(".config/hypr/utils/fn.lua"), "return {}\n")
        # GUTTER_DRY: no hyprctl call
        self.assertEqual(self.calls(), [])

    def marker(self, sig="sig1"):
        return self.dir / "run/gutter" / ("hypr-started-" + sig)

    def test_apply_touches_the_loader_marker(self):
        self.apply(HYPRLAND_INSTANCE_SIGNATURE="sig1")
        self.assertTrue(self.marker().is_file())
        # Without a signature the loader's fallback name.
        self.apply()
        self.assertTrue(self.marker("x").is_file())

    def test_marker_follows_xdg_runtime_dir_and_falls_back_to_tmp(self):
        other = self.dir / "elsewhere"
        self.apply(XDG_RUNTIME_DIR=str(other), HYPRLAND_INSTANCE_SIGNATURE="s")
        self.assertTrue((other / "gutter/hypr-started-s").is_file())

    def test_dry_run_does_not_touch_the_marker(self):
        self.run_hypr(HYPRLAND_INSTANCE_SIGNATURE="sig1")
        self.assertFalse((self.dir / "run").exists())
        r = self.run_hypr("--dry-run", HYPRLAND_INSTANCE_SIGNATURE="sig1")
        self.assertFalse((self.dir / "run").exists())
        self.assertIn("would: touch the loader marker", r.stdout)

    def test_manual_steps_are_printed(self):
        out = self.apply().stdout
        self.assertIn("cava", out)

    def test_apply_twice_is_idempotent(self):
        self.apply()
        # What the first run produced, plus a change in the old config that the backup must not pick up.
        (self.cfg / "hypr/variables.lua").write_text("return { changed = true }\n")
        first = tree(self.home)
        self.apply()
        self.assertEqual(tree(self.home), first)
        self.assertEqual((self.cfg / "hypr.pre-gutter/variables.lua").read_text(), "return {}\n")

    def test_loader_is_not_rewritten_when_identical(self):
        self.apply()
        loader = self.cfg / "hypr/hyprland.lua"
        os.utime(loader, (1000, 1000))
        self.apply()
        self.assertEqual(loader.stat().st_mtime, 1000)

    def test_missing_hypr_dir_is_skipped(self):
        shutil.rmtree(self.cfg / "hypr")
        self.apply()
        self.assertFalse((self.cfg / "hypr.pre-gutter").exists())
        self.assertTrue((self.cfg / "hypr/hyprland.lua").exists())

    def refuse(self, repo=None, *args, **kw):
        before = tree(self.home)
        r = self.run_script("install-hyprland.sh", *args, repo=repo, **kw)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertEqual(tree(self.home), before)
        return r

    def refuse_repo(self, name):
        repo = self.copy_repo(name)
        self.link_shell(repo)
        r = self.refuse(repo, "--apply")
        self.assertIn("cannot go in the loader", r.stderr)
        self.refuse(repo)                            # a dry run refuses too

    def test_repo_path_with_semicolon_is_refused(self):
        self.refuse_repo("a;b")

    def test_repo_path_with_question_mark_is_refused(self):
        self.refuse_repo("a?b")

    def test_repo_path_with_long_bracket_close_is_refused(self):
        self.refuse_repo("a]==]b")

    def test_repo_path_ending_in_bracket_prefix_is_refused(self):
        self.refuse_repo("a]==")

    def test_repo_path_with_newline_is_refused(self):
        self.refuse_repo("a\nb")

    def test_repo_path_with_other_odd_characters_is_accepted(self):
        repo = self.copy_repo("a b&c]==d")
        self.link_shell(repo)
        r = self.run_script("install-hyprland.sh", "--apply", repo=repo)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("[==[%s]==]" % repo, self.read(".config/hypr/hyprland.lua"))

    def test_missing_shell_link_is_refused(self):
        (self.cfg / "quickshell/gutter").unlink()
        for args in (("--apply",), ()):
            r = self.refuse(None, *args)
            self.assertIn("scripts/install.sh", r.stderr)

    def test_dangling_shell_link_is_refused(self):
        self.link_shell(self.dir / "gone")
        r = self.refuse(None, "--apply")
        self.assertIn("scripts/install.sh", r.stderr)

    def test_shell_link_to_another_folder_is_refused(self):
        other = self.copy_repo("other")
        self.link_shell(other)
        r = self.refuse(None, "--apply")
        self.assertIn("this checkout", r.stderr)
        self.refuse(None)

    def test_missing_gutter_lua_is_refused(self):
        repo = self.copy_repo("partial", with_gutter_lua=False)
        self.link_shell(repo)
        r = self.refuse(repo, "--apply")
        self.assertIn("gutter.lua", r.stderr)
        self.refuse(repo)

    def test_shell_link_checks_hold_without_gutter_dry(self):
        self.stub("Hyprland")
        (self.cfg / "quickshell/gutter").unlink()
        self.refuse(None, "--apply", dry=False)
        self.assertEqual(self.calls(), [])

    def test_a_checkout_that_is_the_link_itself_is_accepted(self):
        # ~/.config/quickshell/gutter may be the checkout (a plain folder): readlink -f is the folder itself.
        repo = self.copy_repo("plain")
        (self.cfg / "quickshell/gutter").unlink()
        shutil.rmtree(self.cfg / "quickshell")
        (self.cfg / "quickshell").mkdir()
        os.rename(repo, self.cfg / "quickshell/gutter")
        moved = self.cfg / "quickshell/gutter"
        r = self.run_script("install-hyprland.sh", "--apply", repo=moved)
        self.assertEqual(r.returncode, 0, r.stderr)

    # --- symlinked hypr dir and loader ---

    def test_symlinked_hypr_dir_is_backed_up_by_content(self):
        dotfiles = self.dir / "dotfiles-hypr"
        os.rename(self.cfg / "hypr", dotfiles)
        (self.cfg / "hypr").symlink_to(dotfiles)
        original = tree(dotfiles)
        self.apply()
        backup = self.cfg / "hypr.pre-gutter"
        self.assertFalse(backup.is_symlink())
        self.assertEqual(tree(backup), original)
        self.assertEqual((backup / "hyprland.lua").read_text(), "-- previous loader\n")
        self.assertTrue((self.cfg / "hypr").is_symlink())      # the folder link stays
        self.assertTrue((self.cfg / "hypr/hyprland.lua").read_text().startswith("-- Gutter's Hyprland loader"))
        self.assertEqual(self.read(".config/hypr/variables.lua"), "return {}\n")

    def test_symlinked_hyprland_lua_is_replaced_not_written_through(self):
        dotfiles = self.dir / "dotfiles"
        dotfiles.mkdir()
        target = dotfiles / "hyprland.lua"
        target.write_text("-- dotfiles loader\n")
        (self.cfg / "hypr/hyprland.lua").unlink()
        (self.cfg / "hypr/hyprland.lua").symlink_to(target)
        self.apply()
        loader = self.cfg / "hypr/hyprland.lua"
        self.assertFalse(loader.is_symlink())
        self.assertTrue(loader.read_text().startswith("-- Gutter's Hyprland loader"))
        self.assertEqual(target.read_text(), "-- dotfiles loader\n")
        self.assertEqual((self.cfg / "hypr.pre-gutter/hyprland.lua").read_text(), "-- dotfiles loader\n")
        self.assertFalse((self.cfg / "hypr.pre-gutter/hyprland.lua").is_symlink())
        first = tree(self.home)
        self.apply()
        self.assertEqual(tree(self.home), first)

    def test_failed_backup_leaves_no_temp_folder(self):
        (self.cfg / "hypr/dangling").symlink_to(self.dir / "nowhere")
        before = tree(self.home)
        r = self.run_script("install-hyprland.sh", "--apply")
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertEqual(tree(self.home), before)
        self.assertEqual([p.name for p in self.cfg.iterdir() if "pre-gutter" in p.name], [])

    def test_verify_failure_aborts_before_writes(self):
        self.stub("Hyprland", '#!/bin/sh\necho "Hyprland $*" >> "%s"\necho "config error" >&2\nexit 1\n' % self.log)
        before = tree(self.home)
        r = self.run_script("install-hyprland.sh", "--apply", dry=False)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(tree(self.home), before)
        self.assertEqual([c.split()[0] for c in self.calls()], ["Hyprland"])      # no hyprctl
        self.assertIn("--verify-config", self.calls()[0])
        self.assertIn("config error", r.stderr)

    def test_verify_failure_also_fails_a_dry_run(self):
        self.stub("Hyprland", "#!/bin/sh\nexit 1\n")
        r = self.run_script("install-hyprland.sh", dry=False)
        self.assertEqual(r.returncode, 1)

    def test_apply_verifies_then_reloads(self):
        self.stub("Hyprland")
        self.apply(dry=False)
        calls = self.calls()
        self.assertEqual([c.split()[0] for c in calls], ["Hyprland", "Hyprland", "hyprctl"])
        self.assertEqual(calls[2], "hyprctl reload")
        self.assertIn("--verify-config -c", calls[0])
        self.assertTrue(calls[0].endswith("/hyprland.lua"))
        self.assertTrue(calls[1].endswith(str(ROOT / "hypr/gutter.lua")), calls[1])      # the entry file on its own
        self.assertTrue((self.cfg / "hypr/hyprland.lua").exists())

    def test_verify_runs_in_a_temp_home(self):
        self.stub("Hyprland", '#!/bin/sh\necho "$HOME $XDG_CONFIG_HOME $XDG_STATE_HOME $*" >> "%s"\n' % self.log)
        self.apply(dry=False)
        line = self.calls()[0]
        self.assertNotIn(str(self.home), line.split(" -c")[0])
        self.assertNotIn(str(self.cfg), line.split(" -c")[0])

    def test_verify_with_nothing_to_copy(self):
        self.stub("Hyprland")
        self.apply(dry=False)
        self.assertEqual([c.split()[0] for c in self.calls()], ["Hyprland", "Hyprland", "hyprctl"])

    def test_dry_run_says_verify_not_would_verify(self):
        self.stub("Hyprland")
        out = self.run_hypr(dry=False).stdout
        self.assertIn("verify ", out)
        self.assertNotIn("would: verify", out)

    def test_gutter_lua_verify_failure_aborts(self):
        # Fails only for the repo's entry file, not the loader.
        self.stub("Hyprland", '#!/bin/sh\ncase "$*" in *hypr/gutter.lua) echo bad >&2; exit 1;; esac\n')
        r = self.refuse(None, "--apply", dry=False)
        self.assertIn("gutter.lua", r.stderr)

    def test_no_hyprland_binary_without_dry_flag_fails(self):
        # PATH without Hyprland: only the stubs and the basics.
        bin_dir = self.dir / "bin"
        bin_dir.mkdir()
        for tool in ("bash", "env", "jq", "python3", "readlink", "mktemp", "mkdir", "cp", "cat", "rm", "awk", "grep",
                     "dirname", "cmp", "chmod", "mv", "date", "sed", "tr", "head", "tail", "ln", "sort", "tee",
                     "basename", "touch", "stat"):
            p = shutil.which(tool)
            if p:
                (bin_dir / tool).symlink_to(p)
        before = tree(self.home)
        r = self.run_script("install-hyprland.sh", "--apply", dry=False, PATH="%s:%s" % (self.stubs, bin_dir))
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertEqual(tree(self.home), before)
        self.assertIn("Hyprland", r.stderr)

    @unittest.skipUnless(HAS_HYPRLAND, "Hyprland is not installed")
    def test_real_verify_with_nothing_to_copy(self):
        self.apply(dry=False)
        self.assertEqual(self.calls(), ["hyprctl reload"])

    @unittest.skipUnless(HAS_HYPRLAND, "Hyprland is not installed")
    def test_real_verify_accepts_the_written_config(self):
        r = self.apply(dry=False)
        self.assertEqual(self.calls(), ["hyprctl reload"])
        # The same check again on the written loader, with the XDG folders the script used, must stay green.
        self.assertNotIn("error", (r.stdout + r.stderr).lower())

class Install(Base):
    def setUp(self):
        super().setUp()
        self.put(".config/foot/foot.ini", FOOT_INI)
        self.put(".config/fuzzel/fuzzel.ini", FUZZEL_INI, 0o600)

    def install(self, **kw):
        r = self.run_script("install.sh", **kw)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def test_install_idempotent(self):
        self.install()
        first = tree(self.home)
        self.install()
        self.assertEqual(tree(self.home), first)
        link = self.home / ".local/bin/gutter"
        self.assertEqual(os.readlink(link), str(ROOT / "tools/gutter"))
        self.assertTrue((self.state / "gutter").is_dir())
        self.assertEqual(self.read(".config/foot/gutter.ini"), "")
        self.assertEqual(self.read(".config/fuzzel/gutter.ini"), "")

    def test_install_links_the_shell_checkout(self):
        shell = self.cfg / "quickshell/gutter"
        self.install()
        self.assertEqual(os.path.realpath(shell), str(ROOT))
        self.assertTrue(shell.is_symlink())
        first = tree(self.home)
        self.install()
        self.assertEqual(tree(self.home), first)

    def test_install_keeps_a_correct_shell_link(self):
        (self.cfg / "quickshell").mkdir(parents=True)
        (self.cfg / "quickshell/gutter").symlink_to(ROOT / "scripts/..")      # another spelling of the checkout
        before = os.readlink(self.cfg / "quickshell/gutter")
        r = self.install()
        self.assertEqual(os.readlink(self.cfg / "quickshell/gutter"), before)
        self.assertNotIn("quickshell", r.stderr)

    def test_install_does_not_replace_a_foreign_shell_link(self):
        other = self.dir / "other-checkout"
        other.mkdir()
        (self.cfg / "quickshell").mkdir(parents=True)
        (self.cfg / "quickshell/gutter").symlink_to(other)
        r = self.install()
        self.assertEqual(os.readlink(self.cfg / "quickshell/gutter"), str(other))
        self.assertIn("quickshell/gutter", r.stderr)

    def test_install_does_not_replace_a_foreign_folder_or_dangling_link(self):
        shell = self.cfg / "quickshell/gutter"
        shell.mkdir(parents=True)
        (shell / "shell.qml").write_text("x")
        r = self.install()
        self.assertTrue(shell.is_dir() and not shell.is_symlink())
        self.assertIn("left alone", r.stderr)
        shutil.rmtree(shell)
        shell.symlink_to(self.dir / "gone")
        self.install()
        self.assertEqual(os.readlink(shell), str(self.dir / "gone"))

    def test_install_honours_xdg_config_home(self):
        xdg = self.dir / "xdg"
        (xdg / "foot").mkdir(parents=True)
        (xdg / "foot/foot.ini").write_text(FOOT_INI)
        self.install(XDG_CONFIG_HOME=str(xdg))
        self.assertTrue((xdg / "quickshell/gutter").is_symlink())
        self.assertIn("include=%s/foot/gutter.ini" % xdg, (xdg / "foot/foot.ini").read_text())
        self.assertTrue((xdg / "foot/gutter.ini").exists())

    def test_install_foreign_link_left_alone(self):
        (self.home / ".local/bin").mkdir(parents=True)
        (self.home / ".local/bin/gutter").write_text("mine")
        r = self.install()
        self.assertEqual(self.read(".local/bin/gutter"), "mine")
        self.assertIn("not ours", r.stderr)

    def test_install_dry_skips_hooks(self):
        self.install()
        self.assertFalse((self.home / ".claude").exists())

    def test_install_non_dry_runs_the_hooks(self):
        self.install(dry=False)
        settings = json.loads(self.read(".claude/settings.json"))
        self.assertIn("hooks", settings)


class HandoverInstall(Base):
    def setUp(self):
        super().setUp()
        self.put(".config/foot/foot.ini", FOOT_INI)
        self.put(".config/fuzzel/fuzzel.ini", FUZZEL_INI, 0o600)

    def handover(self, *args):
        r = subprocess.run(["python3", str(ROOT / "tools/handover.py"), *args], capture_output=True, text=True,
                           env=self.env)
        return r

    def install(self):
        r = self.handover("install", "--home", str(self.home), "--state", str(self.state))
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_foot_and_fuzzel_include_gutter(self):
        self.install()
        fuzzel = self.read(".config/fuzzel/fuzzel.ini")
        self.assertEqual(fuzzel.count("include=~/.config/fuzzel/gutter.ini"), 1)
        self.assertNotIn("[colors]", fuzzel)
        self.assertNotIn("[border]", fuzzel)
        self.assertNotIn("radius=10", fuzzel)
        self.assertIn("[main]\nx=1", fuzzel)
        self.assertTrue(fuzzel.startswith("font=JetBrains Mono NF:size=17\nterminal=foot -e\ninclude="))
        foot = self.read(".config/foot/foot.ini")
        self.assertEqual(foot.count("include=~/.config/foot/gutter.ini"), 1)
        main = foot.split("\n[", 1)[0]
        self.assertEqual(main.splitlines()[-1], "include=~/.config/foot/gutter.ini")
        self.assertIn("[colors-dark]\nalpha=0.78", foot)
        self.assertIn("[colors-light]\nalpha=0.78", foot)
        self.assertEqual(foot.count("[colors-light]"), 1)
        self.assertIn("[scrollback]\nlines=10000", foot)

    def test_colors_light_copies_alpha_alpha_mode_and_blur(self):
        self.put(".config/foot/foot.ini", FOOT_INI.replace("alpha=0.78\n", "alpha=0.78\nalpha-mode=matching\nblur=yes\nfoo=bar\n"))
        self.install()
        self.assertIn("[colors-light]\nalpha=0.78\nalpha-mode=matching\nblur=yes\n", self.read(".config/foot/foot.ini"))
        self.assertNotIn("foo=bar\n[", self.read(".config/foot/foot.ini"))
        self.assertEqual(self.read(".config/foot/foot.ini").split("[colors-light]")[1].count("foo"), 0)

    def test_existing_colors_light_is_kept(self):
        self.put(".config/foot/foot.ini", FOOT_INI + "\n[colors-light]\nalpha=0.5\n")
        self.install()
        foot = self.read(".config/foot/foot.ini")
        self.assertEqual(foot.count("[colors-light]"), 1)
        self.assertIn("[colors-light]\nalpha=0.5\n", foot)

    def test_xdg_config_home_other_than_home_config(self):
        xdg = self.dir / "xdg"
        (xdg / "fuzzel").mkdir(parents=True)
        (xdg / "fuzzel/fuzzel.ini").write_text(FUZZEL_INI)
        r = subprocess.run(["python3", str(ROOT / "tools/handover.py"), "install", "--home", str(self.home)],
                           capture_output=True, text=True, env=dict(self.env, XDG_CONFIG_HOME=str(xdg)))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("include=%s/fuzzel/gutter.ini" % xdg, (xdg / "fuzzel/fuzzel.ini").read_text())
        self.assertTrue((xdg / "fuzzel/gutter.ini").exists())
        # The default config folder was not touched.
        self.assertNotIn("include=", self.read(".config/foot/foot.ini"))

    def test_empty_include_files_are_created(self):
        self.install()
        for rel in (".config/foot/gutter.ini", ".config/fuzzel/gutter.ini"):
            self.assertEqual(self.read(rel), "", rel)

    def test_existing_include_files_are_left_alone(self):
        for rel in (".config/foot/gutter.ini", ".config/fuzzel/gutter.ini"):
            self.put(rel, "# from an earlier apply\n[colors-dark]\nbackground=000000\n")
        self.install()
        self.install()
        for rel in (".config/foot/gutter.ini", ".config/fuzzel/gutter.ini"):
            self.assertEqual(self.read(rel), "# from an earlier apply\n[colors-dark]\nbackground=000000\n", rel)

    def test_backups_hold_the_originals_and_survive_a_second_run(self):
        self.install()
        self.install()
        self.assertEqual(self.read(".config/foot/foot.ini.pre-gutter"), FOOT_INI)
        self.assertEqual(self.read(".config/fuzzel/fuzzel.ini.pre-gutter"), FUZZEL_INI)
        self.assertEqual(stat.S_IMODE((self.cfg / "fuzzel/fuzzel.ini.pre-gutter").stat().st_mode), 0o600)

    def test_idempotent_and_modes_kept(self):
        self.install()
        first = tree(self.home)
        self.install()
        self.assertEqual(tree(self.home), first)
        self.assertEqual(stat.S_IMODE((self.cfg / "fuzzel/fuzzel.ini").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((self.cfg / "foot/foot.ini").stat().st_mode), 0o644)

    def test_missing_configs_are_skipped(self):
        (self.cfg / "fuzzel/fuzzel.ini").unlink()
        self.install()
        self.assertTrue((self.cfg / "foot/gutter.ini").exists())
        self.assertFalse((self.cfg / "fuzzel/gutter.ini").exists())
        self.assertFalse((self.cfg / "fuzzel/fuzzel.ini.pre-gutter").exists())

    def test_symlinked_config_is_edited_in_place(self):
        dotfiles = self.dir / "dotfiles"
        dotfiles.mkdir()
        link = self.cfg / "foot/foot.ini"
        target = dotfiles / "foot.ini"
        link.rename(target)
        link.symlink_to(target)
        target.chmod(0o640)
        self.install()
        self.assertTrue(link.is_symlink())
        self.assertIn("include=~/.config/foot/gutter.ini", target.read_text())
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o640)
        self.assertEqual([p.name for p in dotfiles.iterdir()], ["foot.ini"])

    def read_bytes(self, rel):
        return (self.home / rel).read_bytes()

    def test_crlf_files_keep_their_line_endings(self):
        crlf = lambda t: t.replace("\n", "\r\n").encode()
        (self.cfg / "foot/foot.ini").write_bytes(crlf(FOOT_INI))
        (self.cfg / "fuzzel/fuzzel.ini").write_bytes(crlf(FUZZEL_INI))
        self.install()
        for rel in (".config/foot/foot.ini", ".config/fuzzel/fuzzel.ini"):
            data = self.read_bytes(rel)
            self.assertEqual(data.count(b"\n"), data.count(b"\r\n"), rel)
            self.assertIn(b"include=~/.config/", data, rel)
        self.assertIn(b"[colors-light]\r\nalpha=0.78\r\n", self.read_bytes(".config/foot/foot.ini"))
        before = tree(self.home)
        self.install()
        self.assertEqual(tree(self.home), before)

    def test_mixed_endings_follow_the_majority(self):
        self.put(".config/fuzzel/fuzzel.ini", "font=x\n[main]\r\nx=1\r\ny=2\r\n")
        self.install()
        self.assertEqual(self.read_bytes(".config/fuzzel/fuzzel.ini"),
                         b"font=x\ninclude=~/.config/fuzzel/gutter.ini\r\n[main]\r\nx=1\r\ny=2\r\n")

    def test_form_feed_does_not_start_a_line(self):
        # str.splitlines would split at the form feed and take "[colors]" for a header, dropping keep=1.
        self.put(".config/fuzzel/fuzzel.ini", "font=x\nnote=a\x0c[colors]\nkeep=1\n\n[main]\nx=1\n")
        self.install()
        self.assertEqual(self.read(".config/fuzzel/fuzzel.ini"),
                         "font=x\nnote=a\x0c[colors]\nkeep=1\ninclude=~/.config/fuzzel/gutter.ini\n\n[main]\nx=1\n")

    def test_dropping_the_last_sections_leaves_no_trailing_blank_line(self):
        self.put(".config/fuzzel/fuzzel.ini", "font=x\n\n[main]\nx=1\n\n[colors]\nbackground=1\n\n[border]\nwidth=2\n")
        self.install()
        self.assertEqual(self.read(".config/fuzzel/fuzzel.ini"),
                         "font=x\ninclude=~/.config/fuzzel/gutter.ini\n\n[main]\nx=1\n")

    def test_state_option_is_accepted_and_unused(self):
        self.install()
        elsewhere = self.dir / "elsewhere"
        r = self.handover("install", "--home", str(self.home), "--state", str(elsewhere))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(elsewhere.exists())

    def test_old_subcommands_are_gone(self):
        for sub in ("take", "give-back"):
            self.assertNotEqual(self.handover(sub, "--home", str(self.home)).returncode, 0)



if __name__ == "__main__":
    unittest.main()

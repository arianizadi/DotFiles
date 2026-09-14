"""Isolated behavior tests; no compositor, desktop, clipboard or service is touched.

Mocks establish our argument handling, rollback and privacy defaults. They do not
validate the real Hyprland parser, VMware rendering or systemd session lifecycle.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "config/arian-hypr/scripts"
SHIM = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["TEST_LOG"], "a") as output:
    output.write(json.dumps([name, *args]) + "\n")
if name == "mv":
    os.replace(args[-2], args[-1])
elif name == "hyprctl":
    if "version" in args:
        print(json.dumps({"tag": os.environ.get("TEST_VERSION", "v0.56.2")}))
    elif "systeminfo" in args:
        if os.environ.get("TEST_PROVIDER"):
            print("configProvider: " + os.environ["TEST_PROVIDER"])
    elif "activeworkspace" in args:
        print(json.dumps({"id": int(os.environ.get("TEST_ACTIVE_WORKSPACE", "1"))}))
    elif "configerrors" in args:
        theme = os.readlink(pathlib.Path(os.environ["TEST_BUNDLE"]) / "current")
        print(json.dumps(["bad configuration"] if theme == "themes/" + os.environ.get("TEST_BAD_THEME", "") else []))
elif name == "systemctl" and "is-active" in args:
    sys.exit(1)
elif name == "slurp":
    sys.exit(1)
elif name == "fuzzel":
    path = pathlib.Path(os.environ["TEST_CHOICES"])
    choices = json.loads(path.read_text())
    sys.stdin.read()
    if not choices:
        sys.exit(1)
    print(choices.pop(0))
    path.write_text(json.dumps(choices))
elif name == "wl-copy":
    if "--clear" not in args:
        sys.stdin.buffer.read()
elif name == "uwsm":
    sys.exit(0 if os.environ.get("TEST_UWSM_ACTIVE") == "1" else 1)
'''


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hypr-runtime-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.bundle = self.root / "config with spaces/arian-hypr"
        shutil.copytree(SCRIPTS, self.bundle / "scripts")
        assets = "waybar.json waybar.css fuzzel.ini mako.conf kitty.conf hyprland.lua hyprland.conf hyprlock.conf wallpaper.png".split()
        for theme in ("frost", "haunt"):
            folder = self.bundle / "themes" / theme
            folder.mkdir(parents=True)
            for asset in assets:
                (folder / asset).write_text("test fixture\n")
            (folder / "palette.json").write_text(json.dumps({"workspace": ["1", "2", "3", "4", "5"] if theme == "frost" else ["🎃", "👻", "🦇", "🕸", "🌙"]}))
        (self.bundle / "current").symlink_to("themes/frost")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in "flock mv hyprctl systemctl systemd-run notify-send pkill waybar swaybg mako makoctl hypridle wl-paste cliphist wl-copy slurp fuzzel uwsm dbus-update-activation-environment".split():
            path = self.bin / name
            path.write_text(SHIM)
            path.chmod(0o755)
        self.log = self.root / "calls.jsonl"
        self.log.touch()
        self.choices = self.root / "choices.json"
        self.choices.write_text("[]")
        self.state = self.root / "state/arian-hypr"
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        HOME=str(self.root), XDG_STATE_HOME=str(self.root / "state"),
                        TEST_LOG=str(self.log), TEST_BUNDLE=str(self.bundle),
                        TEST_CHOICES=str(self.choices))
        self.env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        self.env.pop("WAYLAND_DISPLAY", None)

    def run_script(self, name, *args, live=False):
        env = dict(self.env)
        if live:
            env.update(WAYLAND_DISPLAY="wayland-test", HYPRLAND_INSTANCE_SIGNATURE="test-only")
        return subprocess.run(["bash", str(self.bundle / "scripts" / name), *args],
                              env=env, capture_output=True, text=True, timeout=15)

    def calls(self, executable=None):
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return [call for call in calls if executable is None or call[0] == executable]

    def test_offline_switch_is_relative_and_does_not_touch_services(self):
        result = self.run_script("theme.sh", "haunt")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(self.bundle / "current"), "themes/haunt")
        self.assertEqual(self.calls("systemctl"), [])
        self.assertEqual(self.run_script("theme.sh", "toggle").stdout.strip(), "frost")

    def test_theme_rejects_arbitrary_path_without_mutation(self):
        self.assertEqual(self.run_script("theme.sh", "../../other").returncode, 2)
        self.assertEqual(os.readlink(self.bundle / "current"), "themes/frost")

    def test_failed_live_reload_restores_previous_link(self):
        self.env["TEST_BAD_THEME"] = "haunt"
        result = self.run_script("theme.sh", "haunt", live=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Restored frost", result.stderr)
        self.assertEqual(os.readlink(self.bundle / "current"), "themes/frost")
        self.assertEqual(len([call for call in self.calls("hyprctl") if "reload" in call]), 2)
        self.assertEqual(self.calls("systemd-run"), [])

    def test_session_never_starts_clipboard_capture_by_default(self):
        result = self.run_script("session.sh", "start", live=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        units = [arg for call in self.calls("systemd-run") for arg in call if arg.startswith("--unit=")]
        self.assertIn("--unit=arian-hypr-waybar", units)
        self.assertNotIn("--unit=arian-hypr-clipboard", units)
        self.assertEqual(self.calls("pkill"), [])

    def test_opted_in_clipboard_uses_own_limited_database(self):
        self.state.mkdir(parents=True)
        (self.state / "clipboard-enabled").touch()
        result = self.run_script("session.sh", "start", live=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        call = next(call for call in self.calls("systemd-run") if "--unit=arian-hypr-clipboard" in call)
        self.assertIn(str(self.state / "clipboard.db"), call)
        self.assertIn("100", call)
        self.assertIn("text", call)

    def test_screenshot_cancel_does_not_create_files_or_clear_clipboard(self):
        result = self.run_script("actions.sh", "screenshot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "Pictures").exists())
        self.assertEqual(self.calls("wl-copy"), [])

    def test_arbitrary_menu_text_is_never_executed(self):
        self.choices.write_text(json.dumps(["touch " + str(self.root / "bad")]))
        result = self.run_script("actions.sh", "settings")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "bad").exists())

    def test_logout_uses_correct_dispatcher_for_both_config_generations(self):
        for version, dispatcher in (("v0.54.2", "exit"), ("v0.56.2", "hl.dsp.exit()")):
            with self.subTest(version=version):
                self.env["TEST_VERSION"] = version
                self.log.write_text("")
                self.choices.write_text(json.dumps(["Log out", "Log out and close open applications"]))
                result = self.run_script("actions.sh", "power", live=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(["hyprctl", "dispatch", dispatcher], self.calls("hyprctl"))

    def test_actual_config_provider_overrides_version_for_workspace_clicks(self):
        self.env["TEST_VERSION"] = "v0.56.2"
        self.env["TEST_PROVIDER"] = "hyprlang"
        result = self.run_script("actions.sh", "workspace", "3", live=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["hyprctl", "dispatch", "workspace", "3"], self.calls("hyprctl"))
        self.env["TEST_PROVIDER"] = "lua"
        result = self.run_script("actions.sh", "workspace", "5", live=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["hyprctl", "dispatch", "hl.dsp.focus({workspace=5})"], self.calls("hyprctl"))

    def test_workspace_rejects_code_and_out_of_range_values(self):
        for value in ("0", "10", "1}); bad()"):
            self.assertEqual(self.run_script("actions.sh", "workspace", value).returncode, 2)
        self.assertEqual(self.calls("hyprctl"), [])

    def test_workspace_status_tracks_current_theme_and_active_workspace(self):
        self.env["TEST_ACTIVE_WORKSPACE"] = "2"
        self.assertEqual(self.run_script("theme.sh", "haunt").returncode, 0)
        result = self.run_script("actions.sh", "workspace-status", "2", live=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"text": "👻", "class": "active", "tooltip": "Workspace 2"})
        result = self.run_script("actions.sh", "workspace-status", "3", live=True)
        self.assertEqual(json.loads(result.stdout)["class"], "inactive")

    def test_uwsm_terminal_launch_is_placed_in_managed_app_unit(self):
        self.env["TEST_UWSM_ACTIVE"] = "1"
        result = self.run_script("actions.sh", "terminal", "btop", live=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["uwsm", "app", "--", "kitty", "--config", str(self.bundle / "kitty/kitty.conf"), "btop"], self.calls("uwsm"))


if __name__ == "__main__":
    unittest.main()

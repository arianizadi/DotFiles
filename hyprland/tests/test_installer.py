#!/usr/bin/env python3
"""Exercise transactions in temporary homes; never install packages or touch a desktop.

The host tools uname/id/cat/pacman/Hyprland are stubbed. Real cp/mv exercise
directory and symlink preservation on Linux and macOS.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]
PROGRAMS = """uname id cat mv sudo pacman systemctl Hyprland waybar fuzzel mako kitty
swaybg hyprlock hypridle grim slurp wl-copy wl-paste notify-send jq playerctl
pavucontrol thunar cliphist btop firefox wpctl nmtui xdg-user-dir hyprctl makoctl
flock systemd-run vmtoolsd""".split()
STUB = r'''#!/bin/bash
case "${0##*/}" in
  uname) printf '%s\n' "${TEST_UNAME:-Linux}" ;;
  id) printf '%s\n' "${TEST_UID:-1000}" ;;
  cat)
    if [[ "$1" == /etc/os-release ]]; then
      printf 'ID=%s\n' "${TEST_DISTRO:-cachyos}"
    else
      exec /bin/cat "$@"
    fi ;;
  mv)
    [[ "$1" != -- ]] || shift
    if [[ "${TEST_FAIL_MOVE:-0}" == 1 && "$1" == *'/.arian-hypr-stage.'*'/next/arian-hypr' ]]; then exit 8; fi
    exec /bin/mv "$@" ;;
  Hyprland)
    printf 'Hyprland %s\n' "$*" >> "$TEST_LOG"
    case "$1" in
      --version) printf 'Hyprland %s built from branch main\n' "${TEST_VERSION:-0.55.0}" ;;
      --help) [[ "${TEST_NO_VALIDATOR:-0}" == 1 ]] || printf '%s\n' '--verify-config --config' ;;
      --verify-config)
        [[ -f "$3" ]] || exit 5
        [[ "${TEST_FAIL_VERIFY:-0}" != 1 ]] || exit 6 ;;
    esac ;;
  sudo)
    printf 'sudo %s\n' "$*" >> "$TEST_LOG"
    exec "$@" ;;
  pacman)
    printf 'pacman %s\n' "$*" >> "$TEST_LOG"
    [[ "${TEST_FAIL_PACMAN:-0}" != 1 ]] || exit 7 ;;
  systemctl)
    printf 'systemctl %s\n' "$*" >> "$TEST_LOG"
    if [[ "$1" == cat && "${TEST_NO_VGAUTH:-0}" == 1 ]]; then exit 1; fi ;;
esac
'''


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="arian-hypr-test-")
        self.root = Path(self.temp.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.repo = self.root / "checkout with spaces" / "hyprland"
        self.repo.mkdir(parents=True)
        for name in ("install.sh", "restore.sh"):
            shutil.copy2(SOURCE / name, self.repo / name)
        config = self.repo / "config"
        (config / "hypr").mkdir(parents=True)
        for name in ("hyprland.conf", "hyprland.lua"):
            (config / "hypr" / name).write_text("fixture compositor entry\n")
        for name in ("frost", "haunt"):
            (config / "arian-hypr" / "themes" / name).mkdir(parents=True)
        (config / "arian-hypr" / "current").symlink_to("themes/frost")
        (config / "arian-hypr" / "bundle.txt").write_text("new bundle\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in PROGRAMS:
            program = self.bin / name
            program.write_text(STUB)
            program.chmod(0o755)
        self.log = self.root / "commands.log"
        self.env = os.environ.copy()
        for name in ("XDG_CONFIG_HOME", "XDG_STATE_HOME"):
            self.env.pop(name, None)
        self.env.update(HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin", TEST_LOG=str(self.log))
        self.config = self.home / ".config"
        self.backups = self.home / ".local/state/arian-hypr/backups"

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, *args, restore=False, success=True, **env):
        result = subprocess.run(
            ["/bin/bash", str(self.repo / ("restore.sh" if restore else "install.sh")), *map(str, args)],
            env={**self.env, **env}, capture_output=True, text=True, timeout=15,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def backup_dirs(self):
        return set(self.backups.iterdir()) if self.backups.exists() else set()

    def command_log(self):
        return self.log.read_text() if self.log.exists() else ""

    def install(self, **env):
        previous = self.backup_dirs()
        self.run_script("--skip-packages", **env)
        created = self.backup_dirs() - previous
        self.assertEqual(len(created), 1)
        return created.pop()

    def test_dry_run_is_read_only_on_mac(self):
        result = self.run_script("--dry-run", "--vmware", TEST_UNAME="Darwin")
        self.assertIn("sudo pacman -Syu --needed", result.stdout)
        self.assertFalse(self.config.exists())
        self.assertFalse(self.backups.exists())
        self.assertEqual(self.command_log(), "")

    def test_rejects_host_root_wrong_distro_and_nonstandard_config(self):
        for env in ({"TEST_UNAME": "Darwin"}, {"TEST_UID": "0"}, {"TEST_DISTRO": "ubuntu"},
                    {"XDG_CONFIG_HOME": str(self.home / "other")}):
            with self.subTest(env=env):
                self.run_script("--skip-packages", success=False, **env)
                self.assertFalse(self.config.exists())
                self.assertFalse(self.backups.exists())

    def test_fresh_install_and_undo_remove_only_recorded_paths(self):
        backup = self.install()
        (self.config / "unrelated").mkdir()
        (self.config / "unrelated/keep").write_text("unrelated user data")
        self.assertEqual((self.config / "arian-hypr/current").readlink(), Path("themes/frost"))
        self.assertIn("--config " + str(self.config / "hypr/hyprland.lua"), self.command_log())
        self.run_script(backup, restore=True)
        for name in ("hypr", "arian-hypr", "arian-hypr-local"):
            self.assertFalse((self.config / name).exists())
        self.assertEqual((self.config / "unrelated/keep").read_text(), "unrelated user data")
        self.assertEqual(len(self.backup_dirs()), 2)

    def test_repeat_install_preserves_theme_and_overrides_and_saves_edits(self):
        self.install()
        current = self.config / "arian-hypr/current"
        current.unlink()
        current.symlink_to("themes/haunt")
        override = self.config / "arian-hypr-local/local.lua"
        override.write_text("personal settings\n")
        (self.config / "hypr/user-added.txt").write_text("old config edit\n")
        backup = self.install()
        self.assertEqual(current.readlink(), Path("themes/haunt"))
        self.assertEqual(override.read_text(), "personal settings\n")
        self.assertEqual((backup / "items/hypr/user-added.txt").read_text(), "old config edit\n")
        self.assertFalse((self.config / "hypr/user-added.txt").exists())

    def test_restore_preserves_previous_symlink_and_backups_new_edits(self):
        external = self.home / "original hypr"
        external.mkdir()
        (external / "config").write_text("original\n")
        self.config.mkdir()
        (self.config / "hypr").symlink_to(external, target_is_directory=True)
        backup = self.install()
        (self.config / "hypr/new-user-edit").write_text("keep my later work\n")
        previous = self.backup_dirs()
        self.run_script(backup, restore=True)
        recovery = (self.backup_dirs() - previous).pop()
        self.assertTrue((self.config / "hypr").is_symlink())
        self.assertEqual((external / "config").read_text(), "original\n")
        self.assertEqual((recovery / "items/hypr/new-user-edit").read_text(), "keep my later work\n")
        self.run_script(recovery, restore=True)
        self.assertEqual((self.config / "hypr/new-user-edit").read_text(), "keep my later work\n")

    def test_restore_dry_run_is_read_only(self):
        backup = self.install()
        previous = self.backup_dirs()
        contents = (self.config / "hypr/hyprland.lua").read_bytes()
        log = self.command_log()
        self.run_script("--dry-run", backup, restore=True, TEST_UNAME="Darwin")
        self.assertEqual(self.backup_dirs(), previous)
        self.assertEqual((self.config / "hypr/hyprland.lua").read_bytes(), contents)
        self.assertEqual(self.command_log(), log)

    def test_bad_manifest_rejected_without_config_mutation(self):
        backup = self.install()
        manifest = backup / "manifest.tsv"
        original = manifest.read_text()
        for bad in (original.replace("\thypr\n", "\t../../outside\n"),
                    original + "present\thypr\n", original.splitlines()[0] + "\n",
                    original.replace("absent\thypr", "present\thypr")):
            with self.subTest(manifest=bad):
                manifest.write_text(bad)
                previous = self.backup_dirs()
                self.run_script(backup, restore=True, success=False)
                self.assertEqual(self.backup_dirs(), previous)
                self.assertTrue((self.config / "hypr/hyprland.lua").exists())

    def test_refuses_backup_outside_backup_root(self):
        backup = self.install()
        outside = self.root / "outside-backup"
        shutil.copytree(backup, outside, symlinks=True)
        self.run_script(outside, restore=True, success=False)
        self.assertEqual(len(self.backup_dirs()), 1)

    def test_validator_failure_rolls_back_existing_config(self):
        (self.config / "hypr").mkdir(parents=True)
        (self.config / "hypr/original").write_text("restore me\n")
        self.run_script("--skip-packages", TEST_FAIL_VERIFY="1", success=False)
        self.assertEqual((self.config / "hypr/original").read_text(), "restore me\n")
        self.assertFalse((self.config / "arian-hypr").exists())
        self.assertFalse((self.config / "arian-hypr-local").exists())
        self.assertEqual(len(self.backup_dirs()), 1)
        self.assertFalse(list(self.config.glob(".arian-hypr-stage.*")))

    def test_validator_failure_rolls_back_fresh_install(self):
        self.run_script("--skip-packages", TEST_FAIL_VERIFY="1", success=False)
        self.assertEqual(list(self.config.iterdir()), [])

    def test_mid_activation_failure_restores_all_existing_directories(self):
        for name in ("hypr", "arian-hypr", "arian-hypr-local"):
            (self.config / name).mkdir(parents=True)
            (self.config / name / "original").write_text(f"original {name}\n")
        self.run_script("--skip-packages", TEST_FAIL_MOVE="1", success=False)
        for name in ("hypr", "arian-hypr", "arian-hypr-local"):
            self.assertEqual((self.config / name / "original").read_text(), f"original {name}\n")
            self.assertEqual([p.name for p in (self.config / name).iterdir()], ["original"])
        self.assertFalse(list(self.config.glob(".arian-hypr-stage.*")))

    def test_legacy_version_and_missing_validator(self):
        result = self.run_script("--skip-packages", TEST_VERSION="0.54.3", TEST_NO_VALIDATOR="1")
        self.assertIn("hyprland.conf", result.stdout)
        self.assertIn("no --verify-config", result.stdout)
        self.assertNotIn("Hyprland --verify-config", self.command_log())

    def test_old_version_or_missing_program_prevents_mutation(self):
        self.run_script("--skip-packages", TEST_VERSION="0.53.0", success=False)
        self.assertFalse(self.config.exists())
        (self.bin / "fuzzel").unlink()
        self.run_script("--skip-packages", success=False)
        self.assertFalse(self.config.exists())

    def test_package_failure_prevents_config_changes(self):
        self.run_script(TEST_FAIL_PACMAN="1", success=False)
        self.assertFalse(self.config.exists())
        self.assertIn("pacman -Syu --needed", self.command_log())

    def test_vmware_packages_and_services(self):
        self.run_script("--vmware")
        log = self.command_log()
        self.assertIn("open-vm-tools gtkmm3", log)
        self.assertIn("systemctl enable --now vmtoolsd.service", log)
        self.assertIn("systemctl enable --now vgauthd.service", log)
        self.assertLess(log.index("Hyprland --verify-config"), log.index("systemctl enable"))

    def test_custom_state_directory(self):
        state = self.home / "state elsewhere"
        self.run_script("--skip-packages", XDG_STATE_HOME=str(state))
        backup = next((state / "arian-hypr/backups").iterdir())
        self.run_script(backup, restore=True, XDG_STATE_HOME=str(state))
        self.assertFalse((self.config / "hypr").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)

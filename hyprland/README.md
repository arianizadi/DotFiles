# Frost / Haunt

Two coordinated Hyprland themes for CachyOS in VMware: icy graphite and blue, or Halloween orange/purple/black with emoji workspaces. Includes Waybar, Fuzzel, Kitty, Mako, lock screen, and matching wallpapers.

## Install

Run inside the VM as your normal user:

```bash
curl -fsSL https://raw.githubusercontent.com/arianizadi/DotFiles/main/hyprland/bootstrap.sh | bash
```

Then log out and select **Hyprland (UWSM)** if available. The installer updates packages, enables VMware tools, backs up existing configuration, and validates the installed Hyprland config when supported. Hyprland 0.54 and Lua-based 0.55+ are supported. Your C/C++, tmux, and shell configs are separate.

Run the same command to update. The checkout is kept at `~/.local/share/arian-hypr-dotfiles`. Existing theme selection and personal overrides survive reinstall. Native Wayland host/guest clipboard integration depends on VMware; guest clipboard history is optional and starts off.

## Shortcuts

| Key | Action |
| --- | --- |
| Super + Shift + T | Switch Frost / Haunt |
| Super + Enter | Terminal |
| Super + Space | Apps |
| Super + W / E | Browser / files |
| Super + Q / F | Close / fullscreen |
| Super + 1–9 | Workspace |
| Super + Shift + 1–9 | Move window to workspace |
| Super + arrows | Focus window |
| Super + Shift + arrows | Move window |
| Super + Alt + Space | Float window |
| Super + comma | Controls, audio, network, clipboard settings |
| Super + V | Clipboard history |
| Super + Ctrl + V | Clear guest clipboard/history |
| Super + Shift + S | Screenshot area |
| Super + L | Lock |
| Super + Escape | Session menu |
| Super + / | All shortcuts |

The top bar shows five workspaces; workspaces 6–9 remain available by keyboard. Blur is off and animations are short for VMware. Idle locks after ten minutes; it does not automatically suspend the VM.

## Customize

Personal overrides: `~/.config/arian-hypr-local/local.lua` (0.55+) or `local.conf` (0.54). These load last and are preserved on update. For monitor names and modes, run `hyprctl monitors`.

Repository files: `config/hypr/` for bindings and behavior; `config/arian-hypr/themes/{frost,haunt}/` for app styling and wallpapers. `tools/build_themes.py` holds palettes and regenerates the themed text files. Reinstall after editing repository files; installed configs are copies.

## Restore / diagnose

The installer prints the exact backup path. Restore it with:

```bash
bash ~/.local/share/arian-hypr-dotfiles/hyprland/restore.sh "/full/backup/path"
```

Then log out and back in. Restore backs up your current configuration too; it does not remove installed packages. If the desktop fails, use Ctrl + Alt + F3 to log into a console and run restore.

```bash
bash ~/.config/arian-hypr/scripts/doctor.sh
```

Local tests cover installer transactions and runtime commands with mock Linux tools. CI checks current Hyprland Lua and Fuzzel syntax using native Arch binaries. Actual display, sound, lock/unlock, and VMware behavior still need checking in your guest.

[Upstream references](docs/SOURCES.md) · [Wallpaper provenance](docs/WALLPAPERS.md)

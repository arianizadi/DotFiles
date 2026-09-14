# Sources and compatibility

Researched against upstream documentation and code on 2026-09-14. Configuration and artwork in this folder were created for this repository; upstream examples informed API usage, not a copied desktop theme.

- [CachyOS Hyprland setup](https://wiki.cachyos.org/configuration/desktop_environments/hyprland/) — current CachyOS uses Lua-based Hyprland configuration and Noctalia defaults. Replacing the compositor entry means this bundle starts its own components on the next session.
- [Hyprland configuration entry point](https://wiki.hypr.land/Configuring/Start/) — the Lua transition begins at 0.55. Both formats are included; the installer requires 0.54 or newer.
- [Official Lua example](https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua) — monitor, input, bindings, animations, startup API.
- [Hyprland Lua gradient parser](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/lua/types/LuaConfigGradient.cpp) — multicolor gradients use a colors table and angle, unlike the old string syntax.
- [Hyprland CLI](https://github.com/hyprwm/Hyprland/blob/main/src/main.cpp) — native `--verify-config` validation when available.
- [Waybar reference configuration](https://github.com/Alexays/Waybar/blob/master/resources/config.jsonc) and [manuals](https://github.com/Alexays/Waybar/tree/master/man) — modules and GTK CSS styling.
- [Fuzzel configuration manual](https://codeberg.org/dnkl/fuzzel/src/branch/master/doc/fuzzel.ini.5.scd) — launcher colors, font, spacing, and borders.
- [Mako configuration manual](https://github.com/emersion/mako/blob/master/doc/mako.5.scd) — notification behavior, dimensions, history, and do-not-disturb mode.
- [Kitty configuration](https://sw.kovidgoyal.net/kitty/conf/) — terminal palettes, include files, and appearance.
- [Hyprlock](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/) and [Hypridle](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/) — lock screen and idle behavior.
- [Swaybg](https://github.com/swaywm/swaybg) — simple wallpaper display; avoids the changing Hyprpaper configuration API.
- [Arch VMware guest setup](https://wiki.archlinux.org/title/VMware/Install_Arch_Linux_as_a_guest) — open-vm-tools and guest services.
- [Open VM Tools Wayland clipboard report](https://github.com/vmware/open-vm-tools/issues/792) — native Wayland clipboard integration is not assumed to work.

Modern Hyprland can change APIs between rolling releases. Prefer the installed native configuration checker and the repository's CI results to assumptions based on an older tutorial. Real VMware rendering, lock/unlock, sound, input mapping, and portal behavior must be verified in the user's guest after installation.

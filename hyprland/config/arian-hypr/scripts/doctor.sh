#!/usr/bin/env bash
# Read-only diagnostics: do not dump environment variables or clipboard entries.
set -uo pipefail
BUNDLE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/arian-hypr
failures=0
printf 'Arian Hyprland desktop diagnostics\n\n'
printf 'Theme: %s\n' "$(readlink "$BUNDLE/current" 2>/dev/null || printf 'missing')"
if [[ -f "$STATE/clipboard-enabled" ]]; then printf 'Clipboard history: enabled (contents hidden)\n'; else printf 'Clipboard history: disabled\n'; fi
printf '\nRequired programs\n'
for program in Hyprland hyprctl waybar swaybg kitty fuzzel mako makoctl hypridle hyprlock grim slurp wl-copy wl-paste cliphist jq flock systemctl systemd-run notify-send xdg-user-dir firefox thunar pavucontrol nmtui btop wpctl; do
    if command -v "$program" >/dev/null; then
        printf '  OK       %s\n' "$program"
    else
        printf '  MISSING  %s\n' "$program"
        failures=$((failures + 1))
    fi
done
printf '\nCompositor\n'
if command -v hyprctl >/dev/null && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl version || failures=$((failures + 1))
    printf '\nConfiguration errors (empty is good)\n'
    errors=$(hyprctl -j configerrors 2>&1)
    printf '%s\n' "$errors"
    if ! command -v jq >/dev/null || ! jq -e 'type == "array" and length == 0' <<<"$errors" >/dev/null 2>&1; then failures=$((failures + 1)); fi
    printf '\nGuest monitors and available modes\n'
    hyprctl monitors all || failures=$((failures + 1))
else
    printf 'No active Hyprland IPC environment. Run this in the VM desktop.\n'
fi
printf '\nManaged services\n'
if command -v systemctl >/dev/null; then
    systemctl --user --no-pager --plain list-units --all 'arian-hypr-*.service' 'hyprpolkitagent.service' || true
    printf '\nVMware guest tools\n'
    systemctl --no-pager --plain is-active vmtoolsd.service 2>/dev/null || true
fi
printf '\nVirtual graphics hardware\n'
if command -v lspci >/dev/null; then lspci | grep -Ei 'vga|3d|display' || true; else printf 'lspci unavailable (optional: pciutils).\n'; fi
printf '\nRenderer evidence\n'
if command -v glxinfo >/dev/null && [[ -n "${DISPLAY:-}" ]]; then
    glxinfo -B 2>/dev/null || true
    printf 'glxinfo measures the Xwayland GL path; it does not prove native Wayland performance.\n'
else
    printf 'glxinfo unavailable or no DISPLAY (optional: mesa-utils).\n'
fi
printf '\nMissing-program/configuration checks: %s issue(s).\n' "$failures"
printf 'Logs: journalctl --user -b -u arian-hypr-waybar -u arian-hypr-wallpaper -u arian-hypr-mako --no-pager\n'
(( failures == 0 ))

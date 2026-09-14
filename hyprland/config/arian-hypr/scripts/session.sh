#!/usr/bin/env bash
# Own only this desktop's services. Never kill another session's Waybar or mako.
set -euo pipefail
umask 077

BUNDLE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/arian-hypr
mkdir -p -- "$STATE"
command -v flock >/dev/null || { printf 'Missing flock (util-linux).\n' >&2; exit 1; }
exec 9>"$STATE/session.lock"
flock -x 9

warn() { printf 'arian-hypr: %s\n' "$*" >&2; }
active() { systemctl --user is-active --quiet "arian-hypr-$1.service"; }
stop_unit() {
    systemctl --user stop "arian-hypr-$1.service" 2>/dev/null || true
    systemctl --user reset-failed "arian-hypr-$1.service" 2>/dev/null || true
}
start_unit() {
    local name=$1 executable attempt
    shift
    executable=$(command -v "$1") || { warn "Missing $1; skipping $name."; return 1; }
    shift
    if active "$name"; then return 0; fi
    # --collect releases the unit name after a stop. Allow a short GC delay.
    for attempt in 1 2 3 4 5; do
        if systemd-run --user --quiet --collect --unit="arian-hypr-$name" \
            --service-type=exec --property=PartOf=graphical-session.target \
            --property=After=graphical-session.target \
            --property=Restart=on-failure --property=RestartSec=2s \
            -- "$executable" "$@"; then return 0; fi
        (( attempt == 5 )) || sleep 0.1
    done
    warn "Could not start $name. Run scripts/doctor.sh for diagnostics."
    return 1
}
clipboard_start() {
    [[ -f "$STATE/clipboard-enabled" ]] || return 0
    start_unit clipboard wl-paste --type text --watch \
        cliphist -db-path "$STATE/clipboard.db" -max-items 100 store
}
start_visuals() {
    start_unit waybar waybar --config "$BUNDLE/current/waybar.json" --style "$BUNDLE/current/waybar.css" || true
    start_unit wallpaper swaybg --image "$BUNDLE/current/wallpaper.png" --mode fill || true
}
import_environment() {
    [[ -n "${WAYLAND_DISPLAY:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || {
        warn 'Start this from inside the installed Hyprland session.'; return 1;
    }
    export XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-Hyprland}
    local name
    local -a names=()
    for name in WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_CONFIG_HOME XDG_STATE_HOME PATH; do
        [[ -v "$name" ]] && names+=("$name")
    done
    systemctl --user import-environment "${names[@]}"
    if command -v dbus-update-activation-environment >/dev/null; then
        dbus-update-activation-environment --systemd "${names[@]}" || warn 'Could not update D-Bus activation environment.'
    fi
}

case ${1:-start} in
    start)
        import_environment
        # A plain Hyprland session may leave services alive after logout;
        # restarting our own units here also replaces any old display socket.
        for unit in waybar wallpaper mako idle clipboard; do stop_unit "$unit"; done
        start_visuals
        start_unit mako mako --config "$BUNDLE/current/mako.conf" || true
        start_unit idle hypridle --config "$BUNDLE/hypridle.conf" || true
        clipboard_start || true
        systemctl --user start hyprpolkitagent.service || warn 'hyprpolkitagent did not start.'
        ;;
    refresh)
        import_environment
        stop_unit waybar
        stop_unit wallpaper
        start_visuals
        if active mako; then
            makoctl reload || { stop_unit mako; start_unit mako mako --config "$BUNDLE/current/mako.conf"; }
        else
            start_unit mako mako --config "$BUNDLE/current/mako.conf" || true
        fi
        ;;
    clipboard-start) import_environment; clipboard_start ;;
    clipboard-stop) stop_unit clipboard ;;
    stop)
        for unit in waybar wallpaper mako idle clipboard; do stop_unit "$unit"; done
        ;;
    *) printf 'Usage: %s {start|refresh|stop|clipboard-start|clipboard-stop}\n' "$0" >&2; exit 2 ;;
esac

#!/usr/bin/env bash
# Switch complete themes by atomically replacing one relative symlink.
set -euo pipefail
umask 077
BUNDLE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/arian-hypr

current() {
    case $(readlink "$BUNDLE/current" 2>/dev/null || true) in
        themes/frost) printf 'frost\n' ;;
        themes/haunt) printf 'haunt\n' ;;
        *) printf 'unknown\n' ;;
    esac
}
case ${1:-} in
    current) current; exit 0 ;;
    frost|haunt|toggle) ;;
    *) printf 'Usage: %s {frost|haunt|toggle|current}\n' "$0" >&2; exit 2 ;;
esac
mkdir -p -- "$STATE"
exec 9>"$STATE/theme.lock"
flock -x 9
previous=$(current)
theme=$1
if [[ $theme == toggle ]]; then
    if [[ $previous == frost ]]; then theme=haunt; else theme=frost; fi
fi
for asset in waybar.json waybar.css fuzzel.ini mako.conf kitty.conf hyprland.lua hyprland.conf hyprlock.conf wallpaper.png; do
    [[ -s "$BUNDLE/themes/$theme/$asset" ]] || { printf 'Missing theme asset: %s/%s\n' "$theme" "$asset" >&2; exit 1; }
done
if [[ -e "$BUNDLE/current" && ! -L "$BUNDLE/current" ]]; then
    printf 'Refusing to replace current: it must be a symlink.\n' >&2; exit 1
fi
tempdir=$(mktemp -d "$BUNDLE/.theme.XXXXXX")
trap 'rm -rf -- "$tempdir"' EXIT
activate() {
    ln -s -- "themes/$1" "$tempdir/current"
    # GNU mv -T replaces the link itself, including a link to a directory.
    mv -Tf -- "$tempdir/current" "$BUNDLE/current"
}
has_session=false
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    [[ $previous == frost || $previous == haunt ]] || { printf 'Select a theme before logging in; current has no known rollback target.\n' >&2; exit 1; }
    command -v jq >/dev/null || { printf 'Missing jq; cannot validate the running configuration.\n' >&2; exit 1; }
    # Check IPC before changing any files; a stale environment is not a session.
    hyprctl -j version >/dev/null
    has_session=true
fi
activate "$theme"
if $has_session; then
    errors=''
    if ! hyprctl reload >/dev/null || ! errors=$(hyprctl -j configerrors) || ! jq -e 'type == "array" and length == 0' <<<"$errors" >/dev/null; then
        printf 'Theme reload failed; configuration errors:\n%s\n' "$errors" >&2
        if [[ $previous == frost || $previous == haunt ]]; then
            activate "$previous"
            hyprctl reload >/dev/null || true
            printf 'Restored %s.\n' "$previous" >&2
        else
            # There was no known working theme to restore.
            printf 'No previous valid theme was available; run doctor.sh before continuing.\n' >&2
        fi
        exit 1
    fi
    "$BUNDLE/scripts/session.sh" refresh
    # Kitty documents SIGUSR1 as its configuration reload signal.
    # Restrict by this user and exact process name; terminals stay open.
    pkill -USR1 -u "$(id -u)" -x kitty 2>/dev/null || true
    if command -v notify-send >/dev/null; then
        case $theme in frost) title='❄ Frost';; haunt) title='🎃 Haunt';; esac
        notify-send --app-name='Arian desktop' "$title" 'Desktop theme applied.' || true
    fi
fi
printf '%s\n' "$theme"

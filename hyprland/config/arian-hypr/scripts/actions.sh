#!/usr/bin/env bash
# Menu selections are matched literally. Never execute text returned by fuzzel.
set -euo pipefail
umask 077
BUNDLE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/arian-hypr

notify() { command -v notify-send >/dev/null && notify-send --app-name='Arian desktop' "$@" || true; }
menu() { fuzzel --config "$BUNDLE/current/fuzzel.ini" --dmenu --prompt "$1"; }
uwsm_active() { command -v uwsm >/dev/null && uwsm check is-active >/dev/null 2>&1; }
launch() {
    if uwsm_active; then uwsm app -- "$@"; else "$@"; fi
}
terminal() { launch kitty --config "$BUNDLE/kitty/kitty.conf" "$@"; }
launcher() {
    local -a options=(--config "$BUNDLE/current/fuzzel.ini" --terminal="kitty --config \"$BUNDLE/kitty/kitty.conf\" -e")
    if uwsm_active; then options+=(--launch-prefix='uwsm app --'); fi
    exec fuzzel "${options[@]}"
}
config_provider() {
    local info version
    info=$(hyprctl systeminfo 2>/dev/null || true)
    # The IPC report describes the actual loaded provider, including -c overrides.
    if [[ $info =~ configProvider:[[:space:]]*lua ]]; then printf 'lua\n'; return; fi
    if [[ $info =~ configProvider:[[:space:]]*hyprlang ]]; then printf 'hyprlang\n'; return; fi
    # Older releases do not expose configProvider. The managed default changed
    # to Lua at 0.55; never guess if the version cannot be identified.
    version=$(hyprctl -j version | jq -r '.tag // .version // ""')
    [[ $version =~ ([0-9]+)\.([0-9]+) ]] || { printf 'Cannot identify Hyprland config provider.\n' >&2; return 1; }
    if (( BASH_REMATCH[1] > 0 || BASH_REMATCH[2] >= 55 )); then printf 'lua\n'; else printf 'hyprlang\n'; fi
}
workspace() {
    local number=${1:-} provider
    [[ $number =~ ^[1-9]$ ]] || { printf 'Workspace must be 1 through 9.\n' >&2; return 2; }
    provider=$(config_provider) || return 1
    if [[ $provider == lua ]]; then
        hyprctl dispatch "hl.dsp.focus({workspace=$number})"
    else
        hyprctl dispatch workspace "$number"
    fi
}
workspace_status() {
    local number=${1:-} active_id label class=inactive
    [[ $number =~ ^[1-9]$ ]] || { printf 'Workspace must be 1 through 9.\n' >&2; return 2; }
    active_id=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // 0') || active_id=0
    [[ $active_id == "$number" ]] && class=active
    label=$(jq -r --argjson index "$((number - 1))" '.workspace[$index] // empty' "$BUNDLE/current/palette.json" 2>/dev/null) || label=''
    [[ -n $label ]] || label=$number
    jq -cn --arg text "$label" --arg class "$class" --arg tooltip "Workspace $number" \
        '{text: $text, class: $class, tooltip: $tooltip}'
}
history() { cliphist -db-path "$STATE/clipboard.db" "$@"; }
confirm() {
    local choice
    choice=$(printf 'Cancel\n%s\n' "$1" | menu 'Confirm › ') || return 1
    [[ $choice == "$1" ]]
}
clipboard_enable() {
    confirm 'Enable history (stores copied text)' || return 0
    mkdir -p -- "$STATE"
    touch "$STATE/clipboard-enabled"
    if ! "$BUNDLE/scripts/session.sh" clipboard-start; then
        rm -f -- "$STATE/clipboard-enabled"
        notify 'Clipboard history could not start' 'Run doctor.sh to check the session.'
        return 1
    fi
    notify 'Clipboard history enabled' 'Up to 100 text entries are stored locally, including any secrets you copy.'
}
clipboard_clear() {
    "$BUNDLE/scripts/session.sh" clipboard-stop
    [[ ! -f "$STATE/clipboard.db" ]] || history wipe
    wl-copy --clear
    wl-copy --primary --clear 2>/dev/null || true
    if [[ -f "$STATE/clipboard-enabled" ]]; then "$BUNDLE/scripts/session.sh" clipboard-start; fi
    notify 'Clipboard cleared' 'History and the current guest clipboard are empty.'
}
clipboard_menu() {
    local choice
    if [[ ! -f "$STATE/clipboard-enabled" ]]; then
        choice=$(printf 'Enable history (stores copied text)\nClear saved history and clipboard\nCancel\n' | menu 'History is off › ') || return 0
        case $choice in
            'Enable history (stores copied text)') clipboard_enable ;;
            'Clear saved history and clipboard') clipboard_clear ;;
        esac
        return 0
    fi
    [[ -f "$STATE/clipboard.db" ]] || { notify 'Clipboard history is empty' 'Copy some text first.'; return 0; }
    choice=$(history list | menu 'Clipboard › ') || return 0
    [[ -n $choice ]] || return 0
    # Require a real history ID, then let cliphist decode the original bytes.
    [[ $choice =~ ^[0-9]+$'\t' ]] || return 0
    printf '%s\n' "$choice" | history decode | wl-copy
}
screenshot() {
    local mode=${1:-area} geometry='' pictures directory file
    case $mode in
        area) geometry=$(slurp) || return 0; [[ -n $geometry ]] || return 0 ;;
        full) ;;
        *) printf 'Screenshot mode must be area or full.\n' >&2; return 2 ;;
    esac
    pictures=$(xdg-user-dir PICTURES 2>/dev/null || true)
    [[ -n $pictures && $pictures == /* && $pictures != "$HOME" ]] || pictures="$HOME/Pictures"
    directory="$pictures/Screenshots"
    mkdir -p -- "$directory"
    file=$(mktemp --suffix=.png "$directory/Screenshot_$(date +%Y-%m-%d_%H-%M-%S)_XXXXXX")
    if [[ $mode == area ]]; then
        grim -g "$geometry" "$file" || { rm -f -- "$file"; return 1; }
    else
        grim "$file" || { rm -f -- "$file"; return 1; }
    fi
    [[ -s $file ]] || { rm -f -- "$file"; return 1; }
    if wl-copy --type image/png < "$file"; then
        notify 'Screenshot saved and copied' "$file"
    else
        notify 'Screenshot saved' "Clipboard unavailable. File: $file"
    fi
}
power_menu() {
    local choice provider
    local -a logout=()
    choice=$(printf 'Lock\nLog out\nReboot VM\nShut down VM\nCancel\n' | menu 'Session › ') || return 0
    case $choice in
        Lock) exec hyprlock --config "$BUNDLE/current/hyprlock.conf" ;;
        'Log out')
            confirm 'Log out and close open applications' || return 0
            if uwsm_active; then
                logout=(uwsm stop)
            else
                if ! provider=$(config_provider); then
                    notify 'Cannot identify Hyprland configuration' 'Run doctor.sh before logging out.'
                    return 1
                fi
                if [[ $provider == lua ]]; then
                    logout=(hyprctl dispatch 'hl.dsp.exit()')
                else
                    logout=(hyprctl dispatch exit)
                fi
            fi
            "$BUNDLE/scripts/session.sh" stop
            if ! "${logout[@]}"; then
                "$BUNDLE/scripts/session.sh" start
                return 1
            fi
            ;;
        'Reboot VM') confirm 'Reboot VM and close open applications' && systemctl reboot ;;
        'Shut down VM') confirm 'Shut down VM and close open applications' && systemctl poweroff ;;
    esac
}
settings_menu() {
    local choice clipboard='Enable clipboard history'
    [[ ! -f "$STATE/clipboard-enabled" ]] || clipboard='Disable clipboard history and clear'
    choice=$(printf '%s\n' '❄ Frost · dark ice' '🎃 Haunt · Halloween' 'Sound' 'Network' 'System monitor' 'Toggle do not disturb' "$clipboard" 'Clear clipboard' 'Keybindings' | menu 'Desktop › ') || return 0
    case $choice in
        '❄ Frost · dark ice') "$BUNDLE/scripts/theme.sh" frost ;;
        '🎃 Haunt · Halloween') "$BUNDLE/scripts/theme.sh" haunt ;;
        Sound) launch pavucontrol ;;
        Network) terminal nmtui ;;
        'System monitor') terminal btop ;;
        'Toggle do not disturb') makoctl mode -t do-not-disturb ;;
        'Enable clipboard history') clipboard_enable ;;
        'Disable clipboard history and clear') rm -f -- "$STATE/clipboard-enabled"; clipboard_clear ;;
        'Clear clipboard') clipboard_clear ;;
        Keybindings) show_help ;;
    esac
}
show_help() {
    printf '%s\n' \
        'Super + Enter    Terminal' \
        'Super + Space    App launcher' \
        'Super + E        Files' \
        'Super + W        Browser' \
        'Super + Q        Close window' \
        'Super + F        Fullscreen' \
        'Super + V        Clipboard history' \
        'Super + Ctrl + V    Clear clipboard' \
        'Super + comma    Desktop controls' \
        'Super + Shift + T    Switch theme' \
        'Super + L        Lock screen' \
        'Print / Super + Shift + S    Area screenshot' \
        'Super + slash    This shortcut guide' \
        'Super + Shift + R    Reload compositor' \
        'Super + arrows   Focus window' \
        'Super + Shift + arrows    Move window' \
        'Super + Alt + Space    Toggle floating' \
        'Super + J        Toggle split direction' \
        'Super + 1…9      Workspace' \
        'Super + Shift + 1…9    Move window' \
        'Super + Escape   Session menu' | menu 'Keybindings › ' >/dev/null || true
}

case ${1:-help} in
    launcher) launcher ;;
    terminal) shift; terminal "$@" ;;
    browser) launch firefox ;;
    files) launch thunar ;;
    network) terminal nmtui ;;
    workspace) workspace "${2:-}" ;;
    workspace-status) workspace_status "${2:-}" ;;
    lock) exec hyprlock --config "$BUNDLE/current/hyprlock.conf" ;;
    power) power_menu ;;
    screenshot) screenshot "${2:-area}" ;;
    clipboard) clipboard_menu ;;
    clear-clipboard) clipboard_clear ;;
    settings) settings_menu ;;
    help) show_help ;;
    *) printf 'Usage: %s {launcher|terminal|browser|files|network|workspace N|workspace-status N|lock|power|screenshot [area|full]|clipboard|clear-clipboard|settings|help}\n' "$0" >&2; exit 2 ;;
esac

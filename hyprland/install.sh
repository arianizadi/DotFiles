#!/usr/bin/env bash
# Copy a self-contained desktop into the current user's CachyOS/Arch account.
set -euo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
DRY_RUN=0
SKIP_PACKAGES=0
VMWARE=0
RESTORE_FROM=''
OPERATION=install
TARGETS=(hypr arian-hypr arian-hypr-local)
PACKAGES=(hyprland waybar fuzzel mako kitty swaybg hyprlock hypridle grim slurp
    wl-clipboard libnotify jq playerctl pavucontrol thunar gvfs hyprpolkitagent
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk ttf-jetbrains-mono-nerd
    noto-fonts noto-fonts-emoji papirus-icon-theme btop firefox cliphist
    wireplumber pipewire pipewire-pulse networkmanager xdg-user-dirs)
STAGE=''
BACKUP=''
TRANSACTION=0

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
exists() { [[ -e "$1" || -L "$1" ]]; }

usage() {
    cat <<'EOF'
Usage: bash hyprland/install.sh [--dry-run] [--vmware] [--skip-packages]

  --dry-run       Preview only; no writes, sudo, package changes, or services.
                 Safe to use on macOS to review the Linux installation plan.
  --vmware        Also install VMware guest tools and enable their system services.
  --skip-packages Copy settings only after checking required programs are installed.
  --help          Show this help.

Run without sudo as your normal user inside CachyOS/Arch Linux. The default
installs packages with sudo pacman -Syu --needed, then copies the configuration.
Existing configurations are backed up before replacement. No live session is
reloaded or restarted. Log out and select the Hyprland session when ready.

Restore: bash hyprland/restore.sh [--dry-run] BACKUP_DIRECTORY
EOF
}

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --vmware) VMWARE=1 ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --restore)
            OPERATION=restore
            shift
            while (($#)); do
                case "$1" in
                    --dry-run) DRY_RUN=1 ;;
                    --help|-h) say 'Usage: bash hyprland/restore.sh [--dry-run] BACKUP_DIRECTORY'; exit 0 ;;
                    --*) die "Unknown restore option: $1" ;;
                    *) [[ -z "$RESTORE_FROM" ]] || die 'Supply exactly one backup directory.'; RESTORE_FROM=$1 ;;
                esac
                shift
            done
            break ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1 (try --help)" ;;
    esac
    shift
done

[[ -n "${HOME:-}" && "$HOME" == /* && "$HOME" != / ]] || die 'HOME must be an absolute, non-root directory.'
[[ "$HOME" != *$'\n'* && "$HOME" != *$'\t'* ]] || die 'HOME cannot contain tabs or newlines.'
CONFIG_ROOT="$HOME/.config"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/arian-hypr"
BACKUP_ROOT="$STATE_ROOT/backups"
[[ "${XDG_CONFIG_HOME:-$CONFIG_ROOT}" == "$CONFIG_ROOT" ]] ||
    die "This bundle uses $CONFIG_ROOT. Unset XDG_CONFIG_HOME or set it to this directory before installing."
[[ "$STATE_ROOT" == /* && "$STATE_ROOT" != *$'\n'* && "$STATE_ROOT" != *$'\t'* ]] ||
    die 'XDG_STATE_HOME must be an absolute path without tabs or newlines.'

require_platform() {
    [[ "$(uname -s)" == Linux ]] || die 'Installation and restore run only inside the Linux VM. Use --dry-run on the host.'
    [[ "$(id -u)" != 0 ]] || die 'Run as your normal desktop user, without sudo. Package commands request sudo themselves.'
    local release key value distro='' like=''
    release=$(cat /etc/os-release 2>/dev/null || true)
    while IFS='=' read -r key value; do
        value=${value//\"/}
        case "$key" in ID) distro=$value ;; ID_LIKE) like=$value ;; esac
    done <<< "$release"
    [[ "$distro" == arch || "$distro" == cachyos || " $like " == *' arch '* ]] ||
        die 'This installer supports CachyOS/Arch Linux only.'
    command -v pacman >/dev/null || die 'pacman was not found.'
}

check_sources() {
    local name
    for name in hypr arian-hypr; do
        [[ -d "$SCRIPT_DIR/config/$name" ]] || die "Missing source directory: config/$name"
    done
    for name in hyprland.conf hyprland.lua; do
        [[ -f "$SCRIPT_DIR/config/hypr/$name" ]] || die "Missing compositor entry: $name"
    done
    for name in frost haunt; do
        [[ -d "$SCRIPT_DIR/config/arian-hypr/themes/$name" ]] || die "Missing theme: $name"
    done
    [[ -L "$SCRIPT_DIR/config/arian-hypr/current" ]] || die 'The bundle current theme link is missing.'
    [[ "$(readlink "$SCRIPT_DIR/config/arian-hypr/current")" == themes/frost ]] || die 'The bundle default theme must be themes/frost.'
}

check_programs() {
    local program missing=()
    for program in Hyprland waybar fuzzel mako kitty swaybg hyprlock hypridle grim slurp \
        wl-copy wl-paste notify-send jq playerctl pavucontrol thunar cliphist btop firefox \
        wpctl nmtui xdg-user-dir hyprctl makoctl flock systemctl systemd-run; do
        command -v "$program" >/dev/null || missing+=("$program")
    done
    if ((VMWARE)) && ! command -v vmtoolsd >/dev/null; then missing+=(vmtoolsd); fi
    ((${#missing[@]} == 0)) || die "Required programs are missing: ${missing[*]}. Run again without --skip-packages."
}

select_entry() {
    local version major minor
    version=$(Hyprland --version 2>&1) || die 'Could not read the installed Hyprland version.'
    if [[ "$version" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        major=${BASH_REMATCH[1]}
        minor=${BASH_REMATCH[2]}
    else
        die "Unrecognized Hyprland version output: $version"
    fi
    ((major > 0 || minor >= 54)) || die 'Hyprland 0.54 or newer is required. Update CachyOS first.'
    ENTRY=hyprland.conf
    if ((major > 0 || minor >= 55)); then ENTRY=hyprland.lua; fi
    say "Installed Hyprland: ${BASH_REMATCH[0]}; validating $ENTRY."
}

snapshot_current() {
    local name state
    mkdir -p -- "$BACKUP_ROOT"
    BACKUP=$(mktemp -d "$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-$OPERATION.XXXXXX")
    mkdir -- "$BACKUP/items"
    printf 'arian-hypr-backup-v1\n' > "$BACKUP/manifest.tmp"
    for name in "${TARGETS[@]}"; do
        state=absent
        if exists "$CONFIG_ROOT/$name"; then
            cp -a -- "$CONFIG_ROOT/$name" "$BACKUP/items/$name"
            state=present
        fi
        printf '%s\t%s\n' "$state" "$name" >> "$BACKUP/manifest.tmp"
    done
    mv -- "$BACKUP/manifest.tmp" "$BACKUP/manifest.tsv"
    say "Backup: $BACKUP"
}

# Only these three fixed destinations can ever be restored. A manifest is data,
# never shell code; reject unknown names, duplicate names, and incomplete copies.
validate_backup() {
    local resolved_root header state name extra index=0
    [[ -n "$RESTORE_FROM" ]] || die 'Supply the backup directory printed by the installer.'
    [[ -d "$BACKUP_ROOT" && ! -L "$RESTORE_FROM" ]] || die 'Backup must be a real directory inside your backup folder.'
    resolved_root=$(cd -- "$BACKUP_ROOT" && pwd -P)
    RESTORE_FROM=$(cd -- "$RESTORE_FROM" 2>/dev/null && pwd -P) || die 'Backup directory does not exist.'
    [[ "$RESTORE_FROM" == "$resolved_root/"* && "${RESTORE_FROM#"$resolved_root/"}" != */* ]] ||
        die "Backup must be directly inside $BACKUP_ROOT."
    [[ -f "$RESTORE_FROM/manifest.tsv" && ! -L "$RESTORE_FROM/manifest.tsv" &&
       -d "$RESTORE_FROM/items" && ! -L "$RESTORE_FROM/items" ]] || die 'Backup manifest or items directory is missing or unsafe.'
    {
        IFS= read -r header || die 'Empty backup manifest.'
        [[ "$header" == arian-hypr-backup-v1 ]] || die 'Unknown backup format.'
        while IFS=$'\t' read -r state name extra || [[ -n "$state$name$extra" ]]; do
            ((index < ${#TARGETS[@]})) || die 'Too many backup manifest records.'
            [[ "$name" == "${TARGETS[$index]}" && -z "$extra" ]] || die 'Invalid backup destination or record order.'
            case "$state" in
                present) exists "$RESTORE_FROM/items/$name" || die "Incomplete backup: $name is missing." ;;
                absent) ! exists "$RESTORE_FROM/items/$name" || die "Inconsistent backup: $name should be absent." ;;
                *) die 'Invalid backup state.' ;;
            esac
            index=$((index + 1))
        done
    } < "$RESTORE_FROM/manifest.tsv"
    ((index == ${#TARGETS[@]})) || die 'Incomplete backup manifest.'
}

prepare_install() {
    local name theme local_file
    for name in hypr arian-hypr; do
        cp -a -- "$SCRIPT_DIR/config/$name" "$STAGE/next/$name"
    done
    if [[ -L "$CONFIG_ROOT/arian-hypr/current" ]]; then
        theme=$(readlink "$CONFIG_ROOT/arian-hypr/current")
        case "$theme" in
            themes/frost|themes/haunt)
                rm -- "$STAGE/next/arian-hypr/current"
                ln -s -- "$theme" "$STAGE/next/arian-hypr/current"
                say "Keeping selected theme: ${theme#themes/}" ;;
        esac
    fi
    if exists "$CONFIG_ROOT/arian-hypr-local"; then
        [[ -d "$CONFIG_ROOT/arian-hypr-local" && ! -L "$CONFIG_ROOT/arian-hypr-local" ]] ||
            die "$CONFIG_ROOT/arian-hypr-local must be a real directory so local overrides can be preserved safely."
        cp -a -- "$CONFIG_ROOT/arian-hypr-local" "$STAGE/next/arian-hypr-local"
    else
        mkdir -- "$STAGE/next/arian-hypr-local"
    fi
    for local_file in local.conf local.lua; do
        if ! exists "$STAGE/next/arian-hypr-local/$local_file"; then
            if [[ "$local_file" == *.lua ]]; then
                say '-- Personal Hyprland overrides. This file is preserved on reinstall.' > "$STAGE/next/arian-hypr-local/$local_file"
            else
                say '# Personal Hyprland overrides. This file is preserved on reinstall.' > "$STAGE/next/arian-hypr-local/$local_file"
            fi
        fi
    done
}

rollback() {
    local name failed=0
    say 'Restoring the previous configuration after an unsuccessful activation.' >&2
    for name in "${TARGETS[@]}"; do
        # The displaced directory is the transaction record. Checking it avoids
        # a signal arriving between a successful rename and a shell assignment.
        # A previously present destination without a displaced copy is untouched.
        if ! exists "$STAGE/displaced/$name" && exists "$BACKUP/items/$name"; then
            continue
        fi
        if exists "$CONFIG_ROOT/$name"; then
            mv -- "$CONFIG_ROOT/$name" "$STAGE/failed/$name" || failed=1
        fi
        if exists "$STAGE/displaced/$name"; then
            mv -- "$STAGE/displaced/$name" "$CONFIG_ROOT/$name" || failed=1
        fi
    done
    if ((failed)); then
        say "Automatic rollback could not finish. Preserved recovery files at $STAGE and $BACKUP." >&2
        STAGE=''
    fi
}

cleanup() {
    local status=$?
    trap - EXIT
    if ((TRANSACTION)); then rollback; fi
    # STAGE comes only from mktemp under CONFIG_ROOT. Never delete destinations
    # from the backup manifest or recursively delete live configuration paths.
    if [[ -n "$STAGE" && "$STAGE" == "$CONFIG_ROOT/.arian-hypr-stage."* ]]; then
        rm -rf -- "$STAGE"
    fi
    exit "$status"
}

activate() {
    local name
    TRANSACTION=1
    for name in "${TARGETS[@]}"; do
        if exists "$CONFIG_ROOT/$name"; then
            mv -- "$CONFIG_ROOT/$name" "$STAGE/displaced/$name"
        fi
        if exists "$STAGE/next/$name"; then
            mv -- "$STAGE/next/$name" "$CONFIG_ROOT/$name"
        fi
    done
}

validate_installed() {
    local help_output
    help_output=$(Hyprland --help 2>&1 || true)
    if [[ "$help_output" == *--verify-config* ]]; then
        if ! Hyprland --verify-config --config "$CONFIG_ROOT/hypr/$ENTRY"; then
            die 'Hyprland rejected the configuration. The previous configuration will be restored; installed packages remain installed.'
        fi
        say 'Hyprland configuration validation passed.'
    else
        say 'This Hyprland build has no --verify-config option; syntax still needs checking in the VM session.'
    fi
}

if [[ "$OPERATION" == install ]]; then
    check_sources
    if ((VMWARE)); then PACKAGES+=(open-vm-tools gtkmm3); fi
else
    validate_backup
fi

if ((DRY_RUN)); then
    say "DRY RUN: $OPERATION; no files, packages, or services will change."
    say "Configuration: $CONFIG_ROOT"
    say "Backup destination: $BACKUP_ROOT/<timestamp>-$OPERATION.<unique-id>"
    if [[ "$OPERATION" == install ]]; then
        if ((SKIP_PACKAGES)); then
            say 'Check required installed programs and Hyprland >= 0.54; skip package changes.'
        else
            say "sudo pacman -Syu --needed ${PACKAGES[*]}"
        fi
        say 'Copy hypr and arian-hypr, preserving a selected Frost/Haunt theme and all local overrides.'
        say 'Validate the installed compositor entry when supported; roll back configuration if validation fails.'
        if ((VMWARE)); then say 'Enable installed VMware services: vmtoolsd.service and vgauthd.service (when provided).'; fi
    else
        say "Restore: $RESTORE_FROM"
        say 'Back up current configurations first, then restore exactly the three recorded configuration paths.'
    fi
    say 'No live Hyprland session will be reloaded or restarted.'
    exit 0
fi

require_platform
if [[ "$OPERATION" == install ]]; then
    if ((!SKIP_PACKAGES)); then
        command -v sudo >/dev/null || die 'sudo was not found.'
        sudo pacman -Syu --needed "${PACKAGES[@]}"
    fi
    check_programs
    select_entry
fi

mkdir -p -- "$CONFIG_ROOT"
STAGE=$(mktemp -d "$CONFIG_ROOT/.arian-hypr-stage.XXXXXX")
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -- "$STAGE/next" "$STAGE/displaced" "$STAGE/failed"
if [[ "$OPERATION" == install ]]; then
    prepare_install
else
    for name in "${TARGETS[@]}"; do
        if exists "$RESTORE_FROM/items/$name"; then
            cp -a -- "$RESTORE_FROM/items/$name" "$STAGE/next/$name"
        fi
    done
fi
snapshot_current
activate
if [[ "$OPERATION" == install ]]; then validate_installed; fi
TRANSACTION=0

if [[ "$OPERATION" == install ]] && ((VMWARE)); then
    command -v sudo >/dev/null || die 'Configuration installed, but sudo is missing; VMware services were not enabled.'
    sudo systemctl enable --now vmtoolsd.service
    if systemctl cat vgauthd.service >/dev/null 2>&1; then
        sudo systemctl enable --now vgauthd.service
    else
        say 'vgauthd.service is not included by this open-vm-tools package; vmtoolsd.service was enabled.'
    fi
fi

say "Configuration $OPERATION completed."
printf 'Undo this operation: bash %q %q\n' "$SCRIPT_DIR/restore.sh" "$BACKUP"
if [[ "$OPERATION" == install ]]; then
    say 'Log out, then select Hyprland (prefer the UWSM session if available). The current session was not reloaded.'
    say 'Keep personal settings in ~/.config/arian-hypr-local/local.conf (0.54) or local.lua (0.55+).'
fi

#!/usr/bin/env bash
# One-line entry point; keep a local checkout so updates and restore stay available.
set -euo pipefail

main() {
    [[ $(uname -s) == Linux && $(id -u) != 0 ]] || {
        printf 'Run this inside CachyOS as your normal user, without sudo.\n' >&2
        return 1
    }
    command -v pacman >/dev/null || { printf 'CachyOS/Arch Linux is required.\n' >&2; return 1; }
    if ! command -v git >/dev/null; then sudo pacman -Syu --needed git; fi
    local checkout="$HOME/.local/share/arian-hypr-dotfiles"
    local remote='https://github.com/arianizadi/DotFiles.git'
    if [[ -e $checkout || -L $checkout ]]; then
        [[ -d $checkout/.git && ! -L $checkout ]] || {
            printf 'Existing path is not the managed checkout: %s\n' "$checkout" >&2; return 1;
        }
        [[ $(git -C "$checkout" remote get-url origin) == "$remote" ]] || {
            printf 'Checkout origin does not match DotFiles.\n' >&2; return 1;
        }
        [[ -z $(git -C "$checkout" status --porcelain) ]] || {
            printf 'Your checkout has edits. Commit or save them before updating: %s\n' "$checkout" >&2; return 1;
        }
        git -C "$checkout" pull --ff-only origin main
    else
        mkdir -p -- "$(dirname -- "$checkout")"
        git clone --depth 1 --branch main "$remote" "$checkout"
    fi
    # Read package-manager prompts from the terminal, not the downloaded script pipe.
    bash "$checkout/hyprland/install.sh" --vmware "$@" < /dev/tty
}

main "$@"

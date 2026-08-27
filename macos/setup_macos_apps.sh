#!/usr/bin/env bash
###############################################################################
# Script: setup_macos_apps.sh
# Description: Install iTerm2 + Tiles on a fresh Mac and restore the settings
#              captured in macos/prefs/ (profile, colours, font, hotkeys).
#
#              Re-runnable: already-installed apps are left alone, prefs are
#              backed up before being overwritten.
#
# Usage:
#   ./macos/setup_macos_apps.sh
#   ./macos/setup_macos_apps.sh --apps-only     # install, don't touch prefs
#   ./macos/setup_macos_apps.sh --prefs-only    # restore prefs, don't install
#
# Note: must NOT be run from inside iTerm2 - restoring its prefs requires
#       quitting it, which would kill this script. Run from Terminal.app.
###############################################################################
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFS_DIR="${SCRIPT_DIR}/prefs"
BACKUP_DIR="${HOME}/Library/Preferences/pre-server-setup-backup"

DO_APPS=1
DO_PREFS=1
case "${1:-}" in
    --apps-only)  DO_PREFS=0 ;;
    --prefs-only) DO_APPS=0 ;;
    "")           ;;
    *) echo "Unknown option: $1"; exit 1 ;;
esac

# bundle : Homebrew cask : preference domain : process name
# The process name is not always the bundle name - iTerm.app runs as "iTerm2".
APPS=(
    "iTerm.app:iterm2:com.googlecode.iterm2:iTerm2"
    "Tiles.app:tiles:com.sempliva.Tiles:Tiles"
)
FONT_CASK="font-meslo-lg-nerd-font"   # MesloLGS NF - iTerm profile + p10k glyphs

###############################################################################
# Guard: restoring iTerm2 prefs means quitting iTerm2
###############################################################################
if [ "$DO_PREFS" -eq 1 ] && { [ "${TERM_PROGRAM:-}" = "iTerm.app" ] || [ -n "${ITERM_SESSION_ID:-}" ]; }; then
    echo "This is running inside iTerm2, which has to be quit to restore its"
    echo "preferences - iTerm2 rewrites its plist on exit and would clobber them."
    echo
    echo "Re-run from Terminal.app, or install only the apps for now:"
    echo "  ./macos/setup_macos_apps.sh --apps-only"
    exit 1
fi

###############################################################################
# 1) Install apps
###############################################################################
if [ "$DO_APPS" -eq 1 ]; then
    echo "==> [1/2] Installing apps..."

    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    for entry in "${APPS[@]}"; do
        IFS=: read -r app cask _domain _proc <<< "$entry"
        if [ -d "/Applications/${app}" ]; then
            echo "  ${app} already installed. Skipping."
        else
            brew install --cask "$cask"
        fi
    done

    if brew list --cask "$FONT_CASK" >/dev/null 2>&1; then
        echo "  ${FONT_CASK} already installed. Skipping."
    else
        brew install --cask "$FONT_CASK"
    fi
else
    echo "==> [1/2] Skipping app install (--prefs-only)."
fi

###############################################################################
# 2) Restore preferences
###############################################################################
if [ "$DO_PREFS" -eq 1 ]; then
    echo "==> [2/2] Restoring preferences..."
    mkdir -p "$BACKUP_DIR"
    STAMP="$(date +%Y%m%d%H%M%S)"

    for entry in "${APPS[@]}"; do
        IFS=: read -r app _cask domain proc <<< "$entry"
        src="${PREFS_DIR}/${domain}.plist"

        if [ ! -f "$src" ]; then
            echo "  skip  ${domain} (nothing exported in macos/prefs/)"
            continue
        fi

        # Quit first: both apps flush their in-memory prefs over ours on exit.
        if pgrep -qx "$proc" 2>/dev/null; then
            echo "  quitting ${app}..."
            osascript -e "tell application \"${proc}\" to quit" >/dev/null 2>&1 || true
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                pgrep -qx "$proc" 2>/dev/null || break
                sleep 1
            done
            pkill -x "$proc" 2>/dev/null || true
        fi

        # Back up whatever is there now before overwriting.
        if defaults export "$domain" - > "${BACKUP_DIR}/${domain}.${STAMP}.plist" 2>/dev/null; then
            echo "  backed up existing ${domain} -> ${BACKUP_DIR}/${domain}.${STAMP}.plist"
        else
            rm -f "${BACKUP_DIR}/${domain}.${STAMP}.plist"
        fi

        defaults import "$domain" "$src"
        echo "  restored ${domain}"
    done

    # Drop the prefs cache so the imported values are what the apps read.
    killall cfprefsd >/dev/null 2>&1 || true
else
    echo "==> [2/2] Skipping preference restore (--apps-only)."
fi

###############################################################################
# Summary
###############################################################################
cat <<EOF

============================================================
 macOS app setup complete.
============================================================
Restored from macos/prefs/:
  * iTerm2 - Default profile, Gruvbox Dark Hard preset, MesloLGS NF 13
  * Tiles  - window-management hotkeys, 4px padding, launch at login

Manual steps that cannot be scripted:
  1. Tiles needs Accessibility permission before its hotkeys work:
     System Settings > Privacy & Security > Accessibility > enable Tiles.
     Launch Tiles once and it will prompt.
  2. Launch iTerm2 and confirm the profile looks right. If the font renders
     as boxes, set it manually: Settings > Profiles > Text > MesloLGS NF.
  3. Tiles is paid software - sign in / enter the licence on first launch.

Backups of the previous prefs: ${BACKUP_DIR}
============================================================
EOF

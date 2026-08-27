#!/usr/bin/env bash
###############################################################################
# Script: export_macos_prefs.sh
# Description: Capture this Mac's iTerm2 + Tiles settings into macos/prefs/ so
#              they can be replayed on another Mac by setup_macos_apps.sh.
#
#              Strips machine-local noise (window frames, Sparkle update state,
#              install IDs, NoSync* keys) and writes XML where the data allows
#              it, so the prefs stay diffable in git.
#
# Usage:
#   ./macos/export_macos_prefs.sh
#   git diff macos/prefs        # review before committing
###############################################################################
set -euo pipefail

[ "$(uname -s)" = "Darwin" ] || { echo "macOS only."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFS_DIR="${SCRIPT_DIR}/prefs"
mkdir -p "$PREFS_DIR"

DOMAINS=( "com.googlecode.iterm2" "com.sempliva.Tiles" )

# Dropped on export: per-machine state, not settings worth carrying across Macs.
export STRIP_PREFIXES='NoSync SU NSWindow Frame NSNavPanel NSOSPLastRootDirectory NSToolbar NSSplitView'

for domain in "${DOMAINS[@]}"; do
    SRC_TMP="$(mktemp -t "${domain}")"
    DST="${PREFS_DIR}/${domain}.plist"

    if ! defaults export "$domain" - > "$SRC_TMP" 2>/dev/null || [ ! -s "$SRC_TMP" ]; then
        echo "  skip  ${domain} (no preferences found)"
        rm -f "$SRC_TMP"
        continue
    fi

    # Go through binary1: Apple's parser tolerates dates and the raw control
    # characters that ctrl+<key> hotkeys store, which strict XML parsers reject.
    plutil -convert binary1 "$SRC_TMP"

    python3 - "$SRC_TMP" "$DST" <<'PY'
import os, plistlib, subprocess, sys

src, dst = sys.argv[1], sys.argv[2]
prefixes = tuple(os.environ["STRIP_PREFIXES"].split())

with open(src, "rb") as fh:
    data = plistlib.load(fh)

kept = {k: v for k, v in sorted(data.items()) if not k.startswith(prefixes)}

with open(dst, "wb") as fh:
    plistlib.dump(kept, fh, fmt=plistlib.FMT_BINARY, sort_keys=True)

# Prefer XML for reviewable diffs, but only when it round-trips cleanly.
subprocess.run(["plutil", "-convert", "xml1", dst], check=True)
with open(dst, "rb") as fh:
    body = fh.read()

illegal = {b for b in body if b < 0x20 and b not in (0x09, 0x0A, 0x0D)}
fmt = "xml1"
if illegal:
    subprocess.run(["plutil", "-convert", "binary1", dst], check=True)
    fmt = "binary1 (contains control characters from ctrl+<key> hotkeys)"

print(f"  {len(kept)} keys kept, {len(data) - len(kept)} stripped, format {fmt}")
PY

    rm -f "$SRC_TMP"
    echo "export  ${domain} -> macos/prefs/${domain}.plist"
done

echo
echo "Done. Review with: git diff macos/prefs"

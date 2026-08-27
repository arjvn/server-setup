# macOS app settings

Carries the iTerm2 and Tiles setup from one Mac to another. The prefs in
`prefs/` are exported from a working machine, committed, and replayed on the
new one.

## On the new Mac

```bash
git clone git@github.com:arjvn/server-setup.git
cd server-setup
git checkout macos-support
./macos/setup_macos_apps.sh          # run this from Terminal.app, not iTerm2
```

Installs `iterm2`, `tiles` and the `font-meslo-lg-nerd-font` cask (MesloLGS NF,
which the iTerm profile and Powerlevel10k both expect), then imports the prefs.
Anything already installed is left alone, and the existing prefs are backed up
to `~/Library/Preferences/pre-server-setup-backup/` before being overwritten.

`setup_server.sh` calls this as its last step on macOS. Set `SKIP_MACOS_APPS=1`
to skip it.

Flags: `--apps-only` (install, leave prefs alone), `--prefs-only` (restore
prefs, skip the installs).

**Run it from Terminal.app.** iTerm2 rewrites its plist when it quits, so its
prefs can only be restored while it is closed. The script refuses to run from
inside iTerm2 rather than killing the terminal it is running in.

## What gets carried over

| App | Settings |
|---|---|
| iTerm2 | Default profile, Gruvbox Dark Hard colour preset, MesloLGS NF 13, 80x25, pointer actions, tab style, esc feedback, AI panel config |
| Tiles | All window hotkeys (halves, thirds, fullscreen, display switching), 4px window padding, fullscreen padding, launch at login, menu bar icon off |

## Updating the prefs after changing settings

```bash
./macos/export_macos_prefs.sh
git diff macos/prefs
```

The export strips per-machine state (`NoSync*`, Sparkle update keys, saved
window frames, install IDs) so the diff shows real setting changes only.

`com.googlecode.iterm2.plist` is stored as XML so it diffs. Tiles is stored as
a binary plist: its hotkey entries hold raw control characters from `ctrl+<key>`
bindings, which are not legal in XML.

## Manual steps

1. **Tiles needs Accessibility permission** before any hotkey fires. System
   Settings > Privacy & Security > Accessibility > enable Tiles. Launching
   Tiles once prompts for it.
2. **Tiles is paid** - sign in or enter the licence on first launch.
3. If iTerm2 renders boxes instead of prompt glyphs, set the font by hand:
   Settings > Profiles > Text > MesloLGS NF.

## Not included

No credentials are stored here. The iTerm2 AI panel keeps its API key in the
macOS Keychain, not in the plist, so it does not travel with the repo and has
to be re-entered on the new Mac.

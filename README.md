# server-setup

Bootstrap script for a new machine - Linux server or Mac.

```bash
git clone git@github.com:arjvn/server-setup.git
cd server-setup

sudo bash setup_server.sh   # Linux
./setup_server.sh           # macOS
```

Installs tmux, zsh, git, curl, wget, Miniconda, Oh My Zsh + Powerlevel10k,
generates a GitHub SSH key, and drops the dotfiles from `dots/` into `$HOME`.

On macOS it also installs iTerm2 + Tiles and restores their settings from
`macos/prefs/` - see [macos/README.md](macos/README.md). Set `SKIP_MACOS_APPS=1`
to skip that step.

## Layout

| Path | What |
|---|---|
| `setup_server.sh` | The cross-platform bootstrap |
| `dots/` | `.zshrc`, `.p10k.zsh`, `.tmux.conf` |
| `macos/setup_macos_apps.sh` | Installs iTerm2 + Tiles, restores their prefs |
| `macos/export_macos_prefs.sh` | Re-captures those prefs after changing settings |
| `macos/prefs/` | The exported iTerm2 + Tiles preference plists |

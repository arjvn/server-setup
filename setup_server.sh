#!/usr/bin/env bash
###############################################################################
# Script: setup_server.sh
# Description: Cross-platform (Linux/macOS) setup script for development.
# Installs:
#   - tmux, zsh, git, curl, wget
#   - Miniconda
#   - Oh My Zsh + Powerlevel10k
#   - SSH key + GitHub config
#   - User dotfiles from ./dots/
#
# Usage:
#   chmod +x setup_server.sh
#   sudo bash setup_server.sh   (Linux)
#   ./setup_server.sh           (macOS)
###############################################################################
set -e

###############################################################################
# Detect OS
###############################################################################
OS="$(uname -s)"
case "$OS" in
    Linux*)  PLATFORM="linux" ;;
    Darwin*) PLATFORM="macos" ;;
    *) echo "Unsupported OS: $OS" && exit 1 ;;
esac

###############################################################################
# Root privilege handling
###############################################################################
if [ "$PLATFORM" = "linux" ]; then
    # Require root for apt/yum installs
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root (e.g., sudo bash setup_server.sh)."
        exit 1
    fi
else
    # macOS should NOT be run as root
    if [ "$EUID" -eq 0 ]; then
        echo "⚠️  Don't run this script with sudo on macOS."
        echo "Please re-run as your normal user, e.g.:"
        echo "   ./setup_server.sh"
        exit 1
    fi
fi


###############################################################################
# Variables
###############################################################################
USERNAME="${SUDO_USER:-$(whoami)}"
USERHOME="$(eval echo "~${USERNAME}")"
CONDA_INSTALL_PATH="/opt/miniconda"
SSH_KEYNAME="ki_github_ed25519"
SSH_EMAIL="arjun@kashmirintelligence.com"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTS_DIR="${SCRIPT_DIR}/dots"
DOTFILES=( ".zshrc" ".p10k.zsh" ".tmux.conf" ".gitconfig" )

###############################################################################
# Helper Function
###############################################################################
backup_if_exists() {
    local file_path="$1"
    if [ -e "$file_path" ]; then
        local timestamp="$(date +%Y%m%d%H%M%S)"
        echo "Backing up existing $file_path -> $file_path.bak.$timestamp"
        mv "$file_path" "$file_path.bak.$timestamp"
    fi
}

###############################################################################
# 1) Install packages
###############################################################################
echo "==> [1/7] Installing base packages..."

if [ "$PLATFORM" = "linux" ]; then
    if command -v apt >/dev/null 2>&1; then
        apt update -y
        apt install -y curl wget git tmux zsh
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl wget git tmux zsh
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl wget git tmux zsh
    else
        echo "Unsupported Linux package manager."
        exit 1
    fi
elif [ "$PLATFORM" = "macos" ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"  # Apple Silicon path
    fi
    brew install git tmux zsh wget curl
fi

###############################################################################
# 2) Install Miniconda
###############################################################################
echo "==> [2/7] Installing Miniconda..."

if [ "$PLATFORM" = "macos" ]; then
    CONDA_INSTALL_PATH="$USERHOME/miniconda3"
    INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh"
    # Fallback to x86 if needed
    if [ "$(uname -m)" = "x86_64" ]; then
        INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"
    fi
else
    INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
fi

if [ ! -d "${CONDA_INSTALL_PATH}" ]; then
    echo "Downloading Miniconda installer..."
    wget --quiet "$INSTALLER_URL" -O "/tmp/miniconda.sh"
    bash /tmp/miniconda.sh -b -f -p "${CONDA_INSTALL_PATH}"
    rm /tmp/miniconda.sh
else
    echo "Miniconda already exists at ${CONDA_INSTALL_PATH}. Skipping."
fi

# Conda init script
if [ "$PLATFORM" = "linux" ]; then
    cat <<EOF > /etc/profile.d/conda.sh
# >>> conda initialize >>>
. ${CONDA_INSTALL_PATH}/etc/profile.d/conda.sh
# <<< conda initialize <<<
EOF
else
    # macOS: add to .zprofile
    if ! grep -q "conda.sh" "${USERHOME}/.zprofile" 2>/dev/null; then
        echo ". ${CONDA_INSTALL_PATH}/etc/profile.d/conda.sh" >> "${USERHOME}/.zprofile"
    fi
fi

###############################################################################
# 3) Oh My Zsh + Powerlevel10k
###############################################################################
echo "==> [3/7] Installing Oh My Zsh and Powerlevel10k..."
if [ ! -d "${USERHOME}/.oh-my-zsh" ]; then
    if [ "$PLATFORM" = "linux" ]; then
        sudo -u "${USERNAME}" RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
fi

THEME_DIR="${USERHOME}/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$THEME_DIR" ]; then
    if [ "$PLATFORM" = "linux" ]; then
        sudo -u "$USERNAME" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$THEME_DIR"
    else
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$THEME_DIR"
    fi
else
    git -C "$THEME_DIR" pull || true
fi

###############################################################################
# 4) Copy dotfiles
###############################################################################
echo "==> [4/7] Copying dotfiles..."
for dotfile in "${DOTFILES[@]}"; do
    SRC_FILE="${DOTS_DIR}/${dotfile}"
    DST_FILE="${USERHOME}/${dotfile}"
    if [ -f "${SRC_FILE}" ]; then
        backup_if_exists "${DST_FILE}"
        cp -v "${SRC_FILE}" "${DST_FILE}"
        if [ "$PLATFORM" = "linux" ]; then
            chown "${USERNAME}:${USERNAME}" "${DST_FILE}"
        fi
    else
        echo "No ${dotfile} found. Skipping."
    fi
done

###############################################################################
# 5) Change shell to zsh
###############################################################################
echo "==> [5/7] Changing default shell to zsh..."
if [ "$PLATFORM" = "macos" ]; then
    CURRENT_SHELL="$(dscl . -read /Users/${USERNAME} UserShell 2>/dev/null | awk '{print $2}')"
elif [ "$PLATFORM" = "linux" ]; then
    CURRENT_SHELL="$(getent passwd "${USERNAME}" | cut -d: -f7)"
else
    CURRENT_SHELL=""
fi
if [[ "$CURRENT_SHELL" != *"zsh"* ]]; then
    chsh -s "$(command -v zsh)" "${USERNAME}" || true
fi

###############################################################################
# 6) SSH key setup
###############################################################################
echo "==> [6/7] Setting up GitHub SSH key..."
SSH_DIR="${USERHOME}/.ssh"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

if [ ! -f "${SSH_DIR}/${SSH_KEYNAME}" ]; then
    ssh-keygen -t ed25519 -C "${SSH_EMAIL}" -f "${SSH_DIR}/${SSH_KEYNAME}" -N "" -q
    # Fix ownership if running as root on Linux
    if [ "$PLATFORM" = "linux" ]; then
        chown "${USERNAME}:${USERNAME}" "${SSH_DIR}/${SSH_KEYNAME}" "${SSH_DIR}/${SSH_KEYNAME}.pub"
    fi
else
    echo "SSH key already exists. Skipping."
fi

SSH_CONFIG="${SSH_DIR}/config"
if ! grep -q "Host github.com" "${SSH_CONFIG}" 2>/dev/null; then
    cat <<EOF >> "${SSH_CONFIG}"

Host github.com
    HostName github.com
    IdentityFile ${SSH_DIR}/${SSH_KEYNAME}
    User git
EOF
    chmod 600 "${SSH_CONFIG}"
fi

###############################################################################
# Summary
###############################################################################
echo "============================================================"
echo " Setup complete on ${PLATFORM^^}!"
echo " 1) Miniconda installed at: ${CONDA_INSTALL_PATH}"
echo " 2) tmux, zsh, Oh My Zsh + Powerlevel10k installed."
echo " 3) Copied dotfiles from 'dots' folder."
echo " 4) SSH key generated: ${SSH_DIR}/${SSH_KEYNAME}"
echo "============================================================"
echo "Next steps:"
echo "  * Restart terminal or run: source ~/.zshrc"
echo "  * Add public key to GitHub:"
echo "    cat ${SSH_DIR}/${SSH_KEYNAME}.pub"
echo "  * Test SSH: ssh -T git@github.com"
echo "============================================================"

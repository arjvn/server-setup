#!/usr/bin/env bash
###############################################################################
# Script: setup_server.sh
# Description: Sets up a Linux server with:
#   1) System updates + dev tools (tmux, zsh, git, etc.)
#   2) Miniconda
#   3) Oh My Zsh + Powerlevel10k
#   4) SSH key generation + GitHub config
#   5) Copies user config files (dotfiles) from a local "dots" folder
#
# Usage:
#   chmod +x setup_server.sh
#   sudo bash setup_server.sh
#
###############################################################################
set -e  # Exit on error

###############################################################################
# 0) Check for root privileges (remove or modify if not needed)
###############################################################################
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (e.g., sudo bash setup_server.sh)."
    exit 1
fi

###############################################################################
# 1) Variables to Customize
###############################################################################
USERNAME="arjun"
USERHOME="/home/arjun"
CONDA_INSTALL_PATH="/opt/miniconda"
SSH_KEYNAME="ki_github_ed25519"
SSH_EMAIL="arjun@kashmirintelligence.com"

# Path to the local "dots" folder with config files
# We'll assume it's in the same directory as this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTS_DIR="${SCRIPT_DIR}/dots"

# A list of potential dotfiles you want to copy from `dots` to the user’s home.
# Add or remove filenames from this array as you see fit.
DOTFILES=(
  ".zshrc"
  ".p10k.zsh"
  ".tmux.conf"
  ".gitconfig"
)

###############################################################################
# Helper Function: backup_if_exists
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
# 2) System Update & Package Installation
###############################################################################
echo "==> [1/7] Updating system and installing packages..."
if command -v apt >/dev/null 2>&1; then
    # Ubuntu/Debian
    apt update -y
    # apt upgrade -y    # Optionally uncomment if you want to upgrade everything
    apt install -y curl wget git tmux zsh
elif command -v yum >/dev/null 2>&1; then
    # CentOS/older Fedora
    yum check-update -y
    yum install -y curl wget git tmux zsh
elif command -v dnf >/dev/null 2>&1; then
    # Fedora newer versions
    dnf check-update -y
    dnf install -y curl wget git tmux zsh
else
    echo "Package manager not recognized. Please modify the script for your distro."
    exit 1
fi

###############################################################################
# 3) Install Miniconda (system-wide)
###############################################################################
if [ ! -d "${CONDA_INSTALL_PATH}" ]; then
    echo "==> [2/7] Installing Miniconda to ${CONDA_INSTALL_PATH}..."
    CONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
    wget --quiet "https://repo.anaconda.com/miniconda/${CONDA_INSTALLER}" -O "/tmp/${CONDA_INSTALLER}"
    chmod +x "/tmp/${CONDA_INSTALLER}"
    /tmp/${CONDA_INSTALLER} -b -f -p "${CONDA_INSTALL_PATH}"
    rm "/tmp/${CONDA_INSTALLER}"

    # Create a system-wide conda init script
    echo "==> Configuring conda initialization..."
    cat <<EOF > /etc/profile.d/conda.sh
# >>> conda initialize >>>
. ${CONDA_INSTALL_PATH}/etc/profile.d/conda.sh
# <<< conda initialize <<<
EOF
else
    echo "==> [2/7] Miniconda already installed at ${CONDA_INSTALL_PATH}. Skipping."
fi

###############################################################################
# 4) Install Oh My Zsh (Unattended) + Powerlevel10k
###############################################################################
echo "==> [3/7] Installing (or updating) Oh My Zsh..."
if [ ! -d "${USERHOME}/.oh-my-zsh" ]; then
    sudo -u "${USERNAME}" sh -c "
      export RUNZSH=no;
      export CHSH=no;
      sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\"
    "
else
    echo "Oh My Zsh already installed for ${USERNAME}. Skipping re-install."
fi

echo "==> [4/7] Installing (or updating) Powerlevel10k..."
THEME_DIR="${USERHOME}/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$THEME_DIR" ]; then
    sudo -u "${USERNAME}" git clone --depth=1 \
        https://github.com/romkatv/powerlevel10k.git \
        "$THEME_DIR"
else
    echo "Powerlevel10k theme directory exists. Pulling latest changes..."
    sudo -u "${USERNAME}" git -C "$THEME_DIR" pull || true
fi

###############################################################################
# 5) Copy Dotfiles from local "dots" folder to user's home
###############################################################################
echo "==> [5/7] Copying dotfiles (if found in ${DOTS_DIR})..."

for dotfile in "${DOTFILES[@]}"; do
    SRC_FILE="${DOTS_DIR}/${dotfile}"
    DST_FILE="${USERHOME}/${dotfile}"

    if [ -f "${SRC_FILE}" ]; then
        echo "Found ${dotfile} in dots folder. Installing..."
        backup_if_exists "${DST_FILE}"
        cp -v "${SRC_FILE}" "${DST_FILE}"
        chown "${USERNAME}:${USERNAME}" "${DST_FILE}"
    else
        echo "No ${dotfile} in dots folder. Skipping."
    fi
done

# Optional: ensure Powerlevel10k is set in .zshrc if it wasn't overwritten
# (You can add checks here if you want to forcibly set ZSH_THEME or source .p10k.zsh)

###############################################################################
# 6) Change Default Shell to Zsh
###############################################################################
echo "==> [6/7] Setting default shell to zsh for ${USERNAME}..."
CURRENT_SHELL="$(getent passwd "${USERNAME}" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != *"zsh"* ]]; then
    chsh -s "$(command -v zsh)" "${USERNAME}"
    echo "Default shell changed to zsh."
else
    echo "Default shell is already zsh. No changes."
fi

###############################################################################
# 7) Generate SSH Key for GitHub + SSH Config (Non-Destructive)
###############################################################################
echo "==> [7/7] Setting up GitHub SSH key..."

SSH_DIR="${USERHOME}/.ssh"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chown "${USERNAME}:${USERNAME}" "${SSH_DIR}"

if [ ! -f "${SSH_DIR}/${SSH_KEYNAME}" ]; then
    echo "Generating a new SSH key (${SSH_KEYNAME}) with email: ${SSH_EMAIL}"
    sudo -u "${USERNAME}" ssh-keygen \
        -t ed25519 \
        -C "${SSH_EMAIL}" \
        -f "${SSH_DIR}/${SSH_KEYNAME}" \
        -N "" \
        -q
else
    echo "SSH key ${SSH_KEYNAME} already exists. Skipping generation."
fi

# Ensure .ssh/config has an entry for GitHub
SSH_CONFIG="${SSH_DIR}/config"
if ! grep -q "Host github.com" "${SSH_CONFIG}" 2>/dev/null; then
    echo "Creating SSH config entry for GitHub..."
    cat <<EOF >> "${SSH_CONFIG}"

Host github.com
    HostName github.com
    IdentityFile ${SSH_DIR}/${SSH_KEYNAME}
    User git
EOF
    chown "${USERNAME}:${USERNAME}" "${SSH_CONFIG}"
    chmod 600 "${SSH_CONFIG}"
else
    echo "SSH config entry for GitHub already exists. Skipping."
fi

###############################################################################
# Final Output
###############################################################################
echo "============================================================"
echo " Setup complete!"
echo " 1) Miniconda installed (if not already) at: ${CONDA_INSTALL_PATH}"
echo " 2) tmux, zsh, Oh My Zsh + Powerlevel10k installed."
echo " 3) Copied dotfiles (if they existed in 'dots' folder)."
echo " 4) Conda init script: /etc/profile.d/conda.sh"
echo " 5) Generated SSH key (if not already present): ${SSH_DIR}/${SSH_KEYNAME}"
echo "============================================================"
echo "Next steps:"
echo "  * Log out/log back in or 'sudo su - ${USERNAME}' to load new shell."
echo "  * 'source /etc/profile.d/conda.sh' to activate conda if needed."
echo "  * Add your public key to GitHub:"
echo "    ${SSH_DIR}/${SSH_KEYNAME}.pub"
echo "  * Test SSH: sudo -u ${USERNAME} ssh -T git@github.com"
echo "============================================================"

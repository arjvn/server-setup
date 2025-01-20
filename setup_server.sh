#!/usr/bin/env bash
###############################################################################
# Script: setup_server.sh
# Description: Sets up a Linux server with:
#   1) System updates + basic dev tools (tmux, zsh, git, etc.)
#   2) Miniconda (or swap out for Miniforge if preferred)
#   3) Oh My Zsh and Powerlevel10k
#   4) SSH key generation + GitHub config
#
# Usage:
#   chmod +x setup_server.sh
#   sudo bash setup_server.sh
###############################################################################

set -e  # Exit on any error

# ------------------------------------------------------------------------------
# 0) Check for root privileges (optional, remove if you don’t need it)
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (e.g., sudo bash setup_server.sh)."
    exit 1
fi

# ------------------------------------------------------------------------------
# Variables you should customize:
# ------------------------------------------------------------------------------
USERNAME="arjun"        # or a non-root user like "ubuntu"
USERHOME="/home/arjun"       # or "/home/ubuntu" if USERNAME=ubuntu
CONDA_INSTALL_PATH="/opt/miniconda"
SSH_KEYNAME="ki_github_ed25519"
SSH_EMAIL="arjun@kashmirintelligence.com"

# ------------------------------------------------------------------------------
# 1) Update System & Install Basic Packages
# ------------------------------------------------------------------------------
echo "==> [1/6] Updating system and installing packages..."
if command -v apt >/dev/null 2>&1; then
    # Ubuntu/Debian
    apt update -y
    # apt upgrade -y
    apt install -y curl wget git tmux zsh
# elif command -v yum >/dev/null 2>&1; then
#     # CentOS/Fedora
#     yum check-update -y
#     yum install -y curl wget git tmux zsh
# elif command -v dnf >/dev/null 2>&1; then
#     # Fedora newer versions
#     dnf check-update -y
#     dnf install -y curl wget git tmux zsh
else
    echo "Package manager not recognized. Please modify the script for your distro."
    exit 1
fi

# ------------------------------------------------------------------------------
# 2) Install Miniconda (or Miniforge)
# ------------------------------------------------------------------------------
# You can swap the URL below for Miniforge if you prefer:
#   https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh

CONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
echo "==> [2/6] Downloading Miniconda installer..."
wget --quiet "https://repo.anaconda.com/miniconda/${CONDA_INSTALLER}" -O "/tmp/${CONDA_INSTALLER}"
chmod +x "/tmp/${CONDA_INSTALLER}"

echo "==> Installing Miniconda to $CONDA_INSTALL_PATH..."
/tmp/${CONDA_INSTALLER} -b -f -p "${CONDA_INSTALL_PATH}"
rm "/tmp/${CONDA_INSTALLER}"

echo "==> Configuring system-wide conda initialization..."
cat <<EOF > /etc/profile.d/conda.sh
# >>> conda initialize >>>
. ${CONDA_INSTALL_PATH}/etc/profile.d/conda.sh
# <<< conda initialize <<<
EOF

# ------------------------------------------------------------------------------
# 3) Install & Configure Oh My Zsh (Unattended)
# ------------------------------------------------------------------------------
echo "==> [3/6] Installing Oh My Zsh (unattended) for user ${USERNAME}..."
sudo -u "${USERNAME}" sh -c "
  export RUNZSH=no;
  export CHSH=no;
  sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\"
"

# ------------------------------------------------------------------------------
# 4) Install and Set Powerlevel10k
# ------------------------------------------------------------------------------
echo "==> [4/6] Installing Powerlevel10k..."
sudo -u "${USERNAME}" git clone --depth=1 \
    https://github.com/romkatv/powerlevel10k.git \
    "${USERHOME}/.oh-my-zsh/custom/themes/powerlevel10k" || true

ZSHRC="${USERHOME}/.zshrc"
if [ -f "$ZSHRC" ]; then
    # Replace existing ZSH_THEME with powerlevel10k
    sudo -u "${USERNAME}" sed -i \
        's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' \
        "$ZSHRC"
else
    # If .zshrc doesn't exist for some reason, create it
    touch "$ZSHRC"
    chown "${USERNAME}:${USERNAME}" "$ZSHRC"
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

# Append recommended p10k config snippet
cat <<'EOP' >> "$ZSHRC"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOP

# ------------------------------------------------------------------------------
# 5) Change Default Shell to Zsh
# ------------------------------------------------------------------------------
echo "==> [5/6] Setting default shell to zsh for ${USERNAME}..."
chsh -s "$(command -v zsh)" "${USERNAME}"

# ------------------------------------------------------------------------------
# 6) Generate SSH Key for GitHub + SSH Config
# ------------------------------------------------------------------------------
echo "==> [6/6] Setting up GitHub SSH key..."
SSH_DIR="${USERHOME}/.ssh"
sudo -u "${USERNAME}" mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chown "${USERNAME}:${USERNAME}" "${SSH_DIR}"

# If key doesn't exist, generate it
if [ ! -f "${SSH_DIR}/${SSH_KEYNAME}" ]; then
    echo "Generating a new SSH key (${SSH_KEYNAME}) with email: ${SSH_EMAIL}"
    sudo -u "${USERNAME}" ssh-keygen \
        -t ed25519 \
        -C "${SSH_EMAIL}" \
        -f "${SSH_DIR}/${SSH_KEYNAME}" \
        -N "" \
        -q
else
    echo "Key ${SSH_KEYNAME} already exists. Skipping generation."
fi

# Ensure the .ssh/config has an entry for GitHub
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
fi

# ------------------------------------------------------------------------------
# Final Output
# ------------------------------------------------------------------------------
echo "============================================================"
echo " Setup complete!"
echo " 1) Miniconda installed to:      ${CONDA_INSTALL_PATH}"
echo " 2) tmux, zsh, Oh My Zsh + Powerlevel10k installed."
echo " 3) Conda init script:           /etc/profile.d/conda.sh"
echo " 4) Generated SSH key for GitHub: ${SSH_DIR}/${SSH_KEYNAME}"
echo "============================================================"

echo "Next steps:"
echo "  * Log out and log back in (so zsh is your default shell)."
echo "  * Run:   source /etc/profile.d/conda.sh   to activate conda if needed."
echo "  * Copy your public key to GitHub (Settings > SSH and GPG keys)."
echo "    Public key path: ${SSH_DIR}/${SSH_KEYNAME}.pub"
echo "    You can test SSH connectivity: sudo -u ${USERNAME} ssh -T git@github.com"
echo "============================================================"

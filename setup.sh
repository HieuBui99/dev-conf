#!/usr/bin/env bash
set -euo pipefail

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
    INSTALL="sudo apt-get install -y"
    UPDATE="sudo apt-get update"
elif command -v dnf >/dev/null 2>&1; then
    INSTALL="sudo dnf install -y"
    UPDATE="sudo dnf check-update || true"
elif command -v pacman >/dev/null 2>&1; then
    INSTALL="sudo pacman -S --noconfirm"
    UPDATE="sudo pacman -Sy"
elif command -v brew >/dev/null 2>&1; then
    INSTALL="brew install"
    UPDATE="brew update"
else
    echo "No supported package manager found (apt/dnf/pacman/brew)." >&2
    exit 1
fi

# 1. Install zsh + git + curl
$UPDATE
$INSTALL zsh git curl

# 2. Install Oh My Zsh (unattended)
export RUNZSH=no
export CHSH=no
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# 3. Powerlevel10k theme
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        "$ZSH_CUSTOM/themes/powerlevel10k"
fi

# 4. zsh-syntax-highlighting
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# 5. zsh-autosuggestions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# 6. Configure ~/.zshrc
ZSHRC="$HOME/.zshrc"

# Set theme
sed -i.bak 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"

# Set plugins (order matters: syntax-highlighting must be last)
sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' "$ZSHRC"

# 7. Set zsh as default shell
# === Set zsh as default shell ===
ZSH_PATH="$(command -v zsh)"

if [ -z "$ZSH_PATH" ]; then
    echo "zsh not found in PATH; cannot set as default." >&2
    exit 1
fi

# Ensure zsh is listed in /etc/shells (chsh refuses otherwise)
if [ -w /etc/shells ] || sudo -n true 2>/dev/null; then
    if ! grep -qx "$ZSH_PATH" /etc/shells 2>/dev/null; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
    fi
fi

# Only change if not already the default
CURRENT_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
[ -z "$CURRENT_SHELL" ] && CURRENT_SHELL="${SHELL:-}"

if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
    if chsh -s "$ZSH_PATH" "$USER" 2>/dev/null; then
        echo "Default shell changed to zsh."
    elif sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null; then
        echo "Default shell changed to zsh (via sudo)."
    else
        # Fallback: usermod (no password prompt under sudo)
        if sudo usermod -s "$ZSH_PATH" "$USER" 2>/dev/null; then
            echo "Default shell changed to zsh (via usermod)."
        else
            echo "Could not change default shell automatically." >&2
            echo "Run manually: chsh -s $ZSH_PATH" >&2
        fi
    fi
else
    echo "zsh is already the default shell."
fi

echo "Change takes effect on next login. Run 'exec zsh' to switch now."

echo "Done. Restart your terminal or run: exec zsh"
echo "On first launch, configure the prompt with: p10k configure"

# === Miniconda ===
# Detect architecture for the correct installer
case "$(uname -m)" in
    x86_64)   MC_ARCH="x86_64" ;;
    aarch64)  MC_ARCH="aarch64" ;;
    arm64)    MC_ARCH="aarch64" ;;
    *) echo "Unsupported architecture for Miniconda: $(uname -m)" >&2; exit 1 ;;
esac

# OS (Linux vs macOS)
case "$(uname -s)" in
    Linux)  MC_OS="Linux" ;;
    Darwin) MC_OS="MacOSX" ;;
    *) echo "Unsupported OS for Miniconda: $(uname -s)" >&2; exit 1 ;;
esac

MC_DIR="$HOME/miniconda3"
MC_INSTALLER="/tmp/miniconda.sh"
MC_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-${MC_OS}-${MC_ARCH}.sh"

if [ ! -d "$MC_DIR" ]; then
    curl -fsSL "$MC_URL" -o "$MC_INSTALLER"
    # -b batch/silent (accepts license), -p install prefix
    bash "$MC_INSTALLER" -b -p "$MC_DIR"
    rm -f "$MC_INSTALLER"
fi

# Initialize conda for zsh (writes a block to ~/.zshrc)
"$MC_DIR/bin/conda" init zsh

# Optional: keep base env from auto-activating on every shell
"$MC_DIR/bin/conda" config --set auto_activate_base false
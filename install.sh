#!/bin/bash
# STOLER universal installer – any Linux distro & Termux
set -e

W='\033[1;37m'
RST='\033[0m'

# Определяем среду
if [ -n "$PREFIX" ] && [ -d "$PREFIX" ]; then
    IS_TERMUX=true
    BIN_DIR="$PREFIX/bin"
else
    IS_TERMUX=false
    BIN_DIR="/usr/local/bin"
fi

# Функция для определения пакетного менеджера на Linux
detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then echo "apt-get"
    elif command -v pacman >/dev/null 2>&1; then echo "pacman"
    elif command -v dnf >/dev/null 2>&1; then echo "dnf"
    elif command -v zypper >/dev/null 2>&1; then echo "zypper"
    elif command -v apk >/dev/null 2>&1; then echo "apk"
    elif command -v xbps-install >/dev/null 2>&1; then echo "xbps-install"
    elif command -v emerge >/dev/null 2>&1; then echo "emerge"
    else echo "unknown"
    fi
}

# Установка зависимостей для разных сред
install_deps() {
    if $IS_TERMUX; then
        pkg update -y
        pkg install -y curl jq transmission git
    else
        local PKG=$(detect_pkg_manager)
        case "$PKG" in
            apt-get)
                sudo apt-get update
                sudo apt-get install -y curl jq transmission-cli git
                ;;
            pacman)
                sudo pacman -Syu --noconfirm curl jq transmission-cli git
                ;;
            dnf)
                sudo dnf install -y curl jq transmission-cli git
                ;;
            zypper)
                sudo zypper install -y curl jq transmission-cli git
                ;;
            apk)
                doas apk add curl jq transmission-cli git
                ;;
            xbps-install)
                sudo xbps-install -Sy curl jq transmission git
                ;;
            emerge)
                sudo emerge -av curl jq transmission git
                ;;
            *)
                echo "[!] Unknown package manager. Please install: curl jq transmission-cli git"
                return 1
                ;;
        esac
    fi
}

clear
echo -e "${W}███████╗████████╗ ██████╗ ██╗     ███████╗██████╗ ${RST}"
echo -e "${W}██╔════╝╚══██╔══╝██╔═══██╗██║     ██╔════╝██╔══██╗${RST}"
echo -e "${W}███████╗   ██║   ██║   ██║██║     █████╗  ██████╔╝${RST}"
echo -e "${W}╚════██║   ██║   ██║   ██║██║     ██╔══╝  ██╔══██╗${RST}"
echo -e "${W}███████║   ██║   ╚██████╔╝███████╗███████╗██║  ██║${RST}"
echo -e "${W}╚══════╝   ╚═╝    ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝${RST}"
echo ""
echo -e "${W}  Decentralized Package Manager${RST}"
echo -e "${W}  (C) Copyright aKernel within the STORM project${RST}"
echo ""

echo "[1/4] Installing dependencies..."
install_deps

echo "[2/4] Downloading STOLER..."
STOLER_URL="https://raw.githubusercontent.com/aKernel-soft/storm-central/main/packages/stoler.sh"
curl -sL "$STOLER_URL" -o "$BIN_DIR/stoler"
chmod +x "$BIN_DIR/stoler"

echo "[3/4] Adding official repository..."
stoler remote add storm-central https://raw.githubusercontent.com/aKernel-soft/storm-central/main/index.json 2>/dev/null || true

echo "[4/4] Finalizing..."

echo ""
echo "  STOLER installed successfully!"
echo "  Run 'stoler list' to browse packages."
echo "  (C) Copyright aKernel"

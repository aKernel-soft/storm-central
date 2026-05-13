#!/bin/bash
# STOLER Installer – Decentralized Package Manager
# (C) Copyright CKM SOFTWARE within the STORM project
# Version: 1.0.0

set -e

W='\033[1;37m'  # белый
RST='\033[0m'
STOLER_URL="https://raw.githubusercontent.com/CKM-SOFT/storm-central/main/packages/stoler.sh"
STOLER_BIN="$PREFIX/bin/stoler"

clear
echo -e "${W}███████╗████████╗ ██████╗ ██╗     ███████╗██████╗ ${RST}"
echo -e "${W}██╔════╝╚══██╔══╝██╔═══██╗██║     ██╔════╝██╔══██╗${RST}"
echo -e "${W}███████╗   ██║   ██║   ██║██║     █████╗  ██████╔╝${RST}"
echo -e "${W}╚════██║   ██║   ██║   ██║██║     ██╔══╝  ██╔══██╗${RST}"
echo -e "${W}███████║   ██║   ╚██████╔╝███████╗███████╗██║  ██║${RST}"
echo -e "${W}╚══════╝   ╚═╝    ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝${RST}"
echo ""
echo -e "${W}  Decentralized Package Manager${RST}"
echo -e "${W}  (C) Copyright CKM SOFTWARE within the STORM project${RST}"
echo ""

echo "[1/4] Installing dependencies..."
pkg update -y
pkg install -y curl jq transmission git

echo "[2/4] Downloading STOLER..."
curl -sL "$STOLER_URL" -o "$STOLER_BIN"
chmod +x "$STOLER_BIN"

echo "[3/4] Adding official repository..."
stoler remote add storm-central https://raw.githubusercontent.com/CKM-SOFT/storm-central/main/index.json 2>/dev/null || true

echo "[4/4] Finalizing..."
stoler update 2>/dev/null || true

echo ""
echo "  STOLER installed successfully!"
echo "  Run 'stoler shop' to browse packages."
echo "  (C) Copyright CKM SOFTWARE"

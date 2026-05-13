#!/bin/bash
# STOLER Installer – Decentralized Package Manager
# (C) Copyright CKM SOFTWARE within the STORM project
# Version: 1.0.0

set -e

# ── Цвета и переменные ──
R='\033[1;31m'
G='\033[1;32m'
Y='\033[1;33m'
B='\033[1;34m'
C='\033[1;36m'
W='\033[0m'
STOLER_URL="https://raw.githubusercontent.com/CKM-SOFT/storm-central/main/packages/stoler.sh"
STOLER_BIN="$PREFIX/bin/stoler"

clear
echo -e "${R}███████╗████████╗ ██████╗ ██╗     ███████╗██████╗ ${W}"
echo -e "${R}██╔════╝╚══██╔══╝██╔═══██╗██║     ██╔════╝██╔══██╗${W}"
echo -e "${G}███████╗   ██║   ██║   ██║██║     █████╗  ██████╔╝${W}"
echo -e "${G}╚════██║   ██║   ██║   ██║██║     ██╔══╝  ██╔══██╗${W}"
echo -e "${B}███████║   ██║   ╚██████╔╝███████╗███████╗██║  ██║${W}"
echo -e "${B}╚══════╝   ╚═╝    ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝${W}"
echo ""
echo -e "${C}  Decentralized Package Manager${W}"
echo -e "${C}  (C) Copyright CKM SOFTWARE within the STORM project${W}"
echo ""

echo -e "${Y}[1/4] Installing dependencies...${W}"
pkg update -y
pkg install -y curl jq transmission git

echo -e "${Y}[2/4] Downloading STOLER...${W}"
curl -sL "$STOLER_URL" -o "$STOLER_BIN"
chmod +x "$STOLER_BIN"

echo -e "${Y}[3/4] Adding official repository...${W}"
stoler remote add storm-central https://raw.githubusercontent.com/CKM-SOFT/storm-central/main/index.json 2>/dev/null || true

echo -e "${Y}[4/4] Finalizing...${W}"
stoler update 2>/dev/null || true

echo ""
echo -e "${G}  STOLER installed successfully!${W}"
echo -e "${G}  Run 'stoler shop' to browse packages.${W}"
echo -e "${G}  (C) Copyright CKM SOFTWARE ${W}"

#!/bin/bash
# STOLER – кросс-платформенный децентрализованный пакетный менеджер
set -eo pipefail

# Определяем среду: Termux или обычный Linux
if [ -n "$PREFIX" ] && [ -d "$PREFIX" ]; then
    IS_TERMUX=true
    BIN_DIR="$PREFIX/bin"
    TMP_DIR="$PREFIX/tmp"
else
    IS_TERMUX=false
    BIN_DIR="/usr/local/bin"
    TMP_DIR="/tmp"
fi
DOWNLOAD_BASE="$HOME/stoler"

D="$HOME/.stoler"
mkdir -p "$D/repos" "$D/downloads" "$DOWNLOAD_BASE" "$TMP_DIR"

LOCAL_INDEX="$D/repos/local.json"
REMOTE_DIR="$D/repos/remotes"
mkdir -p "$REMOTE_DIR"
[ ! -f "$LOCAL_INDEX" ] && echo '{"projects":[]}' > "$LOCAL_INDEX"

# ---------- автоматическое добавление ~/stoler в PATH ----------
setup_path() {
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "$DOWNLOAD_BASE" "$HOME/.bashrc"; then
            echo "export PATH=\"$DOWNLOAD_BASE:\$PATH\"" >> "$HOME/.bashrc"
            echo "[*] Added $DOWNLOAD_BASE to PATH in .bashrc. Restart shell or run: source ~/.bashrc"
        fi
    fi
}

# ---------- список всех пакетов ----------
list_all() {
    [ -f "$LOCAL_INDEX" ] && jq -r '.projects[] | "\(.name) [\(.type)] - \(.desc)"' "$LOCAL_INDEX" 2>/dev/null || true
    for f in "$REMOTE_DIR"/*.json; do
        [ -f "$f" ] && jq -r '.projects[] | "\(.name) [\(.type)] - \(.desc)"' "$f" 2>/dev/null || true
    done
}

# ---------- добавление пакета ----------
add_pkg() {
    local name="$1" url="$2" type="$3" desc="$4" magnet="${5:-}"
    [ -z "$name" ] || [ -z "$url" ] && {
        echo "Usage: stoler add <name> <url> <type> <desc> [magnet]"
        return 1
    }
    jq --arg n "$name" --arg u "$url" --arg t "$type" --arg d "$desc" --arg m "$magnet" \
       '.projects += [{"name":$n,"url":$u,"type":$t,"desc":$d,"magnet":$m}]' \
       "$LOCAL_INDEX" > "$TMP_DIR/stoler_add.tmp" && mv "$TMP_DIR/stoler_add.tmp" "$LOCAL_INDEX"
    echo "[+] Package '$name' added."
}

# ---------- добавление удалённого репозитория ----------
remote_add() {
    local name="$1" url="$2"
    [ -z "$name" ] || [ -z "$url" ] && {
        echo "Usage: stoler remote add <name> <url>"
        return 1
    }
    echo "[*] Downloading remote repository '$name'..."
    curl -sL "$url" -o "$REMOTE_DIR/$name.json" && {
        echo "[+] Remote '$name' added."
    } || echo "[!] Failed to download repository."
}

# ---------- поиск пакета ----------
find_pkg() {
    local name="$1"
    local info=""
    if [ -f "$LOCAL_INDEX" ]; then
        info=$(jq -r --arg n "$name" '.projects[] | select(.name==$n) | "\(.magnet)|\(.type)|\(.url)"' "$LOCAL_INDEX" 2>/dev/null || true)
        [ -n "$info" ] && echo "$info" && return 0
    fi
    for f in "$REMOTE_DIR"/*.json; do
        [ -f "$f" ] || continue
        info=$(jq -r --arg n "$name" '.projects[] | select(.name==$n) | "\(.magnet)|\(.type)|\(.url)"' "$f" 2>/dev/null || true)
        [ -n "$info" ] && echo "$info" && return 0
    done
    return 1
}

# ---------- установка пакета (улучшенная) ----------
install_pkg() {
    local name="$1"
    local info magnet type url
    info=$(find_pkg "$name") || { echo "[!] Package '$name' not found."; return 1; }
    IFS='|' read -r magnet type url <<< "$info"

    # 1. Прямой URL
    if [ -n "$url" ] && [ "$url" != "null" ]; then
        local fname=$(basename "$url")
        local target="$DOWNLOAD_BASE/$name"
        echo "[*] Downloading $url..."
        curl -sL -o "$D/downloads/$fname" "$url" && {
            mkdir -p "$DOWNLOAD_BASE"
            cp "$D/downloads/$fname" "$target"
            chmod +x "$target" 2>/dev/null || true
            setup_path
            echo "[+] Installed '$name'. Run it with: $name"
            return 0
        }
        echo "[!] URL failed."
    fi

    # 2. Magnet
    if [ -n "$magnet" ] && [ "$magnet" != "null" ]; then
        if command -v transmission-remote >/dev/null; then
            pgrep transmission-da >/dev/null 2>&1 || { transmission-daemon 2>/dev/null; sleep 2; }
            echo "[*] Using magnet..."
            local out id
            out=$(transmission-remote -a "$magnet" --download-dir "$D/downloads" 2>&1)
            id=$(echo "$out" | grep -oP '(?<="id":)\d+')
            [ -z "$id" ] && { echo "[!] Magnet failed."; return 1; }
            while : ; do
                pct=$(transmission-remote -t "$id" -i 2>/dev/null | awk '/Percent Done:/{print $3}' | tr -d '%')
                [ "$pct" = "100" ] && break
                printf "\rDownloading: %s%%" "$pct"
                sleep 2
            done
            echo ""
            local file=$(find "$D/downloads" -type f ! -name '*.torrent' | head -1)
            [ -z "$file" ] && { echo "[!] No file."; return 1; }
            local target="$DOWNLOAD_BASE/$name"
            mkdir -p "$DOWNLOAD_BASE"
            cp "$file" "$target"
            chmod +x "$target" 2>/dev/null || true
            setup_path
            echo "[+] Installed '$name'. Run it with: $name"
            transmission-remote -t "$id" --remove
            return 0
        else
            echo "[!] Transmission not installed."
        fi
    fi

    echo "[!] Installation failed."
    return 1
}

# ---------- публикация файла (торрент) ----------
publish_file() {
    local file="$1"
    [ ! -f "$file" ] && { echo "[!] File not found."; return 1; }
    if ! command -v transmission-create >/dev/null; then
        echo "[!] Install transmission package first."
        return 1
    fi
    pgrep transmission-da >/dev/null 2>&1 || { transmission-daemon 2>/dev/null; sleep 2; }
    local fname=$(basename "$file")
    echo "[*] Creating torrent for $fname..."
    transmission-create -o "$TMP_DIR/$fname.torrent" -t udp://tracker.opentrackr.org:1337/announce "$file" 2>/dev/null
    transmission-remote -a "$TMP_DIR/$fname.torrent" 2>/dev/null
    sleep 2
    local magnet=""
    for id in $(transmission-remote -l | awk "/$fname/{print \$1}"); do
        magnet=$(transmission-remote -t "$id" -i 2>/dev/null | awk '/Magnet:/{print $2}')
        [ -n "$magnet" ] && break
    done
    echo "Magnet: $magnet"
    echo "Use: stoler add <name> <url> <type> <desc> \"$magnet\""
}

# ---------- самообновление ----------
self_update() {
    local url="$1"
    [ -z "$url" ] && { echo "Usage: stoler self-update <url>"; return 1; }
    echo "[*] Downloading new STOLER version..."
    curl -sL "$url" -o "$TMP_DIR/stoler_new" && {
        chmod +x "$TMP_DIR/stoler_new"
        mv "$TMP_DIR/stoler_new" "$BIN_DIR/stoler"
        echo "[+] STOLER updated."
    } || echo "[!] Update failed."
}

# ---------- интерактивный список (магазин) ----------
list() {
    setup_path
    clear
    echo "======== STOLER LIST ========"
    echo "Developer: CKM SOFTWARE within STORM project"
    echo ""

    local tmp_list="$TMP_DIR/stoler_shop_list"
    list_all > "$tmp_list" 2>/dev/null || true

    local i=1
    declare -A pkg_map
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name="${line%% *}"
        pkg_map[$i]="$name"
        echo "  $i) $line"
        i=$((i+1))
    done < "$tmp_list"
    rm -f "$tmp_list"

    if [ $i -eq 1 ]; then
        echo "  (no packages)"
        echo "Add with: stoler add <name> <url> <type> <desc>"
        echo "Or: stoler remote add <name> <url>"
        return
    fi
    echo "  0) Exit"
    printf "Select: "
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice < i )); then
        install_pkg "${pkg_map[$choice]}"
    elif [ "$choice" = "0" ]; then
        echo "STOLER closed."
    else
        echo "[!] Invalid choice."
    fi
}

help() {
    echo "STOLER - Decentralized Package Manager"
    echo "Developer: CKM SOFTWARE within STORM project"
    echo "Usage: stoler {add|remote|list|install|publish|self-update|help}"
}

case "${1:-}" in
    add)     add_pkg "$2" "$3" "$4" "$5" "$6";;
    remote)  remote_add "$3" "$4";;
    list)    list;;
    install) install_pkg "$2";;
    publish) publish_file "$2";;
    self-update) self_update "$2";;
    help|--help|-h) help;;
    *)       help;;
esac

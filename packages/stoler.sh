#!/bin/bash
# STOLER – rock-solid text-only package manager
set -eo pipefail

D="$HOME/.stoler"
mkdir -p "$D/repos" "$D/downloads" "$PREFIX/tmp"

INDEX="$D/repos/storm-index.json"
MAGNET="magnet:?xt=urn:btih:8e28292ff8f1f9f0eaaacbd48c4018a97c96dd6aMAGNET="magnet:?xt=urn:btih:08e0ca32cd0d9230679559c3b3c3fea6c64a2d94&dn=storm-index.json&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"dn=storm-index.jsonMAGNET="magnet:?xt=urn:btih:08e0ca32cd0d9230679559c3b3c3fea6c64a2d94&dn=storm-index.json&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"
[ ! -f "$INDEX" ] && echo '{"projects":[]}' > "$INDEX"

td() { pgrep transmission-da >/dev/null 2>&1 || { transmission-daemon 2>/dev/null; sleep 2; }; }

update_index() {
  echo "[*] Updating index..."
  td
  transmission-remote -l 2>/dev/null | awk '/storm-index/{print $1}' | while read id; do transmission-remote -t "$id" --remove 2>/dev/null; done
  out=$(transmission-remote -a "$MAGNET" --download-dir "$D/repos" 2>&1)
  id=$(echo "$out" | grep -oP '(?<="id":)\d+')
  [ -z "$id" ] && { echo "[!] Magnet failed."; return 1; }
  while : ; do
    info=$(transmission-remote -t "$id" -i 2>/dev/null)
    pct=$(echo "$info" | awk '/Percent Done:/{print $3}' | tr -d '%')
    pct=${pct:-0}
    [ "$pct" = "100" ] && break
    printf "\r[*] Index: %s%%" "$pct"
    sleep 2
  done
  echo ""
  transmission-remote -t "$id" --stop
  echo "[+] Index updated."
}

list() {
  [ ! -f "$INDEX" ] && { echo "Index missing. Run 'stoler update'."; return; }
  jq -r '.projects[] | "\(.name) [\(.type)] - \(.desc)"' "$INDEX"
}

install_pkg() {
  name="$1"
  info=$(jq -r --arg n "$name" '.projects[] | select(.name==$n) | "\(.magnet)|\(.type)|\(.url)"' "$INDEX")
  [ -z "$info" ] && { echo "[!] Package '$name' not found."; return 1; }
  IFS='|' read -r magnet type url <<< "$info"
  [ -n "$url" ] && [ "$url" != "null" ] && {
    path="${url#file://}"
    if [ -f "$path" ]; then
      mkdir -p "$HOME/storage/downloads/STOLER"
      cp "$path" "$HOME/storage/downloads/STOLER/"
      echo "[+] Installed '$name' from local file."
      return 0
    fi
    echo "[*] Downloading $url..."
    fname=$(basename "$url")
    curl -sL -o "$D/downloads/$fname" "$url" && {
      mkdir -p "$HOME/storage/downloads/STOLER"
      cp "$D/downloads/$fname" "$HOME/storage/downloads/STOLER/"
      echo "[+] Installed '$name' from URL."
      return 0
    }
    echo "[!] URL failed."
  }
  [ -n "$magnet" ] && [ "$magnet" != "null" ] && {
    td
    echo "[*] Using magnet..."
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
    file=$(find "$D/downloads" -type f ! -name '*.torrent' | head -1)
    [ -z "$file" ] && { echo "[!] No file."; return 1; }
    mkdir -p "$HOME/storage/downloads/STOLER"
    cp "$file" "$HOME/storage/downloads/STOLER/"
    echo "[+] Installed '$name' via magnet."
    transmission-remote -t "$id" --remove
    return 0
  }
  echo "[!] Installation failed."
  return 1
}

publish_file() {
  file="$1"
  [ ! -f "$file" ] && { echo "[!] File not found."; return 1; }
  td
  fname=$(basename "$file")
  echo "[*] Creating torrent for $fname..."
  transmission-create -o "$PREFIX/tmp/$fname.torrent" -t udp://tracker.opentrackr.org:1337/announce "$file" 2>/dev/null
  transmission-remote -a "$PREFIX/tmp/$fname.torrent" 2>/dev/null
  sleep 2
  magnet=""
  for id in $(transmission-remote -l | awk "/$fname/{print \$1}"); do
    magnet=$(transmission-remote -t "$id" -i 2>/dev/null | awk '/Magnet:/{print $2}')
    [ -n "$magnet" ] && break
  done
  echo "Magnet: $magnet"
  echo ""
  read -p "Package name: " pkg_name
  read -p "Type (script/apk/binary/other): " pkg_type
  read -p "Description: " pkg_desc
  url="file://$(realpath "$file")"
  jq --arg n "$pkg_name" --arg m "$magnet" --arg t "$pkg_type" --arg d "$pkg_desc" --arg u "$url" \
     '.projects += [{"name":$n,"magnet":$m,"type":$t,"desc":$d,"url":$u}]' \
     "$INDEX" > "$PREFIX/tmp/storm.tmp" && mv "$PREFIX/tmp/storm.tmp" "$INDEX"
  echo "[*] Updating index torrent..."
  transmission-remote -l | awk '/storm-index/{print $1}' | while read id; do transmission-remote -t "$id" --remove 2>/dev/null; done
  transmission-create -o "$PREFIX/tmp/storm-index.torrent" -t udp://tracker.opentrackr.org:1337/announce "$INDEX" 2>/dev/null
  transmission-remote -a "$PREFIX/tmp/storm-index.torrent" 2>/dev/null
  sleep 2
  new_magnet=""
  for id in $(transmission-remote -l | awk '/storm-index/{print $1}'); do
    new_magnet=$(transmission-remote -t "$id" -i 2>/dev/null | awk '/Magnet:/{print $2}')
    [ -n "$new_magnet" ] && break
  done
  [ -n "$new_magnet" ] && sed -i "s|MAGNET="magnet:?xt=urn:btih:8e28292ff8f1f9f0eaaacbd48c4018a97c96dd6aMAGNET=.*|MAGNET=\"$new_magnet\"|" $PREFIX/bin/stoler && echo "[+] New index magnet: $new_magnet"dn=storm-index.jsonMAGNET=.*|MAGNET=\"$new_magnet\"|" $PREFIX/bin/stoler && echo "[+] New index magnet: $new_magnet"tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"
  echo "[+] Package '$pkg_name' published."
}

shop() {
  [ ! -f "$INDEX" ] && { echo "[*] Index missing. Updating..."; update_index || return 1; }
  clear
  echo "======== STOLER SHOP ========"
  echo "Developer: CKM SOFTWARE within STORM project"
  echo ""
  list > "$PREFIX/tmp/stoler_shop_list"
  i=1
  declare -A pkg_map
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%% *}"
    pkg_map[$i]="$name"
    echo "  $i) $line"
    i=$((i+1))
  done < "$PREFIX/tmp/stoler_shop_list"
  rm -f "$PREFIX/tmp/stoler_shop_list"

  if [ $i -eq 1 ]; then
    echo "  (no packages)"
    echo "Publish with 'stoler publish'."
    return
  fi
  echo "  0) Exit"
  printf "Select: "
  read -r choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice < i )); then
    install_pkg "${pkg_map[$choice]}"
  elif [ "$choice" = "0" ]; then
    echo "Shop closed."
  else
    echo "[!] Invalid choice."
  fi
}

help() {
  echo "STOLER - Decentralized Package Manager"
  echo "Developer: CKM SOFTWARE within STORM project"
  echo "Usage: stoler {update|list|install|publish|shop|help}"
}

case "${1:-}" in
  update)  update_index;;
  list)    list;;
  install) install_pkg "$2";;
  publish) publish_file "$2";;
  shop)    shop;;
  help|--help|-h) help;;
  *)       help;;
esac

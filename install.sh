#!/usr/bin/env bash
# install.sh — SQLMAP_SHEET installer (Linux/macOS/Termux)
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/floryid/sqlmap-sheet.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/sqlmap-sheet}"

echo "[*] Deteksi environment..."
IS_TERMUX=0
[[ -n "${PREFIX:-}" && "$PREFIX" == *"com.termux"* ]] && IS_TERMUX=1

if [[ "$IS_TERMUX" == "1" ]]; then
  echo "[*] Termux terdeteksi — install dependency via pkg"
  pkg update -y && pkg install -y python curl git
  pip install --upgrade sqlmap
else
  echo "[*] Linux/macOS — cek dependency"
  command -v sqlmap >/dev/null 2>&1 || {
    echo "[!] sqlmap belum ada. Install dulu:"
    echo "    Debian/Ubuntu: sudo apt install sqlmap"
    echo "    macOS:        brew install sqlmap"
    exit 1
  }
fi

echo "[*] Clone/update repo..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo "[*] Set executable..."
chmod +x "$INSTALL_DIR/sqlmap_sheet.sh"

echo "[*] Tambahkan alias ke ~/.bashrc..."
grep -q "sqlmap_sheet.sh" "$HOME/.bashrc" 2>/dev/null || \
  echo "alias sqlmap-sheet='$INSTALL_DIR/sqlmap_sheet.sh'" >> "$HOME/.bashrc"

echo
echo "[✔] Instalasi selesai."
echo "    Jalankan: source ~/.bashrc && sqlmap-sheet"
echo "    Atau:     $INSTALL_DIR/sqlmap_sheet.sh"
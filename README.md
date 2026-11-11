# 🚀 SQLMAP_SHEET by Pixel_Detective

![Version](https://img.shields.io/badge/version-3.2-blue.svg)
![Bash](https://img.shields.io/badge/language-Bash-4EAA25.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Termux-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**SQLMAP_SHEET** adalah *Interactive Cheat Sheet* berbasis CLI untuk **SQLMap**. Script ini dirancang untuk mempermudah dan mempercepat proses *Penetration Testing* (SQL Injection) tanpa harus menghafal ratusan *flags* SQLMap. 

Dibuat dengan antarmuka interaktif yang modern, mendukung *Session Management*, *Export Report*, dan yang paling penting: **Dioptimalkan penuh untuk Termux (Android)**.

---

## ✨ Fitur Utama

- 🎯 **Deteksi & Enumerasi:** Deteksi dasar, ambil nama DB, tabel, dan kolom.
- 💾 **Submenu DUMP Lengkap:** Dump semua database, tabel, kolom, hingga data spesifik dengan filter `WHERE`.
- 🛡️ **WAF Bypass:** 7 preset *tamper scripts* (Cloudflare, AWS, ModSecurity, dll) untuk menembus WAF.
- 🔑 **SQL Query Kustom:** Jalankan query manual (`--sql-query`) atau dari file (`--sql-file`).
- 🕵️ **Proxy & Anonymizer:** Dukungan Burp Suite, rotasi proxy dari file, dan Tor Network.
- ⚙️ **Advanced Flags:** Akses cepat ke `--parse-errors`, `--smart`, `--hex`, `--dbms`, dan `--csrf-token`.
- 📱 **Termux-Ready:** Deteksi otomatis layar sempit, path `$HOME`, dan fitur `termux-wake-lock` agar scan tidak terputus saat layar mati.
- 📄 **Export Laporan:** Simpan hasil pentest ke format Markdown (`.md`) atau Text (`.txt`).
- 💾 **Session Save/Load:** Simpan konfigurasi target, lanjutkan kapan saja tanpa setup ulang.

---

## 📦 Panduan Instalasi

Pilih sistem operasi yang Anda gunakan:

### 1. Instalasi di Linux (Debian/Ubuntu/Kali)
```bash
# 1. Update repositori
sudo apt update && sudo apt install -y git curl python3 python3-pip

# 2. Install SQLMap
sudo apt install -y sqlmap

# 3. Clone repositori ini
git clone https://github.com/USERNAME/sqlmap-sheet.git
cd sqlmap-sheet

# 4. Beri izin eksekusi
chmod +x sqlmap_sheet.sh

# 5. Jalankan
./sqlmap_sheet.sh

2. Instalasi di macOS
# 1. Pastikan Homebrew terinstall, lalu install dependencies
brew install git python3 sqlmap

# 2. Clone repositori ini
git clone https://github.com/USERNAME/sqlmap-sheet.git
cd sqlmap-sheet

# 3. Beri izin eksekusi
chmod +x sqlmap_sheet.sh

# 4. Jalankan
./sqlmap_sheet.sh

3. Instalasi di Termux (Android)

# 1. Update package Termux
pkg update && pkg upgrade -y

# 2. Install dependencies
pkg install -y python git curl termux-api

# 3. Install SQLMap via pip (versi paling update)
pip install sqlmap

# 4. Clone repositori ini
git clone https://github.com/floryid/sqlmap-sheet.git
cd sqlmap-sheet

# 5. Beri izin eksekusi
chmod +x sqlmap_sheet.sh

# 6. Jalankan
./sqlmap_sheet.sh



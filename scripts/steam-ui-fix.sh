#!/bin/bash
# OpenBottle Steam UI black-screen shim installer; no sudo, no internet, no Steam update blocking.
set -euo pipefail

usage() {
  echo 'Kullanım: steam-ui-fix.sh {install|restore|status|probe} --prefix "WINEPREFIX_ADRESİ"'
  exit 2
}
[[ $# -eq 3 && "$2" == "--prefix" ]] || usage
ACTION="$1"; PREFIX="$3"
[[ "$ACTION" == install || "$ACTION" == restore || "$ACTION" == status || "$ACTION" == probe ]] || usage
[[ -d "$PREFIX/drive_c" ]] || { echo 'HATA: Geçerli Wine şişesi bulunamadı.'; exit 2; }
[[ ! -L "$PREFIX" ]] || { echo 'HATA: Sembolik bağlantı olan şişe kabul edilmiyor.'; exit 2; }

STEAM=''
for dir in "$PREFIX/drive_c/Program Files (x86)/Steam" "$PREFIX/drive_c/Program Files/Steam"; do
  if [[ -f "$dir/Steam.exe" && -d "$dir/bin/cef/cef.win64" ]]; then STEAM="$dir"; break; fi
done
if [[ "$ACTION" == probe && -z "$STEAM" ]]; then
  echo 'state=unavailable'
  if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 ||
    [[ -x /opt/homebrew/bin/x86_64-w64-mingw32-gcc || -x /usr/local/bin/x86_64-w64-mingw32-gcc ]]; then
    echo 'compiler=ready'
  else
    echo 'compiler=missing'
  fi
  echo 'steam=missing'
  exit 0
fi
[[ -n "$STEAM" ]] || { echo 'HATA: Bu şişede Steam.exe ve CEF klasörü bulunamadı.'; exit 2; }
CEF="$STEAM/bin/cef/cef.win64"
TARGET="$CEF/steamwebhelper.exe"
ORIGINAL="$CEF/steamwebhelper_real.exe"
MARKER="$CEF/.openbottle-steam-ui-v1"
[[ ! -L "$TARGET" && ! -L "$ORIGINAL" ]] || { echo 'HATA: Steam yardımcı dosyalarında sembolik bağlantı var.'; exit 2; }

file_hash() {
  shasum -a 256 "$1" | awk '{print $1}'
}
old_hash() {
  [[ -f "$MARKER" ]] || return 0
  sed -n 's/^sha256://p' "$MARKER" | head -n 1
}

case "$ACTION" in
  probe)
    if [[ -f "$MARKER" && -f "$ORIGINAL" && -f "$TARGET" ]]; then
      if [[ "$(old_hash)" == "$(file_hash "$TARGET")" ]]; then
        echo 'state=active'
      else
        echo 'state=changed'
      fi
    elif [[ -f "$MARKER" ]]; then
      echo 'state=damaged'
    elif [[ -f "$ORIGINAL" ]]; then
      echo 'state=conflict'
    elif [[ ! -f "$TARGET" ]]; then
      echo 'state=waiting'
    else
      echo 'state=ready'
    fi
    if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 ||
       [[ -x /opt/homebrew/bin/x86_64-w64-mingw32-gcc || -x /usr/local/bin/x86_64-w64-mingw32-gcc ]]; then
      echo 'compiler=ready'
    else
      echo 'compiler=missing'
    fi
    echo 'steam=installed'
    ;;
  status)
    if [[ -f "$MARKER" && -f "$ORIGINAL" && -f "$TARGET" ]]; then
      if [[ "$(old_hash)" == "$(file_hash "$TARGET")" ]]; then
        echo 'OpenBottle Steam düzeltmesi etkin.'
      else
        echo 'Steam dosyası değişmiş; düzeltme artık etkin değil.'
      fi
    else
      echo 'OpenBottle Steam düzeltmesi kurulu değil.'
    fi
    ;;
  restore)
    if [[ ! -f "$MARKER" ]]; then echo 'Değişiklik yapılmadı: OpenBottle yedeği bulunamadı.'; exit 0; fi
    [[ -f "$ORIGINAL" && -f "$TARGET" ]] || { echo 'HATA: Düzeltme dosyaları eksik. Elle kurtarma gerekiyor.'; exit 1; }
    if [[ "$(old_hash)" == "$(file_hash "$TARGET")" ]]; then
      mv -f "$ORIGINAL" "$TARGET"
      echo 'Steam yardımcı programı orijinal hâline getirildi.'
    else
      # Steam may have self-repaired / updated its own EXE; never replace it with a stale backup.
      rm -f "$ORIGINAL"
      echo 'Steam yardımcı dosyayı zaten değiştirmiş. Güncel dosya korundu, eski yedek kaldırıldı.'
    fi
    rm -f "$MARKER"
    ;;
  install)
    if [[ -f "$MARKER" && -f "$ORIGINAL" && -f "$TARGET" && "$(old_hash)" == "$(file_hash "$TARGET")" ]]; then
      echo 'Düzeltme zaten etkin. Dosyalar değiştirilmedi.'
      exit 0
    fi
    [[ -f "$TARGET" ]] || { echo 'HATA: steamwebhelper.exe bulunamadı.'; exit 1; }
    if [[ -f "$ORIGINAL" && ! -f "$MARKER" ]]; then
      echo 'HATA: Önceden başka bir yama yapılmış olabilir. Dosyalara dokunulmadı.'
      exit 1
    fi
    if [[ -f "$MARKER" && ! -f "$ORIGINAL" ]]; then
      echo 'HATA: Önceki düzeltmenin yedeği kayıp. Dosyalara dokunulmadı.'
      exit 1
    fi
    COMPILER=''
    for candidate in x86_64-w64-mingw32-gcc /opt/homebrew/bin/x86_64-w64-mingw32-gcc /usr/local/bin/x86_64-w64-mingw32-gcc; do
      if command -v "$candidate" >/dev/null 2>&1; then COMPILER="$(command -v "$candidate")"; break; fi
    done
    if [[ -z "$COMPILER" ]]; then
      echo 'HATA: mingw-w64 bulunamadı. Homebrew varsa Terminal üzerinden brew install mingw-w64 çalıştır.'
      exit 3
    fi
    SOURCE="$(cd "$(dirname "$0")" && pwd)/steamwebhelper-wrapper.c"
    [[ -f "$SOURCE" ]] || { echo 'HATA: Wrapper C kaynak dosyası eksik.'; exit 1; }
    TMP="$(mktemp "${TMPDIR:-/tmp}/openbottle-helper.XXXXXX.exe")"
    trap 'rm -f "$TMP"' EXIT
    "$COMPILER" -DUNICODE -D_UNICODE -municode -O2 -Wall -Wextra -mwindows "$SOURCE" -static -lshell32 -o "$TMP"
    [[ "$(head -c 2 "$TMP")" == 'MZ' ]] || { echo 'HATA: Windows PE dosyası üretilemedi.'; exit 1; }
    if [[ ! -f "$ORIGINAL" ]]; then
      cp -p "$TARGET" "$ORIGINAL"
    elif [[ "$(old_hash)" != "$(file_hash "$TARGET")" ]]; then
      # Steam updated its own helper since we patched it: preserve this newest version.
      cp -p "$TARGET" "$ORIGINAL"
    fi
    cp "$TMP" "$CEF/.openbottle-shim.tmp"
    mv -f "$CEF/.openbottle-shim.tmp" "$TARGET"
    printf 'sha256:%s\n' "$(file_hash "$TARGET")" > "$MARKER"
    echo 'Düzeltme uygulandı. Steam dosyasının orijinal dosyası güvenli biçimde yedeklendi.'
    echo 'Steam güncellenirse düzeltme yeniden uygulanabilir; güncellemeler kapatılmadı.'
    ;;
esac

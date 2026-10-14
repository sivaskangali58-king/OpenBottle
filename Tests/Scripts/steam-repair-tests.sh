#!/bin/bash
# Simulates Steam directory layouts; never touches a real Wine prefix.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/steam-ui-fix.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
PREFIX="$ROOT/one"
CEF="$PREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
mkdir -p "$CEF"
printf 'MZoriginal' > "$PREFIX/drive_c/Program Files (x86)/Steam/Steam.exe"
printf 'MZhelper-original' > "$CEF/steamwebhelper.exe"

probe() { bash "$SCRIPT" probe --prefix "$PREFIX" | head -n 1; }
[[ "$(probe)" == 'state=ready' ]]
# Model installation with an explicit backup, marker and replacement shim.
cp "$CEF/steamwebhelper.exe" "$CEF/steamwebhelper_real.exe"
printf 'MZopenbottle-shim' > "$CEF/steamwebhelper.exe"
printf 'sha256:%s\n' "$(shasum -a 256 "$CEF/steamwebhelper.exe" | awk '{print $1}')" > "$CEF/.openbottle-steam-ui-v1"
[[ "$(probe)" == 'state=active' ]]
# Restoration of active patch must reproduce original bits.
bash "$SCRIPT" restore --prefix "$PREFIX" | grep -q 'orijinal'
cmp -s "$CEF/steamwebhelper.exe" <(printf 'MZhelper-original')
[[ "$(probe)" == 'state=ready' ]]
# Simulate Steam replacing the shim during an update. Restore must preserve the new EXE.
cp "$CEF/steamwebhelper.exe" "$CEF/steamwebhelper_real.exe"
printf 'MZopenbottle-shim' > "$CEF/steamwebhelper.exe"
printf 'sha256:%s\n' "$(shasum -a 256 "$CEF/steamwebhelper.exe" | awk '{print $1}')" > "$CEF/.openbottle-steam-ui-v1"
printf 'MZsteam-updated' > "$CEF/steamwebhelper.exe"
[[ "$(probe)" == 'state=changed' ]]
bash "$SCRIPT" restore --prefix "$PREFIX" | grep -q 'Güncel dosya korundu'
cmp -s "$CEF/steamwebhelper.exe" <(printf 'MZsteam-updated')
[[ "$(probe)" == 'state=ready' ]]
# Existing unknown 3rd party patch must be left untouched.
printf 'MZother-mod' > "$CEF/steamwebhelper_real.exe"
[[ "$(probe)" == 'state=conflict' ]]
if bash "$SCRIPT" install --prefix "$PREFIX" > /dev/null 2>&1; then
    echo 'ERROR: installation should refuse unknown 3rd party patch' >&2
    exit 1
fi
[[ "$(probe)" == 'state=conflict' ]]
echo 'Steam script integration: 8 checks passed'

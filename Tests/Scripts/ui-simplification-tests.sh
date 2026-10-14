#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
FILE=Sources/OpenBottle/MainView.swift
function assert_contains() { grep -Fq "$1" "$FILE" || { echo "FAIL: $1"; exit 1; }; }
assert_contains 'ForEach([OBPage.overview, .games, .bottles]'
assert_contains 'Siyah Ekran Sorunu'
assert_contains 'Gelişmiş Seçenekler'
assert_contains 'Gelişmiş Ayarlar ve Günlükler'
assert_contains 'model.createSteamBottle()'
assert_contains 'model.downloadAndInstallSteam(in: bottle)'
assert_contains 'model.requestSteamLaunch(in: bottle)'
assert_contains 'model.launchGame(entry.game, in: entry.bottle)'
assert_contains 'model.linkGPTKTest()'
assert_contains 'model.setHUD('
assert_contains 'Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")'
! grep -Fq 'ForEach([OBPage.overview, .games, .apps, .bottles, .activity]' "$FILE" || { echo 'FAIL: old navigation'; exit 1; }
echo 'UI simplification: 12 checks passed'

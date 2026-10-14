#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
M=Sources/OpenBottle/WorkspaceModel.swift
U=Sources/OpenBottle/MainView.swift
S=Sources/OpenBottle/SteamRepairSheet.swift
require() { grep -Fq "$2" "$1" || { echo "FAIL $1: $2"; exit 1; }; }
require "$M" 'steamLaunchGate.beginUserLaunch(for: bottle.id)'
require "$M" 'onFinish: { [weak self] _ in self?.steamLaunchGate.finish(for: bottle.id) }'
require "$M" 'func requestSteamLaunch(in bottle: Bottle'
require "$M" 'withSteamClosed(in: bottle)'
require "$M" 'SteamWineShutdown.stop(prefix: prefix, wine: wineExecutable)'
require Sources/OpenBottleCore/SteamWineShutdown.swift 'args: ["wineboot", "-k"]'
require Sources/OpenBottleCore/SteamWineShutdown.swift 'args: ["-k"]'
require "$M" 'func runRepairCompilerInstall'
require "$U" 'model.requestSteamLaunch(in: bottle)'
require "$U" '.sheet(item: $activeModal)'
require "$U" 'activeModal = .steamRepair(bottle)'
require "$U" 'Label("Siyah Ekran Sorunu"'
require "$S" '.disabled(inspecting || working)'
require "$S" 'feedback = statusInfo'
require "$S" '.confirmationDialog(confirmationTitle'
[[ $(grep -cF '.confirmationDialog(' "$S") -eq 1 ]] || { echo "FAIL: more than one repair confirmation dialog"; exit 1; }
[[ $(grep -cF '.sheet(' "$U") -eq 1 ]] || { echo "FAIL: competing modal sheets"; exit 1; }
# Repair must not be disabled just because Steam is still running.
if grep -Fq 'Label("Siyah Ekran Sorunu", systemImage: "wrench.adjustable")' "$U"; then
  line=$(grep -nF 'Label("Siyah Ekran Sorunu", systemImage: "wrench.adjustable")' "$U" | head -1 | cut -d: -f1)
  ! sed -n "${line},$((line+1))p" "$U" | grep -Fq '.disabled(model.isBusy)' || { echo 'FAIL: repair button disabled when Steam runs'; exit 1; }
fi
echo 'Steam loop UI/flow: updated checks passed'

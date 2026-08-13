#!/bin/bash
# Produit les captures App Store iPhone et iPad, dans les deux langues.
#
#   python3 Tools/fake_seestar.py --image fixtures/eclipse_2026-08-12.jpg &
#   bash Tools/make_screenshots.sh
#
# La langue systeme fixe la date de la barre d'etat iPad, la langue de l'app
# est passee au lancement. Les deux doivent concorder.
set -euo pipefail

IPHONE=16A5B79A-8982-444E-87FC-3D7E0046402F   # iPhone 17 Pro Max, 1320x2868
IPAD=E38DB088-FBC3-4EBC-A0D9-9D56C1616DE2     # iPad Pro 13", 2064x2752
APP=fr.thibaut.SeestarCompanion
OUT=docs/appstore/screenshots
DEVICES="$HOME/Library/Developer/CoreSimulator/Devices"

mkdir -p "$OUT"

set_language() {  # udid, code
  xcrun simctl shutdown "$1" 2>/dev/null || true
  local plist="$DEVICES/$1/data/Library/Preferences/.GlobalPreferences.plist"
  /usr/libexec/PlistBuddy -c "Delete :AppleLanguages" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :AppleLanguages array" "$plist"
  /usr/libexec/PlistBuddy -c "Add :AppleLanguages:0 string $2" "$plist"
  /usr/libexec/PlistBuddy -c "Set :AppleLocale $3" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :AppleLocale string $3" "$plist"
}

capture() {  # udid, code, locale, fichier
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1
  xcrun simctl status_bar "$1" override --time "9:41" --batteryState charged \
    --batteryLevel 100 --wifiBars 3 --cellularMode notSupported
  xcrun simctl terminate "$1" "$APP" 2>/dev/null || true
  xcrun simctl launch "$1" "$APP" -seestar.manualHost 127.0.0.1 \
    -AppleLanguages "($2)" -AppleLocale "$3" >/dev/null
  # Laisser le temps a la premiere trame d'arriver et a l'overlay de se poser :
  # capturee trop tot, la telemetrie apparait en double, a mi-animation.
  sleep 25
  xcrun simctl io "$1" screenshot "$OUT/$4" >/dev/null 2>&1
  echo "  $4 : $(sips -g pixelWidth -g pixelHeight "$OUT/$4" | tail -2 | tr -d ' \n')"
}

for pair in "en en_US" "fr fr_FR"; do
  set -- $pair
  code=$1 locale=$2
  echo "langue $code"
  set_language "$IPHONE" "$code" "$locale"
  set_language "$IPAD" "$code" "$locale"
  capture "$IPHONE" "$code" "$locale" "iphone-69-$code.png"
  capture "$IPAD" "$code" "$locale" "ipad-13-$code.png"
done

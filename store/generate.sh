#!/bin/sh
# Captures des stores (App Store 1320 × 2868, Play Store 1080 × 1920, image 1024 × 500).
# 1. Écrans de l'app, rendus avec des données de démonstration (fuseau du matin : la journée
#    commence vers 7 h 45) :
#      TZ=Etc/GMT+N flutter test test/screens/store_test.dart --tags store --run-skipped
#    Les tuiles de carte (OpenStreetMap) vont dans build/store/tiles/{z}/{x}/{y}.png.
# 2. Mise en page : sh store/generate.sh [dossier de sortie]
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-build/store/captures}"
WORK=build/store/layout
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
mkdir -p "$WORK" "$OUT/app-store" "$OUT/play-store"
cp store/serie.html store/feature.html store/Anton-Regular.ttf assets/fonts/PlusJakartaSans.ttf build/store/0*.png "$WORK/"
shot() { "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size="$1" --virtual-time-budget=3000 --screenshot="$2" "file://$PWD/$WORK/$3" 2>/dev/null; }
i=0
for n in 1-journee 2-tournee 3-arrivee-client 4-releve 5-commande 6-chef-en-direct 7-ventes; do
  shot 1320,2868 "$OUT/app-store/$n.png" "serie.html#$i"
  shot 1080,1920 "$OUT/play-store/$n.png" "serie.html?play#$i"
  i=$((i + 1))
done
shot 1024,500 "$OUT/play-store/image-presentation-1024x500.png" feature.html
cp assets/icon/app_icon.png "$OUT/app-store/icone-1024.png"
sips -z 512 512 assets/icon/app_icon.png --out "$OUT/play-store/icone-512.png" > /dev/null
echo "Captures dans $OUT"

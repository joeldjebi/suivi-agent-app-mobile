#!/bin/sh
# APK de production obfusquée : noms de classes et de fonctions illisibles dans l'app,
# symboles gardés à part (build/symbols, jamais publiés) puis envoyés à Sentry pour que
# les erreurs restent lisibles. Jeton Sentry (« Organization Token ») dans .env.sentry :
#   SENTRY_AUTH_TOKEN=sntrys_…
# Usage : sh scripts/build-apk.sh   (depuis apps/mobile)
set -e
cd "$(dirname "$0")/.."

if [ -f .env.sentry ]; then
  set -a; . ./.env.sentry; set +a
fi

VERSION=$(sed -n 's/^version: *//p' pubspec.yaml)
# Même nom de version que celui envoyé par l'app (identifiant Android @ version+build).
export SENTRY_RELEASE="ci.suiviagent.suivi_agent@$VERSION"

rm -rf build/symbols
flutter build apk --release \
  --obfuscate --split-debug-info=build/symbols \
  --extra-gen-snapshot-options=--save-obfuscation-map=build/symbols/obfuscation-map.json

if [ -n "$SENTRY_AUTH_TOKEN" ]; then
  dart run sentry_dart_plugin
  echo "Symboles envoyés à Sentry ($SENTRY_RELEASE)."
else
  echo "ATTENTION : SENTRY_AUTH_TOKEN absent (.env.sentry) : symboles NON envoyés à Sentry."
  echo "Gardez build/symbols de cette version et relancez : dart run sentry_dart_plugin"
fi
echo "APK : build/app/outputs/flutter-apk/app-release.apk ($VERSION)"

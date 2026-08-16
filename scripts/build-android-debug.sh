#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/android/FestTimeAndroid"

if [[ ! -x "./gradlew" ]]; then
  echo "Falta gradlew. Ejecuta: gradle wrapper --gradle-version 8.7"
  exit 1
fi

./gradlew assembleDebug

echo "APK debug generado en android/FestTimeAndroid/app/build/outputs/apk/debug/"

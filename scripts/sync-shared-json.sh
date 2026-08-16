#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_FESTIVALS_DIR="$ROOT_DIR/FestTimeApp/Resources/Festivals"
ANDROID_SHARED_DIR="$ROOT_DIR/android/shared-json"
ANDROID_ASSETS_DIR="$ROOT_DIR/android/FestTimeAndroid/app/src/main/assets/festivals"

mkdir -p "$ANDROID_SHARED_DIR" "$ANDROID_ASSETS_DIR"

cp "$IOS_FESTIVALS_DIR/festivals.json" "$ANDROID_SHARED_DIR/festivals-catalog.json"

for events_file in "$IOS_FESTIVALS_DIR"/*-events.json; do
  base_name="$(basename "$events_file" -events.json)"
  stage_file="$IOS_FESTIVALS_DIR/${base_name}-stage-colors.json"

  if [[ ! -f "$stage_file" ]]; then
    echo "Aviso: falta $stage_file, se omite $base_name"
    continue
  fi

  bundle_file="$ANDROID_SHARED_DIR/${base_name}.bundle.json"

  jq -n \
    --slurpfile catalog "$IOS_FESTIVALS_DIR/festivals.json" \
    --arg id "$base_name" \
    --slurpfile events "$events_file" \
    --slurpfile colors "$stage_file" \
    '{
      festival: ($catalog[0].festivals[] | select(.id == $id)),
      stageColors: $colors[0],
      events: $events[0]
    }' > "$bundle_file"

  echo "Bundle generado: $bundle_file"
done

cp "$ANDROID_SHARED_DIR/festivals-catalog.json" "$ANDROID_ASSETS_DIR/festivals-catalog.json"
cp "$ANDROID_SHARED_DIR"/*.bundle.json "$ANDROID_ASSETS_DIR/"

echo "Sincronizacion completada."

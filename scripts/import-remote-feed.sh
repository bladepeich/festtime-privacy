#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEED_URL="${1:-https://raw.githubusercontent.com/bladepeich/festtime-privacy/main/appstore/remote-festivals-feed.test-additions.json}"

IOS_FESTIVALS_DIR="$ROOT_DIR/FestTimeApp/Resources/Festivals"
TMP_DIR="$ROOT_DIR/.tmp"
FEED_FILE="$TMP_DIR/remote-festivals-feed.json"

mkdir -p "$IOS_FESTIVALS_DIR" "$TMP_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq no esta instalado."
  echo "Instala jq y vuelve a ejecutar este script."
  exit 1
fi

echo "Descargando feed remoto..."
curl -fsSL "$FEED_URL" -o "$FEED_FILE"

echo "Validando formato..."
jq -e '.formatVersion and (.festivals | type == "array")' "$FEED_FILE" >/dev/null

echo "Generando catalogo iOS..."
jq '{ festivals: [ .festivals[].festival ] }' "$FEED_FILE" > "$IOS_FESTIVALS_DIR/festivals.json"

echo "Generando ficheros por festival..."
while IFS= read -r festival_id; do
  jq --arg id "$festival_id" '.festivals[] | select(.festival.id == $id) | .events' "$FEED_FILE" \
    > "$IOS_FESTIVALS_DIR/${festival_id}-events.json"

  jq --arg id "$festival_id" '.festivals[] | select(.festival.id == $id) | .stageColors' "$FEED_FILE" \
    > "$IOS_FESTIVALS_DIR/${festival_id}-stage-colors.json"

done < <(jq -r '.festivals[].festival.id' "$FEED_FILE")

echo "Sincronizando assets Android..."
"$ROOT_DIR/scripts/sync-shared-json.sh"

echo "Importacion completada desde: $FEED_URL"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARCHIVE_PATH="$ROOT_DIR/.build/FestTime.xcarchive"
EXPORT_PATH="$ROOT_DIR/.build/appstore-export"
EXPORT_OPTIONS="$ROOT_DIR/scripts/exportOptions-AppStore.plist"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

xcodebuild -project FestTime.xcodeproj \
  -scheme FestTime \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  archive \
  -archivePath "$ARCHIVE_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

echo "Archive: $ARCHIVE_PATH"
echo "Export:  $EXPORT_PATH"
ls -1 "$EXPORT_PATH"

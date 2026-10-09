#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPICON_DIR="$ROOT_DIR/DeskBox/Assets.xcassets/AppIcon.appiconset"
MASTER="$ROOT_DIR/DeskBox/DeskBoxIcon1024.png"

cd "$ROOT_DIR"

swift scripts/generate_icon.swift

cp "$MASTER" "$APPICON_DIR/icon_1024x1024.png"

sips -z 512 512 "$MASTER" --out "$APPICON_DIR/icon_512x512.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$APPICON_DIR/icon_256x256.png" >/dev/null
sips -z 128 128 "$MASTER" --out "$APPICON_DIR/icon_128x128.png" >/dev/null

swift scripts/generate_small_icons.swift

echo "DeskBox AppIcon assets regenerated."

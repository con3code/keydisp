#!/bin/bash
# KeyDisp 配布用ビルドスクリプト
#
# 使い方:
#   ./scripts/release.sh                # ad-hoc 署名（Developer ID なしで配布する場合）
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
#
# Developer ID で署名した場合は、続けて公証（notarization）を行うと
# ダウンロードした人に Gatekeeper の警告が出なくなります:
#   xcrun notarytool submit dist/KeyDisp-vX.Y.Z.zip --keychain-profile <profile> --wait
#   xcrun stapler staple build/Build/Products/Release/KeyDisp.app
#   （staple 後にもう一度 zip を作り直してください）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | awk '{print $2}')
echo "==> KeyDisp v${VERSION}"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building (Release)"
xcodebuild -project KeyDisp.xcodeproj -scheme KeyDisp \
  -configuration Release -derivedDataPath build \
  clean build | grep -E "error:|warning:|BUILD" || true

APP="build/Build/Products/Release/KeyDisp.app"
if [ ! -d "$APP" ]; then
  echo "error: build failed — $APP not found" >&2
  exit 1
fi

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "==> Code signing (identity: ${IDENTITY})"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep "$APP"

mkdir -p dist
ZIP="dist/KeyDisp-v${VERSION}.zip"
rm -f "$ZIP"
echo "==> Creating ${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Done"
ls -lh "$ZIP"

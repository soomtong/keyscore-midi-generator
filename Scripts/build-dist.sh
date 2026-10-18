#!/usr/bin/env bash
set -euo pipefail

# KeyScore.app 을 빌드해 dist/KeyScore-<버전>.dmg 로 묶는다.
# 버전은 앱의 Info.plist 에서 읽는다 (build-app.sh 에서 정한다).
# 이미 있는 DMG 는 --force 가 없으면 덮어쓰지 않는다 (배포한 파일을 실수로 바꾸지 않게).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/KeyScore.app"
DIST="$ROOT/dist"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        -h|--help)
            echo "사용법: $0 [--force]"
            echo "  --force  이미 있는 dist/KeyScore-<버전>.dmg 를 덮어쓴다"
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $arg" >&2
            exit 1
            ;;
    esac
done

"$ROOT/Scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/KeyScore-$VERSION.dmg"

if [ -e "$DMG" ] && [ "$FORCE" -ne 1 ]; then
    echo "$DMG 이(가) 이미 있습니다. 덮어쓰려면 --force 를 붙이세요." >&2
    exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"  # 끌어다 놓아 설치

mkdir -p "$DIST"
hdiutil create \
    -volname "KeyScore $VERSION" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -ov \
    -quiet \
    "$DMG"

echo "만든 위치: $DMG"
shasum -a 256 "$DMG"

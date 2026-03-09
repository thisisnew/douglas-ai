#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DOUGLAS"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/dist/${APP_NAME}.app"
DMG_OUTPUT="$PROJECT_DIR/dist/${APP_NAME}.dmg"

echo "=== 1/4: Release 빌드 ==="
echo "(첫 빌드는 수 분 걸릴 수 있습니다)"
cd "$PROJECT_DIR"
swift build -c release

EXECUTABLE="$BUILD_DIR/$APP_NAME"
if [ ! -f "$EXECUTABLE" ]; then
    echo "빌드 실패: 실행 파일을 찾을 수 없습니다."
    exit 1
fi
echo "빌드 완료: $EXECUTABLE"

echo ""
echo "=== 2/4: .app 번들 생성 ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 실행 파일 복사
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 앱 아이콘 복사
ICON_FILE="$PROJECT_DIR/Sources/Resources/AppIcon.icns"
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "앱 아이콘 복사 완료"
fi

# SPM 리소스 번들 복사 (Contents/Resources 안에 배치)
RESOURCE_BUNDLE="$PROJECT_DIR/.build/arm64-apple-macosx/release/DOUGLAS_DOUGLAS.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "리소스 번들 복사 완료"
fi

# Info.plist 생성
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleExecutable</key>
    <string>DOUGLAS</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.douglas.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DOUGLAS</string>
    <key>CFBundleDisplayName</key>
    <string>DOUGLAS</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

echo ".app 번들 생성 완료: $APP_BUNDLE"

echo ""
echo "=== 2.5/4: 코드 서명 ==="
# 확장 속성 제거 (코드 서명 오류 방지)
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
# Entitlements 파일 복사 및 서명 시 포함
ENTITLEMENTS_FILE="$PROJECT_DIR/Sources/Resources/DOUGLAS.entitlements"
if [ -f "$ENTITLEMENTS_FILE" ]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE"
    echo "코드 서명 완료 (entitlements 포함)"
else
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "코드 서명 완료"
fi

echo ""
echo "=== 3/4: DMG 생성 ==="
rm -f "$DMG_OUTPUT"

# create-dmg가 있으면 사용, 없으면 hdiutil 사용
if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "DOUGLAS" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 190 \
        --app-drop-link 450 190 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_OUTPUT" \
        "$APP_BUNDLE" || true
else
    # hdiutil 사용 (macOS 기본 제공)
    STAGING="$PROJECT_DIR/dist/dmg-staging"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    cp -R "$APP_BUNDLE" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"

    hdiutil create -volname "DOUGLAS" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG_OUTPUT"

    rm -rf "$STAGING"
fi

echo ""
echo "=== 4/4: 완료! ==="
echo ""
echo "  .app 위치: $APP_BUNDLE"
echo "  .dmg 위치: $DMG_OUTPUT"
echo ""
echo "  실행: open \"$APP_BUNDLE\""
echo "  설치: open \"$DMG_OUTPUT\" → 드래그로 Applications에 복사"

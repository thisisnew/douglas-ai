#!/bin/bash
set -e

# ============================================================
# DOUGLAS 릴리즈 스크립트 (완전 자동)
#
# 사용법: ./scripts/release.sh 0.10.6
#        ./scripts/release.sh 0.10.6 "변경사항 메모"
#
# 이 스크립트가 하는 일:
# 1. 버전 번호를 build-app.sh의 Info.plist에 반영
# 2. build-app.sh 실행 (빌드 + .app + DMG)
# 3. GitHub Release 생성 + DMG 업로드
# 4. GitHub Gist의 douglas-version.json 자동 업데이트
#    (downloadURL = GitHub Release의 DMG 링크)
#
# 필요: gh CLI (brew install gh && gh auth login)
# ============================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GIST_ID="a5bb513ef689ce1338f89ed543e464e0"
REPO="thefarmersfront/douglas"

# --- 인자 확인 ---
VERSION="$1"
RELEASE_NOTES="${2:-버그 수정 및 개선}"

if [ -z "$VERSION" ]; then
    echo "사용법: $0 <버전> [릴리즈노트]"
    echo "예시:   $0 0.10.6 \"Command Safety Layer 추가\""
    exit 1
fi

# gh CLI 확인
if ! command -v gh &> /dev/null; then
    echo "❌ gh CLI가 필요합니다."
    echo "   brew install gh && gh auth login"
    exit 1
fi

echo "========================================"
echo "  DOUGLAS 릴리즈 v${VERSION}"
echo "========================================"
echo ""

# --- 1. Info.plist 버전 업데이트 ---
echo "=== 1/4: 버전 번호 업데이트 ==="
BUILD_SCRIPT="$PROJECT_DIR/scripts/build-app.sh"

python3 -c "
import re
with open('$BUILD_SCRIPT', 'r') as f:
    content = f.read()
content = re.sub(
    r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)',
    r'\g<1>${VERSION}\g<2>',
    content
)
build_num = '${VERSION}'.replace('.', '')
content = re.sub(
    r'(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)',
    r'\g<1>' + build_num + r'\g<2>',
    content
)
with open('$BUILD_SCRIPT', 'w') as f:
    f.write(content)
"
echo "  Info.plist → v${VERSION}"

# --- 2. 빌드 ---
echo ""
echo "=== 2/4: 앱 빌드 ==="
bash "$BUILD_SCRIPT"

DMG_PATH="$PROJECT_DIR/dist/DOUGLAS.dmg"
if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG 생성 실패!"
    exit 1
fi

# --- 3. GitHub Release 생성 + DMG 업로드 ---
echo ""
echo "=== 3/4: GitHub Release 생성 ==="

TAG="v${VERSION}"

# 태그가 이미 있으면 삭제하지 않고 에러
if gh release view "$TAG" --repo "$REPO" &>/dev/null; then
    echo "❌ Release $TAG가 이미 존재합니다."
    echo "   먼저 삭제하거나 다른 버전 번호를 사용하세요."
    exit 1
fi

# Release 생성 + DMG 업로드
gh release create "$TAG" "$DMG_PATH" \
    --repo "$REPO" \
    --title "v${VERSION}" \
    --notes "$RELEASE_NOTES"

echo "  Release 생성 완료: $TAG"

# DMG 다운로드 URL 추출
DOWNLOAD_URL=$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[0].url')
if [ -z "$DOWNLOAD_URL" ]; then
    # fallback: 직접 구성
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/DOUGLAS.dmg"
fi
echo "  DMG URL: $DOWNLOAD_URL"

# --- 4. Gist 업데이트 ---
echo ""
echo "=== 4/4: Gist 버전 정보 업데이트 ==="

PUBLISHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
  "version": "${VERSION}",
  "name": "v${VERSION}",
  "releaseNotes": "${RELEASE_NOTES}",
  "downloadURL": "${DOWNLOAD_URL}",
  "publishedAt": "${PUBLISHED_AT}"
}
EOF

gh gist edit "$GIST_ID" -f "douglas-version.json" "$TEMP_JSON"
rm -f "$TEMP_JSON"

echo "  Gist 업데이트 완료"

echo ""
echo "========================================"
echo "  릴리즈 v${VERSION} 완료!"
echo "========================================"
echo ""
echo "  DMG:     $DMG_PATH"
echo "  Release: https://github.com/${REPO}/releases/tag/${TAG}"
echo "  Gist:    https://gist.github.com/donghuyn-kim/${GIST_ID}"
echo ""
echo "  앱 사용자가 '업데이트 확인' 누르면 v${VERSION}이 표시됩니다."
echo ""

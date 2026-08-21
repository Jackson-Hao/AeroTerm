#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AeroTerm"
BUILD_CONFIG="${1:-release}"
ARCH="${2:-}"
DIST_DIR="${PROJECT_ROOT}/dist"
HOST_ARCH="$(uname -m)"

normalize_arch() {
    case "${1}" in
        x64|x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "arm64" ;;
        "") echo "" ;;
        *)
            echo "❌ 不支持的架构: ${1}（可用 x86_64 / arm64）" >&2
            exit 1
            ;;
    esac
}

ARCH="$(normalize_arch "${ARCH}")"
if [ -z "${ARCH}" ]; then
    ARCH="${HOST_ARCH}"
    SWIFT_ARCH_ARGS=()
else
    SWIFT_ARCH_ARGS=(--arch "${ARCH}")
fi

if [ "${ARCH}" = "${HOST_ARCH}" ]; then
    APP_DIR="${DIST_DIR}/${APP_NAME}.app"
else
    APP_DIR="${DIST_DIR}/${APP_NAME}-${ARCH}.app"
fi
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${PROJECT_ROOT}"

BIN_DIR=$(swift build -c "${BUILD_CONFIG}" "${SWIFT_ARCH_ARGS[@]}" --show-bin-path)
BIN_PATH="${BIN_DIR}/${APP_NAME}"

if [ ! -f "${BIN_PATH}" ]; then
    echo "❌ 错误: 未找到 ${BUILD_CONFIG} 二进制，请先编译: ${BIN_PATH}"
    exit 1
fi

echo "📦 正在打包 ${APP_DIR} (${BUILD_CONFIG}, ${ARCH})..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# SwiftPM may emit @rpath dylibs (e.g. RoyalVNCKit). Finder surfaces a missing
# one as "not supported on this version of macOS" instead of a dyld error.
shopt -s nullglob
for dylib in "${BIN_DIR}"/*.dylib; do
    cp "${dylib}" "${MACOS_DIR}/$(basename "${dylib}")"
    chmod +x "${MACOS_DIR}/$(basename "${dylib}")"
done
shopt -u nullglob

if ls "${BIN_DIR}"/*.bundle 1> /dev/null 2>&1; then
    cp -R "${BIN_DIR}"/*.bundle "${RESOURCES_DIR}/" || true
fi

if [ -d "${PROJECT_ROOT}/Sources/AeroTerm/Resources" ]; then
    cp -R "${PROJECT_ROOT}/Sources/AeroTerm/Resources/"* "${RESOURCES_DIR}/" || true
fi

if [ -f "${PROJECT_ROOT}/Assets/AppIcon.icns" ]; then
    cp "${PROJECT_ROOT}/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
elif [ -f "${PROJECT_ROOT}/scripts/generate_icon.swift" ]; then
    echo "⚠️ 未检测到 AppIcon.icns，尝试重新生成..."
    swift "${PROJECT_ROOT}/scripts/generate_icon.swift"
    iconutil -c icns "${PROJECT_ROOT}/Assets/AppIcon.iconset" -o "${PROJECT_ROOT}/Assets/AppIcon.icns"
    cp "${PROJECT_ROOT}/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
else
    echo "⚠️ 未检测到 AppIcon.icns，打包将没有自定义图标。"
fi

if [ -f "${PROJECT_ROOT}/Assets/AppIcon_1024.png" ]; then
    cp "${PROJECT_ROOT}/Assets/AppIcon_1024.png" "${RESOURCES_DIR}/"
fi

cat << PLIST_EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en-US</string>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>ja</string>
        <string>fr</string>
        <string>de</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.aeroterm.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0-0821</string>
    <key>CFBundleVersion</key>
    <string>20260821</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 AeroTerm. All rights reserved.</string>
</dict>
</plist>
PLIST_EOF

echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "🔐 正在进行本地代码签名..."
codesign --force --deep --sign - "${APP_DIR}"

APP_SIZE=$(du -sh "${APP_DIR}" | awk '{print $1}')

DMG_PATH="${DIST_DIR}/${APP_NAME}-darwin-${ARCH}.dmg"
echo "💿 正在打包 ${DMG_PATH}..."
rm -f "${DMG_PATH}"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/aeroterm-dmg.XXXXXX")"
RW_DMG="${DIST_DIR}/.${APP_NAME}.rw.dmg"
cleanup_dmg() {
    if [ -n "${DMG_MOUNT:-}" ] && [ -d "${DMG_MOUNT}" ]; then
        hdiutil detach "${DMG_MOUNT}" -force >/dev/null 2>&1 || true
    fi
    rm -rf "${STAGE}"
    rm -f "${RW_DMG}"
}
trap cleanup_dmg EXIT

ditto "${APP_DIR}" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"

rm -f "${RW_DMG}"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGE}" \
    -ov \
    -fs HFS+ \
    -format UDRW \
    "${RW_DMG}" >/dev/null

# Leave headroom so Finder can write .DS_Store without growing the image.
hdiutil resize -size 180m "${RW_DMG}" >/dev/null

if [ -d "/Volumes/${APP_NAME}" ]; then
    hdiutil detach "/Volumes/${APP_NAME}" -force >/dev/null 2>&1 || true
fi

DMG_MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}" | awk '/\/Volumes\//{print $3; exit}')"
if [ -z "${DMG_MOUNT}" ] || [ ! -d "${DMG_MOUNT}" ]; then
    echo "❌ 无法挂载临时 DMG"
    exit 1
fi

osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {320, 140, 1040, 580}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        delay 0.4
        set position of item "${APP_NAME}.app" of container window to {160, 205}
        set position of item "Applications" of container window to {500, 205}
        update without registering applications
        delay 1
        close
        open
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "${DMG_MOUNT}" >/dev/null
DMG_MOUNT=""

hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
rm -f "${RW_DMG}"
trap - EXIT
rm -rf "${STAGE}"

DMG_SIZE=$(du -sh "${DMG_PATH}" | awk '{print $1}')

echo "=================================================="
echo "✅ 打包完成"
echo "📍 ${APP_DIR}"
echo "📏 ${APP_SIZE}"
echo "💿 ${DMG_PATH}"
echo "📏 ${DMG_SIZE}"
echo "=================================================="

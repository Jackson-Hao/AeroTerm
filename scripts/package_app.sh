#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AeroTerm"
BUILD_CONFIG="${1:-release}"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${PROJECT_ROOT}"

BIN_DIR=$(swift build -c "${BUILD_CONFIG}" --show-bin-path)
BIN_PATH="${BIN_DIR}/${APP_NAME}"

if [ ! -f "${BIN_PATH}" ]; then
    echo "❌ 错误: 未找到 ${BUILD_CONFIG} 二进制，请先编译: ${BIN_PATH}"
    exit 1
fi

echo "📦 正在打包 ${APP_NAME}.app (${BUILD_CONFIG})..."
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
else
    echo "⚠️ 未检测到 AppIcon.icns，尝试重新生成..."
    swift "${PROJECT_ROOT}/scripts/generate_icon.swift"
    iconutil -c icns "${PROJECT_ROOT}/Assets/AppIcon.iconset" -o "${PROJECT_ROOT}/Assets/AppIcon.icns"
    cp "${PROJECT_ROOT}/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
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

ARCH="$(uname -m)"
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

mkdir -p "${STAGE}/.background"
python3 - "${STAGE}/.background/background.png" <<'PY'
import struct, sys, zlib
from pathlib import Path

path = Path(sys.argv[1])
w, h = 1440, 800

def pixel(x, y):
    # Navy grid matching the app icon
    gx = 11 + (3 if (x // 8) % 2 == (y // 8) % 2 else 0)
    gy = 18 + (4 if (x // 8) % 2 == (y // 8) % 2 else 0)
    gz = 36 + (6 if (x // 8) % 2 == (y // 8) % 2 else 0)
    r, g, b = gx, gy, gz
    # Soft cyan chevron pointing toward Applications
    cx, cy = w * 0.5, h * 0.52
    dx, dy = x - cx, y - cy
    # Two bars of a ">"
    def near_line(x0, y0, x1, y1, thick):
        vx, vy = x1 - x0, y1 - y0
        llen = (vx * vx + vy * vy) ** 0.5 or 1
        t = max(0.0, min(1.0, ((x - x0) * vx + (y - y0) * vy) / (llen * llen)))
        px, py = x0 + t * vx, y0 + t * vy
        return (x - px) ** 2 + (y - py) ** 2 <= thick * thick
    if near_line(cx - 36, cy - 48, cx + 44, cy, 7) or near_line(cx + 44, cy, cx - 36, cy + 48, 7):
        r, g, b = 40, 210, 235
    return r, g, b, 255

raw = bytearray()
for y in range(h):
    raw.append(0)
    for x in range(w):
        raw.extend(pixel(x, y))

def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
path.write_bytes(
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", ihdr)
    + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    + chunk(b"IEND", b"")
)
PY

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

chflags hidden "${DMG_MOUNT}/.background" || true

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
        set background picture of theViewOptions to file ".background:background.png"
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

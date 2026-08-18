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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

echo "=================================================="
echo "✅ 打包完成"
echo "📍 ${APP_DIR}"
echo "📏 ${APP_SIZE}"
echo "=================================================="

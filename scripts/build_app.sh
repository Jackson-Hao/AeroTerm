#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AeroTerm"
BUILD_CONFIG="${1:-release}"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "=================================================="
echo "🚀 正在构建 ${APP_NAME} (${BUILD_CONFIG} 模式)..."
echo "=================================================="

# 1. 编译 Release 二进制文件
cd "${PROJECT_ROOT}"
swift build -c "${BUILD_CONFIG}"

BIN_DIR=$(swift build -c "${BUILD_CONFIG}" --show-bin-path)
BIN_PATH="${BIN_DIR}/${APP_NAME}"

if [ ! -f "${BIN_PATH}" ]; then
    echo "❌ 错误: 未找到编译生成的二进制文件: ${BIN_PATH}"
    exit 1
fi

echo "📦 正在组织 macOS .app 应用包结构..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 2. 拷贝可执行文件
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# 3. 拷贝 SPM 生成的 Resource Bundle 与原生 .lproj 资源包
if ls "${BIN_DIR}"/*.bundle 1> /dev/null 2>&1; then
    cp -R "${BIN_DIR}"/*.bundle "${RESOURCES_DIR}/" || true
fi

# 拷贝标准 .lproj 多语言资源包
if [ -d "${PROJECT_ROOT}/Sources/AeroTerm/Resources" ]; then
    cp -R "${PROJECT_ROOT}/Sources/AeroTerm/Resources/"* "${RESOURCES_DIR}/" || true
fi

# 4. 拷贝图标
if [ -f "${PROJECT_ROOT}/Assets/AppIcon.icns" ]; then
    cp "${PROJECT_ROOT}/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
else
    echo "⚠️ 提示: 未检测到 AppIcon.icns，尝试重新生成..."
    swift "${PROJECT_ROOT}/scripts/generate_icon.swift"
    iconutil -c icns "${PROJECT_ROOT}/Assets/AppIcon.iconset" -o "${PROJECT_ROOT}/Assets/AppIcon.icns"
    cp "${PROJECT_ROOT}/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

if [ -f "${PROJECT_ROOT}/Assets/AppIcon_1024.png" ]; then
    cp "${PROJECT_ROOT}/Assets/AppIcon_1024.png" "${RESOURCES_DIR}/"
fi

# 5. 生成 Info.plist
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
    <string>14.0</string>
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

# 6. 生成 PkgInfo
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# 7. 本地 ad-hoc 代码签名
echo "🔐 正在进行本地代码签名..."
codesign --force --deep --sign - "${APP_DIR}"

APP_SIZE=$(du -sh "${APP_DIR}" | awk '{print $1}')

echo "=================================================="
echo "✅ 构建完成！"
echo "📍 应用路径: ${APP_DIR}"
echo "📏 包体积大小: ${APP_SIZE}"
echo "💡 提示: 可以在终端输入 'open ${APP_DIR}' 快速启动体验"
echo "=================================================="

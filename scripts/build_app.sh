#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AeroTerm"
BUILD_CONFIG="${1:-release}"

echo "=================================================="
echo "🚀 正在构建 ${APP_NAME} (${BUILD_CONFIG})..."
echo "=================================================="

cd "${PROJECT_ROOT}"
"${PROJECT_ROOT}/scripts/patch_deps.sh"
swift build -c "${BUILD_CONFIG}"

# 编译成功后自动打包 .app
exec "${PROJECT_ROOT}/scripts/package_app.sh" "${BUILD_CONFIG}"

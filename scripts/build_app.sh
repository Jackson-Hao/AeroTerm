#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AeroTerm"
BUILD_CONFIG="${1:-release}"
ARCH="${2:-}"

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

if [ -n "${ARCH}" ]; then
    echo "=================================================="
    echo "🚀 正在构建 ${APP_NAME} (${BUILD_CONFIG}, ${ARCH})..."
    echo "=================================================="
else
    echo "=================================================="
    echo "🚀 正在构建 ${APP_NAME} (${BUILD_CONFIG})..."
    echo "=================================================="
fi

cd "${PROJECT_ROOT}"
"${PROJECT_ROOT}/scripts/patch_deps.sh"

if [ -n "${ARCH}" ]; then
    swift build -c "${BUILD_CONFIG}" --arch "${ARCH}"
    exec "${PROJECT_ROOT}/scripts/package_app.sh" "${BUILD_CONFIG}" "${ARCH}"
else
    swift build -c "${BUILD_CONFIG}"
    exec "${PROJECT_ROOT}/scripts/package_app.sh" "${BUILD_CONFIG}"
fi

#!/bin/bash
# 在 Apple Silicon 上交叉编译 Intel (x86_64) 发行包，并打出 .app + DMG。
# 产物：
#   dist/AeroTerm-x86_64.app
#   dist/AeroTerm-darwin-x86_64.dmg  （盘内仍是 AeroTerm.app + Applications）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/build_app.sh" "${1:-release}" x86_64

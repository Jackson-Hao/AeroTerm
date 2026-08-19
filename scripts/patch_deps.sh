#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

swift package resolve >/dev/null

PATCH_SRC="${PROJECT_ROOT}/Vendor/patches/royalvnc/VNCConnection+DesktopSize.swift"
CHECKOUT_ROOT="${PROJECT_ROOT}/.build/checkouts/royalvnc"

if [ -f "${PATCH_SRC}" ] && [ -d "${CHECKOUT_ROOT}/Sources/RoyalVNCKit/SDK/Connection" ]; then
    cp "${PATCH_SRC}" "${CHECKOUT_ROOT}/Sources/RoyalVNCKit/SDK/Connection/VNCConnection+DesktopSize.swift"
fi

python3 - <<'PY'
from pathlib import Path
import os
root = Path(".build/checkouts/royalvnc/Sources/RoyalVNCKit")
conn = root / "SDK/Connection/VNCConnection.swift"
view = root / "SDK/UI/FramebufferView/macOS/VNCCAFramebufferView.swift"
for path in (conn, view):
    os.chmod(path, 0o644)

text = conn.read_text()
if "AeroVNCTune.compressionEncoding" not in text:
    text = text.replace(
        "\t\t\tVNCPseudoEncodingType.compressionLevel6.rawValue",
        "\t\t\tAeroVNCTune.compressionEncoding(for: self)",
        1,
    )
    text = text.replace(
        "\t\t\tencs.append(VNCPseudoEncodingType.jpegQualityLevel6.rawValue)",
        "\t\t\tencs.append(AeroVNCTune.jpegEncoding(for: self))",
        1,
    )
    conn.write_text(text)

text = view.read_text()
if "aeroShouldSkipRender" not in text:
    text = text.replace(
        "\tfunc displayLinkDidUpdate(_ displayLink: DisplayLink) {\n\t\trequestRender()\n\t}",
        "\tfunc displayLinkDidUpdate(_ displayLink: DisplayLink) {\n\t\tif aeroShouldSkipRender() { return }\n\t\trequestRender()\n\t}",
        1,
    )
    old = """        guard !settings.useDisplayLink,
              displayLink == nil else {
            return
        }

        requestRender()"""
    new = """        guard !settings.useDisplayLink,
              displayLink == nil else {
            return
        }
        if aeroShouldSkipRender() { return }

        requestRender()"""
    if old in text:
        text = text.replace(old, new, 1)
    view.write_text(text)
PY

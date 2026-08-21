.DEFAULT_GOAL := app

.PHONY: app debug release package x64

# 默认：编译 Release 并自动打包 dist/AeroTerm.app
app release:
	./scripts/build_app.sh release

debug:
	./scripts/build_app.sh debug

# 仅打包已有编译产物（不再编译）
package:
	./scripts/package_app.sh release

# Intel / x86_64 交叉编译并打包（不覆盖本机 arm64 的 dist/AeroTerm.app）
x64:
	./scripts/build_app_x64.sh release

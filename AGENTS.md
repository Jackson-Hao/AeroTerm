# AeroTerm 协作约定

## 编译必须打包

本项目的可交付物是 `dist/AeroTerm.app`，不是 `.build` 里的裸二进制。

- 用户说「编译」「编译 APP」「build」时，一律跑 `./scripts/build_app.sh release`（明确要求 debug 才用 `debug`）。
- 不要只执行 `swift build` 就结束。即便中途用 `swift build` 做语法检查，成功后也必须再跑 `./scripts/package_app.sh`（或完整 `build_app.sh`）打出 `.app`。
- `build_app.sh` 会在 `swift build` 成功后自动调用 `package_app.sh`。
- 等价入口：`make` / `make app`。

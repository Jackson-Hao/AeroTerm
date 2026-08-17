# AeroTerm 技术演进路线图 (Multi-Phase Roadmap)

## ✅ Phase 1: 核心框架、UI体系与基础网络/硬件工具 (已完成)
- [x] **现代原生 UI 框架**：macOS 原生毛玻璃 Sidebar (`.ultraThinMaterial`)、全屏沉浸命令行。
- [x] **VMware 风格 4 步向导**：协议类型选择 -> 基础网络与凭证配置 -> 高级选项 -> 概览确认。
- [x] **左侧栏二分切换**：左侧“已保存”与右侧“当前连接”无缝切换。
- [x] **全屏顶栏自动隐藏**：进入全屏自动隐藏顶栏与侧边栏，鼠标移至顶边缘平滑滑出退出。
- [x] **TCP 调试工作台**：客户端/服务端双模式、Hex/UTF-8 文本、实时吞吐统计、自动 Echo。
- [x] **UDP 调试工作台**：单播 (Unicast)、多播组 (Multicast, 如 239.255.0.1)、广播 (Broadcast)。
- [x] **串口监视器 (Serial)**：自动探测 `/dev/cu.*`、波特率自适应切换 (9600~921600)、Hex/ASCII 监听与发包、打不开前置安全拦截、零闪退生命周期。
- [x] **Telnet 客户端**：Socket 字符流连接与基础 IAC 协商过滤。
- [x] **独立 `.app` 打包工具链**：自动化 Release 编译、Asset 组装、代码签名，包体积仅 **4.0 MB**。

---

## ⏳ Phase 2: SSH 终端引擎与 SFTP 传输深度集成 (下一阶段)
- [ ] **终端渲染引擎**：集成 [`SwiftTerm`](https://github.com/migueldeicaza/SwiftTerm) 或基于 Metal/CoreText 打造高性能 xterm-256color 终端渲染层。
- [ ] **SSH 协议栈**：集成 `Citadel` (SwiftNIO SSH) 或 `libssh2` 静态库，支持 PTY 会话、密码/私钥 (RSA/Ed25519) 认证、会话断线重连。
- [ ] **SFTP 文件传输管理器**：实现目录树遍历、文件多线程并发传输、断点续传、文件拖拽上传下载 (Drag & Drop)。

---

## ⏳ Phase 3: SSH-X11 图形转发与高级网络隧道
- [ ] **X11 Forwarding**：实现 SSH X11 渠道代理转发 (`$DISPLAY`)，对接本地 XQuartz 或轻量 X11 桥接协议。
- [ ] **端口转发与隧道 (Port Forwarding)**：本地端口转发 (Local -L)、远端端口转发 (Remote -R)、动态 SOCKS5 代理 (-D)。

---

## ⏳ Phase 4: VNC 与 FreeRDP 远程桌面
- [ ] **VNC 客户端**：集成 `libvncclient`，基于 Metal 处理 RFB 协议帧缓冲渲染与键盘鼠标事件映射。
- [ ] **RDP 客户端**：静态交叉编译集成 `FreeRDP` C 核心库，Swift 桥接 RemoteFX 位图硬解、NLA/CredSSP 认证与剪贴板双向同步。

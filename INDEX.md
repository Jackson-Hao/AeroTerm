# AeroTerm 项目全量架构索引与协同指南 (Project Master Index)

> **版本**：v1.0 (Phase 1 生产交付态)  
> **语言 / 运行时**：Swift 6 (Strict Concurrency Safe) + SwiftUI + AppKit  
> **底层终端后端**：SwiftTerm (by Miguel de Icaza)  
> **目标系统**：macOS 14.0+ (Apple Silicon & Intel)  
> **打包状态**：Release 签名通过 (26 MB)，0 Errors, 0 Warnings  

---

## 🧭 项目核心架构总览 (Architecture Overview)

```
AeroTerm/
├── Package.swift                             # SwiftPM 清单 (集成 SwiftTerm 1.18.0)
├── Sources/AeroTerm/
│   ├── AeroTermApp.swift                     # App 顶层入口、热键注册与窗口挂载
│   ├── Models/
│   │   ├── SessionModels.swift               # 会话、4大分类、10种协议与网络日志模型
│   │   ├── AppSettings.swift                 # 外观、Cascadia Code NF 字体自动注册
│   │   └── AgentCLIModel.swift               # 6 大 Agent CLI 规范配置与环境模型
│   ├── Theme/
│   │   ├── ThemeModel.swift                  # ANSI 16 色调色板与主题模型
│   │   ├── ThemeManager.swift                # 全局响应式主题热切换引擎
│   │   └── Presets/
│   │       ├── AeroDarkTheme.swift           # Aero Dark (Midnight Neo) 默认暗色
│   │       └── AeroLightTheme.swift          # Aero Light (Solar Mist) 浅色
│   ├── Services/
│   │   ├── AgentCLIService.swift             # XML 动态解析与配置扩展服务 (XMLParser)
│   │   ├── TCPService.swift                  # 原生 TCP 客户端与服务端调试引擎
│   │   ├── UDPService.swift                  # 原生 UDP 单播/组播/广播调试引擎
│   │   ├── SerialService.swift               # macOS IOKit 原生串口通信引擎
│   │   ├── TelnetService.swift               # 原生 Telnet 终端通信引擎
│   │   └── HTTPService.swift                 # REST API 原生网络接口调试引擎
│   ├── ViewModels/
│   │   └── SessionManager.swift              # 顶层会话、窗口路由与多协议引擎生命周期中枢
│   ├── Views/
│   │   ├── MainView.swift                    # 主窗口尺寸平滑展开 (1180x720) 与全屏控制器
│   │   ├── SidebarView.swift                 # 极简二分原生侧边栏 (Saved / Active)
│   │   ├── WelcomeHomeView.swift             # 主工作台欢迎主页
│   │   ├── WorkspaceView.swift               # 动态工作区多协议路由器
│   │   ├── Splash/
│   │   │   └── XcodeStartupWindowView.swift  # 780x480 纯正 Xcode 独立欢迎窗口
│   │   ├── Wizard/
│   │   │   └── NewConnectionWizardView.swift # 840x600 左右两栏防折行新建向导
│   │   ├── Settings/
│   │   │   └── SettingsView.swift            # 原生偏好设置窗口
│   │   ├── Tools/
│   │   │   ├── SwiftTermContainerView.swift  # 基于 SwiftTerm 的通用开源终端容器
│   │   │   ├── AgentCLIToolView.swift        # Agent CLI 交互工作台 (支持 exit 自动关闭)
│   │   │   ├── TCPToolView.swift             # TCP 调试工作台 (双向 Hex/ASCII)
│   │   │   ├── UDPToolView.swift             # UDP 调试工作台
│   │   │   ├── SerialToolView.swift          # 串口调试工作台
│   │   │   ├── TelnetToolView.swift          # Telnet 调试工作台
│   │   │   └── HTTPToolView.swift            # HTTP 接口调试工作台
│   │   └── Common/
│   │       └── RemoteIconView.swift          # 离线 256x256 Agent 高清图标组件
│   └── Resources/
│       ├── agent_cli_configs.xml             # 6 大 Agent CLI 核心 XML 配置文件
│       ├── en-US.lproj/Localizable.strings   # 100% 覆盖的本地化文本
│       ├── Fonts/                            # Cascadia Code NF 4 大完整字重 (OTF)
│       └── Icons/                            # 6 大 Agent 256x256 离线高清 PNG 图标
└── scripts/
    └── build_app.sh                          # 生产构建、资源复制与本地代码签名脚本
```

---

## 🔄 最新核心里程碑交付汇总 (Recent Accomplishments)

### 1. 独立 Xcode 风格启动窗口 (780 x 480)
- 底层接入 `NSWindowDelegate`（`windowWillResize` & `customWindowsToEnterFullScreen`），彻底禁用了窗口拉伸、双击放大与 `Globe+F` 全屏；
- macOS 原生左上角单红灯关闭按钮（隐藏黄绿灯）；
- 140x140 高清大 Logo + 300x300 环境弥散背光 + 毛玻璃右侧最近连接直连。

### 2. 840 x 600 专业向导与 4 大业务分类
- **四大分类**：Remote Connection, Debugging Tools, Remote Desktop, AI & Agent CLI；
- 左侧 240px 专属防折行导航栏，任何选中状态绝对保持单行对齐；
- 100% 覆盖全工程 82 处本地化 key，彻底修复退出弹窗与描述文本。

### 3. 6 大核心 AI Agent CLI 预设与 XML 动态架构
- 标准预设：Claude Code CLI, Codex CLI, Antigravity CLI (AGY), Grok CLI, Hermes CLI, Custom Agent CLI；
- XML 动态解析与环境注入（`agent_cli_configs.xml`）；
- 预先生成并内嵌 6 大 256x256 离线高清 PNG 图标库（0 网络依赖）。

### 4. 接入开源终端模拟器后端 (SwiftTerm)
- 引入 Miguel de Icaza 开发的纯 Swift VT100 / xterm 终端引擎；
- 内核原生 PTY 伪终端控制，彻底解决 Go Bubbletea / Inquirer / Claude Code 的 `/dev/tty` 报错；
- 完整支持 Alternate Screen Buffer、Vim、Nano、Top、Htop、24位真彩色与鼠标交互；
- 支持终端输入 `exit` 或 `Ctrl+D` 毫秒级捕获并自动平滑关闭当前工作区页面；
- 具备与 Phase 2 SSH 远程协议通用的终端复用能力。

### 5. 独立主题与 Cascadia Code NF Nerd Font
- 独立 `Theme/` 模块，提供 Aero Dark / Aero Light 预设调色板与全局热切换；
- 默认内嵌 Cascadia Code NF 4 大字重并支持 CoreText 自动注册。

---

## 🛠️ 构建与发布规范 (Build & Run)

```bash
# 1. 生产模式编译、打包与签名
./scripts/build_app.sh release

# 2. 启动独立 macOS .app 应用
open ./dist/AeroTerm.app
```

<div align="center">
  <img src="Assets/readme-hero.png" alt="AeroTerm" width="100%" />
  <p>
    <a href="README.md">English</a>
    ·
    <a href="README.zh-CN.md">中文-中国（zh-cn）</a>
  </p>
  <p>
    <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111827?logo=apple&logoColor=white" />
    <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" />
    <img alt="License MIT" src="https://img.shields.io/badge/License-MIT-22c55e" />
    <img alt="Version 1.0-0821" src="https://img.shields.io/badge/version-1.0--0821-38bdf8" />
  </p>
  <p><strong>一个应用，管住所有会话。</strong><br />为 Mac 而生，不是套了壳的浏览器。</p>
</div>

---

AeroTerm 是给长期待在远程主机、实验台和本地 Agent CLI 里的人用的原生 macOS 工作台。SSH、SFTP、Telnet、串口、TCP/UDP、HTTP、VNC、RDP，以及常用编程 Agent，都放在同一套工作区里——可以分栏、弹出窗口、挂起或重连，而不必在五六个软件之间跳。

免费、开源。密码和私钥口令保存在 macOS 钥匙串中；拿不到钥匙串保护，AeroTerm 不会启动。

**界面语言：** English · 中文-中国（zh-cn） · 中文-台灣（zh-tw） · 日本語 · Français · Deutsch · 也可跟随系统。

---

## 为什么选 AeroTerm

市面上不少「全能」远程工具是 Electron 套壳：体积大、内存沉，在 Mac 上总差一点味道。专业终端把 shell 做到极致，却不管串口、接口调试和远程桌面。串口助手、API 客户端、远程桌面各自只做一件事，Dock 上越堆越多。

AeroTerm 走另一条路：

| | |
| --- | --- |
| **原生，而不是套壳** | SwiftUI，面向 macOS 15，不是 Chromium。冷启动快，多开会话时界面仍然干净。 |
| **一件事一个窗口就够** | 远程 shell、文件传输、UART 板、报文调试、HTTP、Windows/Linux 桌面、Agent CLI，共用侧边栏、最近记录和布局。 |
| **连接和账号分开** | 连接配置记「去哪」；账号记「你是谁」。一份登录可以挂到多台机器。 |
| **会话可以留下来** | 分栏、把会话拖到独立窗口、挂起而不是关掉标签、链路中断后重连。 |
| **秘密留在这台 Mac 上** | 钥匙串保存密码和私钥口令——没有强制云同步，也不绑定付费保险箱。 |
| **开源，没有付费墙** | MIT 许可。没有「专业版协议包」，没有席位费，用完整功能不必订阅。 |

---

## 对比

| | **AeroTerm** | Termius | Electerm | iTerm2 | 常见串口 / API / 远程桌面工具 |
| --- | :---: | :---: | :---: | :---: | --- |
| **Mac 体验** | 原生 SwiftUI | 跨平台 / Electron | Electron | 原生 | 各异 |
| **SSH + SFTP** | ● | ● | ● | 只能在 shell 里跑 ssh | 往往只做其中一项 |
| **串口（终端 + 收发测试）** | ● | | 有限 | | 专用串口助手 |
| **TCP / UDP 工作台** | ● | | | | 专用抓包/调试工具 |
| **HTTP 客户端与本地服务** | ● | | | | Postman 一类 |
| **VNC + RDP** | ● | 另购或更高套餐 | ● | | 一种协议一个查看器 |
| **在真实终端里跑 AI Agent CLI** | ● | | | 需自己配 | 需自己配 |
| **许可** | MIT，免费 | 免费增值 | 开源 | 开源 | 多为收费 |
| **「全放进一个窗口」的代价** | 一个应用 | 多个产品或付费计划 | 一个较重的应用 | 再装一堆工具 | 再装一堆工具 |

AeroTerm 不打算取代完整 IDE、团队云保险库，或带企业策略的商业连接管理器。它面向个人和小团队：要一个够快的 Mac 工作台，覆盖日常会用到的协议。

---

## 能做什么

<table>
<tr>
<td width="50%" valign="top">

### 远程连接

| | |
| --- | --- |
| **SSH** | 彩色远程终端。密码或私钥登录、主机密钥校验，会话断开可重连。 |
| **SFTP** | 在同一安全通道上浏览、上传、下载、重命名和搜索。支持拖放上传，进度可取消。 |
| **Telnet** | 面向老旧服务器、实验设备和交换机的纯文本控制台。 |

</td>
<td width="50%" valign="top">

### 调试工具

| | |
| --- | --- |
| **TCP** | 客户端与服务端。实时收发、文本或 HEX、编码、定时重发、发文件，可选回显与广播。 |
| **UDP** | 单播、组播或广播，带 HEX 查看。 |
| **串口** | USB-UART 与 RS-232。**Shell** 开完整终端，或 **Tester** 做经典上下分栏收发。 |
| **HTTP** | 客户端（HTTP/HTTPS/WebSocket）和快速本地服务。 |

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 远程桌面

| | |
| --- | --- |
| **VNC** | 图形桌面，剪贴板同步，画质与刷新率预设。 |
| **RDP** | Windows 工作站或服务器，同样的显示控制与重连。 |

</td>
<td width="50%" valign="top">

### AI 与 Agent CLI

在真实终端标签里运行本地 Agent，可指定工作目录和可选环境变量：

Claude Code · Codex · Antigravity · Grok · Hermes · 或任意本地程序。

</td>
</tr>
</table>

---

## 开始使用

1. 打开 `dist/AeroTerm.app`，或从 `dist/AeroTerm-darwin-arm64.dmg` 安装后在「应用程序」里启动。
2. 系统询问时允许钥匙串访问。
3. 新建连接、进入工作台，或点一条最近主机。

`⌘N` 新建连接 · `⌘,` 设置 · `⌃⌘S` 侧边栏 · `⇧⌘1` 欢迎窗口

需要 **macOS 15** 或更高版本。

---

## 开放源代码许可

AeroTerm 以 [MIT License](LICENSE) 发布。

### 使用的开源库

AeroTerm 使用了下列开源项目。这些组件仍受其原许可约束；相应声明随源码提供，并在许可要求时随应用分发。

| 项目 | 许可 | 用途 |
| --- | --- | --- |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | 终端模拟 |
| [Citadel](https://github.com/orlandos-nl/Citadel) | MIT | SSH 客户端 |
| [RoyalVNCKit](https://github.com/royalapplications/royalvnc) | MIT | VNC 客户端 |
| [RDPKit](Vendor/RDPKit) | MIT | RDP 客户端 |
| [SwiftNIO](https://github.com/apple/swift-nio) / [SwiftNIO SSL](https://github.com/apple/swift-nio-ssl) | Apache-2.0 | 网络（经 Citadel、RDPKit） |
| [SwiftNIO SSH](https://github.com/Wellz26/swift-nio-ssh) | Apache-2.0 | SSH 传输（经 Citadel） |
| [Swift Crypto](https://github.com/apple/swift-crypto) | Apache-2.0 | 密码学（经 Citadel / RoyalVNC） |
| [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift) | MIT | 密码学（经 RoyalVNC） |
| [Cascadia Code NF](https://github.com/microsoft/cascadia-code) | SIL Open Font License 1.1 | 内置等宽字体 |

感谢以上项目的作者与维护者。

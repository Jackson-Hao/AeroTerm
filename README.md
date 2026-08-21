# AeroTerm

[English](README.md) · [中文-中国（zh-cn）](README.zh-CN.md)

<div align="center">
  <img src="Assets/AppIcon_1024.png" width="128" height="128" alt="AeroTerm Icon" />
  <h3>A native macOS workbench for SSH, files, lab tools, remote desktops, and AI agent CLIs</h3>
  <p>One app. Every session. Built for the Mac, not a browser in a box.</p>
</div>

---

## What it is

AeroTerm is a native macOS app for people who live on remote hosts, lab benches, and local agent CLIs. SSH, SFTP, Telnet, serial, TCP/UDP, HTTP, VNC, RDP, and popular coding agents all sit in the same workspace — split, popped out, suspended, or reconnected without scattering into five other programs.

It is free and open source. Passwords and private-key passphrases stay in the macOS Keychain; AeroTerm will not start until it can protect them.

**Languages:** English, 中文-中国（zh-cn）, 中文-台湾（zh-tw）, 日本語, Français, Deutsch, or follow the system language.

---

## Why AeroTerm

Most “all-in-one” remote tools are Electron shells: large on disk, heavy in RAM, and never quite at home on the Mac. Dedicated terminals are excellent at shells and nothing else. Serial testers, API clients, and remote-desktop apps each solve one job and leave the rest on another dock icon.

AeroTerm is the opposite bet:

- **Native, not wrapped.** SwiftUI on macOS 15, not Chromium. Cold start stays snappy; the workbench stays calm when many sessions are open.
- **One place for the whole job.** Remote shells, file transfer, UART boards, packet debugging, HTTP APIs, Windows/Linux desktops, and agent CLIs share the same sidebar, recents, and layout.
- **Connections and logins are separate.** A host profile remembers *where*; an account remembers *who you are*. Reuse one login across many machines without copying passwords around.
- **Sessions you can keep.** Split panes, detach a session to its own window, suspend instead of killing the tab, reconnect when the link drops.
- **Secrets stay on the Mac.** Keychain-backed passwords and key passphrases — no cloud vault unless you choose to put one there yourself.
- **Open source, no paywall.** MIT licensed. No “Pro” protocol pack, no seat count, no sync subscription required to use the app.

---

## How it compares

| | **AeroTerm** | Termius | Electerm | iTerm2 | Typical serial / API / RDP apps |
| --- | --- | --- | --- | --- | --- |
| **Mac feel** | Native SwiftUI | Cross-platform / Electron | Electron | Native | Mixed |
| **SSH + SFTP** | Yes | Yes | Yes | SSH via the shell | Usually one or the other |
| **Serial (shell + tester)** | Yes | No | Limited | No | Serial-only tools |
| **TCP / UDP workbench** | Yes | No | No | No | Dedicated packet tools |
| **HTTP client & local server** | Yes | No | No | No | Postman and friends |
| **VNC + RDP** | Yes | Extra product / plan | Yes | No | Viewer per protocol |
| **AI agent CLIs in a real terminal** | Yes | No | No | Manual | Manual |
| **License** | MIT, free | Freemium | Open source | Open source | Often paid |
| **Cost of “everything in one window”** | One app | Several products or a paid plan | One heavy app | Many extra apps | Many extra apps |

AeroTerm is not trying to replace a full IDE, a cloud team vault, or a commercial connection manager with enterprise policy. It is for individuals and small teams who want a fast Mac workbench that covers the protocols they actually use.

---

## What you can do

### Remote connection

| Tool | Role |
| --- | --- |
| **SSH** | Color remote terminal. Password or private key, host-key checking, reconnect if the session drops. |
| **SFTP** | Browse, upload, download, rename, and search over the same secure channel. Drag-and-drop upload with a cancellable progress bar. |
| **Telnet** | Plain-text console for older servers, lab gear, and switches. |

### Debugging tools

| Tool | Role |
| --- | --- |
| **TCP client / server** | Live stream, text or HEX, encodings, timed repeat, file send, optional echo and broadcast. |
| **UDP** | Unicast, multicast, or broadcast, with a HEX inspector. |
| **Serial** | USB-UART and RS-232. **Shell** for a full terminal, or **Tester** for classic send/receive with timestamps and HEX. |
| **HTTP client** | HTTP, HTTPS, and WebSocket: method, URL, params, headers, body, auth, pretty JSON. |
| **HTTP server** | A quick local listener that echoes or returns a custom status and body. |

### Remote desktop

| Tool | Role |
| --- | --- |
| **VNC** | Graphical desktop with clipboard sync, quality and refresh presets. |
| **RDP** | Windows workstation or server, with the same display controls and reconnect. |

### AI & agent CLI

Run a local agent in a real terminal tab, with working directory and optional environment:

Claude Code, Codex, Antigravity, Grok, Hermes, or any custom binary you point at.

---

## Getting started

1. Open `dist/AeroTerm.app`, or AeroTerm from Applications after you install it.
2. Grant Keychain access when macOS asks.
3. Create a connection, open the workbench, or click a recent host.

**⌘N** new connection · **⌘,** settings · **⌃⌘S** sidebar · **⇧⌘1** welcome window.

Requires **macOS 15** or later.

---

## License

AeroTerm is released under the [MIT License](LICENSE).

### Third-party open source

AeroTerm uses the following open-source projects. Their licenses apply to those components; copies of the notices ship with the sources and, where the license requires it, with the app.

| Project | License | Used for |
| --- | --- | --- |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | Terminal emulator |
| [Citadel](https://github.com/orlandos-nl/Citadel) | MIT | SSH client |
| [RoyalVNCKit](https://github.com/royalapplications/royalvnc) | MIT | VNC client |
| [RDPKit](Vendor/RDPKit) | MIT | RDP client |
| [SwiftNIO](https://github.com/apple/swift-nio) / [SwiftNIO SSL](https://github.com/apple/swift-nio-ssl) | Apache-2.0 | Networking (via Citadel and RDPKit) |
| [SwiftNIO SSH](https://github.com/Wellz26/swift-nio-ssh) | Apache-2.0 | SSH transport (via Citadel) |
| [Swift Crypto](https://github.com/apple/swift-crypto) | Apache-2.0 | Cryptography (via Citadel / RoyalVNC) |
| [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift) | MIT | Cryptography (via RoyalVNC) |
| [Cascadia Code NF](https://github.com/microsoft/cascadia-code) | SIL Open Font License 1.1 | Bundled coding font |

Thank you to the authors and maintainers of these projects.

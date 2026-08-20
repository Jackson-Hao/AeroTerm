# AeroTerm

<div align="center">
  <img src="Assets/AppIcon_1024.png" width="128" height="128" alt="AeroTerm Icon" />
  <h3>A lightweight native macOS workbench for SSH, files, network tools, remote desktops, and AI agent CLIs</h3>
  <p>Fast to open. Calm to look at. Built to keep every session in one place.</p>
</div>

---

## What AeroTerm is

AeroTerm is a native macOS app for people who live in terminals, lab benches, and remote machines. It brings remote shells, file transfer, serial ports, TCP/UDP debugging, HTTP APIs, VNC/RDP desktops, and popular AI coding CLIs into a single workspace.

It is designed to feel like a first-party Mac app: a compact welcome window, a glass sidebar, an immersive workbench, and sessions you can split, pop out, suspend, or reconnect without losing the layout.

---

## Design

AeroTerm follows a few visual and interaction choices throughout:

- **Xcode-style welcome window.** A fixed, compact launch screen with a large app mark, a close-only traffic light, and a frosted recents list on the right. You can start a new connection, open the main workbench, or jump straight into a recent host.
- **Sidebar plus canvas.** Saved profiles and live sessions sit on the left. The right side is a full workbench: home when idle, terminals and tool panes when you are connected.
- **Immersive when you need it.** Enter full screen and the chrome recedes so the session fills the display. Move the pointer to the top edge when you want the menu bar back.
- **Two terminal palettes.** Aero Dark (Midnight Neo) and Aero Light (Solar Mist) color the UI and the terminal together. You can also pick well-known palettes such as Campbell, Solarized Dark, One Dark, or Phosphor Green.
- **A readable coding font by default.** Cascadia Code NF ships with the app, with ligatures and icon glyphs for modern CLI tools. SF Mono, Menlo, Monaco, and Courier New are available if you prefer them.
- **Localized interface.** English, 简体中文, 日本語, Français, and Deutsch, or follow the system language.

Passwords and private-key passphrases are stored in the macOS Keychain. AeroTerm will not start until it can protect those secrets.

---

## Getting started

1. Open `dist/AeroTerm.app` (or launch AeroTerm from Applications if you installed it there).
2. Grant Keychain access when macOS asks. This is required so saved passwords stay in the system keychain.
3. On the welcome window, pick one of:
   - **Create a New Connection…** — walk through the wizard.
   - **Open Main Workbench** — skip ahead to Home.
   - A row in **Recent Connections** — reconnect in one click.

You can return to the welcome window later with **⇧⌘1**.

---

## The workbench

### Sidebar

The left column has two lists:

| Tab | What it shows |
| --- | --- |
| **Saved** | Named connection profiles you can edit, duplicate, or launch again. |
| **Active** | Sessions that are open right now, including ones that are suspended or waiting to reconnect. |

From the bottom of the sidebar you can go **Home**, open **Settings**, or start a new connection. Hide or show the sidebar with **⌃⌘S**.

### Home

Home is the quiet landing page: app identity, a large **New Connection** button (**⌘N**), and a searchable recents list. It is the same recents you see on the welcome window, so a host you used yesterday is always one click away.

### Session layout

Each live session occupies a pane. You can:

- **Split Right** or **Split Down** to keep two (or more) tools visible at once.
- **Drag a session** onto an empty pane or another split to rearrange the layout.
- **Open in New Window** to pop a session out, then **Merge to Main Window** to bring it back.
- **Suspend** a session when you want the pane to stay but the connection to pause, then **Resume** later.
- **Close** a session (**⌘W**). For terminals, typing `exit` or pressing **Ctrl+D** also closes the tab.

Empty panes wait for a drop. Closing a pane removes it from the layout; closing the session disconnects it.

### Connection overlay

When a remote session is connecting, a compact overlay shows live status: probing the host, authenticating, and success or failure. You can cancel from there if the host is unreachable.

---

## New Connection Wizard

**⌘N** opens a two-step wizard.

1. **Protocol Selection** — choose a category on the left, then a tool on the right. Each type has a short description so you can pick by job, not by jargon.
2. **Connection Setup** — fill in the name, target, and credentials (or pick a saved account). Optionally save the profile for next time, and connect immediately when you finish.

Leaving the wizard with unsaved fields asks you to confirm, so a half-written host is not discarded by accident.

The four categories:

### Remote Connection

| Tool | What it is for |
| --- | --- |
| **SSH** | A full-color remote terminal for Linux, macOS, and UNIX hosts. Password or private-key login, optional passphrase, host-key checking, and Reconnect if the session drops. |
| **SFTP** | Browse, upload, and download files over the same secure channel. Rename, new folders, search, drag-and-drop upload, and a progress bar you can cancel. |
| **Telnet** | A plain-text console for older servers, lab gear, and network switches. |

SSH accounts are reusable: create a login once, then attach it to many hosts. If a server’s host key has changed since last time, AeroTerm stops and tells you before you continue.

### Debugging Tools

| Tool | What it is for |
| --- | --- |
| **TCP Client** | Connect to a socket, watch a live stream, and send text or HEX. Line numbers, timestamps, encodings, file send, timed repeat, and save received data to disk. |
| **TCP Server** | Listen on a local port, talk to one client or broadcast to all, with optional echo. |
| **UDP Tool** | Send and receive unicast, multicast, or broadcast datagrams, with a HEX inspector. |
| **Serial** | Talk to USB-UART and RS-232 devices. Choose **Shell** (a full terminal with highlight styles and palettes) or **Tester** (receive above, send below, with timestamps, line numbers, HEX, and timed send). Baud rate, data bits, parity, stop bits, flow control, DTR/RTS, and export to a log. |
| **HTTP Client** | An API workbench for HTTP, HTTPS, and WebSocket: method, URL, params, headers, body, auth, pretty JSON, and a response pane. |
| **HTTP Server** | A quick local listener that can echo requests or return a custom status, content type, and body. |

If no serial adapter is present, AeroTerm refuses to open an empty session and asks you to plug one in first.

### Remote Desktop

| Tool | What it is for |
| --- | --- |
| **VNC** | Graphical remote desktop with clipboard sync. Quality and refresh-rate presets (High / Balanced / Smooth, 60 / 30 / 15 Hz). |
| **RDP** | A Windows desktop session with the same display controls, for servers and workstations. |

Both keep a Reconnect path if the session drops, instead of throwing the tab away.

### AI & Agent CLI

Launch a local agent CLI inside a real terminal tab, with working directory and optional environment values:

- **Claude Code CLI** — Anthropic’s coding agent
- **Codex CLI** — OpenAI’s coding agent
- **Antigravity CLI** — Google DeepMind’s agentic coding CLI
- **Grok CLI** — xAI’s command-line agent
- **Hermes CLI** — Nous Research’s open-weights agent
- **Custom Agent CLI** — any local binary, script, or shell you point it at

Each preset has its own icon. When the agent process exits, the tab closes on its own.

---

## Connections and accounts

Profiles and logins are separate on purpose.

- **Connections** remember *where* to go: host, port, protocol, serial path, display quality, and so on. Manage them from the sidebar or the Connections window.
- **Accounts** remember *who you are*: username plus password or private key. Manage them in **Settings → Accounts**. Pick an existing account in the wizard, or create one inline.

You can edit a saved connection without touching a running session. Deleting a profile does not close sessions that are already open. Auto-connect on launch is available for profiles you want waiting when AeroTerm starts.

---

## Settings

Open **AeroTerm → Settings…** (**⌘,**).

| Tab | What you can change |
| --- | --- |
| **Appearance** | Interface language and color theme (Aero Dark / Aero Light). |
| **Terminal** | Font family, font size, and terminal palette, with a live preview. |
| **Accounts** | Create, edit, and delete reusable logins. |
| **About** | App identity and version. |

---

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| **⌘N** | New Connection Wizard |
| **⌘,** | Settings |
| **⌘W** | Close the current session |
| **⌃⌘S** | Hide or show the sidebar |
| **⇧⌘1** | Welcome window |
| **⌘↩** | Send on the serial tester |
| **Ctrl+D** or `exit` | Close a terminal session from inside the shell |

---

## License

AeroTerm is released under the [MIT License](LICENSE).

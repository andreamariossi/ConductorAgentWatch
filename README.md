# Conductor AgentWatch 🤖

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue.svg)](https://developer.apple.com/macos/)

A lightweight, **native Swift** macOS menu bar app for tracking your Claude Code, Codex, and Antigravity usage in real-time. Monitor token consumption, costs, session blocks, and server-side limits with a premium, monospaced native interface.

Conductor AgentWatch runs as a menu-bar-only app built on `NSStatusItem` + `NSPopover` + SwiftUI. It is under **3 MB installed with zero runtime dependencies** — no Electron, no Node, near-zero idle overhead. It parses your local activity transcripts directly and shows **real server-truth limit gauges** (5-hour + weekly utilization with reset countdowns, absolute reset clock times, and predicted cutoff warnings).

---

## Screenshots

| Overview | Dashboard |
| :---: | :---: |
| ![Overview](./screenshots/overview.png) | ![Dashboard](./screenshots/dashboard.png) |

| Live Monitoring | Usage Analytics |
| :---: | :---: |
| ![Live](./screenshots/live.png) | ![Analytics](./screenshots/analytics.png) |

| Settings | Terminal Logs |
| :---: | :---: |
| ![Settings](./screenshots/settings.png) | ![Terminal](./screenshots/terminal.png) |

---

## Features

- **Multi-Agent Tracking** — Support for Claude Code (`CL`), Codex (`CX`), and Antigravity (`AG`) with compact 2-letter status bar abbreviations (e.g. `CL: 74%` or `AG: 23%`).
- **Live Menu Bar Status** — Dynamic usage percentage shown right in your macOS status bar, matching the active agent.
- **5-Hour Session Blocks** — Track current block tokens, burn rate, end-of-window projection, and reset countdowns.
- **Server-Truth Limit Gauges** — Resolves real 5-hour and weekly utilization from Anthropic's server, with absolute clock times for resets (e.g., "resets at 16:10").
- **Automatic Local Fallback** — Falling back to local transcript estimation if the network is offline or credentials are missing.
- **Interactive Explanatory Tooltips** — Hover over any ring or progress bar to see exactly how local log calculations differ from live server-side rate limits.
- **Charts & Analytics** — Beautiful, native SwiftUI charts displaying your daily and weekly token usage distributions.
- **Threshold Notifications** — Native macOS alerts at 70% and 90% utilization to prevent mid-workflow rate-limiting.
- **Launch at Login** — Single toggle in the Settings tab to launch on startup automatically.

---

## Installation

### Build from Source

Requires **Xcode 16.4 / Swift 6.1** and **macOS 14+** (Sonoma).

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/ConductorAgentWatch.git
cd ConductorAgentWatch/swift

# 2. Build the application (signs and bundles automatically)
./scripts/build-app.sh

# 3. Move it to your Applications folder
mv dist/ConductorAgentWatch.app /Applications/
open /Applications/ConductorAgentWatch.app
```

---

## Linking Your Account (How It Works)

Conductor AgentWatch is fully integrated with your local developer tools. It does not ask for or store your passwords; instead, it automatically links to your account using local config files and macOS secure storage:

1. **OAuth Keychain Integration**: 
   When you log in to Claude Code (`claude`), the CLI securely saves your login credentials in the macOS Keychain under the service label **`Claude Code-credentials`**. Conductor AgentWatch automatically accesses this keychain item to read the active access token and fetch your real-time server-side limits from the Anthropic OAuth usage API.
2. **Local Transcript Scanning**:
   The app scans local project transcripts in `~/.claude/projects/` to compile your daily costs, cost per turn, and active block token metrics.
3. **No Setup Required**:
   Simply run `claude` (Claude Code) in your terminal and complete the standard login once. Conductor AgentWatch will automatically discover the credentials and start updating your dashboard in real-time.

---

## Usage

1. **Launch** — Open the app. The Conductor icon and active agent abbreviation appear in the menu bar.
2. **Left-Click** — Opens the floating popover with five tabs: Overview, Dashboard, Live, Activity, Analytics, and Settings.
3. **Right-Click** — Access the context menu to trigger a manual refresh or quit the app.
4. **Positioning** — Hold `Cmd (⌘)` and click-and-drag the menu bar icon to rearrange its position on your status bar.

---

## Tech Stack

* **Frontend**: Swift 6.1 + SwiftUI + AppKit (`NSStatusItem` / `NSPopover`)
* **Graphics**: Swift Charts for analytics
* **Integration**: Custom non-blocking file watcher for `~/.claude/` activity
* **Footprint**: Under 3 MB disk usage, minimal memory footprint.

---

## Credits

This project is a renamed and enhanced fork of the original **[CCSeva](https://github.com/Iamshankhadeep/ccseva)** application created by **[Shankhadeep Dey](https://github.com/Iamshankhadeep)**. 
* **Original GitHub Repository**: [Iamshankhadeep/ccseva](https://github.com/Iamshankhadeep/ccseva)
* **Author's Reddit Post**: [Built my first side project outside of work: A native macOS menu bar app for tracking Claude Code API usage in real-time](https://www.reddit.com/r/ClaudeAI/comments/1lmplia/built_my_first_side_project_outside_of_work_a/)

Built with ❤️ using [Swift](https://swift.org), [SwiftUI](https://developer.apple.com/xcode/swiftui/), and [ccusage](https://github.com/ryoppippi/ccusage) (for the usage data format and 5-hour block algorithm).

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Note**: This is an unofficial tool for tracking Claude Code usage. Requires a valid Claude Code installation and configuration.

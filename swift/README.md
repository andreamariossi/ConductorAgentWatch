# Conductor AgentWatch (native Swift)

A lightweight, native macOS menu bar app that monitors Claude Code, Codex, and Antigravity usage in real time — a Swift/AppKit/SwiftUI implementation designed to be high-performance, fast, and feature-rich.
No Node, no Electron, no external dependencies: under 3 MB binary size.

## Build

Requires Xcode 16.4 / Swift 6.1 toolchain, macOS 14+ (built and tested on arm64).

```bash
cd swift
swift build                 # debug build
.build/debug/ConductorAgentWatch --diagnose   # headless functional check (see below)

./scripts/build-app.sh      # release build → dist/ConductorAgentWatch.app (ad-hoc signed)
open dist/ConductorAgentWatch.app
```

The app is a menu-bar-only app (`LSUIElement`): look for the usage percentage in the menu bar. Left-click opens the popover; right-click shows Refresh / Quit.

`ConductorAgentWatch --diagnose` skips the UI entirely and runs the JSONL scan, 5-hour block computation, weekly aggregation and a limits-endpoint probe, printing a summary. Use it to sanity-check the data pipeline.

## Architecture

SwiftPM executable package (no .xcodeproj), Swift 6 language mode, macOS 14+.

```
Sources/ConductorAgentWatch/
Base directory containing:
├── App/
│   └── AppDelegate.swift      # NSStatusItem + NSPopover(NSHostingController) shell
├── Data/
│   ├── JSONLScanner.swift     # actor: incremental ~/.claude JSONL parsing + dedup
│   ├── AgentScanner.swift     # scans and abbreviations for multi-agent support
│   ├── Aggregator.swift       # 5h session blocks, daily/weekly/model/project rollups
│   ├── Models.swift           # UsageEntry, SessionBlock, UsageSnapshot, ...
│   ├── Pricing.swift          # static per-token pricing (LiteLLM snapshot), prefix match
│   ├── FileWatcher.swift      # FSEvents wrapper (file events, 2s latency, 3s debounce)
│   └── UsageStore.swift       # @MainActor ObservableObject — single source of truth
├── Limits/
│   ├── LimitsProvider.swift   # protocol + window types
│   ├── OAuthLimitsProvider.swift  # api.anthropic.com/api/oauth/usage client
│   └── Credentials.swift      # Keychain ("Claude Code-credentials") / file token
├── Support/
│   ├── Settings.swift         # ~/.conductoragentwatch/settings.json (shared preferences)
│   ├── Notifier.swift         # UNUserNotificationCenter / osascript thresholds
│   ├── Formatting.swift       # ISO8601 parsing, token/cost/duration formatting
│   └── Diagnose.swift         # --diagnose headless check
└── UI/                        # SwiftUI popover: Dashboard / Live / Analytics / Settings
```

### Data Pipeline

1. **Scan** — `UsageDataSource` (an actor) recursively scans `~/.claude/projects/**/*.jsonl`
   (plus `$CLAUDE_CONFIG_DIR` roots and `~/.config/claude` when present). Files are read
   incrementally (seek + plain read of only the appended bytes; no memory mapping), split
   on newline bytes, and prefiltered with a raw byte search for `"type":"assistant"`
   before any JSON decoding. An incremental cache keyed on (file identity, mtime, size,
   byte offset) means re-scans only parse appended bytes — transcripts are append-only —
   and a rotated/replaced or truncated file is re-parsed from scratch.
2. **Dedup** — streaming writes duplicate assistant rows. Dedup key is `message.id + ":" + requestId` (message.id alone when requestId is missing); first occurrence wins.
3. **Cost** — `costUSD` is absent from transcripts in practice, so cost is computed from a static per-token pricing table snapshotted from LiteLLM, with longest-prefix model matching.
4. **Blocks** — 5-hour session block algorithm: blocks anchor at the entry timestamp floored to the UTC hour; a new block starts when an entry is >5h after the block start or >5h after the previous entry. Burn rate and end-of-window projections come from the active block.
5. **Refresh** — FSEvents on the data roots (debounced 3 s) + a configurable fallback timer (default 60 s) + manual refresh.

### Limit Gauges & Server-Truth (Keychain Integration)

Subscription limits are enforced server-side, so local token counting can only estimate them. The Dashboard's gauges read the same endpoint Claude Code itself uses:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>        # from Keychain "Claude Code-credentials"
anthropic-beta: oauth-2025-04-20
```

The response is parsed into windows like `five_hour` and `seven_day`. The decoder is defensive, polling is capped at once per 120 s with backoff on 401/429, and on any failure the app falls back to local estimation, badging gauges "estimated" instead of "live".

The Keychain read shells out to `/usr/bin/security` with a 10 s hard timeout (the call can otherwise hang on a keychain authorization prompt); a denied or failed read is cached negatively for 30 minutes so you aren't re-prompted on every poll.

### Settings Compatibility

`~/.conductoragentwatch/settings.json` is read and written to maintain your preferences. If you have legacy `~/.ccseva/settings.json` settings, they are automatically migrated backwards-compatibly on start.

### Notifications

Warning at ≥70% and critical at ≥90% of the 5-hour window, 5-minute cooldown, and only when the status *worsens*. Uses `UNUserNotificationCenter` when running from the app bundle; falls back to `osascript` in command-line environments.

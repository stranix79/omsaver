<p align="center">
  <img src="assets/omsaver.png" alt="OmSaver" width="820">
</p>

<h1 align="center">om› saver</h1>

<p align="center">
  <b>A TUI screensaver for macOS. Omarchy vibes, real system stats, zero dependencies.</b><br>
  <sub>Part of the <a href="https://omfi.stranix.net">OmSuite</a> — small native tools that make your Mac feel like a tiling-WM rig.</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square">
  <img src="https://img.shields.io/badge/arch-universal%20(arm64%20%2B%20x86__64)-8aa6e0?style=flat-square">
  <img src="https://img.shields.io/badge/size-~200%20KB-a6e3a1?style=flat-square">
  <img src="https://img.shields.io/badge/license-MIT-e5c27a?style=flat-square">
</p>

---

Your idle Mac deserves better than slow-panning drone footage. **OmSaver** turns it
into a living terminal dashboard:

- 🕐 **A huge monospaced clock** — date and uptime included, readable from across the room
- 📊 **Real telemetry** — per-core CPU bars, memory gauge and a load sparkline,
  sampled live from the kernel (`host_processor_info`, `host_statistics64`)
- 📜 **A scrolling journal** of lovingly fake ops —
  `HERDING PACKETS`, `DEFRAGMENTING THE AETHER`, `FEEDING THE DAEMONS` —
  with a blinking block cursor, of course
- 🪟 **Tiling-WM aesthetics** — dark panes, thin blue borders, Hyprland-ish gaps,
  straight from the [Omarchy](https://omarchy.org) school of beauty
- 🍃 **Native and tiny** — one Swift file, AppKit only, no Electron, no network,
  no tracking, ~200 KB

## Install

**Download** the latest `OmSaver.saver.zip` from
[Releases](https://github.com/stranix79/omsaver/releases), unzip, double-click
`OmSaver.saver`, and macOS offers to install it. Then
*System Settings → Screen Saver → OmSaver*.

**Or build from source** (no Xcode project needed, just the command line tools):

```console
$ git clone https://github.com/stranix79/omsaver.git
$ cd omsaver
$ ./build.sh install
✓ installé — Réglages Système → Économiseur d'écran → OmSaver
```

## Why is it free?

Because a screensaver is a billboard 😄 — OmSaver is the free half of the
**OmSuite**, a series of small paid utilities in the same spirit:

| | | |
|---|---|---|
| **OmFi** | keyboard-driven Wi-Fi panel — scan, join, QR-share, DNS switching, live graphs | [omfi.stranix.net](https://omfi.stranix.net) |
| **OmDash** | system vitals at a glance | *soon* |
| **OmWin** | Omarchy keybindings for your windows | *soon* |

Also from the same bench: [ZapZap](https://zapzap.stranix.net) (WhatsApp, one
keystroke away) and [Sygnet](https://sygnet.app) (bookmark sync that actually
includes Safari). Everything: [apps.stranix.net](https://apps.stranix.net).

## Privacy

OmSaver reads your CPU/memory statistics locally and displays them. That's it.
No network requests, no analytics, no files written. The "network scans" in the
journal are theatrical fiction.

## License

MIT © 2026 [Stranix](https://apps.stranix.net) — Gilles Fauvie.
Built in Belgium, one `swiftc` invocation at a time.

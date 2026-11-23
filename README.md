# ClipSync

ClipSync sends clipboard-style content from an Android phone to a Windows PC (and text back) over the local Wi-Fi network. No cloud, no account, no internet connection required.

## Features
- **Phone to PC in two taps**: Android Share sheet target & Quick Settings tile.
- **Direct to Clipboard**: Text and links land directly on the Windows clipboard; images optionally too.
- **Local File Transfers**: Photos, videos, and files up to 50 MB saved directly to `Downloads/ClipSync`.
- **PC to Phone**: Hotkey (`Ctrl+Shift+S`) or auto-send pushes clipboard text to phone notifications.
- **Encrypted & Authenticated**: Self-signed TLS with certificate pinning and QR-code pairing.
- **Zero Configuration**: mDNS service discovery on local networks.

## Repository Layout
- `desktop/`: Windows application built with Tauri 2, Rust (Axum, Tokio, Arboard), React, and Vite.
- `mobile/`: Android application built with Flutter, Riverpod, Dio, and native Kotlin extensions.
- `docs/`: Technical specifications (`SPEC.md`) and protocol reference (`PROTOCOL.md`).

## Quick Start
See `docs/SPEC.md` for milestone details and development instructions.

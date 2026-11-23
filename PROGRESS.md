# ClipSync Progress Log

## Current Status: Milestone M7 (PC to Phone) Complete ✅

| Milestone | Status | Description |
|---|---|---|
| **M0: Skeleton** | ✅ Complete | Repository layout, Tauri 2 desktop app, Flutter mobile app, build verification |
| **M1: Rust Server Dev Mode** | ✅ Complete | Axum server, `/info`, `/text`, `/file` dev mode, clipboard write, file save |
| **M2: Flutter Sender MVP** | ✅ Complete | Dev screen, manual host/token, text send, file upload |
| **M3: Share Target & Tile** | ✅ Complete | Android share sheet, `QuickSendActivity`, `ClipboardTileService` |
| **M4: Security & Pairing** | ✅ Complete | TLS generation, QR pairing, device secrets, pinned client |
| **M5: Discovery** | ✅ Complete | mDNS registration, `nsd`, resolver fallback |
| **M6: Windows Product** | ✅ Complete | Tauri React UI, system tray, history SQLite, settings |
| **M7: PC to Phone** | ✅ Complete | WebSocket `/events`, clipboard watcher, global hotkey, phone notifications |
| **M8: Polish & Release** | ⏳ Pending (Next) | NSIS installer with firewall rule, release APK, error states |

### Done in M7:
- **Desktop WebSocket `/events` Server (`desktop/src-tauri/src/server/ws.rs`)**:
  - Implemented authenticated real-time streaming endpoint with Bearer auth and private IP checking.
  - Immediate `hello` greeting upon connection: `{"type": "hello", "server_name": ..., "protocol": 1}`.
  - Active 20-second ping loop with `AtomicU32` missed pong tracking. Disconnects client after 2 consecutive missed pongs.
  - Real-time serialization and broadcast of `text` and `file_offer` events to connected phones.
- **Desktop Clipboard Watcher & Loop Prevention (`desktop/src-tauri/src/clipboard/watcher.rs`, `src/lib.rs`)**:
  - Dedicated thread polling clipboard sequence number every 250ms.
  - Password manager protection: skips changes when `ExcludeClipboardContentFromMonitorProcessing` format is active.
  - SHA-256 hash tracking skips `last_written_clipboard` echo writes.
  - Automatic broadcast of `text` messages to connected phones when `auto_send_clipboard` is enabled.
- **Desktop Global Hotkey & Tray Push (`desktop/src-tauri/src/hotkey.rs`, `src/lib.rs`, `src/tray.rs`)**:
  - Global hotkey `Ctrl+Shift+S` via `tauri-plugin-global-shortcut` and System Tray "Send clipboard to phone" action.
  - Reads clipboard text, updates `last_written_clipboard`, broadcasts `text` event to phones, and records `out` item in SQLite.
- **Desktop File Offer Download Route (`desktop/src-tauri/src/server/routes.rs`)**:
  - Serves registered file offers from in-memory offers map via `GET /api/v1/files/:id` with streaming body and `Content-Disposition`.
- **Mobile EventsClient & Keepalive (`mobile/lib/core/events_client.dart`)**:
  - Pinned TLS WebSocket client connecting to `wss://<host>:<port>/api/v1/events` with Bearer auth.
  - Exponential backoff reconnect: 1s, 2s, 4s, 8s, 16s, clamped at 30s per SPEC.
  - Automatic response to `ping` with `{"type": "pong"}`.
- **Mobile EventsService & Notifications (`mobile/lib/services/events_service.dart`, `notifications.dart`)**:
  - Incoming `text` events: flags content in `LoopPrevention`, displays notification with "Copy" action. Tapping Copy writes to Android clipboard and saves in SQLite history (`status: 'done'`).
  - Incoming `file_offer` events: displays notification with "Download" action. Tapping Download streams file to external Downloads directory via `GET /api/v1/files/:id` and saves in SQLite history.
- **Mobile Echo Loop Prevention (`mobile/lib/core/loop_prevention.dart`)**:
  - LRU-capped hash cache tracking incoming content from PC. `TransferService` and `HomeScreen` prevent any received content from echoing back to the PC.
- **Android 14+ Foreground Service (`mobile/lib/services/foreground_service.dart`, `AndroidManifest.xml`)**:
  - Configured `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SPECIAL_USE` permissions with `specialUse` type and justification string.
- **Automated Test Suites**:
  - Desktop: 46/46 tests passed in `cargo test` across 6 test suites (unit, security, discovery, product, server, events).
  - Mobile: 56/56 tests passed in `flutter test` across all suites (events, resolver, pairing, share receiver, transfer service, widgets). `flutter analyze` 0 issues.

### Done in M6:
- React UI pages (Home, History, Devices, Settings, Help).
- System tray with context menu (Open, Pause receiving, Send clipboard, Open folder, Quit) and single instance protection.
- History retention cleanup (startup and 24h background task) pruning items > 30 days and enforcing 500 items max limit.
- Settings persistence in `%APPDATA%/ClipSync/config.json` with registry autostart.
- 42/42 desktop tests and 46/46 mobile tests passed.

### Done in M5:
- Desktop mDNS advertising (`mdns-sd`) registering `_clipsync._tcp.local.` with TXT records `id`, `name`, `v=1`, `fp` (first 16 hex chars).
- Dynamic mDNS update and unregistration on port/interface change.
- Mobile `PcResolver` with 3-stage fallback: (1) cached host/port with `GET /info` (1.5s), (2) mDNS lookup with `nsd` (5s) and automatic cache update, (3) manual fallback.
- 37/37 desktop tests and 46/46 mobile tests passed.

### Done in M4:
- Desktop TLS with rcgen (ECDSA P-256, 10-year validity, SANs).
- Desktop Pairing API: 128-bit pairing token (single-use, 5 min TTL), `clipsync://pair` QR generation, 256-bit base64url device secret in SQLite.
- Desktop Rate Limiting & Private IP Filter (RFC 1918 allowed, 5 pairs/min limit, 5 auth failures blocks IP for 60s).
- Mobile certificate pinning with `PinnedClient` checking DER SHA-256 fingerprint.
- Mobile QR scanner (`mobile_scanner`), manual entry fallback, 4-step pairing service, and secure store.
- 32/32 desktop tests and 36/36 mobile tests passed.

### Done in M3:
- Configured Android manifest with `ACTION_SEND` and `ACTION_SEND_MULTIPLE`.
- Configured `QuickSendActivity` and `ClipboardTileService`.
- Implemented `ShareReceiverScreen` dialog with progress bar, multi-item queue, > 50 MB rejection, success checkmark, auto-dismiss, and Retry/Close actions.
- 8 tests in `share_receiver_test.dart`.

### Done in M2:
- Built dev connection screen (`mobile/lib/features/home/dev_screen.dart`, route `/dev`).
- Implemented text sender with <= 1 MB limit and UUID deduplication.
- Implemented file picker & streaming sender with <= 50 MB limit, progress callback, and network retry policy.
- 13 automated unit tests in `transfer_service_test.dart`.

### Next (Milestone M8: Polish & Release):
- Friendly error messages and empty states across desktop and mobile.
- App icons (desktop and Android mipmap).
- Windows NSIS installer that automatically adds the Windows Firewall inbound rule (`netsh advfirewall firewall add rule name="ClipSync" dir=in action=allow protocol=TCP localport=47821`).
- Release APK instructions.
- README.md with comprehensive setup, architecture, and network troubleshooting guide.

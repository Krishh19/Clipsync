# ClipSync Progress Log

## Current Status: Milestone M6 (Windows Product UI & System Tray) Complete ✅

| Milestone | Status | Description |
|---|---|---|
| **M0: Skeleton** | ✅ Complete | Repository layout, Tauri 2 desktop app, Flutter mobile app, build verification |
| **M1: Rust Server Dev Mode** | ✅ Complete | Axum server, `/info`, `/text`, `/file` dev mode, clipboard write, file save |
| **M2: Flutter Sender MVP** | ✅ Complete | Dev screen, manual host/token, text send, file upload |
| **M3: Share Target & Tile** | ✅ Complete | Android share sheet, `QuickSendActivity`, `ClipboardTileService` |
| **M4: Security & Pairing** | ✅ Complete | TLS generation, QR pairing, device secrets, pinned client |
| **M5: Discovery** | ✅ Complete | mDNS registration, `nsd`, resolver fallback |
| **M6: Windows Product** | ✅ Complete | Tauri React UI, system tray, history SQLite, settings |
| **M7: PC to Phone** | ⏳ Pending (Next) | WebSocket `/events`, clipboard watcher, global hotkey, phone notifications |
| **M8: Polish & Release** | ⏳ Pending | NSIS installer with firewall rule, release APK, error states |

### Done in M6:
- **Tauri IPC Commands & Real LAN / Security Data (`desktop/src-tauri/src/commands.rs`)**:
  - `get_local_lan_ip()`: Identifies primary LAN IP using OS UDP routing table socket probe without transmitting packets, falling back safely to loopback.
  - `get_pair_qr()`: Generates QR codes with real LAN IP and actual TLS certificate SHA-256 fingerprint from `state.cert_fingerprint` / TLS storage.
  - `get_status()`: Returns local endpoint, port, connected devices count from `state.ws_clients`, running status, and `is_paused` flag.
  - `copy_history_item()`: Copies text (arboard), images (decoded via `image` crate then arboard), or files (CF_HDROP via clipboard-win) using `state.clipboard_writer`.
  - `open_folder()`: Invokes Windows Explorer to display files or directories (`explorer.exe`).
  - `set_settings()` / `get_settings()`: Reads/writes `%APPDATA%/ClipSync/config.json` and updates live configuration.
  - `configure_windows_autostart()`: Configures `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` for `ClipSync` with `--minimized` argument.
  - `toggle_pause_receiving()` and `get_pause_status()`: Manages atomic receiving toggle.
- **System Tray & Window Lifecycle (`desktop/src-tauri/src/tray.rs`, `src/lib.rs`, `tauri.conf.json`)**:
  - Tray menu items: "Open", "Pause receiving", "Send clipboard to phone", "Open save folder", "Quit".
  - Left click on tray icon restores, unminimizes, and focuses main window.
  - Close-to-tray behavior: `tauri::WindowEvent::CloseRequested` calls `api.prevent_close()` and `window.hide()`.
  - Single-instance protection: `tauri-plugin-single-instance` integrated to focus existing window if another instance launches.
  - Minimized launch support: checks `--minimized` CLI argument to hide window at startup.
- **History Retention & Periodic Cleanup (`desktop/src-tauri/src/storage/db.rs`, `src/lib.rs`)**:
  - `Database::clean_retention(days, max_items)`: Deletes items older than cutoff timestamp and caps total items to `max_items`.
  - Runs automatically on application startup and in a 24-hour periodic background task.
- **React Frontend (`desktop/src/App.tsx`, `App.css`)**:
  - Home tab: Status badge, local endpoint, connected phones count, receiving status badge, Pause/Resume button, push text form, recent transfers preview, and "Pair New Phone" modal with SVG QR code and 5-minute countdown.
  - History tab: Newest first items list with kind badges, direction indicators, text/file details, Copy, Show in folder, Delete, and Clear History.
  - Devices tab: Paired devices list with last seen timestamp and Revoke action.
  - Settings tab: Inputs for Device Name, Port, Save Folder, Max File Size, Send Hotkey, History Retention Days, History Max Items, and checkboxes for text/links, images, videos as files, notifications, auto-send clipboard, and autostart with Windows.
  - Help tab: Windows Firewall guide, Wi-Fi AP isolation advice, manual IP discovery, and security model overview.
  - `npm run build`: Compiles cleanly with 0 TypeScript/Vite errors.
- **Automated Product Tests (`desktop/src-tauri/tests/product_tests.rs`)**:
  - `test_get_local_lan_ip_returns_valid_ip`: Verified valid IPv4 address parsing.
  - `test_history_retention_days_and_count`: Verified pruning of items > 30 days and capping to max count.
  - `test_database_crud_operations`: Verified insert, retrieve, single delete, and clear.
  - `test_device_revocation_and_query`: Verified revocation flag and lookup rejection.
  - `test_settings_serialization_and_defaults`: Verified config defaults and JSON round-trip serialization.
  - All 42 tests in test suite pass (`cargo test`).

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
- Wired stream listeners in `mobile/lib/main.dart` with `receive_sharing_intent`.
- Enhanced `HomeScreen` clipboard sending with automatic HTTP link detection (`kind: 'link'`).
- Added 8 automated tests in `mobile/test/share_receiver_test.dart`.

### Done in M2:
- Built dev connection screen (`mobile/lib/features/home/dev_screen.dart`, route `/dev`).
- Implemented text sender with <= 1 MB limit and UUID deduplication.
- Implemented file picker & streaming sender with <= 50 MB limit, progress callback, and network retry policy.
- Added 13 automated unit tests in `mobile/test/transfer_service_test.dart`.
- Verified live end-to-end against M1 dev server with matching SHA-256 hash.

### Next (Milestone M7: PC to Phone):
- Desktop WebSocket `/api/v1/events` implementation (JSON messages: `hello`, `text`, `file_offer`, `ping`/`pong`).
- Desktop clipboard watcher thread polling sequence number every 250ms (ignoring `last_written` and password managers via `ExcludeClipboardContentFromMonitorProcessing`).
- Desktop global hotkey (default Ctrl+Shift+S) sending current clipboard text to connected phones.
- Desktop "Send file to phone" registering file in in-memory offers map for 1 hour, emitting `file_offer`.
- Mobile `EventsService`: keeps WebSocket alive with backoff (1s to 30s), ping/pong handling (answer pong on ping; reconnect after 2 missed).
- Mobile foreground service (`specialUse` type with justification string) to receive while app is in background.
- Mobile notifications with Copy action for text and Download action for file offers.

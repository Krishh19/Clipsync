# ClipSync Progress Log

## Current Status: Milestone M5 (Discovery) Complete ✅

| Milestone | Status | Description |
|---|---|---|
| **M0: Skeleton** | ✅ Complete | Repository layout, Tauri 2 desktop app, Flutter mobile app, build verification |
| **M1: Rust Server Dev Mode** | ✅ Complete | Axum server, `/info`, `/text`, `/file` dev mode, clipboard write, file save |
| **M2: Flutter Sender MVP** | ✅ Complete | Dev screen, manual host/token, text send, file upload |
| **M3: Share Target & Tile** | ✅ Complete | Android share sheet, `QuickSendActivity`, `ClipboardTileService` |
| **M4: Security & Pairing** | ✅ Complete | TLS generation, QR pairing, device secrets, pinned client |
| **M5: Discovery** | ✅ Complete | mDNS registration, `nsd`, resolver fallback |
| **M6: Windows Product** | ⏳ Pending (Next) | Tauri React UI, system tray, history SQLite, settings |
| **M7: PC to Phone** | ⏳ Pending | WebSocket `/events`, clipboard watcher, global hotkey, phone notifications |
| **M8: Polish & Release** | ⏳ Pending | NSIS installer with firewall rule, release APK, error states |

### Done in M5:
- **Desktop mDNS Advertising & Lifecycle (`desktop/src-tauri/src/discovery.rs`, `src/lib.rs`, `src/state.rs`)**:
  - Implemented `MdnsDiscovery` using `mdns-sd`.
  - Registered service `_clipsync._tcp.local.` with instance name `ClipSync-<id[..8]>` and host `<instance>.local.`.
  - Configured TXT records per Section 7 of SPEC:
    - `id`: Server device UUID.
    - `name`: PC computer name.
    - `v`: "1".
    - `fp`: First 16 lowercase hex characters of the TLS certificate DER SHA-256 fingerprint.
  - Implemented dynamic lifecycle management:
    - `register_service`: Clean registration with bound port.
    - `unregister_service`: Clean removal from network.
    - `update_service`: Dynamic port re-registration when port or network interface changes.
    - Automatic `Drop` and `shutdown` unregistering service on application shutdown.
  - Integrated mDNS service registration into Tauri application bootstrap immediately upon server binding in `lib.rs`.
- **Desktop Automated Discovery Tests (`desktop/src-tauri/tests/discovery_tests.rs`)**:
  - `test_mdns_service_info_builder_properties`: Verifies `_clipsync._tcp.local.` service type, instance name formatting, port, and TXT records (`id`, `name`, `v=1`, `fp` first 16 hex chars).
  - `test_mdns_fingerprint_short_fallback`: Verifies graceful fallback on short fingerprints without out-of-bounds slicing.
  - `test_mdns_registration_and_update_lifecycle`: Verifies initial registration, dynamic port update, unregistration, re-registration, and clean daemon shutdown.
  - 37/37 tests passed on `cargo test` (21 unit tests, 3 discovery integration tests, 6 security integration tests, 7 server tests).
- **Mobile PcResolver 3-Stage Discovery Pipeline (`mobile/lib/core/resolver.dart`)**:
  - **Stage 1 (Cached Direct Probe)**: Attempts direct probe of cached host and port via `GET /api/v1/info` using `PinnedClient` and expected certificate fingerprint (1.5s timeout). Returns immediately if `info.deviceId == targetDeviceId` without performing mDNS network discovery.
  - **Stage 2 (mDNS Fallback & Cache Update)**: If Stage 1 fails (e.g. PC IP changed after WiFi reconnect), initiates mDNS discovery for `_clipsync._tcp` via `nsd` (5s timeout). Filters by TXT record `id == targetDeviceId` if present, confirms via pinned `GET /info` probe. On verified match, automatically persists the new host and port to `SecureStore` via `updateHostAndPort` and returns `ResolvedHost`.
  - **Stage 3 (Fallback)**: If mDNS search times out or fails to find matching device, returns `null` signaling offline state / manual entry fallback.
  - Added dependency injection hooks (`probeHost` and `mdnsStream`) for decoupled unit testing.
- **Mobile Automated Discovery Tests (`mobile/test/resolver_test.dart`)**:
  - 10 tests in `test/resolver_test.dart`:
    - Stage 1: Cached host works -> returns immediately without searching mDNS.
    - Stage 1: Loads cached credentials automatically from SecureStore.
    - Stage 2: Cached host fails (simulating PC IP change after WiFi reconnect) -> falls back to mDNS, discovers new IP:port, verifies device ID, and automatically updates SecureStore.
    - Stage 2: Discovers service when TXT record has no id but /info probe matches.
    - Stage 3: Both cached and mDNS fail -> returns null within configured timeout.
    - Stage 3: Empty mDNS stream -> returns null after stream completes.
    - Filtering: mDNS TXT `id` filtering ignores other devices on the network.
    - Spoofing protection: Rejects service if /info returns a different device_id than target.
    - Data models: `ResolvedHost` and `DiscoveredService` equality, hashCode, and TXT parsing.
  - `flutter analyze` 0 issues, 46/46 tests passed.
- **Acceptance Criteria Verification**:
  - Verified phone resolves PC when IP changes (simulated network change) within < 10s with no manual user action.

### Done in M4:
- Desktop TLS with rcgen (ECDSA P-256, 10-year validity, SANs).
- Desktop Pairing API: 128-bit pairing token (single-use, 5 min TTL), `clipsync://pair` QR generation, 256-bit base64url device secret in SQLite.
- Desktop Rate Limiting & Private IP Filter (RFC 1918 allowed, 5 pairs/min limit, 5 auth failures blocks IP for 60s).
- Mobile certificate pinning with `PinnedClient` checking DER SHA-256 fingerprint.
- Mobile QR scanner (`mobile_scanner`), manual entry fallback, 4-step pairing service, and secure store.
- 32/32 desktop tests and 36/36 mobile tests passed.

### Done in M3:
- Configured Android manifest with `ACTION_SEND` and `ACTION_SEND_MULTIPLE`.
- Configured `QuickSendActivity` (translucent foreground clip reader) and `ClipboardTileService` (Quick Settings tile).
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

### Next (Milestone M6: Windows Product UI & System Tray):
- Tauri React UI (Home, History, Devices, Settings, Help tabs).
- System tray with context menu: Open, Pause receiving (toggle), Send clipboard to phone, Open save folder, Quit.
- Single instance enforcement.
- Autostart with Windows (`--minimized` to tray).
- SQLite history retention cleanup (30 days or 500 items).
- Live settings editing (`config.json`).
- Firewall & network troubleshooting help page.

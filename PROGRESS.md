# ClipSync Progress Log

## Current Status: Milestone M4 (Security & Pairing) Complete ✅

| Milestone | Status | Description |
|---|---|---|
| **M0: Skeleton** | ✅ Complete | Repository layout, Tauri 2 desktop app, Flutter mobile app, build verification |
| **M1: Rust Server Dev Mode** | ✅ Complete | Axum server, `/info`, `/text`, `/file` dev mode, clipboard write, file save |
| **M2: Flutter Sender MVP** | ✅ Complete | Dev screen, manual host/token, text send, file upload |
| **M3: Share Target & Tile** | ✅ Complete | Android share sheet, `QuickSendActivity`, `ClipboardTileService` |
| **M4: Security & Pairing** | ✅ Complete | TLS generation, QR pairing, device secrets, pinned client |
| **M5: Discovery** | ⏳ Pending (Next) | mDNS registration, `nsd`, resolver fallback |
| **M6: Windows Product** | ⏳ Pending | Tauri React UI, system tray, history SQLite, settings |
| **M7: PC to Phone** | ⏳ Pending | WebSocket `/events`, clipboard watcher, global hotkey, phone notifications |
| **M8: Polish & Release** | ⏳ Pending | NSIS installer with firewall rule, release APK, error states |

### Done in M4:
- **Desktop TLS & HTTPS (`desktop/src-tauri/src/server/tls.rs`, `server/mod.rs`)**:
  - Implemented self-signed ECDSA P-256 certificate generation with `rcgen` (valid 10 years, SAN includes hostname, `localhost`, and `127.0.0.1`), saved in `%APPDATA%/ClipSync/tls/`.
  - Derived lowercase SHA-256 fingerprint from DER certificate bytes.
  - Implemented HTTPS serving via `axum_server::bind_rustls(addr, rustls_config).handle(handle).serve(...)` with graceful shutdown and dynamic port probing across 20 ports.
- **Desktop Pairing API (`desktop/src-tauri/src/pairing.rs`, `server/routes.rs`)**:
  - 128-bit pairing token generation (single-use, 5-minute TTL).
  - `GET /api/v1/pair/qr`: Returns `clipsync://pair?host=<ip>&port=<port>&token=<hex>&fp=<sha256-hex>&id=<server_id>&name=<url-encoded>`, SVG QR code, and 300s expiry.
  - `POST /api/v1/pair`: Validates one-time token, rejects invalid/expired token with 401 `invalid_token`. On success, generates 256-bit base64url device secret, stores SHA-256 hash in SQLite `devices` table with `revoked = 0`, and returns `{"device_secret": "...", "server_device_id": "...", "server_name": "..."}`.
  - `DELETE /api/v1/pair`: Allows paired phone to unpair/revoke itself.
- **Desktop Rate Limiting & Private IP Filter (`desktop/src-tauri/src/server/ratelimit.rs`, `server/routes.rs`)**:
  - Private IP filter: Accepts only loopback, RFC 1918 private IPs (10/8, 172.16/12, 192.168/16), and link-local IPs (169.254/16, fe80::/10). Rejects public IP addresses.
  - Pair rate limiter: Limits `POST /api/v1/pair` to 5 attempts per minute per IP (returns 429 `rate_limited` when exceeded).
  - Auth failure tracking: 5 failed auth attempts blocks offending IP for 60 seconds (returns 429 `rate_limited`). Successful auth clears the failure count.
  - Protected endpoint authentication: Enforces Bearer token SHA-256 validation against SQLite `devices` for `/text`, `/file`, `/files/:id`, `/events`, and `DELETE /pair`. Immediately returns 401 if missing, invalid, or revoked.
- **Desktop Security Test Suite (`desktop/src-tauri/tests/security_tests.rs`)**:
  - 6 integration tests verifying TLS cert generation & fingerprint, pairing token single-use & 5-min expiration, private IP filtering & rate limiting, 401 on missing/wrong token, pairing flow with device revocation, and QR endpoint.
  - 32/32 tests passed on standard build (`cargo test`); 33/33 passed with `dev_plain_http`.
- **Mobile Certificate Pinning & PinnedClient (`mobile/lib/core/pinned_client.dart`)**:
  - Custom `HttpClient` with `badCertificateCallback` enforcing SHA-256 fingerprint verification against X509 DER certificate bytes.
  - Configured `Dio` with `IOHttpClientAdapter(createHttpClient: ...)` and 15-second connect/receive timeouts.
- **Mobile Pairing Models & URI Parser (`mobile/lib/core/pairing_models.dart`)**:
  - Parsed and validated `clipsync://pair` URIs (host, port 1..65535, 128-bit hex token, 64-character SHA-256 hex fingerprint, server device ID, URL-decoded server name).
- **Mobile Pairing Service & Secure Storage (`mobile/lib/services/pairing_service.dart`, `mobile/lib/data/secure_store.dart`)**:
  - Complete 4-step secure pairing handshake: pin-verified `GET /api/v1/info`, server device ID verification, `POST /api/v1/pair` token exchange, and persistence of `pc.host`, `pc.port`, `pc.fingerprint`, `pc.device_id`, `pc.name`, `pc.secret` in `FlutterSecureStorage`.
  - Added `unpair()` clearing secure storage and notifying desktop.
- **Mobile QR Scanner & Manual Entry UI (`mobile/lib/features/pairing/pairing_screen.dart`)**:
  - Camera viewfinder QR scanning with `MobileScanner`, permission handling, manual entry tab, and pairing progress/error states.
- **Mobile Test Suite (`mobile/test/pairing_test.dart`)**:
  - 15 comprehensive unit tests covering QR parsing, fingerprint verification, server device ID mismatch rejection, 401 token handling, storage persistence, and unpair flow.
  - `flutter analyze` 0 issues, 36/36 tests passed.

### Done in M3:
- Configured Android manifest (`mobile/android/app/src/main/AndroidManifest.xml`) with `ACTION_SEND` and `ACTION_SEND_MULTIPLE`.
- Configured `QuickSendActivity` (translucent foreground clipboard reader) and `ClipboardTileService` (Quick Settings tile).
- Implemented `ShareReceiverScreen` dialog with progress bar, multi-item queue, > 50 MB rejection, success checkmark, auto-dismiss, and Retry/Close actions.
- Wired stream listeners in `mobile/lib/main.dart` with `receive_sharing_intent`.
- Enhanced `HomeScreen` clipboard sending with automatic HTTP link detection (`kind: 'link'`).
- Added 8 automated tests in `mobile/test/share_receiver_test.dart` (21/21 passed).
- Verified live end-to-end share flows for link, photo, video, and tile.

### Done in M2:
- Built dev connection screen (`mobile/lib/features/home/dev_screen.dart`, route `/dev`).
- Added plain HTTP dev communication support (`isDevPlainHttp`) and config persistence.
- Implemented text sender with <= 1 MB limit and UUID deduplication.
- Implemented file picker & streaming sender with <= 50 MB limit, progress callback, and network retry policy.
- Added 13 automated unit tests in `mobile/test/transfer_service_test.dart`.
- Verified live end-to-end against M1 dev server with matching SHA-256 hash.

### Next (Milestone M5: Discovery):
- PC mDNS advertiser (`mdns-sd`) registering `_clipsync._tcp.local.` with TXT records `id`, `name`, `v=1`, `fp` (first 16 hex chars of cert fingerprint). Re-registers on network interface changes.
- Mobile `PcResolver`:
  1. Try cached host and port with `GET /info` (1.5s timeout) verifying `device_id`.
  2. mDNS lookup for `_clipsync._tcp` matching `id` (5s timeout).
  3. Fail with "PC not found" offering manual fallback.
- Test: after PC's IP changes (WiFi reconnect / simulated IP change), phone finds it within 10s with no user action.

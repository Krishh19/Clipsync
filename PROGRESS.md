# ClipSync Progress Log

## Current Status: Milestone M3 (Share Target & Tile) Complete ✅

| Milestone | Status | Description |
|---|---|---|
| **M0: Skeleton** | ✅ Complete | Repository layout, Tauri 2 desktop app, Flutter mobile app, build verification |
| **M1: Rust Server Dev Mode** | ✅ Complete | Axum server, `/info`, `/text`, `/file` dev mode, clipboard write, file save |
| **M2: Flutter Sender MVP** | ✅ Complete | Dev screen, manual host/token, text send, file upload |
| **M3: Share Target & Tile** | ✅ Complete | Android share sheet, `QuickSendActivity`, `ClipboardTileService` |
| **M4: Security & Pairing** | ⏳ Pending (Next) | TLS generation, QR pairing, device secrets, pinned client |
| **M5: Discovery** | ⏳ Pending | mDNS registration, `nsd`, resolver fallback |
| **M6: Windows Product** | ⏳ Pending | Tauri React UI, system tray, history SQLite, settings |
| **M7: PC to Phone** | ⏳ Pending | WebSocket `/events`, clipboard watcher, global hotkey, phone notifications |
| **M8: Polish & Release** | ⏳ Pending | NSIS installer with firewall rule, release APK, error states |

### Done in M3:
- Configured Android manifest (`mobile/android/app/src/main/AndroidManifest.xml`):
  - Intent filters for `ACTION_SEND` and `ACTION_SEND_MULTIPLE` handling mime types `text/plain`, `image/*`, `video/*`, and `*/*`.
  - Configured `QuickSendActivity` with transparent theme (`@style/TranslucentTheme`) for foreground clip reading and immediate forwarding.
  - Configured `ClipboardTileService` with `BIND_QUICK_SETTINGS_TILE` for Quick Settings one-tap sending.
- Implemented `ShareReceiverScreen` (`mobile/lib/features/share_receiver/share_receiver_screen.dart`):
  - Compact dialog UI matching platform conventions.
  - Linear progress bar showing active streaming percentage and current item name.
  - Sequential multi-item queue handling (`ACTION_SEND_MULTIPLE`).
  - Pre-transmission size check rejecting items > 50 MB with error state.
  - Success state displaying green checkmark and auto-dismissing after 1.5 seconds (`SystemNavigator.pop()`).
  - Failure state displaying error details with Retry and Close buttons.
- Wired stream listeners in `mobile/lib/main.dart` with `receive_sharing_intent`:
  - Handled incoming shared media while app is running in background.
  - Handled initial shared media on cold start.
- Enhanced `HomeScreen` (`mobile/lib/features/home/home_screen.dart`):
  - Foreground "Send clipboard" button reading primary clip via `Clipboard.getData`.
  - Added URL pattern recognition marking web URLs with `kind: 'link'`.
- Added 8 automated tests in `mobile/test/share_receiver_test.dart`:
  - Verified streaming progress bar and active item name.
  - Verified success checkmark and auto-close timer dismissal.
  - Verified sequential queue processing for multiple items.
  - Verified pre-send size rejection for items > 50 MB.
  - Verified error state and Retry button re-executing transfer.
  - Verified AndroidManifest intent filters and Kotlin component registrations.
- Verified live end-to-end acceptance criteria (`mobile/bin/m3_e2e_test.dart`):
  - Share link landed on Windows clipboard.
  - Share photo saved to `Downloads/ClipSync` as image.
  - Share video saved to `Downloads/ClipSync` as video.
  - Quick Settings tile simulation sent clipboard text to Windows PC.

### Done in M2:
- Built dev connection screen (`mobile/lib/features/home/dev_screen.dart`, route `/dev`) with Host, Port, and Token configuration.
- Added plain HTTP dev communication support (`isDevPlainHttp`) in `mobile/lib/core/api_client.dart` and dev configuration persistence in `mobile/lib/data/secure_store.dart`.
- Implemented text sender:
  - Enforced client-side text limit check (<= 1 MB) before sending.
  - Unique UUID `client_id` deduplication header.
  - Verified text sent from Flutter arrives on Windows clipboard (ready for Ctrl+V).
- Implemented file picker & streaming sender:
  - Integrated `file_picker` for photos, videos, and files up to 50 MB.
  - Enforced client-side size limit rejection (> 50 MB rejected before upload).
  - Streamed file upload with real-time percentage progress callback.
  - Inferred MIME types dynamically.
  - Implemented network error retry policy: retries twice with exponential backoff on network errors only; never retries on 4xx responses.
- Added 13 automated unit tests in `mobile/test/transfer_service_test.dart`.
- Verified live end-to-end against M1 dev server (`mobile/bin/m2_e2e_test.dart`) with identical SHA-256 hash.

### Next (Milestone M4: Security & Pairing):
- Self-signed ECDSA P-256 TLS cert generation via `rcgen` (valid 10 years, SAN localhost & PC hostname) saved in `%APPDATA%/ClipSync/tls/`. Calculate DER SHA-256 fingerprint.
- QR pairing payload generation (`clipsync://pair?...`). 128-bit pairing token (single-use, 5 min TTL) returning 256-bit base64url device secret.
- Private IP filter (10/8, 172.16/12, 192.168/16, 169.254/16, fe80::/10, loopback) and rate limiting.
- Mobile QR scanner with `mobile_scanner`, URL parser, `PinnedClient` checking DER fingerprint in `badCertificateCallback`.
- Store device secret in `flutter_secure_storage`.
- Remove `dev_plain_http` feature dependency and verify rejection of unauthenticated/revoked requests.

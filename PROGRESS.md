# ClipSync Progress Log

## Current Status: Milestone M2 (Flutter Sender MVP) Complete ✅

| Milestone | Status | Description |
|---|---|---|
| **M0: Skeleton** | ✅ Complete | Repository layout, Tauri 2 desktop app, Flutter mobile app, build verification |
| **M1: Rust Server Dev Mode** | ✅ Complete | Axum server, `/info`, `/text`, `/file` dev mode, clipboard write, file save |
| **M2: Flutter Sender MVP** | ✅ Complete | Dev screen, manual host/token, text send, file upload |
| **M3: Share Target & Tile** | ⏳ Pending (Next) | Android share sheet, `QuickSendActivity`, `ClipboardTileService` |
| **M4: Security & Pairing** | ⏳ Pending | TLS generation, QR pairing, device secrets, pinned client |
| **M5: Discovery** | ⏳ Pending | mDNS registration, `nsd`, resolver fallback |
| **M6: Windows Product** | ⏳ Pending | Tauri React UI, system tray, history SQLite, settings |
| **M7: PC to Phone** | ⏳ Pending | WebSocket `/events`, clipboard watcher, global hotkey, phone notifications |
| **M8: Polish & Release** | ⏳ Pending | NSIS installer with firewall rule, release APK, error states |

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
- Added 13 automated unit tests in `mobile/test/transfer_service_test.dart`:
  - Network error retry backoff verification (recovering on 2nd and 3rd attempts, failing after 3).
  - Immediate failure without retry on 401, 413, and 400.
  - Client-side size limit enforcement for text (> 1 MB) and files (> 50 MB).
  - MIME type inference.
  - Root widget smoke test.
- Verified live end-to-end against M1 dev server (`mobile/bin/m2_e2e_test.dart`):
  - Sent text verified on Windows clipboard with `Get-Clipboard`.
  - Streamed 20 MB test video (`20,971,520 bytes`) with progress callback.
  - Verified identical SHA-256 hash on arrival: `D6D4CE27BB4DC9689D5DE23035EDD0B96044BD54A20CAF7FB7F373BFB169597F`.

### Next (Milestone M3):
- Configure AndroidManifest intent filters for `ACTION_SEND` and `ACTION_SEND_MULTIPLE`.
- Implement `QuickSendActivity` for instant clipboard sharing on window focus.
- Implement `ClipboardTileService` for one-tap Quick Settings tile sending.
- Build compact `ShareReceiverScreen` UI.
- Verify sharing link from Chrome, photo from Gallery, video from Files, and tile clipboard send.

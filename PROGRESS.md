# ClipSync Progress Log

## Current Status: Milestone M1 (Rust Server Dev Mode) Complete ✅

| Milestone | Status | Description |
|---|---|---|
| **M0: Skeleton** | ✅ Complete | Repository layout, Tauri 2 desktop app, Flutter mobile app, build verification |
| **M1: Rust Server Dev Mode** | ✅ Complete | Axum server, `/info`, `/text`, `/file` dev mode, clipboard write, file save |
| **M2: Flutter Sender MVP** | ⏳ Pending (Next) | Dev screen, manual host/token, text send, file upload |
| **M3: Share Target & Tile** | ⏳ Pending | Android share sheet, `QuickSendActivity`, `ClipboardTileService` |
| **M4: Security & Pairing** | ⏳ Pending | TLS generation, QR pairing, device secrets, pinned client |
| **M5: Discovery** | ⏳ Pending | mDNS registration, `nsd`, resolver fallback |
| **M6: Windows Product** | ⏳ Pending | Tauri React UI, system tray, history SQLite, settings |
| **M7: PC to Phone** | ⏳ Pending | WebSocket `/events`, clipboard watcher, global hotkey, phone notifications |
| **M8: Polish & Release** | ⏳ Pending | NSIS installer with firewall rule, release APK, error states |

### Done in M1:
- Configured `dev_plain_http` feature in `desktop/src-tauri/Cargo.toml`.
- Configured static dev token authentication (`dev-token-clipsync`).
- Implemented `GET /api/v1/info` returning `name`, `device_id`, and `protocol: 1`.
- Implemented `POST /api/v1/text`:
  - Enforced 1 MB maximum text payload limit (returns 413 if exceeded).
  - Implemented 60-second in-memory client ID deduplication.
  - Connected `arboard` clipboard writer to automatically copy incoming text/links to the Windows clipboard.
  - Inserted history records into SQLite database.
- Implemented `POST /api/v1/file`:
  - Enforced `Content-Length` header check (returns 413 immediately if > 50 MB or missing).
  - Streamed body to `.partial/<uuid>` while counting bytes; aborted, deleted partial file, and returned 413 if byte count exceeded 50 MB.
  - Filename sanitization (Windows reserved names, path traversal, control chars, trailing dots/spaces, 120-char limit).
  - Handled duplicate filenames with unique suffixes (`name (1).ext`).
  - Saved files to `Downloads/ClipSync`.
- Created standalone `src/bin/dev_server.rs` running plain HTTP on port 47821.
- Added 20 unit and integration tests (`tests/server_tests.rs`):
  - 13 unit tests for dedup, filename sanitizing, auth, and streaming byte limit abort with cleanup.
  - 7 integration tests for all endpoints, limits, and auth.
- **Verification Results**:
  - `cargo test --features dev_plain_http`: 20 passed, 0 failed.
  - `curl` `GET /api/v1/info`: Verified 200 with name and device_id.
  - `curl` `POST /api/v1/text`: Verified 201 response and text verified on Windows clipboard with `Get-Clipboard`.
  - `curl` `POST /api/v1/file`: Verified 201 response and file saved cleanly to `Downloads/ClipSync`.
  - `curl` 51 MB upload: Verified 413 response and 0 leftover files in `.partial/`.

### Next (Milestone M2):
- Build Flutter sender MVP dev screen with host, port, and token fields.
- Implement text send and file picker / sender with progress callback.
- Verify text sent from Flutter appears on PC clipboard and files transfer with identical SHA-256.

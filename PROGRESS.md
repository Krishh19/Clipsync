# ClipSync Progress Log

## Current Status: Milestone M0 (Skeleton) Complete ✅

| Milestone | Status | Description |
|---|---|---|
| **M0: Skeleton** | ✅ Complete | Repository layout, Tauri 2 desktop app, Flutter mobile app, build verification |
| **M1: Rust Server Dev Mode** | ⏳ Pending (Next) | Axum server, `/info`, `/text`, `/file` dev mode, clipboard write, file save |
| **M2: Flutter Sender MVP** | ⏳ Pending | Dev screen, manual host/token, text send, file upload |
| **M3: Share Target & Tile** | ⏳ Pending | Android share sheet, `QuickSendActivity`, `ClipboardTileService` |
| **M4: Security & Pairing** | ⏳ Pending | TLS generation, QR pairing, device secrets, pinned client |
| **M5: Discovery** | ⏳ Pending | mDNS registration, `nsd`, resolver fallback |
| **M6: Windows Product** | ⏳ Pending | Tauri React UI, system tray, history SQLite, settings |
| **M7: PC to Phone** | ⏳ Pending | WebSocket `/events`, clipboard watcher, global hotkey, phone notifications |
| **M8: Polish & Release** | ⏳ Pending | NSIS installer with firewall rule, release APK, error states |

### Done in M0:
- Initialized Git repository and set up root documentation (`docs/SPEC.md`, `docs/PROTOCOL.md`, `README.md`, `PROGRESS.md`, `DECISIONS.md`, `.gitignore`).
- Verified local toolchains: Rust 1.100, MSVC v143, Flutter 3.50, Android SDK 37, Node 22.
- **Desktop (`desktop/`)**:
  - Scaffolding complete per Section 6 of SPEC.
  - Rust backend modules in `src-tauri/`: `main.rs`, `lib.rs`, `state.rs`, `config.rs`, `commands.rs`, `tray.rs`, `discovery.rs`, `pairing.rs`, `hotkey.rs`, `notify.rs`, `clipboard/` (`watcher.rs`, `writer.rs`), `server/` (`routes.rs`, `auth.rs`, `tls.rs`, `upload.rs`, `ws.rs`, `errors.rs`, `ratelimit.rs`), `storage/` (`db.rs`, `files.rs`, `sanitize.rs`).
  - React/TypeScript frontend with tabs for Home, History, Devices, Settings, Help.
  - `cargo check`: Passed (0 errors, 0 warnings).
  - `cargo test`: Passed (all 3 unit tests passed).
  - `cargo build`: Passed (`clipsync-desktop.exe` binary built).
  - `npm run build`: Passed (TypeScript check & Vite production bundle created).
- **Mobile (`mobile/`)**:
  - Scaffolding complete per Section 6 and Section 10 of SPEC.
  - Riverpod, GoRouter, Dio, Drift, and Kotlin native services configured.
  - Modules in `lib/`: `core/` (pinned client, resolver, models, api/events clients), `data/` (Drift database, secure store), `services/` (transfers, events, notifications), `features/` (home, history, pairing, settings, share receiver).
  - Native Kotlin stubs: `MainActivity.kt`, `QuickSendActivity.kt`, `ClipboardTileService.kt`.
  - AndroidManifest configured with permissions (`INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`) and intent filters for `ACTION_SEND` and `ACTION_SEND_MULTIPLE`.
  - `flutter analyze`: Passed (0 issues).
  - `flutter test`: Passed (all smoke tests passed).
  - `flutter build apk --debug`: Passed (`build/app/outputs/flutter-apk/app-debug.apk` built).

### Next (Milestone M1):
- Implement plain HTTP dev server behind `dev_plain_http` feature with static dev token.
- Implement `/info`, `/text`, `/file` with byte limits and filename sanitizing.
- Write text to Windows clipboard via `arboard`.
- Save files to `Downloads/ClipSync`.
- Verify curl integration tests and unit tests.

# ClipSync: Build Specification (Flutter + Rust)

*Working name “ClipSync”. Written for AI-assisted implementation. Version 1.0, 23 November 2026.*

## 1. How to use this document with your AI IDE

Paste this whole document into the IDE as project context, or save it as `docs/SPEC.md` and reference it in every session. Rules for the AI:

- Build **one milestone at a time** (section 12), in order. After each milestone: build, run the tests, summarise what changed, and stop.
- Do not add features outside this spec. If something is ambiguous, choose the simplest option and record it in `DECISIONS.md`.
- Use the latest stable version of every dependency (`cargo add`, `flutter pub add`). Crate and package APIs change, so read the current docs or source before using an API. Never guess method names.
- Never log clipboard contents, tokens, or secrets.
- Commit after each milestone and keep `PROGRESS.md` updated with done, next, and known issues.

**Kickoff prompt to paste first:**

> Read docs/SPEC.md completely. Create the repository skeleton from section 6 and implement Milestone M0 only. When it builds cleanly, summarise what you did and wait for my go-ahead before starting M1.

**Prompt template for every later milestone:**

> Implement Milestone Mx from docs/SPEC.md. Follow the protocol in section 7 exactly. Add the tests listed for it, run them, and fix failures. Then check every acceptance criterion and report which pass. Do not start the next milestone.

## 2. Product overview

ClipSync sends clipboard-style content from an Android phone to a Windows PC (and text back) over the local WiFi network. No cloud, no account, no internet connection required.

**Supported content (v1):** text, links, photos, short videos, and other files, all up to 50 MB.

**Goals**

- Phone to PC in two taps: Share, then ClipSync.
- Text and links land directly on the Windows clipboard. Images optionally too. Videos and files are saved to a folder with a notification.
- PC to phone: push text to the phone with a hotkey or automatically.
- Automatic discovery, one-time QR pairing, encrypted and authenticated traffic.
- The Windows app idles in the system tray using very little RAM.

**Non-goals (v1)**

- iOS, macOS, or Linux clients
- Internet relay or cloud sync
- Reading the Android clipboard in the background (the OS forbids it)
- Files over 50 MB, folders, resumable transfers
- Multiple PCs per phone (a PC may pair with several phones; a phone has one active PC)

**User stories**

1. I share a photo from Gallery to ClipSync. It appears in `Downloads/ClipSync` on my PC and I get a notification.
2. I copy a link on my phone and tap the ClipSync Quick Settings tile. I press Ctrl+V on the PC and the link pastes.
3. I copy text on my PC and press Ctrl+Shift+S. My phone shows a notification with a Copy button.
4. On first launch I scan a QR code once and never configure anything again.

## 3. Platform constraints that shape the design

- **Android 10+ blocks background clipboard reads.** Phone to PC must therefore be explicit: share sheet, Quick Settings tile, in-app button. The clipboard can be read only while an activity has window focus.
- **Windows clipboard** can be observed in real time. Poll the clipboard sequence number every 250 ms; it is cheap and reliable.
- **Windows Firewall** shows a prompt on the first inbound listen, and the Public network profile blocks inbound connections by default. The UI must show a troubleshooting hint, and the installer should add an inbound rule for the app.
- **Router quirks:** guest networks and AP isolation block device-to-device traffic, and some routers block multicast. Always offer manual host entry.
- **DHCP:** IPs change. Identify the PC by `device_id`, never by IP alone.

## 4. Architecture

Two apps speak one HTTPS + WebSocket protocol (section 7).

- **Windows app (Rust, Tauri 2):** an axum HTTPS server running inside the Tauri backend on its tokio runtime; mDNS advertiser; clipboard watcher and writer; SQLite history; system tray; a React window for pairing, history, and settings.
- **Android app (Flutter):** Dart HTTPS client with certificate pinning, WebSocket client for PC-to-phone events, Android share target, Quick Settings tile, optional foreground service.

Phone-to-PC path: share intent → resolve PC (cached host, then mDNS, then manual) → pinned HTTPS POST → PC authenticates, validates, saves → writes clipboard → notification and history row.

PC-to-phone path: clipboard watcher, hotkey, or UI → WebSocket event to the connected phone → local notification (and optional download).

## 5. Tech stack

**Windows**

| Concern | Choice |
| --- | --- |
| Shell and UI | Tauri 2, React, TypeScript, Vite, plain CSS (follow system light or dark) |
| Server | tokio, axum, axum-server with rustls, tower-http (body limits, tracing) |
| TLS | rustls, rcgen (self-signed certificate, generated once) |
| Discovery | mdns-sd |
| Clipboard | arboard (text, images), clipboard-win (sequence number, CF\_HDROP file lists) |
| Storage | rusqlite with the bundled feature |
| Errors and logs | thiserror, anyhow, tracing, tracing-appender |
| Misc | serde, serde\_json, uuid, sha2, rand, qrcode, image |
| Tauri plugins | notification, autostart, single-instance, global-shortcut, dialog, opener |

Tauri 2 has a built-in tray API, so no separate tray crate is needed.

**Android (Flutter, minSdk 26, target latest stable)**

- State and routing: `flutter_riverpod`, `go_router`
- HTTP: `dio` with a custom `HttpClient` (see section 8)
- WebSocket: `web_socket_channel` (`IOWebSocketChannel` with a custom client and headers)
- Discovery: `nsd`
- QR: `mobile_scanner`
- Share target: `receive_sharing_intent` (fall back to `share_handler` if it fails on the current Flutter version)
- Storage: `flutter_secure_storage`, `shared_preferences`, `drift` with `sqlite3_flutter_libs`
- Notifications and background: `flutter_local_notifications`, `flutter_foreground_task`, `permission_handler`
- Files and utilities: `file_picker`, `path_provider`, `crypto`, `uuid`
- Native Kotlin for the tile and clipboard activity (section 10)

## 6. Repository layout

```
clipsync/
  README.md  DECISIONS.md  PROGRESS.md
  docs/
    SPEC.md  PROTOCOL.md
  desktop/                    Tauri 2 app
    src/                      React UI (pages: Home, History, Devices, Settings, Help)
    src-tauri/
      Cargo.toml
      src/
        main.rs  lib.rs  state.rs  config.rs  commands.rs  tray.rs
        server/    mod.rs routes.rs auth.rs tls.rs upload.rs ws.rs errors.rs ratelimit.rs
        discovery.rs  pairing.rs  hotkey.rs  notify.rs
        clipboard/ mod.rs watcher.rs writer.rs
        storage/   mod.rs db.rs files.rs sanitize.rs
  mobile/                     Flutter app
    lib/
      main.dart
      core/       pinned_client.dart api_client.dart events_client.dart resolver.dart models.dart
      features/   pairing/ home/ history/ settings/ share_receiver/
      services/   transfer_service.dart events_service.dart notifications.dart
      data/       db.dart secure_store.dart
    android/app/src/main/kotlin/.../
      MainActivity.kt  QuickSendActivity.kt  ClipboardTileService.kt
```

## 7. Protocol specification (v1)

Base URL: `https://<host>:<port>/api/v1`. Self-signed certificate, TLS 1.2 or newer. Default port **47821**; if busy, try the next 20 ports. The real port is advertised via mDNS and in the pairing QR. Auth: `Authorization: Bearer <device_secret>` on everything except `GET /info` and `POST /pair`.

| Endpoint | Auth | Purpose |
| --- | --- | --- |
| `GET /info` | none | Returns `name`, `device_id`, `protocol` (1) |
| `POST /pair` | one-time token | Exchange a pairing token for a device secret |
| `DELETE /pair` | bearer | Phone unpairs itself |
| `POST /text` | bearer | Send text or a link |
| `POST /file` | bearer | Upload a photo, video, or file |
| `GET /files/{id}` | bearer | Download a file the PC offered (supports Range) |
| `GET /events` (WebSocket) | bearer | Live PC-to-phone events and keepalive |

**POST /pair** body: `token`, `device_id` (UUID made by the phone), `device_name`, `platform` (`android`). Response 200: `device_secret` (256-bit random, base64url), `server_device_id`, `server_name`. A wrong, expired, or used token returns 401 `invalid_token`.

**POST /text** body (JSON): `kind` (`text` or `link`), `content` (UTF-8, at most 1 MB), `client_id` (UUID; the server ignores repeats seen within 60 s). Response 201: `id`.

**POST /file**: raw request body, streamed. Headers: `Content-Length` (required), `Content-Type`, `X-File-Name` (URL-encoded UTF-8 original name), `X-Client-Id`. Server behaviour:

1. If `Content-Length` is missing or above the limit, reject with 413 before reading the body.
2. Stream to `<save_dir>/.partial/<uuid>` while counting bytes. If the count passes the limit, abort, delete the partial file, and return 413.
3. Sanitise the name (section 8), pick a unique final name (`name (1).ext`), and move the file into place.
4. Classify as `image`, `video`, or `file` by MIME type, then extension.
5. Apply the auto-copy rules (section 15), insert a history row, show a notification.

Response 201: `id`, `name`, `size`, `kind`.

**WebSocket /events** (server to client, JSON messages with a `type` field):

- `hello`: `server_name`, `protocol`
- `text`: `id`, `kind`, `content`, `ts`
- `file_offer`: `id`, `name`, `size`, `mime`, `ts` (the phone then calls `GET /files/{id}`)
- `ping` every 20 s; the client answers `pong`. The server closes the connection after two missed pongs.

The client reconnects with exponential backoff from 1 s up to 30 s.

**Errors:** an HTTP status plus a JSON body with `error.code` and `error.message`. Codes: `unauthorized` 401, `invalid_token` 401, `bad_request` 400, `too_large` 413, `unsupported` 415, `rate_limited` 429, `internal` 500.

**Pairing QR payload** (a URL): `clipsync://pair?host=<ip>&port=<port>&token=<hex>&fp=<sha256-hex>&id=<server_device_id>&name=<url-encoded>`

**mDNS:** service `_clipsync._tcp.local.`, TXT records `id`, `name`, `v=1`, `fp` (first 16 hex characters of the certificate fingerprint).

## 8. Security model

- **Certificate:** generated once with rcgen (ECDSA P-256, 10-year validity, SAN includes the PC hostname and `localhost`), stored in `%APPDATA%/ClipSync/tls/`. Fingerprint = lowercase hex SHA-256 of the DER certificate.
- **Pinning on the phone:** build a Dart `HttpClient` whose `badCertificateCallback` returns true only when the SHA-256 of the presented certificate DER equals the stored fingerprint. Use this client for Dio (via `IOHttpClientAdapter`) and for the WebSocket. Pinning applies to the very first request too, because the QR carries the fingerprint.
- **Pairing:** the PC generates a 128-bit token, valid for 5 minutes and single use, shown only as a QR code in the UI. A successful `POST /pair` returns a long-lived device secret.
- **Secrets at rest:** the PC stores only a SHA-256 hash of each device secret. The phone stores the secret in `flutter_secure_storage`. The PC UI can revoke any device, and revoked devices get 401 immediately.
- **Network filter:** accept connections only from private or link-local source addresses (10/8, 172.16/12, 192.168/16, 169.254/16, fe80::/10, loopback).
- **Rate limits:** 5 pair attempts per minute per IP; 5 failed auths from an IP blocks it for 60 s.
- **Filenames:** strip path separators, control characters, and reserved Windows names (CON, PRN, AUX, NUL, COM1-9, LPT1-9); trim trailing dots and spaces; cap at 120 characters; never write outside the save folder.
- **Body limits:** `/pair` 4 KB, `/text` 1 MB, `/file` 50 MB (configurable).
- **Logging:** never log clipboard contents, tokens, or secrets. Log to a rotating file in `%APPDATA%/ClipSync/logs/`.
- **Android:** `usesCleartextTraffic` is false. The app talks only to the paired PC.

## 9. Windows app specification

**Process behaviour**

- Single instance. Autostart launches with `--minimized` straight to the tray. Closing the window hides it to the tray.
- Tray menu: Open, Pause receiving (toggle), Send clipboard to phone, Open save folder, Quit.

**Backend modules**

- `config`: JSON settings in `%APPDATA%/ClipSync/config.json` with the defaults from section 15. Changes apply live (restart the server only when the port changes).
- `server`: axum router, auth middleware, handlers from section 7, graceful shutdown.
- `discovery`: registers the mDNS service and re-registers when the network changes.
- `pairing`: creates tokens, builds the QR payload, verifies and consumes tokens, issues device secrets.
- `clipboard::writer`: sets text (arboard), images (decode PNG or JPEG with the `image` crate, then arboard), and file lists (CF\_HDROP via clipboard-win). Before every write, store a hash of the content as `last_written`.
- `clipboard::watcher`: dedicated thread polling the sequence number every 250 ms. On change, read the text; skip it if it matches `last_written`; skip it if the clipboard carries the registered format `ExcludeClipboardContentFromMonitorProcessing` (password managers set it); otherwise, if auto-send is on and a phone is connected, send a `text` event.
- `storage`: SQLite with migrations; retention cleanup at startup and daily.
- `notify`: toast on receive. Title: `From <phone name>`. Body: the first 80 characters, or the file name. Clicking a file toast opens the folder.
- `hotkey`: global shortcut (default Ctrl+Shift+S) sends the current clipboard text to connected phones.
- `commands`: Tauri IPC for the UI: `get_status`, `get_pair_qr` (SVG, payload, expiry), `list_devices`, `revoke_device`, `get_history`, `delete_history_item`, `clear_history`, `get_settings`, `set_settings`, `open_folder`, `send_text_to_phone`, `send_file_to_phone` (registers the file in an in-memory offers map for 1 hour, then emits `file_offer`), `copy_history_item`.

**UI pages (React)**

- *Home:* server status, `IP:port`, count of connected phones, and a Pair new phone button that opens a QR modal with a 5-minute countdown.
- *History:* newest first; icon, preview (image thumbnails), time, device; actions Copy, Open, Show in folder, Delete.
- *Devices:* paired phones, last seen, Revoke.
- *Settings:* every option in section 15.
- *Help:* firewall and network troubleshooting steps.

## 10. Android app specification

**Screens**

1. *Pairing:* scan the QR with `mobile_scanner`, parse `clipsync://pair`, call `GET /info` with pinning, verify `id`, call `POST /pair`, store everything. Manual fallback: host, port, token, and fingerprint fields.
2. *Home:* connection chip (Connected, Searching, Offline) with the PC name; large Send clipboard button; text field with Send; Send photo / video / file button; recent transfers with progress and Retry on failure.
3. *History:* from the local database; tap to copy or open.
4. *Settings:* paired PC info, Unpair, a toggle for the foreground service (needed to receive from the PC while the app is closed), notification permission status, about.
5. *Share receiver:* a compact screen shown when launched by a share intent. Shows the name and progress, then a check mark, and closes after 1.5 s. Handles multiple items one after another. Rejects files over 50 MB on the client with a clear message. On failure shows Retry and Close.

**Services**

- `PinnedClient`: builds the pinned `HttpClient` and Dio instance (section 8).
- `PcResolver`: (1) try the last known host and port with `GET /info`, 1.5 s timeout, verifying `device_id`; (2) mDNS lookup for `_clipsync._tcp` matching the id, 5 s; (3) fail with PC not found and offer manual entry. Cache the successful host and port.
- `TransferService`: a queue; `sendText`, `sendFile` (stream from disk with `Content-Length` and a progress callback); retry twice with backoff on network errors only, never on 4xx.
- `EventsService`: keeps the WebSocket alive with backoff. On `text`, show a notification with a Copy action. On `file_offer`, show a Download action that saves the file to the app’s external Downloads folder and offers Open.

**Android native (Kotlin and manifest)**

- Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `POST_NOTIFICATIONS`, plus the foreground service permission for the chosen type. Use a type that is valid on Android 14 and later (`specialUse` with a justification string); `dataSync` has time limits on Android 15.
- Intent filters on `MainActivity` for `ACTION_SEND` and `ACTION_SEND_MULTIPLE` with MIME types `text/plain`, `image/*`, `video/*`, `*/*`.
- `QuickSendActivity`: translucent, no UI. In `onWindowFocusChanged(true)` it reads the primary clip. For text it relaunches `MainActivity` with an `ACTION_SEND` intent carrying that text; for a content URI it does the same with `EXTRA_STREAM`. Then it finishes. This reuses the share-receiver pipeline.
- `ClipboardTileService`: a Quick Settings tile whose click launches `QuickSendActivity` (use the PendingIntent overload on API 34+).
- Optional later: a home-screen widget that launches `QuickSendActivity`.

## 11. Data models

**PC (SQLite)**

```
devices(id TEXT PRIMARY KEY, name TEXT, platform TEXT, secret_hash TEXT,
        created_at INTEGER, last_seen INTEGER, revoked INTEGER DEFAULT 0)
items(id TEXT PRIMARY KEY, direction TEXT CHECK(direction IN ('in','out')),
      kind TEXT CHECK(kind IN ('text','link','image','video','file')),
      device_id TEXT, text TEXT, file_path TEXT, file_name TEXT, mime TEXT,
      size INTEGER, created_at INTEGER)
CREATE INDEX idx_items_created ON items(created_at DESC);
```

**Phone**

- Secure storage keys: `self.device_id`, `pc.device_id`, `pc.name`, `pc.host`, `pc.port`, `pc.fingerprint`, `pc.secret`
- Drift table `transfers`: `id`, `direction`, `kind`, `label`, `size`, `status` (queued, sending, done, failed), `error`, `created_at`

## 12. Milestones

Each milestone ends with a working build. Do them in order.

**M0: Skeleton.** Create the layout from section 6. The Tauri window opens; the Flutter app runs on a device. *Accept:* `cargo build` and `flutter run` both succeed.

**M1: Rust server, dev mode.** Plain HTTP behind a `dev_plain_http` Cargo feature with a static dev token. Implement `/info`, `/text`, `/file` with limits and filename sanitising; write text to the clipboard; save files. *Accept:* curl can send text (it appears on the clipboard) and a file; a 51 MB upload returns 413 and leaves no partial file; unit tests for sanitising and limits pass.

**M2: Flutter sender MVP.** A dev screen with host, port, and token fields; send text; pick and send a file with progress. *Accept:* Ctrl+V on the PC pastes the sent text; a 20 MB video arrives with an identical SHA-256.

**M3: Share target and clipboard send.** Manifest filters, share receiver screen, Send clipboard button, `QuickSendActivity`, Quick Settings tile. *Accept:* sharing a link from Chrome, a photo from Gallery, and a video from Files all arrive; the tile sends the current clipboard text.

**M4: Security.** TLS with rcgen; pairing with token and QR; device secrets; auth middleware; private-IP filter; rate limits. Flutter: pinned client, QR scanner, secure storage. Remove the dev token and plain HTTP. *Accept:* unauthenticated requests get 401; a wrong fingerprint fails to connect; tokens expire after 5 minutes and work once; a revoked device gets 401.

**M5: Discovery.** mDNS advertising on the PC, `nsd` and `PcResolver` on the phone, manual fallback. *Accept:* after the PC’s IP changes (WiFi reconnect), the phone finds it within 10 s with no user action.

**M6: Windows product.** Tauri UI pages, tray, single instance, autostart, notifications, SQLite history and retention, live settings, firewall help page. *Accept:* the app runs from the tray, starts with Windows, history persists across restarts, and images and videos follow the settings.

**M7: PC to phone.** WebSocket events, clipboard watcher with loop prevention, hotkey, Send file to phone, Android `EventsService`, foreground service, notifications with Copy and Download. *Accept:* copying on the PC then pressing the hotkey shows a phone notification within 2 s; no echo loops in either direction.

**M8: Polish and release.** Friendly error messages, empty states, app icons, Windows installer (NSIS) that adds the firewall rule, release APK instructions, README with setup and troubleshooting. *Accept:* a fresh install on a clean PC and phone works by following the README only.

## 13. Testing

- **Rust unit tests:** filename sanitising (reserved names, traversal, unicode, length); token expiry and single use; size limit when the client lies about Content-Length; auth middleware; private-IP filter; `client_id` dedupe; retention cleanup.
- **Rust integration tests:** start the server on an ephemeral port and call every endpoint with `reqwest` using the pinned certificate.
- **Flutter tests:** QR URL parser; fingerprint comparison; resolver fallback order (mocked); transfer retry policy; share receiver widget states (progress, success, failure).
- **Manual checklist:** Android 10, 13, and 14 or 15; Windows 10 and 11; 2.4 and 5 GHz; 50 MB transfer on a weak signal; phone screen off; PC sleep and wake; guest network (expect a clear error); firewall set to the Public profile.

## 14. Edge cases and error handling

- Clipboard on the PC is empty or holds an unsupported format: do nothing, no error.
- Duplicate file names: `name (1).ext`.
- Upload interrupted: delete the partial file; the phone shows Retry.
- PC asleep or off: the phone shows PC not found with a manual option; no endless spinner.
- WiFi changed on the phone: drop the WebSocket, re-resolve, reconnect.
- HEIC and other images the `image` crate cannot decode: save the file as is and skip the clipboard step.
- Videos are never placed on the clipboard unless Copy received videos as files is on.
- Text over 1 MB: reject on the phone before sending, with a clear message.
- Echo loops: the watcher ignores anything the app itself wrote (`last_written`); the phone never re-sends content it received.
- Two phones sending at once: handle each request independently; order history by receive time.

## 15. Default settings

| Setting | Default |
| --- | --- |
| Port | 47821 |
| Save folder | `%USERPROFILE%/Downloads/ClipSync` |
| Max file size | 50 MB |
| Copy received text and links to clipboard | On |
| Copy received images to clipboard | On |
| Copy received videos as files | Off |
| Notifications on receive | On |
| Auto-send PC clipboard text to phone | Off (privacy; use the hotkey instead) |
| Send hotkey | Ctrl+Shift+S |
| Start with Windows | On after first pairing |
| History retention | 30 days or 500 items, whichever comes first |
| Device name | Windows computer name |

## 16. Definition of done and future ideas

**v1 is done when:** all milestones pass their acceptance criteria; a 50 MB video, a 10 MB photo, a link, and a 100 KB text all transfer correctly from the phone; text transfers from the PC to the phone; an unpaired device cannot send anything; and the README lets a new user set everything up unassisted.

**Later:** iOS share extension, macOS and Linux desktop clients on the same protocol, resumable uploads, zip-and-send folders, a home-screen widget, and a Wi-Fi Direct fallback.

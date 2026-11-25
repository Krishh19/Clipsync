# ClipSync

**Fast, private, local-network clipboard and file sync between Android and Windows.**

No cloud. No accounts. No subscriptions. No telemetry. Your clipboard and files never leave your local Wi-Fi network.

---

## ⚡ Highlights

- **Instant Phone → PC Transfer**: Share links, photos, videos, or files up to 50 MB directly from the Android Share Sheet or the Quick Settings tile. Text lands straight on your PC's clipboard (ready for `Ctrl+V`), and files land in your `Downloads\ClipSync` folder.
- **Instant PC → Phone Transfer**: Press `Ctrl+Shift+S` (or use the system tray menu) on Windows to push your PC clipboard text directly to your phone as an actionable notification with a **Copy** button.
- **End-to-End Cryptographic Security**: Self-signed ECDSA P-256 TLS certificate with strict SHA-256 fingerprint pinning on Android. No untrusted root CAs, no man-in-the-middle risks.
- **Zero-Config Pairing**: Scan a QR code on your PC screen with your phone's camera to securely pair in seconds, or expand **Manual Pairing Details** in the Desktop QR modal for one-click copy of Host IP, Port, Token, and SHA-256 Fingerprint.
- **In-App Photo & Text Viewers**: Built-in Desktop Lightbox modal (with zoom, Open in Photos, Show in Folder) and Mobile full-screen pinch-to-zoom `PhotoViewerScreen` + `TextDetailSheet` inspector.
- **Native Drag & Drop + Search History**: Drag files directly into the Desktop window or use `+ Pick File`, and filter transfer history across `All`, `Photos`, `Files`, `Text`, and `Links`.
- **Automatic Discovery**: Zero-configuration mDNS (`_clipsync._tcp.local.`) automatically re-discovers your PC when IP addresses change after Wi-Fi reconnects.
- **Privacy First**: Password manager entries (`ExcludeClipboardContentFromMonitorProcessing`) are automatically skipped. Strict two-way loopback suppression prevents clipboard reflection loops.

---

## 🏗️ Architecture

```
┌─────────────────────────────────┐           Local Wi-Fi Network          ┌──────────────────────────────────┐
│         Windows PC              │ ◄────────────────────────────────────► │          Android Phone           │
│                                 │                                        │                                  │
│  Tauri 2 + React + TypeScript   │    HTTPS (TLS 1.3 / ECDSA P-256)       │   Flutter (Dart 3.14+)           │
│  Axum REST + WebSocket Server  │      Certificate SHA-256 Pinning       │   Dio with PinnedClient          │
│  Arboard + Clipboard-Win        │                                        │   ReceiveSharingIntent           │
│  SQLite (rusqlite) Storage      │    mDNS Service Discovery              │   Drift SQLite + SecureStorage   │
│  mdns-sd Advertiser             │      _clipsync._tcp.local.             │   QuickSend & Tile Services      │
└─────────────────────────────────┘                                        └──────────────────────────────────┘
```

---

## 📋 System Requirements

| Platform | Minimum Requirement | Recommended |
|---|---|---|
| **Windows PC** | Windows 10 (64-bit) Version 1809+ | Windows 11 (64-bit) |
| **Android Phone** | Android 8.0 Oreo (API Level 26) | Android 13, 14, or 15 |
| **Network** | Both devices connected to the same local Wi-Fi / LAN | 5 GHz Wi-Fi or Ethernet on PC |

---

## 🚀 Quick Setup & Installation

### 1. Windows PC Installation

#### Option A: Run Pre-built Installer (Recommended)
1. Download and run `ClipSync-Setup.exe`.
2. The installer automatically registers the Windows Firewall inbound rule:
   ```cmd
   netsh advfirewall firewall add rule name="ClipSync" dir=in action=allow protocol=TCP localport=47821 program="%ProgramFiles%\ClipSync\clipsync-desktop.exe"
   ```
3. Launch **ClipSync** from the Start Menu or System Tray.

#### Option B: Build from Source
**Prerequisites:** Rust (`rustup` with MSVC build tools), Node.js (v20+), and npm.
```powershell
# 1. Clone repository
git clone https://github.com/ClipSync/clipsync.git
cd clipsync/desktop

# 2. Install frontend dependencies
npm install

# 3. Build React frontend & Tauri binary
npm run build
cd src-tauri
$env:PATH = "C:\Users\krish\.cargo\bin;$env:PATH"
cargo build --release
```
The compiled executable will be located at `desktop\src-tauri\target\release\clipsync-desktop.exe`.

---

### 2. Android Phone Installation

#### Option A: Install Release APK
1. Download `app-release.apk` to your phone.
2. Tap the APK to install (enable "Install unknown apps" in Settings if prompted).

#### Option B: Build from Source
**Prerequisites:** Flutter SDK (3.14+), Android SDK (API 34+), Java 17+.
```bash
cd clipsync/mobile
flutter pub get
flutter build apk --release
```
The output APK will be at `mobile/build/app/outputs/flutter-apk/app-release.apk`.

---

## 🔗 How to Pair (First-Time Setup)

1. **Open ClipSync on Windows**:
   - The Home tab displays your server status, local IP (e.g. `192.168.1.150:47821`), and connected phones.
   - Click the **Pair New Phone** button to open the pairing modal. A QR code appears with a 5-minute countdown.
2. **Open ClipSync on Android**:
   - Tap **Pair with PC** to open the built-in camera scanner.
   - Point your camera at the QR code on your PC screen.
   - ClipSync automatically parses the pairing payload, validates the PC's TLS certificate fingerprint, exchanges a single-use token for a 256-bit device secret, and stores the credentials in Android Keystore.
3. **Done!** Your phone and PC are now securely paired.

*(Optional Manual Fallback: If your camera is unavailable, tap **Manual Entry** on Android and enter the PC Host IP, Port, 128-bit Token, and SHA-256 Fingerprint displayed in the desktop pairing dialog).*

---

## 📱 Everyday Usage Guide

### Phone → PC Transfers

- **Share Links & Text**: In Chrome, Twitter, Reddit, or any app, tap **Share** → select **ClipSync**. The text or web link is instantly injected into your Windows clipboard, ready to paste with `Ctrl+V`.
- **Share Photos & Videos**: In Google Photos, Gallery, or Files, select one or more media files (up to 50 MB) and tap **Share** → **ClipSync**. A compact transfer dialog shows real-time progress. On completion, files are saved in your PC's `Downloads\ClipSync` folder.
- **Quick Settings Tile**: Add the **ClipSync Send** tile to your Android Quick Settings panel (swipe down twice → tap Edit / pencil icon → drag ClipSync to active tiles). Tap the tile at any time to instantly beam your phone's current clipboard to your PC!
- **Foreground Button**: Open the ClipSync app and tap **Send Clipboard** to send text or links directly.

### PC → Phone Transfers

- **Global Hotkey (`Ctrl+Shift+S`)**: Copy any text on your PC and press `Ctrl+Shift+S`. Your phone will vibrate and show a notification with the snippet and a **Copy** button. Tap **Copy** to place it on your Android clipboard.
- **System Tray Menu**: Right-click the ClipSync icon in your Windows notification area and select **Send clipboard to phone**.
- **Send Files from PC**: In the ClipSync desktop app, drag and drop or select a file to offer to your phone. Your phone displays a notification with a **Download** button that saves the file to Android's `Downloads` folder.

---

## 🛡️ Security & Privacy Architecture

ClipSync adheres strictly to zero-trust, local-only security principles:

1. **Self-Signed TLS with Strict Pinning**:
   - Desktop generates a 10-year ECDSA P-256 TLS certificate on first run (`%APPDATA%\ClipSync\tls\`).
   - The QR code contains the full DER SHA-256 certificate fingerprint.
   - Mobile validates the presented certificate in `badCertificateCallback` before establishing any connection.
2. **Ephemeral Pairing Tokens**:
   - Pairing tokens are 128-bit random hex strings valid for **5 minutes** and **single use**.
   - A successful exchange produces a 256-bit base64url device secret.
   - The PC stores only the SHA-256 hash of the secret in SQLite. Mobile stores the secret in encrypted `FlutterSecureStorage`.
3. **Network Isolation & Rate Limiting**:
   - The server only accepts connections from private RFC 1918 (10/8, 172.16/12, 192.168/16), link-local (169.254/16, fe80::/10), and loopback IP addresses. Public internet requests are blocked with `403 Forbidden`.
   - Pairing is rate-limited to 5 attempts per minute per IP.
   - 5 failed authentications blocks the client IP for 60 seconds.
4. **Password Manager Privacy Protection**:
   - The Windows clipboard watcher inspects clipboard format flags and skips any changes bearing the `ExcludeClipboardContentFromMonitorProcessing` format (registered by 1Password, Bitwarden, KeePass, etc.).
5. **Two-Way Echo Suppression**:
   - Content received from the phone is marked with `last_written_clipboard` on PC so the clipboard watcher will not reflect it back.
   - Mobile maintains an LRU cache (`LoopPrevention`) to guarantee received text is never re-transmitted.

---

## 🔧 Network Troubleshooting & FAQ

### Problem 1: "PC Not Found" / Connection Times Out

1. **Verify Same Wi-Fi Network**: Ensure both your phone and PC are connected to the same Wi-Fi router or access point.
2. **Disable Wi-Fi AP Isolation (Client Isolation)**: Some guest networks or Wi-Fi routers prevent wireless devices from communicating with one another. Open your router's admin settings and ensure **AP Isolation / Client Isolation** is turned **OFF**.
3. **Check Windows Network Profile**:
   - Open Windows **Settings** → **Network & Internet** → **Wi-Fi** (or Ethernet) → Click your network.
   - Ensure the Network Profile type is set to **Private network** (NOT Public). Public profiles block inbound discovery and REST traffic by default.
4. **Verify Windows Firewall Rule**:
   - Run PowerShell as Administrator and check if port 47821 is allowed:
     ```powershell
     netsh advfirewall firewall show rule name="ClipSync"
     ```
   - If missing, add the rule manually:
     ```powershell
     netsh advfirewall firewall add rule name="ClipSync" dir=in action=allow protocol=TCP localport=47821
     ```

### Problem 2: Phone Loses Connection in Background

1. **Battery Optimization**: Open Android Settings → Apps → ClipSync → Battery → Select **Unrestricted**.
2. **Foreground Service**: Open ClipSync Settings on your phone and verify **Background Receiving Service** is enabled. ClipSync runs an Android 14+ compliant `specialUse` foreground service to keep WebSocket connections alive when the screen is off.

### Problem 3: File Upload Fails (> 50 MB)

- ClipSync enforces a default maximum file size limit of 50 MB to prevent local network buffer bloat. You can adjust this limit in the PC app under the **Settings** tab.

---

## 🧪 Testing & Verification Suites

Both codebases include comprehensive automated test suites:

```powershell
# Run all Desktop Rust unit, security, discovery, product, and events tests (46 tests):
cd desktop\src-tauri
$env:PATH = "C:\Users\krish\.cargo\bin;$env:PATH"
cargo test

# Build React frontend (TypeScript check + Vite bundle):
cd ..
npm run build

# Run all Mobile Flutter unit, widget, pairing, resolver, and events tests (56 tests):
cd ..\mobile
flutter analyze
flutter test
```

---

## 🤝 Community & Governance

- [Security Policy](SECURITY.md) — Vulnerability reporting & local cryptographic architecture
- [Contributing Guide](CONTRIBUTING.md) — Development setup & pull request workflow
- [Code of Conduct](CODE_OF_CONDUCT.md) — Community standards (Contributor Covenant v2.1)

## 📄 License

ClipSync is licensed under the MIT License. See [LICENSE](LICENSE) for details.

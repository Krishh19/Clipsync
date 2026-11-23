# ClipSync Android Application

The mobile companion app for ClipSync, providing seamless bidirectional clipboard synchronization and high-speed local file transfer between Android and Windows PCs over your local Wi-Fi network.

---

## Features

- **Bidirectional Sync**: Instantly share text and links between Windows and Android clipboards.
- **Direct File Streaming**: Stream photos, videos, and files up to 50 MB directly to your PC.
- **Quick Settings Tile**: Single-tap "Send to PC" tile from your Android notification shade.
- **System Share Target**: Send content to your PC directly from any Android app's Share sheet.
- **Certificate Pinning**: End-to-end local HTTPS with TLS SHA-256 certificate fingerprint pinning.
- **3-Stage PC Discovery**: Direct cached probe (1.5s) → mDNS lookup for `_clipsync._tcp` (5s) → automatic IP cache updates.
- **Echo Loop Prevention**: Two-way deduplication ensuring items from the PC are never echoed back.
- **Foreground Service**: Background sync via Android 14+ `specialUse` foreground service.

---

## Technical Requirements

| Component | Requirement | Note |
|---|---|---|
| **OS Version** | Android 8.0+ (API 26+) | `minSdk = 26` |
| **Target SDK** | Android 14+ (API 34+) | `targetSdk = 34` / `compileSdk = 37` |
| **Java Compatibility** | Java 8+ / Java 17 | Core library desugaring enabled (`desugar_jdk_libs:2.1.4`) |
| **Architecture** | ARM64 (`arm64-v8a`), ARMv7 (`armeabi-v7a`), x86_64 | Standard Flutter multi-ABI support |

---

## Release Build & Packaging

### 1. Keystore Generation

To sign the release APK for distribution, create a release keystore using the Java `keytool` utility:

```powershell
keytool -genkey -v -keystore clipsync-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias clipsync
```

Store `clipsync-release-key.jks` in a secure location (or under `mobile/android/app/`). **Never commit your `.jks` file or passwords to version control.**

### 2. Configure `key.properties`

Create a file named `mobile/android/key.properties` (this file is excluded from Git via `.gitignore`):

```properties
storePassword=<YOUR_KEYSTORE_PASSWORD>
keyPassword=<YOUR_KEY_PASSWORD>
keyAlias=clipsync
storeFile=clipsync-release-key.jks
```

If `key.properties` is not present, Gradle gracefully falls back to the debug signing configuration so developer release builds (`flutter run --release`) continue to work seamlessly.

### 3. ProGuard & R8 Optimization

ClipSync includes tailored R8 rules in `mobile/android/app/proguard-rules.pro` to safeguard:
- Native SQLite3 libraries (`sqlite3_flutter_libs`)
- Drift ORM schema reflection
- Flutter Foreground Task background service (`specialUse` type)
- Camera and MLKit QR scanner components (`mobile_scanner`)
- Share intent handlers (`receive_sharing_intent`)

### 4. Build Release APK

To generate a standalone release APK:

```powershell
cd c:\Clipsync\mobile
flutter clean
flutter pub get
flutter build apk --release
```

The compiled release APK will be located at:
```
mobile/build/app/outputs/flutter-apk/app-release.apk
```

To build split per-ABI APKs (smaller individual download sizes):

```powershell
flutter build apk --release --split-per-abi
```

To build an Android App Bundle (AAB) for Google Play:

```powershell
flutter build appbundle --release
```

---

## Android Permissions & Lifecycle

ClipSync requests the following permissions in `AndroidManifest.xml`:

- `INTERNET` & `ACCESS_NETWORK_STATE`: Pinned TLS HTTP and WebSocket communication with your local PC.
- `ACCESS_WIFI_STATE` & `CHANGE_WIFI_MULTICAST_STATE`: Multicast DNS (mDNS) service discovery via `nsd`.
- `POST_NOTIFICATIONS`: Display incoming clipboard text ("Copy" action) and file offers ("Download" action).
- `FOREGROUND_SERVICE` & `FOREGROUND_SERVICE_SPECIAL_USE`: Maintains WebSocket keepalive when the app is in the background. Android 14+ compliant with subtype justification property:
  ```xml
  <property
      android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
      android:value="Receiving real-time clip updates and files from paired local PC" />
  ```
- `CAMERA`: QR code scanning during one-time PC pairing (`mobile_scanner`).

---

## Development & Testing

### Static Code Analysis
Run the Flutter analyzer to verify 0 warnings or lint issues:
```powershell
cd c:\Clipsync\mobile
flutter analyze
```

### Automated Test Suite
Run all unit and widget tests:
```powershell
cd c:\Clipsync\mobile
flutter test
```

Test coverage includes:
- **Pairing**: QR URI parsing, SHA-256 fingerprint verification, 4-step handshake, server device ID check.
- **Discovery**: 3-stage resolver (cache hit, mDNS fallback, automatic IP cache update, timeout fallback).
- **Events**: WebSocket keepalive, exponential backoff (1s..30s), ping/pong, notifications, download dispatch.
- **Loop Prevention**: SHA-256 echo suppression preventing circular sync loops between devices.
- **Share Target & Tile**: Multi-item sequential streaming, client-side 50 MB limits, Quick Settings tile intents.

# Contributing to ClipSync

Thank you for your interest in contributing to ClipSync!

## Project Structure

- `desktop/` — Windows Desktop app (Tauri 2 + Rust + Axum + React/TypeScript)
- `mobile/` — Android Mobile app (Flutter + Drift SQLite + Material 3)
- `assets/` & `scripts/` — Official brand icons and icon generation scripts

## Development Setup

### Prerequisites
- **Desktop**: Rust (stable), Node.js 20+, Windows 10/11 (WebView2)
- **Mobile**: Flutter SDK (stable), Android SDK (API 26+), Java 17

### Running Tests
```bash
# Desktop frontend build & Rust tests
cd desktop
npm ci && npm run build
cd src-tauri && cargo test --lib -j 2

# Mobile static analysis & tests
cd mobile
flutter pub get
flutter analyze
flutter test
```

## Pull Request Guidelines
1. Fork the repository and create a feature branch from `master`.
2. Ensure `cargo test`, `npm run build`, `flutter analyze`, and `flutter test` all pass with zero warnings or errors.
3. Follow our [Code of Conduct](CODE_OF_CONDUCT.md).
4. Keep commits focused and descriptive (e.g. `feat(desktop): ...`, `fix(mobile): ...`).

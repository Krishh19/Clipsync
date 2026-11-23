# Architecture & Technical Decisions (ADR)

## ADR-001: Milestone-by-Milestone Implementation
- **Context**: The build specification strictly mandates implementing one milestone at a time, running tests, summarizing changes, and obtaining sign-off before proceeding to the next.
- **Decision**: All development strictly follows the milestones (M0 through M8) in order. No feature creep or out-of-order development.

## ADR-002: Tauri 2 for Windows Application
- **Context**: Low memory footprint in system tray is required along with a rich settings and pairing UI.
- **Decision**: Tauri 2 with React + Vite + TypeScript for UI, and Rust (Tokio runtime) for background services (Axum HTTPS server, mDNS, clipboard watcher, SQLite).

## ADR-003: Direct Certificate Fingerprint Pinning
- **Context**: Self-signed TLS certificate is used to avoid cloud CAs and maintain local-only operation without warnings.
- **Decision**: Pinned Dart `HttpClient` validates DER SHA-256 fingerprint transferred during QR-code pairing.

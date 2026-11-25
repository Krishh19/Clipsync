# Security Policy

## Supported Versions

Only the latest release of ClipSync is supported with security updates.

| Version | Supported |
| --- | --- |
| 0.1.x | ✅ Yes |

## Security Architecture

ClipSync is designed as a **local-only, zero-cloud** peer-to-peer tool:
- **TLS 1.3 + Certificate Pinning**: The Windows desktop server generates a self-signed ECDSA P-256 certificate on first launch. The Android client pins the exact SHA-256 certificate fingerprint during QR or manual pairing and refuses any mismatched certificate.
- **Per-Device Bearer Secrets**: Each paired phone receives a unique 256-bit random token stored in Android EncryptedSharedPreferences/Keystore and hashed with SHA-256 in the desktop SQLite database.
- **Single-Use Expiring Pairing Tokens**: Pairing tokens expire after 5 minutes and are invalidated immediately after first use.
- **Rate Limiting & Private IP Filtering**: Pairing and auth endpoints enforce per-IP rate limiting, and optional private-subnet enforcement blocks external WAN requests.
- **Sanitized Filenames & Size Caps**: Incoming filenames are sanitized against path traversal and Windows reserved names; text is capped at 1 MB and file transfers at 50 MB.

## Reporting a Vulnerability

If you discover a security vulnerability in ClipSync, please **do not** open a public GitHub issue.

Instead, please report it privately via GitHub Security Advisories on the repository (`Security` tab $\to$ `Advisories` $\to$ `Report a vulnerability`), or contact the maintainer directly. Please include:
- A clear description of the issue and potential impact
- Steps to reproduce or a minimal proof-of-concept
- Affected component (`desktop` or `mobile`) and version

We aim to acknowledge reports within 48 hours and provide a fix or mitigation plan as quickly as possible.

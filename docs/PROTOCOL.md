# ClipSync Protocol Specification (v1)

Base URL: `https://<host>:<port>/api/v1`  
TLS: 1.2 or newer, self-signed certificate (ECDSA P-256) generated once.  
Default port: **47821** (tries next 20 ports if busy).  
Auth header: `Authorization: Bearer <device_secret>` on all endpoints except `GET /info` and `POST /pair`.

---

## 1. Endpoints

| Endpoint | Method | Auth | Purpose |
|---|---|---|---|
| `/info` | GET | None | Server identity, discovery validation |
| `/pair` | POST | Pairing token | Exchange one-time token for device secret |
| `/pair` | DELETE | Bearer | Phone unpairs itself; revokes secret |
| `/text` | POST | Bearer | Send text or link to PC clipboard |
| `/file` | POST | Bearer | Stream file/photo/video to PC |
| `/files/{id}` | GET | Bearer | Download file offered by PC (supports Range) |
| `/events` | GET (WebSocket) | Bearer | Bidirectional events, keepalive ping/pong |

---

## 2. Request & Response Details

### `GET /info`
- **Request**: No auth, no body.
- **Response 200**:
  ```json
  {
    "name": "DESKTOP-ABC1234",
    "device_id": "c1f7b7e2-4b2a-4a2e-8c3e-9b2f7a1b2c3d",
    "protocol": 1
  }
  ```

### `POST /pair`
- **Request**:
  ```json
  {
    "token": "4a7b2c9d1e...",
    "device_id": "<uuid-generated-by-phone>",
    "device_name": "Pixel 8 Pro",
    "platform": "android"
  }
  ```
- **Response 200**:
  ```json
  {
    "device_secret": "<256-bit-random-base64url>",
    "server_device_id": "<server-uuid>",
    "server_name": "DESKTOP-ABC1234"
  }
  ```
- **Error 401**: `{"error": {"code": "invalid_token", "message": "Token expired or invalid"}}`

### `DELETE /pair`
- **Request**: Auth: `Bearer <device_secret>`
- **Response 200**: `{"status": "unpaired"}`

### `POST /text`
- **Request**: Auth: `Bearer <device_secret>`
  ```json
  {
    "kind": "text", 
    "content": "Copied text content",
    "client_id": "<uuid-for-deduplication>"
  }
  ```
  *(kind is "text" or "link"; content <= 1 MB; repeats within 60s ignored)*
- **Response 201**: `{"id": "<uuid>"}`

### `POST /file`
- **Headers**:
  - `Authorization: Bearer <device_secret>`
  - `Content-Length`: `<bytes>` (Required, max 50 MB default)
  - `Content-Type`: MIME type (e.g., `image/jpeg`)
  - `X-File-Name`: URL-encoded UTF-8 filename
  - `X-Client-Id`: `<uuid>`
- **Body**: Raw binary stream.
- **Server Behavior**:
  - Rejects with 413 if Content-Length missing or > limit.
  - Streams to `<save_dir>/.partial/<uuid>` while counting bytes.
  - Aborts, deletes partial file, and returns 413 if byte count exceeds limit.
  - Sanitizes filename, generates unique name if duplicate (`name (1).ext`), moves to destination.
  - Auto-copies if enabled, adds history row, triggers toast notification.
- **Response 201**:
  ```json
  {
    "id": "<uuid>",
    "name": "photo (1).jpg",
    "size": 1048576,
    "kind": "image"
  }
  ```

### `GET /files/{id}`
- **Headers**: `Authorization: Bearer <device_secret>`
- **Optional**: `Range: bytes=0-1023`
- **Response 200 / 206**: Binary file content.

### `GET /events` (WebSocket)
- **Headers**: `Authorization: Bearer <device_secret>`
- **Server Messages**:
  - `hello`: `{"type": "hello", "server_name": "...", "protocol": 1}`
  - `text`: `{"type": "text", "id": "...", "kind": "text", "content": "...", "ts": 1700000000}`
  - `file_offer`: `{"type": "file_offer", "id": "...", "name": "...", "size": 1234, "mime": "...", "ts": 1700000000}`
  - `ping`: `{"type": "ping"}` every 20s. Client must reply with `{"type": "pong"}`. Server drops after 2 missed pongs.

---

## 3. Discovery & QR Format

### mDNS Service
- Service: `_clipsync._tcp.local.`
- TXT Records:
  - `id`: Server device ID
  - `name`: Server display name
  - `v`: `1`
  - `fp`: First 16 hex characters of SHA-256 certificate fingerprint

### QR Code URI
```
clipsync://pair?host=<ip>&port=<port>&token=<hex>&fp=<sha256-hex>&id=<server_device_id>&name=<url-encoded>
```

---

## 4. Standard Error Format
All non-2xx responses return:
```json
{
  "error": {
    "code": "unauthorized | invalid_token | bad_request | too_large | unsupported | rate_limited | internal",
    "message": "Human-readable explanation"
  }
}
```

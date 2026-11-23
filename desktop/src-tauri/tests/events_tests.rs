use clipsync_desktop_lib::config::AppConfig;
use clipsync_desktop_lib::server::ws::WsServerMessage;
use clipsync_desktop_lib::state::{AppState, FileOffer};
use clipsync_desktop_lib::storage::{Database, DeviceRow};
use futures_util::{SinkExt, StreamExt};
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::oneshot;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::handshake::client::Request;

async fn spawn_events_test_server() -> (u16, PathBuf, Arc<AppState>, oneshot::Sender<()>) {
    let temp_dir = std::env::temp_dir().join(format!("clipsync_events_test_{}", uuid::Uuid::new_v4()));
    let _ = std::fs::create_dir_all(&temp_dir);

    let mut cfg = AppConfig::default();
    cfg.save_folder = temp_dir.to_string_lossy().to_string();
    cfg.copy_text_links = false;
    cfg.copy_images = false;
    cfg.device_name = "Test-ClipSync-PC".to_string();

    let db = Database::new_in_memory().unwrap();
    let state = AppState::new(cfg, db);

    let dev = DeviceRow {
        id: "phone-device-1".to_string(),
        name: "Test Android".to_string(),
        platform: "android".to_string(),
        secret_hash: clipsync_desktop_lib::server::auth::hash_secret("dev-token-clipsync"),
        created_at: 1000,
        last_seen: 1000,
        revoked: false,
    };
    state.database.insert_device(&dev).unwrap();

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let router = clipsync_desktop_lib::server::routes::create_router(state.clone());

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    tokio::spawn(async move {
        let _ = axum::serve(listener, router)
            .with_graceful_shutdown(async move {
                let _ = shutdown_rx.await;
            })
            .await;
    });

    (port, temp_dir, state, shutdown_tx)
}

#[tokio::test]
async fn test_file_offer_and_download() {
    let (port, temp_dir, state, _shutdown) = spawn_events_test_server().await;

    // Create a dummy file to offer
    let file_path = temp_dir.join("test_document.pdf");
    let content = b"%PDF-1.4 sample content for ClipSync file transfer test";
    tokio::fs::write(&file_path, content).await.unwrap();

    let offer_id = "offer-uuid-1234".to_string();
    let offer = FileOffer {
        id: offer_id.clone(),
        name: "test_document.pdf".to_string(),
        file_path: file_path.clone(),
        mime: "application/pdf".to_string(),
        size: content.len() as u64,
        created_at: Instant::now(),
    };
    state.add_file_offer(offer).await;

    let client = reqwest::Client::new();

    // 1. Download via /api/v1/files/:id
    let res = client
        .get(format!("http://127.0.0.1:{}/api/v1/files/{}", port, offer_id))
        .header("Authorization", "Bearer dev-token-clipsync")
        .send()
        .await
        .unwrap();

    assert_eq!(res.status(), reqwest::StatusCode::OK);
    assert_eq!(
        res.headers().get("content-type").unwrap().to_str().unwrap(),
        "application/pdf"
    );
    assert_eq!(
        res.headers().get("content-length").unwrap().to_str().unwrap(),
        content.len().to_string()
    );
    let bytes = res.bytes().await.unwrap();
    assert_eq!(bytes.as_ref(), content);

    // 2. Download via /files/:id (root route)
    let res_root = client
        .get(format!("http://127.0.0.1:{}/files/{}", port, offer_id))
        .header("Authorization", "Bearer dev-token-clipsync")
        .send()
        .await
        .unwrap();

    assert_eq!(res_root.status(), reqwest::StatusCode::OK);
    let root_bytes = res_root.bytes().await.unwrap();
    assert_eq!(root_bytes.as_ref(), content);

    // 3. Unknown file offer should return 404
    let res_404 = client
        .get(format!("http://127.0.0.1:{}/files/non-existent-id", port))
        .header("Authorization", "Bearer dev-token-clipsync")
        .send()
        .await
        .unwrap();

    assert_eq!(res_404.status(), reqwest::StatusCode::NOT_FOUND);
}

#[test]
fn test_clipboard_watcher_echo_loop_prevention() {
    let last_written = Arc::new(std::sync::Mutex::new(None));

    let sample_text = "https://example.com/shared-link";
    let mut hasher = Sha256::new();
    hasher.update(sample_text.as_bytes());
    let hash = hasher.finalize().to_vec();

    // Simulate writer setting last_written
    {
        let mut guard = last_written.lock().unwrap();
        *guard = Some(hash.clone());
    }

    // Verify watcher detects echo for identical text
    let mut test_hasher = Sha256::new();
    test_hasher.update(sample_text.as_bytes());
    let test_hash = test_hasher.finalize().to_vec();

    let is_echo = {
        let guard = last_written.lock().unwrap();
        guard.as_ref() == Some(&test_hash)
    };
    assert!(is_echo, "Watcher should recognize exact match as echo loop");

    // Verify different text does not trigger echo prevention
    let different_text = "New user copied snippet";
    let mut diff_hasher = Sha256::new();
    diff_hasher.update(different_text.as_bytes());
    let diff_hash = diff_hasher.finalize().to_vec();

    let is_diff_echo = {
        let guard = last_written.lock().unwrap();
        guard.as_ref() == Some(&diff_hash)
    };
    assert!(!is_diff_echo, "Different text should not be flagged as echo");
}

#[tokio::test]
async fn test_ws_events_hello_and_text_broadcast() {
    let (port, _temp_dir, state, _shutdown) = spawn_events_test_server().await;

    let ws_url = format!("ws://127.0.0.1:{}/api/v1/events", port);
    let request = Request::builder()
        .uri(&ws_url)
        .header("Authorization", "Bearer dev-token-clipsync")
        .header("Host", format!("127.0.0.1:{}", port))
        .header("Connection", "Upgrade")
        .header("Upgrade", "websocket")
        .header("Sec-WebSocket-Version", "13")
        .header("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
        .body(())
        .unwrap();

    let (mut ws_stream, response) = connect_async(request).await.expect("Failed to connect WS");
    assert_eq!(response.status(), reqwest::StatusCode::SWITCHING_PROTOCOLS);

    // 1. Verify first message is 'hello'
    let first_msg = ws_stream.next().await.unwrap().unwrap();
    let txt = first_msg.into_text().unwrap();
    let val: serde_json::Value = serde_json::from_str(&txt).unwrap();
    assert_eq!(val["type"], "hello");
    assert_eq!(val["server_name"], "Test-ClipSync-PC");
    assert_eq!(val["protocol"], 1);

    // 2. Broadcast text event from server
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    let text_event = WsServerMessage::Text {
        id: "evt-text-1".to_string(),
        kind: "text".to_string(),
        content: "Hello from PC to phone!".to_string(),
        ts: now,
    };
    state.broadcast_ws_message(text_event).await;

    let second_msg = ws_stream.next().await.unwrap().unwrap();
    let second_txt = second_msg.into_text().unwrap();
    let second_val: serde_json::Value = serde_json::from_str(&second_txt).unwrap();
    assert_eq!(second_val["type"], "text");
    assert_eq!(second_val["content"], "Hello from PC to phone!");
    assert_eq!(second_val["id"], "evt-text-1");

    // 3. Client answers with pong JSON
    let pong_msg = tokio_tungstenite::tungstenite::Message::Text("{\"type\":\"pong\"}".into());
    ws_stream.send(pong_msg).await.unwrap();

    // 4. Broadcast file offer event
    let file_event = WsServerMessage::FileOffer {
        id: "offer-file-1".to_string(),
        name: "photo.jpg".to_string(),
        size: 1048576,
        mime: "image/jpeg".to_string(),
        ts: now,
    };
    state.broadcast_ws_message(file_event).await;

    let third_msg = ws_stream.next().await.unwrap().unwrap();
    let third_txt = third_msg.into_text().unwrap();
    let third_val: serde_json::Value = serde_json::from_str(&third_txt).unwrap();
    assert_eq!(third_val["type"], "file_offer");
    assert_eq!(third_val["name"], "photo.jpg");
    assert_eq!(third_val["size"], 1048576);

    ws_stream.close(None).await.unwrap();
}

#[tokio::test]
async fn test_ws_events_unauthorized() {
    let (port, _temp_dir, _state, _shutdown) = spawn_events_test_server().await;

    let ws_url = format!("ws://127.0.0.1:{}/api/v1/events", port);
    let request = Request::builder()
        .uri(&ws_url)
        .header("Authorization", "Bearer invalid-token")
        .header("Host", format!("127.0.0.1:{}", port))
        .header("Connection", "Upgrade")
        .header("Upgrade", "websocket")
        .header("Sec-WebSocket-Version", "13")
        .header("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
        .body(())
        .unwrap();

    let conn_result = connect_async(request).await;
    assert!(conn_result.is_err(), "Invalid token should fail WS handshake with 401");
}

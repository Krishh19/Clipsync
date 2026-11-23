use clipsync_desktop_lib::config::AppConfig;
use clipsync_desktop_lib::state::AppState;
use clipsync_desktop_lib::storage::Database;
use serde_json::json;
use std::sync::Arc;
use tokio::sync::oneshot;

async fn spawn_test_server(max_file_size_mb: u64) -> (String, std::path::PathBuf, Arc<AppState>, oneshot::Sender<()>) {
    let temp_dir = std::env::temp_dir().join(format!("clipsync_test_{}", uuid::Uuid::new_v4()));
    let _ = std::fs::create_dir_all(&temp_dir);

    let mut cfg = AppConfig::default();
    cfg.save_folder = temp_dir.to_string_lossy().to_string();
    cfg.max_file_size_mb = max_file_size_mb;
    cfg.copy_text_links = false; // don't mutate host clipboard in unit tests
    cfg.copy_images = false;
    cfg.device_name = "Test ClipSync PC".to_string();

    let db = Database::new_in_memory().unwrap();
    let state = AppState::new(cfg, db);

    // Register test device secret so tests pass both with and without dev_plain_http feature
    let dev = clipsync_desktop_lib::storage::DeviceRow {
        id: "test-device".to_string(),
        name: "Test Phone".to_string(),
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

    let base_url = format!("http://127.0.0.1:{}", port);
    (base_url, temp_dir, state, shutdown_tx)
}

#[tokio::test]
async fn test_get_info_endpoint() {
    let (base_url, temp_dir, _state, shutdown) = spawn_test_server(50).await;
    let client = reqwest::Client::new();

    let res = client
        .get(format!("{}/api/v1/info", base_url))
        .send()
        .await
        .unwrap();

    assert_eq!(res.status(), 200);
    let body: serde_json::Value = res.json().await.unwrap();
    assert_eq!(body["name"], "Test ClipSync PC");
    assert_eq!(body["protocol"], 1);
    assert!(body["device_id"].is_string());

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_text_endpoint_auth_and_send() {
    let (base_url, temp_dir, state, shutdown) = spawn_test_server(50).await;
    let client = reqwest::Client::new();

    // 1. Without auth: should return 401
    let res_no_auth = client
        .post(format!("{}/api/v1/text", base_url))
        .json(&json!({
            "kind": "text",
            "content": "Hello world"
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(res_no_auth.status(), 401);

    // 2. With dev token: should return 201
    let res_with_dev = client
        .post(format!("{}/api/v1/text", base_url))
        .header("Authorization", "Bearer dev-token-clipsync")
        .json(&json!({
            "kind": "text",
            "content": "Hello ClipSync PC"
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(res_with_dev.status(), 201);
    let body: serde_json::Value = res_with_dev.json().await.unwrap();
    assert!(body["id"].is_string());

    // Verify saved to database
    let items = state.database.list_items(10).unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].text, Some("Hello ClipSync PC".to_string()));

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_text_endpoint_client_id_dedup() {
    let (base_url, temp_dir, state, shutdown) = spawn_test_server(50).await;
    let client = reqwest::Client::new();

    let client_id = "test-dedup-uuid-1234";

    // First POST
    let res1 = client
        .post(format!("{}/api/v1/text", base_url))
        .header("Authorization", "Bearer dev-token-clipsync")
        .json(&json!({
            "kind": "text",
            "content": "Message with deduplication",
            "client_id": client_id
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(res1.status(), 201);
    let body1: serde_json::Value = res1.json().await.unwrap();
    let id1 = body1["id"].as_str().unwrap().to_string();

    // Second repeated POST with same client_id within 60s
    let res2 = client
        .post(format!("{}/api/v1/text", base_url))
        .header("Authorization", "Bearer dev-token-clipsync")
        .json(&json!({
            "kind": "text",
            "content": "Message with deduplication (repeat)",
            "client_id": client_id
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(res2.status(), 201);
    let body2: serde_json::Value = res2.json().await.unwrap();
    let id2 = body2["id"].as_str().unwrap().to_string();

    // Must return the SAME id
    assert_eq!(id1, id2);

    // Database should only contain 1 item (deduped)
    let items = state.database.list_items(10).unwrap();
    assert_eq!(items.len(), 1);

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_text_endpoint_too_large() {
    let (base_url, temp_dir, _state, shutdown) = spawn_test_server(50).await;
    let client = reqwest::Client::new();

    // 1 MB + 1 byte
    let large_text = "x".repeat(1024 * 1024 + 1);

    let res = client
        .post(format!("{}/api/v1/text", base_url))
        .header("Authorization", "Bearer dev-token-clipsync")
        .json(&json!({
            "kind": "text",
            "content": large_text
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(res.status(), 413);

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_file_upload_success_and_sanitization() {
    let (base_url, temp_dir, state, shutdown) = spawn_test_server(50).await;
    let client = reqwest::Client::new();

    let content = b"This is a test file content for ClipSync M1";

    let res = client
        .post(format!("{}/api/v1/file", base_url))
        .header("Authorization", "Bearer dev-token-clipsync")
        .header("Content-Length", content.len())
        .header("Content-Type", "text/plain")
        .header("X-File-Name", "my%20test%20document%3A.txt")
        .body(content.to_vec())
        .send()
        .await
        .unwrap();

    assert_eq!(res.status(), 201);
    let body: serde_json::Value = res.json().await.unwrap();
    assert_eq!(body["name"], "my test document.txt"); // colon stripped
    assert_eq!(body["size"], content.len() as u64);
    assert_eq!(body["kind"], "file");

    // Verify saved file on disk
    let saved_file = temp_dir.join("my test document.txt");
    assert!(saved_file.exists());
    let saved_content = std::fs::read(&saved_file).unwrap();
    assert_eq!(saved_content, content);

    // Verify database row
    let items = state.database.list_items(10).unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].file_name, Some("my test document.txt".to_string()));

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_file_upload_content_length_limit() {
    let (base_url, temp_dir, _state, shutdown) = spawn_test_server(50).await;
    let client = reqwest::Client::new();

    // Stated Content-Length is 51 MB (53,477,376 bytes > 50 MB limit)
    let res = client
        .post(format!("{}/api/v1/file", base_url))
        .header("Authorization", "Bearer dev-token-clipsync")
        .header("Content-Length", "53477376")
        .header("Content-Type", "application/octet-stream")
        .header("X-File-Name", "large_video.mp4")
        .body(vec![0u8; 100]) // client only sent a little, but header declared > 50 MB
        .send()
        .await
        .unwrap();

    // Rejects with 413 BEFORE reading stream
    assert_eq!(res.status(), 413);

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_file_upload_missing_content_length() {
    let (base_url, temp_dir, _state, shutdown) = spawn_test_server(50).await;
    let client = reqwest::Client::new();

    // No Content-Length header
    let res = client
        .post(format!("{}/api/v1/file", base_url))
        .header("Authorization", "Bearer dev-token-clipsync")
        .header("Content-Type", "application/octet-stream")
        .header("X-File-Name", "no_length.dat")
        .send()
        .await
        .unwrap();

    // Rejects with 413 per spec
    assert_eq!(res.status(), 413);

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

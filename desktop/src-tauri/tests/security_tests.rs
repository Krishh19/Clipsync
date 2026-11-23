use clipsync_desktop_lib::config::AppConfig;
use clipsync_desktop_lib::pairing::PairingManager;
use clipsync_desktop_lib::server::ratelimit::RateLimiter;
use clipsync_desktop_lib::server::tls::get_or_create_tls_certs;
use clipsync_desktop_lib::state::AppState;
use clipsync_desktop_lib::storage::Database;
use serde_json::json;
use std::net::{IpAddr, Ipv4Addr};
use std::sync::Arc;
use tokio::sync::oneshot;

async fn spawn_test_server() -> (String, std::path::PathBuf, Arc<AppState>, oneshot::Sender<()>) {
    let temp_dir = std::env::temp_dir().join(format!("clipsync_sec_test_{}", uuid::Uuid::new_v4()));
    let _ = std::fs::create_dir_all(&temp_dir);

    let mut cfg = AppConfig::default();
    cfg.save_folder = temp_dir.to_string_lossy().to_string();
    cfg.copy_text_links = false;
    cfg.copy_images = false;
    cfg.device_name = "ClipSync Sec PC".to_string();

    let db = Database::new_in_memory().unwrap();
    let state = AppState::new(cfg, db);

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

#[test]
fn test_tls_cert_generation_and_fingerprint() {
    let temp_dir = std::env::temp_dir().join(format!("clipsync_tls_test_{}", uuid::Uuid::new_v4()));
    let tls_config = get_or_create_tls_certs(&temp_dir, "test-pc").unwrap();

    assert!(tls_config.cert_path.exists());
    assert!(tls_config.key_path.exists());
    assert_eq!(tls_config.fingerprint.len(), 64);
    assert!(tls_config.fingerprint.chars().all(|c| c.is_ascii_hexdigit()));

    // Loading existing certificate returns identical fingerprint
    let tls_config_existing = get_or_create_tls_certs(&temp_dir, "test-pc").unwrap();
    assert_eq!(tls_config.fingerprint, tls_config_existing.fingerprint);

    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_pairing_token_single_use_and_expiration() {
    let pm = PairingManager::new();
    let token = pm.create_token().await;
    assert_eq!(token.len(), 32);

    // Consume once: valid
    assert!(pm.consume_token(&token).await);

    // Consume second time: rejected (single-use)
    assert!(!pm.consume_token(&token).await);

    // Wrong token rejected
    assert!(!pm.consume_token("invalid_token_123").await);
}

#[test]
fn test_private_ip_filter_and_rate_limiter() {
    // 1. Private IP filter
    assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1))));
    assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(192, 168, 1, 10))));
    assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1))));
    assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(172, 16, 0, 1))));
    assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(169, 254, 1, 1))));

    // Public IP rejected
    assert!(!RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(8, 8, 8, 8))));
    assert!(!RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(1, 1, 1, 1))));

    // 2. Pair rate limiter (max 5 per min)
    let limiter = RateLimiter::new();
    let ip = IpAddr::V4(Ipv4Addr::new(192, 168, 1, 100));
    for _ in 0..5 {
        assert!(limiter.check_pair_rate(ip));
    }
    assert!(!limiter.check_pair_rate(ip));

    // 3. Auth failure tracking (5 failures blocks IP for 60s)
    let auth_ip = IpAddr::V4(Ipv4Addr::new(192, 168, 1, 102));
    for _ in 0..4 {
        limiter.record_auth_failure(auth_ip);
        assert!(!limiter.is_auth_blocked(auth_ip));
    }
    limiter.record_auth_failure(auth_ip);
    assert!(limiter.is_auth_blocked(auth_ip));

    // Success resets failure count
    limiter.record_auth_success(auth_ip);
    assert!(!limiter.is_auth_blocked(auth_ip));
}

#[tokio::test]
async fn test_protected_endpoints_missing_and_wrong_token() {
    let (base_url, temp_dir, _state, shutdown) = spawn_test_server().await;
    let client = reqwest::Client::new();

    // 1. Missing Authorization header
    let res = client
        .post(format!("{}/api/v1/text", base_url))
        .json(&json!({"kind": "text", "content": "secret"}))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 401);

    // 2. Wrong Bearer token
    let res = client
        .post(format!("{}/api/v1/text", base_url))
        .header("Authorization", "Bearer invalid-wrong-token")
        .json(&json!({"kind": "text", "content": "secret"}))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 401);

    // 3. DELETE /pair with wrong token
    let res = client
        .delete(format!("{}/api/v1/pair", base_url))
        .header("Authorization", "Bearer invalid-wrong-token")
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 401);

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_pairing_flow_and_device_revocation() {
    let (base_url, temp_dir, state, shutdown) = spawn_test_server().await;
    let client = reqwest::Client::new();

    // 1. Create a pairing token
    let token = state.pairing_manager.create_token().await;

    // 2. POST /pair with wrong token -> 401 invalid_token
    let res_wrong = client
        .post(format!("{}/api/v1/pair", base_url))
        .json(&json!({
            "token": "wrong-token-abc",
            "device_id": "phone-uuid-1",
            "device_name": "Pixel 8",
            "platform": "android"
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(res_wrong.status(), 401);
    let body_err: serde_json::Value = res_wrong.json().await.unwrap();
    assert_eq!(body_err["error"]["code"], "invalid_token");

    // 3. POST /pair with valid token -> 200/201 Success
    let res_valid = client
        .post(format!("{}/api/v1/pair", base_url))
        .json(&json!({
            "token": token,
            "device_id": "phone-uuid-1",
            "device_name": "Pixel 8",
            "platform": "android"
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(res_valid.status(), 200);
    let pair_data: serde_json::Value = res_valid.json().await.unwrap();
    let secret = pair_data["device_secret"].as_str().unwrap().to_string();
    assert!(!secret.is_empty());
    assert_eq!(pair_data["server_name"], "ClipSync Sec PC");

    // 4. Repeated POST /pair with used token -> 401 invalid_token (single use)
    let res_reuse = client
        .post(format!("{}/api/v1/pair", base_url))
        .json(&json!({
            "token": token,
            "device_id": "phone-uuid-2",
            "device_name": "Pixel 8",
            "platform": "android"
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(res_reuse.status(), 401);

    // 5. Use device secret on protected endpoint -> 201 Created
    let res_text = client
        .post(format!("{}/api/v1/text", base_url))
        .header("Authorization", format!("Bearer {secret}"))
        .json(&json!({"kind": "text", "content": "Encrypted message from paired phone"}))
        .send()
        .await
        .unwrap();
    assert_eq!(res_text.status(), 201);

    // 6. Revoke device
    state.database.revoke_device("phone-uuid-1").unwrap();

    // 7. Request with revoked secret -> 401 Unauthorized immediately
    let res_revoked = client
        .post(format!("{}/api/v1/text", base_url))
        .header("Authorization", format!("Bearer {secret}"))
        .json(&json!({"kind": "text", "content": "Message from revoked device"}))
        .send()
        .await
        .unwrap();
    assert_eq!(res_revoked.status(), 401);

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

#[tokio::test]
async fn test_qr_endpoint() {
    let (base_url, temp_dir, _state, shutdown) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let res = client
        .get(format!("{}/api/v1/pair/qr", base_url))
        .send()
        .await
        .unwrap();

    assert_eq!(res.status(), 200);
    let qr: serde_json::Value = res.json().await.unwrap();
    assert!(qr["url"].as_str().unwrap().starts_with("clipsync://pair?"));
    assert!(qr["svg"].as_str().unwrap().contains("<svg"));
    assert_eq!(qr["expires_in_seconds"], 300);

    let _ = shutdown.send(());
    let _ = std::fs::remove_dir_all(temp_dir);
}

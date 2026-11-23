use axum::body::Body;
use axum::extract::{Path as AxumPath, State, WebSocketUpgrade};
use axum::http::{HeaderMap, StatusCode};
use axum::response::IntoResponse;
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use tower_http::trace::TraceLayer;
use serde::{Deserialize, Serialize};
use std::net::IpAddr;
use std::sync::Arc;
use uuid::Uuid;

use crate::server::auth::{hash_secret, verify_bearer};
use crate::server::errors::ApiError;
use crate::server::ratelimit::RateLimiter;
use crate::server::upload::handle_file_upload;
use crate::server::ws::handle_ws_upgrade;
use crate::state::AppState;
use crate::storage::ItemRow;

#[derive(Serialize)]
pub struct InfoResponse {
    pub name: String,
    pub device_id: String,
    pub protocol: u32,
}

#[derive(Deserialize)]
pub struct PairRequest {
    pub token: String,
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
}

#[derive(Serialize)]
pub struct PairResponse {
    pub device_secret: String,
    pub server_device_id: String,
    pub server_name: String,
}

#[derive(Serialize)]
pub struct PairQrResponse {
    pub url: String,
    pub svg: String,
    pub expires_in_seconds: u64,
}

#[derive(Deserialize)]
pub struct TextRequest {
    pub kind: String,
    pub content: String,
    pub client_id: Option<String>,
}

#[derive(Serialize)]
pub struct TextResponse {
    pub id: String,
}

pub fn create_router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/api/v1/info", get(get_info))
        .route("/api/v1/pair", post(post_pair))
        .route("/api/v1/pair", delete(delete_pair))
        .route("/api/v1/pair/qr", get(get_pair_qr_endpoint))
        .route("/api/v1/text", post(post_text))
        .route("/api/v1/file", post(post_file))
        .route("/api/v1/files/:id", get(get_file))
        .route("/api/v1/events", get(get_events))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

fn extract_client_ip(headers: &HeaderMap) -> IpAddr {
    if let Some(forwarded) = headers.get("x-forwarded-for").and_then(|v| v.to_str().ok()) {
        if let Some(first_ip) = forwarded.split(',').next() {
            if let Ok(ip) = first_ip.trim().parse() {
                return ip;
            }
        }
    }
    if let Some(real_ip) = headers.get("x-real-ip").and_then(|v| v.to_str().ok()) {
        if let Ok(ip) = real_ip.trim().parse() {
            return ip;
        }
    }
    IpAddr::V4(std::net::Ipv4Addr::new(127, 0, 0, 1))
}

fn check_auth_and_ip(headers: &HeaderMap, state: &AppState) -> Result<String, ApiError> {
    let ip = extract_client_ip(headers);

    if !RateLimiter::is_private_ip(&ip) {
        return Err(ApiError::Unauthorized);
    }

    if state.rate_limiter.is_auth_blocked(ip) {
        return Err(ApiError::RateLimited);
    }

    let auth = headers.get(axum::http::header::AUTHORIZATION).and_then(|v| v.to_str().ok());
    match verify_bearer(auth, &state.database) {
        Some(device_id) => {
            state.rate_limiter.record_auth_success(ip);
            Ok(device_id)
        }
        None => {
            state.rate_limiter.record_auth_failure(ip);
            Err(ApiError::Unauthorized)
        }
    }
}

async fn get_info(headers: HeaderMap, State(state): State<Arc<AppState>>) -> Result<Json<InfoResponse>, ApiError> {
    let ip = extract_client_ip(&headers);
    if !RateLimiter::is_private_ip(&ip) {
        return Err(ApiError::Unauthorized);
    }

    let cfg = state.config.read().await;
    Ok(Json(InfoResponse {
        name: cfg.device_name.clone(),
        device_id: cfg.server_device_id.clone(),
        protocol: 1,
    }))
}

async fn get_pair_qr_endpoint(
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> Result<Json<PairQrResponse>, ApiError> {
    let ip = extract_client_ip(&headers);
    if !RateLimiter::is_private_ip(&ip) {
        return Err(ApiError::Unauthorized);
    }

    let (port, server_id, server_name) = {
        let cfg = state.config.read().await;
        (cfg.port, cfg.server_device_id.clone(), cfg.device_name.clone())
    };

    let fp = {
        let f = state.cert_fingerprint.read().await;
        if f.is_empty() {
            "0000000000000000000000000000000000000000000000000000000000000000".to_string()
        } else {
            f.clone()
        }
    };

    let qr_data = state
        .pairing_manager
        .get_qr_data("127.0.0.1", port, &fp, &server_id, &server_name)
        .await
        .ok_or_else(|| ApiError::Internal("Failed to generate QR data".to_string()))?;

    Ok(Json(PairQrResponse {
        url: qr_data.url,
        svg: qr_data.svg,
        expires_in_seconds: qr_data.expires_in_seconds,
    }))
}

async fn post_pair(
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    Json(req): Json<PairRequest>,
) -> Result<Json<PairResponse>, ApiError> {
    let ip = extract_client_ip(&headers);

    if !RateLimiter::is_private_ip(&ip) {
        return Err(ApiError::Unauthorized);
    }

    if !state.rate_limiter.check_pair_rate(ip) {
        return Err(ApiError::RateLimited);
    }

    let is_valid = state.pairing_manager.consume_token(&req.token).await;
    if !is_valid {
        return Err(ApiError::InvalidToken);
    }

    let secret = state.pairing_manager.generate_device_secret();
    let secret_hash = hash_secret(&secret);

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let dev_row = crate::storage::DeviceRow {
        id: req.device_id,
        name: req.device_name,
        platform: req.platform,
        secret_hash,
        created_at: now,
        last_seen: now,
        revoked: false,
    };

    state
        .database
        .insert_device(&dev_row)
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let cfg = state.config.read().await;
    Ok(Json(PairResponse {
        device_secret: secret,
        server_device_id: cfg.server_device_id.clone(),
        server_name: cfg.device_name.clone(),
    }))
}

async fn delete_pair(
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
) -> Result<StatusCode, ApiError> {
    let device_id = check_auth_and_ip(&headers, &state)?;

    state
        .database
        .revoke_device(&device_id)
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok(StatusCode::NO_CONTENT)
}

async fn post_text(
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    Json(req): Json<TextRequest>,
) -> Result<(StatusCode, Json<TextResponse>), ApiError> {
    let device_id = check_auth_and_ip(&headers, &state)?;

    if req.content.len() > 1024 * 1024 {
        return Err(ApiError::TooLarge("Text exceeds 1 MB limit".to_string()));
    }

    let id = Uuid::new_v4().to_string();

    // Check client_id deduplication (within 60s)
    if let Some(ref client_id) = req.client_id {
        if let Some(existing_id) = state.client_id_dedup.check_or_insert(client_id, &id) {
            // Repeat seen within 60 s: return 201 with existing id, skip duplicate write/db
            return Ok((StatusCode::CREATED, Json(TextResponse { id: existing_id })));
        }
    }

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let item = ItemRow {
        id: id.clone(),
        direction: "in".to_string(),
        kind: req.kind,
        device_id: Some(device_id),
        text: Some(req.content.clone()),
        file_path: None,
        file_name: None,
        mime: Some("text/plain".to_string()),
        size: Some(req.content.len() as i64),
        created_at: now,
    };

    state
        .database
        .insert_item(&item)
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    // Check config: copy text/links to clipboard
    let copy_enabled = {
        let cfg = state.config.read().await;
        cfg.copy_text_links
    };

    if copy_enabled {
        state.clipboard_writer.write_text(&req.content);
    }

    Ok((StatusCode::CREATED, Json(TextResponse { id })))
}

async fn post_file(
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    body: Body,
) -> Result<impl IntoResponse, ApiError> {
    let _device_id = check_auth_and_ip(&headers, &state)?;

    handle_file_upload(headers, state, body).await
}

async fn get_file(
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    AxumPath(file_id): AxumPath<String>,
) -> Result<impl IntoResponse, ApiError> {
    let _device_id = check_auth_and_ip(&headers, &state)?;

    let offer = state
        .get_file_offer(&file_id)
        .await
        .ok_or_else(|| ApiError::NotFound("File offer not found or expired".to_string()))?;

    let file = tokio::fs::File::open(&offer.file_path)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let stream = tokio_util::io::ReaderStream::new(file);
    let body = Body::from_stream(stream);

    let mut response_headers = HeaderMap::new();
    response_headers.insert(
        axum::http::header::CONTENT_TYPE,
        offer.mime.parse().unwrap_or(axum::http::HeaderValue::from_static("application/octet-stream")),
    );

    Ok((StatusCode::OK, response_headers, body))
}

async fn get_events(
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> Result<impl IntoResponse, ApiError> {
    let device_id = check_auth_and_ip(&headers, &state)?;

    Ok(handle_ws_upgrade(ws, state, device_id).await)
}

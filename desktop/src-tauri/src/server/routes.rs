use axum::body::Body;
use axum::extract::{Path as AxumPath, State, WebSocketUpgrade};
use axum::http::{HeaderMap, StatusCode};
use axum::response::IntoResponse;
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use tower_http::trace::TraceLayer;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

use crate::server::auth::{hash_secret, verify_bearer};
use crate::server::errors::ApiError;
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
        .route("/api/v1/text", post(post_text))
        .route("/api/v1/file", post(post_file))
        .route("/api/v1/files/:id", get(get_file))
        .route("/api/v1/events", get(get_events))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

async fn get_info(State(state): State<Arc<AppState>>) -> Json<InfoResponse> {
    let cfg = state.config.read().await;
    Json(InfoResponse {
        name: cfg.device_name.clone(),
        device_id: cfg.server_device_id.clone(),
        protocol: 1,
    })
}

async fn post_pair(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PairRequest>,
) -> Result<Json<PairResponse>, ApiError> {
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
    let auth = headers.get(axum::http::header::AUTHORIZATION).and_then(|v| v.to_str().ok());
    let device_id = verify_bearer(auth, &state.database).ok_or(ApiError::Unauthorized)?;

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
    let auth = headers.get(axum::http::header::AUTHORIZATION).and_then(|v| v.to_str().ok());
    let device_id = verify_bearer(auth, &state.database).ok_or(ApiError::Unauthorized)?;

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
    let auth = headers.get(axum::http::header::AUTHORIZATION).and_then(|v| v.to_str().ok());
    let _device_id = verify_bearer(auth, &state.database).ok_or(ApiError::Unauthorized)?;

    handle_file_upload(headers, state, body).await
}

async fn get_file(
    headers: HeaderMap,
    State(state): State<Arc<AppState>>,
    AxumPath(file_id): AxumPath<String>,
) -> Result<impl IntoResponse, ApiError> {
    let auth = headers.get(axum::http::header::AUTHORIZATION).and_then(|v| v.to_str().ok());
    let _device_id = verify_bearer(auth, &state.database).ok_or(ApiError::Unauthorized)?;

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
    let auth = headers.get(axum::http::header::AUTHORIZATION).and_then(|v| v.to_str().ok());
    let device_id = verify_bearer(auth, &state.database).ok_or(ApiError::Unauthorized)?;

    Ok(handle_ws_upgrade(ws, state, device_id).await)
}

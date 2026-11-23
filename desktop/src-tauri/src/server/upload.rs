use axum::body::Body;
use axum::http::HeaderMap;
use axum::response::IntoResponse;
use axum::Json;
use futures_util::StreamExt;
use serde::Serialize;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::fs::{self as tokio_fs, File};
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use crate::server::errors::ApiError;
use crate::state::AppState;
use crate::storage::ItemRow;

#[derive(Serialize)]
pub struct FileUploadResponse {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub kind: String,
}

pub async fn handle_file_upload(
    headers: HeaderMap,
    state: Arc<AppState>,
    body: Body,
) -> Result<impl IntoResponse, ApiError> {
    let content_length = headers
        .get(axum::http::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
        .ok_or_else(|| ApiError::BadRequest("Content-Length header is required".to_string()))?;

    let max_bytes = {
        let cfg = state.config.read().await;
        cfg.max_file_size_mb * 1024 * 1024
    };

    if content_length > max_bytes {
        return Err(ApiError::TooLarge(format!(
            "File size {content_length} exceeds limit of {max_bytes} bytes"
        )));
    }

    let raw_name = headers
        .get("x-file-name")
        .and_then(|v| v.to_str().ok())
        .map(|v| urlencoding_decode(v))
        .unwrap_or_else(|| "unnamed_file".to_string());

    let client_id = headers
        .get("x-client-id")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let content_type = headers
        .get(axum::http::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("application/octet-stream")
        .to_string();

    let file_id = Uuid::new_v4().to_string();
    let partial_path = state.file_manager.partial_dir().join(&file_id);

    state
        .file_manager
        .ensure_dirs()
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let mut partial_file = File::create(&partial_path)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let mut stream = body.into_data_stream();
    let mut total_bytes = 0u64;

    while let Some(chunk_result) = stream.next().await {
        let chunk = match chunk_result {
            Ok(c) => c,
            Err(e) => {
                let _ = tokio_fs::remove_file(&partial_path).await;
                return Err(ApiError::BadRequest(e.to_string()));
            }
        };

        total_bytes += chunk.len() as u64;
        if total_bytes > max_bytes {
            let _ = tokio_fs::remove_file(&partial_path).await;
            return Err(ApiError::TooLarge("File exceeded maximum size limit".to_string()));
        }

        if let Err(e) = partial_file.write_all(&chunk).await {
            let _ = tokio_fs::remove_file(&partial_path).await;
            return Err(ApiError::Internal(e.to_string()));
        }
    }

    let _ = partial_file.flush().await;
    drop(partial_file);

    let final_path = state.file_manager.get_unique_path(&raw_name);
    if let Err(e) = tokio_fs::rename(&partial_path, &final_path).await {
        let _ = tokio_fs::remove_file(&partial_path).await;
        return Err(ApiError::Internal(e.to_string()));
    }

    let kind = classify_media(&content_type, &final_path);
    let final_filename = final_path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("file")
        .to_string();

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let item = ItemRow {
        id: file_id.clone(),
        direction: "in".to_string(),
        kind: kind.clone(),
        device_id: client_id,
        text: None,
        file_path: Some(final_path.to_string_lossy().to_string()),
        file_name: Some(final_filename.clone()),
        mime: Some(content_type),
        size: Some(total_bytes as i64),
        created_at: now,
    };

    let _ = state.database.insert_item(&item);

    Ok((
        axum::http::StatusCode::CREATED,
        Json(FileUploadResponse {
            id: file_id,
            name: final_filename,
            size: total_bytes,
            kind,
        }),
    ))
}

fn classify_media(mime: &str, path: &PathBuf) -> String {
    if mime.starts_with("image/") {
        return "image".to_string();
    }
    if mime.starts_with("video/") {
        return "video".to_string();
    }

    if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
        let ext_lower = ext.to_lowercase();
        match ext_lower.as_str() {
            "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" => return "image".to_string(),
            "mp4" | "mov" | "mkv" | "webm" | "avi" => return "video".to_string(),
            _ => {}
        }
    }

    "file".to_string()
}

fn urlencoding_decode(val: &str) -> String {
    urlencoding_decode_str(val).unwrap_or_else(|| val.to_string())
}

fn urlencoding_decode_str(val: &str) -> Option<String> {
    let mut bytes = Vec::new();
    let mut chars = val.bytes();
    while let Some(b) = chars.next() {
        if b == b'%' {
            let h1 = chars.next()?;
            let h2 = chars.next()?;
            let pair = [h1, h2];
            let hex_str = std::str::from_utf8(&pair).ok()?;
            let byte = u8::from_str_radix(hex_str, 16).ok()?;
            bytes.push(byte);
        } else if b == b'+' {
            bytes.push(b' ');
        } else {
            bytes.push(b);
        }
    }
    String::from_utf8(bytes).ok()
}

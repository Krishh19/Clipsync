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
    let max_bytes = {
        let cfg = state.config.read().await;
        cfg.max_file_size_mb * 1024 * 1024
    };

    let content_length = match headers
        .get(axum::http::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
    {
        Some(len) => len,
        None => {
            return Err(ApiError::TooLarge("Content-Length header is missing or invalid".to_string()));
        }
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
                drop(partial_file);
                let _ = tokio_fs::remove_file(&partial_path).await;
                return Err(ApiError::BadRequest(e.to_string()));
            }
        };

        total_bytes += chunk.len() as u64;
        if total_bytes > max_bytes {
            drop(partial_file);
            let _ = tokio_fs::remove_file(&partial_path).await;
            return Err(ApiError::TooLarge("File exceeded maximum size limit".to_string()));
        }

        if let Err(e) = partial_file.write_all(&chunk).await {
            drop(partial_file);
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

    // Apply auto-copy rules per settings
    let (copy_images, copy_videos) = {
        let cfg = state.config.read().await;
        (cfg.copy_images, cfg.copy_videos_as_files)
    };

    if kind == "image" && copy_images {
        state.clipboard_writer.write_image(&final_path);
    } else if kind == "video" && copy_videos {
        if let Some(path_str) = final_path.to_str() {
            state.clipboard_writer.write_file_list(&[path_str]);
        }
    }

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

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Bytes;
    use futures_util::stream;
    use crate::config::AppConfig;
    use crate::storage::Database;

    #[tokio::test]
    async fn test_streaming_byte_limit_and_cleanup_when_client_lies() {
        let temp_dir = std::env::temp_dir().join(format!("clipsync_stream_test_{}", Uuid::new_v4()));
        let _ = std::fs::create_dir_all(&temp_dir);

        let mut cfg = AppConfig::default();
        cfg.save_folder = temp_dir.to_string_lossy().to_string();
        cfg.max_file_size_mb = 1; // 1 MB limit

        let db = Database::new_in_memory().unwrap();
        let state = AppState::new(cfg, db);

        // Client header claims Content-Length is 500 bytes (within 1 MB limit)
        let mut headers = HeaderMap::new();
        headers.insert(axum::http::header::CONTENT_LENGTH, "500".parse().unwrap());
        headers.insert("x-file-name", "sneaky.bin".parse().unwrap());

        // But the stream actually yields 2 MB of data (two 1 MB chunks)
        let chunk1 = Bytes::from(vec![1u8; 1024 * 1024]);
        let chunk2 = Bytes::from(vec![2u8; 1024 * 1024]);
        let body_stream = stream::iter(vec![
            Ok::<Bytes, std::io::Error>(chunk1),
            Ok::<Bytes, std::io::Error>(chunk2),
        ]);
        let body = Body::from_stream(body_stream);

        // Call handle_file_upload
        let result = handle_file_upload(headers, state.clone(), body).await;

        // Verify result is Err(ApiError::TooLarge)
        assert!(matches!(result, Err(ApiError::TooLarge(_))));

        // Verify no files remain in .partial/ directory
        let partial_dir = state.file_manager.partial_dir();
        if partial_dir.exists() {
            let entries: Vec<_> = std::fs::read_dir(&partial_dir).unwrap().collect();
            assert_eq!(entries.len(), 0, "Partial directory should be empty");
        }

        let _ = std::fs::remove_dir_all(temp_dir);
    }
}

use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tauri::State;
use uuid::Uuid;

use crate::config::AppConfig;
use crate::server::ws::WsServerMessage;
use crate::state::{AppState, FileOffer};
use crate::storage::{DeviceRow, ItemRow};

#[derive(Serialize)]
pub struct ServerStatus {
    pub ip: String,
    pub port: u16,
    pub connected_devices_count: usize,
    pub is_running: bool,
}

#[derive(Serialize)]
pub struct QrCodeResponse {
    pub url: String,
    pub svg: String,
    pub expires_in_seconds: u64,
}

#[tauri::command]
pub async fn get_status(state: State<'_, Arc<AppState>>) -> Result<ServerStatus, String> {
    let port = {
        let cfg = state.config.read().await;
        cfg.port
    };
    let connected_count = {
        let clients = state.ws_clients.read().await;
        clients.len()
    };

    Ok(ServerStatus {
        ip: "127.0.0.1".to_string(), // In full discovery, enumerates local network IPs
        port,
        connected_devices_count: connected_count,
        is_running: true,
    })
}

#[tauri::command]
pub async fn get_pair_qr(state: State<'_, Arc<AppState>>) -> Result<QrCodeResponse, String> {
    let (port, server_id, server_name) = {
        let cfg = state.config.read().await;
        (cfg.port, cfg.server_device_id.clone(), cfg.device_name.clone())
    };

    let cert_fp = "0000000000000000000000000000000000000000000000000000000000000000";
    let qr = state
        .pairing_manager
        .get_qr_data("127.0.0.1", port, cert_fp, &server_id, &server_name)
        .await
        .ok_or_else(|| "Failed to generate QR code".to_string())?;

    Ok(QrCodeResponse {
        url: qr.url,
        svg: qr.svg,
        expires_in_seconds: qr.expires_in_seconds,
    })
}

#[tauri::command]
pub async fn list_devices(state: State<'_, Arc<AppState>>) -> Result<Vec<DeviceRow>, String> {
    state
        .database
        .list_devices()
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn revoke_device(state: State<'_, Arc<AppState>>, device_id: String) -> Result<(), String> {
    state
        .database
        .revoke_device(&device_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_history(state: State<'_, Arc<AppState>>, limit: Option<u32>) -> Result<Vec<ItemRow>, String> {
    state
        .database
        .list_items(limit.unwrap_or(50))
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn delete_history_item(state: State<'_, Arc<AppState>>, id: String) -> Result<(), String> {
    state
        .database
        .delete_item(&id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn clear_history(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    state
        .database
        .clear_items()
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_settings(state: State<'_, Arc<AppState>>) -> Result<AppConfig, String> {
    let cfg = state.config.read().await;
    Ok(cfg.clone())
}

#[tauri::command]
pub async fn set_settings(state: State<'_, Arc<AppState>>, settings: AppConfig) -> Result<(), String> {
    settings.save().map_err(|e| e.to_string())?;
    let mut lock = state.config.write().await;
    *lock = settings;
    Ok(())
}

#[tauri::command]
pub async fn open_folder(path: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .arg(path)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn send_text_to_phone(state: State<'_, Arc<AppState>>, text: String) -> Result<(), String> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let id = Uuid::new_v4().to_string();
    let msg = WsServerMessage::Text {
        id: id.clone(),
        kind: "text".to_string(),
        content: text.clone(),
        ts: now,
    };

    state.broadcast_ws_message(msg).await;

    let item = ItemRow {
        id,
        direction: "out".to_string(),
        kind: "text".to_string(),
        device_id: None,
        text: Some(text),
        file_path: None,
        file_name: None,
        mime: Some("text/plain".to_string()),
        size: None,
        created_at: now,
    };
    let _ = state.database.insert_item(&item);

    Ok(())
}

#[derive(Deserialize)]
pub struct SendFileInput {
    pub file_path: String,
}

#[tauri::command]
pub async fn send_file_to_phone(
    state: State<'_, Arc<AppState>>,
    input: SendFileInput,
) -> Result<(), String> {
    let path = std::path::PathBuf::from(&input.file_path);
    if !path.exists() {
        return Err("File does not exist".to_string());
    }

    let file_id = Uuid::new_v4().to_string();
    let file_name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("file")
        .to_string();

    let metadata = std::fs::metadata(&path).map_err(|e| e.to_string())?;
    let size = metadata.len();

    let offer = FileOffer {
        id: file_id.clone(),
        name: file_name.clone(),
        file_path: path.clone(),
        mime: "application/octet-stream".to_string(),
        size,
        created_at: std::time::Instant::now(),
    };

    state.add_file_offer(offer).await;

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let msg = WsServerMessage::FileOffer {
        id: file_id.clone(),
        name: file_name.clone(),
        size,
        mime: "application/octet-stream".to_string(),
        ts: now,
    };

    state.broadcast_ws_message(msg).await;

    let item = ItemRow {
        id: file_id,
        direction: "out".to_string(),
        kind: "file".to_string(),
        device_id: None,
        text: None,
        file_path: Some(path.to_string_lossy().to_string()),
        file_name: Some(file_name),
        mime: Some("application/octet-stream".to_string()),
        size: Some(size as i64),
        created_at: now,
    };
    let _ = state.database.insert_item(&item);

    Ok(())
}

#[tauri::command]
pub async fn copy_history_item(state: State<'_, Arc<AppState>>, id: String) -> Result<(), String> {
    let items = state.database.list_items(100).map_err(|e| e.to_string())?;
    let item = items
        .into_iter()
        .find(|i| i.id == id)
        .ok_or_else(|| "Item not found".to_string())?;

    if let Some(text) = item.text {
        state.clipboard_writer.write_text(&text);
        return Ok(());
    }

    if let Some(file_path) = item.file_path {
        let path = std::path::Path::new(&file_path);
        if item.kind == "image" {
            state.clipboard_writer.write_image(path);
        } else {
            state.clipboard_writer.write_file_list(&[&file_path]);
        }
        return Ok(());
    }

    Err("No content to copy".to_string())
}

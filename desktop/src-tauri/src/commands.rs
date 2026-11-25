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
    pub is_paused: bool,
}

#[derive(Serialize)]
pub struct QrCodeResponse {
    pub url: String,
    pub svg: String,
    pub expires_in_seconds: u64,
}

pub fn get_local_lan_ip() -> String {
    if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if socket.connect("8.8.8.8:80").is_ok() {
            if let Ok(addr) = socket.local_addr() {
                let ip = addr.ip();
                if !ip.is_loopback() {
                    return ip.to_string();
                }
            }
        }
    }
    "127.0.0.1".to_string()
}

pub fn configure_windows_autostart(enable: bool) {
    #[cfg(target_os = "windows")]
    {
        if enable {
            if let Ok(exe_path) = std::env::current_exe() {
                let cmd = format!("\"{}\" --minimized", exe_path.display());
                let _ = std::process::Command::new("reg")
                    .args(&[
                        "add",
                        r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
                        "/v",
                        "ClipSync",
                        "/t",
                        "REG_SZ",
                        "/d",
                        &cmd,
                        "/f",
                    ])
                    .status();
            }
        } else {
            let _ = std::process::Command::new("reg")
                .args(&[
                    "delete",
                    r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
                    "/v",
                    "ClipSync",
                    "/f",
                ])
                .status();
        }
    }
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
    let is_paused = state.is_paused.load(std::sync::atomic::Ordering::SeqCst);

    Ok(ServerStatus {
        ip: get_local_lan_ip(),
        port,
        connected_devices_count: connected_count,
        is_running: true,
        is_paused,
    })
}

#[tauri::command]
pub async fn get_pair_qr(state: State<'_, Arc<AppState>>) -> Result<QrCodeResponse, String> {
    let (port, server_id, server_name) = {
        let cfg = state.config.read().await;
        (cfg.port, cfg.server_device_id.clone(), cfg.device_name.clone())
    };

    let fp = {
        let f = state.cert_fingerprint.read().await;
        if f.is_empty() {
            let tls_dir = crate::config::app_data_dir().join("tls");
            crate::server::tls::get_or_create_tls_certs(&tls_dir, &server_name)
                .map(|t| t.fingerprint)
                .unwrap_or_else(|_| "0000000000000000000000000000000000000000000000000000000000000000".to_string())
        } else {
            f.clone()
        }
    };

    let ip = get_local_lan_ip();
    let qr = state
        .pairing_manager
        .get_qr_data(&ip, port, &fp, &server_id, &server_name)
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
    configure_windows_autostart(settings.start_with_windows);
    let mut lock = state.config.write().await;
    *lock = settings;
    Ok(())
}

#[tauri::command]
pub async fn toggle_pause_receiving(state: State<'_, Arc<AppState>>) -> Result<bool, String> {
    let current = state.is_paused.load(std::sync::atomic::Ordering::SeqCst);
    let new_val = !current;
    state.is_paused.store(new_val, std::sync::atomic::Ordering::SeqCst);
    Ok(new_val)
}

#[tauri::command]
pub async fn get_pause_status(state: State<'_, Arc<AppState>>) -> Result<bool, String> {
    Ok(state.is_paused.load(std::sync::atomic::Ordering::SeqCst))
}

#[tauri::command]
pub async fn open_folder(path: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        let clean = path.replace('/', "\\");
        std::process::Command::new("explorer")
            .arg(clean)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(not(target_os = "windows"))]
    {
        open::that(&path).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn open_file(path: String) -> Result<(), String> {
    let p = std::path::Path::new(&path);
    if !p.exists() {
        return Err("File not found".to_string());
    }
    open::that(p).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn reveal_in_folder(path: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        let clean = path.replace('/', "\\");
        std::process::Command::new("explorer")
            .args([format!("/select,{}", clean)])
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(not(target_os = "windows"))]
    {
        let p = std::path::Path::new(&path);
        let folder = if p.is_file() {
            p.parent().unwrap_or(p)
        } else {
            p
        };
        open::that(folder).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn read_image_base64(path: String) -> Result<String, String> {
    let p = std::path::Path::new(&path);
    if !p.exists() {
        return Err("File not found".to_string());
    }
    let bytes = std::fs::read(p).map_err(|e| e.to_string())?;
    let ext = p
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    let mime = match ext.as_str() {
        "png" => "image/png",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "bmp" => "image/bmp",
        _ => "image/jpeg",
    };
    use base64::Engine;
    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
    Ok(format!("data:{};base64,{}", mime, b64))
}

#[derive(Serialize)]
pub struct PickedFileInfo {
    pub path: String,
    pub name: String,
    pub size: u64,
}

#[tauri::command]
pub async fn pick_file() -> Result<Option<PickedFileInfo>, String> {
    let file = rfd::AsyncFileDialog::new().pick_file().await;
    match file {
        Some(handle) => {
            let path = handle.path().to_path_buf();
            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("file")
                .to_string();
            let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
            Ok(Some(PickedFileInfo {
                path: path.to_string_lossy().to_string(),
                name,
                size,
            }))
        }
        None => Ok(None),
    }
}

#[tauri::command]
pub async fn get_file_info(path: String) -> Result<PickedFileInfo, String> {
    let p = std::path::PathBuf::from(&path);
    if !p.exists() || !p.is_file() {
        return Err("File not found".to_string());
    }
    let name = p
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("file")
        .to_string();
    let size = std::fs::metadata(&p).map_err(|e| e.to_string())?.len();
    Ok(PickedFileInfo { path, name, size })
}

#[tauri::command]
pub async fn send_text_to_phone(state: State<'_, Arc<AppState>>, text: String) -> Result<usize, String> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let connected_count = state.ws_clients.read().await.len();

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

    Ok(connected_count)
}

#[derive(Deserialize)]
pub struct SendFileInput {
    pub file_path: String,
}

#[tauri::command]
pub async fn send_file_to_phone(
    state: State<'_, Arc<AppState>>,
    input: SendFileInput,
) -> Result<usize, String> {
    let path = std::path::PathBuf::from(&input.file_path);
    if !path.exists() {
        return Err("File does not exist".to_string());
    }

    let connected_count = state.ws_clients.read().await.len();

    let file_id = Uuid::new_v4().to_string();
    let file_name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("file")
        .to_string();

    let metadata = std::fs::metadata(&path).map_err(|e| e.to_string())?;
    let size = metadata.len();

    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    let (kind, mime) = match ext.as_str() {
        "png" => ("image", "image/png"),
        "jpg" | "jpeg" => ("image", "image/jpeg"),
        "gif" => ("image", "image/gif"),
        "webp" => ("image", "image/webp"),
        "bmp" => ("image", "image/bmp"),
        "mp4" | "mov" | "mkv" => ("video", "video/mp4"),
        _ => ("file", "application/octet-stream"),
    };

    let offer = FileOffer {
        id: file_id.clone(),
        name: file_name.clone(),
        file_path: path.clone(),
        mime: mime.to_string(),
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
        mime: mime.to_string(),
        ts: now,
    };

    state.broadcast_ws_message(msg).await;

    let item = ItemRow {
        id: file_id,
        direction: "out".to_string(),
        kind: kind.to_string(),
        device_id: None,
        text: None,
        file_path: Some(path.to_string_lossy().to_string()),
        file_name: Some(file_name),
        mime: Some(mime.to_string()),
        size: Some(size as i64),
        created_at: now,
    };
    let _ = state.database.insert_item(&item);

    Ok(connected_count)
}

#[tauri::command]
pub async fn copy_history_item(state: State<'_, Arc<AppState>>, id: String) -> Result<(), String> {
    let items = state.database.list_items(200).map_err(|e| e.to_string())?;
    let item = items
        .into_iter()
        .find(|i| i.id == id)
        .ok_or_else(|| "Item not found".to_string())?;

    if let Some(ref text) = item.text {
        if state.clipboard_writer.write_text(text) {
            return Ok(());
        }
    }

    if let Some(ref file_path) = item.file_path {
        let path = std::path::Path::new(file_path);
        if item.kind == "image" {
            if state.clipboard_writer.write_image(path) {
                return Ok(());
            }
        } else {
            if state.clipboard_writer.write_file_list(&[file_path.as_str()]) {
                return Ok(());
            }
        }
    }

    Err("Failed to copy item to clipboard".to_string())
}

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub port: u16,
    pub save_folder: String,
    pub max_file_size_mb: u64,
    pub copy_text_links: bool,
    pub copy_images: bool,
    pub copy_videos_as_files: bool,
    pub notifications_on_receive: bool,
    pub auto_send_clipboard: bool,
    pub send_hotkey: String,
    pub start_with_windows: bool,
    pub retention_days: u32,
    pub retention_max_items: u32,
    pub device_name: String,
    pub server_device_id: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        let device_name = std::env::var("COMPUTERNAME")
            .or_else(|_| std::env::var("HOSTNAME"))
            .unwrap_or_else(|_| "ClipSync PC".to_string());

        let save_folder = dirs_save_folder().unwrap_or_else(|| "ClipSync".to_string());

        Self {
            port: 47821,
            save_folder,
            max_file_size_mb: 50,
            copy_text_links: true,
            copy_images: true,
            copy_videos_as_files: false,
            notifications_on_receive: true,
            auto_send_clipboard: false,
            send_hotkey: "Ctrl+Shift+S".to_string(),
            start_with_windows: false,
            retention_days: 30,
            retention_max_items: 500,
            device_name,
            server_device_id: Uuid::new_v4().to_string(),
        }
    }
}

pub fn app_data_dir() -> PathBuf {
    let base = std::env::var("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."));
    base.join("ClipSync")
}

pub fn dirs_save_folder() -> Option<String> {
    if let Ok(profile) = std::env::var("USERPROFILE") {
        let path = PathBuf::from(profile).join("Downloads").join("ClipSync");
        return Some(path.to_string_lossy().to_string());
    }
    None
}

impl AppConfig {
    pub fn config_path() -> PathBuf {
        app_data_dir().join("config.json")
    }

    pub fn load() -> Self {
        let path = Self::config_path();
        if path.exists() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(cfg) = serde_json::from_str::<AppConfig>(&content) {
                    return cfg;
                }
            }
        }
        let cfg = AppConfig::default();
        let _ = cfg.save();
        cfg
    }

    pub fn save(&self) -> Result<(), std::io::Error> {
        let path = Self::config_path();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        fs::write(path, json)
    }
}

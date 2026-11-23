pub mod clipboard;
pub mod commands;
pub mod config;
pub mod discovery;
pub mod hotkey;
pub mod notify;
pub mod pairing;
pub mod server;
pub mod state;
pub mod storage;
pub mod tray;

use commands::*;
use config::AppConfig;
use discovery::MdnsDiscovery;
use state::AppState;
use storage::Database;
use tracing::info;

pub fn run() {
    let log_dir = config::app_data_dir().join("logs");
    let _ = std::fs::create_dir_all(&log_dir);
    let file_appender = tracing_appender::rolling::daily(&log_dir, "clipsync.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .with_writer(non_blocking)
        .init();

    info!("Starting ClipSync Desktop Application");

    let cfg = AppConfig::load();
    let db_path = config::app_data_dir().join("clipsync.db");

    if let Some(parent) = db_path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    let db = Database::new(&db_path).unwrap_or_else(|e| {
        tracing::error!("Failed to open database at {}: {}, using in-memory", db_path.display(), e);
        Database::new_in_memory().expect("in-memory database fallback failed")
    });

    let app_state = AppState::new(cfg.clone(), db);

    // Start background Axum server (HTTPS with TLS)
    let server_state = app_state.clone();
    let port = cfg.port;
    tauri::async_runtime::spawn(async move {
        if let Err(e) = server::start_server(server_state, port, true).await {
            tracing::error!("Failed to start server: {}", e);
        }
    });

    // Start mDNS discovery service
    if let Ok(discovery) = MdnsDiscovery::new() {
        let _ = discovery.register_service(
            &cfg.server_device_id,
            &cfg.device_name,
            cfg.port,
            "0000000000000000000000000000000000000000000000000000000000000000",
        );
    }

    let builder_state = app_state.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(builder_state)
        .setup(|app| {
            if let Err(e) = tray::setup_tray(app.handle()) {
                tracing::warn!("Failed to setup system tray: {}", e);
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            get_pair_qr,
            list_devices,
            revoke_device,
            get_history,
            delete_history_item,
            clear_history,
            get_settings,
            set_settings,
            open_folder,
            send_text_to_phone,
            send_file_to_phone,
            copy_history_item,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

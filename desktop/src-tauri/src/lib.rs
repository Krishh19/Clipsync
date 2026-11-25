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

    // Run startup retention cleanup
    if let Err(e) = db.clean_retention(cfg.retention_days, cfg.retention_max_items) {
        tracing::warn!("Failed to run startup retention cleanup: {}", e);
    }

    let app_state = AppState::new(cfg.clone(), db);

    // Periodic daily retention cleanup
    let periodic_state = app_state.clone();
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(86400));
        loop {
            interval.tick().await;
            let (days, max_items) = {
                let cfg = periodic_state.config.read().await;
                (cfg.retention_days, cfg.retention_max_items)
            };
            if let Err(e) = periodic_state.database.clean_retention(days, max_items) {
                tracing::warn!("Failed to run periodic retention cleanup: {}", e);
            } else {
                tracing::info!("Periodic retention cleanup completed");
            }
        }
    });

    // Start clipboard watcher thread
    let watcher_state = app_state.clone();
    app_state.clipboard_watcher.start(
        app_state.last_written_clipboard.clone(),
        move |text| {
            let state = watcher_state.clone();
            tauri::async_runtime::spawn(async move {
                if state.is_paused.load(std::sync::atomic::Ordering::SeqCst) {
                    return;
                }
                let auto_send = {
                    let cfg = state.config.read().await;
                    cfg.auto_send_clipboard
                };
                if !auto_send {
                    return;
                }
                let has_clients = {
                    let clients = state.ws_clients.read().await;
                    !clients.is_empty()
                };
                if !has_clients {
                    return;
                }
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs() as i64;
                let id = uuid::Uuid::new_v4().to_string();
                let msg = server::ws::WsServerMessage::Text {
                    id: id.clone(),
                    kind: "text".to_string(),
                    content: text.clone(),
                    ts: now,
                };
                state.broadcast_ws_message(msg).await;

                let item = storage::ItemRow {
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
            });
        },
    );

    // Start background Axum server (HTTPS with TLS) and register mDNS
    let server_state = app_state.clone();
    let port = cfg.port;
    tauri::async_runtime::spawn(async move {
        match server::start_server(server_state.clone(), port, true).await {
            Ok(handle) => {
                let (device_id, device_name, fp) = {
                    let cfg = server_state.config.read().await;
                    let fp = server_state.cert_fingerprint.read().await;
                    (cfg.server_device_id.clone(), cfg.device_name.clone(), fp.clone())
                };

                if let Some(ref discovery) = *server_state.discovery {
                    if let Err(e) = discovery.register_service(&device_id, &device_name, handle.port, &fp) {
                        tracing::warn!("Failed to register mDNS service: {}", e);
                    }
                }
                *server_state.server_handle.lock().unwrap() = Some(handle);
            }
            Err(e) => {
                tracing::error!("Failed to start server: {}", e);
            }
        }
    });

    let builder_state = app_state.clone();
    let hotkey_state = app_state.clone();
    let shortcut_plugin = tauri_plugin_global_shortcut::Builder::new()
        .with_handler(move |_app, _shortcut, event| {
            if event.state() == tauri_plugin_global_shortcut::ShortcutState::Pressed {
                let state = hotkey_state.clone();
                tauri::async_runtime::spawn(async move {
                    hotkey::send_clipboard_to_connected_phones(state).await;
                });
            }
        })
        .build();

    use tauri::Manager;

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(shortcut_plugin)
        .manage(builder_state)
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .setup(|app| {
            if let Err(e) = tray::setup_tray(app.handle()) {
                tracing::warn!("Failed to setup system tray: {}", e);
            }

            let send_hotkey = {
                let state = app.state::<std::sync::Arc<AppState>>();
                let cfg = state.config.blocking_read();
                cfg.send_hotkey.clone()
            };
            use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut};
            if let Ok(shortcut) = send_hotkey.parse::<Shortcut>() {
                if let Err(e) = app.global_shortcut().register(shortcut) {
                    tracing::warn!("Failed to register global hotkey {}: {}", send_hotkey, e);
                } else {
                    tracing::info!("Registered global hotkey: {}", send_hotkey);
                }
            }

            let args: Vec<String> = std::env::args().collect();
            if args.iter().any(|arg| arg == "--minimized") {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                }
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
            open_file,
            reveal_in_folder,
            read_image_base64,
            pick_file,
            get_file_info,
            send_text_to_phone,
            send_file_to_phone,
            copy_history_item,
            toggle_pause_receiving,
            get_pause_status,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

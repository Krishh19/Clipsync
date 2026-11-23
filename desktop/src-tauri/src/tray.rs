use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager,
};
use tracing::info;

pub fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let open_i = MenuItem::with_id(app, "open", "Open", true, None::<&str>)?;
    let pause_i = MenuItem::with_id(app, "pause", "Pause receiving", true, None::<&str>)?;
    let send_i = MenuItem::with_id(app, "send_clip", "Send clipboard to phone", true, None::<&str>)?;
    let folder_i = MenuItem::with_id(app, "folder", "Open save folder", true, None::<&str>)?;
    let quit_i = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&open_i, &pause_i, &send_i, &folder_i, &quit_i])?;

    let icon = app.default_window_icon().cloned().ok_or("No default window icon")?;

    let _tray = TrayIconBuilder::new()
        .icon(icon)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.unminimize();
                    let _ = window.set_focus();
                }
            }
            "pause" => {
                if let Some(state) = app.try_state::<std::sync::Arc<crate::state::AppState>>() {
                    let was_paused = state.is_paused.fetch_xor(true, std::sync::atomic::Ordering::SeqCst);
                    let new_state = !was_paused;
                    info!("Toggled pause receiving from tray: is_paused={}", new_state);
                }
            }
            "send_clip" => {
                if let Some(state) = app.try_state::<std::sync::Arc<crate::state::AppState>>() {
                    let state = (*state).clone();
                    tauri::async_runtime::spawn(async move {
                        let sent = crate::hotkey::send_clipboard_to_connected_phones(state).await;
                        info!("Tray send clipboard result: {}", sent);
                    });
                }
            }
            "folder" => {
                if let Some(state) = app.try_state::<std::sync::Arc<crate::state::AppState>>() {
                    let state = (*state).clone();
                    tauri::async_runtime::spawn(async move {
                        let folder = {
                            let cfg = state.config.read().await;
                            cfg.save_folder.clone()
                        };
                        let _ = crate::commands::open_folder(folder);
                    });
                }
            }
            "quit" => {
                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.unminimize();
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)?;

    Ok(())
}

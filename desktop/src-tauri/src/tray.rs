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
                    let _ = window.set_focus();
                }
            }
            "pause" => {
                info!("Toggled pause receiving");
            }
            "send_clip" => {
                info!("Send clipboard triggered from tray");
            }
            "folder" => {
                info!("Open folder triggered from tray");
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
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)?;

    Ok(())
}

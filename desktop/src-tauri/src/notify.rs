use tracing::info;

pub struct NotificationManager;

impl NotificationManager {
    pub fn new() -> Self {
        Self
    }

    pub fn show_received_text(&self, sender_name: &str, text: &str) {
        let snippet: String = text.chars().take(80).collect();
        info!("Notification: From {} -> {}", sender_name, snippet);
        // In full milestone, triggers tauri-plugin-notification
    }

    pub fn show_received_file(&self, sender_name: &str, file_name: &str, _file_path: &str) {
        info!("Notification: From {} -> Received file {}", sender_name, file_name);
        // In full milestone, triggers tauri-plugin-notification with click action
    }
}

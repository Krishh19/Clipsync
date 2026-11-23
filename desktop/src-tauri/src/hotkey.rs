use sha2::{Digest, Sha256};
use std::sync::Arc;
use tracing::info;
use crate::server::ws::WsServerMessage;
use crate::state::AppState;
use crate::storage::ItemRow;

pub struct HotkeyManager;

impl HotkeyManager {
    pub fn new() -> Self {
        Self
    }
}

/// Reads current clipboard text and pushes it to all connected phones via WebSocket.
/// Updates `last_written_clipboard` with the SHA-256 hash to prevent echo loops.
pub async fn send_clipboard_to_connected_phones(state: Arc<AppState>) -> bool {
    let text = match arboard::Clipboard::new() {
        Ok(mut clip) => match clip.get_text() {
            Ok(t) if !t.is_empty() => t,
            _ => return false,
        },
        Err(_) => return false,
    };

    // Calculate SHA-256 hash and record in last_written to prevent echo loops
    let mut hasher = Sha256::new();
    hasher.update(text.as_bytes());
    let hash = hasher.finalize().to_vec();
    {
        let mut last = state.last_written_clipboard.lock().unwrap();
        *last = Some(hash);
    }

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let id = uuid::Uuid::new_v4().to_string();

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
    info!("Successfully sent clipboard text to connected phones via hotkey/action");

    true
}

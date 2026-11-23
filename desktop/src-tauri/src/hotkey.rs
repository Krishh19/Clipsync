use std::sync::Arc;
use tracing::info;
use crate::state::AppState;

pub struct HotkeyManager;

impl HotkeyManager {
    pub fn new() -> Self {
        Self
    }

    pub fn register_default_shortcut(&self, _state: Arc<AppState>) {
        info!("Registering global hotkey (default Ctrl+Shift+S)");
        // In full milestone, integrates with tauri-plugin-global-shortcut
    }
}

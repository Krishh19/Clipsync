use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, RwLock};

use crate::clipboard::{ClipboardWatcher, ClipboardWriter};
use crate::config::AppConfig;
use crate::pairing::PairingManager;
use crate::server::dedup::ClientIdDedup;
use crate::server::ws::WsServerMessage;
use crate::storage::{Database, FileManager};

#[derive(Clone)]
pub struct FileOffer {
    pub id: String,
    pub name: String,
    pub file_path: PathBuf,
    pub mime: String,
    pub size: u64,
    pub created_at: std::time::Instant,
}

pub struct AppState {
    pub config: Arc<RwLock<AppConfig>>,
    pub database: Database,
    pub file_manager: FileManager,
    pub pairing_manager: PairingManager,
    pub clipboard_writer: ClipboardWriter,
    pub clipboard_watcher: ClipboardWatcher,
    pub ws_clients: Arc<RwLock<HashMap<String, mpsc::Sender<WsServerMessage>>>>,
    pub file_offers: Arc<RwLock<HashMap<String, FileOffer>>>,
    pub last_written_clipboard: Arc<Mutex<Option<Vec<u8>>>>,
    pub client_id_dedup: Arc<ClientIdDedup>,
}

impl AppState {
    pub fn new(cfg: AppConfig, db: Database) -> Arc<Self> {
        let save_folder = PathBuf::from(&cfg.save_folder);
        let last_written = Arc::new(Mutex::new(None));
        let clipboard_writer = ClipboardWriter::new(last_written.clone());
        let clipboard_watcher = ClipboardWatcher::new();

        Arc::new(Self {
            config: Arc::new(RwLock::new(cfg)),
            database: db,
            file_manager: FileManager::new(save_folder),
            pairing_manager: PairingManager::new(),
            clipboard_writer,
            clipboard_watcher,
            ws_clients: Arc::new(RwLock::new(HashMap::new())),
            file_offers: Arc::new(RwLock::new(HashMap::new())),
            last_written_clipboard: last_written,
            client_id_dedup: Arc::new(ClientIdDedup::default()),
        })
    }

    pub async fn register_ws_client(&self, device_id: &str, sender: mpsc::Sender<WsServerMessage>) {
        let mut clients = self.ws_clients.write().await;
        clients.insert(device_id.to_string(), sender);
    }

    pub async fn unregister_ws_client(&self, device_id: &str) {
        let mut clients = self.ws_clients.write().await;
        clients.remove(device_id);
    }

    pub async fn broadcast_ws_message(&self, message: WsServerMessage) {
        let clients = self.ws_clients.read().await;
        for (device_id, tx) in clients.iter() {
            if let Err(e) = tx.send(message.clone()).await {
                tracing::warn!("Failed to deliver WS message to device {}: {}", device_id, e);
            }
        }
    }

    pub async fn add_file_offer(&self, offer: FileOffer) {
        let mut offers = self.file_offers.write().await;
        offers.insert(offer.id.clone(), offer);
    }

    pub async fn get_file_offer(&self, id: &str) -> Option<FileOffer> {
        let offers = self.file_offers.read().await;
        offers.get(id).cloned()
    }
}

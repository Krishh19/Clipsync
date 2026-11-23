use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::response::IntoResponse;
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::interval;
use tracing::{debug, error, info};

use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsServerMessage {
    #[serde(rename = "hello")]
    Hello {
        server_name: String,
        protocol: u32,
    },
    #[serde(rename = "text")]
    Text {
        id: String,
        kind: String,
        content: String,
        ts: i64,
    },
    #[serde(rename = "file_offer")]
    FileOffer {
        id: String,
        name: String,
        size: u64,
        mime: String,
        ts: i64,
    },
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "pong")]
    Pong,
}

pub async fn handle_ws_upgrade(
    ws: WebSocketUpgrade,
    state: Arc<AppState>,
    device_id: String,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_ws_socket(socket, state, device_id))
}

async fn handle_ws_socket(socket: WebSocket, state: Arc<AppState>, device_id: String) {
    let (mut sender, mut receiver) = socket.split();
    let (tx, mut rx) = mpsc::channel::<WsServerMessage>(32);

    // Register active connection
    state.register_ws_client(&device_id, tx.clone()).await;
    info!("WebSocket client connected for device: {}", device_id);

    // Send hello message
    let (server_name, protocol) = {
        let cfg = state.config.read().await;
        (cfg.device_name.clone(), 1)
    };

    let hello_msg = WsServerMessage::Hello {
        server_name,
        protocol,
    };
    if let Ok(json) = serde_json::to_string(&hello_msg) {
        let _ = sender.send(Message::Text(json)).await;
    }

    let missed_pongs = Arc::new(std::sync::atomic::AtomicU32::new(0));

    // Ping interval task: pings every 20s, terminates if 2 consecutive pongs missed
    let ping_tx = tx.clone();
    let ping_missed = missed_pongs.clone();
    let dev_id = device_id.clone();
    let ping_handle = tokio::spawn(async move {
        let mut ticker = interval(Duration::from_secs(20));
        // Consume the immediate first tick
        ticker.tick().await;
        loop {
            ticker.tick().await;
            let missed = ping_missed.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            if missed >= 2 {
                info!(
                    "WebSocket client {} missed {} consecutive pongs; closing connection",
                    dev_id, missed
                );
                break;
            }
            if ping_tx.send(WsServerMessage::Ping).await.is_err() {
                break;
            }
        }
    });

    // Outbound messages forwarding task
    let mut send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            match serde_json::to_string(&msg) {
                Ok(json) => {
                    if let Err(e) = sender.send(Message::Text(json)).await {
                        debug!("Failed to send websocket message: {}", e);
                        break;
                    }
                }
                Err(e) => {
                    error!("Failed to serialize websocket message: {}", e);
                }
            }
        }
    });

    // Inbound messages receiving task
    let recv_missed = missed_pongs.clone();
    let mut recv_task = tokio::spawn(async move {
        while let Some(msg_result) = receiver.next().await {
            match msg_result {
                Ok(Message::Text(txt)) => {
                    debug!("Received WS text message: {}", txt);
                    if let Ok(val) = serde_json::from_str::<serde_json::Value>(&txt) {
                        if val.get("type").and_then(|t| t.as_str()) == Some("pong") {
                            debug!("Resetting missed pongs on received json pong");
                            recv_missed.store(0, std::sync::atomic::Ordering::SeqCst);
                        }
                    }
                }
                Ok(Message::Close(_)) => {
                    break;
                }
                Ok(Message::Pong(_)) => {
                    debug!("Received WS pong control frame; resetting missed pongs");
                    recv_missed.store(0, std::sync::atomic::Ordering::SeqCst);
                }
                Err(e) => {
                    debug!("WS error: {}", e);
                    break;
                }
                _ => {}
            }
        }
    });

    tokio::select! {
        _ = (&mut send_task) => {},
        _ = (&mut recv_task) => {},
        _ = ping_handle => {},
    };

    send_task.abort();
    recv_task.abort();

    state.unregister_ws_client(&device_id).await;
    info!("WebSocket client disconnected for device: {}", device_id);
}

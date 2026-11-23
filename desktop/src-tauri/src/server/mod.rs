pub mod auth;
pub mod dedup;
pub mod errors;
pub mod ratelimit;
pub mod routes;
pub mod tls;
pub mod upload;
pub mod ws;

use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::oneshot;
use tracing::info;

use crate::state::AppState;

pub struct ServerHandle {
    pub port: u16,
    pub shutdown_tx: Option<oneshot::Sender<()>>,
}

pub async fn start_server(
    state: Arc<AppState>,
    start_port: u16,
) -> Result<ServerHandle, Box<dyn std::error::Error + Send + Sync>> {
    let mut listener = None;
    let mut bound_port = start_port;

    for p in start_port..=start_port.saturating_add(20) {
        let addr = SocketAddr::from(([0, 0, 0, 0], p));
        match tokio::net::TcpListener::bind(addr).await {
            Ok(l) => {
                listener = Some(l);
                bound_port = p;
                break;
            }
            Err(e) => {
                tracing::warn!("Port {} unavailable: {}, trying next port...", p, e);
            }
        }
    }

    let listener = listener.ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::AddrInUse,
            format!("All ports from {} to {} are busy", start_port, start_port.saturating_add(20)),
        )
    })?;

    // Update config with the actual bound port
    {
        let mut cfg = state.config.write().await;
        cfg.port = bound_port;
    }

    let bound_addr = SocketAddr::from(([0, 0, 0, 0], bound_port));
    info!("ClipSync server bound to {}", bound_addr);

    let router = routes::create_router(state.clone());
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, router)
            .with_graceful_shutdown(async move {
                let _ = shutdown_rx.await;
            })
            .await
        {
            tracing::error!("Server error: {}", e);
        }
    });

    Ok(ServerHandle {
        port: bound_port,
        shutdown_tx: Some(shutdown_tx),
    })
}

pub mod auth;
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
    pub shutdown_tx: Option<oneshot::Sender<()>>,
}

pub async fn start_server(
    state: Arc<AppState>,
    port: u16,
) -> Result<ServerHandle, Box<dyn std::error::Error + Send + Sync>> {
    let router = routes::create_router(state.clone());
    let addr = SocketAddr::from(([0, 0, 0, 0], port));

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    info!("Starting ClipSync server on {}", addr);

    tokio::spawn(async move {
        let listener = match tokio::net::TcpListener::bind(addr).await {
            Ok(l) => l,
            Err(e) => {
                tracing::error!("Failed to bind server to {}: {}", addr, e);
                return;
            }
        };

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
        shutdown_tx: Some(shutdown_tx),
    })
}

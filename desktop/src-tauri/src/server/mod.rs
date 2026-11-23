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
    use_tls: bool,
) -> Result<ServerHandle, Box<dyn std::error::Error + Send + Sync>> {
    let mut bound_port = start_port;
    let mut listener_found = false;

    for p in start_port..=start_port.saturating_add(20) {
        let addr = SocketAddr::from(([0, 0, 0, 0], p));
        if let Ok(l) = std::net::TcpListener::bind(addr) {
            drop(l);
            bound_port = p;
            listener_found = true;
            break;
        }
    }

    if !listener_found {
        return Err(std::io::Error::new(
            std::io::ErrorKind::AddrInUse,
            format!("All ports from {} to {} are busy", start_port, start_port.saturating_add(20)),
        ).into());
    }

    {
        let mut cfg = state.config.write().await;
        cfg.port = bound_port;
    }

    let addr = SocketAddr::from(([0, 0, 0, 0], bound_port));
    let router = routes::create_router(state.clone());
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    if use_tls {
        let tls_dir = crate::config::app_data_dir().join("tls");
        let hostname = {
            let cfg = state.config.read().await;
            cfg.device_name.clone()
        };
        let tls_config = tls::get_or_create_tls_certs(&tls_dir, &hostname)?;
        {
            let mut fp_lock = state.cert_fingerprint.write().await;
            *fp_lock = tls_config.fingerprint.clone();
        }

        let rustls_config = tls::create_rustls_config(&tls_config.cert_path, &tls_config.key_path).await?;
        info!("ClipSync HTTPS (TLS) server running on https://{}", addr);

        let handle = axum_server::Handle::new();
        let server_handle = handle.clone();
        tokio::spawn(async move {
            if let Ok(()) = shutdown_rx.await {
                server_handle.graceful_shutdown(Some(std::time::Duration::from_secs(2)));
            }
        });

        tokio::spawn(async move {
            if let Err(e) = axum_server::bind_rustls(addr, rustls_config)
                .handle(handle)
                .serve(router.into_make_service_with_connect_info::<SocketAddr>())
                .await
            {
                tracing::error!("TLS Server error: {}", e);
            }
        });
    } else {
        info!("ClipSync HTTP server running on http://{}", addr);
        let listener = tokio::net::TcpListener::bind(addr).await?;
        tokio::spawn(async move {
            let shutdown_signal = async move {
                if let Ok(()) = shutdown_rx.await {
                    // intentional shutdown
                } else {
                    std::future::pending::<()>().await;
                }
            };
            if let Err(e) = axum::serve(listener, router)
                .with_graceful_shutdown(shutdown_signal)
                .await
            {
                tracing::error!("Server error: {}", e);
            }
        });
    }

    Ok(ServerHandle {
        port: bound_port,
        shutdown_tx: Some(shutdown_tx),
    })
}

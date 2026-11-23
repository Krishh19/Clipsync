use clipsync_desktop_lib::config::AppConfig;
use clipsync_desktop_lib::server::start_server;
use clipsync_desktop_lib::state::AppState;
use clipsync_desktop_lib::storage::Database;
use tracing::info;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .init();

    info!("Starting ClipSync Dev Server (plain HTTP mode)");

    let mut cfg = AppConfig::load();
    cfg.port = 47821;

    let db = Database::new_in_memory()?;
    let state = AppState::new(cfg, db);

    let handle = start_server(state.clone(), 47821).await?;

    println!("============================================================");
    println!("ClipSync Dev Server running at: http://127.0.0.1:{}", handle.port);
    println!("Static dev token: dev-token-clipsync");
    println!("Authorization: Bearer dev-token-clipsync");
    println!("Press Ctrl+C to stop.");
    println!("============================================================");

    tokio::signal::ctrl_c().await?;
    println!("Shutting down dev server...");

    if let Some(shutdown_tx) = handle.shutdown_tx {
        let _ = shutdown_tx.send(());
    }

    Ok(())
}

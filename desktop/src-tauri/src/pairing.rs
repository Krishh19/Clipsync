use qrcode::render::svg;
use qrcode::QrCode;
use rand::RngCore;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

#[derive(Clone)]
pub struct ActiveToken {
    pub token: String,
    pub created_at: Instant,
    pub expires_in: Duration,
}

pub struct PairingManager {
    active_token: Arc<RwLock<Option<ActiveToken>>>,
}

pub struct PairQrData {
    pub url: String,
    pub svg: String,
    pub expires_in_seconds: u64,
}

impl PairingManager {
    pub fn new() -> Self {
        Self {
            active_token: Arc::new(RwLock::new(None)),
        }
    }

    pub async fn create_token(&self) -> String {
        let mut bytes = [0u8; 16]; // 128-bit random token
        rand::thread_rng().fill_bytes(&mut bytes);
        let token = bytes.iter().map(|b| format!("{b:02x}")).collect::<String>();

        let mut lock = self.active_token.write().await;
        *lock = Some(ActiveToken {
            token: token.clone(),
            created_at: Instant::now(),
            expires_in: Duration::from_secs(300), // 5 minutes
        });

        token
    }

    pub async fn consume_token(&self, token: &str) -> bool {
        let mut lock = self.active_token.write().await;
        if let Some(active) = lock.take() {
            if active.token == token && active.created_at.elapsed() <= active.expires_in {
                return true;
            }
        }
        false
    }

    pub fn generate_device_secret(&self) -> String {
        let mut bytes = [0u8; 32]; // 256-bit random
        rand::thread_rng().fill_bytes(&mut bytes);
        // Base64url without padding
        base64_url_encode(&bytes)
    }

    pub async fn get_qr_data(
        &self,
        host: &str,
        port: u16,
        cert_fp: &str,
        server_id: &str,
        server_name: &str,
    ) -> Option<PairQrData> {
        let token = self.create_token().await;
        let url = format!(
            "clipsync://pair?host={}&port={}&token={}&fp={}&id={}&name={}",
            host,
            port,
            token,
            cert_fp,
            server_id,
            urlencoding_encode(server_name)
        );

        let qr = QrCode::new(url.as_bytes()).ok()?;
        let svg = qr
            .render::<svg::Color>()
            .min_dimensions(200, 200)
            .build();

        Some(PairQrData {
            url,
            svg,
            expires_in_seconds: 300,
        })
    }
}

fn base64_url_encode(bytes: &[u8]) -> String {
    const URL_SAFE_CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::new();
    let mut val = 0u32;
    let mut valb = -6;
    for &b in bytes {
        val = (val << 8) + (b as u32);
        valb += 8;
        while valb >= 0 {
            out.push(URL_SAFE_CHARS[((val >> valb) & 0x3F) as usize] as char);
            valb -= 6;
        }
    }
    if valb > -6 {
        out.push(URL_SAFE_CHARS[((val << (8 - (valb + 8))) & 0x3F) as usize] as char);
    }
    out
}

fn urlencoding_encode(val: &str) -> String {
    let mut encoded = String::new();
    for b in val.bytes() {
        if b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || b == b'.' || b == b'~' {
            encoded.push(b as char);
        } else {
            encoded.push_str(&format!("%{b:02X}"));
        }
    }
    encoded
}

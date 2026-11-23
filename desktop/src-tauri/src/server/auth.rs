use sha2::{Digest, Sha256};
use crate::storage::Database;

pub fn hash_secret(secret: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(secret.as_bytes());
    hex::encode(hasher.finalize())
}

pub fn verify_bearer(auth_header: Option<&str>, db: &Database) -> Option<String> {
    let header = auth_header?;
    let token = header.strip_prefix("Bearer ")?.trim();

    // In dev mode, allow dev token
    #[cfg(feature = "dev_plain_http")]
    if token == "clipsync-dev-token" {
        return Some("dev_device".to_string());
    }

    let hashed = hash_secret(token);
    match db.get_device_by_secret_hash(&hashed) {
        Ok(Some(dev)) => Some(dev.id),
        _ => None,
    }
}

pub mod hex {
    pub fn encode<T: AsRef<[u8]>>(data: T) -> String {
        data.as_ref()
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect()
    }
}

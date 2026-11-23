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
    if token == "dev-token-clipsync" || token == "clipsync-dev-token" {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{Database, DeviceRow};

    #[test]
    fn test_auth_missing_or_invalid_header() {
        let db = Database::new_in_memory().unwrap();
        assert_eq!(verify_bearer(None, &db), None);
        assert_eq!(verify_bearer(Some("Basic 12345"), &db), None);
        assert_eq!(verify_bearer(Some("Bearer "), &db), None);
        assert_eq!(verify_bearer(Some("Bearer random-wrong-token"), &db), None);
    }

    #[test]
    #[cfg(feature = "dev_plain_http")]
    fn test_auth_dev_token() {
        let db = Database::new_in_memory().unwrap();
        assert_eq!(
            verify_bearer(Some("Bearer dev-token-clipsync"), &db),
            Some("dev_device".to_string())
        );
        assert_eq!(
            verify_bearer(Some("Bearer clipsync-dev-token"), &db),
            Some("dev_device".to_string())
        );
    }

    #[test]
    fn test_auth_valid_db_device() {
        let db = Database::new_in_memory().unwrap();
        let secret = "my-secret-key-12345";
        let secret_hash = hash_secret(secret);

        let dev = DeviceRow {
            id: "phone-device-1".to_string(),
            name: "Pixel 8".to_string(),
            platform: "android".to_string(),
            secret_hash,
            created_at: 1000,
            last_seen: 1000,
            revoked: false,
        };
        db.insert_device(&dev).unwrap();

        assert_eq!(
            verify_bearer(Some(&format!("Bearer {secret}")), &db),
            Some("phone-device-1".to_string())
        );

        // Revoke device
        db.revoke_device("phone-device-1").unwrap();
        assert_eq!(
            verify_bearer(Some(&format!("Bearer {secret}")), &db),
            None
        );
    }
}

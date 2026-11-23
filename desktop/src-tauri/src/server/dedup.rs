use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub struct ClientIdDedup {
    cache: Mutex<HashMap<String, (String, Instant)>>,
    ttl: Duration,
}

impl ClientIdDedup {
    pub fn new(ttl: Duration) -> Self {
        Self {
            cache: Mutex::new(HashMap::new()),
            ttl,
        }
    }

    /// Checks if a client_id has been seen within the TTL window.
    /// If seen, returns Some(existing_item_id).
    /// If not seen, records the (client_id -> item_id) mapping and returns None.
    pub fn check_or_insert(&self, client_id: &str, item_id: &str) -> Option<String> {
        let mut map = self.cache.lock().unwrap();
        let now = Instant::now();

        // Prune expired entries
        map.retain(|_, (_, seen_at)| now.duration_since(*seen_at) < self.ttl);

        if let Some((existing_id, _)) = map.get(client_id) {
            return Some(existing_id.clone());
        }

        map.insert(client_id.to_string(), (item_id.to_string(), now));
        None
    }

    pub fn len(&self) -> usize {
        let map = self.cache.lock().unwrap();
        map.len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

impl Default for ClientIdDedup {
    fn default() -> Self {
        Self::new(Duration::from_secs(60))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dedup_records_and_detects_duplicate() {
        let dedup = ClientIdDedup::default();
        let client_id = "test-client-123";

        // First attempt: should return None (not a duplicate)
        let first = dedup.check_or_insert(client_id, "id-1");
        assert_eq!(first, None);

        // Immediate second attempt: should return Some("id-1")
        let second = dedup.check_or_insert(client_id, "id-2");
        assert_eq!(second, Some("id-1".to_string()));
    }

    #[test]
    fn test_dedup_expires_after_ttl() {
        let dedup = ClientIdDedup::new(Duration::from_millis(50));
        let client_id = "test-client-expiry";

        assert_eq!(dedup.check_or_insert(client_id, "id-1"), None);
        std::thread::sleep(Duration::from_millis(60));

        // After TTL expiry, should not be considered duplicate
        assert_eq!(dedup.check_or_insert(client_id, "id-2"), None);
    }
}

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub struct RateLimiter {
    pair_attempts: Mutex<HashMap<IpAddr, Vec<Instant>>>,
    failed_auths: Mutex<HashMap<IpAddr, (usize, Instant)>>,
}

impl RateLimiter {
    pub fn new() -> Self {
        Self {
            pair_attempts: Mutex::new(HashMap::new()),
            failed_auths: Mutex::new(HashMap::new()),
        }
    }

    pub fn is_private_ip(ip: &IpAddr) -> bool {
        match ip {
            IpAddr::V4(v4) => {
                v4.is_loopback()
                    || v4.is_private()
                    || v4.is_link_local()
            }
            IpAddr::V6(v6) => {
                v6.is_loopback()
                    || ((v6.segments()[0] & 0xffc0) == 0xfe80) // fe80::/10
                    || ((v6.segments()[0] & 0xfe00) == 0xfc00) // fc00::/7 (unique local)
            }
        }
    }

    pub fn check_pair_rate(&self, ip: IpAddr) -> bool {
        let mut map = self.pair_attempts.lock().unwrap();
        let now = Instant::now();
        let window = Duration::from_secs(60);

        let timestamps = map.entry(ip).or_default();
        timestamps.retain(|&t| now.duration_since(t) < window);

        if timestamps.len() >= 5 {
            false
        } else {
            timestamps.push(now);
            true
        }
    }

    pub fn record_auth_failure(&self, ip: IpAddr) {
        let mut map = self.failed_auths.lock().unwrap();
        let now = Instant::now();
        let entry = map.entry(ip).or_insert((0, now));
        entry.0 += 1;
        entry.1 = now;
    }

    pub fn is_auth_blocked(&self, ip: IpAddr) -> bool {
        let map = self.failed_auths.lock().unwrap();
        if let Some(&(fails, time)) = map.get(&ip) {
            if fails >= 5 && time.elapsed() < Duration::from_secs(60) {
                return true;
            }
        }
        false
    }
}

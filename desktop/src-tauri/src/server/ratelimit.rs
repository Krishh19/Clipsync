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
                    || ((v6.segments()[0] & 0xffc0) == 0xfe80) // fe80::/10 (link-local)
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
        // If previous block expired, reset count
        if entry.1.elapsed() >= Duration::from_secs(60) {
            entry.0 = 0;
        }
        entry.0 += 1;
        entry.1 = now;
    }

    pub fn record_auth_success(&self, ip: IpAddr) {
        let mut map = self.failed_auths.lock().unwrap();
        map.remove(&ip);
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

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{Ipv4Addr, Ipv6Addr};

    #[test]
    fn test_private_ip_detection() {
        // Private IPv4
        assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1))));
        assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(10, 0, 0, 5))));
        assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(172, 16, 0, 1))));
        assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(192, 168, 1, 50))));
        assert!(RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(169, 254, 1, 1))));

        // Public IPv4 (should be rejected)
        assert!(!RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(8, 8, 8, 8))));
        assert!(!RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(1, 1, 1, 1))));
        assert!(!RateLimiter::is_private_ip(&IpAddr::V4(Ipv4Addr::new(142, 250, 190, 46))));

        // IPv6 loopback
        assert!(RateLimiter::is_private_ip(&IpAddr::V6(Ipv6Addr::LOCALHOST)));
    }

    #[test]
    fn test_pair_rate_limiting() {
        let limiter = RateLimiter::new();
        let ip = IpAddr::V4(Ipv4Addr::new(192, 168, 1, 100));

        // 5 attempts allowed within 60s
        for _ in 0..5 {
            assert!(limiter.check_pair_rate(ip));
        }

        // 6th attempt rejected
        assert!(!limiter.check_pair_rate(ip));
    }

    #[test]
    fn test_auth_failure_blocking() {
        let limiter = RateLimiter::new();
        let ip = IpAddr::V4(Ipv4Addr::new(192, 168, 1, 101));

        for _ in 0..4 {
            limiter.record_auth_failure(ip);
            assert!(!limiter.is_auth_blocked(ip));
        }

        // 5th failure triggers block
        limiter.record_auth_failure(ip);
        assert!(limiter.is_auth_blocked(ip));

        // Success resets failure count
        limiter.record_auth_success(ip);
        assert!(!limiter.is_auth_blocked(ip));
    }
}

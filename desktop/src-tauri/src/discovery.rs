use anyhow::Result;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;
use std::sync::Mutex;
use tracing::info;

pub struct MdnsDiscovery {
    daemon: ServiceDaemon,
    current_service_fullname: Mutex<Option<String>>,
}

impl MdnsDiscovery {
    pub fn new() -> Result<Self> {
        let daemon = ServiceDaemon::new()?;
        Ok(Self {
            daemon,
            current_service_fullname: Mutex::new(None),
        })
    }

    pub fn build_service_info(
        device_id: &str,
        device_name: &str,
        port: u16,
        cert_fingerprint: &str,
    ) -> Result<ServiceInfo> {
        let service_type = "_clipsync._tcp.local.";
        let instance_name = format!("ClipSync-{}", &device_id[..device_id.len().min(8)]);

        let fp_prefix = if cert_fingerprint.len() >= 16 {
            &cert_fingerprint[..16]
        } else {
            cert_fingerprint
        };

        let mut properties = HashMap::new();
        properties.insert("id".to_string(), device_id.to_string());
        properties.insert("name".to_string(), device_name.to_string());
        properties.insert("v".to_string(), "1".to_string());
        properties.insert("fp".to_string(), fp_prefix.to_string());

        let host_name = format!("{}.local.", &instance_name);
        let my_service = ServiceInfo::new(
            service_type,
            &instance_name,
            &host_name,
            "",
            port,
            properties,
        )?;

        Ok(my_service)
    }

    pub fn register_service(
        &self,
        device_id: &str,
        device_name: &str,
        port: u16,
        cert_fingerprint: &str,
    ) -> Result<String> {
        // Unregister previous service if any
        self.unregister_service()?;

        let service = Self::build_service_info(device_id, device_name, port, cert_fingerprint)?;
        let fullname = service.get_fullname().to_string();

        self.daemon.register(service)?;
        info!("mDNS service registered as {} on port {}", fullname, port);

        let mut lock = self.current_service_fullname.lock().unwrap();
        *lock = Some(fullname.clone());

        Ok(fullname)
    }

    pub fn unregister_service(&self) -> Result<()> {
        let mut lock = self.current_service_fullname.lock().unwrap();
        if let Some(fullname) = lock.take() {
            let _ = self.daemon.unregister(&fullname);
            info!("mDNS service unregistered: {}", fullname);
        }
        Ok(())
    }

    pub fn update_service(
        &self,
        device_id: &str,
        device_name: &str,
        port: u16,
        cert_fingerprint: &str,
    ) -> Result<String> {
        self.register_service(device_id, device_name, port, cert_fingerprint)
    }

    pub fn get_registered_fullname(&self) -> Option<String> {
        let lock = self.current_service_fullname.lock().unwrap();
        lock.clone()
    }

    pub fn shutdown(&self) -> Result<()> {
        let _ = self.unregister_service();
        self.daemon.shutdown()?;
        Ok(())
    }
}

impl Drop for MdnsDiscovery {
    fn drop(&mut self) {
        let _ = self.shutdown();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_service_info_properties() {
        let device_id = "12345678-abcd-ef01-2345-6789abcdef01";
        let device_name = "My Test Laptop";
        let port = 47821;
        let fingerprint = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4";

        let info = MdnsDiscovery::build_service_info(device_id, device_name, port, fingerprint).unwrap();

        assert_eq!(info.get_type(), "_clipsync._tcp.local.");
        assert_eq!(info.get_port(), 47821);
        assert_eq!(info.get_property_val_str("id"), Some(device_id));
        assert_eq!(info.get_property_val_str("name"), Some(device_name));
        assert_eq!(info.get_property_val_str("v"), Some("1"));
        assert_eq!(info.get_property_val_str("fp"), Some("a1b2c3d4e5f60718")); // exactly 16 chars
    }

    #[test]
    fn test_service_lifecycle() {
        let discovery = MdnsDiscovery::new().unwrap();
        let device_id = "test-device-uuid";
        let device_name = "Test PC";

        // 1. Initial registration
        let fullname = discovery
            .register_service(device_id, device_name, 47821, "0123456789abcdef0123")
            .unwrap();
        assert_eq!(discovery.get_registered_fullname(), Some(fullname.clone()));

        // 2. Update service (e.g. port change)
        let updated_fullname = discovery
            .update_service(device_id, device_name, 47822, "0123456789abcdef0123")
            .unwrap();
        assert_eq!(discovery.get_registered_fullname(), Some(updated_fullname));

        // 3. Unregister service
        discovery.unregister_service().unwrap();
        assert_eq!(discovery.get_registered_fullname(), None);
    }
}

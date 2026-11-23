use anyhow::Result;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;
use tracing::info;

pub struct MdnsDiscovery {
    daemon: ServiceDaemon,
}

impl MdnsDiscovery {
    pub fn new() -> Result<Self> {
        let daemon = ServiceDaemon::new()?;
        Ok(Self { daemon })
    }

    pub fn register_service(
        &self,
        device_id: &str,
        device_name: &str,
        port: u16,
        cert_fingerprint: &str,
    ) -> Result<()> {
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

        self.daemon.register(my_service)?;
        info!("mDNS service registered as {} on port {}", instance_name, port);
        Ok(())
    }

    pub fn shutdown(&self) -> Result<()> {
        self.daemon.shutdown()?;
        Ok(())
    }
}

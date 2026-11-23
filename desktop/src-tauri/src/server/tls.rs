use anyhow::{Context, Result};
use axum_server::tls_rustls::RustlsConfig;
use rcgen::{CertificateParams, DistinguishedName, DnType, KeyPair, SanType};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use tracing::info;

pub struct TlsConfig {
    pub cert_path: PathBuf,
    pub key_path: PathBuf,
    pub fingerprint: String,
}

pub async fn create_rustls_config(cert_path: &Path, key_path: &Path) -> Result<RustlsConfig> {
    RustlsConfig::from_pem_file(cert_path, key_path)
        .await
        .map_err(|e| anyhow::anyhow!(e))
}

pub fn get_or_create_tls_certs(tls_dir: &Path, hostname: &str) -> Result<TlsConfig> {
    fs::create_dir_all(tls_dir).context("failed to create tls dir")?;
    let cert_path = tls_dir.join("cert.pem");
    let key_path = tls_dir.join("key.pem");

    if cert_path.exists() && key_path.exists() {
        let cert_pem = fs::read_to_string(&cert_path)?;
        let der = pem_to_der(&cert_pem)?;
        let fingerprint = compute_fingerprint(&der);
        return Ok(TlsConfig {
            cert_path,
            key_path,
            fingerprint,
        });
    }

    info!("Generating new self-signed TLS certificate with rcgen");
    let mut params = CertificateParams::default();
    let mut dn = DistinguishedName::new();
    dn.push(DnType::CommonName, format!("ClipSync ({hostname})"));
    params.distinguished_name = dn;

    params.subject_alt_names = vec![
        SanType::DnsName(hostname.to_string().try_into()?),
        SanType::DnsName("localhost".to_string().try_into()?),
        SanType::IpAddress(std::net::IpAddr::V4(std::net::Ipv4Addr::new(127, 0, 0, 1))),
    ];

    let key_pair = KeyPair::generate_for(&rcgen::PKCS_ECDSA_P256_SHA256)?;
    let cert = params.self_signed(&key_pair)?;

    let cert_pem = cert.pem();
    let key_pem = key_pair.serialize_pem();

    fs::write(&cert_path, &cert_pem)?;
    fs::write(&key_path, &key_pem)?;

    let der = cert.der();
    let fingerprint = compute_fingerprint(der.as_ref());

    Ok(TlsConfig {
        cert_path,
        key_path,
        fingerprint,
    })
}

pub fn compute_fingerprint(der_bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(der_bytes);
    let hash = hasher.finalize();
    hash.iter().map(|b| format!("{b:02x}")).collect()
}

fn pem_to_der(pem: &str) -> Result<Vec<u8>> {
    for p in rustls_pemfile::certs(&mut pem.as_bytes()) {
        let cert = p?;
        return Ok(cert.to_vec());
    }
    anyhow::bail!("no certificate found in pem")
}

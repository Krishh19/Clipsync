use clipsync_desktop_lib::discovery::MdnsDiscovery;

#[test]
fn test_mdns_service_info_builder_properties() {
    let device_id = "a1b2c3d4-e5f6-7890-abcd-ef0123456789";
    let device_name = "Alice's Surface Laptop";
    let port = 47821;
    let cert_fingerprint = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08";

    let service = MdnsDiscovery::build_service_info(
        device_id,
        device_name,
        port,
        cert_fingerprint,
    )
    .expect("Failed to build service info");

    // 1. Service Type and Name
    assert_eq!(service.get_type(), "_clipsync._tcp.local.");
    assert!(service.get_fullname().contains("ClipSync-a1b2c3d4"));
    assert_eq!(service.get_port(), 47821);

    // 2. TXT Properties
    assert_eq!(service.get_property_val_str("id"), Some(device_id));
    assert_eq!(service.get_property_val_str("name"), Some(device_name));
    assert_eq!(service.get_property_val_str("v"), Some("1"));

    // 3. Fingerprint: First 16 hex characters
    let expected_fp = &cert_fingerprint[..16];
    assert_eq!(service.get_property_val_str("fp"), Some(expected_fp));
    assert_eq!(expected_fp.len(), 16);
}

#[test]
fn test_mdns_fingerprint_short_fallback() {
    let device_id = "dev-1234";
    let device_name = "Short FP PC";
    let short_fp = "abc12";

    let service = MdnsDiscovery::build_service_info(device_id, device_name, 47825, short_fp)
        .expect("Failed with short fp");

    assert_eq!(service.get_property_val_str("fp"), Some("abc12"));
}

#[test]
fn test_mdns_registration_and_update_lifecycle() {
    let discovery = MdnsDiscovery::new().expect("Failed to create MdnsDiscovery");
    let device_id = "11223344-5566-7788-99aa-bbccddeeff00";
    let device_name = "Office PC";
    let fp = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";

    // 1. Initially no registered service
    assert_eq!(discovery.get_registered_fullname(), None);

    // 2. Register service
    let fullname1 = discovery
        .register_service(device_id, device_name, 47821, fp)
        .expect("Registration failed");
    assert!(fullname1.contains("ClipSync-11223344"));
    assert_eq!(discovery.get_registered_fullname(), Some(fullname1.clone()));

    // 3. Update service (e.g. port dynamically assigned to 47822)
    let fullname2 = discovery
        .update_service(device_id, device_name, 47822, fp)
        .expect("Update failed");
    assert_eq!(fullname1, fullname2);
    assert_eq!(discovery.get_registered_fullname(), Some(fullname2));

    // 4. Unregister service
    discovery.unregister_service().expect("Unregistration failed");
    assert_eq!(discovery.get_registered_fullname(), None);

    // 5. Re-register service
    let fullname3 = discovery
        .register_service(device_id, "Renamed Office PC", 47823, fp)
        .expect("Re-registration failed");
    assert_eq!(discovery.get_registered_fullname(), Some(fullname3));

    // 6. Graceful shutdown
    discovery.shutdown().expect("Shutdown failed");
    assert_eq!(discovery.get_registered_fullname(), None);
}

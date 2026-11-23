use clipsync_desktop_lib::commands::get_local_lan_ip;
use clipsync_desktop_lib::config::AppConfig;
use clipsync_desktop_lib::storage::{Database, DeviceRow, ItemRow};
use std::net::Ipv4Addr;
use std::str::FromStr;

#[test]
fn test_get_local_lan_ip_returns_valid_ip() {
    let ip_str = get_local_lan_ip();
    assert!(!ip_str.is_empty(), "LAN IP should not be empty");
    let parsed = Ipv4Addr::from_str(&ip_str);
    assert!(parsed.is_ok(), "LAN IP '{}' must be a valid IPv4 address", ip_str);
}

#[test]
fn test_history_retention_days_and_count() {
    let db = Database::new_in_memory().expect("failed to init db");
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    // Insert 5 old items (40 days old)
    for i in 1..=5 {
        let item = ItemRow {
            id: format!("old-item-{}", i),
            direction: "in".to_string(),
            kind: "text".to_string(),
            device_id: Some("dev-1".to_string()),
            text: Some(format!("Old message {}", i)),
            file_path: None,
            file_name: None,
            mime: Some("text/plain".to_string()),
            size: None,
            created_at: now - (40 * 86400) + i,
        };
        db.insert_item(&item).expect("insert old item");
    }

    // Insert 10 recent items (1-10 hours old)
    for i in 1..=10 {
        let item = ItemRow {
            id: format!("recent-item-{}", i),
            direction: "in".to_string(),
            kind: "text".to_string(),
            device_id: Some("dev-1".to_string()),
            text: Some(format!("Recent message {}", i)),
            file_path: None,
            file_name: None,
            mime: Some("text/plain".to_string()),
            size: None,
            created_at: now - ((11 - i) * 3600),
        };
        db.insert_item(&item).expect("insert recent item");
    }

    assert_eq!(db.list_items(100).unwrap().len(), 15);

    // Clean retention with 30 days retention, 50 max items
    // Old items (>30 days) should be pruned
    let deleted_old = db.clean_retention(30, 50).expect("clean retention days");
    assert_eq!(deleted_old, 5, "5 old items should have been deleted by age");

    let remaining = db.list_items(100).unwrap();
    assert_eq!(remaining.len(), 10, "10 recent items should remain");
    for item in &remaining {
        assert!(item.id.starts_with("recent-item-"));
    }

    // Now clean retention with max_items = 4
    db.clean_retention(30, 4).expect("clean retention max items");
    let remaining_after_limit = db.list_items(100).unwrap();
    assert_eq!(remaining_after_limit.len(), 4, "Only 4 items should remain");
    // Newest items should be kept (recent-item-10, 9, 8, 7)
    assert_eq!(remaining_after_limit[0].id, "recent-item-10");
    assert_eq!(remaining_after_limit[1].id, "recent-item-9");
    assert_eq!(remaining_after_limit[2].id, "recent-item-8");
    assert_eq!(remaining_after_limit[3].id, "recent-item-7");
}

#[test]
fn test_database_crud_operations() {
    let db = Database::new_in_memory().expect("failed to init db");

    let item = ItemRow {
        id: "item-crud-1".to_string(),
        direction: "out".to_string(),
        kind: "file".to_string(),
        device_id: None,
        text: None,
        file_path: Some("C:\\test\\file.png".to_string()),
        file_name: Some("file.png".to_string()),
        mime: Some("image/png".to_string()),
        size: Some(1024),
        created_at: 1000,
    };

    db.insert_item(&item).expect("insert item");
    let items = db.list_items(10).unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].id, "item-crud-1");
    assert_eq!(items[0].file_name.as_deref(), Some("file.png"));

    // Delete single item
    db.delete_item("item-crud-1").expect("delete item");
    assert_eq!(db.list_items(10).unwrap().len(), 0);

    // Clear all items
    db.insert_item(&item).expect("reinsert");
    db.clear_items().expect("clear all");
    assert_eq!(db.list_items(10).unwrap().len(), 0);
}

#[test]
fn test_device_revocation_and_query() {
    let db = Database::new_in_memory().expect("failed to init db");

    let dev = DeviceRow {
        id: "dev-phone-1".to_string(),
        name: "Pixel 9".to_string(),
        platform: "android".to_string(),
        secret_hash: "hash_abc_123".to_string(),
        created_at: 1000,
        last_seen: 1200,
        revoked: false,
    };

    db.insert_device(&dev).expect("insert device");
    let found = db.get_device_by_secret_hash("hash_abc_123").unwrap();
    assert!(found.is_some());
    assert_eq!(found.unwrap().name, "Pixel 9");

    // Revoke
    db.revoke_device("dev-phone-1").expect("revoke device");
    let after_revoke = db.get_device_by_secret_hash("hash_abc_123").unwrap();
    assert!(after_revoke.is_none(), "Revoked device secret should not match");

    let all_devs = db.list_devices().unwrap();
    assert_eq!(all_devs.len(), 1);
    assert!(all_devs[0].revoked);
}

#[test]
fn test_settings_serialization_and_defaults() {
    let mut config = AppConfig::default();
    assert_eq!(config.port, 47821);
    assert!(config.copy_text_links);
    assert!(config.copy_images);
    assert!(!config.copy_videos_as_files);
    assert!(config.notifications_on_receive);
    assert!(!config.auto_send_clipboard);
    assert_eq!(config.send_hotkey, "Ctrl+Shift+S");
    assert_eq!(config.retention_days, 30);
    assert_eq!(config.retention_max_items, 500);

    // Modify settings
    config.port = 48000;
    config.device_name = "Custom-PC".to_string();
    config.start_with_windows = true;
    config.retention_days = 60;
    config.retention_max_items = 1000;

    let json = serde_json::to_string_pretty(&config).expect("serialize config");
    let deserialized: AppConfig = serde_json::from_str(&json).expect("deserialize config");

    assert_eq!(deserialized.port, 48000);
    assert_eq!(deserialized.device_name, "Custom-PC");
    assert!(deserialized.start_with_windows);
    assert_eq!(deserialized.retention_days, 60);
    assert_eq!(deserialized.retention_max_items, 1000);
}

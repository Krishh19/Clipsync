use anyhow::Result;
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceRow {
    pub id: String,
    pub name: String,
    pub platform: String,
    pub secret_hash: String,
    pub created_at: i64,
    pub last_seen: i64,
    pub revoked: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemRow {
    pub id: String,
    pub direction: String,
    pub kind: String,
    pub device_id: Option<String>,
    pub text: Option<String>,
    pub file_path: Option<String>,
    pub file_name: Option<String>,
    pub mime: Option<String>,
    pub size: Option<i64>,
    pub created_at: i64,
}

#[derive(Clone)]
pub struct Database {
    conn: Arc<Mutex<Connection>>,
}

impl Database {
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
        };
        db.init()?;
        Ok(db)
    }

    pub fn new_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
        };
        db.init()?;
        Ok(db)
    }

    pub fn init(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS devices (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                platform TEXT NOT NULL,
                secret_hash TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                last_seen INTEGER NOT NULL,
                revoked INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY,
                direction TEXT CHECK(direction IN ('in','out')) NOT NULL,
                kind TEXT CHECK(kind IN ('text','link','image','video','file')) NOT NULL,
                device_id TEXT,
                text TEXT,
                file_path TEXT,
                file_name TEXT,
                mime TEXT,
                size INTEGER,
                created_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);
            "#,
        )?;
        Ok(())
    }

    pub fn insert_device(&self, dev: &DeviceRow) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            r#"INSERT OR REPLACE INTO devices (id, name, platform, secret_hash, created_at, last_seen, revoked)
               VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"#,
            params![
                dev.id,
                dev.name,
                dev.platform,
                dev.secret_hash,
                dev.created_at,
                dev.last_seen,
                if dev.revoked { 1 } else { 0 }
            ],
        )?;
        Ok(())
    }

    pub fn list_devices(&self) -> Result<Vec<DeviceRow>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, name, platform, secret_hash, created_at, last_seen, revoked FROM devices ORDER BY created_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            let revoked_int: i32 = row.get(6)?;
            Ok(DeviceRow {
                id: row.get(0)?,
                name: row.get(1)?,
                platform: row.get(2)?,
                secret_hash: row.get(3)?,
                created_at: row.get(4)?,
                last_seen: row.get(5)?,
                revoked: revoked_int != 0,
            })
        })?;

        let mut devices = Vec::new();
        for r in rows {
            devices.push(r?);
        }
        Ok(devices)
    }

    pub fn get_device_by_secret_hash(&self, hash: &str) -> Result<Option<DeviceRow>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, name, platform, secret_hash, created_at, last_seen, revoked FROM devices WHERE secret_hash = ?1 AND revoked = 0",
        )?;
        let mut rows = stmt.query_map([hash], |row| {
            let revoked_int: i32 = row.get(6)?;
            Ok(DeviceRow {
                id: row.get(0)?,
                name: row.get(1)?,
                platform: row.get(2)?,
                secret_hash: row.get(3)?,
                created_at: row.get(4)?,
                last_seen: row.get(5)?,
                revoked: revoked_int != 0,
            })
        })?;

        if let Some(r) = rows.next() {
            Ok(Some(r?))
        } else {
            Ok(None)
        }
    }

    pub fn revoke_device(&self, device_id: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute("UPDATE devices SET revoked = 1 WHERE id = ?1", params![device_id])?;
        Ok(())
    }

    pub fn update_last_seen(&self, device_id: &str, ts: i64) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute("UPDATE devices SET last_seen = ?1 WHERE id = ?2", params![ts, device_id])?;
        Ok(())
    }

    pub fn insert_item(&self, item: &ItemRow) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            r#"INSERT INTO items (id, direction, kind, device_id, text, file_path, file_name, mime, size, created_at)
               VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)"#,
            params![
                item.id,
                item.direction,
                item.kind,
                item.device_id,
                item.text,
                item.file_path,
                item.file_name,
                item.mime,
                item.size,
                item.created_at
            ],
        )?;
        Ok(())
    }

    pub fn list_items(&self, limit: u32) -> Result<Vec<ItemRow>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            r#"SELECT id, direction, kind, device_id, text, file_path, file_name, mime, size, created_at
               FROM items ORDER BY created_at DESC LIMIT ?1"#,
        )?;
        let rows = stmt.query_map([limit], |row| {
            Ok(ItemRow {
                id: row.get(0)?,
                direction: row.get(1)?,
                kind: row.get(2)?,
                device_id: row.get(3)?,
                text: row.get(4)?,
                file_path: row.get(5)?,
                file_name: row.get(6)?,
                mime: row.get(7)?,
                size: row.get(8)?,
                created_at: row.get(9)?,
            })
        })?;

        let mut items = Vec::new();
        for r in rows {
            items.push(r?);
        }
        Ok(items)
    }

    pub fn delete_item(&self, id: &str) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM items WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn clear_items(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM items", [])?;
        Ok(())
    }

    pub fn clean_retention(&self, days: u32, max_items: u32) -> Result<usize> {
        let conn = self.conn.lock().unwrap();
        let cutoff = chrono_now_seconds() - (days as i64 * 86400);
        let deleted_old = conn.execute("DELETE FROM items WHERE created_at < ?1", params![cutoff])?;

        // Keep at most max_items
        conn.execute(
            r#"DELETE FROM items WHERE id NOT IN (
                SELECT id FROM items ORDER BY created_at DESC LIMIT ?1
            )"#,
            params![max_items],
        )?;

        Ok(deleted_old)
    }
}

fn chrono_now_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

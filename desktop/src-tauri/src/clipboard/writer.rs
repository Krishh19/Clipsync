use arboard::{Clipboard, ImageData};
use sha2::{Digest, Sha256};
use std::borrow::Cow;
use std::path::Path;
use std::sync::{Arc, Mutex};
use tracing::{error, info};

pub struct ClipboardWriter {
    last_written: Arc<Mutex<Option<Vec<u8>>>>,
}

impl ClipboardWriter {
    pub fn new(last_written: Arc<Mutex<Option<Vec<u8>>>>) -> Self {
        Self { last_written }
    }

    pub fn write_text(&self, text: &str) -> bool {
        let mut hasher = Sha256::new();
        hasher.update(text.as_bytes());
        let hash = hasher.finalize().to_vec();

        {
            let mut last = self.last_written.lock().unwrap();
            *last = Some(hash);
        }

        match Clipboard::new() {
            Ok(mut cb) => {
                if let Err(e) = cb.set_text(text) {
                    error!("Failed to write text to clipboard: {}", e);
                    false
                } else {
                    info!("Successfully wrote text to clipboard");
                    true
                }
            }
            Err(e) => {
                error!("Failed to open clipboard: {}", e);
                false
            }
        }
    }

    pub fn write_image(&self, image_path: &Path) -> bool {
        let img = match image::open(image_path) {
            Ok(i) => i.to_rgba8(),
            Err(e) => {
                error!("Failed to decode image from {}: {}", image_path.display(), e);
                return false;
            }
        };

        let (width, height) = img.dimensions();
        let raw = img.into_raw();

        let mut hasher = Sha256::new();
        hasher.update(&raw);
        let hash = hasher.finalize().to_vec();

        {
            let mut last = self.last_written.lock().unwrap();
            *last = Some(hash);
        }

        let image_data = ImageData {
            width: width as usize,
            height: height as usize,
            bytes: Cow::Owned(raw),
        };

        match Clipboard::new() {
            Ok(mut cb) => {
                if let Err(e) = cb.set_image(image_data) {
                    error!("Failed to write image to clipboard: {}", e);
                    false
                } else {
                    info!("Successfully wrote image to clipboard");
                    true
                }
            }
            Err(e) => {
                error!("Failed to open clipboard: {}", e);
                false
            }
        }
    }

    pub fn write_file_list(&self, file_paths: &[&str]) -> bool {
        #[cfg(target_os = "windows")]
        {
            use clipboard_win::raw::set_file_list;
            let mut combined = String::new();
            for p in file_paths {
                combined.push_str(p);
                combined.push(';');
            }

            let mut hasher = Sha256::new();
            hasher.update(combined.as_bytes());
            let hash = hasher.finalize().to_vec();

            {
                let mut last = self.last_written.lock().unwrap();
                *last = Some(hash);
            }

            if let Err(e) = set_file_list(file_paths) {
                error!("Failed to write file list to clipboard: {:?}", e);
                return false;
            }
            info!("Successfully wrote file list to clipboard");
            true
        }
        #[cfg(not(target_os = "windows"))]
        {
            let _ = file_paths;
            false
        }
    }
}

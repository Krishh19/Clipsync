use arboard::Clipboard;
use sha2::{Digest, Sha256};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use tracing::{debug, error, info};

pub struct ClipboardWatcher {
    running: Arc<AtomicBool>,
}

impl ClipboardWatcher {
    pub fn new() -> Self {
        Self {
            running: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn start<F>(&self, last_written: Arc<Mutex<Option<Vec<u8>>>>, on_text_changed: F)
    where
        F: Fn(String) + Send + Sync + 'static,
    {
        if self.running.swap(true, Ordering::SeqCst) {
            return;
        }

        let running = self.running.clone();

        thread::spawn(move || {
            info!("Clipboard watcher thread started");
            let mut last_seq = get_clipboard_sequence();

            while running.load(Ordering::SeqCst) {
                thread::sleep(Duration::from_millis(250));

                let current_seq = get_clipboard_sequence();
                if current_seq == last_seq {
                    continue;
                }
                last_seq = current_seq;

                #[cfg(target_os = "windows")]
                if is_excluded_by_password_manager() {
                    debug!("Clipboard change ignored: password manager format present");
                    continue;
                }

                if let Ok(mut cb) = Clipboard::new() {
                    if let Ok(text) = cb.get_text() {
                        let mut hasher = Sha256::new();
                        hasher.update(text.as_bytes());
                        let hash = hasher.finalize().to_vec();

                        let is_echo = {
                            let last = last_written.lock().unwrap();
                            last.as_ref() == Some(&hash)
                        };

                        if is_echo {
                            debug!("Clipboard change ignored: matches last_written echo");
                            continue;
                        }

                        on_text_changed(text);
                    }
                } else {
                    error!("Clipboard watcher failed to access clipboard");
                }
            }
            info!("Clipboard watcher thread stopped");
        });
    }

    pub fn stop(&self) {
        self.running.store(false, Ordering::SeqCst);
    }
}

fn get_clipboard_sequence() -> u32 {
    #[cfg(target_os = "windows")]
    {
        use clipboard_win::raw::seq_num;
        seq_num().map(|n| n.get()).unwrap_or(0)
    }
    #[cfg(not(target_os = "windows"))]
    {
        0
    }
}

#[cfg(target_os = "windows")]
fn is_excluded_by_password_manager() -> bool {
    use clipboard_win::raw::{is_format_avail, register_format};
    // Registered format: ExcludeClipboardContentFromMonitorProcessing
    if let Some(fmt) = register_format("ExcludeClipboardContentFromMonitorProcessing") {
        is_format_avail(fmt.get())
    } else {
        false
    }
}

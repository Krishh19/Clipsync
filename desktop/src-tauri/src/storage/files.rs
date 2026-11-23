use std::path::{Path, PathBuf};
use std::fs;
use std::io::Result as IoResult;
use super::sanitize::sanitize_filename;

pub struct FileManager {
    pub base_dir: PathBuf,
}

impl FileManager {
    pub fn new<P: AsRef<Path>>(base_dir: P) -> Self {
        Self {
            base_dir: base_dir.as_ref().to_path_buf(),
        }
    }

    pub fn ensure_dirs(&self) -> IoResult<()> {
        fs::create_dir_all(&self.base_dir)?;
        fs::create_dir_all(self.partial_dir())?;
        Ok(())
    }

    pub fn partial_dir(&self) -> PathBuf {
        self.base_dir.join(".partial")
    }

    pub fn get_unique_path(&self, original_name: &str) -> PathBuf {
        let clean_name = sanitize_filename(original_name);
        let target_path = self.base_dir.join(&clean_name);

        if !target_path.exists() {
            return target_path;
        }

        let stem = Path::new(&clean_name)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("file");
        let ext = Path::new(&clean_name)
            .extension()
            .and_then(|s| s.to_str());

        let mut index = 1;
        loop {
            let candidate_name = match ext {
                Some(e) => format!("{stem} ({index}).{e}"),
                None => format!("{stem} ({index})"),
            };
            let candidate_path = self.base_dir.join(candidate_name);
            if !candidate_path.exists() {
                return candidate_path;
            }
            index += 1;
        }
    }
}

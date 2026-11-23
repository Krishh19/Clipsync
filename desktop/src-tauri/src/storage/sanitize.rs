const RESERVED_NAMES: &[&str] = &[
    "CON", "PRN", "AUX", "NUL",
    "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
    "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

pub fn sanitize_filename(filename: &str) -> String {
    // 1. Remove path components, keeping only the file stem and extension
    let name = filename
        .replace('\\', "/")
        .split('/')
        .last()
        .unwrap_or("file")
        .to_string();

    // 2. Filter out invalid/control characters: < > : " / \ | ? * and ASCII control (0..32)
    let filtered: String = name
        .chars()
        .filter(|&c| {
            !c.is_control()
                && c != '<'
                && c != '>'
                && c != ':'
                && c != '"'
                && c != '/'
                && c != '\\'
                && c != '|'
                && c != '?'
                && c != '*'
        })
        .collect();

    // 3. Trim trailing dots and spaces (Windows restriction)
    let trimmed = filtered.trim_end_matches(['.', ' ']).trim();
    let effective = if trimmed.is_empty() { "file" } else { trimmed };

    // 4. Check for Windows reserved names
    let stem = effective.split('.').next().unwrap_or(effective);
    let is_reserved = RESERVED_NAMES.iter().any(|&r| stem.eq_ignore_ascii_case(r));
    let safe_base = if is_reserved {
        format!("_{effective}")
    } else {
        effective.to_string()
    };

    // 5. Cap at 120 chars, preserving extension if present
    if safe_base.chars().count() > 120 {
        if let Some(dot_pos) = safe_base.rfind('.') {
            let ext = &safe_base[dot_pos..];
            let stem = &safe_base[..dot_pos];
            let max_stem_len = 120_usize.saturating_sub(ext.chars().count());
            let truncated_stem: String = stem.chars().take(max_stem_len).collect();
            format!("{truncated_stem}{ext}")
        } else {
            safe_base.chars().take(120).collect()
        }
    } else {
        safe_base
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_reserved_name() {
        assert_eq!(sanitize_filename("CON.txt"), "_CON.txt");
        assert_eq!(sanitize_filename("nul"), "_nul");
    }

    #[test]
    fn test_sanitize_traversal() {
        assert_eq!(sanitize_filename("../../etc/passwd"), "passwd");
        assert_eq!(sanitize_filename(r"C:\Windows\System32\cmd.exe"), "cmd.exe");
    }

    #[test]
    fn test_sanitize_trailing_dots() {
        assert_eq!(sanitize_filename("test..."), "test");
        assert_eq!(sanitize_filename("test.txt."), "test.txt");
    }
}

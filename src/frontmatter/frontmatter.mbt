// Frontmatter Utilities
// Extract and work with YAML frontmatter from markdown documents

///|
/// Look up a frontmatter entry value by key
fn find_entry_value(entries : Array[(String, String)], key : String) -> String? {
  for entry in entries {
    let (k, v) = entry
    if k == key {
      return Some(v)
    }
  }
  None
}

///|
/// Normalize a comma-separated list by trimming whitespace and dropping empties
fn parse_list_value(value : String) -> Array[String] {
  let items : Array[String] = []
  for part in value.split(",") {
    let trimmed = part.to_string().trim(chars=" \t\n\r").to_string()
    if !trimmed.is_empty() {
      items.push(trimmed)
    }
  }
  items
}

///|
/// Get a string value from frontmatter entries
pub fn get_string(fm : @md.Frontmatter, key : String) -> String? {
  find_entry_value(fm.entries, key)
}

///|
/// Get a boolean value from frontmatter entries
/// Returns true if value is "true", false if "false", None otherwise
pub fn get_bool(fm : @md.Frontmatter, key : String) -> Bool? {
  match get_string(fm, key) {
    Some("true") => Some(true)
    Some("false") => Some(false)
    _ => None
  }
}

///|
/// Get an integer value from frontmatter entries
pub fn get_int(fm : @md.Frontmatter, key : String) -> Int? {
  match get_string(fm, key) {
    Some(s) => Some(@string.parse_int(s)) catch { _ => None }
    None => None
  }
}

///|
/// Get a comma-separated list from frontmatter entries
pub fn get_list(fm : @md.Frontmatter, key : String) -> Array[String] {
  match get_string(fm, key) {
    Some(s) => parse_list_value(s)
    None => []
  }
}

///|
/// Check if a key exists in frontmatter
pub fn has_key(fm : @md.Frontmatter, key : String) -> Bool {
  find_entry_value(fm.entries, key) is Some(_)
}

///|
/// Get all keys from frontmatter
pub fn keys(fm : @md.Frontmatter) -> Array[String] {
  fm.entries.map(fn(entry) {
    let (k, _) = entry
    k
  })
}

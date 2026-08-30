///|
/// GFM tagfilter support for raw HTML output.
let gfm_disallowed_html_tags : Array[String] = [
  "iframe", "noembed", "noframes", "plaintext", "script", "style", "title", "textarea",
  "xmp",
]

///|
/// Return the next `<` that starts a GFM-disallowed opening or closing tag.
fn find_gfm_disallowed_tag(html : String, start : Int) -> Int? {
  let len = html.length()
  let mut search_from = start
  while search_from < len {
    match find_exact_from(html, search_from, "<") {
      None => return None
      Some(candidate) => {
        let mut name_start = candidate + 1
        if name_start < len && html.unsafe_get(name_start) == '/' {
          name_start = name_start + 1
        }
        for tag in gfm_disallowed_html_tags {
          let name_end = name_start + tag.length()
          if name_end <= len &&
            html[name_start:name_end].equal_ignore_ascii_case(tag[:]) &&
            name_end < len {
            let boundary = html.unsafe_get(name_end)
            if is_html_space(boundary) || boundary == '/' || boundary == '>' {
              return Some(candidate)
            }
          }
        }
        search_from = candidate + 1
      }
    }
  }
  None
}

///|
/// Escape only the `<` of tags prohibited by GFM's tagfilter extension.
fn gfm_tagfilter(html : String) -> String {
  match find_gfm_disallowed_tag(html, 0) {
    None => html
    Some(first) => {
      let buf = StringBuilder()
      let mut cursor = 0
      let mut match_start = first
      while true {
        buf.write_string(html.unsafe_substring(start=cursor, end=match_start))
        buf.write_string("&lt;")
        cursor = match_start + 1
        match find_gfm_disallowed_tag(html, cursor) {
          Some(next) => match_start = next
          None => break
        }
      }
      buf.write_string(html.unsafe_substring(start=cursor, end=html.length()))
      buf.to_string()
    }
  }
}

///| HTML renderer compatibility tests

///| Compares output with remark-html

///|
/// Normalize XHTML-style void tags (`<hr />`) to their HTML5 spelling so that
/// this serialization difference alone never fails the comparison.
fn normalize_void_tags(s : String) -> String {
  let len = s.length()
  let buf = StringBuilder()
  let mut i = 0
  let mut last = 0
  while i + 2 < len {
    if s.unsafe_get(i) == ' ' &&
      s.unsafe_get(i + 1) == '/' &&
      s.unsafe_get(i + 2) == '>' {
      buf.write_string(s.unsafe_substring(start=last, end=i))
      buf.write_char('>')
      i = i + 3
      last = i
    } else {
      i = i + 1
    }
  }
  if last == 0 {
    return s
  }
  buf.write_string(s.unsafe_substring(start=last, end=len))
  buf.to_string()
}

///|
/// Test helper: compare our HTML output with remark-html output
pub fn assert_html_compat(input : String, name : String) -> Unit {
  let our_output = @markdown.md_to_html(input)
  let remark_output = remark_html(input)

  // Normalize trailing whitespace for comparison
  let our_normalized = normalize_void_tags(our_output).trim_end(chars=" \n\t")
  let remark_normalized = normalize_void_tags(remark_output).trim_end(chars=" \n\t")
  if our_normalized != remark_normalized {
    println("=== HTML Test: \{name} ===")
    println("=== Input ===")
    println(input)
    println("=== Our output ===")
    println(our_normalized)
    println("=== Remark-html output ===")
    println(remark_normalized)
    panic()
  }
}

///|
/// Test helper with strict mode
pub fn assert_html_compat_strict(input : String, name : String) -> Unit {
  let our_output = @markdown.md_to_html_strict(input)
  let remark_output = remark_html(input)
  let our_normalized = normalize_void_tags(our_output).trim_end(chars=" \n\t")
  let remark_normalized = normalize_void_tags(remark_output).trim_end(chars=" \n\t")
  if our_normalized != remark_normalized {
    println("=== HTML Test (strict): \{name} ===")
    println("=== Input ===")
    println(input)
    println("=== Our output ===")
    println(our_normalized)
    println("=== Remark-html output ===")
    println(remark_normalized)
    panic()
  }
}

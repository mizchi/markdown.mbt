///| MDX Attribute Parser
///|
///| Parses JSX/Web Component attributes like:
///| - name="value"
///| - name='value'
///| - name={expression}
///| - name (boolean)

// =============================================================================
// Attribute Parser
// =============================================================================

///|
/// Parse attributes from a string starting after the tag name
/// Input: ` prop="value" count={42} disabled>`
/// Returns: array of attributes and position after last attribute
pub fn parse_attributes(input : String, start : Int) -> (Array[MdxAttribute], Int) {
  let chars = input.to_array()
  let len = chars.length()
  let mut pos = start
  let attrs : Array[MdxAttribute] = []

  while pos < len {
    // Skip whitespace
    while pos < len && is_attr_whitespace(chars[pos]) {
      pos += 1
    }

    if pos >= len {
      break
    }

    let c = chars[pos]

    // Check for end of tag
    if c == '>' || c == '/' {
      break
    }

    // Parse attribute name
    let name_start = pos
    while pos < len && is_attr_name_char(chars[pos]) {
      pos += 1
    }

    if pos == name_start {
      // No valid attribute name, skip this character
      pos += 1
      continue
    }

    let name = attr_substring(chars, name_start, pos)

    // Skip whitespace
    while pos < len && is_attr_whitespace(chars[pos]) {
      pos += 1
    }

    // Check if there's a value
    if pos < len && chars[pos] == '=' {
      pos += 1  // Skip =

      // Skip whitespace
      while pos < len && is_attr_whitespace(chars[pos]) {
        pos += 1
      }

      if pos >= len {
        // Boolean attribute (no value after =)
        attrs.push(MdxAttribute::boolean(name))
        continue
      }

      let value_char = chars[pos]

      if value_char == '"' || value_char == '\'' {
        // String value
        let quote = value_char
        pos += 1  // Skip opening quote
        let value_start = pos

        while pos < len && chars[pos] != quote {
          if chars[pos] == '\\' && pos + 1 < len {
            pos += 2  // Skip escape
          } else {
            pos += 1
          }
        }

        let value = attr_substring(chars, value_start, pos)

        if pos < len {
          pos += 1  // Skip closing quote
        }

        attrs.push(MdxAttribute::string(name, value))
      } else if value_char == '{' {
        // Expression value
        pos += 1  // Skip {
        let expr_start = pos
        let mut depth = 1

        while pos < len && depth > 0 {
          let ec = chars[pos]
          if ec == '{' {
            depth += 1
          } else if ec == '}' {
            depth -= 1
          } else if ec == '"' || ec == '\'' || ec == '`' {
            // Skip string content
            let quote = ec
            pos += 1
            while pos < len && chars[pos] != quote {
              if chars[pos] == '\\' && pos + 1 < len {
                pos += 2
              } else {
                pos += 1
              }
            }
          }
          if depth > 0 {
            pos += 1
          }
        }

        let expr = attr_substring(chars, expr_start, pos)

        if pos < len {
          pos += 1  // Skip closing }
        }

        attrs.push(MdxAttribute::expression(name, expr))
      } else {
        // Unquoted value (not standard JSX but handle it)
        let value_start = pos
        while pos < len && not(is_whitespace(chars[pos])) && chars[pos] != '>' && chars[pos] != '/' {
          pos += 1
        }
        let value = attr_substring(chars, value_start, pos)
        attrs.push(MdxAttribute::string(name, value))
      }
    } else {
      // Boolean attribute (no =)
      attrs.push(MdxAttribute::boolean(name))
    }
  }

  (attrs, pos)
}

///|
/// Parse a single attribute from input
pub fn parse_single_attribute(input : String) -> MdxAttribute? {
  let (attrs, _) = parse_attributes(input, 0)
  if attrs.length() > 0 {
    Some(attrs[0])
  } else {
    None
  }
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
fn is_attr_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn is_attr_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '-' || c == '_' || c == ':' || c == '.'
}

///|
fn attr_substring(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

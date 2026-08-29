///|
/// ANSI escape codes for terminal styling

// Reset
pub let reset : String = "\u001b[0m"

// Text styles

///|
pub let bold : String = "\u001b[1m"

///|
pub let dim : String = "\u001b[2m"

///|
pub let italic : String = "\u001b[3m"

///|
pub let underline : String = "\u001b[4m"

///|
pub let strikethrough : String = "\u001b[9m"

// Foreground colors

///|
pub let black : String = "\u001b[30m"

///|
pub let red : String = "\u001b[31m"

///|
pub let green : String = "\u001b[32m"

///|
pub let yellow : String = "\u001b[33m"

///|
pub let blue : String = "\u001b[34m"

///|
pub let magenta : String = "\u001b[35m"

///|
pub let cyan : String = "\u001b[36m"

///|
pub let white : String = "\u001b[37m"

// Bright foreground colors

///|
pub let bright_black : String = "\u001b[90m"

///|
pub let bright_red : String = "\u001b[91m"

///|
pub let bright_green : String = "\u001b[92m"

///|
pub let bright_yellow : String = "\u001b[93m"

///|
pub let bright_blue : String = "\u001b[94m"

///|
pub let bright_magenta : String = "\u001b[95m"

///|
pub let bright_cyan : String = "\u001b[96m"

///|
pub let bright_white : String = "\u001b[97m"

// Background colors

///|
pub let bg_black : String = "\u001b[40m"

///|
pub let bg_red : String = "\u001b[41m"

///|
pub let bg_green : String = "\u001b[42m"

///|
pub let bg_yellow : String = "\u001b[43m"

///|
pub let bg_blue : String = "\u001b[44m"

///|
pub let bg_magenta : String = "\u001b[45m"

///|
pub let bg_cyan : String = "\u001b[46m"

///|
pub let bg_white : String = "\u001b[47m"

///|
/// Apply style to text
pub fn style(text : String, codes : Array[String]) -> String {
  let buf = StringBuilder::new()
  for code in codes {
    buf.write_string(code)
  }
  buf.write_string(text)
  buf.write_string(reset)
  buf.to_string()
}

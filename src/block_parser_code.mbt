///| Fenced and indented code-block parsing.

///|
/// Try to parse fenced code block
fn BlockParser::try_parse_fenced_code(
  self : BlockParser,
  start : Int,
  indent : Int,
) -> Block? {
  if indent > 3 {
    return None
  }
  let leading = self.read_leading_trivia()
  let fence_char = match self.scanner.peek() {
    Some(c) if c == '`' || c == '~' => c
    _ => return None
  }
  let fence_marker = if fence_char == '`' {
    FenceMarker::Backtick
  } else {
    FenceMarker::Tilde
  }
  let fence_length = self.scanner.count_char(fence_char)
  if fence_length < 3 {
    return None
  }
  self.scanner.advance(fence_length)

  // Read info string (language + optional filename)
  let _ = self.scanner.skip_spaces()
  let info = self.scanner.read_line().trim_end(chars=" \t").to_owned()

  // Skip newline
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Read code content until closing fence
  let code_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
    let line_indent = self.scanner.count_leading_spaces()

    // Check for closing fence
    if line_indent <= 3 {
      let saved = self.scanner.pos
      let _ = self.scanner.skip_spaces()
      let closing_count = self.scanner.count_char(fence_char)
      if closing_count >= fence_length {
        // Found closing fence
        self.scanner.advance(closing_count)
        let _ = self.scanner.skip_spaces()
        if char_is(self.scanner.peek(), '\n') || self.scanner.is_eof() {
          if char_is(self.scanner.peek(), '\n') {
            self.scanner.advance(1)
          }
          break
        }
      }
      self.scanner.restore(saved)
    }

    // Read code line (remove up to `indent` leading spaces)
    self.scanner.append_line_stripped_indent_to(code_buf, indent)
    if char_is(self.scanner.peek(), '\n') {
      code_buf.write_char('\n')
      self.scanner.advance(1)
    }
  }
  let trailing = Trivia::empty()
  Some(
    Block::FencedCode(
      fence_marker~,
      fence_length~,
      info~,
      code=code_buf.to_string(),
      indent~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=trailing,
    ),
  )
}

///|
/// Try to parse indented code block
fn BlockParser::try_parse_indented_code(
  self : BlockParser,
  start : Int,
) -> Block? {
  let leading = Trivia::empty()
  let code_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
    let line_start = self.scanner.pos

    // Check if line starts with 4+ spaces
    let indent = self.scanner.count_leading_spaces()
    if indent < 4 && !self.scanner.is_blank_line() {
      self.scanner.restore(line_start)
      break
    }
    if self.scanner.is_blank_line() {
      code_buf.write_char('\n')
      self.scanner.skip_line()
    } else {
      // Skip 4 spaces
      self.scanner.advance(4)
      self.scanner.append_line_to(code_buf)
      if char_is(self.scanner.peek(), '\n') {
        code_buf.write_char('\n')
        self.scanner.advance(1)
      }
    }
  }
  let code = code_buf.to_string().trim_end(chars="\n").to_owned()
  if code.is_empty() {
    return None
  }
  Some(
    Block::IndentedCode(
      code~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

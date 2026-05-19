///|
/// Inline parser tests
test "parse inline text" {
  let inlines = parse_inlines("Hello World")
  @debug.debug_inspect(inlines.length(), content="1")
  match inlines[0] {
    Inline::Text(content~, ..) => @debug.debug_inspect(content, content=(
      #|"Hello World"
    ))
    _ => fail("Expected Text")
  }
}

///|
test "parse emphasis with asterisk" {
  let inlines = parse_inlines("Hello *world*")
  @debug.debug_inspect(inlines.length(), content="2")
  match inlines[1] {
    Inline::Emphasis(marker~, children~, ..) => {
      @debug.debug_inspect(marker, content="Asterisk")
      @debug.debug_inspect(children.length(), content="1")
    }
    _ => fail("Expected Emphasis")
  }
}

///|
test "parse emphasis with underscore" {
  let inlines = parse_inlines("Hello _world_")
  @debug.debug_inspect(inlines.length(), content="2")
  match inlines[1] {
    Inline::Emphasis(marker~, ..) => @debug.debug_inspect(marker, content="Underscore")
    _ => fail("Expected Emphasis")
  }
}

///|
test "parse strong with asterisk" {
  let inlines = parse_inlines("Hello **world**")
  @debug.debug_inspect(inlines.length(), content="2")
  match inlines[1] {
    Inline::Strong(marker~, children~, ..) => {
      @debug.debug_inspect(marker, content="Asterisk")
      @debug.debug_inspect(children.length(), content="1")
    }
    _ => fail("Expected Strong")
  }
}

///|
test "parse strong with underscore" {
  let inlines = parse_inlines("Hello __world__")
  @debug.debug_inspect(inlines.length(), content="2")
  match inlines[1] {
    Inline::Strong(marker~, ..) => @debug.debug_inspect(marker, content="Underscore")
    _ => fail("Expected Strong")
  }
}

///|
test "parse inline code" {
  let inlines = parse_inlines("Hello `code` world")
  @debug.debug_inspect(inlines.length(), content="3")
  match inlines[1] {
    Inline::Code(content~, backtick_count~, ..) => {
      @debug.debug_inspect(content, content=(
        #|"code"
      ))
      @debug.debug_inspect(backtick_count, content="1")
    }
    _ => fail("Expected Code")
  }
}

///|
test "parse inline code with double backticks" {
  let inlines = parse_inlines("Use ``code with `backticks` inside``")
  match inlines[1] {
    Inline::Code(content~, backtick_count~, ..) => {
      @debug.debug_inspect(backtick_count, content="2")
      @debug.debug_inspect(content.contains("`"), content="true")
    }
    _ => fail("Expected Code")
  }
}

///|
test "parse link" {
  let inlines = parse_inlines("Click [here](https://example.com)")
  @debug.debug_inspect(inlines.length(), content="2")
  match inlines[1] {
    Inline::Link(url~, title~, children~, ..) => {
      @debug.debug_inspect(url, content=(
        #|"https://example.com"
      ))
      @debug.debug_inspect(title, content=(
        #|""
      ))
      @debug.debug_inspect(children.length(), content="1")
    }
    _ => fail("Expected Link")
  }
}

///|
test "parse link with title" {
  let inlines = parse_inlines("[link](https://example.com \"Title\")")
  match inlines[0] {
    Inline::Link(url~, title~, ..) => {
      @debug.debug_inspect(url, content=(
        #|"https://example.com"
      ))
      @debug.debug_inspect(title, content=(
        #|"Title"
      ))
    }
    _ => fail("Expected Link")
  }
}

///|
test "parse reference link" {
  let inlines = parse_inlines("[text][ref]")
  match inlines[0] {
    Inline::RefLink(label~, children~, ..) => {
      @debug.debug_inspect(label, content=(
        #|"ref"
      ))
      @debug.debug_inspect(children.length(), content="1")
    }
    _ => fail("Expected RefLink")
  }
}

///|
test "parse image" {
  let inlines = parse_inlines("![alt text](image.png)")
  match inlines[0] {
    Inline::Image(alt~, url~, title~, ..) => {
      @debug.debug_inspect(alt, content=(
        #|"alt text"
      ))
      @debug.debug_inspect(url, content=(
        #|"image.png"
      ))
      @debug.debug_inspect(title, content=(
        #|""
      ))
    }
    _ => fail("Expected Image")
  }
}

///|
test "parse image with title" {
  let inlines = parse_inlines("![alt](image.png \"Title\")")
  match inlines[0] {
    Inline::Image(alt~, url~, title~, ..) => {
      @debug.debug_inspect(alt, content=(
        #|"alt"
      ))
      @debug.debug_inspect(url, content=(
        #|"image.png"
      ))
      @debug.debug_inspect(title, content=(
        #|"Title"
      ))
    }
    _ => fail("Expected Image")
  }
}

///|
test "parse reference image" {
  let inlines = parse_inlines("![alt][ref]")
  match inlines[0] {
    Inline::RefImage(alt~, label~, ..) => {
      @debug.debug_inspect(alt, content=(
        #|"alt"
      ))
      @debug.debug_inspect(label, content=(
        #|"ref"
      ))
    }
    _ => fail("Expected RefImage")
  }
}

///|
test "parse autolink URL" {
  let inlines = parse_inlines("<https://example.com>")
  match inlines[0] {
    Inline::Autolink(url~, is_email~, ..) => {
      @debug.debug_inspect(url, content=(
        #|"https://example.com"
      ))
      @debug.debug_inspect(is_email, content="false")
    }
    _ => fail("Expected Autolink")
  }
}

///|
test "parse autolink email" {
  let inlines = parse_inlines("<user@example.com>")
  match inlines[0] {
    Inline::Autolink(url~, is_email~, ..) => {
      @debug.debug_inspect(url, content=(
        #|"user@example.com"
      ))
      @debug.debug_inspect(is_email, content="true")
    }
    _ => fail("Expected Autolink")
  }
}

///|
test "parse strikethrough" {
  let inlines = parse_inlines("Hello ~~deleted~~ world")
  @debug.debug_inspect(inlines.length(), content="3")
  match inlines[1] {
    Inline::Strikethrough(children~, ..) =>
      @debug.debug_inspect(children.length(), content="1")
    _ => fail("Expected Strikethrough")
  }
}

///|
test "parse hard break two spaces" {
  let inlines = parse_inlines("Line 1  \nLine 2")
  // Should have: "Line 1", HardBreak, "Line 2"
  let has_hard_break = inlines
    .iter()
    .any(fn(i) {
      match i {
        Inline::HardBreak(style=HardBreakStyle::TwoSpaces, ..) => true
        _ => false
      }
    })
  @debug.debug_inspect(has_hard_break, content="true")
}

///|
test "parse hard break backslash" {
  let inlines = parse_inlines("Line 1\\\nLine 2")
  let has_hard_break = inlines
    .iter()
    .any(fn(i) {
      match i {
        Inline::HardBreak(style=HardBreakStyle::Backslash, ..) => true
        _ => false
      }
    })
  @debug.debug_inspect(has_hard_break, content="true")
}

///|
test "parse soft break" {
  let inlines = parse_inlines("Line 1\nLine 2")
  let has_soft_break = inlines
    .iter()
    .any(fn(i) {
      match i {
        Inline::SoftBreak(..) => true
        _ => false
      }
    })
  @debug.debug_inspect(has_soft_break, content="true")
}

///|
test "parse escaped character" {
  let inlines = parse_inlines("Hello \\*not emphasis\\*")
  // Should parse as text, not emphasis
  let is_all_text = inlines
    .iter()
    .all(fn(i) {
      match i {
        Inline::Text(..) => true
        _ => false
      }
    })
  @debug.debug_inspect(is_all_text, content="true")
}

///|
test "parse nested emphasis in link" {
  let inlines = parse_inlines("[**bold** link](url)")
  match inlines[0] {
    Inline::Link(children~, ..) =>
      // Should have Strong as first child
      match children[0] {
        Inline::Strong(..) => ()
        _ => fail("Expected Strong inside Link")
      }
    _ => fail("Expected Link")
  }
}

///|
test "parse mixed inline content" {
  let inlines = parse_inlines("Hello *world* and `code`")
  @debug.debug_inspect(inlines.length() >= 4, content="true")
}

///|
test "parse_inlines_multipass with Japanese" {
  // Test the multi-pass parser that uses code_unit_at
  let inlines = parse_inlines_multipass("テスト*強調*終了")
  // Check that it parses without crashing
  inspect(inlines.length() >= 1, content="true")
}

///|
test "parse_inlines_multipass with Japanese emphasis" {
  let inlines = parse_inlines_multipass("*日本語*")
  match inlines[0] {
    @markdown.Inline::Emphasis(children~, ..) =>
      match children[0] {
        @markdown.Inline::Text(content~, ..) =>
          inspect(content, content="日本語")
        _ => fail("Expected Text inside Emphasis")
      }
    _ => fail("Expected Emphasis")
  }
}

///|
test "parse_inlines_multipass with Chinese" {
  let inlines = parse_inlines_multipass("**中文**测试")
  inspect(inlines.length() >= 1, content="true")
}

///|
test "parse_inlines_multipass mixed ASCII and Japanese" {
  let inlines = parse_inlines_multipass("Hello*世界*Goodbye")
  // Should have: Text("Hello") + Emphasis("世界") + Text("Goodbye")
  inspect(inlines.length(), content="3")
  match inlines[0] {
    @markdown.Inline::Text(content~, ..) => inspect(content, content="Hello")
    _ => fail("Expected Text")
  }
  match inlines[1] {
    @markdown.Inline::Emphasis(children~, ..) =>
      match children[0] {
        @markdown.Inline::Text(content~, ..) =>
          inspect(content, content="世界")
        _ => fail("Expected Text")
      }
    _ => fail("Expected Emphasis")
  }
  match inlines[2] {
    @markdown.Inline::Text(content~, ..) => inspect(content, content="Goodbye")
    _ => fail("Expected Text")
  }
}

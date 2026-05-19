///|
/// Block parser tests
test "parse heading" {
  let result = parse("# Hello World\n")
  let blocks = result.document.children
  @debug.debug_inspect(blocks.length(), content="1")
  match blocks[0] {
    Block::Heading(level~, style~, children~, ..) => {
      @debug.debug_inspect(level, content="1")
      @debug.debug_inspect(style, content="Atx")
      @debug.debug_inspect(children.length(), content="1")
      match children[0] {
        Inline::Text(content~, ..) => @debug.debug_inspect(content, content=(
          #|"Hello World"
        ))
        _ => fail("Expected text")
      }
    }
    _ => fail("Expected heading")
  }
}

///|
test "parse heading level 2-6" {
  for level = 2; level <= 6; level = level + 1 {
    let prefix = String::make(level, '#')
    let result = parse("\{prefix} Test\n")
    match result.document.children[0] {
      Block::Heading(level=l, ..) => @debug.debug_inspect(l == level, content="true")
      _ => fail("Expected heading")
    }
  }
}

///|
test "parse heading with closing hashes" {
  let result = parse("## Title ##\n")
  match result.document.children[0] {
    Block::Heading(level~, closing_hashes~, ..) => {
      @debug.debug_inspect(level, content="2")
      @debug.debug_inspect(closing_hashes, content="2")
    }
    _ => fail("Expected heading")
  }
}

///|
test "parse paragraph" {
  let result = parse("Hello world.\n")
  match result.document.children[0] {
    Block::Paragraph(children~, ..) =>
      match children[0] {
        Inline::Text(content~, ..) => @debug.debug_inspect(content, content=(
          #|"Hello world."
        ))
        _ => fail("Expected text")
      }
    _ => fail("Expected paragraph")
  }
}

///|
test "parse multiline paragraph" {
  let result = parse("Line 1\nLine 2\n")
  match result.document.children[0] {
    Block::Paragraph(children~, ..) => {
      // With inline parsing: "Line 1" + SoftBreak + "Line 2"
      @debug.debug_inspect(children.length() >= 2, content="true")
      match children[0] {
        Inline::Text(content~, ..) => @debug.debug_inspect(content, content=(
          #|"Line 1"
        ))
        _ => fail("Expected text")
      }
    }
    _ => fail("Expected paragraph")
  }
}

///|
test "parse fenced code block" {
  let result = parse("```js\nconsole.log('hello');\n```\n")
  match result.document.children[0] {
    Block::FencedCode(info~, code~, fence_marker~, fence_length~, ..) => {
      @debug.debug_inspect(info, content=(
        #|"js"
      ))
      @debug.debug_inspect(code, content=(
        #|"console.log('hello');\n"
      ))
      @debug.debug_inspect(fence_marker, content="Backtick")
      @debug.debug_inspect(fence_length, content="3")
    }
    _ => fail("Expected fenced code")
  }
}

///|
test "parse fenced code with tilde" {
  let result = parse("~~~python\nprint('hello')\n~~~\n")
  match result.document.children[0] {
    Block::FencedCode(info~, fence_marker~, ..) => {
      @debug.debug_inspect(info, content=(
        #|"python"
      ))
      @debug.debug_inspect(fence_marker, content="Tilde")
    }
    _ => fail("Expected fenced code")
  }
}

///|
test "parse fenced code with filename" {
  let result = parse("```json:package.json\n{\"name\": \"test\"}\n```\n")
  match result.document.children[0] {
    Block::FencedCode(info~, ..) => @debug.debug_inspect(info, content=(
      #|"json:package.json"
    ))
    _ => fail("Expected fenced code")
  }
}

///|
test "parse thematic break" {
  // Thematic break after content to avoid frontmatter confusion
  let result = parse("text\n\n---\n")
  let children = result.document.children
  // Find the thematic break
  let mut found = false
  for block in children {
    match block {
      Block::ThematicBreak(marker~, count~, ..) => {
        @debug.debug_inspect(marker == '-', content="true")
        @debug.debug_inspect(count, content="3")
        found = true
      }
      _ => ()
    }
  }
  @debug.debug_inspect(found, content="true")
}

///|
test "parse thematic break with asterisk" {
  let result = parse("***\n")
  match result.document.children[0] {
    Block::ThematicBreak(marker~, ..) => @debug.debug_inspect(marker == '*', content="true")
    _ => fail("Expected thematic break")
  }
}

///|
test "parse blockquote" {
  let result = parse("> Quote\n")
  match result.document.children[0] {
    Block::Blockquote(children~, ..) => {
      @debug.debug_inspect(children.length(), content="1")
      match children[0] {
        Block::Paragraph(children=p_children, ..) =>
          match p_children[0] {
            Inline::Text(content~, ..) => @debug.debug_inspect(content, content=(
              #|"Quote"
            ))
            _ => fail("Expected text")
          }
        _ => fail("Expected paragraph in blockquote")
      }
    }
    _ => fail("Expected blockquote")
  }
}

///|
test "parse bullet list" {
  let result = parse("- Item 1\n- Item 2\n")
  match result.document.children[0] {
    Block::BulletList(marker~, items~, tight~, ..) => {
      @debug.debug_inspect(marker, content="Dash")
      @debug.debug_inspect(items.length(), content="2")
      @debug.debug_inspect(tight, content="true")
    }
    _ => fail("Expected bullet list")
  }
}

///|
test "parse ordered list" {
  let result = parse("1. First\n2. Second\n")
  match result.document.children[0] {
    Block::OrderedList(start~, delimiter~, items~, ..) => {
      @debug.debug_inspect(start, content="1")
      @debug.debug_inspect(delimiter, content="Dot")
      @debug.debug_inspect(items.length(), content="2")
    }
    _ => fail("Expected ordered list")
  }
}

///|
test "parse indented code" {
  let result = parse("    code line\n    more code\n")
  match result.document.children[0] {
    Block::IndentedCode(code~, ..) =>
      @debug.debug_inspect(code, content=(
        #|"code line\nmore code"
      ))
    _ => fail("Expected indented code")
  }
}

///|
test "parse setext heading h1" {
  let result = parse("Title\n=====\n")
  match result.document.children[0] {
    Block::Heading(level~, style~, ..) => {
      @debug.debug_inspect(level, content="1")
      @debug.debug_inspect(style, content="Setext")
    }
    _ => fail("Expected setext heading")
  }
}

///|
test "parse setext heading h2" {
  let result = parse("Title\n-----\n")
  match result.document.children[0] {
    Block::Heading(level~, style~, ..) => {
      @debug.debug_inspect(level, content="2")
      @debug.debug_inspect(style, content="Setext")
    }
    _ => fail("Expected setext heading")
  }
}

///|
test "parse frontmatter" {
  let result = parse("---\ntitle: Hello\nauthor: World\n---\n# Content\n")
  match result.document.frontmatter {
    Some(fm) => {
      @debug.debug_inspect(fm.entries.length(), content="2")
      let (k1, v1) = fm.entries[0]
      @debug.debug_inspect(k1, content=(
        #|"title"
      ))
      @debug.debug_inspect(v1, content=(
        #|"Hello"
      ))
    }
    None => fail("Expected frontmatter")
  }
}

///|
test "parse link definition" {
  let result = parse("[link]: https://example.com \"Title\"\n")
  @debug.debug_inspect(result.definitions.length(), content="1")
  let def = result.definitions[0]
  @debug.debug_inspect(def.label, content=(
    #|"link"
  ))
  @debug.debug_inspect(def.url, content=(
    #|"https://example.com"
  ))
  @debug.debug_inspect(def.title, content=(
    #|"Title"
  ))
}

///|
test "parse mixed content" {
  let result = parse("# Title\n\nParagraph text.\n\n```js\ncode\n```\n")
  let children = result.document.children
  // Should have: Heading, BlankLines, Paragraph, BlankLines, FencedCode
  let mut heading_count = 0
  let mut para_count = 0
  let mut code_count = 0
  for block in children {
    match block {
      Block::Heading(..) => heading_count += 1
      Block::Paragraph(..) => para_count += 1
      Block::FencedCode(..) => code_count += 1
      _ => ()
    }
  }
  @debug.debug_inspect(heading_count, content="1")
  @debug.debug_inspect(para_count, content="1")
  @debug.debug_inspect(code_count, content="1")
}

///|
test "parse simple table" {
  let source = "| A | B |\n|---|---|\n| 1 | 2 |\n"
  let result = parse(source)
  match result.document.children[0] {
    Block::Table(header~, alignments~, rows~, ..) => {
      @debug.debug_inspect(header.length(), content="2")
      @debug.debug_inspect(alignments.length(), content="2")
      @debug.debug_inspect(rows.length(), content="1")
    }
    _ => fail("Expected Table")
  }
}

///|
test "parse table with alignment" {
  let source = "| Left | Center | Right |\n|:---|:---:|---:|\n| a | b | c |\n"
  let result = parse(source)
  match result.document.children[0] {
    Block::Table(alignments~, ..) => {
      @debug.debug_inspect(alignments[0], content="Left")
      @debug.debug_inspect(alignments[1], content="Center")
      @debug.debug_inspect(alignments[2], content="Right")
    }
    _ => fail("Expected Table")
  }
}

///|
test "parse table with multiple rows" {
  let source = "| H1 | H2 |\n|---|---|\n| R1C1 | R1C2 |\n| R2C1 | R2C2 |\n| R3C1 | R3C2 |\n"
  let result = parse(source)
  match result.document.children[0] {
    Block::Table(rows~, header~, ..) => {
      @debug.debug_inspect(header.length(), content="2")
      @debug.debug_inspect(rows.length(), content="3")
    }
    _ => fail("Expected Table")
  }
}

///|
test "parse table with inline formatting" {
  let source = "| **Bold** | *Italic* |\n|---|---|\n| `code` | [link](url) |\n"
  let result = parse(source)
  match result.document.children[0] {
    Block::Table(header~, rows~, ..) => {
      // Header cell should have Strong
      match header[0].children[0] {
        Inline::Strong(..) => ()
        _ => fail("Expected Strong in header")
      }
      // Data cell should have Code
      match rows[0][0].children[0] {
        Inline::Code(..) => ()
        _ => fail("Expected Code in cell")
      }
    }
    _ => fail("Expected Table")
  }
}

///|
test "parse nested code block with 4 backticks" {
  // Use 4 backticks to wrap markdown containing 3-backtick code blocks
  let source = "````md\n```js\nconsole.log('hello');\n```\n````\n"
  let result = parse(source)
  match result.document.children[0] {
    Block::FencedCode(info~, code~, fence_length~, ..) => {
      @debug.debug_inspect(fence_length, content="4")
      @debug.debug_inspect(info, content=(
        #|"md"
      ))
      // The inner code block should be preserved as content
      @debug.debug_inspect(code.contains("```js"), content="true")
      @debug.debug_inspect(code.contains("console.log"), content="true")
    }
    _ => fail("Expected fenced code block")
  }
}

///|
test "parse code block with lang and filename" {
  let result = parse("```typescript:src/index.ts\nconst x = 1;\n```\n")
  match result.document.children[0] {
    Block::FencedCode(info~, ..) =>
      @debug.debug_inspect(info, content=(
        #|"typescript:src/index.ts"
      ))
    _ => fail("Expected fenced code")
  }
}

///|
test "parse code block with lang, filename, and meta" {
  // Support meta attributes like {highlight=[1,3]}
  let result = parse(
    "```js:app.js {highlight=[1,3]}\nconst a = 1;\nconst b = 2;\nconst c = 3;\n```\n",
  )
  match result.document.children[0] {
    Block::FencedCode(info~, ..) =>
      @debug.debug_inspect(info, content=(
        #|"js:app.js {highlight=[1,3]}"
      ))
    _ => fail("Expected fenced code")
  }
}

///|
test "serialize table roundtrip" {
  let source = "| A | B |\n|:---|---:|\n| 1 | 2 |\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(output.contains("| A |"), content="true")
  // remark-gfm style: | :-- | (left) and | --: | (right)
  @debug.debug_inspect(output.contains("| :-- |"), content="true")
  @debug.debug_inspect(output.contains("| --: |"), content="true")
}

///|
test "parse task list unchecked" {
  let result = parse("- [ ] todo item\n")
  match result.document.children[0] {
    Block::BulletList(items~, ..) => {
      @debug.debug_inspect(items.length(), content="1")
      @debug.debug_inspect(items[0].checked, content="Some(false)")
    }
    _ => fail("Expected BulletList")
  }
}

///|
test "parse task list checked lowercase" {
  let result = parse("- [x] done item\n")
  match result.document.children[0] {
    Block::BulletList(items~, ..) => {
      @debug.debug_inspect(items.length(), content="1")
      @debug.debug_inspect(items[0].checked, content="Some(true)")
    }
    _ => fail("Expected BulletList")
  }
}

///|
test "parse task list checked uppercase" {
  let result = parse("- [X] done item\n")
  match result.document.children[0] {
    Block::BulletList(items~, ..) => {
      @debug.debug_inspect(items.length(), content="1")
      @debug.debug_inspect(items[0].checked, content="Some(true)")
    }
    _ => fail("Expected BulletList")
  }
}

///|
test "parse task list mixed" {
  let result = parse("- [ ] foo\n- [x] bar\n")
  match result.document.children[0] {
    Block::BulletList(items~, ..) => {
      @debug.debug_inspect(items.length(), content="2")
      @debug.debug_inspect(items[0].checked, content="Some(false)")
      @debug.debug_inspect(items[1].checked, content="Some(true)")
    }
    _ => fail("Expected BulletList")
  }
}

///|
test "serialize task list roundtrip" {
  let source = "- [ ] foo\n- [x] bar\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(output.contains("[ ] foo"), content="true")
  @debug.debug_inspect(output.contains("[x] bar"), content="true")
}

///|
test "parse custom element single line" {
  let result = parse("<my-component>content</my-component>\n")
  @debug.debug_inspect(result.document.children.length(), content="1")
  match result.document.children[0] {
    Block::HtmlBlock(html~, ..) => {
      @debug.debug_inspect(html.contains("my-component"), content="true")
      @debug.debug_inspect(html.contains("content"), content="true")
    }
    _ => fail("Expected HtmlBlock")
  }
}

///|
test "parse custom element multi-line" {
  let source =
    #|<my-component>
    #|  <div>Content here</div>
    #|  <p>More content</p>
    #|</my-component>
    #|
  let result = parse(source)
  @debug.debug_inspect(result.document.children.length(), content="1")
  match result.document.children[0] {
    Block::HtmlBlock(html~, ..) => {
      @debug.debug_inspect(html.contains("<my-component>"), content="true")
      @debug.debug_inspect(html.contains("</my-component>"), content="true")
      @debug.debug_inspect(html.contains("Content here"), content="true")
    }
    _ => fail("Expected HtmlBlock for multi-line custom element")
  }
}

///|
test "parse custom element self-closing" {
  let result = parse("<my-component attr=\"value\" />\n")
  @debug.debug_inspect(result.document.children.length(), content="1")
  match result.document.children[0] {
    Block::HtmlBlock(html~, ..) => {
      @debug.debug_inspect(html.contains("my-component"), content="true")
      @debug.debug_inspect(html.contains("/>"), content="true")
    }
    _ => fail("Expected HtmlBlock for self-closing custom element")
  }
}

///|
test "parse custom element with attributes" {
  let source =
    #|<custom-button class="primary" data-id="123">
    #|  Click me
    #|</custom-button>
    #|
  let result = parse(source)
  @debug.debug_inspect(result.document.children.length(), content="1")
  match result.document.children[0] {
    Block::HtmlBlock(html~, ..) => {
      @debug.debug_inspect(html.contains("custom-button"), content="true")
      @debug.debug_inspect(html.contains("class=\"primary\""), content="true")
      @debug.debug_inspect(html.contains("data-id=\"123\""), content="true")
    }
    _ => fail("Expected HtmlBlock")
  }
}

///|
test "parse custom element with BEM class names (double underscore)" {
  // BEM naming: block__element--modifier
  // The __ should NOT be interpreted as markdown strong syntax
  let source =
    #|<styled-checkbox-demo>
    #|  <div class="checkbox__control">
    #|    <span class="checkbox__icon--check"></span>
    #|  </div>
    #|</styled-checkbox-demo>
    #|
  let result = parse(source)
  @debug.debug_inspect(result.document.children.length(), content="1")
  match result.document.children[0] {
    Block::HtmlBlock(html~, ..) => {
      // Verify the double underscores are preserved
      @debug.debug_inspect(html.contains("checkbox__control"), content="true")
      @debug.debug_inspect(html.contains("checkbox__icon--check"), content="true")
    }
    _ => fail("Expected HtmlBlock for custom element with BEM classes")
  }
}

///|
test "parse custom element single line with BEM classes" {
  let source = "<my-demo><span class=\"switch__thumb\"></span></my-demo>\n"
  let result = parse(source)
  @debug.debug_inspect(result.document.children.length(), content="1")
  match result.document.children[0] {
    Block::HtmlBlock(html~, ..) =>
      // __ must be preserved, not treated as strong/bold markdown
      @debug.debug_inspect(html.contains("switch__thumb"), content="true")
    _ => fail("Expected HtmlBlock")
  }
}

///|
test "parse html comment block" {
  let result = parse("<!-- comment -->\n\n# Title\n")
  @debug.debug_inspect(result.document.children.length(), content="3")
  match result.document.children[0] {
    Block::HtmlBlock(html~, ..) => @debug.debug_inspect(html, content=(
      #|"<!-- comment -->\n"
    ))
    _ => fail("Expected HtmlBlock for HTML comment")
  }
}

///|
test "parse multiline html comment block" {
  let source =
    #|<!--
    #|comment
    #|-->
    #|
  let result = parse(source)
  @debug.debug_inspect(result.document.children.length(), content="1")
  match result.document.children[0] {
    Block::HtmlBlock(html~, ..) => {
      @debug.debug_inspect(html.contains("<!--"), content="true")
      @debug.debug_inspect(html.contains("comment"), content="true")
      @debug.debug_inspect(html.contains("-->"), content="true")
    }
    _ => fail("Expected HtmlBlock for multiline HTML comment")
  }
}

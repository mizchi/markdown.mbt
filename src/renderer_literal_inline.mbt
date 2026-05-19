///| Inline rendering for the literal (source-preserving) renderer.
///|
///| Split from renderer_literal.mbt to keep that file focused on the
///| document / block-level dispatch. Helpers (`LiteralOpts`,
///| `write_marker`, `write_image_preview_slot`, `repeat_char`,
///| `escape_html` …) live alongside in the same package.


///|
fn render_inlines_literal(
  inlines : Array[Inline],
  buf : StringBuilder,
  opts : LiteralOpts,
) -> Unit {
  for inline in inlines {
    render_inline_literal(inline, buf, opts)
  }
}

///|
fn render_inline_literal(
  inline : Inline,
  buf : StringBuilder,
  opts : LiteralOpts,
) -> Unit {
  // Inline spans come from the inline parser and are relative to the
  // surrounding block's content, not the document. They are intentionally
  // omitted from `data-src-*` annotations — the block-level ancestor's
  // span is enough to recover precise source offsets via the visible-text
  // invariant.
  match inline {
    Inline::Text(content~, ..) => escape_html_into(buf, content)
    Inline::SoftBreak(..) => buf.write_char('\n')
    Inline::HardBreak(..) => {
      write_marker(buf, "\\")
      buf.write_char('\n')
    }
    Inline::Emphasis(children~, ..) => {
      buf.write_string("<em>")
      write_marker(buf, "*")
      render_inlines_literal(children, buf, opts)
      write_marker(buf, "*")
      buf.write_string("</em>")
    }
    Inline::Strong(children~, ..) => {
      buf.write_string("<strong>")
      write_marker(buf, "**")
      render_inlines_literal(children, buf, opts)
      write_marker(buf, "**")
      buf.write_string("</strong>")
    }
    Inline::Strikethrough(children~, ..) => {
      buf.write_string("<del>")
      write_marker(buf, "~~")
      render_inlines_literal(children, buf, opts)
      write_marker(buf, "~~")
      buf.write_string("</del>")
    }
    Inline::Code(content~, ..) => {
      let backticks = calc_code_span_backticks(content)
      let needs_padding = content.length() > 0 &&
        ({
          let first = content.get_char(0)
          let last = content.get_char(content.length() - 1)
          first == Some('`') || last == Some('`')
        })
      buf.write_string("<code>")
      write_marker_repeat(buf, '`', backticks)
      if needs_padding {
        buf.write_char(' ')
      }
      escape_html_into(buf, content)
      if needs_padding {
        buf.write_char(' ')
      }
      write_marker_repeat(buf, '`', backticks)
      buf.write_string("</code>")
    }
    Inline::WikiLink(target~, label~, fragment~, ..) => {
      let href = if fragment.is_empty() {
        target
      } else {
        target + "#" + fragment
      }
      buf.write_string("<a class=\"md-wikilink\" href=\"")
      escape_html_attr_into(buf, href)
      buf.write_string("\">")
      write_marker(buf, "[[")
      escape_html_into(buf, target)
      if !fragment.is_empty() {
        escape_html_into(buf, "#" + fragment)
      }
      if !label.is_empty() {
        write_marker(buf, "|")
        escape_html_into(buf, label)
      }
      write_marker(buf, "]]")
      buf.write_string("</a>")
    }
    Inline::Link(children~, url~, title~, ..) => {
      buf.write_string("<a href=\"")
      escape_html_attr_into(buf, url)
      buf.write_char('"')
      if !title.is_empty() {
        buf.write_string(" title=\"")
        escape_html_attr_into(buf, title)
        buf.write_char('"')
      }
      buf.write_char('>')
      write_marker(buf, "[")
      render_inlines_literal(children, buf, opts)
      let trailing = if title.is_empty() {
        "](" + url + ")"
      } else {
        "](" + url + " \"" + title + "\")"
      }
      write_marker(buf, trailing)
      buf.write_string("</a>")
    }
    Inline::RefLink(children~, label~, ..) => {
      buf.write_string("<a class=\"md-reflink\" href=\"#ref-")
      escape_html_attr_into(buf, label)
      buf.write_string("\">")
      write_marker(buf, "[")
      render_inlines_literal(children, buf, opts)
      write_marker(buf, "][" + label + "]")
      buf.write_string("</a>")
    }
    Inline::Autolink(url~, is_email~, ..) => {
      let href = if is_email { "mailto:" + url } else { url }
      buf.write_string("<a href=\"")
      escape_html_attr_into(buf, href)
      buf.write_string("\">")
      write_marker(buf, "<")
      escape_html_into(buf, url)
      write_marker(buf, ">")
      buf.write_string("</a>")
    }
    Inline::Image(alt~, url~, title~, ..) => {
      buf.write_string("<span class=\"md-image\" role=\"img\" aria-label=\"")
      escape_html_attr_into(buf, alt)
      buf.write_string("\">")
      if opts.image_preview {
        write_image_preview_slot(buf, url, alt, title)
      }
      write_marker(buf, "![")
      escape_html_into(buf, alt)
      let trailing = if title.is_empty() {
        "](" + url + ")"
      } else {
        "](" + url + " \"" + title + "\")"
      }
      write_marker(buf, trailing)
      buf.write_string("</span>")
    }
    Inline::RefImage(alt~, label~, ..) => {
      // Reference images don't carry an URL inline; the slot stays empty.
      // The consumer can resolve `data-md-image-ref` against their own
      // definition map and assign a `src` later.
      buf.write_string("<span class=\"md-image\" role=\"img\" aria-label=\"")
      escape_html_attr_into(buf, alt)
      buf.write_string("\">")
      if opts.image_preview {
        buf.write_string("<img class=\"md-image-preview\" data-md-image-ref=\"")
        escape_html_attr_into(buf, label)
        buf.write_string("\" alt=\"")
        escape_html_attr_into(buf, alt)
        buf.write_string("\" loading=\"lazy\" />")
      }
      write_marker(buf, "![")
      escape_html_into(buf, alt)
      write_marker(buf, "][" + label + "]")
      buf.write_string("</span>")
    }
    Inline::HtmlInline(html~, ..) => {
      buf.write_string("<span class=\"md-html-inline\">")
      escape_html_into(buf, html)
      buf.write_string("</span>")
    }
    Inline::FootnoteReference(label~, ..) => {
      // The `[^label]` source characters are the only content, but they
      // sit inside an `aria-hidden` marker span — without an explicit
      // `aria-label` the `<a>` would be focusable yet nameless.
      buf.write_string("<sup class=\"footnote-ref\"><a href=\"#fn-")
      escape_html_attr_into(buf, label)
      buf.write_string("\" aria-label=\"Footnote ")
      escape_html_attr_into(buf, label)
      buf.write_string("\">")
      write_marker(buf, "[^" + label + "]")
      buf.write_string("</a></sup>")
    }
  }
}

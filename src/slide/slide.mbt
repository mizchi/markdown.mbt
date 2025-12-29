///|
/// Slide represents a single slide with its content span
pub(all) struct Slide {
  /// 0-indexed slide number
  index : Int
  /// Start offset in source text
  start : Int
  /// End offset in source text (exclusive)
  end : Int
  /// The AST blocks for this slide
  blocks : Array[@markdown.Block]
}

///|
/// SlideDocument represents a parsed slide document
pub(all) struct SlideDocument {
  slides : Array[Slide]
  source : String
}

///|
/// Parse markdown into slides, splitting on ThematicBreak (---)
pub fn parse(source : String) -> SlideDocument {
  let result = @markdown.parse(source)
  let doc = result.document
  let slides : Array[Slide] = []
  let current_blocks : Array[@markdown.Block] = []
  let mut slide_start = 0
  let mut slide_index = 0

  for block in doc.children {
    match block {
      @markdown.Block::ThematicBreak(span~, ..) => {
        // End current slide before the thematic break
        if current_blocks.length() > 0 {
          slides.push(
            Slide::{
              index: slide_index,
              start: slide_start,
              end: span.from,
              blocks: current_blocks.copy(),
            },
          )
          slide_index += 1
          current_blocks.clear()
        }
        // Start new slide after thematic break
        slide_start = span.to
      }
      _ => {
        current_blocks.push(block)
      }
    }
  }

  // Don't forget the last slide
  if current_blocks.length() > 0 {
    slides.push(
      Slide::{
        index: slide_index,
        start: slide_start,
        end: source.length(),
        blocks: current_blocks.copy(),
      },
    )
  }

  // Handle empty document
  if slides.length() == 0 {
    slides.push(
      Slide::{ index: 0, start: 0, end: source.length(), blocks: [] },
    )
  }

  SlideDocument::{ slides, source }
}

///|
/// Find which slide contains the given cursor position
pub fn SlideDocument::find_slide_at_position(
  self : SlideDocument,
  position : Int
) -> Int {
  for slide in self.slides {
    if position >= slide.start && position < slide.end {
      return slide.index
    }
  }
  // Default to last slide if position is at or beyond end
  if self.slides.length() > 0 {
    return self.slides[self.slides.length() - 1].index
  }
  0
}

///|
/// Get total number of slides
pub fn SlideDocument::slide_count(self : SlideDocument) -> Int {
  self.slides.length()
}

///|
/// Get a specific slide by index
pub fn SlideDocument::get_slide(self : SlideDocument, index : Int) -> Slide? {
  if index >= 0 && index < self.slides.length() {
    Some(self.slides[index])
  } else {
    None
  }
}

///|
/// Get the source text for a slide
pub fn SlideDocument::get_slide_source(
  self : SlideDocument,
  index : Int
) -> String {
  match self.get_slide(index) {
    Some(slide) => {
      let start = if slide.start < 0 { 0 } else { slide.start }
      let end = if slide.end > self.source.length() {
        self.source.length()
      } else {
        slide.end
      }
      if start >= end {
        ""
      } else {
        // Use try to handle potential slice errors
        try {
          self.source[start:end].to_string()
        } catch {
          _ => ""
        }
      }
    }
    None => ""
  }
}

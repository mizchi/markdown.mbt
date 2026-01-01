///| MDX Lezer Tokenizer Benchmarks

// =============================================================================
// Test Data
// =============================================================================

///|
let simple_heading : String = "# Hello World"

///|
let simple_jsx : String = "<Button>Click me</Button>"

///|
let jsx_with_attrs : String = "<Button variant=\"primary\" onClick={handleClick} disabled>Submit</Button>"

///|
let self_closing_jsx : String = "<Image src=\"/photo.jpg\" alt=\"Photo\" width={800} height={600} />"

///|
let simple_import : String = "import Button from './Button'"

///|
let named_imports : String = "import { Button, Card, Modal } from './components'"

///|
let frontmatter : String =
  #|---
  #|title: Hello
  #|author: World
  #|date: 2024-01-01
  #|---

///|
let code_fence : String =
  #|```javascript
  #|function hello() {
  #|  console.log('Hello, World!');
  #|}
  #|```

///|
let inline_markdown : String = "This is **bold** and *italic* and `code` text."

///|
fn generate_mdx_doc(imports : Int, headings : Int, components : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("---\ntitle: Generated\n---\n\n")
  for i = 0; i < imports; i = i + 1 {
    buf.write_string("import Component\{i} from './Component\{i}'\n")
  }
  buf.write_string("\n")
  for i = 0; i < headings; i = i + 1 {
    buf.write_string("## Heading \{i}\n\n")
    buf.write_string("Some **bold** and *italic* text.\n\n")
  }
  for i = 0; i < components; i = i + 1 {
    buf.write_string("<Component\{i} prop\{i}=\"value\{i}\" onClick={{handler}}>Content \{i}</Component\{i}>\n\n")
  }
  buf.to_string()
}

///|
let small_mdx_doc : String = generate_mdx_doc(3, 2, 5)

///|
let medium_mdx_doc : String = generate_mdx_doc(10, 5, 20)

///|
let large_mdx_doc : String = generate_mdx_doc(30, 15, 50)

///|
let blog_post : String =
  #|---
  #|title: Understanding React Hooks
  #|author: John Doe
  #|date: 2024-01-15
  #|tags: [react, hooks, javascript]
  #|---
  #|
  #|import { CodeBlock } from './components/CodeBlock'
  #|import { Callout } from './components/Callout'
  #|import { Author } from './components/Author'
  #|
  #|# Understanding React Hooks
  #|
  #|React Hooks are a powerful way to add state and lifecycle features to functional components.
  #|
  #|<Callout type="info">
  #|  This tutorial assumes you have basic knowledge of React.
  #|</Callout>
  #|
  #|## useState Hook
  #|
  #|The `useState` hook allows you to add state to functional components.
  #|
  #|```javascript
  #|import { useState } from 'react';
  #|
  #|function Counter() {
  #|  const [count, setCount] = useState(0);
  #|  return (
  #|    <button onClick={() => setCount(count + 1)}>
  #|      Count: {count}
  #|    </button>
  #|  );
  #|}
  #|```
  #|
  #|## useEffect Hook
  #|
  #|The `useEffect` hook lets you perform side effects in your components.
  #|
  #|<CodeBlock language="javascript" showLineNumbers>
  #|{`import { useEffect, useState } from 'react';
  #|
  #|function DataFetcher() {
  #|  const [data, setData] = useState(null);
  #|
  #|  useEffect(() => {
  #|    fetch('/api/data')
  #|      .then(res => res.json())
  #|      .then(setData);
  #|  }, []);
  #|
  #|  return <div>{data}</div>;
  #|}`}
  #|</CodeBlock>
  #|
  #|## Conclusion
  #|
  #|React Hooks provide a **cleaner** and more *intuitive* way to manage state and side effects.
  #|
  #|<Author name="John Doe" avatar="/john.jpg" />

// =============================================================================
// Tokenization Benchmarks
// =============================================================================

///|
test "mdx-lezer: tokenize simple heading" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(simple_heading)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize simple JSX" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(simple_jsx)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize JSX with attributes" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(jsx_with_attrs)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize self-closing JSX" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(self_closing_jsx)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize simple import" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(simple_import)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize named imports" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(named_imports)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize frontmatter" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(frontmatter)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize code fence" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(code_fence)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize inline markdown" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(inline_markdown)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

// =============================================================================
// Document Size Benchmarks
// =============================================================================

///|
test "mdx-lezer: tokenize small document" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(small_mdx_doc)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize medium document" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(medium_mdx_doc)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize large document" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(large_mdx_doc)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: tokenize blog post" (b : @bench.T) {
  b.bench(fn() {
    let tokenizer = MdxTokenizer::new(blog_post)
    let tokens = tokenizer.tokenize_all()
    b.keep(tokens)
  })
}

// =============================================================================
// Highlighting Benchmarks
// =============================================================================

///|
test "mdx-lezer: highlight small document" (b : @bench.T) {
  b.bench(fn() {
    let tokens = highlight_mdx(small_mdx_doc)
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: highlight medium document" (b : @bench.T) {
  b.bench(fn() {
    let tokens = highlight_mdx(medium_mdx_doc)
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: highlight large document" (b : @bench.T) {
  b.bench(fn() {
    let tokens = highlight_mdx(large_mdx_doc)
    b.keep(tokens)
  })
}

///|
test "mdx-lezer: highlight blog post" (b : @bench.T) {
  b.bench(fn() {
    let tokens = highlight_mdx(blog_post)
    b.keep(tokens)
  })
}

// =============================================================================
// HTML Generation Benchmarks
// =============================================================================

///|
test "mdx-lezer: to_html small document" (b : @bench.T) {
  b.bench(fn() {
    let html = highlight_mdx_to_html(small_mdx_doc)
    b.keep(html)
  })
}

///|
test "mdx-lezer: to_html medium document" (b : @bench.T) {
  b.bench(fn() {
    let html = highlight_mdx_to_html(medium_mdx_doc)
    b.keep(html)
  })
}

///|
test "mdx-lezer: to_html blog post" (b : @bench.T) {
  b.bench(fn() {
    let html = highlight_mdx_to_html(blog_post)
    b.keep(html)
  })
}

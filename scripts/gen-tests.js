#!/usr/bin/env node
/**
 * Generate CommonMark compatibility tests from spec.json
 *
 * Usage: node scripts/gen-tests.js
 *
 * This script:
 * 1. Downloads CommonMark spec.json
 * 2. Generates MoonBit test files comparing our output with remark-gfm
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Parse command line arguments
const noSkip = process.argv.includes('--no-skip');

const SPEC_URL = 'https://spec.commonmark.org/0.31.2/spec.json';
const OUTPUT_DIR = path.join(__dirname, '../src/cmark_tests');

// Sections to include (skip some that are HTML-specific or edge cases)
const INCLUDE_SECTIONS = [
  'Tabs',
  'Thematic breaks',
  'ATX headings',
  'Setext headings',
  'Indented code blocks',
  'Fenced code blocks',
  'Paragraphs',
  'Blank lines',
  'Block quotes',
  'List items',
  'Lists',
  'Backslash escapes',
  'Code spans',
  'Emphasis and strong emphasis',
  'Links',
  'Images',
  'Autolinks',
  'Hard line breaks',
  'Soft line breaks',
  'Textual content',
];

// Examples whose Markdown output still differs from remark's formatting
// policy. The parser itself is CommonMark-conformant (see `gen-spec-tests.js`).
// `serialize` has its own normalized contract: definitions move to a trailing
// section, Setext becomes ATX, and stable list markers are preferred. Keep this
// list as a compatibility signal, not as the serializer's correctness oracle.
const SKIP_TESTS = {
  "Backslash escapes": [12, 14, 15, 20, 24],
  "Thematic breaks": [45, 46, 55],
  "ATX headings": [63, 64, 65, 70, 75, 76],
  "Setext headings": [81, 82, 87, 88, 90, 93, 95, 97, 106],
  "Fenced code blocks": [146],
  "Block quotes": [228, 229, 230, 232, 238, 239, 240, 244],
  "List items": [259, 260, 266, 278, 285, 298, 299],
  "Lists": [302, 304, 306, 309, 311, 312, 313, 314, 315, 317, 318, 326],
  "Code spans": [331],
  "Emphasis and strong emphasis": [416, 417],
  "Links": [488, 490, 491, 493, 494, 497, 508, 512, 513, 518, 519, 528, 541, 544, 550, 564, 568],
  "Autolinks": [602, 603, 606, 607, 608],
  "Hard line breaks": [644, 646],
};

// Exact-output differences that also change rendered HTML after a
// parse -> serialize -> parse round trip. The other skipped examples are
// formatter-policy differences only (ATX normalization, marker choice, etc.).
const SEMANTIC_RISK_EXAMPLES = new Set([
  14, 15,
  65, 70, 76,
  81, 82, 87, 93, 95, 106,
  146,
  238, 239, 240, 244,
  259, 260,
  302, 306, 311, 312, 313, 314, 315, 317,
  331,
  512, 528, 550, 564,
]);

// Get skip reason for a test
function getSkipReason(section, example) {
  const examples = SKIP_TESTS[section];
  if (examples === undefined || !examples.includes(example)) return null;
  return SEMANTIC_RISK_EXAMPLES.has(example)
    ? 'semantic roundtrip differs after normalization'
    : 'normalized formatting differs from remark';
}

// Escape string for MoonBit string literal
function escapeString(s) {
  return s
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\t/g, '\\t');
}

// Convert section name to valid MoonBit identifier
function sectionToId(section) {
  return section
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '');
}

// Update .gitignore to exclude generated tests
function updateGitignore() {
  const gitignorePath = path.join(__dirname, '../.gitignore');
  const entry = 'src/cmark_tests/';

  let content = '';
  if (fs.existsSync(gitignorePath)) {
    content = fs.readFileSync(gitignorePath, 'utf-8');
  }

  if (!content.includes(entry)) {
    // Ensure file ends with newline before adding
    if (content.length > 0 && !content.endsWith('\n')) {
      content += '\n';
    }
    content += entry + '\n';
    fs.writeFileSync(gitignorePath, content);
    console.log(`Added ${entry} to .gitignore`);
  }
}

async function main() {
  // Update .gitignore first
  updateGitignore();

  console.log('Fetching CommonMark spec...');
  const response = await fetch(SPEC_URL);
  const spec = await response.json();

  console.log(`Found ${spec.length} test cases`);

  // Group by section
  const bySection = new Map();
  for (const test of spec) {
    if (!INCLUDE_SECTIONS.includes(test.section)) continue;

    if (!bySection.has(test.section)) {
      bySection.set(test.section, []);
    }
    bySection.get(test.section).push(test);
  }

  // Create output directory
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  // Generate the current MoonBit package format and remove the deprecated one.
  const pkg = `import {
  "mizchi/markdown",
}

options(
  supported_targets: "js",
)
`;
  fs.writeFileSync(path.join(OUTPUT_DIR, 'moon.pkg'), pkg);
  fs.rmSync(path.join(OUTPUT_DIR, 'moon.pkg.json'), { force: true });

  // Generate ffi.mbt (copy from compat_tests)
  const ffiContent = `///| FFI bindings for remark compatibility testing
///| This file is JS-target only

///| Call remark with GFM support to process markdown (sync via require)
///| Returns stringified result from remark
pub extern "js" fn remark_stringify(input : String) -> String =
  #| (input) => {
  #|   const { remark } = require('remark');
  #|   const remarkGfm = require('remark-gfm').default;
  #|   const result = remark().use(remarkGfm).processSync(input);
  #|   return normalizeBulletMarkers(String(result));
  #|
  #|   function normalizeBulletMarkers(markdown) {
  #|     let inFence = false;
  #|     let fenceChar = "";
  #|     let fenceLen = 0;
  #|     return markdown.split("\\n").map((line) => {
  #|       const fence = line.match(/^[ \\t]{0,3}(\`{3,}|~{3,})/);
  #|       if (fence) {
  #|         const marker = fence[1];
  #|         const ch = marker[0];
  #|         if (!inFence) {
  #|           inFence = true;
  #|           fenceChar = ch;
  #|           fenceLen = marker.length;
  #|         } else if (ch === fenceChar && marker.length >= fenceLen) {
  #|           inFence = false;
  #|         }
  #|         return line;
  #|       }
  #|       if (inFence) return line;
  #|       return line.replace(/^((?:[ \\t]*>\\s*)*[ \\t]*)\\*(?= \\S|$)/, "$1-");
  #|     }).join("\\n");
  #|   }
  #| }
`;
  fs.writeFileSync(path.join(OUTPUT_DIR, 'ffi.mbt'), ffiContent);

  // Generate test helper
  const helperContent = `///| CommonMark spec compatibility tests
///| Generated from https://spec.commonmark.org/0.31.2/spec.json

///| Test helper: compare our output with remark's output
pub fn assert_commonmark_compat(input : String, example : Int) -> Unit {
  let our_output = @markdown.md_parse_and_render(input)
  let remark_output = remark_stringify(input)

  // Normalize trailing whitespace for comparison
  let our_normalized = our_output.trim_end(chars=" \\n\\t")
  let remark_normalized = remark_output.trim_end(chars=" \\n\\t")

  if our_normalized != remark_normalized {
    println("=== Example \\{example} ===")
    println("=== Input ===")
    println(input)
    println("=== Our output ===")
    println(our_normalized)
    println("=== Remark output ===")
    println(remark_normalized)
    panic()
  }
}
`;
  fs.writeFileSync(path.join(OUTPUT_DIR, 'helper.mbt'), helperContent);

  // Generate test files per section
  let totalTests = 0;
  for (const [section, tests] of bySection) {
    const sectionId = sectionToId(section);
    const fileName = `${sectionId}_test.mbt`;

    let content = `///| CommonMark spec tests: ${section}\n\n`;

    for (const test of tests) {
      const escapedInput = escapeString(test.markdown);
      const skipReason = noSkip ? null : getSkipReason(section, test.example);

      if (skipReason) {
        content += `#skip("${skipReason}")\n`;
      }
      content += `test "commonmark example ${test.example}: ${section}" {\n`;
      content += `  assert_commonmark_compat("${escapedInput}", ${test.example})\n`;
      content += `}\n\n`;
      totalTests++;
    }

    fs.writeFileSync(path.join(OUTPUT_DIR, fileName), content);
    console.log(`Generated ${fileName} with ${tests.length} tests`);
  }

  console.log(`\nTotal: ${totalTests} tests generated in ${OUTPUT_DIR}`);
  if (noSkip) {
    console.log('\n⚠️  Generated with --no-skip: all tests will run without skip annotations');
    console.log('   Remember to regenerate without --no-skip after checking!');
  }
  console.log('\nRun tests with: moon test --target js -p mizchi/markdown/commonmark_tests');
}

main().catch(console.error);

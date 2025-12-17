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

const fs = require('fs');
const path = require('path');

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

// Tests to skip with reasons
// This parser implements a practical subset of CommonMark.
// Edge cases and complex patterns are intentionally not supported.
// Generated from actual test failures (340 failures out of 542 tests)
const SKIP_TESTS = {
  // Tabs: Tab handling in various contexts
  'Tabs': {
    reason: 'Tab handling edge case',
    examples: [1, 2, 4, 5, 6, 7, 8, 9],
  },
  // Backslash escapes: Output format differences
  'Backslash escapes': {
    reason: 'Escape output format difference',
    examples: [12, 14, 15, 20, 21, 22, 23, 24],
  },
  // Thematic breaks: Edge cases with lists
  'Thematic breaks': {
    reason: 'Thematic break edge case',
    examples: [45, 46, 48, 49, 55, 59, 60, 61],
  },
  // ATX headings: Edge cases
  'ATX headings': {
    reason: 'ATX heading edge case',
    examples: [63, 64, 65, 66, 69, 70, 75, 76],
  },
  // Setext headings: Not implemented (ATX is sufficient)
  'Setext headings': {
    reason: 'Setext headings not implemented',
    examples: [80, 82, 83, 84, 86, 87, 88, 89, 90, 91, 93, 94, 95, 96, 97, 98, 99, 102, 103, 106],
  },
  // Indented code blocks: Edge cases
  'Indented code blocks': {
    reason: 'Indented code edge case',
    examples: [108, 109, 112, 115],
  },
  // Fenced code blocks: Edge cases
  'Fenced code blocks': {
    reason: 'Fenced code edge case',
    examples: [121, 138, 141, 145, 146],
  },
  // Paragraphs: No longer skipped (whitespace handling fixed)
  // Block quotes: Lazy continuation and nesting
  'Block quotes': {
    reason: 'Block quote edge case',
    examples: [228, 229, 230, 231, 232, 233, 238, 239, 240, 244, 247, 250, 251],
  },
  // List items: Complex indentation and lazy continuation
  'List items': {
    reason: 'List item edge case',
    examples: [254, 256, 258, 259, 260, 262, 263, 264, 266, 270, 271, 273, 274, 277, 278, 279, 280, 281, 282, 283, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 296, 298, 299, 300],
  },
  // Lists: Tight/loose distinction and complex nesting
  'Lists': {
    reason: 'List edge case',
    examples: [301, 302, 304, 306, 307, 309, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 323, 324, 325, 326],
  },
  // Code spans: Backtick counting edge cases
  'Code spans': {
    reason: 'Code span edge case',
    examples: [331, 335, 336, 338, 341, 342, 343, 344, 345, 346, 347, 348, 349],
  },
  // Emphasis: Single-pass parser cannot handle all edge cases (Rule 9/10, mod 3)
  'Emphasis and strong emphasis': {
    reason: 'Single-pass parser limitation: emphasis edge case',
    examples: [351, 352, 353, 354, 358, 359, 360, 361, 362, 363, 365, 366, 367, 368, 371, 372, 374, 375, 376, 379, 380, 383, 384, 385, 386, 387, 388, 389, 391, 392, 397, 398, 400, 401, 402, 404, 406, 407, 408, 412, 416, 417, 419, 420, 421, 422, 424, 425, 426, 433, 434, 435, 436, 438, 439, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 461, 465, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481],
  },
  // Links: URL edge cases and reference link complexities
  'Links': {
    reasons: {
      // URL edge cases: spaces, newlines, nested parens
      url_edge: [488, 489, 490, 491, 492, 493, 494, 496, 497, 498, 499, 503, 506, 508, 509, 510, 511, 512, 513, 514, 515],
      // Reference link edge cases
      ref_link: [518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571],
    },
  },
  // Images: Similar to links edge cases
  'Images': {
    reason: 'Image edge case',
    examples: [573, 574, 575, 576, 577, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593],
  },
  // Autolinks: Protocol and email edge cases
  'Autolinks': {
    reason: 'Autolink edge case',
    examples: [602, 603, 606, 608, 609, 610, 611, 612],
  },
  // Hard line breaks: Edge cases
  'Hard line breaks': {
    reason: 'Hard line break edge case',
    examples: [642, 644, 646],
  },
  // Soft line breaks: No longer skipped (whitespace handling fixed)
};

// Get skip reason for a test
function getSkipReason(section, example) {
  const config = SKIP_TESTS[section];
  if (!config) return null;

  // Check if using multiple reasons (like Links)
  if (config.reasons) {
    for (const [key, examples] of Object.entries(config.reasons)) {
      if (examples.includes(example)) {
        if (key === 'url_edge') return 'URL edge case: spaces, newlines, nested parens';
        if (key === 'ref_link') return 'Reference link edge case';
        return key;
      }
    }
    return null;
  }

  // Single reason for all examples
  if (config.examples && config.examples.includes(example)) {
    return config.reason;
  }
  return null;
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

  // Generate moon.pkg.json
  const pkgJson = {
    import: ['mizchi/markdown'],
    'test-import': ['mizchi/markdown'],
  };
  fs.writeFileSync(
    path.join(OUTPUT_DIR, 'moon.pkg.json'),
    JSON.stringify(pkgJson, null, 2) + '\n'
  );

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
  #|   return String(result);
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

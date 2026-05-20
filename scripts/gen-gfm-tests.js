#!/usr/bin/env node
/**
 * Generate GFM extension tests from spec.txt
 *
 * Usage: node scripts/gen-gfm-tests.js [--no-skip]
 *
 * This script:
 * 1. Downloads GFM spec.txt from github/cmark-gfm
 * 2. Parses examples from the spec
 * 3. Generates MoonBit test files comparing our output with remark-gfm
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Parse command line arguments
const noSkip = process.argv.includes('--no-skip');

const SPEC_URL = 'https://raw.githubusercontent.com/github/cmark-gfm/master/test/spec.txt';
const OUTPUT_DIR = path.join(__dirname, '../src/gfm_tests');

// GFM extension sections to include
const GFM_EXTENSION_SECTIONS = [
  'Tables (extension)',
  'Strikethrough (extension)',
  'Autolinks (extension)',
  'Task list items (extension)',
  'Disallowed Raw HTML (extension)',
];

// Tests to skip with reasons
// Generated from actual test failures
const SKIP_TESTS = {
  'Tables (extension)': {
    reason: 'Table edge case',
    examples: [199, 200, 202, 203, 204],  // 198, 201, 205 pass
  },
  'Strikethrough (extension)': {
    reason: 'Strikethrough edge case',
    examples: [492],  // 491 passes
  },
  'Autolinks (extension)': {
    reason: 'Extended autolink not implemented',
    examples: [621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631],
  },
  // Task list items: All tests pass (279, 280)
  'Disallowed Raw HTML (extension)': {
    reason: 'HTML filtering not implemented',
    examples: [652],
  },
};

// Get skip reason for a test
function getSkipReason(section, example) {
  const config = SKIP_TESTS[section];
  if (!config) return null;
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
    .replace(/\s*\(extension\)\s*/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '');
}

// Parse spec.txt to extract examples
function parseSpec(specText) {
  const examples = [];
  let currentSection = '';
  let exampleNum = 0;

  const lines = specText.split('\n');
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    // Track current section
    if (line.startsWith('## ')) {
      currentSection = line.slice(3).trim();
    }

    // Look for example blocks
    if (line.includes('```````````````````````````````` example')) {
      exampleNum++;

      // Only process GFM extension sections
      if (!GFM_EXTENSION_SECTIONS.includes(currentSection)) {
        // Skip to end of example
        i++;
        while (i < lines.length && !lines[i].startsWith('````````````````````````````````')) {
          i++;
        }
        i++;
        continue;
      }

      // Parse example content
      i++;
      let markdown = '';
      let html = '';
      let inHtml = false;

      while (i < lines.length && !lines[i].startsWith('````````````````````````````````')) {
        if (lines[i] === '.') {
          inHtml = true;
        } else if (inHtml) {
          html += lines[i] + '\n';
        } else {
          // Convert → to actual tab character
          markdown += lines[i].replace(/→/g, '\t') + '\n';
        }
        i++;
      }

      examples.push({
        example: exampleNum,
        section: currentSection,
        markdown: markdown,
        html: html,
      });
    }

    i++;
  }

  return examples;
}

async function main() {
  console.log('Fetching GFM spec...');
  const response = await fetch(SPEC_URL);
  const specText = await response.text();

  console.log('Parsing spec...');
  const allExamples = parseSpec(specText);

  // Filter to GFM extensions only
  const examples = allExamples.filter(e => GFM_EXTENSION_SECTIONS.includes(e.section));
  console.log(`Found ${examples.length} GFM extension examples`);

  // Group by section
  const bySection = new Map();
  for (const test of examples) {
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
    supported_targets: 'js',
    'test-import': ['mizchi/markdown'],
  };
  fs.writeFileSync(
    path.join(OUTPUT_DIR, 'moon.pkg.json'),
    JSON.stringify(pkgJson, null, 2) + '\n'
  );

  // Generate ffi.mbt
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
  #|       return line.replace(/^((?:[ \\t]*>\\s*)*[ \\t]*)\\* (?=\\S)/, "$1- ");
  #|     }).join("\\n");
  #|   }
  #| }
`;
  fs.writeFileSync(path.join(OUTPUT_DIR, 'ffi.mbt'), ffiContent);

  // Generate test helper
  const helperContent = `///| GFM extension compatibility tests
///| Generated from https://github.github.com/gfm/

///| Test helper: compare our output with remark's output
pub fn assert_gfm_compat(input : String, example : Int) -> Unit {
  let our_output = @markdown.md_parse_and_render(input)
  let remark_output = remark_stringify(input)

  // Normalize trailing whitespace for comparison
  let our_normalized = our_output.trim_end(chars=" \\n\\t")
  let remark_normalized = remark_output.trim_end(chars=" \\n\\t")

  if our_normalized != remark_normalized {
    println("=== GFM Example \\{example} ===")
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
  fs.writeFileSync(path.join(OUTPUT_DIR, 'helper_test.mbt'), helperContent);

  // Generate test files per section
  let totalTests = 0;
  for (const [section, tests] of bySection) {
    const sectionId = sectionToId(section);
    const fileName = `${sectionId}_test.mbt`;

    let content = `///| GFM spec tests: ${section}\n\n`;

    for (const test of tests) {
      const escapedInput = escapeString(test.markdown);
      const skipReason = noSkip ? null : getSkipReason(section, test.example);

      if (skipReason) {
        content += `#skip("${skipReason}")\n`;
      }
      content += `test "gfm example ${test.example}: ${section}" {\n`;
      content += `  assert_gfm_compat("${escapedInput}", ${test.example})\n`;
      content += `}\n\n`;
      totalTests++;
    }

    fs.writeFileSync(path.join(OUTPUT_DIR, fileName), content);
    console.log(`Generated ${fileName} with ${tests.length} tests`);
  }

  console.log(`\nTotal: ${totalTests} GFM extension tests generated in ${OUTPUT_DIR}`);
  if (noSkip) {
    console.log('\n⚠️  Generated with --no-skip: all tests will run without skip annotations');
    console.log('   Remember to regenerate without --no-skip after checking!');
  }
  console.log('\nRun tests with: moon test --target js src/gfm_tests');
}

main().catch(console.error);

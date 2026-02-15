import { markdown } from './gen/markdown-component.js';
import assert from 'node:assert/strict';

// Test 1: md-to-html
{
  const html = markdown.mdToHtml('# Hello\n\nWorld');
  assert(html.includes('<h1>'), `Expected <h1> in: ${html}`);
  assert(html.includes('Hello'), `Expected Hello in: ${html}`);
  assert(html.includes('<p>'), `Expected <p> in: ${html}`);
  assert(html.includes('World'), `Expected World in: ${html}`);
  console.log('PASS: md-to-html');
}

// Test 2: md-to-ast-json
{
  const json = markdown.mdToAstJson('# Test');
  const ast = JSON.parse(json);
  assert(ast.children, 'AST should have children');
  assert(ast.children.length > 0, 'AST should have at least one child');
  console.log('PASS: md-to-ast-json');
}

// Test 3: md-serialize
{
  const md = markdown.mdSerialize('# Hello\n\nWorld\n');
  assert(md.includes('# Hello'), `Expected # Hello in: ${md}`);
  assert(md.includes('World'), `Expected World in: ${md}`);
  console.log('PASS: md-serialize');
}

console.log('All tests passed!');

import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const manifest = readFileSync(join(root, "moon.mod"), "utf8");
const version = manifest.match(/^version = "([^"]+)"$/m)?.[1];
if (!version) throw new Error("Missing module version");
const archive = resolve(process.argv[2] ?? join(root, "_build/publish", "mizchi-markdown-" + version + ".zip"));
const entries = execFileSync("unzip", ["-Z", "-1", archive], { encoding: "utf8" }).split("\n");
const legacy = entries.filter((entry) => /(^|\/)moon\.(mod|pkg)\.json$/.test(entry));
if (legacy.length) throw new Error("Legacy manifests in package:\n" + legacy.join("\n"));

const temporary = mkdtempSync(join(tmpdir(), "markdown-package-"));
const packaged = join(temporary, "package");
const consumer = join(temporary, "consumer");
const moon = (cwd, ...args) => execFileSync("moon", args, { cwd, stdio: "inherit" });
try {
  mkdirSync(packaged);
  execFileSync("unzip", ["-q", archive, "-d", packaged]);
  // No repository .mooncakes cache or local dependency overrides are copied.
  moon(packaged, "check", "--target", "all", "--warn-list", "-a");
  moon(packaged, "doc");
  moon(join(packaged, "benches"), "check", "--target", "all", "--warn-list", "-a");
  moon(join(packaged, "component"), "build", "--target", "wasm", "--release", "--warn-list", "-a");

  mkdirSync(consumer);
  writeFileSync(join(temporary, "moon.work"), 'members = ["./package", "./consumer"]\n');
  writeFileSync(join(consumer, "moon.mod"), 'name = "test/markdown_consumer"\nimport { "mizchi/markdown@' + version + '" }\n');
  writeFileSync(join(consumer, "moon.pkg"), 'import { "mizchi/markdown" }\n');
  writeFileSync(join(consumer, "consumer_test.mbt"), [
    'test "packaged Markdown API" {',
    '  let result = @markdown.parse("# Hello\\n\\nWorld\\n")',
    '  assert_eq(result.document.children.length(), 3)',
    '  assert_eq(@markdown.md_to_html("# Hello\\n"), "<h1>Hello</h1>\\n")',
    '}',
    '',
  ].join("\n"));
  moon(consumer, "test", ".", "--target", "all", "--warn-list", "-a");
  console.log("Verified mizchi/markdown@" + version + " from " + archive);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}

# Playground Editor フォント化と VRT 導入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Playground エディタに日本語対応の等幅フォント (PlemolJP) を導入し、textarea とハイライトオーバーレイの文字幅が CI で検証されるようにする。

**Architecture:** フォント設定を `.mono` class に集約して editor/overlay/simple-editor/line-numbers/preview code に一律適用する。`Range.getBoundingClientRect()` で overlay の行末位置を実測し、canvas `measureText` で textarea 理論幅と比較する幾何検証を必須ゲート、`toHaveScreenshot` を補助ゲートとして Playwright に載せる。

**Tech Stack:** PlemolJP (SIL OFL woff2), Playwright (Chromium), Luna UI (JSX), just, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-04-10-playground-editor-font-and-vrt-design.md`

---

## 前提

- 作業は本プランを含む feature ブランチで行う（既に worktree で開始済みなら不要）。
- Node.js v24+, pnpm が使える。
- MoonBit CLI がローカルで使える（`moon build --target js` が通る）。
- 既存の dev server は port 5188。Playwright 設定はそのまま使用。
- **Refactoring 方針**: `.mono` class はフォント family/weight/letter-spacing/feature-settings のみを担当し、font-size と line-height は各使用箇所で決める。これにより preview (13px) と editor (14px) でサイズは保ったまま、family の単一化が実現できる。

---

## File Structure

**新規作成:**
- `playground/public/fonts/PlemolJP-Regular.woff2` — 同梱する日本語等幅フォント本体
- `playground/public/fonts/OFL.txt` — PlemolJP の SIL OFL 1.1 ライセンス原文
- `playground/styles/editor-font.css` — `@font-face` と `.mono` class 定義
- `e2e/fixtures/width-fixture.md` — VRT 用固定マークダウン
- `e2e/helpers/measure-line.ts` — textarea/overlay 行幅計測ヘルパ
- `e2e/vrt-width.spec.ts` — 幾何検証テスト (必須ゲート)
- `e2e/vrt-screenshot.spec.ts` — スクリーンショット VRT (補助ゲート)
- `justfile` — リポジトリルートに新規作成、`vrt` / `vrt-update` を追加

**変更:**
- `playground/index.html` — `.mono` を読み込み、editor/preview の font-family を剥がす、`.editor-highlight` の font-weight guard 追加
- `playground/SyntaxHighlightEditor.tsx` — textarea / highlight / line-numbers に `mono` class を追加
- `playground/main.tsx` — `SimpleEditor` の textarea に `mono` class を追加
- `playground/ast-renderer.tsx` — preview 内の `<code>` / `<pre><code>` に `mono` class を追加
- `.github/workflows/ci.yml` — `vrt` ジョブを新規追加（既存 `test` ジョブは変更しない）
- `README.md` — Credits に PlemolJP 表記追加

---

## Task 1: PlemolJP フォントファイルとライセンスを配置する

**Files:**
- Create: `playground/public/fonts/PlemolJP-Regular.woff2`
- Create: `playground/public/fonts/OFL.txt`

- [ ] **Step 1: PlemolJP Regular woff2 を入手して配置する**

`yuru7/PlemolJP` の最新リリース v3.0.0 から `PlemolJP_HS_v3.0.0.zip`（HS = 半角ASCII/全角CJKの 1:2 比率版）をダウンロードし、内部の `PlemolJP_HS/PlemolJP-Regular.ttf` を woff2 に変換して配置する。変換は以下で行う:

```bash
# 一時作業ディレクトリで
mkdir -p /tmp/plemoljp && cd /tmp/plemoljp
curl -L -o plemoljp.zip "https://github.com/yuru7/PlemolJP/releases/download/v3.0.0/PlemolJP_HS_v3.0.0.zip"
unzip -o plemoljp.zip
# 展開後 PlemolJP_HS/ 内に ttf 群が存在する。Regular を woff2 化。
pnpm dlx ttf2woff2 < PlemolJP_HS/PlemolJP-Regular.ttf > PlemolJP-Regular.woff2
# 結果を repo に配置
cp PlemolJP-Regular.woff2 /Users/mz/ghq/github.com/mizchi/markdown.mbt/playground/public/fonts/
```

**バージョンが変わっていた場合**: `gh release list -R yuru7/PlemolJP` または https://github.com/yuru7/PlemolJP/releases で最新の `PlemolJP_HS_v*.zip` を探す。woff2 出力サイズは 2〜4MB 程度が期待値。ttf2woff2 は stdin/stdout で受け渡す CLI なので `<` `>` のリダイレクトが必要。

確認:

```bash
ls -lh playground/public/fonts/PlemolJP-Regular.woff2
file playground/public/fonts/PlemolJP-Regular.woff2
```

Expected: woff2 ファイルが存在、`file` コマンドで `Web Open Font Format (Version 2)` と表示される。

- [ ] **Step 2: SIL OFL 1.1 ライセンス原文を配置する**

PlemolJP リポジトリの `LICENSE` ファイル（SIL OFL 1.1 原文）を `playground/public/fonts/OFL.txt` としてコピーする:

```bash
curl -L -o playground/public/fonts/OFL.txt https://raw.githubusercontent.com/yuru7/PlemolJP/main/LICENSE
head -3 playground/public/fonts/OFL.txt
```

Expected: `Copyright 2022 The PlemolJP Project Authors` のような行が含まれる SIL OFL 1.1 テキスト。

- [ ] **Step 3: README に Credits を追記する**

`README.md` の末尾（既存内容の後）に以下を追加:

```markdown
## Credits

- Fonts: [PlemolJP](https://github.com/yuru7/PlemolJP) (SIL Open Font License 1.1) — bundled in `playground/public/fonts/`
```

`Credits` セクションが既にあれば下に追記する。

- [ ] **Step 4: コミット**

```bash
git add playground/public/fonts/PlemolJP-Regular.woff2 playground/public/fonts/OFL.txt README.md
git commit -m "feat(playground): bundle PlemolJP font with SIL OFL license"
```

---

## Task 2: `.mono` class と @font-face を定義する

**Files:**
- Create: `playground/styles/editor-font.css`

- [ ] **Step 1: `editor-font.css` を作成する**

`playground/styles/editor-font.css` に以下を書く:

```css
/* PlemolJP — Japanese monospace font used by the playground editor.
   Bundled in playground/public/fonts/. License: SIL OFL 1.1 (see OFL.txt). */
@font-face {
  font-family: 'PlemolJP';
  src: url('/fonts/PlemolJP-Regular.woff2') format('woff2');
  font-weight: 400;
  font-style: normal;
  /* block: 初期描画を必ずこのフォントで行う。swap/fallback だと VRT が
     ロード競合でぶれるため採用しない。 */
  font-display: block;
  unicode-range: U+0000-FFFF, U+10000-1FFFF;
}

/* Single source of truth for monospace typography in the playground.
   Apply this class to every element whose width must line up pixel-perfect
   with .editor-textarea (the transparent cursor layer). Do NOT add
   font-weight, font-style, letter-spacing, or font-feature-settings in
   downstream selectors — it WILL cause cursor drift. */
.mono {
  font-family: 'PlemolJP', ui-monospace, Monaco, Menlo, Consolas, monospace;
  font-weight: 400;
  font-style: normal;
  letter-spacing: 0;
  font-feature-settings: normal;
  font-variant-ligatures: none;
  font-kerning: none;
  tab-size: 2;
}
```

注意: **font-size と line-height は `.mono` に入れない**。preview は 13px、editor は 14px と使い分けるため、サイズは各 consumer の既存 CSS に委ねる。

- [ ] **Step 2: コミット**

```bash
git add playground/styles/editor-font.css
git commit -m "feat(playground): add .mono class and @font-face for PlemolJP"
```

---

## Task 3: `index.html` に editor-font.css を読み込ませフォント指定を剥がす

**Files:**
- Modify: `playground/index.html`

- [ ] **Step 1: `<head>` に editor-font.css を追加する**

`playground/index.html` の既存 `<title>Markdown.mbt Playground</title>` の直後に以下を追加:

```html
  <title>Markdown.mbt Playground</title>
  <link rel="preload" href="/fonts/PlemolJP-Regular.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="/styles/editor-font.css">
```

- [ ] **Step 2: `.line-numbers` から font-family / font-size / line-height を剥がす**

`.line-numbers` rule を次のように変更:

```css
    .line-numbers {
      background: var(--bg-secondary);
      color: var(--text-secondary);
      padding: 16px 0;
      text-align: right;
      user-select: none;
      font-size: 14px;
      line-height: 1.5;
      min-width: 50px;
      border-right: 1px solid var(--border-color);
    }
```

削除したのは `font-family: 'Monaco', 'Menlo', 'Consolas', monospace;` の 1 行のみ。`.mono` class で family を当てる。

- [ ] **Step 3: `.editor-textarea, .editor-highlight` の combined rule から font-family を剥がす**

次のように変更:

```css
    .editor-textarea,
    .editor-highlight {
      font-size: 14px;
      line-height: 1.5;
      padding: 16px 16px 50vh 24px;
      margin: 0;
      border: none;
      white-space: pre-wrap;
      word-wrap: break-word;
      overflow-wrap: break-word;
    }
```

削除したのは `font-family: 'Monaco', 'Menlo', 'Consolas', monospace;` と `tab-size: 2;` の 2 行（両方 `.mono` 側で担保）。

- [ ] **Step 4: `.editor-highlight` に font-weight guard を追加する**

`.editor-highlight` rule を次のように変更:

```css
    .editor-highlight {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      min-height: 100%;
      pointer-events: none;
      z-index: 1;
      color: var(--text-primary);
      /* Guard: even if a descendant span accidentally applies font-weight,
         the overlay must stay regular-weight to match the textarea width. */
      font-weight: 400 !important;
    }
```

- [ ] **Step 5: `.simple-editor` から font-family / tab-size を剥がす**

`.simple-editor` rule を次のように変更:

```css
    .simple-editor {
      width: 100%;
      max-width: 900px;
      height: 100%;
      font-size: 14px;
      line-height: 1.5;
      padding: 16px;
      padding-bottom: 50vh;
      margin: 0;
      border: none;
      border-left: 1px solid var(--border-color);
      border-right: 1px solid var(--border-color);
      background: var(--bg-primary);
      color: var(--text-primary);
      resize: none;
      outline: none;
      white-space: pre-wrap;
      word-wrap: break-word;
      overflow-wrap: break-word;
    }
```

削除したのは `font-family: 'Monaco', 'Menlo', 'Consolas', monospace;` と `tab-size: 2;` の 2 行。

- [ ] **Step 6: `.preview code` から font-family を剥がす**

`.preview code` rule を次のように変更:

```css
    .preview code {
      font-size: 13px;
      background: var(--code-bg);
      padding: 0.2em 0.4em;
      border-radius: 3px;
    }
```

削除したのは `font-family: 'Monaco', 'Menlo', 'Consolas', monospace;` の 1 行。

- [ ] **Step 7: dev server で最低限の動作確認（手動）**

```bash
pnpm vite --port 5188 &
sleep 2
curl -sI http://localhost:5188/fonts/PlemolJP-Regular.woff2 | head -3
curl -sI http://localhost:5188/styles/editor-font.css | head -3
# 止める
kill %1 2>/dev/null
```

Expected: どちらも `HTTP/1.1 200 OK` で応答。

- [ ] **Step 8: コミット**

```bash
git add playground/index.html
git commit -m "refactor(playground): remove inline font-family, load editor-font.css"
```

---

## Task 4: `SyntaxHighlightEditor.tsx` に `mono` class を追加する

**Files:**
- Modify: `playground/SyntaxHighlightEditor.tsx`

- [ ] **Step 1: textarea と highlight div に `mono` を追加する**

`SyntaxHighlightEditor` 関数の return 文 (現行 774 行目付近) を次のように変更:

```tsx
  return (
    <div class="syntax-editor-container">
      {props.showLineNumbers && (
        <div class="line-numbers mono" ref={(el) => { lineNumbersRef = el as HTMLDivElement; }}>
          <For each={lineNumbersArray}>
            {(num) => <div class="line-number">{num}</div>}
          </For>
        </div>
      )}
      <div class="editor-wrapper" ref={(el) => { wrapperRef = el as HTMLDivElement; }}>
        <div class="editor-content">
          <div class="editor-highlight mono" ref={(el) => { highlightRef = el as HTMLDivElement; }}></div>
          <textarea
            ref={(el) => setupEditor(el as HTMLTextAreaElement)}
            class="editor-textarea mono"
            onBeforeInput={handleBeforeInput}
            onInput={handleInput}
            onScroll={syncScroll}
            onKeyDown={handleKeyDown}
            onKeyUp={handleCursorUpdate}
            onClick={handleCursorUpdate}
            spellcheck={false}
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
          />
        </div>
      </div>
    </div>
  );
```

変更点は 3 箇所のみ: `line-numbers` → `line-numbers mono`、`editor-highlight` → `editor-highlight mono`、`editor-textarea` → `editor-textarea mono`。

- [ ] **Step 2: 型チェック**

```bash
pnpm exec tsc --noEmit
```

Expected: エラーなし。

- [ ] **Step 3: コミット**

```bash
git add playground/SyntaxHighlightEditor.tsx
git commit -m "feat(playground): apply .mono to highlight editor elements"
```

---

## Task 5: `main.tsx` の SimpleEditor に `mono` を追加する

**Files:**
- Modify: `playground/main.tsx`

- [ ] **Step 1: SimpleEditor の textarea class を変更する**

`main.tsx` の `SimpleEditor` 関数内 (現行 236-244 行目付近) を次のように変更:

```tsx
  return (
    <textarea
      ref={(el) => setupTextarea(el as HTMLTextAreaElement)}
      class="simple-editor mono"
      onInput={handleInput}
      onKeyUp={handleCursorUpdate}
      onClick={handleCursorUpdate}
      spellcheck={false}
    />
  );
```

変更点は `class="simple-editor"` → `class="simple-editor mono"` の 1 箇所のみ。

- [ ] **Step 2: 型チェック**

```bash
pnpm exec tsc --noEmit
```

Expected: エラーなし。

- [ ] **Step 3: コミット**

```bash
git add playground/main.tsx
git commit -m "feat(playground): apply .mono to simple editor"
```

---

## Task 6: `ast-renderer.tsx` の preview code 出力に `mono` を追加する

**Files:**
- Modify: `playground/ast-renderer.tsx`

- [ ] **Step 1: code block fallback の `<code>` に mono を追加する**

`ast-renderer.tsx` 内、`case "code":` ブロックの fallback (現行 208-212 行付近) を次のように変更:

```tsx
      // Fallback for unsupported languages
      return (
        <pre key={key} data-span={span}>
          <code class={lang ? `language-${lang} mono` : "mono"}>{block.value}</code>
        </pre>
      );
```

- [ ] **Step 2: inline code の `<code>` に mono を追加する**

同ファイルの inline code 出力 (現行 413 行目付近) を次のように変更:

```tsx
      return <code key={key} class="mono">{inline.value}</code>;
```

- [ ] **Step 3: syntree 経由の highlight 出力で mono を継承させる**

syntree の highlight 出力は `RawHtml` で挿入されるため、そのルート `<pre>` に class を付けられない。代わりに `.preview pre` に `.mono` 的なフォント継承を効かせたいが、ここでは `.preview code, .preview pre { font-family: inherit; }` を index.html に追加する方針を取らず、`RawHtml` の outer を `<div class="mono">` で包むパッチを当てる。

`case "code":` の該当ブロック (現行 196-205 行付近) を次のように変更:

```tsx
      if (highlighted) {
        // Use highlighted HTML from syntree (highlight format).
        // Wrap with .mono so inner <pre><code> inherits PlemolJP.
        return (
          <div class="mono" key={key}>
            <RawHtml
              data-span={span}
              html={highlighted}
            />
          </div>
        );
      }
```

ただしラッパ div は block レイアウトを変えないように注意。問題があれば次ステップの手動確認で調整する。

- [ ] **Step 4: 型チェックと手動確認**

```bash
pnpm exec tsc --noEmit
```

Expected: エラーなし。

続いて dev server を立ち上げて目視確認:

```bash
pnpm vite --port 5188 &
sleep 2
```

ブラウザで http://localhost:5188/ を開き、preview の code block / inline code が PlemolJP で描画されていることを確認（日本語混在の行を手で入力して幅が崩れないか見る）。確認できたら `kill %1` で止める。

- [ ] **Step 5: コミット**

```bash
git add playground/ast-renderer.tsx
git commit -m "feat(playground): apply .mono to preview code elements"
```

---

## Task 7: VRT 用 fixture を作成する

**Files:**
- Create: `e2e/fixtures/width-fixture.md`

- [ ] **Step 1: fixture を作成する**

Write ツールで `e2e/fixtures/width-fixture.md` を作成する。ファイル内容は以下の 30 行ちょうど（先頭の `# VRT Width Fixture` から末尾の閉じフェンス ``` まで）。**各行は半角換算 60 文字以内**（`.editor-content` の max-width 900px で折り返さないため）:

````
# VRT Width Fixture

Normal paragraph with ASCII only.

**bold** and *italic* and ***both*** and `inline code`.

- [ ] Unchecked task item
- [x] Checked task item
- [ ] Mixed 日本語タスク with ASCII 123
- regular list item

> blockquote with 日本語 content

日本語のみの段落。半角全角比 1:2 を厳密に保つ行。

| col1 | 日本語 | 3 |
|------|--------|---|
| a    | い     | 3 |

[link text](https://example.com) then ![alt](x.png)

---

```ts
const x: number = 42; // 日本語コメント
function greet(name: string) { return name; }
```
````

上の外側の 4 バッククォートは plan 表記上のエスケープで、**ファイル本体には 4 バッククォート行は含めない**。ファイル先頭は `# VRT Width Fixture`、末尾は 3 バッククォートの閉じフェンス ``` で終わる。

実ファイルの確認:

```bash
awk '{ print length, $0 }' e2e/fixtures/width-fixture.md | sort -rn | head -5
```

Expected: 最大行長が 60 以下（日本語 1 文字は awk 上複数バイトとして数えられるので、日本語を含む行は 60 を超えても良い。ASCII のみの行が 60 以内であることを目視で確認）。

```bash
grep -P '\t' e2e/fixtures/width-fixture.md && echo "TAB FOUND - remove it" || echo "no tabs"
```

Expected: `no tabs`

- [ ] **Step 2: コミット**

```bash
git add e2e/fixtures/width-fixture.md
git commit -m "test(e2e): add width fixture for VRT"
```

---

## Task 8: 計測ヘルパ `measure-line.ts` を作成する

**Files:**
- Create: `e2e/helpers/measure-line.ts`

- [ ] **Step 1: helper ファイルを作成する**

`e2e/helpers/measure-line.ts`:

```ts
import type { Page } from '@playwright/test';

export interface LineMeasurement {
  idx: number;
  src: string;
  textareaWidth: number;
  overlayWidth: number;
  drift: number;
  overlayHeight: number;
  wrapped: boolean;
}

/**
 * For each line in the editor, compute the theoretical width of the textarea
 * text (via canvas measureText) and compare against the actual rendered width
 * of the overlay (via Range.getBoundingClientRect on the .highlight-line div).
 *
 * Returns one entry per source line. Wrapped lines are flagged so tests can
 * fail loudly instead of reporting misleading drift.
 */
export async function measureLineDrift(page: Page): Promise<LineMeasurement[]> {
  return page.evaluate(() => {
    const ta = document.querySelector('.editor-textarea') as HTMLTextAreaElement | null;
    const hl = document.querySelector('.editor-highlight') as HTMLElement | null;
    if (!ta || !hl) throw new Error('editor not found');

    const lines = Array.from(hl.querySelectorAll('.highlight-line')) as HTMLElement[];
    const srcLines = ta.value.split('\n');

    const style = getComputedStyle(ta);
    const lineHeightPx = parseFloat(style.lineHeight);
    const fontShorthand = `${style.fontStyle} ${style.fontVariant} ${style.fontWeight} ${style.fontSize}/${style.lineHeight} ${style.fontFamily}`;
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('canvas 2d context unavailable');
    ctx.font = fontShorthand;

    const results: Array<{
      idx: number;
      src: string;
      textareaWidth: number;
      overlayWidth: number;
      drift: number;
      overlayHeight: number;
      wrapped: boolean;
    }> = [];

    for (let i = 0; i < srcLines.length; i++) {
      const src = srcLines[i] ?? '';
      const taWidth = ctx.measureText(src).width;

      let overlayWidth = 0;
      let overlayHeight = 0;
      const lineEl = lines[i];
      if (lineEl) {
        const range = document.createRange();
        range.selectNodeContents(lineEl);
        const rect = range.getBoundingClientRect();
        overlayWidth = rect.width;
        overlayHeight = rect.height;
        range.detach?.();
      }

      // Consider the line wrapped when the rendered height exceeds one line.
      // Add 1px tolerance for fractional rounding.
      const wrapped = overlayHeight > lineHeightPx + 1;

      results.push({
        idx: i,
        src,
        textareaWidth: taWidth,
        overlayWidth,
        drift: Math.abs(taWidth - overlayWidth),
        overlayHeight,
        wrapped,
      });
    }
    return results;
  });
}
```

- [ ] **Step 2: 型チェック**

```bash
pnpm exec tsc --noEmit
```

Expected: エラーなし。

- [ ] **Step 3: コミット**

```bash
git add e2e/helpers/measure-line.ts
git commit -m "test(e2e): add measureLineDrift helper for width VRT"
```

---

## Task 9: 幾何検証テスト `vrt-width.spec.ts` を作成する

**Files:**
- Create: `e2e/vrt-width.spec.ts`

- [ ] **Step 1: テストファイルを作成する**

`e2e/vrt-width.spec.ts`:

```ts
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { measureLineDrift } from './helpers/measure-line';

const FIXTURE = readFileSync(
  resolve(__dirname, 'fixtures/width-fixture.md'),
  'utf8',
);

const DRIFT_TOLERANCE_PX = 0.5;

for (const theme of ['light', 'dark'] as const) {
  test(`VRT width: fixture lines align (${theme})`, async ({ page }) => {
    await page.goto('/');
    await page.evaluate((t) => {
      localStorage.clear();
      localStorage.setItem('theme', t);
      indexedDB.deleteDatabase('markdown-editor');
    }, theme);
    await page.reload();

    await page.waitForSelector('.syntax-editor-container', { timeout: 15000 });
    await page.evaluate(() => (document as any).fonts.ready);

    // Inject fixture and trigger the editor's input pipeline.
    await page.evaluate((text) => {
      const ta = document.querySelector('.editor-textarea') as HTMLTextAreaElement;
      ta.value = text;
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    }, FIXTURE);
    await page.waitForTimeout(300);

    const drifts = await measureLineDrift(page);

    // 1. No wrapped lines — fixture is designed to fit in one row each.
    const wrapped = drifts.filter((d) => d.wrapped);
    expect(wrapped, `wrapped lines detected:\n${JSON.stringify(wrapped, null, 2)}`).toHaveLength(0);

    // 2. Per-line drift within tolerance. Empty lines with zero overlay width
    //    are treated as aligned.
    const offending = drifts.filter(
      (d) =>
        d.drift > DRIFT_TOLERANCE_PX &&
        !(d.src.trim() === '' && d.overlayWidth === 0),
    );
    expect(
      offending,
      `lines with drift > ${DRIFT_TOLERANCE_PX}px:\n${JSON.stringify(offending, null, 2)}`,
    ).toHaveLength(0);
  });
}
```

- [ ] **Step 2: テストを実行して緑を確認する**

```bash
pnpm playwright test e2e/vrt-width.spec.ts --reporter=line
```

Expected: 2 tests passed (light / dark)。もしネットワークやフォントロードで不安定なら `page.evaluate(() => document.fonts.ready)` の位置を `waitForTimeout` の後ろに動かして再実行。

もし `offending` が 0 でない場合:
- ログに出ているドリフト行を見て、CSS で拾いきれていない font-family 指定が残っていないかを確認する
- `.editor-textarea` と `.editor-highlight` の `getComputedStyle` を `page.evaluate` で出力して `fontFamily` が `"PlemolJP"` を先頭に含むかを verify

- [ ] **Step 3: 意図的なバグで fail を verify する**

`playground/index.html` の `.editor-highlight { font-weight: 400 !important; }` を一時的に `font-weight: 700 !important;` に変更:

```bash
pnpm playwright test e2e/vrt-width.spec.ts --reporter=line
```

Expected: 少なくとも 1 行で drift がしきい値を超えて FAIL する。verify できたら即座に `400 !important` に revert して動作確認:

```bash
pnpm playwright test e2e/vrt-width.spec.ts --reporter=line
```

Expected: 再び 2 passed。

- [ ] **Step 4: コミット**

```bash
git add e2e/vrt-width.spec.ts
git commit -m "test(e2e): add width alignment VRT for editor overlay"
```

---

## Task 10: スクリーンショット VRT `vrt-screenshot.spec.ts` を作成する

**Files:**
- Create: `e2e/vrt-screenshot.spec.ts`

- [ ] **Step 1: テストファイルを作成する**

`e2e/vrt-screenshot.spec.ts`:

```ts
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const FIXTURE = readFileSync(
  resolve(__dirname, 'fixtures/width-fixture.md'),
  'utf8',
);

for (const theme of ['light', 'dark'] as const) {
  test(`VRT screenshot: editor renders consistently (${theme})`, async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto('/');
    await page.evaluate((t) => {
      localStorage.clear();
      localStorage.setItem('theme', t);
      indexedDB.deleteDatabase('markdown-editor');
    }, theme);
    await page.reload();

    await page.waitForSelector('.syntax-editor-container', { timeout: 15000 });
    await page.evaluate(() => (document as any).fonts.ready);

    await page.evaluate((text) => {
      const ta = document.querySelector('.editor-textarea') as HTMLTextAreaElement;
      ta.value = text;
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    }, FIXTURE);
    await page.waitForTimeout(400);

    const editor = page.locator('.editor-wrapper').first();
    await expect(editor).toHaveScreenshot(`editor-${theme}.png`, {
      maxDiffPixelRatio: 0.002,
    });
  });
}
```

- [ ] **Step 2: ベースラインを生成する**

```bash
pnpm playwright test e2e/vrt-screenshot.spec.ts --update-snapshots --reporter=line
```

Expected: 2 snapshot files が `e2e/vrt-screenshot.spec.ts-snapshots/` に保存される。目視で `editor-light.png` と `editor-dark.png` を開いて、チェックリスト行の `[ ]` と日本語テキストが歪んでいないことを確認する:

```bash
ls e2e/vrt-screenshot.spec.ts-snapshots/
```

- [ ] **Step 3: 再実行して緑を確認する**

```bash
pnpm playwright test e2e/vrt-screenshot.spec.ts --reporter=line
```

Expected: 2 tests passed。

**注意**: ベースラインはマシン固有のレンダリング差が混ざる可能性があるため、この段階ではあくまでローカル参照。CI で Ubuntu 上のベースラインに差し替える工程は Task 12 で行う。

- [ ] **Step 4: コミット**

```bash
git add e2e/vrt-screenshot.spec.ts e2e/vrt-screenshot.spec.ts-snapshots/
git commit -m "test(e2e): add editor screenshot VRT with light/dark baselines"
```

---

## Task 11: `justfile` に VRT タスクを追加する

**Files:**
- Create: `justfile` (リポジトリルートに新規)

- [ ] **Step 1: justfile を作成する**

`justfile` (リポジトリルート):

```makefile
# Task runner for markdown.mbt

default:
    @just --list

# Run VRT (geometry + screenshot).
vrt:
    pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts

# Regenerate screenshot VRT baselines. Use after an intentional UI change.
vrt-update:
    pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts --update-snapshots
```

- [ ] **Step 2: 実行して緑を確認する**

```bash
just vrt
```

Expected: 4 tests passed (width-light, width-dark, screenshot-light, screenshot-dark)。

`just` が無い場合は `brew install just` または `cargo install just` を案内する。今回は CI では直接 `pnpm playwright test` を呼ぶため、ローカル利便ツールとして追加するのみ。

- [ ] **Step 3: コミット**

```bash
git add justfile
git commit -m "chore: add justfile with vrt / vrt-update tasks"
```

---

## Task 12: GitHub Actions に `vrt` ジョブを追加する

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: `vrt` ジョブを追加する**

`.github/workflows/ci.yml` の `jobs:` 配下に `test:` の次として `vrt:` ジョブを追加する（`test:` ジョブは変更しない）:

```yaml
  vrt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install MoonBit CLI
        run: |
          curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
          echo "$HOME/.moon/bin" >> "$GITHUB_PATH"
      - name: Set up pnpm
        uses: pnpm/action-setup@v4
        with:
          run_install: false
      - uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: "pnpm"
      - name: Install dependencies
        run: pnpm install --frozen-lockfile
      - name: Build MoonBit JS artifacts
        run: |
          moon update
          moon build --target js
      - name: Install Playwright browsers
        run: pnpm playwright install --with-deps chromium
      - name: Run VRT
        run: pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts --reporter=line
      - name: Upload Playwright report on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-report
          path: |
            playwright-report/
            test-results/
          retention-days: 7
```

- [ ] **Step 2: ローカルで YAML の構文を検証する**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo OK
```

Expected: `OK`

- [ ] **Step 3: コミット**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add VRT job for editor width and screenshot tests"
```

- [ ] **Step 4: リモートに push して CI を走らせる**

```bash
git push
```

GitHub 上で Actions タブを開き `vrt` ジョブが緑になるかを確認する。**最初の実行では macOS で生成したスクリーンショットベースラインが Ubuntu のものと差分を出す可能性が高い**。失敗した場合は Task 13 でベースラインを差し替える。

---

## Task 13: CI 上のスクリーンショットベースラインに差し替える（必要な場合のみ）

**Files:**
- Modify: `e2e/vrt-screenshot.spec.ts-snapshots/editor-light.png`
- Modify: `e2e/vrt-screenshot.spec.ts-snapshots/editor-dark.png`

Task 12 の CI 実行で `vrt-screenshot.spec.ts` が fail した場合のみ実施。

- [ ] **Step 1: 失敗した CI run から `test-results` artifact をダウンロードする**

GitHub Actions の `vrt` ジョブ failure run → Artifacts → `playwright-report` をダウンロード。zip を展開し、`test-results/vrt-screenshot-*/` 配下に `editor-{theme}-actual.png` が含まれる。

- [ ] **Step 2: actual 画像をベースラインとして置き換える**

```bash
# 展開した artifact のパスを使う
ACTUAL_DIR=/tmp/playwright-report/test-results
cp "$ACTUAL_DIR"/vrt-screenshot-*-light*/editor-light-actual.png e2e/vrt-screenshot.spec.ts-snapshots/editor-light.png
cp "$ACTUAL_DIR"/vrt-screenshot-*-dark*/editor-dark-actual.png e2e/vrt-screenshot.spec.ts-snapshots/editor-dark.png
```

- [ ] **Step 3: コミットして push し、CI が緑になることを確認する**

```bash
git add e2e/vrt-screenshot.spec.ts-snapshots/editor-light.png e2e/vrt-screenshot.spec.ts-snapshots/editor-dark.png
git commit -m "test(e2e): replace VRT screenshot baselines with Ubuntu CI output"
git push
```

GitHub Actions で `vrt` ジョブが緑になることを確認する。

---

## Task 14: 既存テストと最終確認

**Files:** なし（検証のみ）

- [ ] **Step 1: MoonBit テストを実行する**

```bash
moon test --target js src
```

Expected: すべて緑。

- [ ] **Step 2: 既存 Playwright テスト (non-VRT) を実行する**

```bash
pnpm playwright test --grep-invert "VRT " --reporter=line
```

Expected: すべて緑。`task-toggle`, `playground`, `moonlight`, `ui-toggle`, `debug-*` が通る。

- [ ] **Step 3: VRT も含めて通しで実行する**

```bash
pnpm playwright test --reporter=line
```

Expected: 全部緑。

- [ ] **Step 4: `playground/index.html` に font-family 個別指定が残っていないことを verify する**

```bash
grep -n "font-family" playground/index.html
```

Expected: `font-family: -apple-system, ...` の body 行のみが残る。`'Monaco'` / `'Menlo'` / `'Consolas'` を含む行は 0 件。

```bash
grep -En "'Monaco'|'Menlo'|'Consolas'" playground/index.html
```

Expected: 何も出ない。

- [ ] **Step 5: 最終コミット（必要なら）**

もしテストで fail があり追加修正が必要だった場合のみ、修正をコミットする。全て緑なら追加コミット不要。

---

## 受け入れ基準チェックリスト

実装完了時に以下が全て満たされていることを確認:

- [ ] `moon test --target js src` 緑
- [ ] `pnpm playwright test` 緑（既存 e2e + 新 VRT 4 tests）
- [ ] `just vrt` 緑
- [ ] `- [ ] task` 含む行の drift が VRT で 0.5px 以内
- [ ] 日本語混在行の drift が VRT で 0.5px 以内
- [ ] GitHub Actions の `vrt` ジョブが PR で緑
- [ ] `playground/index.html` から editor 関連の font-family 個別指定が完全に除去されている
- [ ] `playground/public/fonts/PlemolJP-Regular.woff2` と `OFL.txt` がコミット済み
- [ ] `README.md` の Credits に PlemolJP が記載されている

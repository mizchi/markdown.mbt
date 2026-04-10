# Playground Editor — 日本語等幅フォント化と VRT 導入

- Date: 2026-04-10
- Scope: `playground/` のハイライトエディタと E2E (`e2e/`)
- Status: Draft for review

## 背景と課題

`playground` の SyntaxHighlightEditor は textarea を透明化し、その背面に
`.editor-highlight` という DOM を同じ寸法で重ねることでシンタックスハイライトを
実現している。両者が同じ幅・同じ行の高さで描画されることが前提で、ズレた場合は
カーソル位置がハイライト上の文字と一致しなくなる。

現状、以下の問題が観測されている。

1. `- [ ] task` などのチェックリスト行が「bold に見え、文字幅がズレる」とユーザーが報告。
2. フォントスタックは `'Monaco', 'Menlo', 'Consolas', monospace` で **日本語用の
   明示的フォールバックが無い**。CJK 文字は OS 既定フォント（macOS なら Hiragino 等）
   にフォールバックされ、半角:全角 = 1:2 の比率が保証されない。
3. `playground/index.html` の CSS コメントに「`font-weight`/`font-style` を editor 系
   CSS に付けてはいけない (cursor 位置がズレる)」という注意書きがあるが、構造的に
   強制する仕組みは無い。個別 CSS セレクタが font-weight を入れると即事故になる。
4. VRT（Visual Regression Test）は未導入で、上記のズレを検知する自動テストが存在しない。

## 目標

- Playground のエディタ/プレビューで **日本語を含む等幅フォント** を採用し、半角:全角
  の幅比を厳密に保証する。
- `textarea` と `.editor-highlight` の **幅が物理的に一致する** ことを CI で検証する
  仕組み (VRT) を導入する。
- 現状の「チェックリスト行で bold/幅ズレ」の主訴を解消し、回帰を VRT で防止する。

## 非目標 (Out of Scope)

- エディタ自体のレイアウト/機能追加（行番号/折り返し/マルチカーソルなど）。
- CommonMark 全要素の網羅的 VRT（代表 fixture のみ）。
- Firefox/WebKit での VRT 実行（Chromium 固定）。
- フォントファイル自体の sub-setting（単一 woff2 運用）。

## 方針サマリ

- 日本語等幅フォントは **PlemolJP (SIL OFL)** の Regular woff2 を `playground/public/fonts/`
  に同梱する。
- フォント設定は **単一の `.mono` CSS class** に集約し、editor/overlay/simple editor
  /preview code の全てに付与する。個別セレクタから font-family/font-weight/
  letter-spacing を剥がし、ドリフトの余地を構造的に消す。
- VRT は **幾何検証 (必須ゲート) + スクリーンショット (補助) の 2 本立て**。
  - 幾何検証: 各行の textarea 理論幅と overlay 実測幅の diff が `±0.5px` 以内。
  - スクリーンショット: `.editor-wrapper` を `maxDiffPixelRatio: 0.002` で撮影。
- 実行環境: Chromium 固定、Ubuntu CI、bundled woff2 により OS 差分を排除。
- `font-display: block` によりフォント未ロード時の描画を禁止して VRT の安定性を確保。

## アーキテクチャ

### ファイル配置

```
playground/
├── public/
│   └── fonts/
│       ├── PlemolJP-Regular.woff2          # 新規: 同梱フォント
│       └── OFL.txt                         # 新規: SIL OFL 原文
├── styles/
│   └── editor-font.css                     # 新規: @font-face と .mono
├── index.html                              # 変更: editor-font.css 読み込み、
│                                           #        font 指定を .mono に集約
├── SyntaxHighlightEditor.tsx               # 変更: textarea/highlight に .mono
└── main.tsx                                # 変更: SimpleEditor にも .mono

e2e/
├── fixtures/
│   └── width-fixture.md                    # 新規: VRT 用 markdown
├── helpers/
│   └── measure-line.ts                     # 新規: textarea↔overlay 幅計測ヘルパ
├── vrt-width.spec.ts                       # 新規: 幾何検証 (必須ゲート)
└── vrt-screenshot.spec.ts                  # 新規: スクリーンショット (補助)

.github/workflows/
└── ci.yml                                  # 変更: vrt ジョブ追加

justfile                                    # 変更: vrt / vrt-update 追加
README.md                                   # 変更: PlemolJP のライセンス記載
```

### `.mono` class の単一ソース化

```css
.mono {
  font-family: 'PlemolJP', ui-monospace, Monaco, Menlo, Consolas, monospace;
  font-size: 14px;
  line-height: 1.5;
  font-weight: 400;
  letter-spacing: 0;
  font-feature-settings: normal;
  font-variant-ligatures: none;
  font-kerning: none;
  tab-size: 2;
}
```

適用箇所（HTML 側で `class="... mono"` を付与する要素）:

- `.editor-textarea`（`SyntaxHighlightEditor.tsx`）
- `.editor-highlight`（`SyntaxHighlightEditor.tsx`）
- `.simple-editor`（`main.tsx` SimpleEditor）
- `.line-numbers`（`SyntaxHighlightEditor.tsx`）
- `.preview pre`, `.preview code`（`ast-renderer.tsx` の code block renderer。
  preview は JSX で出力しているので、出力時に `className="mono"` を付ける。
  旧 `.preview code { font-family: ... }` CSS は削除）

個別 CSS セレクタ側からは `font-family` / `font-size` / `line-height` / `font-weight` /
`letter-spacing` の指定を削除する。これらは `.mono` が単独で決める。

### 回帰防止の追加ルール

1. `.editor-highlight { font-weight: 400 !important; }` を追加し、子要素 span が
   誤って font-weight を上書きしても overlay 全体が 400 を維持するよう強制。
   `!important` はこの一箇所のみ許容。
2. CSS レビュー時のガイドとして `playground/index.html` のフォント注意書きコメントを
   `.mono` class の定義直前にも再掲する。

## フォント同梱

- PlemolJP の配布元: https://github.com/yuru7/PlemolJP (SIL OFL 1.1)。
- 必要なウェイト: Regular のみ。bold/italic は入れない（既存ポリシーとの整合）。
- 配置: `playground/public/fonts/PlemolJP-Regular.woff2`
- ライセンス: `playground/public/fonts/OFL.txt` に原文をコピー。
- README: Credits セクションに「Fonts: PlemolJP (SIL OFL 1.1), https://github.com/yuru7/PlemolJP」
  を 1 行追加。
- サイズ: 単一 woff2 で 2〜3MB 想定。VRT と CI の安定性を優先し sub-setting は行わない。

### `@font-face`

```css
@font-face {
  font-family: 'PlemolJP';
  src: url('/fonts/PlemolJP-Regular.woff2') format('woff2');
  font-weight: 400;
  font-style: normal;
  font-display: block;
  unicode-range: U+0000-FFFF, U+10000-1FFFF;
}
```

`font-display: block` の採用理由: `swap`/`fallback` はロード前にシステムフォントで
描画されるため、VRT 撮影タイミング次第でベースラインとの差分が発生する。`block`
は最初の約 3 秒間白紙表示となる代わりに、フォントがロードされた状態でのみ描画される
ため、テスト安定性が高い。テスト側は `document.fonts.ready` を待ってから検証する。

## VRT 設計

### Fixture (`e2e/fixtures/width-fixture.md`)

下記を 1 ファイルに固定収容する。コメントを除いて全て意味のある要素:

- `# heading` 行
- 通常段落（ASCII）
- `**bold**` `*italic*` `***bold italic***` `` `inline code` ``
- `- [ ] ...` / `- [x] ...`（主訴の検知点）
- CJK 混在タスク `- [ ] 日本語タスク 項目 with mixed 英数字 123`
- 通常の箇条書き
- `> blockquote` 日本語込み
- 日本語のみの段落（半角:全角比の厳密検証）
- GFM table（日本語セル含む）
- 4 space インデントコードブロック（日本語コメント含む）
- link / image
- `---` ThematicBreak
- fenced code block (`ts`) 内に日本語コメント

### 計測ヘルパ (`e2e/helpers/measure-line.ts`)

- ブラウザ内で `canvas.getContext('2d').measureText` を用いて textarea 各行の
  理論幅を算出。`ctx.font` は `.editor-textarea` の computed style から組み立てる。
- overlay 側は `.highlight-line` の `getBoundingClientRect().width` **ではなく**、
  `Range` API で行内 inline content の実幅を取得する:
  ```ts
  const range = document.createRange();
  range.selectNodeContents(lineEl);
  const width = range.getBoundingClientRect().width;
  ```
  `.highlight-line` は block div なので width が常に親 container 幅になってしまい、
  そのままでは行末位置は測れない。`Range` は inline content のみを囲うので、
  wrap していない限り行末までの実幅が取れる。
- 行ごとに `{ idx, src, textareaWidth, overlayWidth, drift }` を返す。
- 空行（`src.trim() === ''`）かつ overlay Range 幅 0 は「ズレなし」として扱う。
- **折り返し禁止の保証**: fixture は `.editor-content` の max-width (900px) に収まる
  行長に抑える。折り返しが発生すると Range の高さが line-height より大きくなるので、
  ヘルパは併せて `range.getBoundingClientRect().height` が `line-height` 相当
  (`21px` @ 1.5 * 14px) 以内であることも assert し、折り返し検出時はテストを失敗させる。

### 幾何検証テスト (`e2e/vrt-width.spec.ts`)

- light / dark テーマ両方をループで検証。
- 手順: localStorage クリア → reload → `document.fonts.ready` 待機 → fixture を
  textarea に注入 → input event dispatch → 200ms 待機 → `measureLineDrift` →
  `drift > 0.5` の行が 0 件であることを assert。
- 失敗時のメッセージには JSON で ズレた全行を出力（デバッグしやすさのため）。
- tolerance: `0.5px`。1ch (約 8.4px @14px) の数分の一のズレしか許容せず、
  1 文字単位のドリフトは確実に検知する。サブピクセル round off は通す。

### スクリーンショット VRT (`e2e/vrt-screenshot.spec.ts`)

- 対象要素: `.editor-wrapper`。
- `toHaveScreenshot` で light/dark 各 1 枚ずつ（合計 2 枚）保存。
- tolerance: `maxDiffPixelRatio: 0.002` (0.2%)。文字の微小な色差は許容しつつ、
  エリアが数文字単位でズレれば確実に fail する。
- 初回ベースラインは CI (Ubuntu) で生成したものを真とする方針。ローカル macOS では
  差分が出ても構わない（CI ジョブが唯一のゲート）。

### justfile タスク

```makefile
vrt:
    pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts

vrt-update:
    pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts --update-snapshots
```

## CI 統合

既存の `.github/workflows/ci.yml` を確認した時点の状態:

- `test` ジョブのみ存在。MoonBit CLI インストール → `moon check` / `moon test` /
  `moon bench` / `component` の wasm ビルドを実行。Playwright は未セットアップ。

本設計での変更:

- 同ファイルに新規ジョブ `vrt` を追加する（既存の `test` ジョブはそのまま）。
  既存フローに手を入れないことで、VRT 導入が他のビルドの成功/失敗に混ざらない。
- 新規 `vrt` ジョブの内容:
  - `runs-on: ubuntu-latest` / Chromium のみ。
  - MoonBit CLI インストール → `moon update` → `moon build --target js`（`js/api.js`
    が import する `_build/js/release/build/api/api.js` 生成のために必要）。
  - `pnpm install --frozen-lockfile`。
  - `pnpm playwright install --with-deps chromium`。
  - `pnpm playwright test e2e/vrt-width.spec.ts e2e/vrt-screenshot.spec.ts`。
  - 失敗時は `playwright-report/` と `test-results/` を artifact アップロード。
- ベースライン画像は CI (Ubuntu) 上で生成したものを真とする。macOS 手元での
  `--update-snapshots` は原則行わない運用。将来必要になったら `workflow_dispatch`
  で手動トリガするベースライン更新ジョブを追加する。

## バグ修正の手当て

現状の `- [ ] task` 幅ズレの原因は、コード読みの範囲では `highlightMarkdownLine`
自体が bold 用の span を出していないため、以下のいずれかまたは両方と推定している:

- CJK フォールバックによる半角:全角比の崩れ（実質 "bold" に見える）。
- `[` `]` 周辺の合字/カーニング（フォント依存）。
- `highlightMarkdownLineImpl` の `linkMatch` 近辺で想定外の枝分岐（確率低）。

本設計では以下で包括的に封じる:

- PlemolJP 化で半角:全角を構造保証。
- `.mono` で `font-variant-ligatures: none` / `font-kerning: none` を強制。
- `.editor-highlight { font-weight: 400 !important }` で子 span からの bold 混入を禁止。
- 幾何検証 VRT が、要因を問わず「ズレている事実」を直接検知する。

なお、実装時に `highlightMarkdownLineImpl` が本当に `[ ]` に対して `md-bold` 系の
span を出していないかを一度 DOM で確認する（実装計画の verify ステップ）。もし
出していればそこは別途バグ修正する。

## 作業順序

1. `playground/public/fonts/PlemolJP-Regular.woff2` と `OFL.txt` を配置、
   README に Credits 追記
2. `playground/styles/editor-font.css` を作成（`@font-face` と `.mono` class）
3. `playground/index.html` から `editor-font.css` を読み込み。既存 CSS の以下から
   font-family / font-size / line-height / font-weight / letter-spacing の指定を剥がす:
   - `.editor-textarea`, `.editor-highlight` (合流指定)
   - `.simple-editor`
   - `.line-numbers`
   - `.preview code`, `.preview pre code`
4. `.editor-highlight { font-weight: 400 !important }` を `index.html` の CSS に追加
5. `SyntaxHighlightEditor.tsx` の textarea/highlight 要素に `class` に `mono` を追加
   （`class="editor-textarea mono"` と `class="editor-highlight mono"`）
6. `SyntaxHighlightEditor.tsx` の `.line-numbers` にも `mono` を追加
7. `main.tsx` の `SimpleEditor` の textarea に `mono` を追加
   （`class="simple-editor mono"`）
8. `ast-renderer.tsx` / preview 側の `<pre>` `<code>` 出力に `mono` を付与
   （現状は CSS セレクタ `.preview code` で font-family を当てているので、その CSS を
   `.preview .mono` に置換しつつ、renderer 側で `<code className="mono">` を出す）
9. `e2e/fixtures/width-fixture.md` を作成
10. `e2e/helpers/measure-line.ts` を作成
11. `e2e/vrt-width.spec.ts` を作成し `pnpm playwright test e2e/vrt-width.spec.ts` で緑確認
12. `e2e/vrt-screenshot.spec.ts` を作成し `just vrt-update` でベースライン生成、
    目視確認後コミット
13. `justfile` をリポジトリルートに新規作成し、`vrt` / `vrt-update` ターゲットを追加
    （現状 justfile は存在しない。ユーザーの慣習に合わせて新規導入する）
14. `.github/workflows/ci.yml` に `vrt` ジョブを追加（既存 `test` ジョブは変更しない）
15. 検証: 一時的に `.editor-highlight` に `font-weight: bold` を入れて VRT
    (vrt-width.spec.ts) が fail することを確認 → revert。これで VRT が実効的に
    機能していることを verify
16. 最終チェック: `moon test`（既存）・`pnpm playwright test`（既存 e2e）・
    `just vrt` が全て緑

## リスクと対応

- **woff2 ファイルサイズ増**: 2〜3MB をリポジトリに同梱する。LFS は使わず通常の
  git 管理。playground のビルド成果物が大きくなるが、デプロイ先 (GitHub Pages 等) は
  問題にならない想定。必要なら将来 sub-set を検討。
- **CI フレーキー**: bundled font + Chromium + Ubuntu により OS 差分は発生しない想定。
  万が一サブピクセル差分が出る場合は tolerance を段階的に緩める前に、原因 (例: 改行・
  フォント読み込み待ち) を調査する。
- **既存 e2e とのコンフリクト**: 現状 e2e のうち task-toggle など既存テストが動くか
  念のため再確認する。本設計は既存 CSS の font 指定を剥がすので、もし既存テストが
  特定の font-family に依存していた場合は修正する。
- **折り返しによる誤計測**: `.highlight-line` は `white-space: pre-wrap` なので、
  fixture の行長が `.editor-content` max-width (900px) を超えると折り返し、Range
  の bounding rect が複数行分になって幅計測が破綻する。ヘルパで Range の高さが
  `line-height` 以内かを併せて assert し、折り返し時は明示的に失敗させる。fixture
  は 1 行 60 文字（半角換算）以内に抑える。
- **font-display: block の白紙時間**: ユーザー体験上約 3 秒の白紙があり得る。
  PlemolJP は 2〜3MB で LAN/CDN 越しなら 1 秒未満でロードされる想定なので許容。
  気になれば `rel="preload" as="font"` を `<head>` に入れる。

## 受け入れ基準

- `moon test` 既存テストが緑。
- `pnpm playwright test` で既存 e2e がすべて緑。
- `just vrt` (= 新規の vrt-width + vrt-screenshot) が緑。
- チェックリスト行 `- [ ] task` を含む VRT 行が `drift <= 0.5px`。
- 日本語混在行が `drift <= 0.5px`。
- `.github/workflows/ci.yml` の vrt ジョブが PR で緑になる。
- `playground/index.html` から editor 関連の font-family/font-weight/letter-spacing
  の個別指定が削除され、`.mono` class に一本化されている。

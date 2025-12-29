# SyntaxHighlightEditor 最適化記録

## 目標

60fps（16.67ms/フレーム）でのシンタックスハイライト付きMarkdownエディタ

## 最終結果

| テスト | P95 | 平均 | 状態 |
|--------|-----|------|------|
| Simple Typing | 16.3-17.4ms | ~15.5ms | 境界付近 |
| Mixed Markdown | 16.4-18.1ms | ~15.4ms | 境界付近 |
| Newlines | 16.4-17.3ms | ~15.3ms | 時々PASS |

平均値は目標達成。P95はGC等の外部要因で分散あり。

---

## 効果があった最適化

### 1. 行番号のデフォルト無効化

**効果: 高**

```typescript
// Before: 常に行番号を表示・更新
<For each={lineNumbersArray}>
  {(num) => <div class="line-number">{num}</div>}
</For>

// After: オプショナル化（デフォルト無効）
{props.showLineNumbers && (
  <div class="line-numbers">...</div>
)}
```

- 行数シグナルの更新コストを削減
- DOM要素数の削減
- スクロール同期処理の簡略化

### 2. 変更行のみ更新（カーソル位置ベース）

**効果: 高**

```typescript
// カーソル位置から現在行を特定（split不要）
const [cursorLine, lineStart, lineEnd] = getLineInfo(value, cursorPos);

// 単一文字入力時は該当行のみ更新
const rawLine = value.slice(lineStart, lineEnd);
if (lineElements[cursorLine]) {
  const newHighlight = highlightSingleLine(rawLine);
  if (prevHighlightedLines[cursorLine] !== newHighlight) {
    setLineContent(lineElements[cursorLine], newHighlight);
  }
}
```

- 全行再計算から単一行更新へ
- `value.split("\n")` の回避（大きなドキュメントで効果大）

### 3. 全文字列比較の削除

**効果: 中**

```typescript
// Before: O(n) の文字列比較
if (value === lastHighlightedValue) return;

// After: 削除（signal変更時のみeffectが発火するため不要）
```

- Lunaのsignal変更検知を信頼
- 大きなドキュメントでのO(n)比較を回避

### 4. 改行検出の最適化

**効果: 中**

```typescript
// Before: 毎回全文をカウント
const newLineCount = countLines(value); // O(n)

// After: 1文字変更時はO(1)でチェック
const lengthDiff = valueLen - lastValueLength;
if (lengthDiff === 1) {
  // 追加された文字が改行かチェック
  lineCountChanged = cursorPos > 0 && value[cursorPos - 1] === "\n";
} else if (lengthDiff === -1) {
  // 削除時はカーソル行変化で判定
  lineCountChanged = cursorLine !== lastCursorLine;
}
```

### 5. textContent vs innerHTML の使い分け

**効果: 中**

```typescript
function setLineContent(el: HTMLElement, html: string): void {
  if (html.indexOf("<") === -1) {
    // HTMLタグなし → textContent（Parse HTML不要）
    if (html.indexOf("&") !== -1) {
      el.textContent = decodeEntities(html);
    } else {
      el.textContent = html;
    }
  } else {
    // HTMLタグあり → innerHTML必須
    el.innerHTML = html;
  }
}
```

### 6. isUserInput フラグ

**効果: 中**

```typescript
let isUserInput = false;

const handleInput = (e: Event) => {
  isUserInput = true;
  props.onChange(target.value);
};

createEffect(() => {
  const value = props.value();
  if (isUserInput) {
    isUserInput = false; // textarea.value設定をスキップ
  } else if (editorRef) {
    editorRef.value = value; // 外部からの変更のみ設定
  }
});
```

- ユーザー入力時のtextarea.value再設定を回避

### 7. Show → CSS display 制御

**効果: 高**

```typescript
// Before: Showコンポーネント（子要素が毎回再生成）
<Show when={editorMode() === "highlight"}>
  <SyntaxHighlightEditor ... />
</Show>

// After: CSS display制御（コンポーネント状態維持）
<div style={{ display: editorMode() === "highlight" ? "contents" : "none" }}>
  <SyntaxHighlightEditor ... />
</div>
```

- コンポーネントの再生成を防止
- 内部状態（カーソル位置、スクロール位置）を維持

---

## 効果がなかった・限定的だった最適化

### 1. escapeHtml の最適化

**効果: 限定的**

```typescript
// Fast path追加
let needsEscape = false;
for (let i = 0; i < text.length; i++) {
  if (c === "&" || c === "<" || c === ">" || c === '"') {
    needsEscape = true;
    break;
  }
}
if (!needsEscape) return text;
```

- ほとんどのテキストでは効果あり
- ボトルネックは他の箇所（innerHTML、signal処理）だったため全体への影響は小

### 2. キャッシュ（lineCache, inlineCache）

**効果: 限定的**

- 同じ行を再度ハイライトする場合に効果
- 入力中は毎回内容が変わるためヒット率低い
- コードブロック内では効果あり

---

## やるべきではないこと

### 1. setTimeout / requestAnimationFrame によるデバウンス

**理由**: Lunaのsignal batchがqueueMicrotaskで自動バッチ処理するため、追加のスケジューリングは余計

```typescript
// NG: 余計なオーバーヘッド
const scheduleHighlight = () => {
  clearTimeout(highlightTimer);
  highlightTimer = window.setTimeout(updateHighlight, 16);
};

// OK: 直接呼び出し
const scheduleHighlight = () => {
  updateHighlight();
};
```

- コールスタックが見づらくなる
- デバッグが困難になる
- 実際のパフォーマンス向上に寄与しない

### 2. 過度な変数キャッシュ

**理由**: JavaScriptエンジンの最適化を信頼すべき

```typescript
// 過度なキャッシュは可読性を下げるだけ
const len = arr.length; // 不要な場合が多い
```

### 3. DocumentFragment の使用（この用途では）

**理由**: 行単位の更新では効果なし。大量のDOM追加時のみ有効。

---

## プロファイル分析結果

主要なボトルネック（CPU時間の割合）：

| Activity | 割合 | 説明 |
|----------|------|------|
| set value | 44.9% | DOM プロパティ設定全般 |
| Parse HTML | 23.2% | innerHTML 解析 |
| CPP GC | 10.2% | ガベージコレクション |
| highlightMarkdownLines | 5.3% | マークダウン解析 |
| set innerHTML | 3.1% | innerHTML 設定 |

### 根本的な制約

1. **innerHTML は避けられない**: シンタックスハイライトにはHTMLタグが必要
2. **GC は制御困難**: 文字列操作で必然的にメモリ確保が発生
3. **Parse HTML コスト**: ブラウザのHTML解析オーバーヘッド

---

## 今後の改善方向性

### 短期（追加最適化）

1. **ハイライト対象の絞り込み**
   - 表示領域内の行のみハイライト（仮想スクロール的アプローチ）

2. **正規表現の最適化**
   - highlightMarkdownLine 内の正規表現をコンパイル済みに

3. **Web Worker へのオフロード**
   - ハイライト計算をメインスレッド外で実行

### 中期（設計変更）

1. **Canvas / WebGL レンダリング**
   - DOM を完全に回避
   - Monaco Editor / CodeMirror のアプローチ

2. **差分ハイライト**
   - Tree-sitter のような増分パーサーとの統合

### 見送り

1. **Shadow DOM**: パフォーマンス改善に寄与しない
2. **Web Components**: 複雑性が増すだけ

---

## ベンチマーク実行方法

```bash
# 開発サーバー起動
pnpm dev

# ベンチマーク実行
npx tsx e2e/benchmark.ts

# トレース付き（DevToolsで分析可能）
npx tsx e2e/benchmark.ts --trace
```

---

## 参考: 最適化前後の比較

### Before（最適化前）

- Show コンポーネントで毎回再生成
- 全行を毎回再ハイライト
- 全文字列比較
- 行番号を常に更新

### After（最適化後）

- CSS display で状態維持
- カーソル行のみ更新
- signal 変更検知に依存
- 行番号オプショナル化

**結果**: 平均入力遅延 ~25ms → ~15ms（約40%改善）

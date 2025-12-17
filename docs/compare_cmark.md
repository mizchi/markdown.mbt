# cmark実装との比較分析

rami3l/cmark (v0.4.0) のemphasis実装を分析し、採用可能なアプローチをまとめる。

## ベンチマーク比較

| Document | mizchi/markdown | rami3l/cmark | 差 |
|----------|-----------------|--------------|-----|
| small (5) | 46.38µs | 36.43µs | +27% 遅い |
| medium (20) | 142.42µs | 155.81µs | **-9% 速い** |
| large (100) | 660.70µs | 794.09µs | **-17% 速い** |

中〜大規模ドキュメントでは優位。小規模での初期化オーバーヘッドが課題。

## Emphasis実装の違い

### 現在の実装の問題点

1. **Rule 9, 10 (mod 3ルール) 未実装**
2. **Closer Index なし** - 閉じるデリミタの検索が非効率
3. **単一パス処理** - 複雑なネストに対応できない
4. **Left/Right flanking が部分的**

### cmarkのアーキテクチャ

#### 1. トークン化フェーズ

```moonbit
// 各 * や _ の連続に対して TokenEmphasisMarks を生成
TokenEmphasisMarks { start, char, count, may_open, may_close }
```

#### 2. Left/Right Flanking判定 (CommonMark仕様)

```moonbit
// 基本判定
is_left_flanking = !is_next_white && (!is_next_punct || is_prev_white || is_prev_punct)
is_right_flanking = !is_prev_white && (!is_prev_punct || is_next_white || is_next_punct)

// * の場合
may_open = is_left_flanking
may_close = is_right_flanking

// _ の場合 (単語境界の追加制約)
may_open = is_left_flanking && (!is_right_flanking || is_prev_punct)
may_close = is_right_flanking && (!is_left_flanking || is_next_punct)
```

#### 3. Closer Index

閉じるデリミタの位置をハッシュマップでインデックス化:

```moonbit
priv struct CloserIndex(Map[Closer, Set[Int]])

fn CloserIndex::exists(self, key: Closer, after~: Int) -> Bool
fn CloserIndex::pos(self, key: Closer, after~: Int) -> Int?
```

「この位置より後ろに閉じる `*` があるか？」を O(1) で検索可能。

#### 4. Rule 9, 10 (mod 3ルール)

CommonMark仕様のRule 9, 10を実装:

```moonbit
fn marks_match(marks: TokenEmphasisMarks, opener: TokenEmphasisMarks) -> Bool {
  opener.char == marks.char &&
  (
    (marks.may_open || !opener.may_close) ||
    marks.count % 3 == 0 ||
    (opener.count + marks.count) % 3 != 0
  )
}
```

このルールにより、`***foo**` のような曖昧なケースを正しく処理できる。

#### 5. 3パス処理

1. **First pass**: コードスパン、オートリンク、リンク
2. **Second pass**: emphasis, strikethrough
3. **Last pass**: テキストノード生成

## 実装計画と検証結果

### Phase 1: Rule 9, 10 (mod 3ルール) の追加

**対象ファイル**: `src/inline_parser.mbt`

**変更内容**:
- `try_parse_emphasis` でマーカーカウントを追跡
- 閉じるマーカーとのマッチング時に mod 3 ルールを適用

**期待効果**: Emphasisテスト大幅改善 (現在 42/132)

**実装結果**: ❌ 効果なし (42/132 → 42/132)

### Phase 2: Left/Right Flanking の完全実装

**対象ファイル**: `src/inline_parser.mbt`

**変更内容**:
- `_` の単語境界ルールを厳密に実装
- Unicode空白・句読点の判定を追加

**期待効果**: `_` 関連のエッジケース改善

**実装結果**: ❌ リグレッション発生 (42/132 → 41/132)

### 問題分析

Emphasis テストの失敗の大部分は**シリアライズの差異**:
- remark: テキスト中の `*` `_` をエスケープ (`\*`, `\_`)
- 本実装: そのまま出力

例: `a * foo bar*`
- remark出力: `a \* foo bar\*`
- 本実装出力: `a * foo bar*`

これはCST設計上の選択の違いであり、パースの正確性の問題ではない。

### Phase 3: Closer Index の導入 (未実施)

**対象ファイル**: `src/inline_parser.mbt` (新規構造体追加)

**変更内容**:
- `CloserIndex` 構造体を追加
- トークン化時に閉じるデリミタをインデックス化
- 検索時に O(1) ルックアップを使用

**期待効果**: パフォーマンス改善（特に大規模ドキュメント）

### Phase 4: 複数パス処理 (未実施)

**対象ファイル**: `src/inline_parser.mbt` (大幅リファクタリング)

**変更内容**:
- トークン化 → パス1 → パス2 → パス3 の構造に変更
- 各パスで異なる種類のインラインを処理

**期待効果**: 複雑なネストの正確な処理

### Phase 4: 複数パス処理 (実装・検証済み)

**実装内容**:
- `inline_token.mbt` に Token enum、tokenize、CloserIndex を実装
- `parse_inlines_multipass()` 関数として 3パス処理を実装

**ベンチマーク結果**:

| Test | Original | Multipass | 比較 |
|------|----------|-----------|------|
| stress 10 (30 markers) | 2.51 µs | 1.76 µs | **30% 高速** |
| stress 50 (150 markers) | 9.71 µs | 13.10 µs | 35% 低速 |
| stress 100 (300 markers) | 41.90 µs | 65.32 µs | 56% 低速 |

**結果**: ❌ 大規模入力で性能劣化

小規模入力では高速だが、マーカー数が増えると低速に。
トークン配列生成と複数回走査のオーバーヘッドが原因。

### 結論

Emphasis の CommonMark 互換性向上には大規模リファクタリングが必要だが、
現在の検証では性能とのトレードオフが厳しい。

| アプローチ | 効果 | 性能 |
|-----------|------|------|
| Phase 1: mod 3 rule | ❌ 効果なし | - |
| Phase 2: Flanking | ❌ リグレッション | - |
| Phase 4: Multi-pass | 検証中 | 大規模で低速 |

現状のアーキテクチャでは Emphasis 42/132 (32%) が限界と思われる。
性能を維持しつつ互換性を向上させるには、さらなる最適化が必要。

## 参考リンク

- [CommonMark Spec - Emphasis and strong emphasis](https://spec.commonmark.org/0.31.2/#emphasis-and-strong-emphasis)
- [rami3l/cmark](https://github.com/moonbit-community/cmark.mbt)
- ソース: `.mooncakes/rami3l/cmark/src/cmark/inline_struct.mbt`

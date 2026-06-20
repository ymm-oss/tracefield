# 領域: EntryStatus（状態の定義）
- path: ../../crates/tracefield-core/src/entry.rs   # スコープdir（codex の cwd）からの相対
- lines: 52-138
- 抽出対象:
  - `EntryStatus` の取りうる値（`Active` / `Retracted` / `Superseded`）と初期状態
  - エントリ生成時の初期ステータス（`Entry::new` / `from_new`）
  - ステータスがどのフィールド・不変条件に関わるか
- 文脈: ステータスは `store.rs` の `retract` / `supersede` で遷移し、`serve` や選択ロジックが `Active` だけを通す（read 路の駆動）。遷移の本体は別領域（region-store-*）。

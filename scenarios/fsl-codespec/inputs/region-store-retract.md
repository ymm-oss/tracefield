# 領域: retract と引用閉包（Active → Retracted の遷移）
- path: ../../crates/tracefield-core/src/store.rs   # スコープdir（codex の cwd）からの相対
- lines: 135-230
- 抽出対象:
  - `retract` の前提ガード（対象 id の存在・現ステータス）と事後状態（対象＋下流閉包が `Retracted`）
  - `mark_closure` プリミティブの挙動（どの集合に何のステータスを書くか）
  - `downstream_closure` の引用逆 BFS（どの辺をたどるか／`Active` だけ辿るか）
  - 不変条件: 撤回は下流引用閉包に伝播する／既に終端のものをどう扱うか
- 文脈: テスト `retract_marks_downstream_citation_closure`（around 305-330）が期待挙動の実例（e1撤回で e2/e3 も Retracted、無関係 e4 は Active のまま）。`supersede` は別領域。

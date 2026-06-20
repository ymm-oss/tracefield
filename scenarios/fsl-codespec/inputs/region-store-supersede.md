# 領域: supersede（Active → Superseded、置換は Active 維持）
- path: ../../crates/tracefield-core/src/store.rs   # スコープdir（codex の cwd）からの相対
- lines: 156-215
- 抽出対象:
  - `supersede` の前提ガード（旧 id・新 id の存在、自己置換の拒否など）
  - 事後状態: 旧エントリ＋その下流閉包が `Superseded`、**置換（新 id）は `Active` のまま**という非対称
  - `mark_closure` の共有（retract と何を共有し何が違うか＝書くステータスだけ違う）
  - 拒否条件: 未知 id / 自己置換
- 文脈: テスト `supersede_marks_closure_and_keeps_replacement_active`（around 333-368）と `supersede_rejects_unknown_or_self_replacement`（around 369-）が期待挙動の実例。retract と対で読むと不変条件が際立つ。

# impl-brief: 生成側ハルシネーション抑制の engine 硬化（citation-backfill 撤去）

対象: `crates/tracefield-core/src/flow.rs` の `apply_core_gates`。

## 背景（なぜ）
「読み取り」側の接地ゲート（per-stage `grounded` フラグ＋`evidence_quote` の実ファイル/引用 store 照合）は完成済み。
本タスクは「生成」側ハルシネーション抑制の手法 *govern the composer* を engine 面で*健全化*する 1 点のみ。

手法本体（grounded composer ＋ 第二 verify→adjudication(retract) ＋ retract_overturned）は
`scenarios/fsl-direction` の flow.toml/agents.json の*設定*で既に実現しており、engine 変更は不要。
ただし 1 箇所だけ、ゲートの接地を*偽装*しうる挙動が残っている:

`apply_core_gates` は、エントリの citations が*全て無効*（active store に無い）になったとき、
**直近 selected 入力 5 件を自動で citations に詰め直す**（`citations_repaired=true`）。これは
fallback による*provenance の捏造*であり、生成側で致命的:

- 捏造した施策（依拠 FSL 事実が inputs に無い）が citations を失っても、5 件のもっともらしい
  出典を機械的に着せられ、retract 閉包・読み手から見て「接地済み」に見えてしまう。
- grounded ステージでは `evidence_quote` をこの*backfill された citations* に照合するため、
  本来 `evidence_quote_not_found` になるべき捏造が、偶然 quote が直近入力に含まれれば誤接地しうる。

これは「捏造の検出」を engine が自ら掘り崩す経路。ユーザーのプロジェクト規約（fallback 実装の禁止）
にも反する。**fallback を撤去し、citations を失ったエントリは空のまま + 可視フラグを残す**
（no-silent-drop は維持、provenance は捏造しない）。

## 変更内容（最小）
`apply_core_gates`（おおよそ `flow.rs:2665` 周辺）:

1. `fallback_citations` の構築（`selected.iter().filter(Active).take(5)...`）を**削除**。
2. citations 再構築ブロックを次に変更（backfill 分岐を撤去し、欠落は可視フラグのみ）:
   ```rust
   let before = entry.citations.clone();
   entry
       .citations
       .retain(|citation| active_ids.contains(citation.as_str()));
   if entry.citations != before {
       entry
           .meta
           .insert("invalid_citations_dropped".to_string(), json!(true));
   }
   ```
   （`citations_repaired` キーは廃止。空 citations はそのまま空で通す。）
3. `selected: &[Entry]` 引数が `apply_core_gates` 内で他に使われていなければ**シグネチャから除去**し、
   全呼び出し側（serial/parallel actors・clustering・command・marker の各経路）から実引数を外す。
   他で使われている場合のみ残置（その判断はソースで確認。`_` 接頭ではなく不要なら削除を優先）。

## 検証（必須・このタスク内で完了）
- `cargo build --release -p tracefield`、`cargo fmt --check`、`cargo clippy -p tracefield-core -p tracefield`。
- `cargo test`（全スイート、mock）。
- **`citations_repaired` / backfill に依存するテストが落ちたら、勝手に backfill を戻さない**。
  そのテストは*撤去した fallback を符号化していた*ものなので、新挙動（空 citations + `invalid_citations_dropped`）
  に沿って*テスト側を*更新し、何を変えたかを報告すること。閉包(closure)系テストが「backfill された
  citation 経由で synthesis が retract 閉包に入る」ことを前提にしていた場合は、その前提自体が
  本タスクで除去したい挙動なので、テストを新挙動に合わせて更新する。
- 既存の `grounded` ゲート（reading）テスト群（`grounded_flag_enables_evidence_quote_gate`,
  `on_disk_*`）が緑のままであることを確認。

## スコープ外（やらないこと）
- scenarios の編集（fsl-direction の flow/agents は本体側で対応済み）。
- 新しいゲート種別・新メタキー・新ステージの追加。backfill 撤去*のみ*。
- 後方互換のための設定スイッチ追加（規約により不要。挙動は単純化する方向）。

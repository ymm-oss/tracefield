# 実装ブリーフ 27 — qa stage（テスト実行 + 受入基準突合 + 差し戻しループ）

> cursor-agent 指示（第27弾）。設計は [`design-pipeline.md`](./design-pipeline.md) §1/§5（**決定的一次・LLM二次**の原則）。前提: brief-26 まで（121 tests）。
> `mise exec -- mix ...`。ネット不可。**tracefield リポジトリに git commit しない**（テスト内 tmp リポジトリへの commit はテスト動作なので可）。mise.toml に触れない。
> 着手前に必読: `lib/mix/tasks/tracefield.dev.ex` / `lib/tracefield/workspace.ex` / `lib/tracefield/llm/mock.ex` / `test/dev_task_test.exs`（brief-26 の implement stage パターンを qa に拡張する）。
> 核心: QA 判定は**決定的一次（テスト exit）＋ LLM 二次（受入基準突合）**。fail は根拠つき `:verdict` を残して **implement へ差し戻し**、
> 来歴不変条件 `verdict → change → decision → requirement → issue chunk` を完成させる（パイプライン全長の provenance がこれで閉じる）。

## 1. `Reference` — `@types` に `:verdict` を追加（永続/replay は既存機構で自動）。

## 2. `Tracefield.QA`（新モジュール、LLM 二次）

- `judge(adapter, llm_opts, requirement, change, test_result)` → `%{matched: boolean, note: String.t()}`
  - プロンプト: `TRACEFIELD_QA` マーカー + 要件（`e<id>: text`、受入基準を含む）+ 実装変更（change の text と meta の files）
    + テスト結果（exit と tail）+ 「この変更は要件の受入基準を満たすか。JSON `{"matched": true|false, "note": "…"}` のみ返せ。」
  - `adapter.complete(messages, llm_opts)` で呼ぶ（agent turn と同じ流儀）。応答からは寛容に JSON を抽出。
  - LLM 失敗・JSON 抽出失敗時のフォールバック: `%{matched: test_result.exit == 0, note: "judge unavailable"}`（**決定的一次が常に権威**）。
- Mock 分岐（`llm/mock.ex` の complete cond に追加）: `TRACEFIELD_QA` を見たら決定的に
  `{"matched": <プロンプトに "IMPLEMENTED" を含むか>, "note": "mock突合"}` を返す。

## 3. `tracefield.dev` の qa stage

- dispatch 変更: `implement`+`done` →（現行メッセージではなく）`start_qa`。`qa`+`done` → 「qa 完了。Issue 完遂（refine→design→implement→qa）」+ `print_qa_done`。
  qa は人間 gate を持たず**中断しない**ので `qa`+`awaiting_human` は存在しない。
- `start_qa`:
  1. `Workspace.load!`（clean 要求はしない — テスト実行が artifacts を作り得るため）。round = state round + 1。adapter は organ ラウンドと同じ選択則（`adapter_module(opts[:adapter])`）。
  2. 決定的一次: `Workspace.run_tests!`。
  3. 対象 change = active な organ `:change` のうち **entry_number 最大**（既存 `entry_number/1` を再利用）。無ければ `Mix.raise`。
  4. active な `:requirement` ごとに `QA.judge` → `:verdict` を absorb:
     author `"QA"`、text `QA判定 r<N>: <pass|fail> — テスト exit <E> / 突合: <matched|unmatched> <note>`、
     citations `[requirement.id, latest_change.id]`、meta `%{test_exit:, matched:, pass:, round:}`。**pass = (exit == 0 and matched)**。
  5. 合否は**このラウンドで absorb した verdict 群**（absorb の戻り値）で判定（過去ラウンドの fail verdict は履歴として active のまま残る）。
     全 pass → state `qa`/`done` + `print_qa_done`: verdict 数 / workspace HEAD 短縮 sha /
     **5ノード provenance** `verdict → change → decision → requirement → issue chunk`（implement の printer と同型で1段深く）。
  6. いずれか fail → **implement へ差し戻し**: fail verdict の text 群を「QA差し戻し:」として feedback に渡し、
     brief-26 の `run_organ_round` を再利用して organ ラウンド（round+1、approved = `approved_design_decisions`）→ 新 `:change` →
     `await_implement`（iteration 0）。state は `implement`/`awaiting_human` に戻る。
- **`implement_complete?` の強化（重要）**: 現行の「human の active :decision が active :change を引用」では、
  QA 差し戻し後に**古い gate-I 承認が新しい :change を未レビューのまま完了させてしまう**。
  → 「human の active `:decision` が **entry_number 最大の active organ `:change`** を引用していること」に変更。
  brief-26 の e2e は APPROVE が active :change 全部（最新含む）を引用するので green のまま。

## 4. 既存テストの更新（許される既存テスト変更はこれ1箇所のみ）

- brief-26 e2e（dev_task_test.exs「implement stage runs after design …」）末尾の `again = Dev.run_dev(...)` は、
  implement done 再実行 → **qa が走る**ようになる。この e2e は test_cmd `"true"`・IMPLEMENTED.md ありなので qa pass →
  assert を `again.state["stage"] == "qa"` / `"status" == "done"` に**更新**せよ（verdict の存在と citation の assert を足してよい）。

## 5. 新テスト（`test/dev_task_test.exs` 追記、必要なら `test/qa_test.exs`）

- Mock 分岐 unit: TRACEFIELD_QA の決定的応答（"IMPLEMENTED" 有 → matched true / 無 → false）。
- `QA.judge` フォールバック: 壊れた応答を返す fake adapter（テスト内に定義）で matched = (exit == 0) になること。
- e2e pass: `drive_to_implement_done!(dir)`（helper 抽出推奨）→ run → `qa`/`done`、active requirement ごとに `:verdict` が存在し
  `[requirement, latest change]` を引用、**5ノード連鎖**が entries 上で辿れる、再実行で done のまま。
- e2e fail→差し戻し→pass: test_cmd `"false"` で implement done（gate I は red 表示でも APPROVE）→ run →
  fail `:verdict`（meta pass=false）が残り state = `implement`/`awaiting_human`、新 `:change` と新 patch が存在、
  **古い gate-I 承認では完了しない**（= implement_complete? 強化の検証。resume しても human entries が無ければ awaiting のまま）
  → workspace.json の test_cmd を `"true"` に書き換え → pending に APPROVE → implement done（workspace に2つ目の apply commit）→
  run → qa pass / `qa`/`done`。
- 既存 121（§4 の1箇所更新を除き）green 維持。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（全 green）
3. 変更ファイル一覧

コミットしない。報告に変更ファイルとテスト結果。

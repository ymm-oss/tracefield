# 実装ブリーフ 6 — C1 固定Roleパイプライン（条件比較の足場）

> codex 指示（第6弾）。前提: brief 1-5 実装済。`mise exec -- mix ...`。ネット無し。コミットしない。
> 目的: 条件 C1（固定Roleパイプライン）を実装し、既存の measure/provenance がそのまま使える run 形を出す。
> C4(自由探索) と同じ scenario/汚染注入/点provenance を用い、後で C1 vs C4 vs C5 を比較できるようにする。

## 1. C1 ランナー（Explore と同じ run 形を返す）

新規 `Tracefield.Pipeline`（または `Explore` にモード追加でも可）:
- 固定Roleを順に1回ずつ: **PM → Engineer → UX → Risk → Legal → Security → FinalIntegrator**。
- 各Roleは task + これまでの transcript を見て、自分の観点から **points JSON**（brief-5 と同形式:
  `{"points":[{"text","depends_on_turns":[..],"uses_injection":bool}]}`）を出す。turn_id/point_id 付与は C4 と共通化。
- **汚染注入**: C4 と同じ `inject_after: initial-framing`（最初のRole=PM の直後に1度）。状態Aは contaminant、Bは correction。
- FinalIntegrator が synthesis（最終レビュー/推奨）を出す（C4 の synthesize 相当）。
- 返り値は C4 と同一形（raw_output, transcript[turn_id/points], state, seed, model, temperature）。
  → 既存 `GroundTruth.measure` / `Provenance` がそのまま適用可能。

## 2. 条件の選択

- `Explore.run`/`GroundTruth.run`/`GroundTruth.measure` に `:condition`（`:c4` 既定 / `:c1`）を通し、ランナーを切替。
- `tracefield.phase1` に `--condition c1|c4`（既定 c4）。出力に condition を明記。結果 map の `condition` を実値に。

## 3. Mock（Phase 0 維持 + C1 でも動く）

- Mock の explorer points 応答は Role 名（PM/Engineer/...）でも動くこと（汚染時の既知連鎖 X→Y→Z は C4 同様に再現できれば望ましいが必須でない）。
- 既定（c4・汚染a）の Phase 0/1 テストは不変（affected={consent}, proxy 1.0、provenance 連鎖テストも維持）。
- 追加テスト: `--condition c1`（mock）で run が完了し、measure が affected_set/provenance を返す（クラッシュしない）こと。

## 4. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（緑。C1 の最小テスト追加、既存全通過）
3. `mise exec -- mix tracefield.phase0`（従来どおり）
4. `mise exec -- mix tracefield.phase1 --adapter mock --condition c1 --n 2`（クラッシュせず、condition=c1 で affected/provenance 出力）

Ollama は実行しない。コミットしない。報告に変更ファイルと c1 mock 実行結果を含める。

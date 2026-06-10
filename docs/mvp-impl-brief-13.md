# 実装ブリーフ 13 — `tracefield.ideate`（最良構成での実アイデア生成・出力表示）

> codex 指示（第13弾）。前提: brief-9〜12 実装済（Reference / Agent(aware,private_doc,procedure,serve_policy) / Embed / Dissolution.measure_concerns）。
> 目的: §14 の最良構成（serve=diverse + aware + 手続き）で**新ドメインのアイデア生成**を実走し、
> **出てきたアイデアそのものを表示**する（メトリクスだけでなく定性出力を見せる）デモ用タスク。
> `mise exec -- mix ...`。ネット無し（mock テストのみ。実 ollama は私が回す）。コミットしない。

## 0. 前提（作成済みシナリオ）

`scenarios/housing-service/` に作成済み:
- `task.md`（アイデア出しの題目）
- `agents.json`（4ペルソナ: id/domain/desc/private_doc ファイル名。配列）
- `private/{kurashi,finance,gijutsu,chiiki}.md`（各ペルソナの私的知識）
- `procedure.md`（アイデア生成手続きのテキスト1個）

## 1. mix タスク `tracefield.ideate`

`mix tracefield.ideate --scenario scenarios/housing-service --adapter mock|ollama --rounds 3 --serve diverse --aware 1 --k 3 --model gemma4:12b --embed-model nomic-embed-text --temperature 0.6`

- 既定: rounds 3, serve diverse, aware 1, k(=k_s) 3, temperature 0.6。
- シナリオ読み込み:
  - task = `<scenario>/task.md`
  - agents = `<scenario>/agents.json` をパース（id, domain, desc, private_doc）。private_doc は `<scenario>/private/<file>` を読む。
  - procedure = `<scenario>/procedure.md`（存在すれば k_p=1 として FACILITATOR が absorb、全 agent に procedure_id を渡す）。
- Reference を task チャンク（type :chunk, author "TASK"）で種入れ。embed_adapter は adapter に追従（mock→Embed.Mock / ollama→Embed.Ollama）。
- agents を agents.json から構築（`Tracefield.Agent.new/4`、aware・serve_policy・k_s・private_doc・procedure_id・adapter・model・temperature・seed= 1000+index）。
- rounds ラウンド、各ラウンド全 agent が `run_turn`。absorbed entries（type :belief 等、:chunk/:procedure 除く）を「アイデア」として収集。

## 2. 出力（ここが主目的）

1. **アイデア一覧（定性・主役）**: round ごと・author ごとに、各アイデアの text と citations を読みやすく列挙。
   例:
   ```
   ── Round 1 ──
   [KURASHI] (cites: -) 設備の使い方が分からない施主向けに…
   [FINANCE] (cites: e2) 省エネ住宅の優遇金利を…
   ...
   ```
2. **健全性メトリクス（従属）**: `Dissolution.measure_concerns(concerns_by_agent, adapter/embed/seed...)` を再利用して
   coverage（distinct アイデア数）・diversity・collapse_rate を表示。discovery/ICC judge は呼ばない（アイデア出しに正解はない）。
3. **横断引用の可視化**: 他 author の entry を citation した（＝領域をまたいだ）アイデアの件数と一覧を別掲。
   （citation 先 entry の author ≠ 自分、を「cross-author 合成」とみなす。procedure_id は除外してカウント。）
4. runs/ に JSON 保存（task, config, 全 entries, metrics）。

## 3. Mock 拡張（テスト用フォールバック）

既存 `TRACEFIELD_AGENT_TURN` mock は agent id が SEC/BIZ/UX 前提。housing の id（KURASHI 等）でも**クラッシュせず**動くよう:
- agent id が未知の場合の**汎用フォールバック**: 「PRIVATE DOCUMENT の最初の語＋（提示があれば）先頭 entry の id を citation にした belief」を1件返す（決定的）。
- これで ideate の mock e2e が成立（各 agent が最低1アイデアを出し、cross-author 引用が round2 以降で発生しうる）。

## 4. テスト

- `agents.json` 読み込み＋private_doc 解決のユニットテスト（4件、private_doc 本文が読めること）。
- ideate mock e2e（rounds 2, serve diverse, aware 1）: クラッシュせず、各 agent がアイデアを出し、metrics（coverage>0, diversity is float）が出ること、cross-author 引用件数が算出されること。
- 既存テスト全 green。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.ideate --scenario scenarios/housing-service --adapter mock --rounds 2`（アイデア一覧＋メトリクス＋cross-author が表示される）

コミットしない。報告に変更ファイルと mock 出力例。

# 実装ブリーフ 30 — 動的エージェント構成 v1（Recruiter + gate 付き投入 + 撤回連鎖 + 退役助言）

> cursor-agent 指示（第30弾）。前提: issue-001〜004 まで（143 tests、Coverage 助言 v1 実装済み）。
> `mise exec -- mix ...`。ネット不可。**tracefield リポジトリに git commit しない**。mise.toml に触れない。
> 着手前に必読: `lib/tracefield/coverage.ex` / `lib/mix/tasks/tracefield.dev.ex`（warn_uncovered_chunks! / load_actors! / build_agent）/
> `lib/tracefield/agent.ex`（sanitize_entry / append_procedure_id の機構）/ `lib/tracefield/reference.ex`（@types / retract / closure / propagate）/ `test/coverage_test.exs`。
> 核心: 名簿（actors.json）の変更を**来歴のある統治対象**にする。投入提案は citable entry、採用は明示操作、
> 投入されたエージェントの全貢献は提案 entry を自動引用する —— **提案の retract → 閉包隔離でそのエージェントの貢献が無効化できる**。
> 投入は助言→提案→人間採用の三段で、自動化はしない（半溶解性の統治境界）。

## 1. `Reference` — `@types` に `:recruit` を追加（永続/replay は既存機構で自動）。

## 2. 提案生成（決定的、`--recruit` フラグ）

- `mix tracefield.dev` に `--recruit`（boolean、既定 false）を追加。
- refine 開始時、`warn_uncovered_chunks!` が無人チャンクを検出**かつ** `--recruit` 指定時:
  無人チャンク群から **1つ**の `:recruit` 提案 entry を決定的に生成して absorb する。
  - author `"RECRUITER"`、citations = 無人チャンク entry ids（= 根拠）、
  - text = `投入提案: 無人領土 <file名 カンマ区切り> を担当するレンズ。id候補 <ID>、domain候補 <domain>`
    （ID は file 名から決定的に導出。例: `impl-context.md` → `LENS-IMPL-CONTEXT`。domain は v1 では `"territory"` 固定でよい）、
  - meta = `%{actor_id:, domain:, desc:, territory_files: [...]}`（採用時に必要な全情報）。
- 同一提案の重複 absorb は `absorb_idempotent` で防ぐ。無人チャンクが無ければ何もしない。
  `--recruit` なしの挙動は現行と完全一致。表示: `⚠ recruit 提案 <entry_id>: <text>`。

## 3. 採用（人間の明示操作 = gate）

- `mix tracefield.dev --adopt-recruit <entry_id>` を追加（`--issue` と併用）。
  1. 当該 entry が存在し type `:recruit` かつ **active** であることを検証（retract 済み・不在は `Mix.raise`）。
  2. actors.json に actor を追記: `{"id": meta.actor_id, "domain": meta.domain, "desc": meta.desc, "kind": "llm", "recruit_entry": "<entry_id>"}`。
     既に同 id が居れば `Mix.raise`（二重採用防止）。
  3. `採用: <actor_id>（recruit <entry_id>）を名簿に追加` を表示して終了（stage は進めない）。
- `load_actors!` は `"recruit_entry"` を actor map の `recruit_entry`（無ければ nil）として読む。

## 4. 撤回連鎖（本ブリーフの統治の要）

- `Agent.new` に `recruit_id:`（string、既定 nil）opt を追加。
- nil でない場合、その agent が absorb する**全 entry の citations 末尾に recruit_id を自動追記**する
  （`append_procedure_id` と同じ機構・同じ位置に `append_recruit_id` を実装。重複追記しない。
  Human adapter には適用不要 — 人間は recruit されない）。
- dev タスクの `build_agent` は actor の `recruit_entry` を `recruit_id:` に渡す。
- これにより既存の retract/closure/propagate 機構が**無改修で**効く:
  `Reference.retract(recruit_entry)` → closure に投入エージェントの全 entry が入る → 隔離。
  （= 投入の前提が誤りだったとき、そのエージェントの影響を一括無効化できる）

## 5. 退役助言（決定的・表示のみ）

- `--status` 実行時、各 llm/cli actor について store 内の被引用数
  （その actor が author の active entry が、他 author の active entry から引用されている数）を表示し、
  **自分の entry が1件以上あるのに被引用 0** の actor に `⚠ retire候補: <actor_id>（被引用 0）` を付す。
  表示のみ。自動除籍はしない。

## 6. テスト（`test/recruit_test.exs` 新規推奨 + 既存ファイル追記）

- 提案生成: 無人チャンクあり+--recruit → :recruit entry（author RECRUITER、citations=無人チャンク ids、meta 完備）。
  --recruit なし → 生成されない。無人チャンクなし+--recruit → 生成されない。再実行で重複しない（idempotent）。
- 採用: actors.json 追記内容・load_actors! の recruit_entry 読み込み・非 active 提案で raise・同 id 二重採用で raise。
- 撤回連鎖（要): recruit_id 付き agent（mock）の entry が recruit_id を引用していること。
  `Reference.retract(提案id)` → `closure` に当該 agent の entries が含まれ quarantine されること。
- 退役助言: 被引用 0 actor の表示 / 被引用ありの actor は表示されない（capture_io）。
- e2e（mock）: 無人チャンクのある issue dir → --recruit 付き初回実行で提案 → --adopt-recruit → 次の run で新 actor が
  ラウンドに参加し entries が recruit_id を引用 → 提案 retract → propagate 後に新 actor の entries が quarantined。
- 既存 143 green 維持。

## 7. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（143 + 新規、全 green）
3. 変更ファイル一覧

コミットしない。報告に変更ファイルとテスト結果。

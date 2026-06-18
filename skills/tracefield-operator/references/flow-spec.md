# flow.toml 仕様

`scenarios/<name>/flow.toml` の全フィールド・有効値。値はソース（`crates/tracefield-core/src/flow.rs`,
`llm.rs`）が真実源。`agents.json` とディレクトリ構成は [scenario-format.md](./scenario-format.md)。

## `[flow]`（必須）

| key | 型 | 既定 | 説明 |
| --- | --- | --- | --- |
| `profile` | string | — | 任意のラベル（メタに記録） |
| `policy` | string | `"fixed"` | `fixed` / `best_first` / `adaptive_branching` / `multi_organ_adaptive` |
| `budget` | int | — | 全体のエントリ予算（任意） |
| `max_feedback_cycles` | int | — | フィードバック上限（任意） |

## `[actor_scaling]`

| key | 型 | 既定 | 説明 |
| --- | --- | --- | --- |
| `default_mode` | string | `"fixed"` | mode 未指定ステージの既定 actor mode |
| `max_total_actors` | int | — | run 全体の actor 上限 |
| `max_parallel_actors` | int | — | 同時実行 actor 上限 |

## `[long_run]`（反復／denoise）

| key | 型 | 既定 | 説明 |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | サイクル反復を有効化 |
| `cycles` | int | `1` | サイクル数（≥1） |
| `cycle_stages` | string[] | `[]` | 各サイクルで反復するステージ id。空なら artifact 以外の全ステージ。ここに入れないステージは最後に1回だけ実行 |
| `max_work_items` | int | — | work item 上限（任意） |

## `[organs.<id>]`（モデル器官。ステージが `organ = "<id>"` で参照）

| key | 型 | 既定 | 説明 |
| --- | --- | --- | --- |
| `adapter` | string | `"mock"` | `mock` / `ollama` / `cli` / `openrouter` / `codex-app-server`（`codex_app_server` も可） |
| `model` | string | — | 下表「アダプタとモデル」参照 |
| `command` | string | — | `cli` のときの実行コマンド（`claude` / `codex` / `cursor-agent`）。`claude-code` は `claude` の別名。`codex-app-server` では不要 |
| `max_tokens` | int | — | 出力トークン上限 |
| `timeout_seconds` | int | `300` | 1リクエストのタイムアウト |

## `[stages.<id>]`（ステージ。宣言順に実行）

| key | 型 | 既定 | 説明 |
| --- | --- | --- | --- |
| `organ` | string | `"mock"` | 使う `[organs.<id>]` の id |
| `inputs` | string[] | （空なら task＋retrieval） | 入力セレクタ（下表） |
| `outputs` | string[] | — | このステージが出すエントリ型（下表） |
| `budget` | int | — | このステージのエントリ予算 |

サブテーブル `[stages.<id>.actors]`:

| key | 型 | 既定 | 説明 |
| --- | --- | --- | --- |
| `mode` | string | `actor_scaling.default_mode` | `fixed` / `per_input` / `per_source` / `per_cluster` / `per_agent` / `auto` / `none` |
| `count` | int | `1` | `mode="fixed"` のときの actor 数 |
| `min` / `max` | int | — | `auto` 時の下限/上限 |
| `roles` | string[] | `[]` | actor を駆動する **agents.json の id**。role が agent id に一致するとその agent の lens（domain/desc/private）で駆動。長 N の roles に対し actor i は `roles[i % N]` を使う |
| `scale_by` | string[] | `[]` | スケール基準（高度） |

サブテーブル `[stages.<id>.context]`（任意・入力の整形）:

| key | 型 | 説明 |
| --- | --- | --- |
| `mode` | string | `head` / `source_excerpt` |
| `chars_per_entry` | int | エントリ毎の文字上限 |
| `chars_total` | int | 合計文字上限 |
| `keywords` | string[] | source_excerpt の抽出キーワード |

### actor mode の意味

- `fixed`：`count` 個（roles を循環割当）。
- `per_input`：入力エントリ**1件＝1 actor**（反証ごと独立審判に使う）。`roles` 長1なら全 actor が同一 lens。
- `per_agent`：agents.json の数だけ。`per_source` / `per_cluster`：source/cluster 単位。
- `auto`：入力規模から `min`〜`max` で自動。`none`：actor 0（ステージをスキップ）。

## 入力セレクタ（`inputs`）

| 記法 | 選択対象 |
| --- | --- |
| `path:<file>` | `meta.path` がその値のエントリ（例 `path:task.md`） |
| `stage:<id>` | そのステージの全 active エントリ（**サイクル横断**） |
| `entry_type:<t>` | その型の全 active エントリ |
| `kind:<k>` | `meta.kind` 一致 |
| `source_url:<url>` | `meta.source_url` 一致 |
| `all` | 全 active エントリ |

`inputs` を空にすると task＋自動 retrieval（最大12件）になる。

## 出力エントリ型（`outputs`）

`observation` / `decision` / `question` / `stance` / `hypothesis` / `belief` /
`requirement` / `answer` / `change` / `verdict` / `claim` / `synthesis` / `audit`
（未知の値は `belief` 扱い）。

## アダプタとモデル（`model` に何を書くか）

| adapter | model に書く値 | 確認方法 |
| --- | --- | --- |
| `mock` | 不要（`"none"` か省略） | — |
| `ollama` | pull 済みモデル名（例 `gemma4:31b-it-qat`, `qwen3.6:27b`） | `ollama list` |
| `cli` (`command="claude"`) | claude のモデル id（例 `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`） | `claude --help` の `--model` |
| `cli` (`command="codex"`) | `codex`（codex 側がモデルを決める） | — |
| `cli` (`command="cursor-agent"`) | 既定 `composer-2.5` | — |
| `codex-app-server` | 任意の codex モデル id（省略可、未指定なら codex 既定） | `codex` を PATH に。tool 使用と provenance 対応 |
| `openrouter` | `provider/model` slug（例 `openai/gpt-5.5`） | OpenRouter のモデル一覧。`OPENROUTER_API_KEY` 必須 |

`cli` + `command="codex"` は one-shot の `codex exec`。`codex-app-server` は `codex app-server`
の JSON-RPC stdio プロトコルで駆動し、ツール活動を provenance エントリとして残せる（別物）。

固定の「選択可能モデル一覧」は存在しない（adapter とローカル環境に依存）。`tracefield doctor` で
利用可能アダプタを確認する。**弱いモデルは大入力で合成が崩れやすい**（設計判断は tracefield-flow-design）。

## artifacts（成果物出力。任意）

`[stages.<id>.artifact]` または top-level `[artifacts.<id>]` で `format` / `from_stage` /
`path` を指定するとレポート/デッキ等を書き出す（`.manifest.json` に source id を併記）。高度機能。

## 高度: `[feedback]` / `[feedback_entries]` / `[process]`

エージェントが `meta.kind="tracefield_feedback"` で改善を差し戻す経路（`[feedback.edge]` /
`[feedback_entries.route]`）、および process ステージの構成。通常の審議・調査フローでは不要。
実例は `scenarios/latest-ai-orchestration-tracefield-feedback/flow.*.toml`。

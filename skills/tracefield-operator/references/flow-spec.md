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
| `input_chunk_paragraphs` | int | `0`（=分割しない） | seed 時に各 `inputs/*` を N 段落（空行区切り）単位で chunk 化し distinct path 付与。長文を `per_input` で網羅抽出する用（private/task は対象外） |

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
| `web_search` | bool | `false` | codex の native `web_search` ツールを有効化（`-c tools.web_search=true`＝`codex --search` 相当、per-call 承認なし）。`adapter="cli" command="codex"` と `adapter="codex-app-server"` の両方で動作（検証済み）。出典URL付きの observation が出て、`codex-app-server` では各検索が `kind="codex_web_search"` の provenance エントリとしても記録される |

## `[stages.<id>]`（ステージ。宣言順に実行）

| key | 型 | 既定 | 説明 |
| --- | --- | --- | --- |
| `organ` | string | `"mock"` | 使う `[organs.<id>]` の id |
| `inputs` | string[] | （空なら task＋retrieval） | 入力セレクタ（下表）。actor mode で shard される |
| `shared_inputs` | string[] | `[]` | 全 actor に**共有**で渡すセレクタ（shard されない）。`per_input` で `inputs` を1件ずつ shard しつつ、閉じた一覧を全 actor に渡す用途。例: stance を1件ずつ shard＋確定 matter 一覧を全 actor へ→単一 LLM の collapse 無しで no-drop ラベル付け |
| `outputs` | string[] | — | このステージが出すエントリ型（下表） |
| `grounded` | bool | `false` | 接地ゲートを有効化。各非 question 主張に `meta.evidence_quote`（引用元の逐語部分文字列）を要求し、それを**引用 store エントリ本文 ∪ `meta.source_path`(+`source_line`) の実ファイル**に機械照合する。外れたら `evidence_quote_not_found`＋`evidence_strength=needs_review`（per-claim・retract 閉包内・no-silent-drop）。`source_`/`web`/`data` を含む id/organ/role でも自動 true（既存ヒューリスティック）。読み取り正準骨格・コード抽出での捏造検出に使う |
| `retract_overturned` | bool | `false` | このステージ後に `reconcile_overturned` を走らせ、`判定: 結論変更…` の verdict が指す `meta.refutes` 主張を機械 retract（adjudication 段に置く） |
| `supersede_marked` | bool | `false` | このステージ後に `reconcile_superseded` を走らせ、各産出エントリが `meta.supersedes`（id 配列 or scalar）で名指した熟考エントリを機械 supersede（消さず格下げ・引用閉包に保持＝来歴/コスト）。`retract_overturned` と対称で「何が置き換えたか」を記録。LLM 合成器なしの昇華段（出来事→commit→supersede）。対象が live でなければ UNACTIONED として可視化（no silent drop） |
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
- `per_input`：入力エントリ**1件＝1 actor**（反証ごと独立審判に使う）。`roles` 長1なら全 actor が同一 lens。`shared_inputs` のエントリは shard されず各 actor に共有される（閉じた一覧を全 actor へ渡し no-drop ラベル付けする等）。
- `per_agent`：agents.json の数だけ。`per_source` / `per_cluster`：source/cluster 単位。
- `auto`：入力規模から `min`〜`max` で自動。`none`：actor 0（`command`/`clustering` 併用時はそれが走る、無ければスキップ）。

サブテーブル `[stages.<id>.command]`（任意・決定論コマンドステージ＝probe）:

LLM actor の代わりに外部コマンドを1回実行し stdout を1エントリに畳む決定論ステージ。
**レンズ（解釈）でなくセンサ（計測）**。`fslc` / `cargo test` / linter 等で主張を接地する。

| key | 型 | 既定 | 説明 |
| --- | --- | --- | --- |
| `program` | string | （必須） | 実行するプログラム |
| `args` | string[] | `[]` | 引数。`{input}` は選択エントリを書いた一時ファイルのパスに置換される |
| `cwd` | string | scenario dir | 作業ディレクトリ（scenario dir からの相対） |
| `timeout_seconds` | int | `600` | タイムアウト |

- 併用必須 `[stages.<id>.actors] mode = "none"`（LLM actor と排他。`clustering` とも排他）。
- `inputs` の選択エントリ本文が `\n\n` 連結で一時ファイルに書かれ、`args` 内の `{input}` がそのパスに置換される（`{input}` を使わなければ静的コマンド）。fence 抽出など**道具固有の整形はコマンド文字列側**に置く（例 `program="bash"`, `args=["-lc","awk '...' \"$0\" > \"$0.fsl\"; fslc verify \"$0.fsl\"","{input}"]`）。stdin は渡さない（必要なら `< {input}`）。
- 結果は1エントリ（`outputs` 先頭型・既定 `observation`）。stdout が本文、exit code は `meta.exit_code`、選択エントリを**引用**する（retract 閉包に入る）。**非ゼロ終了はエラーでなく所見**として記録（spawn 失敗・timeout のみ run を止める）。
- ⚠ サンドボックス無し: tracefield の権限でそのまま走る。read-only / no network は著者責任。

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
描画は機械的（LLM不使用）。`format` は既定 `markdown` / `slides_markdown`（Marp）のほか `contested_map`（`meta.matter` でグループ化し**対立を解決せず提示**＝無落とし＋2者以上で `⚠ CONTESTED`）。

## 高度: `[feedback]` / `[feedback_entries]` / `[process]`

エージェントが `meta.kind="tracefield_feedback"` で改善を差し戻す経路（`[feedback.edge]` /
`[feedback_entries.route]`）、および process ステージの構成。通常の審議・調査フローでは不要。
実例は `scenarios/latest-ai-orchestration-tracefield-feedback/flow.*.toml`。

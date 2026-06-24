# Tracefield User Guide

このガイドは、Tracefield を使ってシナリオを作成し、複数のエージェントで検討を回し、必要に応じて provenance と retraction を確認するための手順をまとめたものです。

Tracefield の現行実装は Rust CLI です。古い Mix/Elixir コマンドは使いません。

## Tracefield でできること

Tracefield は、複数の AI エージェントに同じ課題を異なる観点から検討させ、その入力と出力の関係を citation として残す CLI ツールです。

主な用途:

- 設計レビュー、事業判断、運用リスク整理などの検討を複数観点で回す
- エージェントごとに private document を与え、観点の違いを作る
- ユーザー定義 skill を procedure として注入し、skill の影響も追跡する
- flow 実行結果を JSONL store に保存し、ある entry の downstream 影響を retract する
- `flow.toml` で stage / actor scaling / organ routing / feedback / artifact を定義し、`tracefield run` で汎用 Field Runner flow を実行する

## インストールと確認

必要なもの:

- Rust と Cargo
- Ollama を使う場合は Ollama
- OpenRouter を使う場合は `OPENROUTER_API_KEY`

リポジトリでビルドします。

```sh
cargo build --release -p tracefield
cargo check -p tracefield
cargo test
```

インストールする場合:

```sh
cargo install --path crates/tracefield-cli --locked
tracefield doctor
```

ワークスペース内の release binary を直接使う場合:

```sh
./target/release/tracefield doctor
```

`doctor` は adapter の準備状況を表示します。`mock` は常に使えます。`ollama`、`openrouter`、`cli` は環境に応じて確認されます。

## 最短の実行

まず model-free の mock adapter で動作確認します。

```sh
tracefield run --scenario-dir scenarios/generic-smoke
```

Field Runner flow を確認する場合:

```sh
tracefield new my-flow
tracefield web-input --scenario-dir scenarios/my-flow --url https://example.com/source
tracefield run --scenario-dir scenarios/my-flow
```

`web-input` はURLを取得して `inputs/web/` にMarkdownとして保存します。保存されたファイルには `source_url`、`fetched_at`、`content_type`、`bytes` が入り、`tracefield run` では通常の `kind:input` としてseedされます。複数URLは `--url` を繰り返すか、1行1URLの `--url-file` を渡します。

`tracefield` が PATH に無い場合は release binary を直接使います。

```sh
./target/release/tracefield run --scenario-dir scenarios/generic-smoke
```

mock adapter はモデル、ネットワーク、API key を必要としません。シナリオ構造と出力形式の確認に使います。

## シナリオを作る

新しいシナリオを scaffold します。

```sh
tracefield new my-review --profile consult
```

長時間調査向けの全層テンプレートを作る場合:

```sh
tracefield new my-investigation --profile deep_investigation
```

生成される基本構造:

```text
scenarios/my-review/
├── task.md
├── agents.json
├── flow.toml
├── inputs/
│   └── example.md
└── private/
    ├── lens1.md
    └── lens2.md
```

ユーザー独自 skill を使う場合は `skills/` を追加します。

```text
scenarios/my-review/
├── task.md
├── agents.json
├── flow.toml
├── inputs/
├── skills/
│   └── review/
│       └── SKILL.md
└── private/
    ├── risk.md
    └── value.md
```

## flow.toml

`flow.toml` は `tracefield run` 用の設定です。stage、actor数、organ、artifact出力を定義します。

最小例:

```toml
[flow]
profile = "default"
policy = "fixed"

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "per_input"
max = 2

[stages.analyze]
organ = "reasoning"
inputs = ["stage:collect"]
outputs = ["synthesis", "question"]

[stages.analyze.actors]
mode = "fixed"
count = 1

[artifacts.summary]
format = "markdown"
from_stage = "analyze"
path = "outputs/summary.md"
```

`inputs/` 配下の `.md` / `.txt` / `.json` / `.jsonl` は `corpus_chunk` としてseedされます。`tracefield run` は各stageの出力をentryとして保存し、artifact設定があればMarkdownなどを `outputs/` に生成します。

`consult` profile は `[organs.reasoning] adapter = "mock"` と `[long_run] cycles = 2` を既定にします。adapter / model は CLI フラグではなく `flow.toml` の `[organs.reasoning]` で指定します。旧 `--rounds N` 相当の反復数は `[long_run] cycles = N` です。

stageの `inputs` では `kind:input`、`stage:<id>`、`entry_type:<type>`、`path:<inputs/...>`、`source_url:<url>`、`all` を使えます。`path:` と `source_url:` は、特定web pageだけで小さく検証する場合や、分析層からページ層へtargeted recollectionを返す場合に使います。

`--persist <file>.jsonl` を指定すると、既存storeがあれば読み込んでから続行します。`task`、`inputs/`、`private/`、`skills/` のseed entryは `kind` / `path` で再利用されるため、同じstoreに対する再実行でsource seedが重複しにくくなっています。

artifactを生成した場合は、出力ファイルに加えて `<artifact>.manifest.json` も作成されます。manifestにはartifactが参照したentry id、stage、citationが入り、報告書やスライドからTracefield entryへ戻れるようにします。

レンズが構造的な発見をした場合、通常 entry に `structured_deltas` を添えられます。runner はこれを sibling entry に展開し、`kind = "obstruction" | "invariant" | "completion_candidate" | "morphism"` として保存します。

```json
{
  "entries": [
    {
      "type": "observation",
      "text": "The recommendation plan has a consent-scope risk.",
      "citations": ["e1"],
      "structured_deltas": [
        {
          "kind": "obstruction",
          "type": "consent_scope_mismatch",
          "location_cell_ids": ["e1"],
          "severity": "high",
          "required_resolution": "clarify consent scope before promotion",
          "review_status": "unreviewed"
        }
      ]
    }
  ]
}
```

agentがTracefield自体への改善を見つけた場合は、通常entryとして `meta.kind = "tracefield_feedback"` を付けます。runnerは `[feedback_entries]` と `[[feedback_entries.route]]` に従い、そのentryを再収集、分析、監査、artifact生成などの層へ戻します。

```toml
[feedback_entries]
enabled = true
kind = "tracefield_feedback"
accepted_types = ["change", "requirement", "question", "audit"]
status_field = "status"
dedupe_by = ["target", "action", "normalized_request"]

[[feedback_entries.route]]
target_prefix = "input.web"
to = "source_discovery"

[[feedback_entries.route]]
target_prefix = "flow."
to = "feedback_triage"
```

feedback entryの標準metadataは `target`、`action`、`priority`、`status` です。例: `{"kind":"tracefield_feedback","target":"flow.stage.source_extract","action":"change","priority":"high","status":"proposed"}`。

`tracefield new --profile deep_investigation` は、source discovery、source clustering、source extraction、hypothesis、lens analysis、audit、report/deck artifact production を含むテンプレートを生成します。データ層は `cli` 経由の `/Users/rizumita/Workspace/github/ds4/ds4`、推論層は `cli` の `codex` を使う設定です。`per_input` / `per_source` / `per_cluster` のactorは入力をshardして受け取り、`[stages.<id>.clustering]` を持つstageは `source_cluster` metadata付きのcluster entryを生成します。

## task.md

`task.md` には全エージェントが共有する課題を書きます。private な根拠や役割別の材料は入れず、検討対象だけを具体的にします。

例:

```markdown
Evaluate the proposed internal support workflow and identify risks, missing
requirements, and operational tradeoffs.
```

## agents.json

`agents.json` は、どのエージェントがどの観点で検討するかを定義します。

```json
{
  "agents": [
    {
      "id": "RISK",
      "domain": "risk",
      "desc": "Focus on failure modes, compliance, and operational constraints.",
      "doc": "risk.md",
      "skills": ["review"]
    },
    {
      "id": "VALUE",
      "domain": "value",
      "desc": "Focus on user value, adoption, and business outcomes.",
      "doc": "value.md"
    }
  ]
}
```

主なフィールド:

- `id`: entry の author として使われる短い安定 ID
- `domain`: retrieval/query のヒント
- `desc`: エージェントの役割説明
- `doc`: `private/` 配下の private document
- `model`: 任意の per-agent model override
- `skills`: 任意の scenario-local skill id のリスト

## private documents

`private/*.md` には、そのエージェントだけに渡したい観点、事実、制約、懸念を書きます。

例:

```markdown
Known constraints:
- Support tickets must keep audit trails for 180 days.
- Operators currently handle about 400 tickets per week.

Concerns:
- Role boundaries are ambiguous during escalation.
```

## ユーザー独自 skill

skill は scenario-local な手続きです。`agents.json` の `skills` で参照された skill は、agent skill の基本形に合わせて `skills/<id>/SKILL.md` から読み込まれます。

```text
skills/<id>/SKILL.md
```

skill id は lowercase ASCII letters、digits、`-` のみ使えます。folder name、`agents.json` の id、frontmatter の `name` は一致している必要があります。

例:

```markdown
---
name: review
description: Check claims against explicit evidence before recommending changes.
---

# Review

Before recommending a change, check whether the claim depends on an explicit
source, a private lens, or an assumption that should be stated separately.
```

読み込まれた `SKILL.md` は `procedure` entry として reference store に seed されます。agent prompt には frontmatter を解釈した `name`、`description`、本文 instructions が渡されます。その skill を使う agent が生成した entry には、procedure entry id が citation として自動付与されます。これにより、skill の影響も downstream retraction の対象になります。

現時点で Tracefield が実行するのは `SKILL.md` の instructions 注入です。`references/`、`scripts/`、`assets/` のような bundled resources は、agent skill の構造として置くことはできますが、Field Runner flow が自動実行・自動読込する対象ではありません。必要な内容は `SKILL.md` 本文に要約するか、scenario の `private/*.md` として明示的に渡してください。

## flow を実行する

まず `consult` profile の既定 mock でシナリオ品質を確認します。

```sh
tracefield run --scenario-dir scenarios/my-review
```

`tracefield run` は scenario 内の `flow.toml` を使います。明示する場合は `--config flow.toml` を付けます。

ローカル Ollama で実行する場合:

```toml
# scenarios/my-review/flow.toml
[organs.reasoning]
adapter = "ollama"
model = "gemma4:12b"
```

```sh
ollama serve
ollama pull gemma4:12b
tracefield run --scenario-dir scenarios/my-review
```

CLI adapter を使う場合:

```toml
# scenarios/my-review/flow.toml
[organs.reasoning]
adapter = "cli"
model = "<model>"
```

CLI adapter のデフォルトは `cursor-agent` です。Claude Code を使う場合:

```sh
TRACEFIELD_CLI_COMMAND=claude tracefield run --scenario-dir scenarios/my-review
```

`claude-code` も alias として受け付け、実行時には `claude` binary を呼びます。

Codex CLI を使う場合:

```sh
TRACEFIELD_CLI_COMMAND=codex tracefield run --scenario-dir scenarios/my-review
```

Codex は `codex exec` で起動し、`--output-last-message` に書かれた最終応答を Tracefield が読みます。

OpenRouter を使う場合:

```toml
# scenarios/my-review/flow.toml
[organs.reasoning]
adapter = "openrouter"
model = "openai/gpt-5.5"
```

```sh
export OPENROUTER_API_KEY=...
tracefield run --scenario-dir scenarios/my-review
```

## 出力形式

デフォルトでは人間向けの report が標準出力に表示されます。

compact JSON が必要な場合:

```sh
tracefield run --scenario-dir scenarios/my-review --json
```

pretty JSON report をファイルに保存する場合:

```sh
tracefield run --scenario-dir scenarios/my-review --out runs/my-review.json
```

## provenance を保存する

後で retraction を確認したい場合は JSONL store に保存します。

```sh
tracefield run \
  --scenario-dir scenarios/my-review \
  --persist runs/my-review.jsonl
```

store には task、input、private document、skill procedure、flow output が entry として保存されます。entry id は `e1`, `e2`, ... の形式です。

## structural view を生成する

JSONL store を canonical log として残したまま、HigherGraphen 風の構造ビューへ materialize できます。

```sh
tracefield structural-view \
  --store runs/my-review.jsonl \
  --out runs/my-review.structural-view.json
```

この view では entry が cell、citation が incidence / derivation morphism、`meta.refutes` が obstruction として表現されます。`impact_cones` には、その cell を起点にした downstream citation impact と projection impact が入ります。`--active-only` を付けると、retracted / superseded entry を除いた live view だけを生成します。

deterministic check だけを実行する場合:

```sh
tracefield structural-checks --store runs/my-review.jsonl
```

flow に stage として組み込む場合:

```toml
[stages.structural_verify]
inputs = ["all"]
outputs = ["audit"]

[stages.structural_verify.actors]
mode = "none"

[stages.structural_verify.structural_checks]
enabled = true
checks = ["obstruction_presence", "dangling_incidence"]
scope = "store"
active_only = true
```

この stage は LLM を呼ばず、materialized structural view に対して blocking obstruction、dangling incidence、unreviewed invariant / completion candidate を `audit` entry として出します。

## retract する

ある entry が誤り、汚染、撤回済みだった場合、その downstream citation closure を retracted にできます。

```sh
tracefield retract --store runs/my-review.jsonl --entry e3
```

`retract` は対象 entry を直接引用している entry と、その先の downstream entry をたどって retracted にします。skill procedure を retract した場合、その skill を citation している agent output も closure に含まれます。

## よくある運用順序

1. `tracefield doctor` で環境を確認する。
2. `tracefield new <name> --profile consult` でシナリオを作る。
3. `task.md`、`agents.json`、`private/*.md` を編集する。
4. 必要なら `skills/<id>/SKILL.md` を追加し、agent の `skills` から参照する。
5. `tracefield run` でシナリオと出力を確認する。
6. Ollama、CLI、OpenRouter などの live adapter は `flow.toml` で adapter / model を指定して実行する。
7. provenance が必要なら `--persist` で JSONL store を保存する。
8. 誤った entry や skill の影響を確認したい場合は `retract` を使う。

## トラブルシュート

`tracefield` が見つからない場合:

```sh
cargo install --path crates/tracefield-cli --locked
which tracefield
```

Ollama が reachable でない場合:

```sh
tracefield doctor
ollama serve
ollama pull <model>
```

OpenRouter が失敗する場合:

```sh
echo "$OPENROUTER_API_KEY"
tracefield doctor
```

flow output が弱い、または generic な場合は、live model の前に mock で scenario を見直します。

- `task.md`: 判断対象や調査対象を具体化する
- `agents.json`: `domain` と `desc` の差を明確にする
- `[stages.*.actors] roles`: agent の `id` を書くとその agent の lens（domain/desc/private）で actor を束縛できる。`roles` を省略すると agent の `domain` がそのまま role になるので、観点を stage 毎に書き直さなくてよい
- `private/*.md`: 事実、制約、観測、既知の tradeoff を足す
- `skills/<id>/SKILL.md`: agent に適用したい手順を短く明確に書く

## 現在の制約

- Historical Mix/Elixir task surface は現行実装では使えません。
- `phase1`、`hetero`、`ideate`、`genesis`、`bridge`、`field` などの古い experiment runner は Rust CLI に未移植です。
- skill は現時点では scenario-local な procedure prompt です。外部 tool execution や MCP skill 実行基盤ではありません。
- CLI adapter は外部 CLI の挙動に依存します。Tracefield が外部 CLI 内部の hidden tool usage を完全には監査できません。

# Tracefield User Guide

このガイドは、Tracefield を使ってシナリオを作成し、複数のエージェントで検討を回し、必要に応じて provenance と retraction を確認するための手順をまとめたものです。

Tracefield の現行実装は Rust CLI です。古い Mix/Elixir コマンドは使いません。

## Tracefield でできること

Tracefield は、複数の AI エージェントに同じ課題を異なる観点から検討させ、その入力と出力の関係を citation として残す CLI ツールです。

主な用途:

- 設計レビュー、事業判断、運用リスク整理などの検討を複数観点で回す
- エージェントごとに private document を与え、観点の違いを作る
- ユーザー定義 skill を procedure として注入し、skill の影響も追跡する
- consult 結果を JSONL store に保存し、ある entry の downstream 影響を retract する

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
tracefield consult --scenario-dir scenarios/generic-smoke --adapter mock
```

`tracefield` が PATH に無い場合は release binary を直接使います。

```sh
./target/release/tracefield consult --scenario-dir scenarios/generic-smoke --adapter mock
```

mock adapter はモデル、ネットワーク、API key を必要としません。シナリオ構造と出力形式の確認に使います。

## シナリオを作る

新しいシナリオを scaffold します。

```sh
tracefield new my-review
```

生成される基本構造:

```text
scenarios/my-review/
├── task.md
├── agents.json
└── private/
    ├── lens1.md
    └── lens2.md
```

ユーザー独自 skill を使う場合は `skills/` を追加します。

```text
scenarios/my-review/
├── task.md
├── agents.json
├── skills/
│   └── review/
│       └── SKILL.md
└── private/
    ├── risk.md
    └── value.md
```

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

現時点で Tracefield が実行するのは `SKILL.md` の instructions 注入です。`references/`、`scripts/`、`assets/` のような bundled resources は、agent skill の構造として置くことはできますが、Tracefield consult が自動実行・自動読込する対象ではありません。必要な内容は `SKILL.md` 本文に要約するか、scenario の `private/*.md` として明示的に渡してください。

## consult を実行する

まず mock でシナリオ品質を確認します。

```sh
tracefield consult --scenario-dir scenarios/my-review --adapter mock
```

ローカル Ollama で実行する場合:

```sh
ollama serve
ollama pull gemma4:12b
tracefield consult --scenario-dir scenarios/my-review --adapter ollama --model gemma4:12b
```

CLI adapter を使う場合:

```sh
tracefield consult --scenario-dir scenarios/my-review --adapter cli --model <model>
```

CLI adapter のデフォルトは `cursor-agent` です。Claude Code を使う場合:

```sh
TRACEFIELD_CLI_COMMAND=claude tracefield consult --scenario-dir scenarios/my-review --adapter cli --model <model>
```

`claude-code` も alias として受け付け、実行時には `claude` binary を呼びます。

Codex CLI を使う場合:

```sh
TRACEFIELD_CLI_COMMAND=codex tracefield consult --scenario-dir scenarios/my-review --adapter cli --model <model>
```

Codex は `codex exec` で起動し、`--output-last-message` に書かれた最終応答を Tracefield が読みます。

OpenRouter を使う場合:

```sh
export OPENROUTER_API_KEY=...
tracefield consult --scenario-dir scenarios/my-review --adapter openrouter --model openai/gpt-5.5
```

## 出力形式

デフォルトでは人間向けの report が標準出力に表示されます。

compact JSON が必要な場合:

```sh
tracefield consult --scenario-dir scenarios/my-review --adapter mock --json
```

pretty JSON report をファイルに保存する場合:

```sh
tracefield consult --scenario-dir scenarios/my-review --adapter mock --out runs/my-review.json
```

## provenance を保存する

後で retraction を確認したい場合は JSONL store に保存します。

```sh
tracefield consult \
  --scenario-dir scenarios/my-review \
  --adapter mock \
  --persist runs/my-review.jsonl
```

store には task、private document、skill procedure、agent output が entry として保存されます。entry id は `e1`, `e2`, ... の形式です。

## retract する

ある entry が誤り、汚染、撤回済みだった場合、その downstream citation closure を retracted にできます。

```sh
tracefield retract --store runs/my-review.jsonl --entry e3
```

`retract` は対象 entry を直接引用している entry と、その先の downstream entry をたどって retracted にします。skill procedure を retract した場合、その skill を citation している agent output も closure に含まれます。

## よくある運用順序

1. `tracefield doctor` で環境を確認する。
2. `tracefield new <name>` でシナリオを作る。
3. `task.md`、`agents.json`、`private/*.md` を編集する。
4. 必要なら `skills/<id>/SKILL.md` を追加し、agent の `skills` から参照する。
5. `--adapter mock` でシナリオと出力を確認する。
6. Ollama、CLI、OpenRouter などの live adapter で実行する。
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

consult output が弱い、または generic な場合は、live model の前に mock で scenario を見直します。

- `task.md`: 判断対象や調査対象を具体化する
- `agents.json`: `domain` と `desc` の差を明確にする
- `private/*.md`: 事実、制約、観測、既知の tradeoff を足す
- `skills/<id>/SKILL.md`: agent に適用したい手順を短く明確に書く

## 現在の制約

- Historical Mix/Elixir task surface は現行実装では使えません。
- `phase1`、`hetero`、`ideate`、`genesis`、`bridge`、`field` などの古い experiment runner は Rust CLI に未移植です。
- skill は現時点では scenario-local な procedure prompt です。外部 tool execution や MCP skill 実行基盤ではありません。
- CLI adapter は外部 CLI の挙動に依存します。Tracefield が外部 CLI 内部の hidden tool usage を完全には監査できません。

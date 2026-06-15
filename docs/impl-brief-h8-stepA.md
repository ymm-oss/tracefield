# 実装ブリーフ — H8 Step A: 並列 tool版 RunTurn（Jido Action のツール化）

> 前提: Step 0（`docs/impl-brief-h8-toolprobe.md`）で gemma4:31b-it-qat が valid tool_call を決定的に吐けることを確認済（serve/absorb・入れ子 citations 含む）。
> 目的: tracefield の内部操作を Jido Action→ツール化し、agent が **散文生成ではなくツールコールで store を操作する「tool版 RunTurn」を並列モードとして追加**する。既存の散文パース版（現 `RunTurn`）は一切変えず、後で A/B（Step B）できる形にする。
> **絶対条件: 既存挙動・既存テストを壊さない。tool版は opt-in の並列経路。**

## スコープ

1. tracefield 内部操作を **Jido Action** として定義し、`Jido.Action.Tool.to_tool/1`（`jido_action` 同梱）でツール定義に変換。
2. **tool版の熟議ループ**を `Tracefield.Agent`（`RunTurn`）に opt-in で追加。
3. **Mock アダプタのツールコール対応**（決定的テスト用）。
4. テスト（tool版 RunTurn が Mock で決定的に動く／既存 267 green 維持）。

**やらないこと**: Step B の A/B 計測（citation precision / retrieval coverage の指標化）はまだ。OpenRouter 改造はしない（Ollama＋Mock のみ）。既存 `RunTurn` の散文パス改変禁止。

## 1. Jido Action のツール化

ユーザー選択は「内部 Action のツール化」。手書きスキーマ（Step 0 の toolprobe）でなく、**実 Jido Action から `to_tool` で生成**する設計にする：

- `Tracefield.Agent.Tools.Serve`（`use Jido.Action`）: params `query`（string）。`run/2` は context 内の reference pid を使い `Reference.serve` を呼び、served entries の `{id, author, text}` を返す。
- `Tracefield.Agent.Tools.Absorb`（`use Jido.Action`）: params `content`（string）, `type`（**enum**: 実 entry type の許可集合。Step 0 で gemma が required scalar `type` を落とした癖への対策＝enum 明示＋未指定時 default を持たせる）, `citations`（array of `{id, stance}`、stance enum=`relies_on`/`refutes`/`context`）。`run/2` は entry を組み立てて返す（実 absorb はループ側がまとめて行う）。
- これらを `Jido.Action.Tool.to_tool/1` で `{name, description, parameters_schema}` に変換し、Ollama/Mock の `:tools` に渡す。`json_schema_bridge` が NimbleOptions schema→JSON Schema を担う。
- **citation の供給経路**: tool版では citations は **absorb のツール引数（構造化）から**取り、散文パースを経ない。ただし得られた entry は **既存の `sanitize_entry`／H4 接地ゲート（`meta.citation_stances`、grounding gate）と同じ後処理に通す**こと（A/B を governance で apples-to-apples にするため。citation の「出所」だけが散文パース vs 構造化の違い）。

## 2. tool版 RunTurn（opt-in 並列モード）

`Tracefield.Agent.Core` の schema に **`deliberation: [type: :atom, default: :prose]`** を追加（`:prose`=現状, `:tools`=新経路）。`default: :prose` で**既存挙動は完全不変**。

`RunTurn.run` を分岐：
- `:prose`（既定）→ 現状の `deliberate → take → sanitize → absorb` を**そのまま呼ぶ**（リファクタ最小、既存コードパスを温存）。
- `:tools` → 新規 `deliberate_with_tools/…`:
  1. serve/absorb ツールを渡して adapter を呼ぶ（`:tools` opt 経由）。
  2. **ツールコールループ**（最大ラウンド数 `tool_max_rounds`、schema に追加・default 例 4）:
     - `serve` コール → `Reference.serve` 実行 → 結果を `role: "tool"` メッセージとして会話に戻し継続（=多段 retrieval が可能）。
     - `absorb` コール → entry を蓄積。`entry_limit` 件に達する or ラウンド上限 or モデルがツールを呼ばなくなったら終了。
  3. 蓄積した entry を `:prose` 経路と**同じ sanitize/grounding** に通して `Reference.absorb`。
  4. 返り値（`last_round`/`absorbed_count`/`last_absorbed`/`perception`）は `:prose` と同型。`perception` に tool版固有の `served_queries`（多段検索の各クエリ）と `tool_rounds` を**追加記録**（Step B の retrieval coverage 計測用フック）。
- **決定性**: seed:0、temp 低、`tool_max_rounds` で打ち切り。

## 3. Mock アダプタのツールコール対応

`lib/tracefield/llm/mock.ex` に `:tools` opt 対応を追加：
- `:tools` 無し時は現状の挙動を完全保持。
- `:tools` 指定時は **スクリプト化した決定的 tool_calls** を返せるようにする（テストが「serve→結果→absorb」の往復を決定的に検証できる形）。返り値型は Ollama と同じ `{:ok, %{content, tool_calls}}`。
- スクリプトの渡し方は opts（例 `:tool_script`）で注入できる最小設計でよい。

## 4. テスト

- `test/agent_tooluse_test.exs`（新規）: Mock＋スクリプト化 tool_calls で tool版 RunTurn が
  - serve→absorb 往復を実行し、
  - 構造化 citations が `meta.citation_stances` に正しく載り、
  - grounding gate が `:prose` 経路と同じく効く（過剰引用を弾く）、
  - 多段 serve（serve 2回）が `perception.served_queries` に記録される、
  を決定的に検証。
- `deliberation: :prose`（既定）の既存テストが**全て不変で通る**こと（既存 267 green 維持）。

## 完了条件（Claude に返す）

- `mix test` green（267 以上、既存を割らない）。
- tool版 RunTurn が Mock で決定的に動く新規テストの pass。
- 可能なら（ローカル Ollama 前提・任意）`deliberation: :tools` を gemma4:31b-it-qat で1 run 実走した観察メモ（落ちないか／多段 serve するか）。**サンドボックスで TCP 不可なら省略可・その旨報告**。

## 制約（厳守）

- `deliberation: :prose` を既定にし、既存挙動・既存テストを一切変えない。
- 既存 `RunTurn` の散文パス（`deliberate`/`sanitize_entry`/`absorb` 呼び出し）を改変しない（分岐で温存）。
- 既存テストを編集しない。
- `mix format` は新規/変更ファイルのみ。リポジトリ全体に走らせない。
- 言語ツールチェーンは mise 経由（brew 不可）。

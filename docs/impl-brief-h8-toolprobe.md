# 実装ブリーフ — H8 Step 0: gemma ツールコール de-risk PoC

> 目的: tracefield の agent を Jido tool-use 化する前に、**ローカル gemma が Ollama 経由で valid な tool_call を安定して吐けるか**だけを確認する最小 PoC。ここが通らなければ H8（tool-use レバー）は gemma 基盤では成立せず、OpenRouter 限定の話に縮小する。
> 上位設計は会話ログ参照（散文パース版 vs ツール版の A/B = H8）。本ブリーフは **Step 0 のみ**。Step A/B はまだ実装しない。

## スコープ（これだけ。広げない）

1. `lib/tracefield/llm/ollama.ex` に **ツールコール対応を後方互換で追加**。
2. PoC ランナー `mix tracefield.toolprobe` を新規追加し、`gemma4:31b-it-qat` に2ツールを渡して tool_call が返るか検証・出力。
3. テスト（PoC の解析ロジックの単体テスト）。

**やらないこと**: Agent/RunTurn の改造、Jido Action のツール化、OpenRouter 改造、既存テストの変更、`mix format` のリポジトリ全体実行（新規/変更ファイルのみ）。

## 1. Ollama アダプタ拡張（後方互換が絶対条件）

`lib/tracefield/llm/ollama.ex` の `complete/2`:

- **`:tools` opt が無い時は現状と完全に同一挙動**（`{:ok, content_binary}` を返す）。既存呼び出し・既存テストを一切壊さない。
- `:tools`（list of tool定義 map、後述スキーマ）が渡された時のみ:
  - リクエスト body に `tools:` を含める（Ollama `/api/chat` の tools フィールド）。
  - レスポンスの `message.tool_calls` を解析する。
  - 返り値は **`{:ok, %{content: binary, tool_calls: [%{name: binary, arguments: map}]}}`**（tool_calls が空なら `[]`）。これにより呼び出し側が「tools モードか否か」を返り値の型で判別できる。
  - tool_calls が無く content だけの場合も上記 map 形式で返す（`tool_calls: []`）。

ツール定義 map のスキーマ（Ollama/OpenAI 互換。`Jido.Action.Tool.to_tool/1` の `parameters_schema` をそのまま流用できる形にする）:

```elixir
%{
  type: "function",
  function: %{
    name: "serve",
    description: "...",
    parameters: %{           # JSON Schema
      type: "object",
      properties: %{...},
      required: [...]
    }
  }
}
```

## 2. PoC ランナー `lib/mix/tasks/tracefield.toolprobe.ex`

`mix tracefield.toolprobe`（引数なしで動く）:

- モデルは **`gemma4:31b-it-qat`** をデフォルト。`--model <slug>` で上書き可。
- 次の2ツールを定義して `Ollama.complete` に `tools:` で渡す:
  - `serve(query: string)` — "Retrieve entries from the shared knowledge store matching a query."
  - `absorb(content: string, type: string, citations: array<{id: string, stance: string}>)` — "Write a new entry into the store, citing source entries with a stance (relies_on / refutes / context)."
- system + user プロンプトは「あなたは共有ストアで協働する agent。まず関連情報を検索し、次に根拠を引用して所見を1件書け」程度の**ツール使用を促す最小指示**（日本語/英語どちらでも可、gemma が乗りやすい方）。
- 出力（人間可読 + 末尾に機械可読 JSON 1行）:
  - 各ツールコールの `name` と `arguments`、`arguments` が宣言スキーマに**型的に適合するか**（特に `absorb.citations` が配列で各要素が `{id, stance}` か）。
  - サマリ: `tool_call_count`, `valid_tool_calls`（スキーマ適合数）, `malformed`（不正な引数の列挙）。
- **決定性配慮**: `seed: 0, temperature: 0`（または 0.0 近傍）で複数回（例 3 回）叩き、tool_call の安定性（毎回 valid か、引数のブレ）を出力する。`mix tracefield.toolprobe --runs 3`。

## 3. テスト `test/toolprobe_test.exs`

- Ollama を叩く実通信は CI で不安定なので、**解析ロジック（tool_calls map → valid/malformed 判定）を純関数に切り出して単体テスト**する。実 Ollama 通信を伴う end-to-end は `@tag :live` を付け、デフォルト除外（`mix test` は通る、`mix test --include live` で実走）。
- アダプタの後方互換テスト: `:tools` 無しで `{:ok, binary}` が返る経路が壊れていないこと（Mock or 既存テストで担保されていれば追加不要、要確認）。

## 完了条件（判定材料を私=Claude に返す）

- `mix test` が green（既存 263 を割らない）。
- `mix tracefield.toolprobe --runs 3` を実走した**生出力**（gemma4:31b-it-qat が tool_call を吐いたか、valid 率、3回の安定性、malformed の具体例）。
- これを見て H8 Step A に進むか判断する。**de-risk が目的なので、gemma が吐けない/不安定でも「失敗」ではなく事実として正直に報告**。

## 制約（厳守）

- 既存ファイルの挙動を変えない（`ollama.ex` は `:tools` 無し経路を完全保持）。
- `mix format` は新規/変更したファイルだけ。リポジトリ全体に走らせない。
- 既存テストを編集しない。
- 言語ツールチェーンは mise 経由（brew 不可）。

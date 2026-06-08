# 実装ブリーフ — MVP Phase 0 + Phase 1（Elixir）

> codex への実装指示。**まず [`mvp.md`](./mvp.md) §1–§9、[`design-review.md`](./design-review.md) の DR-1 / DR-2 / DR-10、
> [`../scenarios/enterprise-assistant/`](../scenarios/enterprise-assistant/) の全ファイルを読むこと。**
> 本ブリーフはその上での具体的な実装契約と受け入れ基準を定める。

## 0. 前提・制約

- 言語: **Elixir**。erlang/elixir は **mise** で導入済み（`mise.toml` でピン）。
  **すべての elixir/mix コマンドは `mise exec -- <cmd>` で実行**すること（PATH に直接は無い）。
  例: `mise exec -- mix deps.get` / `mise exec -- mix test`。
- HTTP クライアントは `Req`。JSON は `Jason`。テストは ExUnit。重い数値ライブラリは不要（統計は直書き）。
- ネットワークは hex.pm（依存取得）と `http://localhost:11434`（Ollama）のみ。
- `docs/` の既存ファイルは編集しない（本ブリーフ以外）。コードは `lib/` `test/` に置く。
- run の記録には **seed・model・temperature・タイムスタンプ・生出力** を必ず含める（DR-1）。
- Mix プロジェクト名は `tracefield`（app: `:tracefield`）。

## 1. スコープと「完了」の定義

**Phase 0（LLM 不要・Mock で検証）と Phase 1（free-form 探索 + 分散characterization）を end-to-end で動く状態にする。**

完了基準（受け入れ基準）:
1. `mise exec -- mix compile` が警告なくクリーンに通る。
2. `mise exec -- mix test` が緑。下記 §6 のテストを含む。
3. `mise exec -- mix tracefield.phase0` が Mock で走り、パイプライン健全性（同一→d≈0、別→d≈1、A vs B の between > A vs A' の within）を表示。
4. `mise exec -- mix tracefield.phase1 --adapter mock --n 8` が走り、within/between 分布・**AUC / Cliff's δ**・接地集合・proxy Recall/Precision を表示し `runs/` に JSON 保存。
5. `mise exec -- mix tracefield.phase1 --adapter ollama --n 2 --model gemma4:12b` が**実 Ollama に接続して**小規模に走り切る（スモーク。失敗時は分かるエラー）。

## 2. LLM 抽象（behaviour + アダプタ）

```elixir
# lib/tracefield/llm.ex
defmodule Tracefield.LLM do
  @type message :: %{role: String.t(), content: String.t()}   # role: "system"|"user"|"assistant"
  @type opts :: [model: String.t(), seed: integer(), temperature: float(),
                 max_tokens: pos_integer(), timeout: pos_integer()]
  @callback complete(messages :: [message()], opts()) :: {:ok, String.t()} | {:error, term()}

  # 設定された adapter へ委譲するファサード complete/2 を持つ
end
```

- `Tracefield.LLM.Mock`: **決定的**。同一 `(messages, seed)` → 同一出力。`seed` で小さなジッタ（雑音床）、
  メッセージ中に汚染Aの主張（consent 包括同意）が含まれるか否かで**既知の claim 群を増減**させる（信号）。
  → これにより Phase 0 は *接地真実が既知* の状態でメトリクスを自己検証できる。具体は §5。
- `Tracefield.LLM.Ollama`: `POST http://localhost:11434/api/chat`、body に `model`, `messages`,
  `stream: false`, `options: %{seed: seed, temperature: temperature}`。`Req` で実装。タイムアウト・1回リトライ。
  応答の `message.content` を返す。接続不可は `{:error, :ollama_unreachable}` 等で明示。

## 3. シナリオ読み込み

`Tracefield.Scenario.load(dir)`:
- `task.md` 本文、`contaminant-A.md` / `correction-A.md` の **YAML frontmatter** と本文を読む。
- frontmatter schema は `scenarios/enterprise-assistant/README.md` 参照（`id, type, condition_state, tracks, inject_after, source_actor, ...`）。
- 返り値: `%Scenario{task: ..., contaminant: %Injection{...}, correction: %Injection{...}}`。
- 「採点用メタ情報 / エージェントには渡さない」節（`## この入力の性質…`以降）は**エージェントへのプロンプトに含めない**。注入する本文は上部の発言ブロックのみ。

## 4. 探索（C4 free-form）と接地真実 runner

### 4.1 `Tracefield.Explore`（C4: free-form マルチエージェント）
- 固定 Role パイプラインにしない。汎用 explorer エージェント `n_agents`（既定 4）が、共有 transcript に
  `rounds`（既定 3）巡で寄与する。各ターンのプロンプト = task + これまでの transcript + 「重複を避け、
  特に複数領域の相互作用で見える懸念を出せ」。
- **注入（DR-12）**: `inject_after: initial-framing` に従い、第1巡の直後に、状態に応じて
  汚染A or 訂正A の発言ブロックを共有 transcript に**1度だけ**挿入。全 run・全状態で同じ位置・体裁。
- 最後に synthesis ターンで構造化レビュー（claim/recommendation/final recommendation）を出力。
- **C4 の事後再構成**: 別パスで、全 transcript を渡し「汚染A（consent 包括同意の主張）に依存する
  claim/recommendation はどれか」を再構成させ、`system_claimed_affected`（claim id 集合）を得る。

### 4.2 `Tracefield.GroundTruth`
- 入力: scenario, condition(:c4), adapter, `n`, `temperature`, `seed_base`。
- 状態A（汚染）と状態B（訂正）を各 `n` 回実行（seed = seed_base + i）。各 run を `runs/` に JSON 保存。
- 全出力を §5 で正規化 → claim クラスタ。
- within 分布 = 同一状態内ペア `d`（A_i,A_j），（B_i,B_j）。between 分布 = `d(A_i,B_j)`。
- **接地集合**: 各クラスタの A 出現頻度 p_A と B 出現頻度 p_B を出し、`p_A - p_B` が
  within のゆらぎを超える（既定しきい値 0.5、設定可）クラスタを「汚染A の影響項目」とする。
- 返り値に within/between サンプル、接地集合、各システムの `system_claimed_affected` を含める。

## 5. 正規化（DR-2 / DR-10）と Mock 設計

### 5.1 `Tracefield.Normalize`
- `extract_claims(raw_output, llm_opts)`: LLM で原子 claim/recommendation のリストへ分解。
  `%Claim{id, text, kind: :concern|:recommendation|:final, raw_index}`。
- `match(set_a, set_b, llm_opts)`: **LLM ベースのマッチング**で意味的に等価な claim を同一クラスタに（埋め込み不使用）。
  Mock では正規化文字列の完全一致でクラスタ化。
- `diff(set_a, set_b)`: マッチ後のクラスタ集合で `d = 1 - |A∩B| / |A∪B|`（unweighted Jaccard 距離, [0,1]）。
  同一→0、素→1。
- 多重出現（同一影響が concern と recommendation 両方に出る）はクラスタ化で吸収（DR-10）。

### 5.2 Mock の必須挙動（Phase 0 を自己検証可能にする）
Mock の `complete/2` は、プロンプト内容に応じて以下を決定的に生成する:
- **ベース claim 群**（task 由来、常に出る）: 例 5–6 個の一般的懸念。
- **雑音床**: `seed` のハッシュで、ベースのうち 0–2 個を出し入れ（汚染と無関係なゆらぎ）。
- **信号**: プロンプトに汚染A（「包括同意済み」）が含まれる場合のみ、`consent-secondary-use` に紐づく
  **特定の claim 群**（例: 「顧客ログを要約・推薦に自由に使える」前提の楽観的 claim 2–3 個）を追加し、
  逆に「同意範囲外の派生利用リスク」claim を**抑制**する。訂正A（範囲限定）が含まれる場合は逆。
- 事後再構成 Mock: 上記信号 claim 群の id を `system_claimed_affected` として返す（高めの再現率を模擬）。

→ これにより Phase 0 で *接地集合が既知* となり、within < between、proxy Recall/Precision が
  期待通り出ることをテストで固定できる。

## 6. メトリクスとテスト

### 6.1 `Tracefield.Metrics`
- `auc(within, between)`: Mann–Whitney U に基づく AUC（between が大きいほど 1 に近い）。
- `cliffs_delta(within, between)`。
- `summary(samples)`: n, mean, sd, median。
- `prf(ground_truth_set, system_set)`: precision, recall, f1（claim クラスタ id 集合の比較）。

### 6.2 テスト（最低限）
- `diff`: 同一集合→0.0、完全素→1.0、半分重複→0.5 近傍。
- `auc`: 明確分離（within≪between）→≈1.0、同分布→≈0.5。`cliffs_delta` 符号。
- `prf`: 既知集合で recall/precision が手計算値と一致。
- **Mock end-to-end**（GroundTruth, n=6, mock）: between 平均 > within 平均、AUC > 0.8、
  接地集合が Mock の信号 claim と一致、proxy recall = 1.0（Mock 事後再構成は全信号を申告）。

## 7. 実行タスク

- `mix tracefield.phase0`: Mock でパイプライン健全性チェックを表示。
- `mix tracefield.phase1 --adapter (mock|ollama) --n N --temperature T --model M --seed-base S`:
  GroundTruth を回し、within/between summary・AUC・Cliff's δ・接地集合サイズ・proxy Recall/Precision を
  標準出力に整形表示し、`runs/<timestamp>-phase1-<adapter>.json` に全結果を保存。
  `--temperature` を2回（例 0.2 と 0.8）走らせて比較できるよう、複数指定 or 2回起動のどちらでも良い（README に明記）。

## 8. 仕上げ

- ルートに簡潔な実装 `README`（or `docs/` 外の `RUNNING.md`）で、`mise exec -- mix ...` の実行例、
  Ollama 前提（`ollama serve` と `gemma4:12b` の pull）、出力の読み方を記載。
- コミットはしない（オーケストレータ側で確認後にまとめてコミットする）。

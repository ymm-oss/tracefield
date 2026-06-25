# 実装ブリーフ H1b — 異系列モデルでの H1 再試（OpenRouter を器官に）

> H1（[`findings-substrate-hetero.md`](./findings-substrate-hetero.md)）は gemma 同系列(12b/26b)で「基盤異質性は攻めの便益を増やさない」を示したが、
> **2つの限界**を残した: ①同系列（サイズ違い＝「異なる頭」ではない）②hetero arm のみ ollama の model-swap で非決定的（測定交絡）。
> H1b は **OpenRouter の異系列モデル**を器官に使い、両限界を除いて H1 の本来の clean test を行う。
> 由来: OpenRouter Fusion 調査（2026-06-15）。Fusion は本実験の参照点（後述 §0）。

## 0. 最重要の設計判断 — Fusion エンドポイントでなく「個別モデル」を器官にする

- H1 が問うのは **tracefield 自身の多エージェント半溶解機構**（serve / aware / k_s / k_p / 来歴）が **異質な基盤で便益を生むか**。
- `openrouter/fusion`（panel→judge→synthesize）を器官にすると、**tracefield の機構が Fusion の機構に置き換わり、測りたいものが消える**。Fusion が単体を上回ることは OpenRouter の DRACO ベンチで既知だが、それは ≠ tracefield の検証。
- → **各エージェントの器官 = 別々の OpenRouter 個別モデル**（例 SEC=GPT, BIZ=Gemini, UX=DeepSeek）。
- **Fusion の位置づけ**: tracefield の「攻め（多視点熟議）」を **stateless で製品化した参照点**。tracefield 固有の価値は **守り（来歴・撤回・統治）** ＝ Fusion がやらない別軸（混同しない）。
- **将来の別アイデア（H1b 対象外）**: エージェントの器官を Fusion 呼び出しにする「入れ子熟議」（tracefield のクロスエージェント熟議 × Fusion のイントラエージェントパネル）。別実験として温存。

## 1. 必要なもの = LLM アダプタ1個（per-agent model 機構は H1 で実装済み）

- **新規 `Tracefield.LLM.OpenRouter`**: Req・OpenAI 互換 `POST https://openrouter.ai/api/v1/chat/completions`・`OPENROUTER_API_KEY`（env）。`ollama.ex` と同型（`complete/2`、{:ok, content}/{:error, _}）。
- **`tracefield.hetero.ex` の `adapter_module/1` に `"openrouter"` を追加**（1行）。
- **per-agent モデル割当は既存の `--substrate`/`--models` をそのまま使う**（H1 で実装。`--models SEC=openai/gpt-5.5,BIZ=google/gemini-3-pro,UX=deepseek/deepseek-v4`）。
- **測定層は固定（arm 横断で一定）**:
  - 一次指標 `disc_strict` は **judge 非依存・決定的**（`Discovery.strict_score`、埋め込みも不要）＝ H1b の主結果はここ。
  - `diversity`/`collapse` は **ローカル nomic 埋め込み**（既存配線 `Embed.Ollama`・無料・固定）。
  - `icc`/`coverage` は judge 依存・飽和ぎみの副次 → コスト節約のため判定を最小化 or ローカルに固定（任意）。

## 2. 実験デザイン（交絡を分離する arm）

異系列でも「異質性 vs 単に強いモデル」を分離するため、**比較可能 tier の別系列3モデル**で（H1 と同じ3-arm 論理）:

| arm | SEC | BIZ | UX | 役割 |
| --- | --- | --- | --- | --- |
| `homo-A` | A | A | A | 同質ベースライン（系列A） |
| `homo-B` | B | B | B | 同質（系列B） |
| `homo-C` | C | C | C | 同質（系列C） |
| `hetero` | A | B | C | **異系列混成（本命）** |

- **支持**: `hetero > max(homo-A, homo-B, homo-C)` → 真の異系列異質性効果（超加法）。
- **棄却**: `homo 群の内挿に収まる / 最下位` → 異質性は効かず（強モデルが運ぶだけ）= H1 の同系列結論が異系列でも成立。
- **Fusion の self-fusion(+6.7) の含意**: 同質 arm も tracefield 構造（panel 相当の多エージェント＋serve＋aware）で伸びるはず → **hetero vs homo は「構造の利得の上に乗る異質性の純増分」**を測る（Fusion は同じ二層を製品で観測済み）。
- 固定条件は §14 最良セル: `serve:diverse, aware:1, kp:1, ks:2, hetero(情報):grounded`、seeds≥3（パイロット）→ 6+。

## 3. H1 の交絡をどう除くか

| H1 の限界 | H1b での解消 |
| --- | --- |
| 同系列（gemma サイズ違い） | **GPT/Gemini/DeepSeek 等は別アーキ・別学習** ＝ 本物の基盤異質性 |
| hetero arm のみ非決定的（ollama swap） | **OpenRouter は全モデル同時 API・ローカル swap なし** ＝ 主交絡を除去 |
| （新たな代償） | クラウドは seed でも非決定的（temp>0）→ homo の byte 再現性は失う → **seeds を増やして平均で判断** |

## 4. コストと運用 — 要ユーザー判断（外部・有料）

- **`OPENROUTER_API_KEY` 必須。実行＝実費**（OpenRouter は補完ごと従量）。
- 概算: 1 run ≈ 3 agent × 2 round = 6 補完（+任意で judge 2）。`4 arm × seeds=3 ≈ 12 run ≈ 70–100 補完 × ~1.5k tok`。
  - **安価別系列パイロット**（例 `google/gemini-flash` / `deepseek/deepseek` / `moonshotai/kimi`）で seeds=3 → **数ドル規模**で符号確認。
  - 符号が出たら強 tier（GPT-5.5/Gemini-3-Pro/Opus 等）・seeds 増（十数〜数十ドル規模）。
- 予算ガード: `max_tokens`(1200) と `temperature` 固定、まず最小 `arm × seeds`、`--substrate`/`--models` で段階拡大。

## 5. 検証手順

1. アダプタ `mix compile`（実装済）＋ **mock スモーク**（配線確認・無料）。
2. **key あり 1 完了スモーク**（疎通・JSON entry/stance 準拠の確認）。強モデルは gemma12b より JSON 準拠が良い見込み（データ品質+）。
3. **安価パイロット seeds=3**（4 arm）→ `disc_strict` の arm 比較を `findings-substrate-hetero.md` に追記（H1b 節）。
4. 符号が出れば seeds 増／強 tier。陰性なら「異系列でも基盤異質性は効かない＝攻めの便益は構造×自覚で確定」を強く結論（H1 を一般化）。

## 6. リスク・限界

- **実費・外部依存**（key 必要・レート/障害）。機微情報をクラウド器官に出す点はローカル完結の利点を失う（機微情報を扱う文脈では注意 ── 本実験は合成シナリオなので可）。
- **非決定性**でホモ arm の厳密再現は失う（H1 で swap 交絡検出に使えた手段）。代わりに swap 交絡そのものが無い。
- 各系列で JSON 整形の癖が出うる（既存 `decode_json_object` は寛容）。
- 単一シナリオ・3件天井は H1 と共通（H2 高天井シナリオが望ましい）。
- これは攻めの検証。**守り（来歴・撤回）の優位は別途**（Fusion にはない tracefield 固有価値）。

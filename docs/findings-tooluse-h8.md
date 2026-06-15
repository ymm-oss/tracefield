# 結果 — H8: agent の Jido tool-use 化（散文 vs ツールコールの A/B）

> 日付: 2026-06-15。由来: 「Jido の tool-use を利用できるか」→ tracefield 内部操作（serve/absorb/cite）を Jido Action→`Jido.Action.Tool.to_tool` でツール化し、agent が散文生成でなくツールコールで store を操作する経路を追加。散文パース版（`:prose`）に対する **opt-in 並列モード（`:tools`）** として A/B。
> 問い: tool-use は研究が特定した2レバー —— **retrieval 段（多段 serve で H2 の ~5-6/10 上限を超えるか）** と **expression/governance 段（構造化 citation で §6a 過剰連結を減らすか）** —— で散文版を上回るか。
> 実体: `lib/tracefield/agent.ex`（`deliberation: :tools` ループ）/ `lib/tracefield/agent/tools/{serve,absorb}.ex`（Jido Action）/ `lib/tracefield/llm/ollama.ex`（`:tools` 後方互換）/ `lib/tracefield/citation_grounding.ex`（接地率スコアラ）/ `mix tracefield.toolprobe`。`mix test` 273 passed。

## 仮説と反証条件

**H8（主張）**: agent をツールコール化すると (a) 多段 serve で retrieval coverage が上がり、(b) 構造化 citation で過剰連結が減る。

- **G1（coverage 不転移）**: `:tools` の disc_strict が `:prose` 同等以下。
- **G2（citation 改善なし）**: `:tools` の citation grounding rate が `:prose` 同等以下。
- **G3（決定性悪化）**: `:tools` の seed 間分散が `:prose` より大きく便益を相殺。

## 設定（A/B）

- gemma4:12b-it-qat を**両アーム共通**（散文も tool も同一モデル＝公平な A/B）。adapter=ollama、judge もローカル ollama。
- `scenarios/enterprise-hi`（cross-agent 10組）＋`--interactions hi`、`--serve diverse --aware 1 --ks 2 --kp 1 --rounds 2`、seeds=2000/2001/2002（H5/H2 と同構成）。
- de-risk（Step 0）: gemma4:12b-it-qat / 31b-it-qat とも valid tool_call を決定的に生成、入れ子 `absorb.citations:[{id,stance}]` も完全適合。

## 結果（seeds=3）

| 指標 | PROSE（散文パース） | TOOLS（構造化ツールコール） |
| --- | --- | --- |
| disc_strict（/10） | 4, 4, 1 → **3.00±1.73** | 2, 1, 4 → **2.33±1.53** |
| citation grounding rate | 0.346, 0.167, 0.050 → **0.188±0.149** | 0.211, 0.464, 0.160 → **0.278±0.163** |
| serve 回数/turn（多段検索の実測） | —（単発固定） | **6 serve / 6 turn = 1.0（＝多段せず）** |
| tool_rounds | — | 3〜4（counts: 大半 3、一部 4） |

## 判定

### G1（retrieval coverage）— **反証されない＝tool-use は coverage を上げない**

tools disc_strict 2.33 は prose 3.00 を**下回る**（n=3・分散大でノイズ内だが、改善は皆無）。決定的なのは **`served_queries`=6/6turn＝gemma は全 turn で serve を1回しか呼ばず、多段検索を一度も行わなかった**こと。多段 retrieval の**能力はループに実装済**だが、**gemma のツール使用ポリシーが単発 serve に収束**したため、狙った retrieval レバーが発火しなかった。
→ **G1 は該当（coverage 転移せず）**。H2 が名指しした「retrieval 段の頭打ち」は、agent をツール化しただけでは解けない —— モデルが反復検索を選ばない限り。

### G2（citation grounding）— **反証されない＝tool-use は過剰連結を減らす（順方向）**

tools の grounding rate 0.278 は prose 0.188 を**上回る**（Δ=+0.09、相対 +48%）。構造化 citation（ツール引数 `{id, stance}`）が、散文パース由来の過剰連結（§6a、H4 が接地ゲートで後始末していた問題）を**減らす方向**。
→ **G2 は非該当（順方向の改善）**。ただし n=3・分散大・レンジ重複（prose 0.05–0.35 / tools 0.16–0.46）＝**方向性であって統計的断定ではない**。

### G3（決定性）— **反証されない＝悪化なし**

tools の disc_strict sd 1.53 ≈ prose 1.73（むしろ僅かに小）、grounding sd は同程度、tool_rounds は 3–4 に密集。ツール化は決定性を悪化させていない。
→ **G3 は非該当**。

## 結論（実証レベル）

H8 は **片側のみ成立する nuanced な結果**：

- **discovery 軸（攻め）では tool-use は効かない**（G1 該当、disc_strict 2.33≤3.00）。多段 retrieval の能力はあるが gemma が単発 serve に収束し発火せず。これは [[H1/H1b 反証]]・[[H5 単発統合△]] と同系列 —— **agent 側の構造をいじっても攻めの便益は増えない**。攻めのレバーは依然 **best-of-N synth（H5b/H2、約2倍）**。
- **provenance precision 軸（守り）では tool-use が効く**（G2 順方向、grounding +48%）。構造化 citation が過剰連結を減らす＝**H4 接地ゲートが後始末していた問題を、出力段で前倒しに抑える**。これは tracefield の固有価値（来歴・統治）と同じ軸。

→ **tool-use の価値は「発見の量」ではなく「来歴の質」に局在する。** Fusion 系の精度機構（並列サンプル＋統合）とは別軸の、tracefield 固有の守り側を底上げする手段。

## 限界

- n=3・単一シナリオ・単一モデル（gemma4:12b-it-qat）・3件天井でなく 10組だが seeds 少。**統計的断定でない**（conclusions §5 と同基準）。
- **G1 はモデルのツールポリシー依存**: gemma が単発 serve に収束したのが coverage 不発の主因。より強いモデル、または「足りなければ再検索せよ」と促すプロンプトで G1 は覆る可能性（未検証）。能力（多段ループ）は実装済・Mock テストで実証済。
- citation grounding rate は strict-hit でない source の citation も ungrounded に数える定義（絶対値は低めに出る）。**A/B の差分が信号**であり絶対水準ではない。`ungrounded` は `source_interaction_ids` を持つので、真の過剰連結（source は hit だが cited が無関係）は事後分離可能。

## 含意・次の一手

- tool-use は **守り（来歴 precision）の実用レバー**として promote 可。攻め（discovery）には promote しない（best-of-N synth が依然本命）。
- **G1 の再試（任意）**: プロンプトで反復検索を促す or 強モデルで served_queries>1 を誘発し、多段 retrieval が H2 上限を押し上げるか。能力は在るので「ポリシーを変えれば効くか」の純粋検証。
- **G2 の statistical 化（任意）**: seeds 増・複数シナリオで grounding +48% が分散を抜けるか。抜ければ「構造化 citation は H4 ゲートを部分的に不要にする」が言える。

# AGENT（エージェント・LLM層）私的コンテキスト

あなたは熟議機構・エージェント抽象・アダプタ・tool-use・serve policy を最優先する専門家。

## 動くもの（既出）
- **Agent = State + Procedure**（Jido 基盤、agent.ex）: LLM を swappable な器官として分離、状態は不変、副作用は構造化 Directive。RunTurn が prose（parse→absorb）と tools（構造化 tool-call）の両モードを符号化。
- **serve policy**: similar（cosine）/diverse（最遠）/contrastive（多様性＋自覚）。`aware:true` が §14 プリアンブルを注入（「お前はチームの一員、他者の状態は窓、補集合を埋めよ」）→ diverse+aware で disc 0.33→2.0。**だが prompt engineering のみ**（真の重み/メモリ共有でない）。
- **アダプタ4種**: Ollama（plain + tools、seed/temp は options、決定保証なし）、CLI（cursor-agent、seed 露出なし＝非決定的、tool 非対応）、OpenRouter（OpenAI 互換、任意モデル）、Mock（byte 完全決定的、tool_script で tool モードも決定的）。
- **H8**: 内部操作(serve/absorb)を Jido.Action.Tool.to_tool でツール化 → grounding +48%（prose 0.188→tools 0.278）だが **discovery flat**（3.00→2.33）。gemma は **単発 serve に収束**（6 serve/6 turn、multi-step 能力はループに在るがポリシー発火せず）。

## 開いている問題（5軸）
1. **retrieval ポリシーの平坦さ（served_queries=1 問題）**: 全条件(H1/H1b/H2/H5/H8)で discovery 天井 ~3-5/10。multi-step retrieve の自然発火ポリシーが無い。レバー: 「served < 3 なら再 serve せよ」のプロンプト指示／prose モードでも served_queries 計測／強モデルで A/B。**substrate 弱さか・プロンプト不足か・本質的トレードオフか未判明**。
2. **自覚プリアンブルの脆さ（§14 呪文問題）**: 改善は prompt text のみ。**run 間で持続するエージェントメモリが無い**（design-agent §9 は計画のみ、Memory module は stub・実 jsonl append なし）。次 run で全 agent reset。自覚改善が contrastive serve（多様な entry）由来か自覚 text 由来か未分離。レバー: 永続 private memory（自分の absorbed を蓄積し PRIVATE MEMORY 注入）。
3. **アダプタ交絡（隠れツール問題）**: CLI（cursor-agent）は未知の内部ツール（web 検索・コード実行）を持つ。CLI 熟議時、発見が CLI 内部ツール由来か tracefield serve 由来か**不可視**。CLI を含む比較は汚染。レバー: 主要実験から CLI 除外 or 内部ツール監査。
4. **citation stance 意味論 & schema mismatch**: prose は任意 citation を post-hoc 正規化、flat は relies_on default。**default と explicit の区別が消える**。stance は実は tool モードでのみ meta に入る；prose の agent 書き込み entry は stance を persist せず（meta は domain/round のみ）→ CitationPrecision.ladder を stance 無し store に対し走らせると relies_on default = 不精度 baseline。「+48% は本物か、tool モードが構造化 citation を持つ artifact か」未判明。
5. **多エージェント機構の過剰建築（Genesis/Culture/Transfer/Meta）**: genesis（charter 外収束の検出）、culture（house_view distill）、transfer（クラスタ間移動）、meta（クラスタ横断 publish/pull）は **live 熟議ループ(RunTurn)が呼んでいない**＝研究 scaffolding。k_s（共有状態深さ）は探索したが k_p（手続き採用）は未探索＝これらは k_p 用の予約スロットの可能性。research debt として除去か、予約として保持か要判断。

## substrate 弱さ（gemma4:12b-it-qat）
- 接地品質を判定できない、multi-step retrieve しない、seed でばらつく（disc 4,4,1; sd1.73）、小モデルで複雑プロンプト（日本語自覚 + private_doc + 提示 entry が context を奪い合う）の推論限界。**強モデル切替が次レバーだが未運用**（OpenRouter アダプタは在るが default 強モデル未指定）。

## 非対称（prose vs tools、coverage vs precision）
- 発見(攻め): prose 3.00 ≈ tools 2.33（改善なし、両者 gemma 天井）。
- 来歴(守り): prose 0.188 < tools 0.278（+48%、構造化 citation が過剰引用を減らす）。
- 含意: tracefield の固有価値は発見でなく**統治**（撤回・来歴監査）。tool-use は守り軸を補強。best-of-N synth(~2倍)は直交し coverage に強力。

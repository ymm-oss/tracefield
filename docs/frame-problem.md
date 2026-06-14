# 知見 — フレーム問題と tracefield（概念整理）

> 由来: 2026-06-14 セッションの対話（「tracefield はフレーム問題を弱める → AI駆動開発にどう活かすか」を起点に5問）。
> 実装側の帰結は [`findings-contrastive-serve.md`](./findings-contrastive-serve.md)。実証根拠は [`experiment-results.md`](./experiment-results.md) / [`conclusions.md`](./conclusions.md)。
> 本書は**概念整理**であり、§5（クラスタ）等は設計レベル（未実証）の主張を含む。実証済み/設計の別は各節に明記。

## 1. frame は2つ（混同注意）— 最重要

| | 研究期 **Frame Revision** | 開発期 **動的フレームギャップ検出** |
| --- | --- | --- |
| 意味 | 組織的 frame（クラスタ編成/charter）の改訂。EGI 上り | 進行中プロセスで「いま何が関連し誰も見ていないか」 |
| 実体 | Frame Revision Trigger（[`glossary.md`](./glossary.md)） | 無人論点・未回答の老化・動員率（`tracefield.dev` [e35]、`Coverage`/`Patrol`） |
| 実証 | **C7 ablation で trace recall 不変(1.00)＝主アウトカムに効かない副軸**（experiment-results §1-2） | 直近実装の実機構 |

→「tracefield がフレーム問題を弱める」効果の出どころは**後者＋来歴＋領土台帳**であって、研究期 Frame Revision ではない。**この2つを混同しない**。

## 2. なぜ弱まるのか — frame を器官の外に持つ

古典的フレーム問題＝「何が関連し・何が変化し・何が不変かを毎回再導出するコスト」。stateless な LLM はここが構造的に弱い。tracefield の解は **frame を LLM に持たせず永続構造に持つ**（[`design-agent.md`](./design-agent.md): Actor＝状態+手続き、LLM＝器官）:

- **領土台帳** ＝ 関連範囲の明示境界（静的 frame）
- **来歴グラフ＋閉包隔離** ＝ ramification（変化の波及）。「X 撤回で何が壊れるか」を増分維持（C6 で load-bearing）
- **動的ギャップ検出** ＝ frame 自体の自己修正（無人論点・未回答老化・動員率）
- **patrol** ＝ 有界注意下の関連スライス注入

両翼が**同一の一手**で解ける（conclusions §3）: 守り＝ramification の規律（引用強制・照合）、攻め＝relevance の自覚（situational awareness）。

## 3. 半溶解性の寄与は「半＋契約の自覚」、溶解ではない

- **§11**: 生の状態共有(k_s↑)は**均質化ダイヤル**（diversity 0.45→0.08、collapse→0.85）＝エコー。同一モデルは重みレベルで既に溶解、ペルソナは薄膜。
- **§14**: 解錠は `serve:diverse` ＋ **aware（契約の自覚）**。disc 0.33→2.0、同時に collapse↓・coverage↑。
- **統一原理(§3)**: 機構(構造)は必要条件にすぎず、参加者が契約を知って初めて機能する＝**構造×契約の自覚**。

→ フレーム問題への寄与は「**半**(偏り温存＝複数 frame ゆえ隙間が可視)」と「**契約の明示**（関連の外部指定）」。生の**溶解そのものはむしろ問題を作る**（被覆の死角・エコー）。

## 4. 古典的テキスト通信では不足

伝送はテキストで足りる（§10: API 越しは結局言語）。だが store の価値は**伝送でなく番地(addressability)＋射影方策(serve)**:

- **守り**: 閉包/撤回には番地付き永続単位＋依存辺が要る（チャットログでは不可）。
- **攻め**: 古典の2択（全ブロードキャスト＝§11 エコー／自分宛のみ＝近視）は §14 の負けセル。store は「選択的・多様・予算有界な射影」を実装。
- **古典通信で足りる場合**: 短命・撤回/監査不要・少数 agent なら、明示契約をプロンプトに置いた古典通信で十分。store の価値は (i)撤回/監査 (ii)仕事の長さ (iii)agent 数(エコー) (iv)文脈予算 に比例。

## 5. クラスタ規模が効く分野（設計レベル）

- 固有提供: **越境統治**(cross-cluster retraction、最小実装済)・**析出**(genesis＝組織 scale の Frame Revision、設計段階)・スケールフリー再帰。制約も再帰（接続も「半」かつ異質でないと均質化、design-cluster §4）。
- **キラー条件**: 反証不能で外部撤回される前提が、**異質な多チームへ伝播**（§6d の B 型を cluster scale へ）。
- 分野: 規制系システム工学／エビデンス統合(撤回論文の波及)／インテリジェンス・デューデリ／大規模マルチチーム開発／コンサル。genesis 主役は R&D・危機対応（**未検証**）。

## 6. 統合原則 — relevance > diversity

効くのは「**正しい counterpart を見せる＋明示契約**」であり、**diversity を作りにいくと theater**。
この原則を実験で検証 → [`findings-contrastive-serve.md`](./findings-contrastive-serve.md)（差延＝`serve :contrastive` は genuine 発見を surface 多様性とトレード＝net-negative、棚上げ）。

## 限界

- 1〜4・6 は実証（§3/§10/§11/§14・C6/C7、contrastive 実験）に接地。**5 は設計レベル（未実証）**。
- 実証はいずれも機構レベル（seeds 3〜6・単一シナリオ・gemma 系）であり統計的断定ではない（conclusions §5）。

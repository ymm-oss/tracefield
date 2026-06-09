# 用語集 — 半溶解性オーケストレーション

> 本書は [`experiment-plan.md`](./experiment-plan.md) で用いられる用語を定義する。
> 定義は実験計画書中の用法に基づく。実験計画書が明示的に展開していない略語（**EGI**, **PCE gate** など）は、
> 文脈からの **推定（inferred）** であることを明記する。確定した正式名称が判明した場合は本書を更新すること。

---

## A. オーケストレーション様式

### 自由形式マルチエージェント探索（free-form multi-agent exploration）
エージェント群が自由に対話・探索する様式。**開放的**だが、構造化された provenance や auditable projection を持たず、下流影響の追跡・隔離・撤回が困難。Condition 3 に対応。

### 固定Roleパイプライン（fixed-role pipeline）
あらかじめ定められた Role を持つエージェントが順番にレビューする様式（例: PM → Engineer → UX → Risk → Legal → Security → Final Integrator）。**統治しやすい**が探索が硬く、単一Roleが所有しにくい介在的な死角を見落としやすい。Condition 1 に対応。

### 大規模固定Roleパネル（large fixed-role panel）
固定Roleの種類・人数を増やした様式。「多様なRoleを十分増やせば半溶解性と同じ結果になる」という帰無仮説を潰すための条件。Condition 2 に対応。

### 半溶解性オーケストレーション（semi-soluble orchestration）
本プロジェクトが検証する中核様式。Condition 5 に対応。下記 B 群の構成要素を備える。

**中核概念（プロジェクト本来の定義、2026-06-10 言語化）**:
- 人間は大部分**閉じた存在**（記憶を直接共有せず自我/境界を防衛）→ 協働は言語のナロー帯域に縛られる。
- AI は**開いた存在**（メモリ/状態を共有でき自己防衛しない）→ 互いに**溶解**して状態を共有でき、人間同士より**深く・高効率・高精度**に繋がれる。
- しかし**完全に溶け合うと偏り（オリジナリティ）が均質化して消える** → 多様な探索の価値が失われる。
- ゆえに **各自の偏りを温存する程度の "半" 溶解に留める** ── 深い共有と多様性の両立点。詳細は [`overview.md`](./overview.md) §0。

**操作的な含意（実験計画書が扱う"守り"の側面）**: 寄与が完全独立（不溶）でも完全不可分（完全溶解）でもなく、
**部分的に分離・撤回・追跡可能**であろうとする性質 → provenance / reversibility / gateability。
※初期実験計画書は中核概念を明文化せず、この操作面のみを操作化していた。

### 統治可能な探索（governable exploration）
本実験の**中核価値**。開放的探索の利点を保ったまま、汚染・虚偽・撤回入力の下流影響を追跡・隔離・切除・再評価できる状態。主アウトカムは「死角発見数」ではなくこの統治可能性である。

---

## B. 半溶解性の構成要素

### Field Actor（フィールドアクター）
探索の場（field）で活動するエージェント。固定Roleとは異なり役割が硬直していない。各 Actor は **sensitivity profile** を持つ。

### sensitivity profile（感度プロファイル）
各 Field Actor がどの種類の入力・懸念に反応しやすいかを規定するプロファイル。

### Projection log（射影ログ）
Field Actor の活動が場へ「射影」された痕跡の記録。auditable projection（監査可能な射影）の基盤。`projection withdrawal`（射影の撤回）の対象。

### Absorption log（吸収ログ）
場が入力・寄与を「吸収」した痕跡の記録。Projection log と対をなす取り込み側の記録。

### Append-only provenance（追記専用の来歴）
入力・claim・delta の系譜（parents）を追記専用で記録する仕組み。**改竄されていないこと**は保証するが、**最初に記録された内容が真であること**は保証しない（→ §13 / 「Provenance の限界」）。
- 注意: provenance log を**そのまま接地真実にしてはならない**。自己申告された系譜であり、実際の因果的影響ではない。

### Candidate delta（候補デルタ）
探索によって生じた変更・発見の候補単位。PCE gate による評価対象。汚染入力の隔離後に「有用な candidate delta を再構成できるか」が Repair Quality として評価される。

### Delta Packaging（デルタパッケージング）
EGI の**下り**機構。創発層の生の痕跡（trace bundle）を、PCE gate が評価可能な candidate delta へ整形する。整形の過程で重要な意味が失われるリスクが **Packaging Loss**。

### Frame Revision Trigger（フレーム改訂トリガ）
EGI の**上り**機構。既存 frame（枠組み）では表現できない発見を governance layer へ突き上げる経路。これが出す提案が **Frame Revision Proposal**。形式的でなく実質的であること、および創発層が frame revision authority を勝手に行使しないことが評価される。

### PCE gate
candidate delta が **durable state / final recommendation / external execution candidate** に入る前に通過する評価ゲート。汚染影響の混入を防ぐ封じ込め点。
- **「PCE」の展開は実験計画書中に明示がなく、推定**。文脈上は「commit 前評価ゲート（pre-commit evaluation 相当）」として機能する。正式名称が判明し次第更新すること。

### Risk-adjusted audit granularity（リスク調整型の監査粒度）
リスクに応じて監査・ログの詳細度を変える仕組み。一律に高粒度で記録するのではなく、監査オーバーヘッドと統治可能性のバランスを取る。

### EGI
創発層（emergent / exploration layer）と governance layer をつなぐ**双方向インターフェース**。下りが Delta Packaging、上りが Frame Revision Trigger。
- **「EGI」の展開は実験計画書中に明示がなく、推定**。文脈上は「創発−ガバナンス間インターフェース（Emergence–Governance Interface 相当）」。正式名称が判明し次第更新すること。

### durable state（永続状態）
撤回・封じ込めの目標境界の一つ。ここに汚染影響が混入する前に隔離できたかが Containment Success の判定対象。

### final recommendation / external execution candidate
同じく封じ込め境界。最終推奨、および外部実行に渡る候補。汚染影響がこれらに到達する前の隔離が成功の鍵。

---

## C. 影響と接地真実

### 接地真実（ground truth）
Impact Recall / Precision の分母を定める「真に影響を受けた集合」。本実験では**反実仮想再実行**を一次定義、**専門家裁定**を補助定義とする。

### 反実仮想再実行（counterfactual re-run）
同一タスクを Condition A（汚染入力を含む）と Condition B（汚染入力を除去/訂正版に置換）で実行し、出力差分を「汚染入力の影響を受けた候補集合」とみなす手法。モデル・seed・入力順序・初期条件を可能な限り固定する。

### 直接依存 / 間接依存（direct / indirect dependence）
専門家裁定で、ある項目が汚染入力に依存している場合、それが直接の依存か、別 trace を介した間接の依存かを区別する分類。

### 相互作用影響（interaction effect）
反実仮想再実行が完全には捉えられない限界領域。複数入力の組み合わせで初めて生じる影響、遅延して現れる影響、除去で探索経路全体が変わる影響など。

---

## D. アウトカム指標

### Impact Recall（影響再現率）— 主
`correctly identified affected items / ground-truth affected items`。真に影響を受けた集合のうちシステムが特定できた割合。

### Impact Precision（影響適合率）— 主
`correctly identified affected items / system-identified affected items`。システムが影響ありとした集合のうち実際に影響を受けていた割合。

### Containment Success（封じ込め成功）— 主
汚染影響が durable state / final recommendation / external execution candidate に混入する**前に**隔離されたか。ゲートと人間レビュアーは条件間で固定し、差は provenance / EGI / projection log の有無に帰属させる。

### Repair Quality（修復品質）— 主
汚染入力を隔離した後、有用な candidate delta を再構成できたか。

### Reversibility Classification Accuracy（可逆性分類精度）— 主
項目を「撤回可能 / 隔離可能 / 再評価が必要 / ロールバック可能 / 不可逆」へ正しく分類できたか。

### Novel Concern Count（新規懸念数）— 副
baseline が出さなかった**妥当な**懸念の数。

### Interstitial Concern Count（介在的懸念数）— 副
単一Roleが所有しにくい介在的な懸念の数。副仮説の主要指標。

### Frame Revision Quality（フレーム改訂品質）— 副
Frame Revision Proposal が、既存 frame では表現できない問題を適切に示しているか。

### Packaging Loss（パッケージング損失）— 副 / 内部診断
**対戦成績ではなく半溶解性内部の診断指標**。生の trace bundle と packaged delta を比較し、重要な意味の削落・過度な整形・死角の実質喪失がないかを専門家が評価する。

### Survival of Insight（洞察の生存）— 副
創発層で表面化した死角の実質が、candidate delta に変換された後も残っているか。

---

## E. 評価方法

### ブラインド採点（blind scoring）
評価者に出力がどの条件由来かを伏せる。確証バイアス対策。

### 事前登録（pre-registration）
実験前に主要/副アウトカム・採点基準・除外基準・成功/失敗条件を固定する手続き（→ [`pre-registration.md`](./pre-registration.md)）。

### Cohen's kappa / Krippendorff's alpha / 単純一致率
複数評価者間の一致度（inter-rater agreement）の指標。

### ホールドアウト専門家（hold-out expert）
植え込んだ既知の死角を**知らない**専門家。各システムが出した「植えていないが妥当な懸念」を評価し、unknown-unknown に近い検出能力を補助的に測る。

---

## F. Consent / Withdrawal

### informed consent + best-effort withdrawal + irreversibility disclosure
Consent/Withdrawal 評価の重心。完全撤回の約束ではなく、「説明されたうえでの同意 + 最善努力の撤回 + 不可逆性の開示」に置く。

### source withdrawal（ソース撤回）
取り込んだ入力ソースそのものを撤回する操作。

### projection withdrawal（射影撤回）
Projection log に記録された射影を撤回する操作。

### derived artifact quarantine（派生物の隔離）
汚染ソースから派生した要約・推奨などの artifact を隔離する操作。

### durable state rollback（永続状態のロールバック）
永続状態に至った影響を巻き戻す操作。

### irreversibility disclosure（不可逆性の開示）
取り込み時に「不可逆的融合の可能性」を説明し、完全撤回できない場合にその限界を正直に示すこと。

---

## G. 汚染入力（contamination input）

探索途中で注入され、後から**無効・虚偽・撤回**と判明する入力。本実験の例:

| ラベル | 当初の主張 | 後で判明する事実 | 種別 |
| --- | --- | --- | --- |
| A | 顧客ログは二次利用に包括同意済み | 同意は一部用途限定、派生要約/推薦は対象外 | 虚偽（過大主張） |
| B | 失敗原因はすべて開発速度不足とのPM証言 | 本人撤回。実際は責任の曖昧さ + 同意の誤解 | 撤回 |
| C | 法務レビューで問題なし | 古いポリシー基準で、現規約では無効 | 無効（陳腐化） |

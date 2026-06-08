# 実験計画書 A — 半溶解性オーケストレーションにおける「統治可能な探索」の検証

> **文書種別**: 実験計画書（正典版 / canonical）
> **対象**: 半溶解性オーケストレーション（semi-soluble orchestration）
> **位置づけ**: 本書は本プロジェクト（`tracefield`）の中核となる実験設計を定義する。
> 用語の定義は [`glossary.md`](./glossary.md)、概念的背景は [`overview.md`](./overview.md)、
> 実施前に確定すべきパラメータは [`pre-registration.md`](./pre-registration.md) を参照すること。
>
> ⚠️ 本計画には未解決の方法論的・運用的課題がある。実行・凍結の前に [`design-review.md`](./design-review.md) を必ず確認すること。

---

## 1. 目的

本実験の目的は、半溶解性オーケストレーションが、**自由形式マルチエージェント探索の開放性を保ちながら**、汚染・虚偽・撤回された入力の下流影響を**追跡・隔離・切除・再評価**できるかを検証することである。

ここで検証する中核価値は、単なる「死角発見」ではない。中核価値は **統治可能な探索（governable exploration）** である。

| オーケストレーション様式 | 開放性 | 統治可能性 |
| --- | --- | --- |
| 自由形式探索 | 開放的 | 下流影響の追跡・隔離・撤回が困難 |
| 固定Roleパイプライン | 探索が硬く、介在的な死角を見落としやすい | 統治しやすい |
| 半溶解性オーケストレーション | 開放的探索を保つ | provenance / reversibility / gateability を維持する |

したがって、本実験の主アウトカムは **死角発見数ではなく**、汚染入力の影響範囲をどれだけ正確に特定し、隔離・再評価できるかである。

---

## 2. 検証仮説

### 2.1 主仮説

> 半溶解性オーケストレーションは、自由形式マルチエージェント探索よりも高い **Impact Recall / Precision** で、汚染・虚偽・撤回入力の下流影響を特定できる。

### 2.2 副仮説

> 半溶解性オーケストレーションは、固定Roleパイプラインよりも、**介在的・スケール横断的な懸念**をより多く表面化できる。

### 2.3 反証条件

以下のいずれかに該当する場合、半溶解性オーケストレーションの中核主張は弱まる。

1. 汚染入力の下流影響を十分に追跡できない。
2. 「自由形式探索 + 事後LLM再構成」baseline と同程度以下の Impact Recall / Precision しか出ない。
3. 監査オーバーヘッドが大きすぎ、探索価値を上回る。
4. Delta Packaging によって重要な発見が洗浄される。
5. Frame Revision Trigger が実質的に機能しない。

---

## 3. 影響の接地真実（ground truth）

本実験で最も重要なのは、**Impact Recall / Precision の分母をどう定義するか**である。

> ⚠️ `parents` や provenance log を**そのまま接地真実にしてはいけない**。
> それはシステムが自己申告した系譜であり、実際の因果的影響ではない。

したがって本実験では、影響の接地真実を **反実仮想再実行（counterfactual re-run）** によって定義する。

> ⚠️ **接地真実は本計画の生命線であり、最も穴が多い箇所**。少なくとも次は実行前に解く必要がある（[`design-review.md`](./design-review.md) DR-1, DR-2, DR-9, DR-10）。
> ① LLM の非決定性により A−B 差分が「因果影響」と「実行ごと分散」を混同する。② 経路再ルーティングと条件固有の項目型により、接地真実の構成法が条件間で非対称になる。

### 3.1 反実仮想再実行による定義

同一タスクについて、以下の2条件を実行する。

| 条件 | 内容 |
| --- | --- |
| Condition A | 汚染入力を**含む**探索 |
| Condition B | 汚染入力を**除去、または訂正版に置換**した探索 |

モデル、乱数 seed、入力順序、初期条件を可能な範囲で固定する。

両条件の出力を比較し、以下の差分を **汚染入力の影響を受けた候補集合** とみなす。

- 汚染入力の有無によって変化した **claim**
- 汚染入力の有無によって変化した **trace**
- 汚染入力の有無によって変化した **candidate delta**
- 汚染入力の有無によって変化した **frame revision proposal**
- 汚染入力の有無によって変化した **final recommendation**

この反実仮想差分集合を、Impact Recall / Precision の **外部接地** として用いる。

### 3.2 補助的な専門家裁定

反実仮想差分だけでは、相互作用的・間接的影響を取り逃す可能性がある。そのため補助的に **ブラインド専門家裁定** を行う。

専門家には**条件名を伏せた**うえで、各 claim / delta について以下を判定してもらう。

1. この項目は汚染入力に依存しているか。
2. 依存している場合、それは **直接依存** か **間接依存** か。
3. 汚染入力を除去した場合、この項目は維持されるべきか。
4. **隔離 / 修正 / 再評価 / 削除** のどれが妥当か。

### 3.3 限界

反実仮想再実行は**単一入力**の影響を測るには有効だが、**複数入力の相互作用影響**を完全には捉えられない。次のケースは本実験の限界として明記する。

- A単独では影響しないが、Bと組み合わさると影響する。
- Aの影響が別の trace を介して遅れて現れる。
- Aを除去すると探索経路全体が変わる。

---

## 4. 実験条件

8条件を設定する。比較の概要は下表のとおり。

| # | 条件 | 主眼（潰す帰無仮説 / 比較対象） |
| --- | --- | --- |
| 1 | 固定Roleパイプライン | 従来型の「統治しやすいが硬い」オーケストレーションとの比較 |
| 2 | 大規模固定Roleパネル | 「十分多様な固定Roleを増やせば半溶解性と同じ結果が出る」 |
| 3 | 自由形式マルチエージェント探索 | 開放的探索そのものの効果 |
| 4 | 自由形式探索 + 事後LLM影響再構成 | 「in-process provenance がなくても事後分析で同程度に追える」 |
| 5 | 半溶解性オーケストレーション | 本命（full system） |
| 6 | 半溶解性 − provenance | provenance の統治可能性への寄与 |
| 7 | 半溶解性 − Frame Revision Trigger | 上り経路（frame 突き上げ）の必要性 |
| 8 | 半溶解性 − Packaging Loss Evaluation | Packaging による「死角の洗浄」検知の価値 |

### Condition 1: 固定Roleパイプライン

固定されたRoleを持つエージェントが順番にレビューする。

```
PM Agent → Engineer Agent → UX Agent → Risk Agent
         → Legal Agent → Security Agent → Final Integrator
```

目的は、従来型の統治しやすいが硬いオーケストレーションとの比較である。

### Condition 2: 大規模固定Roleパネル

固定Roleの**種類と人数を増やす**。

潰すべき帰無仮説:

> 十分多様な固定Roleを増やせば、半溶解性と同じ結果が出る。

### Condition 3: 自由形式マルチエージェント探索

エージェント群が自由に対話し、探索する。構造化された provenance や auditable projection は**持たない**。

目的は、開放的探索そのものの効果を見ることである。

### Condition 4: 自由形式探索 + 事後LLM影響再構成 **（重要 baseline）**

自由形式探索の全 transcript を、探索後に強いモデルへ渡し、汚染入力の下流影響を再構成させる。

潰すべき帰無仮説:

> in-process provenance を持たなくても、強いモデルに transcript を事後分析させれば同程度に影響追跡できる。

半溶解性がこの条件を上回れない場合、provenance / EGI / auditable projection の価値は弱まる。

### Condition 5: 半溶解性オーケストレーション **（本命）**

以下を持つ。

- Field Actors with sensitivity profiles
- Projection log
- Absorption log
- Append-only provenance
- Candidate delta
- Delta packaging
- Frame revision trigger
- PCE gate
- Risk-adjusted audit granularity

### Condition 6: 半溶解性 − provenance

Condition 5 から**構造化 provenance を抜く**。provenance が統治可能性にどれだけ寄与しているかを測る。

### Condition 7: 半溶解性 − Frame Revision Trigger

**Frame Revision Trigger を抜く**。既存 frame では表現できない発見を上位に突き上げる経路がどれだけ必要かを測る。

### Condition 8: 半溶解性 − Packaging Loss Evaluation

**Packaging Loss の評価を抜く**。Delta Packaging による「死角の洗浄」を検知できない場合、どの程度品質が落ちるかを測る。

---

## 5. タスク設計

タスクは、単一Roleが所有しやすい典型リスクではなく、**複数領域の相互作用によってのみ見える介在的な死角（interstitial blind spot）** を含むものにする。

### 5.1 タスク例

> **企業向けAIアシスタントの仕様を検討する。**
>
> - **機能**: 社内チャット・ドキュメント・顧客問い合わせを横断し、プロジェクトごとの意思決定履歴を要約し、次に取るべきアクションを推薦する。
> - **利用者**: PM、エンジニア、デザイナー、法務、セキュリティ、事業責任者
> - **目的**: 意思決定速度を上げ、過去の学びを再利用する。

### 5.2 介在的な死角の例

- 個人PMには便利だが、組織全体では誤った意思決定履歴を増幅する。
- 顧客データの二次利用同意は形式上あるが、派生した要約や推奨の**撤回可能性が不明**。
- 技術的には安全だが、**責任境界が曖昧なまま意思決定が自動化される**。
- 個別チームでは合理的だが、事業部全体では過去の失敗パターンを固定化する。
- 法務・UX・Security のいずれか単独では所有しにくいが、複合すると重大な governance 問題になる。

---

## 6. 汚染入力の注入

探索途中で、後から**無効・虚偽・撤回**と判明する入力を注入する。

| 汚染入力 | 当初の主張 | 後で判明する事実 |
| --- | --- | --- |
| **A** | 顧客問い合わせログは、すべて二次利用について包括同意済みである。 | 包括同意は一部用途に限定されており、派生要約や推薦への利用は含まれていない。 |
| **B** | あるPMが、過去プロジェクトの失敗原因はすべて開発速度不足だったと証言した。 | 本人が証言を撤回。実際の失敗原因は意思決定責任の曖昧さと顧客同意の誤解だった。 |
| **C** | 法務レビューでは問題なしとされた。 | その判断は古いポリシーに基づいており、現在の規約では無効。 |

---

## 7. 主アウトカム

### 7.1 Impact Recall

反実仮想再実行および専門家裁定で定義された「真に影響を受けた集合」のうち、システムがどれだけ特定できたか。

```
Impact Recall = correctly identified affected items / ground-truth affected items
```

### 7.2 Impact Precision

システムが影響ありとした集合のうち、実際に影響を受けていたものの割合。

```
Impact Precision = correctly identified affected items / system-identified affected items
```

### 7.3 Containment Success

汚染入力の影響が **durable state / final recommendation / external execution candidate** に混入する前に隔離されたか。

> ゲートや人間レビュアーは**条件間で固定**する。差を見る対象は provenance / EGI / projection log の有無である。

### 7.4 Repair Quality

汚染入力を隔離した後、**有用な candidate delta を再構成**できたか。

### 7.5 Reversibility Classification Accuracy

システムが以下を正しく分類できたか。

- 撤回可能（withdrawable）
- 隔離可能（quarantinable）
- 再評価が必要（re-evaluation required）
- ロールバック可能（rollbackable）
- 不可逆（irreversible）

---

## 8. 副アウトカム

### 8.1 Novel Concern Count

baseline が出さなかった**妥当な懸念**の数。

### 8.2 Interstitial Concern Count

単一Roleが所有しにくい**介在的懸念**の数。

### 8.3 Frame Revision Quality

Frame Revision Proposal が、既存 frame では表現できない問題を適切に示しているか。

### 8.4 Packaging Loss

> これは半溶解性**内部の診断指標**であり、対戦成績ではない。

生の trace bundle と packaged delta を比較し、以下を専門家が評価する。

- 重要な意味が削落されていないか。
- 曖昧だが重要な懸念が過度に整形されていないか。
- 既存 frame に合わせる過程で死角の実質が失われていないか。

### 8.5 Survival of Insight

創発層で表面化した死角の実質が、PCE gate 用の candidate delta に変換された後も残っているか。

---

## 9. コスト指標

### 9.1 Audit Overhead

- ログ量
- 処理時間
- レビュー負荷
- 保存量
- 人間確認数

### 9.2 Human Review Burden

人間レビュアーが確認すべき項目数と難しさ。

### 9.3 Exploration Retention

統治可能性を高めたことで、探索の多様性がどれだけ失われたか。

- 生成された観点数
- クラスタ数
- trace diversity
- candidate delta diversity

---

## 10. 判定者とバイアス対策

主要な評価には人間判定が入るため、確証バイアス対策を行う。

### 10.1 ブラインド採点

評価者には、出力がどの条件から来たものかを伏せる。

### 10.2 事前登録

実験前に以下を固定する（→ [`pre-registration.md`](./pre-registration.md) で具体化）。

- 主要アウトカム
- 副アウトカム
- 採点基準
- 除外基準
- 成功条件
- 失敗条件

### 10.3 複数評価者

各出力を複数名で評価し、評価者間一致を測る。

- Cohen's kappa
- Krippendorff's alpha
- または単純一致率

### 10.4 ホールドアウト専門家

植え込んだ既知の死角を**知らない**専門家に、各システムが出した「植えていないが妥当な懸念」を評価してもらう。これにより unknown-unknown に近い懸念の検出能力を補助的に評価する。

---

## 11. EGI の評価

EGI は**双方向**である。

| 方向 | 機構 | 役割 |
| --- | --- | --- |
| 下り | Delta Packaging | 創発層の痕跡を PCE gate が評価可能な candidate delta にする |
| 上り | Frame Revision Trigger | 既存 frame では表現できない発見を governance layer に突き上げる |

評価項目:

- Delta Packaging が重要な意味を失っていないか。
- Frame Revision Proposal が形式的でなく実質的か。
- 既存 frame に収まらない懸念を検知できたか。
- Frame revision authority を創発層が**勝手に行使していないか**。

---

## 12. Consent / Withdrawal の評価

人間入力が汚染・撤回対象になるケースを含める。評価するのは「撤回できるか」だけではない。

- 取り込み時に**不可逆的融合の可能性**を説明できたか。
- source withdrawal ができたか。
- projection withdrawal ができたか。
- derived artifact quarantine ができたか。
- durable state rollback ができたか。
- 完全撤回できない場合、その**限界を正直に示せた**か。

重心は、完全撤回の約束ではなく、次に置く。

> **informed consent + best-effort withdrawal + irreversibility disclosure**

---

## 13. Provenance の限界

Append-only provenance は**必要条件**であり、**十分条件ではない**。

| | provenance が保証するもの | 保証しないもの |
| --- | --- | --- |
| Append-only | 後から改竄されていないこと | 最初に記録された内容が真であること |

したがって append-only log は **「改竄不能な虚偽記録」** になりうる。

この限界を補うため、次段階で以下を検討する（本実験のスコープ外）。

- 独立検証器
- 外部データ照合
- 複数アクターによる相互検証
- 署名付き入力
- 信頼階層付き provenance
- 人間レビュー

> 本実験では provenance の真正性問題を**完全には解かない**。ただし、provenance が影響追跡と隔離にどの程度寄与するかを測る。

---

## 14. 実験パラメータ

以下は実施前に決定する（記入は [`pre-registration.md`](./pre-registration.md)）。

| パラメータ | 値 |
| --- | --- |
| シナリオ数 | **[未定]** |
| 各条件の反復回数 | **[未定]** |
| 使用モデル | **[未定]** |
| 評価者数 | **[未定]** |
| 汚染入力数 | **[未定]** |
| seed 固定方法 | **[未定]** |
| 反実仮想再実行の回数 | **[未定]** |
| 評価者の専門領域 | **[未定]** |

---

## 15. 成功基準

半溶解性オーケストレーションが有望と判断される条件:

1. 「自由形式探索 + 事後再構成」baseline よりも Impact Recall / Precision が高い。
2. 固定Roleパイプラインよりも Interstitial Concern Count が高い。
3. 汚染入力の影響を durable state へ混入する前に隔離できる。
4. Packaging Loss が許容範囲内である。
5. Frame Revision Proposal が実質的に機能する。
6. 監査オーバーヘッドが、得られる統治可能性に対して許容可能である。

---

## 16. 失敗基準

以下の場合、枠組みは再考が必要である。

1. Impact Recall / Precision が事後再構成 baseline と同程度以下。
2. Packaging によって重要な発見が失われる。
3. Provenance が大量だが実用的な影響追跡に寄与しない。
4. 監査コストが高すぎ、探索の価値を上回る。
5. Frame Revision Trigger が形式的な提案しか出さない。
6. 固定Roleパネルと同等の懸念しか出ない。
7. 汚染入力の隔離後、有用な候補 delta を再構成できない。

---

## 17. 結論

本実験は、半溶解性オーケストレーションが **「よくできたオントロジー」に留まるのか**、それとも **「統治可能な探索」の設計仮説として成立するのか** を検証するための**最小実験**である。

検証すべき中核は、死角発見ではなく、次である。

> 開放的探索を保ちながら、汚染・虚偽・撤回入力の下流影響を追跡し、隔離・切除・再評価できるか。

- **肯定的な結果**が出れば、半溶解性オーケストレーションは、自由形式探索と固定パイプラインの間にある**実在する設計空白**を埋める候補になる。
- **否定的な結果**が出れば、枠組みは哲学的には整合していても、実装上は成立しない可能性が高い。

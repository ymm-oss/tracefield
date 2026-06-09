# tracefield — ドキュメント

`tracefield` は、**半溶解性オーケストレーション（semi-soluble orchestration）** が
「統治可能な探索（governable exploration）」の設計仮説として成立するかを検証する研究プロジェクトである。

中核の問いは、死角発見の多寡ではない。

> 開放的なマルチエージェント探索を保ちながら、
> **汚染・虚偽・撤回された入力の下流影響を追跡し、隔離・切除・再評価できるか。**

---

## ドキュメント一覧

| 文書 | 内容 | こんなときに読む |
| --- | --- | --- |
| [`overview.md`](./overview.md) | 概念的背景・設計空白の主張・中核価値・EGI の双方向構造 | まず全体像を掴みたい |
| [`experiment-plan.md`](./experiment-plan.md) | 実験計画書A 本文（全17節）。目的・仮説・接地真実・8条件・指標・成功/失敗基準 | 実験設計の正典を参照したい |
| [`glossary.md`](./glossary.md) | 用語集（Field Actor / provenance / EGI / PCE gate / 各種指標 など） | 用語の定義を確認したい |
| [`design-review.md`](./design-review.md) | 設計レビュー。実行・凍結の前に解くべき方法論的/運用的な穴を重大度別に整理（DR-1〜DR-20） | 計画を実行に移す前に穴を潰したい |
| [`mvp.md`](./mvp.md) | MVP 設計。接地真実の妥当性（DR-1/DR-2）を先に測る最小 de-risking プローブ（C4 vs 薄いC5・1汚染・自動指標） | 本実験の前に最小実証で前提を検証したい |
| [`findings-mvp.md`](./findings-mvp.md) | **MVP 第1次結果**。実モデルで汚染影響を局在化できた（precision/recall=1.0）。効いた設計（スタンス測定）と発見したバグ・限界 | 何が分かったか・次に何をすべきか知りたい |
| [`experiment-results.md`](./experiment-results.md) | **本実験フェーズ結果**。C1〜C8 比較行列（C5=recall1.0、C6 ablation で provenance が load-bearing、C2 で「Role増やせば」null 棄却）+ 結論・限界 | 条件比較の最終結果を知りたい |
| `mvp-impl-brief*.md` / `../RUNNING.md` | codex への実装ブリーフ群と実行手順（Elixir ハーネス） | 実装の詳細・動かし方を知りたい |
| [`pre-registration.md`](./pre-registration.md) | 事前登録書（記入式）。`[未定]` パラメータと採点基準・分析計画、設計レビュー由来の追加項目（DR-*）を凍結する | 実験を始める前に確定事項を埋める |

推奨読み順: **overview → experiment-plan → glossary（適宜参照） → design-review（穴の確認） → mvp（最小実証） → pre-registration（実施前に記入）**

> ⚠️ **実行前の必読**: `design-review.md`。特に接地真実（反実仮想再実行）の妥当性（DR-1, DR-2）は主アウトカムの生命線で、ここが崩れると他の結果は無意味になる。

---

## いま何が決まっていて、何が未定か

- **決まっていること**: 中核価値（統治可能な探索）、主仮説/副仮説/反証条件、接地真実の方法（反実仮想再実行 + 専門家裁定）、8条件、主/副/コスト指標、成功/失敗基準。
- **未定（実施前に確定）**: シナリオ数・反復回数・使用モデル・評価者数/専門領域・汚染入力数・seed 固定方法・反実仮想再実行回数。
  → これらは [`pre-registration.md`](./pre-registration.md) で埋めて凍結する。

---

## 8つの実験条件（早見）

| # | 条件 | 役割 |
| --- | --- | --- |
| 1 | 固定Roleパイプライン | 統治しやすいが硬い従来型との比較 |
| 2 | 大規模固定Roleパネル | 「Roleを増やせば同等」を潰す |
| 3 | 自由形式探索 | 開放的探索そのものの効果 |
| 4 | 自由形式探索 + 事後LLM再構成 | **重要 baseline**（事後分析で追えるか） |
| 5 | 半溶解性オーケストレーション | **本命** |
| 6 | 半溶解性 − provenance | provenance の寄与 |
| 7 | 半溶解性 − Frame Revision Trigger | 上り経路の必要性 |
| 8 | 半溶解性 − Packaging Loss Evaluation | 「死角の洗浄」検知の価値 |

詳細は [`experiment-plan.md` §4](./experiment-plan.md#4-実験条件)。

---

## 注記

- 本ドキュメント群は実験計画書A（原文）を正典化・構造化したもの。記述は原文に忠実であることを優先している。
- 原文に正式名称の明示がない略語（**EGI** / **PCE gate**）は文脈からの**推定**として定義しており、[`glossary.md`](./glossary.md) にその旨を明記している。正式名称が判明した場合は glossary を起点に更新すること。

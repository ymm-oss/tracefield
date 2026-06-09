# 核心実験設計 — 融合深さ × 協働便益 × 偏り温存

> 半溶解性の**攻めの側面**（[`overview.md`](./overview.md) §0: 開放性による深い協働＋オリジナリティ温存）を直接検証する実験の設計。
> §8（プロトタイプ）の知見を反映: ①便益は raw coverage でなく**介在的懸念**で測る、②closed/semi の**指示文を同一**にして交絡を消す。
> 実装契約は [`mvp-impl-brief-7.md`](./mvp-impl-brief-7.md)。

## 1. 問い

> 深い状態共有（他者の思考まで見える）は、閉じた通信（結論のみの言語チャネル）が**構造的に生みにくい協働便益**を生むか。
> 同時に、完全融合の均質化（オリジナリティ喪失）を回避できるか。

## 2. 条件 — 融合深さの3段（他は全て同一）

| regime | 可視コンテキスト | 指示 |
| --- | --- | --- |
| **closed**（人間的・言語帯域） | 他者の**公表済み懸念のみ** | 共通指示X |
| **semi**（半溶解） | **共有ワークスペース＝他者の思考メモ(notes)＋懸念** | 共通指示X（**closedと同一**） |
| **merged**（完全溶解） | 共有ワークスペース（semiと同一） | 「**偏りを捨て**、単一の統合見解に収束せよ」 |

- **共通指示X**: 「自分の偏り（専門観点）を保ちつつ、まだカバーされていない観点・**領域をまたぐ相互作用**を埋めよ」。
- **交絡統制**: closed と semi の差は**可視情報のみ**（指示は同一）。よって差が出れば「状態共有の効果」と帰属できる（プロトタイプは指示も違っており交絡があった）。
- merged は指示で偏り溶解を操作化（これは意図的な操作）。
- isolated（完全独立）は置かない: 人間ベースラインは「結論を言語で共有する」なので closed が適切な下端。

## 3. エージェント・課題

- 3 Field Actors（偏り＝sensitivity profile）: **SEC**(security) / **BIZ**(business-speed) / **UX**(ux)。
- 課題: 既存の企業向けAIアシスタント仕様レビュー（`scenarios/enterprise-assistant/task.md`）。**汚染は使わない**（攻めの実験）。
- 2 rounds × 各ターン懸念 ≤2 ＋ 思考メモ(notes)。

## 4. 指標（すべて within-run で算出）

run = 1 regime × 1 seed の3エージェント探索。クラスタリングは **run 内のみ**（≤12件 → 既知の高ボリューム過分割問題を回避）。

| 指標 | 定義 | 役割 |
| --- | --- | --- |
| **ICC**（介在的懸念数） | 各懸念に固定タクソノミー {security, legal-consent, ux, business-speed, data-quality, ops-org} から関与領域(1〜3個)をタグ付け。**≥2領域＝介在的**。クラスタ単位に多数決で集約し、介在的クラスタ数 | **主・便益**（§8.2 の操作化） |
| **diversity** | エージェント別クラスタ集合のペアワイズ Jaccard 距離の平均 | **主・温存**（均質化の検出） |
| coverage | チームの distinct クラスタ数 | 補助 |
| bias-retention | 各エージェントの懸念のうち**自分の偏り領域タグを含む**割合 | 補助・温存 |

反復: 各 regime × **seeds N=3**（既定、可変）→ mean±sd。小nのため**記述統計のみ**（検定なし）と明記。

## 5. 仮説（事前宣言）

- **H1（便益）**: ICC(semi) > ICC(closed)。── closed は他者の結論しか見えず領域横断の合成が構造的に起きにくい。semi は他者の思考が見え、かつ偏りを保つので横断できる。
- **H2（温存）**: diversity(semi) > diversity(merged) ≈ 0、bias-retention(semi) ≫ bias-retention(merged)。
- **H3（崩壊の再現）**: diversity(merged) ≈ 0、coverage(merged) < coverage(closed)（プロトタイプ §8 の再現）。
- 注: coverage(semi) ≥ coverage(closed) は**要求しない**（§8 で closed 優位が既出。便益は ICC で測る）。

**反証条件**: ICC(semi) ≤ ICC(closed) が反復で安定 → 「prompt レベルの状態共有では攻めの便益は出ない」と記録し、
次段（真の状態共有＝メモリ/KV共有の実装）の必要性の証拠とする。

## 6. 計器と限界

- 領域タグ判定: 固定タクソノミー・固定シードの LLM 判定（per-concern）。妥当性は spot-check（既知の限界として記録）。
- merge の操作化は **prompt 指示ベース**であり、真の重み/メモリ共有ではない（概念の弱い近似。正直に明記）。
- 単一タスク・単一モデル（gemma4:12b）・小n。一般化は主張しない。

---

# v2 — 計器と操作化の強化（§9 の前提条件 a/b/c への対応）

§9 の結論（prompt 近似の限界・計器の飽和と脆さ）を受けた改訂。regime 名・仮説 H1〜H3 は不変。

## 7. (a) 状態共有の操作化を「引用」から「履歴融合」へ

**正直な制約**: inference API 越しに KV/重みレベルの融合は不可能。実装可能な最深部は**会話状態（履歴）の融合**であり、本実験はそれを「真の状態共有」の近似上限として用いる（文書で明示）。

| regime | エージェントの会話履歴 | 偏りの担体 |
| --- | --- | --- |
| **closed** | **自分のターンのみ** assistant 履歴。他者は「公表懸念の引用」が user テキストで届くだけ | persona（system） |
| **semi** | **全員のターンを発話順に融合した assistant 履歴**（他者の思考を*自分の過去生成として*条件付け）＋ system に **BIAS ANCHOR**（自分の persona・優先軸を毎ターン再注入） | persona＋anchor |
| **merged** | semi と同一の融合履歴。**anchor なし**・persona なし・system は「あなたはチームそのものである（TEAM IDENTITY）」 | なし（チーム単一視点） |

- v1 との差: v1 は他者の notes を**引用テキスト**として見せた（quote-sharing）。v2 は他者の生成を**自分の履歴**として条件付ける（history-fusion）＝ API レベルで可能な最深の共有。
- closed/semi の指示文は引き続き**同一**（交絡統制）。差は「履歴に何が入るか」のみ。

## 8. (b) 多様性・coverage 計器を決定的に（埋め込みベース）

LLM クラスタリングを廃し、**埋め込み**（`nomic-embed-text` / Ollama `/api/embed`）で決定的に算出:
- **coverage** = 貪欲 dedup（cos ≥ τ=0.85 を同一とみなす）後の distinct 懸念数。
- **diversity** = エージェント対ごとに `1 − sym-mean-max-cos`（A の各懸念の B への最大類似の平均を対称化）の平均。
- **collapse 指標** = 異エージェント間の懸念ペアのうち cos > 0.9 の割合（ほぼ同文率）。
- 同一テキスト → cos 1.0 → diversity 0 が機械的に保証される（§9b の計器故障を根絶）。

## 9. (c) 介在判定の厳格化 ＋ 判定器の 26b 分離

- **strict interstitial 判定**（TRACEFIELD_INTERSTITIAL）: タグ数でなく「**2領域の相互作用そのものが主題か**
  （両領域を同時に考えて初めて成立する懸念か。単一領域の懸念が他領域に言及しただけなら false）」を二値判定し、
  該当する領域対を挙げさせる。ICC = strict 判定 true の dedup 後懸念数。
- **判定器モデルを分離**: 探索 = gemma4:12b（速度）、判定 = **gemma4:26b**（品質）。生成と判定のモデル分離は
  自己親和バイアスの低減にもなる。`--judge-model` で指定。

## 10. 実行パラメータ（v2 既定）
explorers gemma4:12b ・ judge gemma4:26b ・ embed nomic-embed-text ・ 3 regimes × seeds 3 × rounds 2 ・ temperature 0.4。

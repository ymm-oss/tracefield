# findings: surface-don't-resolve（対立を解決せず提示する）と scale_by 共有文脈

## 問い
定例MTG/多ステークホルダ調査のように、1つの論点(matter)に複数当事者の*対立する立場*が共存する素材から、AI が対立を1つの結論に畳まずに「誰がどの立場か」を来歴つきで提示できるか（surface, don't resolve）。実データ＝公開 TC39 議事録(2024-10 plenary, Extractors 提案)、adapter=cli(codex/claude)、n=1。

## 失敗: 単一文脈 LLM の matter 整合は collapse する
「全 stance を1文脈で読み matter を正準化し 1:1 で再出力」する単一 LLM 段は、closed-set 指示・debate による集合補完・「1件も落とすな/件数一致」の明記をしても、入力 15〜18 → 出力 3 に collapse（少数＝対立 voice を落とす）。3回再現（matter_align / matter_propose / matter_label すべて ~3）。[[findings-diffusion-thinking]] の「単一 NORM は*開放集合*で定番へ再収束し新領域を黙って落とす」(auto-memory 訂正 2026-06-23) と同型。**プロンプトでは単一文脈 LLM の reduce 挙動を止められない。** → no-drop は構造でしか保証できない。

## 解: 「下層=網羅抽出 / 上層=整合」を分離し、整合を構造で no-drop にする
1. **coverage（per-unit）**: 長文を chunk に割り `per_input` で 1 actor=1 chunk 抽出。1 actor が長文を1回読む設計は網羅不足（18 中 3 しか出ない）→ chunk 化で 18 stance。PDF の「ページ数だけ担当レンズを置く」と同型。
2. **matter 集合を閉じる（異種 debate）**: codex が正準 matter を提案 → **claude が欠落/恣意 merge を反証し欠落 matter を足し戻す**。単一モデルの方向性 drop を異種反証で補う（[[findings-bet2-overturn]]: debate>>単一、異種 organ が真の対照）。実測: claude が `【欠落matter】Web互換性・ASI` `エンジン実装` を追加し、いずれも後段で CONTESTED 化＝codex 単独が落とした対立を救った。
3. **no-drop ラベル付け（`shared_inputs` ＝ scale_by 共有文脈）**: `per_input` で stance を1個ずつ shard ＋ 確定した matter リストを `shared_inputs` で全 actor に共有。1 actor=1 stance を閉じた集合にラベル付け＝**物理的に collapse 不能**。実測 18→18 無落とし（単一文脈の 16→3 と対照）。これが律速の engine プリミティブ（拡散実験と会議ケースが独立に同じ gap に収束した）。
4. **機械的・発言者ベースの CONTESTED 判定**: 当事者識別は `entry.author`（＝actor 役割、全 stance で同一）でなく `meta.speaker`（発言者）。`contested_map` artifact が matter 別 group ＋ distinct speaker ≥2 で `⚠ CONTESTED`。LLM 合成でなく rule-based fold（[[findings-lens-type]] §6.6 / 北極星「最終結論は機械的集約」）。

## 実測（TC39, n=1）
18 stance → 18 ラベル（no-drop）。複数 matter が正しく CONTESTED 化: 「Stage 2進行可否」(DE/RBN/SYG)、「エンジン実装・最適化戦略」(DRR/SYG＝native 実装の対立)、「機能範囲・構文・利用価値」(RBN/SYG…)、「性能・TypeScript最適化」(JRL/RBN)。AI は結論を1つに畳まず、実際の TC39 の対立をそのまま提示した。

## 残課題
- relabel 段で `meta.speaker` を一部(18 中 ~4)落とし party が `MATTER_LABEL` 表記に＝忠実性（プロンプト）課題で、構造ではない。
- **n=1**。係数・頑健性は要再現。
- TC39 は技術政治＝政治的潜在状態/agenda 無し＝**P1(対立抽出)の検証**であって、P2(agenda 条件付き先読み)/feasibility(retrieval vs judgment)は別。公開素材には agenda/事前登録デッキが無く、本来の feasibility 判定は実 prep 待ち。

## 実装
- engine(`crates/tracefield-core/src/flow.rs`): `shared_inputs`（StageConfig field／`per_input` は `inputs` を shard・`shared_inputs` を全 actor に共有）＋ `entry_speaker`（`meta.speaker` フォールバック `author`）＋ `contested_map` artifact format（matter 別 group・無落とし・≥2 speaker で CONTESTED、機械描画）。
- 単体テスト: `shared_inputs_reach_every_actor_without_drop_or_dup` / `contested_map_groups_members_and_flags_divergence`。
- scenario(committed): `scenarios/meeting-support-probe`（合成テンプレ＋ foresight deepen-loop arm）、`scenarios/meeting-support-probe-tc39`（**config＋出典 URL のみ。実トランスクリプトは vendoring せず README の手順で各自取得**＝`scenarios/` を synthetic 限定に保つ・CLAUDE.md 準拠）。

# 設計 — クラスタの自動生成（析出）

> 「クラスタは同時多発的に発生して有機的につながる」の**発生**側。[`design-cluster.md`](./design-cluster.md) の続編。
> 位置づけ: これは実験計画書Aで唯一未検証だった **EGI 上り＝Frame Revision Trigger の組織スケール操作化**である ──
> 既存 frame（現在のクラスタ編成）では表現できない発見が、**構造そのものを作り変える**（新チームの析出）。

## 1. 3つの発生様式

| 様式 | トリガ | 人間組織の対応物 |
| --- | --- | --- |
| **析出（precipitation）** — 本命 | メタ場に**どのクラスタにも属さない高密度な話題の引力圏（attractor）**が形成される | 横断ワーキンググループの結成 |
| **需要駆動（demand）** | 新タスクの embedding がどの既存クラスタの charter にも合致しない | 新規プロジェクトチーム |
| **分裂（mitosis）** — v2 | 1クラスタの store が双峰化（自前 entries が2つの分離可能な塊に） | 部門の分割 |

析出が本命である理由: 引力圏の成員 entries が**複数クラスタ由来**であることを条件にすれば、
それは**クラスタスケールの介在的懸念**（§8.2 の上位版）── 単一チームが所有できない主題が、自分の居場所を要求している状態。

## 2. 析出の検出（attractor detection）

メタ場の active な非 chunk/非 procedure entries（全クラスタの公開知見）に対して:

1. **グループ化**: embedding の貪欲クラスタリング（`τ_genesis`、既定 0.7 目安）。
   ※ §10b の教訓: **しきい値は絶対値でなくベースライン相対で較正**（既存クラスタ内 entries の凝集度を基準に）。
2. **attractor 判定**（3条件すべて）:
   - **密度**: 成員数 ≥ `min_size`（既定 4）
   - **横断性**: 由来クラスタ数 ≥ 2（source_cluster の distinct 数 ── 介在性）
   - **無主性**: グループ重心と各既存クラスタ **charter**（後述）の類似が全て < `τ_claim`（既にどこかの仕事である主題は対象外）
3. 検出結果は**genesis 提案**として出力（即生成はしない ── §3 の統治へ）。

**charter** = クラスタの自己同一性の表現。v1 は「task.md 全文＋直近の公開 entries の重心 embedding」。
store が育つと charter も更新される（版管理: charter entry を META に publish し直す）。

## 3. 発生の統治（有機的 ≠ 無統制）

発生イベント自体を半溶解の統治下に置く:

- **出生証明（citable genesis）**: genesis 提案は META への `:genesis` entry ──
  **「このクラスタは e12, e17, e23 ゆえに存在する」**を citation で記録（存在の provenance）。
- **ゲート**: 提案は即実行されない。v1 は**人間承認**（PCE gate の組織スケール版 ── 未実装だった PCE gate がここで本来の役割を得る）。
  将来は予算上限・しきい値による自動承認も。
- **可逆性**: クラスタは**解散・併合**できる（genesis entry を superseded に、store はアーカイブ、
  他クラスタへ渡った写しは provenance ごと生存）。
- **スプロール対 均質化の双対**（場スケールの「半」）: 生成しきい値が低すぎる → クラスタ乱立＝**どこにも臨界質量が無い（不溶）**。
  高すぎる → 巨大単一クラスタ＝**完全溶解**。→ **場レベル計器**で動作点を監視:
  クラスタ数、charter 間多様性（embedding 距離）、クラスタ間引用率。
  単一クラスタで実証した「半の動作点」が場スケールにも存在する、が本設計の中心仮説。

## 4. 新生クラスタの初期付与（endowment）

| 要素 | 生成方法 |
| --- | --- |
| `task.md`（charter） | attractor 成員 entries から LLM が起草（「この主題を所有するチームの使命」） |
| 種 store | 成員 entries を `Meta.pull`（source_chain 付き＝**生まれた瞬間から来歴がある**） |
| `agents.json` | v1: **由来クラスタごとに1レンズ**（その視点の代表）＋汎用1体。LLM 起草・人間編集可 |
| 手続き | 既定手続き＋（任意）由来クラスタの手続きを採用（採用 provenance 付き） |
| 私的メモリ | **空から開始** ── 偏りは run を重ねて育つ（brief-15 の来歴機構がそのまま新クラスタの個性形成になる） |
| META 接続 | `links: :auto` に参加（publish/discover/撤回伝播が出生時から有効） |

## 5. ライフサイクル（全体像）

```
析出/需要 → genesis 提案（citable） → ゲート承認 → endowment → 成長（store・メモリ・charter更新）
  → 接続（publish/discover/越境統治） → [分裂 | 併合提案（charter類似が持続的に高い2クラスタ） | 解散]
```

併合は「2クラスタの完全溶解」なので**まれ・要ゲート**（半の原則）。解散は store アーカイブ＋最終 publish。

## 6. 実装スケッチ（v1 = brief-20 候補）

- `Tracefield.Genesis.detect(meta_ref, charters, opts)` → `[%{members, source_clusters, centroid_sim_to_charters, proposal_text}]`
  （決定的: embedding 貪欲グループ化＋3条件。LLM 不使用＝検出は計器）。
- `Tracefield.Genesis.propose(meta_ref, attractor)` → `:genesis` entry を META に absorb（成員 citation 付き）。
- `Tracefield.Genesis.scaffold(proposal, dir, opts)` → シナリオディレクトリ生成
  （task.md/agents.json は LLM 起草、store.jsonl は成員 pull で種入れ）。**実行は人間承認後**（mix タスクで段階分離）。
- `mix tracefield.genesis --meta <store> --detect`（提案一覧表示）/ `--scaffold <proposal-id> --dir <path>`。
- 場レベル計器: `mix tracefield.field --stats`（クラスタ数・charter 間距離行列・クラスタ間引用率）。

## 7. 未解決（正直に）

- `τ_genesis / τ_claim` の較正 ── 実データで相対較正の手順を確立する必要（日本語短文×nomic の凝集度は §10b 参照）。
- charter 更新の頻度・方式（重心ドリフト vs 版管理）。
- 新生クラスタの**レンズ設計の質**（LLM 起草は汎用に流れがち ── 由来クラスタ代表＋人間編集で緩和、要検証）。
- 分裂（mitosis）の検出は v2。需要駆動も v1 では手動起点（タスク到着のフックが要る）。
- **発生の評価**: 「析出したクラスタは、しなかった場合より良い成果を出すか」── 検証設計が必要（反実仮想の新版）。

---
name: tracefield-flow-design
description: tracefield の flow.toml / agents.json を設計する（中身の意思決定: レンズ選定・ステージ構成・機械的集約・沈殿）。「flow.tomlを設計して/書いて」「agents.jsonを作って」「レンズを選んで」「調査フローを設計して」「審議パネルを組んで」と言われた時に使用する。シナリオの新規作成・実行・retract・doctor など CLI 運用は tracefield-operator を使う。
---

# Tracefield Flow Design

flow.toml / agents.json を**設計**するための意思決定ガイド。全フィールド・有効値・
アダプタ別の `model` の書き方は
[flow-spec.md](../tracefield-operator/references/flow-spec.md)、`agents.json`／
ディレクトリ構成は
[scenario-format.md](../tracefield-operator/references/scenario-format.md)、CLI 運用は
[tracefield-operator](../tracefield-operator/SKILL.md) を読む。
根拠はリポジトリ `docs/` の findings: `findings-lens-type.md` / `findings-diffusion-thinking.md` /
`findings-longrun-investigation.md` / `findings-being-sedimentation.md`。

コピペ可能なテンプレは [references/patterns.md](references/patterns.md)。

## 鉄則（これだけは外さない）

1. **偏りを持つ「観点」はレンズ、他者の出力に作用する「操作」はステージ。** 止揚(合成)・反証(批判)はレンズにせずステージに置く。
2. **全 LLM 呼び出しを"忠実な小規模文脈域"に留める。** 一枚岩 SYNTH に多レンズ＋反証を渡すと規模で劣化（レンズ脱落・捏造・結論反転、弱モデルほど激しい）。統合は LLM 再合成でなく `tracefield aggregate` の機械的集約で出す。
3. **多様性は中央集権で殺すな。** 単一統合者は少数意見を溶かす。ピア反復(long_run cycles)は collapse しない。

## レンズ設計（agents.json）

**価値序列（高→低）**: 相互に直交する複数の哲学分野（帰結主義⇄義務論⇄現象学⇄系譜学）＞ 構造変更型の論理操作（場合分け）＞ 分析フレームワーク（制約理論・可逆性・リスク）＞ ロール（職能）。

- **直交性が効く**。「哲学」という塊でなく、注目対象が互いに還元不能な分野を混ぜる。対立する哲学レンズ（功利⇄義務）を1〜2枚入れると、ロールだけのパネルが見落とす死角・代替案が表面化する（盲検確証済み）。
- **ロールは冗長**。職能ロール（BE/PM/SRE/FIN）は同じ事実に重点を変えるだけで構造的再framing を出さない。richな desc にしても変わらない。バイインの当事者マッピングが目的なら可、死角照射が目的なら不可。
- **場合分け(CASES)は強い**。決定変数で場合分けし「1つ選ぶ」を「条件マップ」に変える。唯一、選択肢成立の境界条件を出す。
- 各レンズの desc に**死角を一文明記**（例: "死角: 少数者の不公平を総和に埋もれさせる"）。
- **操作系をレンズにしない**: 止揚/MECE/triangulation（合成）、反証/反例/背理法（批判）は agents として置くが**ステージ専用**にし、analysis パネルに混ぜない。

## ステージ設計（flow.toml）

統治された調査の標準骨格（中央 SYNTH なし）:

```
analysis（直交レンズのパネル） → verify（FALSIFY/COUNTER） → adjudication（per_input: 反証1件=1審判） → [tracefield aggregate で機械集約]
```

- **analysis**: `inputs=["path:task.md"]`。レンズ数だけ actor（`mode="fixed"` + `roles=[...]` か `per_agent`）。
- **verify**: `inputs=["stage:analysis"]`。FALSIFY/COUNTER は自前結論を出さず反証だけ。最も決定的な内容を産む。
- **adjudication**: `mode="per_input"` + `roles=["ADJ"]`。verify の各反証エントリが 1 actor にシャードされ、独立 verdict を下す（一枚岩 SYNTH が反証を黙殺するのを構造的に封じる）。ADJ の verdict は必ず正準ラベル **「判定: {結論変更を要する / 条件付きで結論維持 / 却下}」** で書かせる（`tracefield aggregate` がこのラベル先頭で分類）。
- **集約は機械的に**: 最終 SYNTH ステージを置かず、run 後に `tracefield aggregate --store <jsonl>` を呼ぶ。overturn が1件でも→結論変更 / unclassified→indeterminate(要対応・silent drop なし) / それ以外→維持＋条件の和集合。

### 反復（denoise）と沈殿
- 多サイクル精製は `[long_run] cycles=3 cycle_stages=["analysis"]` ＋ `inputs=["path:task.md","stage:analysis"]`（自己/相互参照）。**約3サイクルがスイート**（cycle1粗→cycle2立場ロック→cycle3二次精製、cycle4で飽和）。ピア反復は mode collapse しない。
- **沈殿した経路依存の立場**を育てるなら、単一 agent＋最小 seed＋自己参照サイクル。既定アトラクタに逆らう種でも保持・自己強化する（確証済み）。

### 検証可能性（retract）
- provenance が要る/後で覆す可能性があるなら `--persist <jsonl>`。load-bearing 前提を `tracefield retract` するとクロージャ伝播で依存結論が自動再開され、再 `aggregate` で基盤が再計算される。

## 設計に効く制約（運用機構は tracefield-operator）
- **モデルは合成の頑健性に効く設計変数**。弱いモデルは大入力で合成が激しく崩れる（レンズ脱落・結論反転）→ 鉄則2「小規模域に留める」を一層厳守。例: `adapter="cli" command="claude" model="claude-sonnet-4-6"`（adapter/model の権威ある設定・mock検証・ビルド済みバイナリ等の運用は operator 参照）。
- `per_input` は入力エントリ数に actor をスケール（`roles` 長1なら全 actor が同一 lens 駆動）＝ステージ設計の道具。

## アンチパターン（findings 由来）
- 死角照射目的でロールパネルを使う（冗長）。
- 止揚/反証をレンズにする（自前テーゼが無くステージ操作）。
- 一枚岩 LLM SYNTH に多項目を渡して統合させる（規模で脱落・捏造、少数意見を溶かす）。
- フォーマット強制で合成を直そうとする（体裁だけ整え中身は捏造する＝かえって危険）。隔離＋機械集約で直す。

---
name: tracefield-flow-design
description: tracefield の flow.toml / agents.json を設計する（レンズ選定・ステージ構成・機械的集約・沈殿の意思決定）。「flow.tomlを設計して/書いて」「agents.jsonを作って」「レンズを選んで」「調査フローを設計して」「審議パネルを組んで」と言われた時に使用する。シナリオの新規作成・実行・retract・doctor など CLI 運用は tracefield-operator を使う。
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
3. **多様性は中央集権で殺すな。** 単一統合者は少数意見を溶かす。（「ピア反復は collapse しない」は denoise の内部 finding であって鉄則ではない → §反復）

## レンズ設計（agents.json）

`desc` の書き方・プロンプト技法（desc がどう実プロンプトに入るか、ステージ役割別の効く言い回し、
ADJ の正準ラベル、アンチパターン）は [references/agent-prompts.md](references/agent-prompts.md)。
**哲学・フレームワーク・論理操作・データ役割の paste 可能な desc お手本**は
[references/lens-catalog.md](references/lens-catalog.md)。

**価値序列（高→低）**: 相互に直交する複数の哲学分野（帰結主義⇄義務論⇄現象学⇄系譜学）＞ 構造変更型の論理操作（場合分け）＞ 分析フレームワーク（制約理論・可逆性・リスク）＞ ロール（職能）。

- **直交性が効く**。「哲学」という塊でなく、注目対象が互いに還元不能な分野を混ぜる。対立する哲学レンズ（功利⇄義務）を1〜2枚入れると、ロールだけのパネルが見落とす死角・代替案が表面化する（盲検確証済み）。
- **ロールは冗長**。職能ロール（BE/PM/SRE/FIN）は同じ事実に重点を変えるだけで構造的再framing を出さない。richな desc にしても変わらない。バイインの当事者マッピングが目的なら可、死角照射が目的なら不可。
- **場合分け(CASES)は強い**。決定変数で場合分けし「1つ選ぶ」を「条件マップ」に変える。唯一、選択肢成立の境界条件を出す。
- 各レンズの desc に**死角を一文明記**（例: "死角: 少数者の不公平を総和に埋もれさせる"）。
- **操作系をレンズにしない**: 止揚/MECE/triangulation（合成）、反証/反例/背理法（批判）は agents として置くが**ステージ専用**にし、analysis パネルに混ぜない。

## ステージ設計（flow.toml）

**このスキルの製品は「統治された単発調査」**。監査価値（機械集約・provenance・retract・no-silent-drop・FALSIFY/COUNTER/ADJ）は単発1パスで完結し、多サイクルを必要としない。標準骨格（中央 SYNTH なし）:

```
analysis（直交レンズのパネル） → verify（FALSIFY/COUNTER） → adjudication（per_input: 反証1件=1審判） → [tracefield aggregate で機械集約]
```

これが**正準骨格**。既定では独立した「収集(collect)」ステージは無い —— 入力は `inputs=["path:task.md"]` やファイル/前ステージ参照で供給する。`source_discovery` 等の収集前段は deep_investigation 型の**任意の変種**であって標準ではない。catalog から「それらしい DAG」を組めてしまうが、組んだ変種をこの骨格と混同しないこと。

- **analysis**: `inputs=["path:task.md"]`。レンズ数だけ actor（`mode="fixed"` + `roles=[...]` か `per_agent`）。
- **verify**: `inputs=["stage:analysis"]`。FALSIFY/COUNTER は自前結論を出さず反証だけ。最も決定的な内容を産む。
- **adjudication**: `mode="per_input"` + `roles=["ADJ"]`。verify の各反証エントリが 1 actor にシャードされ、独立 verdict を下す（一枚岩 SYNTH が反証を黙殺するのを構造的に封じる）。ADJ の verdict は必ず正準ラベル **「判定: {結論変更を要する / 条件付きで結論維持 / 却下}」** で書かせる（`tracefield aggregate` がこのラベル先頭で分類）。
- **集約は機械的に**: 最終 SYNTH ステージを置かず、run 後に `tracefield aggregate --store <jsonl>` を呼ぶ。overturn が1件でも→結論変更 / unclassified→indeterminate(要対応・silent drop なし) / それ以外→維持＋条件の和集合。

### 反復（denoise）と沈殿 — 実験機能（既定 off）
> **denoise は製品でなく研究機能。** answer-quality を上げる主張で、equal-compute ベースライン未検証＝単一強モデルに同等 compute で負けうる領域に最も晒される。既定は `cycles=1`／`long_run` off。下記は外部再現のない**内部 finding**。
- 多サイクル精製は `[long_run] cycles=3 cycle_stages=["analysis"]` ＋ `inputs=["path:task.md","stage:analysis"]`（自己/相互参照）。**約3サイクルがスイート**（cycle1粗→cycle2立場ロック→cycle3二次精製、cycle4で飽和）。ピア反復は mode collapse しない（内部 finding・外部未検証）。
- **沈殿した経路依存の立場**を育てるなら、単一 agent＋最小 seed＋自己参照サイクル。既定アトラクタに逆らう種でも保持・自己強化する（確証済み）。

### 問いの扱い（立てる・増やす・差し替える）
問い(task.md)は seed 1回で固定の不変 entry（サイクルをまたいでも再 seed されない）。だが問いは3通りに動かせる:
- **立てる/増やす**: 「問いを立てる前段」は analysis 型の任意ステージ。入力解決は `path:` と `stage:` を同格に扱う（どちらも Active entry の meta フィルタ違い）ので、前段が吐いた問い(`EntryType::Question`)を後続の `inputs=["stage:前段"]` で渡せる。`source_discovery` 系の変種がこれ。
- **差し替える**: 思考途中で問いそのものが変わったら `tracefield supersede`（下記）。seed の置換でなく「旧問いを退場させ新問いへ再アンカー」を一級イベントにする。

### 検証可能性（retract / supersede）
- provenance が要る/後で覆す可能性があるなら `--persist <jsonl>`。**retract と supersede は同一プリミティブ**（id＋citation 閉包を終端ステータスにマークし、原因を指す meta を打つ）。差は「撤回(前提が誤り)」か「差し替え(より良い後継へ)」か。
- **retract（前提が誤り）**: load-bearing 前提を `tracefield retract` するとクロージャ伝播で依存結論が `Retracted` にマークされる（伝播は決定論、meta `retracted_by`）。
- **supersede（問い/主張が変わった）**: `tracefield supersede --entry <旧> --with <新>` で旧 entry＋下流閉包を `Superseded`（`superseded_by=<新>`）にし、後継 entry は Active に残す（後継が旧を cite していても埋もれない）。古い問いに答えた結論群が閉包ごと退場し、新しい問いの下で再調査できる。
- **再集約は自動でなく手動**: 読み取り経路（入力セレクタ・`tracefield aggregate`・serve）は全て `Active` 限定なので、retract/supersede 後に `aggregate` を再実行すると除外分が落ちて基盤が再計算される。手動なのは設計判断で、黙って再集約すると「結論が変わった」事実が silent recompute に消えるため、閉包を人間に見せる（鉄則の no-silent-drop の裏返し）。

## 設計に効く制約（運用機構は tracefield-operator）
- **モデルは合成の頑健性に効く設計変数**。弱いモデルは大入力で合成が激しく崩れる（レンズ脱落・結論反転）→ 鉄則2「小規模域に留める」を一層厳守。例: `adapter="cli" command="claude" model="claude-sonnet-4-6"`（adapter/model の権威ある設定・mock検証・ビルド済みバイナリ等の運用は operator 参照）。
- `per_input` の価値は**速度でなく隔離**: 各反証エントリを他の反証なしで1 actor に審判させ、一枚岩 SYNTH が反証を黙殺するのを構造的に封じる。入力エントリ数に actor をスケールするが（`roles` 長1なら全 actor が同一 lens 駆動）、実並列度は `max_parallel_actors` 依存で、`=1` なら直列実行でも隔離は成立する。「並列化」でなく「隔離」と理解する。

## アンチパターン（findings 由来）
- 死角照射目的でロールパネルを使う（冗長）。
- 止揚/反証をレンズにする（自前テーゼが無くステージ操作）。
- 一枚岩 LLM SYNTH に多項目を渡して統合させる（規模で脱落・捏造、少数意見を溶かす）。
- フォーマット強制で合成を直そうとする（体裁だけ整え中身は捏造する＝かえって危険）。隔離＋機械集約で直す。

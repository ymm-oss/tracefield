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
`findings-longrun-investigation.md` / `findings-being-sedimentation.md` / `findings-continuity-vs-diffusion.md` /
`findings-bet2-overturn.md`（いつオーケストレーションを呼ぶか＝cued/uncued・仕様を問う）。

コピペ可能なテンプレは [references/patterns.md](references/patterns.md)。

## 鉄則（これだけは外さない）

1. **偏りを持つ「観点」はレンズ、他者の出力に作用する「操作」はステージ。** 止揚(合成)・反証(批判)はレンズにせずステージに置く。
2. **全 LLM 呼び出しを"忠実な小規模文脈域"に留める。** 一枚岩 SYNTH に多レンズ＋反証を渡すと規模で劣化（レンズ脱落・捏造・結論反転、弱モデルほど激しい）。統合は LLM 再合成でなく `tracefield aggregate` の機械的集約で出す。
3. **多様性は中央集権で殺すな。** 単一統合者は少数意見を溶かす。（「ピア反復は collapse しない」は denoise の内部 finding であって鉄則ではない → §反復）

## 設計プロセス（classify → draft → falsify）

スキルを「読む」だけだと、それらしい DAG にパターンマッチして微妙な知見（cued/uncued・中央合成禁止・surface-don't-resolve）を飛ばす。**flow を起こす時はこの3段を回す。** 各分岐の*根拠*は findings 本文の該当 §（ここは選別と検査の入口で、findings の複製ではない）。**分岐は排他でない**——複数が同時に効き、骨格の中で*重ね合わせる*（発散段は diffuse、深掘り段は narrow を*織る*のが勝ち筋＝§narrow-answer・fsl-direction）。どの分岐にも当てはまらなければ「新しい harness を組んで falsify を通す」も可。

### 1. classify（どの知見が効くか。人間が居れば訊き、自律実行なら task から自答する）
- **成果物の形は？** 単一の裁定済み結論 / 共存する立場のマップ / 拡散的な発見。→ 結論＝正準骨格(下記) / マップ＝§surface-don't-resolve / 拡散＝§narrow-answer・交互織り。
- **オーケストレーションは元が取れるか？** 効くのは複雑さでなく **priors からの距離＝新規性**。危険次元が*仕様もモデル priors も*沈黙する盲点（uncued かつ非定番）でのみ隔離直交レンズが固有 edge を出す——しかも**既定 critique では uncued でも単一同様に空振る**（n=1, bet2）。*硬化 critique*（黙って犠牲にする軸を名指させ標的 refutes 必須）とセットで初めて edge 化。馴染んだ複雑さ（EC/認証/CRUD＝priors が饒舌）は単一が priors で発見＝単一＋観点チェックリストで足りる。§cued/uncued。
- **答え空間は？（発散の型）** 外的制約でほぼ一意(narrow/決定)か死角照射(diffuse)か。→ narrow＝両立しない立場トーナメント、または**場合分け(CASES→条件マップ)**（選択肢成立の境界条件が要るとき＝それを出す唯一のレンズ・§レンズ設計）／ diffuse＝直交レンズ panel。深掘りは連続パスへ織る。
- **入力は長文・多者か？** → Yes なら per-unit coverage（chunk×`per_input`、1 actor=1 単位）。§surface-don't-resolve。
- **整合/集約が要るか？** → **機械的に**（`aggregate` / 決定論cluster / `shared_inputs`）。**単一 LLM に N→少数の reduce をさせない**（開放集合で再収束し少数 drop）。
- **接地は何が要るか？** 読み取り主張の出典照合＝`grounded`／組み上がった成果物の外部裁定(fslc・test)＝`[stages.*.command]` 接地プローブ（assemble 後段・grounded と直交＝併用）／来歴・撤回＝`--persist`＋retract/supersede。

### 2. draft
分類に対応する骨格を [references/patterns.md](references/patterns.md) から起こす。既定は正準骨格 `analysis(直交レンズ)→verify(FALSIFY)→adjudication(per_input)→[tracefield aggregate]`。novel な骨格も可（falsify を通れば）。

### 3. falsify（draft を**鉄則違反**に照らして反証。違反は即修正。checklist は「正準骨格への適合」でなく「鉄則違反の検出」＝作り方に依らず効く）
- [ ] **最終統合/集約**に count=1 LLM が多入力を畳む段は無いか → 機械集約 or surface に置換（鉄則2）。※`select`→`initiatives` 連続深掘り（分岐の*深化*）と govern-the-composer の grounded composer（G/V/R 付き）は*合意への reduce でない*＝対象外。
- [ ] **N→少数 への reduce（整合/グルーピング/合意）を単一 LLM** にさせていないか → 構造 no-drop（`shared_inputs`/決定論cluster。無落とし実測は n=1）（§surface-don't-resolve）
- [ ] analysis が **role-only panel** か（uncued の死角照射で）→ 直交哲学レンズを混ぜる（§レンズ設計）
- [ ] uncued を狙うのに **critique が既定（軸を名指さない）** のままか → 硬化 critique（§cued/uncued）
- [ ] **止揚/反証をレンズに**混ぜていないか → ステージ専用（鉄則1）
- [ ] verify/adjudication が **同一モデルの裁量 refuter** か → `per_input` 網羅 or 異種organ or 2極debate（§同一モデル選択バイアス）
- [ ] cued・定番（priors が饒舌）なのに **オーケストレーションを盛って**いないか → 単一＋チェックリスト（§cued/uncued）
- [ ] レンズ desc に **タスク固有の正解を列挙**していないか（カンニング）→ 汎用の角度のみ
- [ ] 外部裁定可能な成果物(fslc/test)があるのに **probe を置かず** LLM の「反証された*と思う*」止まりか → command 接地プローブ（§接地プローブ）
- [ ] denoise/long_run を **equal-compute 検証なしで answer-quality 前提**に使っていないか → 既定 off（§反復）
- [ ] 当事者/対立を **`entry.author`(=actor役割) で数えて**いないか → `meta.speaker` 等の field（§surface-don't-resolve）

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

### surface-don't-resolve（対立を*解決せず*提示する終端・findings-surface-dont-resolve, n=1）
製品が「単一の裁定済み結論」でなく**共存する複数の立場のマップ**（定例MTG/多ステークホルダ状態・係争中の事象）のとき。骨格: per-unit 抽出（chunk×`per_input`＝coverage）→ matter 集合を*閉じる*（codex 提案 → **異種 claude が欠落/恣意 merge を反証して足し戻す debate**）→ **`shared_inputs` で no-drop ラベル付け**（`per_input` で stance を1件ずつ shard＋確定 matter 一覧を全 actor に共有＝物理的に collapse 不能）→ `contested_map` artifact が **distinct `meta.speaker` ≥2** で機械的に CONTESTED 判定。
- **整合に単一 LLM を使うな**: 全 stance を1文脈で再ラベルさせると closed-set 指示・「落とすな/件数一致」明記でも 16→3 に collapse（実証3回）＝開放集合の単一 NORM 再収束（§denoise・findings-diffusion-thinking）。**no-drop は構造（`shared_inputs`）でしか保証できない**。
- **当事者は `entry.author`（＝actor 役割で全 stance 同一）でなく `meta.speaker`** で数える。抽出段が `meta.speaker` を立てる。
- 実測 n=1(TC39 公開議事録): 18→18 無落とし、native 実装等の実対立が CONTESTED 化。係数・頑健性は要再現。P1(対立抽出)の検証であって P2(agenda 条件付き先読み)は別。
- **この骨格は `tracefield new --profile meeting-support`（または `tracefield meeting <dir>`）で雛形が出る**（stances→matter propose/challenge→no-drop label→foresight→Marp deck）。長文議事録は `[flow] input_chunk_paragraphs = N` が seed 時に N 段落単位で chunk 化し `per_input` が網羅抽出（手分割不要・各 chunk は distinct path で resume 安全）。private(agenda) は chunk されず foresight に全体が届く。異種 debate は既定 codex に `[organs.claude]` を足し `matter_challenge.organ` を claude へ。

### 同一モデルの verify/adjudication は選択バイアスを孕む（debate で是正・findings-bet2-overturn）
verify/adjudication が **analysis と同じモデル**だと、生成器の prior を共有した審判になり、**裁量 refuter（`fixed` count で agent が攻撃対象を選ぶ）はモデルの attractor に*同調する*主張を見逃し、*外れる*主張だけを攻撃する**＝収束を捏造する（実測: 11主張中、モデルの好む帰責枠7件は一度も攻撃されず無傷生存、外れたコスト枠4件だけが覆った）。**「生き残った」は反証を生き延びたのでなく*選ばれなかった*だけ。** 是正（強→弱）:
1. **網羅を機械保証**: verify を `mode="per_input"`（`inputs=["entry_type:decision"]`）で **1主張=1反証**に強制し、見逃す裁量を消す。
2. **2極ディベート（patterns.md「7.」）**: 対立する2極（例 帰責派⇄俊敏派）に互いの主張を攻撃させる。各々が相手の本命を潰す*動機*を持つので攻撃が motivated かつ対称。**反 halo 審判**（枠組・聞こえの良さで手心を加えるな／反証不能=無内容も覆りとせよ）と併用。実測: 帰責枠も普通に覆れた（元実験と正反対）＝選択バイアスが結論を作っていた。
3. **真の対照は異種モデル**: stage ごと `organ` を変え analysis と verify/adjudication を別モデルに。同一モデルでは 1–2 が*選択バイアス*を消すが*深層の共有 prior*は残る（討論者も審判も同モデルなら片極の論が弱くなる残存。ただし覆り数の非対称で**可視・測定可能**になる）。
> 反 halo＋動機づけ討論は*ほぼ全主張を覆す*傾向（どの強い主張にも境界条件がある）＝過懐疑の歪み。信号は「勝者」でなく「両極とも境界限定→条件分岐の綜合」。

**同じ選択バイアスは*組織化段*にも再発する（アイデア出し拡散・patterns.md「8.」）**: verify/adjudication だけでなく、束ねる**単一 LLM 段（NORM 圧縮器／SYNTH 統合器）**も発散在庫を prior（定番）へ再収束させ新領域を黙って落とす。是正＝**決定論*無落とし*クラスタ**で単一圧縮器を撤去＋**最終選別もディベート＋機械集約**で単一 SYNTH を撤去。**MAGI 型3体多数決は逆効果**（同一モデルの多数決は prior を「合意」に偽装し少数を黙殺＝実測9票すべて定番・新領域0＝Condorcet 独立性違反）。集約原理＝**可謬性（1反証が N 合意を破る）＞多数決（合意）**。多数決が正当なのは異種 substrate × 独立誤り × 故障耐性（TMR）の別レジームのみ。

### narrow-answer と拡散→連続の交互織り（findings-continuity-vs-diffusion）
答えの空間が狭い問い（外的制約が答えをほぼ一意に縛る戦略**決定**）では、直交レンズのパネルは**単一強モデルに answer-quality で並ばれる**（レンズが収束し多様性の保険が空振る）。死角照射は直交レンズ、narrow-answer の決定問題は**両立しない立場コミットメント**（立場トーナメント）を使い分ける —— コミットを強制すると再収束を防ぎ overturn を生む。
- **設計軸は「単一 vs マルチ」でなく「連続性 vs 拡散」。** 単一＝連続性（1文脈で累積・深い／早すぎる整合化で分岐を見逃す）、パネル＝拡散（隔離文脈に散らし網羅／累積的深さを失う）。
- **勝ち筋は「拡散→連続の交互織り」。** 発散（立場トーナメント＋verify＋per_input 審判）で分岐・死角・overturn を出し、**選ばれた分岐を専用の連続深掘りパスに渡す**と単一1パスを盲検で上回る。
- **勝因は観点でなく文脈の隔離。** 同じレンズの prompt を1文脈に詰めると素の単一より**悪化**する（発散・批判・合成が予算を奪い合い de-risk が最初に崩れる）。価値は (a) 各立場を独立文脈で発展 (b) 各反証を per_input で独立審判 (c) 深い合成を別パスに分離 という構造的隔離で、prompt 移植では再現しない（鉄則2を強モデルで実証）。
- **連続性パスは一級ステージにする**: 発散→`select`（`count=1` で firehose を勝ち方向＋生き残り条件の簡潔ブリーフに蒸留）→`initiatives`（**専用 organ**・大 `max_tokens`・`count=1`・「方向は再議論せず深掘り」desc）。発散と**同一文脈に畳まない**のが要。フル実例 `scenarios/fsl-direction/flow.toml`（framing で問いを立て→directions で発散→…→select→連続深掘り）。
- **narrow-answer の product** は「完全な答え」でなく (a) overturn/死角の発見 (b) 連続性パス用の鋭いブリーフ著者 (c) 監査。深さは連続性パスへ委譲。代替不能な非対称は単一が独力で出せない**稀な構造修正**（例: 安全性/承認の*順序*）に局在し、ゲート密度の差は指示で埋まる。
- **ゲート接地フィルタ（実験・任意）**: 生成された定量決定ゲートを独立 actor が[接地]/[暫定明示]/[未検証-自信過剰]に分類し、false precision を根拠導出 or 反証プローブ化に強制変換する段。再監査で「要検証と書くだけ」の relabeling theater を弾く（実証で未検証 8→1）。

### いつオーケストレーションを呼ぶか（cued/uncued・findings-bet2-overturn）
多エージェントの answer-quality edge は狭い。**呼ぶ判断は「対象が*要件に書かれていない*高ステークス次元を孕むか」**:
- **cued（危険が要件/仕様に明示）→ instructable**: 単一強モデル＋観点チェックリストで届く。オーケストレーションは元を取らない。
- **uncued（次元が潜在＝要件の*書き落とし*）→ 固有 edge**: 単一はもっともらしい整合解で素通りし、強制された直交レンズだけが潜在次元を発見する（実証: 容量衝突・append-only を HARM/INVERT が発見、非誘導の単一は見逃す）。← §narrow-answer の「稀な構造修正」を cued/uncued で精密化したもの。
- **問う対象は*開いたもの*（仕様・要件）にせよ。** テスト等*閉じた下流派生物*を問うのは「ずらす（摂動）」で新次元を生まない（仕様が全正解を規定済＝閉。レンズを当てても発見ゼロ）。**仕様/要件**を哲学レンズ（QANSWER/PROBLEMATIZE/INVERT/HARM/ASCEND）で問うと書き落とし（エラー契約・全順序性・不可逆性・監査）が開く＝**要件の不完全性の発見（行き先①でバグが生まれる場所）**。
- **edge の三条件（揃って初めて隔離が cramming に勝つ）**: (1)開いた対象 (2)哲学的問い（摂動でない） (3)隔離（深い次元は1文脈で自明クラスタに潰れる＝鉄則2/arm-W）。浅い/閉じた課題では「同観点を1文脈に渡した単一」≈オーケストレーションで隔離は無効。
- **レンズは汎用に保て（答えを書くな）**: レンズ desc にタスク固有の正解ケースを列挙すると「カンニング」で edge を捏造する。汎用の*方法/角度*だけ書き具体はモデルに導かせる。比較するなら**単一にも同観点を渡した版で対称に**測る（さもなくば「どちらに答えを教えたか」を測る）。
- **効くのは複雑さでなく*新規性*（priors からの距離）**: 馴染みのある複雑(EC checkout/認証/CRUD)は有名な失敗様式を強モデル単一が priors で全発見＝edge ゼロ。**複雑*かつ*新規**(独自ルール=priors が薄い)で、単一の整合的1パスが素通りする**二次の盲点**(規則間の*適用順序*・*迂回*・*gaming*・全順序公理のような性質)を隔離レンズが拾う＝edge 出現。3ドメイン実証: checkout=ゼロ / semver全順序=薄い / approval(重み付き多者承認)=出現。
- **作り方（具体レシピ）**: 「仕様を問う」型は **patterns.md「6. 仕様を問う」** ＋ lens-catalog「仕様インタロゲーション用レンズ」(QANSWER/PROBLEMATIZE/INVERT/HARM/ASCEND)。実例 `scenarios/spec-probe-{semver,checkout,approval}`。価値検証は単一ベースライン(観点なし／同観点1文脈)と並べ O だけが拾う二次盲点を数える。
- **正直な射程（n=1/codex）**: frontier 相手では edge は*増分*（単一も一次交互作用は拾う／O が二次を数個追加）。各ドメイン n=1＝係数は要再現、方向は3ドメインで一貫。
- **弱/中位ローカルモデルの使いどころ（行き先②・実測）**: 効くのはモデル強度でなく*構造*なので、中位ローカル(qwen27b)を隔離レンズに載せれば二次盲点(適用順序)は単発でも届く。最 subtle な攻撃/gaming は**反復ループ(哲学⇄検討×3, patterns.md「6.」の変種)**で到達＝frontier 単発 O と同等以上。**frontier 不要、中位ローカル×隔離×反復**で深い発見が回る（frontier は最後の鋭さ・再接地だけ）。集約は機械的に（弱 SELECT は稀 signal を落とす）。弱モデルの使いどころは*単発の賢さ*でなく*反復の実行器官*。

### 反復（denoise）と沈殿
denoise（`[long_run]` 自己参照サイクル）には検証状態の異なる2用途が同居する。**用途で記述を分ける**：

**沈殿（正式機能・確証済み）** — 単一 agent＋最小 seed＋自己参照サイクルで**経路依存の立場を育てる**。既定アトラクタに逆らう種でも保持・自己強化する。これは「機構として何が起きるか」の主張（自己参照は種を保持する）で answer-quality の優位主張を含まないため正式に使える。

**多サイクル answer-quality（実験・既定 off）**
> **この用途は製品でなく研究機能。** 「3サイクル精製で答えの質が上がる」は answer-quality の主張で、equal-compute ベースライン未検証＝単一強モデルに同等 compute で負けうる領域に最も晒される。既定は `cycles=1`／`long_run` off。下記は外部再現のない**内部 finding**。**昇格条件**＝equal-compute baseline（同 token budget の単一強モデル1パス）に盲検で負けないこと＋別題材2/別モデル1で方向再現（現状 n=1 を脱する）。
- 多サイクル精製は `[long_run] cycles=3 cycle_stages=["analysis"]` ＋ `inputs=["path:task.md","stage:analysis"]`（自己/相互参照）。**約3サイクルがスイート**（cycle1粗→cycle2立場ロック→cycle3二次精製、cycle4で飽和）。ピア反復は mode collapse しない（内部 finding・外部未検証）。

### 問いの扱い（立てる・増やす・差し替える）
問い(task.md)は seed 1回で固定の不変 entry（サイクルをまたいでも再 seed されない）。だが問いは3通りに動かせる:
- **立てる/増やす**: 「問いを立てる前段」は analysis 型の任意ステージ。入力解決は `path:` と `stage:` を同格に扱う（どちらも Active entry の meta フィルタ違い）ので、前段が吐いた問い(`EntryType::Question`)を後続の `inputs=["stage:前段"]` で渡せる。`source_discovery` 系の変種がこれ。実例 `scenarios/fsl-direction` の `framing` ステージ（証拠に接地して真の問いを起こす）。
- **差し替える**: 思考途中で問いそのものが変わったら `tracefield supersede`（下記）。seed の置換でなく「旧問いを退場させ新問いへ再アンカー」を一級イベントにする。

### 検証可能性（retract / supersede）
- provenance が要る/後で覆す可能性があるなら `--persist <jsonl>`。**retract と supersede は同一プリミティブ**（id＋citation 閉包を終端ステータスにマークし、原因を指す meta を打つ）。差は「撤回(前提が誤り)」か「差し替え(より良い後継へ)」か。
- **retract（前提が誤り）**: load-bearing 前提を `tracefield retract` するとクロージャ伝播で依存結論が `Retracted` にマークされる（伝播は決定論、meta `retracted_by`）。
- **supersede（問い/主張が変わった）**: `tracefield supersede --entry <旧> --with <新>` で旧 entry＋下流閉包を `Superseded`（`superseded_by=<新>`）にし、後継 entry は Active に残す（後継が旧を cite していても埋もれない）。古い問いに答えた結論群が閉包ごと退場し、新しい問いの下で再調査できる。
- **再集約は自動でなく手動**: 読み取り経路（入力セレクタ・`tracefield aggregate`・serve）は全て `Active` 限定なので、retract/supersede 後に `aggregate` を再実行すると除外分が落ちて基盤が再計算される。手動なのは設計判断で、黙って再集約すると「結論が変わった」事実が silent recompute に消えるため、閉包を人間に見せる（鉄則の no-silent-drop の裏返し）。

### 接地ゲート（grounded flag・読み取りハルシネーション抑制・findings-grounded-reading）
レンズ（解釈）が**読み取った主張を出典に逐語照合**する per-claim ゲート。`[stages.<id>] grounded = true` で、その段の各主張に `meta.evidence_quote`（出典の逐語部分文字列8〜30語）を要求し、**引用 store エントリ本文 ∪ `meta.source_path`(+`source_line`) の実ファイル**に機械照合する（外れたら `evidence_quote_not_found`＋`needs_review`、per-claim・retract 閉包内・no-silent-drop）。LLM 不使用の決定論照合＝再接地テーゼ（citation-precision を 0.40→1.00、H1c で審判の覆し決定性を律速）をエンジン側で実装。
- **効き所**: コード/文書の**読み取り段**（analysis / evidence / spec_draft / verify）の主張捏造を機械検出。`relies_on` の真偽を初めて機械検証する。**文書**は store チャンク（in-store 照合）、**コード**は disk 上ファイル（actor が `meta.source_path`/`source_line` を申告し on-disk 照合）。
- **接地プローブ（下記）との別**: ゲートは**主張単位の忠実性**（引用行が主張を支持するか）、プローブは**組み上がった成果物の整合性/外部裁定**（fslc/cargo test）。両者は直交＝併用する（fsl-codespec は verify を grounded、assemble 後段に fslc_gate プローブ）。
- **粒度の注意**: 照合は **entry 単位**（1エントリ＝1 evidence_quote）。複合エントリ（領域 digest・多主張 fragment）は anchor 照合（丸ごと捏造の検出）に留まる ── per-claim full 接地は**反証/事実が atomic な段**（verify 等）で成立。digest 段は grounded にせず下流で再接地する。
- レンズは grounded にしてよい。**審判/止揚の verdict 本文**は引用の逐語写しでないので grounded 対象外だが、**composer（synthesis/施策化）の*事実前提*は接地できる**（下記 govern the composer）。`source_`/`web`/`data` を id/organ/role に含む段は従来通り自動で grounded（明示 flag 推奨・脆い名前依存を脱する）。

### govern the composer（生成側ハルシネーション抑制・findings-grounded-generation）
読み取り（抽出）でなく**生成**（設計/施策/統合＝答えが一意でない）で効かせる版。生成のハルシネーション＝*自由な賭け(commitment)*の中に紛れた**偽の事実前提**。直すべきは賭けでなく前提＝**composer（最終統合・施策化ステージ）を起草者と同じ grounded→verify→adjudicate→retract の規律に入れる**。composer は「合成して*発明*でき、かつ verify の後段にあるため無検査で成果物化する」という最悪面なので狙う。
- **G（接地）**: 最終 composer 段を `grounded = true`。各生成主張の*事実前提*を `meta.evidence_quote`＋`source_path:source_line` で一次資料の実ファイルに照合（読み取りの on-disk ゲートを*そのまま*転用＝同じ機構を別ステージに当てるだけ）。**commitment には evidence_quote を要求せず事実前提にのみ要求**（自由な賭けと事実を物理分離）。composer は主張を*個別エントリ*で出す（後段が主張単位で攻撃/retract できるよう atomic 化。narrative は別途 synthesis で anchor 照合）。
- **V（再反証）**: composer の**新規**主張（最初の verify が見ていない）を独立赤チームで再攻撃する verify→adjudication 段を**後段に増設**（`retract_overturned`）。**G が偽の事実を、V が偽の推論を**殺す（直交。findings-lens-type/diffusion §5 の「鋭い中央合成は未検証の推論的飛躍を運ぶ」を composer に対しても殺す）。
- **R**: 一次 adjudication にも `retract_overturned`。覆された前提は status で消え、composer は生存集合だけを見る（「生存」を指示順守でなく status で機械化）。
- **continuity との両立**: composer が連続深掘りパスでも、on-disk 照合は必要ファイルだけ read-only で開くので文脈を膨らませない（arm W＝全部入り単一文脈＝最低スコア、を再現しない）。
- 実例: `scenarios/fsl-direction`（`initiatives` を grounded＋`verify_init`/`adjudicate_init` 増設＋一次 adjudication に retract_overturned）。fsl-codespec（抽出）の双子＝同じ FSL 題材の生成側。

### 接地プローブ（probe＝決定論コマンドステージ・findings-command-probe）
レンズ（解釈）の対極の**センサ（計測）**。`[stages.<id>.command]` ＋ `[actors] mode="none"` で外部コマンドを1回走らせ stdout を1エントリに畳む（設定は operator の flow-spec）。LLM を介さない＝**confab 原理ゼロの最も忠実な器官**（鉄則2の極限点）で、決定論・exit/JSON・provenance 化が `aggregate` の機械集約哲学と同型。
- 効き所は **verify/adjudication の接地**: 「LLM が反証されたと*思う*」を「`fslc`/`rg`/`cargo test` が事実として反証」に替える。BMC 反例は LLM が握り潰せない究極の FALSIFY。
- 選択エントリを引用するので **retract 閉包に入る**（誤フラグのコマンドは retract で閉包ごと落ちる）。**非ゼロ終了は所見**として記録（spawn 失敗・timeout のみ run を止める）。
- `{input}` で上流エントリを渡せるが、**LLM 散文を argv に文字列補間しない**（注入・脆い）。内容は一時ファイル／`< {input}` 経由。fence 抽出など道具固有の整形は**コマンド文字列＝データ側**に置き、engine は計測に留める。
- **粒度の注意**: `fslc` 等の全体検査ツールは*組み上がった成果物*にしか効かない → assemble の後段に置く。断片段（verify 等）に挿せると誤解しない。repair は可視の再実行に留める（自動フィードバックは鉄則3の silent recompute に触れる）。
- **実測（findings-command-probe）**: fsl-codespec の fslc_gate を実 codex＋実 fslc で検証。判定は closure に乗り、基盤 overturn で stale な fslc 判定が自動退場する（不変条件②）。一方 fslc `verified` は user invariant が無いと型境界のみの**自明 green**になりうる ── ゲートの "no user invariants" 警告がその vacuous green を露出する（`verified` は必要条件であって十分条件でない）。

## 設計に効く制約（運用機構は tracefield-operator）
- **モデルは合成の頑健性に効く設計変数**。弱いモデルは大入力で合成が激しく崩れる（レンズ脱落・結論反転）→ 鉄則2「小規模域に留める」を一層厳守。例: `adapter="cli" command="claude" model="claude-sonnet-4-6"`（adapter/model の権威ある設定・mock検証・ビルド済みバイナリ等の運用は operator 参照）。
- `per_input` の価値は**速度でなく隔離**: 各反証エントリを他の反証なしで1 actor に審判させ、一枚岩 SYNTH が反証を黙殺するのを構造的に封じる。入力エントリ数に actor をスケールするが（`roles` 長1なら全 actor が同一 lens 駆動）、実並列度は `max_parallel_actors` 依存で、`=1` なら直列実行でも隔離は成立する。「並列化」でなく「隔離」と理解する。

## アンチパターン（findings 由来）
- 死角照射目的でロールパネルを使う（冗長）。
- 止揚/反証をレンズにする（自前テーゼが無くステージ操作）。
- 一枚岩 LLM SYNTH に多項目を渡して統合させる（規模で脱落・捏造、少数意見を溶かす）。
- フォーマット強制で合成を直そうとする（体裁だけ整え中身は捏造する＝かえって危険）。隔離＋機械集約で直す。

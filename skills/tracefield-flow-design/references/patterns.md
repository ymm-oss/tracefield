# Flow Patterns（コピペ可能）

organ は例として `adapter="cli" command="claude" model="claude-sonnet-4-6"` を使う（adapter/model の
権威ある設定・mock 検証・実行手順は tracefield-operator）。実例は `scenarios/lens-*`。

## 共通: organ 定義

```toml
[organs.reasoning]
adapter = "cli"
command = "claude"
model = "claude-sonnet-4-6"
max_tokens = 1500
timeout_seconds = 600
```

## 1. 審議パネル（直交レンズ、単発）

死角照射が目的。哲学2＋枠組2＋場合分け1 の直交構成を推奨。

`agents.json`（各 desc に死角を明記）:
```json
{"agents":[
  {"id":"UTIL","domain":"utilitarianism","desc":"功利主義。全関係者の効用の総和を最大化。死角: 少数者の不公平を埋もれさせる。"},
  {"id":"DEONT","domain":"deontology","desc":"義務論。結果でなく義務・規約・約束に従う。死角: 義務衝突の優先順位を軽視。"},
  {"id":"TOC","domain":"theory-of-constraints","desc":"制約理論。律速する唯一の制約を特定し他を従属。死角: 複数制約を単純化。"},
  {"id":"REVERS","domain":"reversibility","desc":"可逆性・オプション価値。一方通行か両開きドアかで分類。死角: 先延ばしコストを軽視。"},
  {"id":"CASES","domain":"case-analysis","desc":"場合分けのみ。決定変数で場合分けし各場合の妥当解を網羅。死角: 確率評価はしない。"}
]}
```

`flow.toml`:
```toml
[flow]
profile = "panel"
policy = "fixed"
[actor_scaling]
default_mode = "fixed"
max_total_actors = 5
[stages.analysis]
organ = "reasoning"
inputs = ["path:task.md"]
outputs = ["observation", "decision"]
[stages.analysis.actors]
mode = "fixed"
count = 5
roles = ["UTIL", "DEONT", "TOC", "REVERS", "CASES"]
```

## 2. 統治された調査（analysis → verify → adjudication → 機械集約）

中央 SYNTH を置かない。反証ごと独立審判 → run 後に `tracefield aggregate`。

`agents.json` に上記レンズ＋以下を追加:
```json
{"id":"FALSIFY","domain":"falsification","desc":"反証操作。各推奨の反証条件と未検証前提を暴く。自前結論は出さない。"},
{"id":"COUNTER","domain":"counterexample","desc":"反例探索。各推奨が破綻するケースと見落とし当事者を提示。自前結論は出さない。"},
{"id":"ADJ","domain":"refutation-adjudication","desc":"反証審判。与えられた1件の反証だけを精査し暫定合意を覆すか判定。判定は必ず {結論変更を要する / 条件付きで結論維持(条件を明記) / 却下(理由を明記)} の3択。冒頭に対象反証のentry idを明記。矮小化・すり替え・反転は禁止。"}
```

`flow.toml`:
```toml
[stages.verify]
organ = "reasoning"
inputs = ["stage:analysis"]
outputs = ["observation", "question"]
[stages.verify.actors]
mode = "fixed"
count = 2
roles = ["FALSIFY", "COUNTER"]

[stages.adjudication]
organ = "reasoning"
inputs = ["stage:verify"]
outputs = ["observation", "decision"]
[stages.adjudication.actors]
mode = "per_input"          # 反証エントリ数に actor をスケール
roles = ["ADJ"]            # 長1 → 全 actor が ADJ 駆動
```

run 後:
```sh
tracefield run --scenario-dir scenarios/<name> --persist runs/<name>.jsonl
tracefield aggregate --store runs/<name>.jsonl   # overturn→changed / unclassified→indeterminate / 他→maintained+条件
```

## 3. 長時間調査（3サイクル denoise ＋ verify ＋ adjudication ＋ 方法論注入）

`[long_run]` で analysis を反復精製。findings を方法論 skill として注入（生全文を渡すと文脈肥大で自滅するため蒸留して skill 化、agents の `skills` に付与）。

```toml
[long_run]
enabled = true
cycles = 3
cycle_stages = ["analysis"]

[stages.analysis]
organ = "reasoning"
inputs = ["path:task.md", "stage:analysis"]   # 自己/相互参照で denoise
outputs = ["observation", "question", "decision"]
[stages.analysis.actors]
mode = "fixed"
count = 5
roles = ["UTIL", "DEONT", "TOC", "REVERS", "CASES"]
# verify / adjudication ステージは上記2と同じ（cycle_stages に入れない＝最後に1回）
```

方法論 skill は `scenarios/<name>/skills/investigation-method/SKILL.md` に置き、各レンズの
`"skills":["investigation-method"]` で付与（auto-cite で provenance に残る）。
内容例: 多数派に同調しない／死角を申告する／収束を疑う(支配的妥協案の罠)／各サイクルで新情報を足す／前提を名指しする。

## 4. 沈殿（経路依存の立場を育てる）

単一 agent ＋最小 seed ＋自己参照サイクル。既定アトラクタに逆らう種でも保持・自己強化する。

`agents.json`:
```json
{"agents":[{"id":"SELF","domain":"self","desc":"自分の過去の発言だけを足場に立場を一段深める主体。最初の足がかりとして『<seed>』の側から考え始めよ。以後は他者でなく自分が述べたことを継承し発展させること。"}]}
```

`flow.toml`:
```toml
[long_run]
enabled = true
cycles = 3
cycle_stages = ["analysis"]
[stages.analysis]
organ = "reasoning"
inputs = ["path:task.md", "stage:analysis"]   # 自分の過去のみ継承
outputs = ["stance"]
[stages.analysis.actors]
mode = "fixed"
count = 1
roles = ["SELF"]
```

## 5. 拡散→連続の交互織り（narrow-answer 決定問題）

死角照射でなく**答えの空間が狭い戦略決定**向け（findings-continuity-vs-diffusion）。両立しない立場で発散→隔離審判→**蒸留→専用の連続深掘りパス**。フル実例は `scenarios/fsl-direction/`（問いを立てる `framing` 前段つき）。要点だけ:

```toml
# 連続深掘り専用 organ（大予算）
[organs.deep]
adapter = "codex-app-server"
max_tokens = 6000

# 発散: 両立しない戦略方向（立場トーナメント＝再収束を防ぎ overturn を生む）
[stages.directions]
organ = "reasoning"
inputs = ["path:task.md"]
outputs = ["decision"]
[stages.directions.actors]
mode = "fixed"
count = 6
roles = ["CORE", "ADJACENT", "GENEALOGY", "INVERT", "PULL", "ANALOGY"]
# → judge(per_input) → critique(FALSIFY/COUNTER) → adjudication(per_input ADJ)  ※パターン2と同じ

# 蒸留: firehose を勝ち方向＋生き残り条件の簡潔ブリーフへ畳む
[stages.select]
organ = "reasoning"
inputs = ["stage:directions", "stage:judge", "stage:adjudication"]
outputs = ["synthesis"]
[stages.select.actors]
mode = "fixed"
count = 1
roles = ["SELECT"]

# 連続性パス: 蒸留ブリーフだけを足場に1 actor で深掘り（発散と分離）
[stages.initiatives]
organ = "deep"
inputs = ["stage:select"]
outputs = ["synthesis", "decision"]
[stages.initiatives.actors]
mode = "fixed"
count = 1
roles = ["INITIATIVES"]
```

連続性パスを発散と同一文脈に畳むと劣化する（de-risk が最初に崩れる）。必ず別 organ・別ステージに分離し、`select` で firehose を畳んでから渡す。

## 6. 仕様を問う（spec interrogation — 複雑×新規で*二次*の盲点を発見）

**対象は*仕様/要件*（開いたもの）。テスト等の閉じた下流を問うのは摂動で新次元を生まない。** 効くのは
**複雑*かつ*新規**（priors が薄い独自ルール）なドメイン。馴染み(EC/認証/CRUD)・cued な仕様は単一強モデルで足りる。
発見されるのは単一の整合的1パスが素通りする**二次の盲点**（規則間の*適用順序*・*迂回*・*gaming*・全順序公理のような性質）。
実例: `scenarios/spec-probe-{semver,checkout,approval}`。根拠 `docs/findings-bet2-overturn.md`。

`task.md`: 「`inputs/spec.md` を*問え*: 何を暗黙に前提にし・何を書き落とし・現実で何が壊れるか（特に複数の部分が*相互作用*する箇所）。仕様の再説明はするな」。
`inputs/spec.md`: 対象仕様。`agents.json`: lens-catalog「仕様インタロゲーション用レンズ」の5本。

```toml
[flow]
profile = "spec-interrogation"
policy = "fixed"
[actor_scaling]
default_mode = "fixed"
max_total_actors = 10
max_parallel_actors = 3
[organs.reasoning]
adapter = "codex-app-server"   # 散文の指摘でよい（コード成果物でないので codex で可）
timeout_seconds = 600
[stages.interrogate]
organ = "reasoning"
inputs = ["path:task.md", "kind:input"]
outputs = ["observation", "question"]   # 各レンズが隔離文脈で仕様の沈黙を列挙
[stages.interrogate.actors]
mode = "fixed"
count = 5
roles = ["QANSWER", "PROBLEMATIZE", "INVERT", "HARM", "ASCEND"]
```

5レンズの出力（observation/question）の和集合が発見された盲点。**価値検証するなら**単一ベースライン
（同 task を `count=1`・観点なし、または同5観点を1文脈に渡した版）と並べ、O だけが拾った*二次*盲点を数える。
射程の正直: frontier 相手では edge は増分（単一も一次の交互作用は拾う／O が二次を数個追加）。

**弱/中位ローカルモデル向け＝反復ループ変種（哲学 ⇄ 検討）**: 中位ローカル(例 qwen3.6:27b)を*隔離レンズ構造*に載せれば
二次盲点(規則の適用順序)は単発でも届く（効くのは構造で、モデル強度でない）。だが**最 subtle な攻撃/gaming(ジャミング DoS・
権限横取り・循環 DoS)には反復が要る**。`[long_run] cycles=3 cycle_stages=["interrogate","deepen"]` で
`interrogate`(inputs に `stage:interrogate`＋`stage:deepen` を足し自己＋検討参照) と `deepen`(批評役 DEEPEN=「答えは出さず
*未探索の角度*だけ名指せ: 規則の同時/順序の相互作用・ある規則が別を打ち消す経路・既出の穴の*悪用*」)を交互に回す。
deepen がサイクル間で発見を compound し、中位モデルが frontier 単発 O と同等以上の深さに届く（実例 `scenarios/spec-probe-approval/flow.ollama-loop.toml`）。
**行き先②(ローカル完結)の含意: frontier 不要＝中位ローカル × 隔離レンズ × 反復。frontier は最後の鋭さ・再接地にだけ薄く。**
集約は弱 SELECT が稀 signal を落とすので**機械集約**にし、再接地が要る覆しは強モデル(H1c)。弱モデルの使いどころは*単発の賢さ*でなく*反復の実行器官*。

## 7. 2極ディベート（同一モデル審判の選択バイアス是正）

同じモデルの verify/adjudication が**自分の好む方向の主張を見逃す**選択バイアス（SKILL「同一モデルの…選択バイアス」）を、**対立2極の相互攻撃**で対称化する。立場トーナメント＋per_input 審判の敵対版。根拠 `docs/findings-bet2-overturn.md`。

`agents.json`（対立2極＋反 halo 審判。partisan は「自極の立場＋相手だけ攻撃するモード＋meta.refutes」を書く）:
```json
{"id":"GOV","domain":"governance-partisan","desc":"統治・帰責派。立場: 希少資源は検証可能性・帰責・ドメイン理解。モード1(task.mdのみ): 自極で論点を読み反証可能な主張(decision)を述べる(トートロジー禁止)。モード2(相手VELの主張が来たら): VELの主張だけを全力攻撃し、速度優先が帰責不能・不可逆損害をどう招くかで潰す。1攻撃=observation1件、meta.refutes:[\"eNN\"]で対象id。相手の全主張に漏れなく反論。"}
{"id":"VEL","domain":"velocity-partisan","desc":"俊敏・スループット派。立場: 希少資源は市場投入速度・実験回数・作って捨てる自由。『責任・検証こそ希少』は儀式・官僚主義と疑う。モード1: 自極で主張(decision)。モード2(相手GOVが来たら): GOVの主張だけを全力攻撃し、安いコードと再生成が検証・負債・帰責の意味をどう無効化するか、トートロジーでないかで潰す。1攻撃=observation1件、meta.refutes必須。全主張に反論。"}
{"id":"ADJ_AH","domain":"adjudication-antihalo","desc":"反証審判(反halo)。1反証だけ精査し冒頭に対象id、続けて『判定: {結論変更を要する/条件付きで結論維持(条件明記)/却下(理由明記)}』。枠組や聞こえの良さで手心を加えるな。反証が『反証不能=無内容/測定不能/境界で破れる』を示し正しければ賛同できる結論でも『結論変更』。矮小化・すり替え・反転禁止。"}
```

`flow.toml`:
```toml
[stages.position]                 # 両極が自極で主張
inputs = ["path:task.md"]
outputs = ["decision"]
[stages.position.actors]
mode = "fixed"
count = 2
roles = ["GOV", "VEL"]

[stages.rebut]                    # 相手の全主張を攻撃(cross-rebut), meta.refutes で対象id
inputs = ["stage:position"]
outputs = ["observation"]
[stages.rebut.actors]
mode = "fixed"
count = 2
roles = ["GOV", "VEL"]

[stages.adjudication]             # 衝突1件=1隔離審判(反halo), 結論変更が指す主張を機械retract
inputs = ["stage:rebut"]
outputs = ["decision"]
retract_overturned = true
[stages.adjudication.actors]
mode = "per_input"
roles = ["ADJ_AH"]
```

実例 `scenarios/codegen-econ-reread/flow.codex-debate.toml`。網羅を更に固めるなら rebut を `per_input`＋`inputs=["entry_type:decision"]`（1主張=1反証で見逃す裁量を消す）。**残存限界**: 討論者も審判も同一モデルなら片極の論が弱くなる残存 prior は消えない（覆り数の非対称で可視化）。真の対照は stage 別 `organ` の異種モデル。反 halo＋動機づけ討論は*ほぼ全主張を覆す*過懐疑傾向＝信号は「勝者」でなく「条件分岐の綜合」。

## 8. アイデア出し（拡散）— 発散ループ＋決定論*無落とし*クラスタ＋ディベート組織化

発散的なアイデア生成向け（死角照射でも narrow-answer 決定でもない）。`lens-diffuse-cluster` の scatter→cluster→synthesis を土台に、3つの実測知見を反映。根拠 `docs/findings-bet2-overturn.md`「アイデア出し(拡散)」、実例 `scenarios/qwen-coding-tasks/`。

**(a) 発散は反復ループで定番を破る**: 開放型アイデア出しは単発だと中位モデルが*角度プロンプトを跨いで定番へ収束*する。`[long_run] cycles=3 cycle_stages=["scatter","deepen"]` で scatter（N角度）⇄ deepen（答え＝タスク名を出さず*未踏の領域*だけ名指す批評役）を回すと cycle2-3 が定番の外で具体化する。scatter の `inputs=["path:task.md","stage:scatter","stage:deepen"]` で自己＋未踏角度を累積参照。蓄積文脈が嵩むので**大文脈 organ（codex-app-server）**が要る（qwen の num_ctx=8192 では回らない）。

**(b) 束ねは単一 LLM 圧縮器を使うな → 決定論*無落とし*クラスタ**: 単一の正規化 actor（NORM）は発散在庫を prior（定番）へ再収束させ新領域を*黙って落とす*（実測 48→3）。raw scatter を自命名 `meta.kind` で `flow-cluster` し、**`max_clusters` を distinct kind 数以上**にして `other_sources` に畳まない（落としを*隠す*NORM より、落としを*露出*させ監査可能にする決定論クラスタが上）。

**(c) 最終選別は単一 SYNTH でなく2極ディベート＋機械集約**: 単一統合器は完全在庫を前にしても定番接頭辞へアンカーする。`propose(CONV 定番派 / FRONTIER 固有優位派が在庫から推しタスクを decision)→ rebut(cross-attack, meta.refutes)→ adjudication(per_input 反 halo, retract_overturned)→ run後 aggregate`（＝パターン7の応用）。FRONTIER が新領域を強制投入し、無視→考慮・反証・条件化へ。**MAGI 型3体多数決は使うな**: 同一モデルの多数決は prior を「合意」に偽装し少数を黙殺する（実測9票すべて定番・新領域0＝Condorcet 独立性違反）。集約原理が決め手＝**可謬性（1反証が N 合意を破る）> 多数決（合意）**。**retract の配線**: reconcile は verdict の citations→rebut→`rebut.meta.refutes` で対象を解決する（攻撃を書く CONV/FRONTIER が refutes を持てばよく、審判 verdict 自身の refutes は不要）。reconcile は `meta.refutes` を**配列・スカラ文字列の両方**受ける（agent が両形を出す。tracefield-core 修正済＝旧版は array のみで scalar 形の攻撃が黙って UNACTIONED 化し片極だけ不発の偽非対称を生んでいた）。run 後は `tracefield aggregate`＋`grep overturned-claim run.log` で確認（retract_overturned は overturn verdict を閉包ごと自己 retract するので aggregate は overturn=0 を見せうる）、`UNACTIONED` flag が出たら人手照合。多数決が正当なのは異種 substrate × 独立誤り × 故障耐性（TMR）の別レジームのみ。

実例 `scenarios/qwen-coding-tasks/flow.codex-{loop,debate,magi}.toml`。残: 領域別隔離統合の完全形は `scale_by`（1セレクタでアクタをスケール＋他セレクタを各アクタへ共有文脈として渡す）実装待ち。

## 入力セレクタ早見

- `path:<file>` … task.md 等（meta.path 一致）
- `stage:<id>` … 当該ステージの全 active エントリ（サイクル横断）
- `entry_type:<t>` / `kind:<k>` / `all` … 型・kind・全件

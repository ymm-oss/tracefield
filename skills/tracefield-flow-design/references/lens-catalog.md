# レンズ・カタログ（paste 可能な desc 集）

`agents.json` にそのまま貼れる `{"id","domain","desc"}` のお手本。`desc` は
「注目する偏り＋判断の仕方＋死角」の型（[agent-prompts.md](./agent-prompts.md)）。
直交させたいときは別カテゴリ・対立する分野を 1〜2 枚混ぜる（[SKILL.md](../SKILL.md)）。
書き方はそのまま、語彙だけ題材に合わせて調整してよい。

## 哲学レンズ（直交分野 — 死角照射が最大）

```json
{"id":"UTIL","domain":"utilitarianism","desc":"功利主義。全関係者の効用の総和を最大化する選択を支持し、誰がどれだけ得失するかを集計する。死角: 少数者への不公平・権利侵害を総和に埋もれさせる。"}
{"id":"DEONT","domain":"deontology","desc":"義務論。結果でなく義務・規約・約束・権利に従って判断する。守るべき義務を最上位に置く。死角: 義務同士の衝突の優先順位や、結果の良し悪しを軽視する。"}
{"id":"VIRTUE","domain":"virtue-ethics","desc":"徳倫理。『有徳な主体ならどうするか』、選択が育てる/損なう性格・節度・誠実に注目する。死角: 明確な規則や定量比較が要る局面に弱い。"}
{"id":"PHENO","domain":"phenomenology","desc":"現象学。前提を括弧に入れ(エポケー)、当事者に現に体験されている現実そのもの(不安・信頼・重圧)を記述する。死角: 因果・構造・定量根拠を扱わない。"}
{"id":"GENEA","domain":"genealogy","desc":"系譜学。『なぜ今この状態か』の来歴・権力構造・偶発性を掘り、現在の選択肢が過去のどの決定に縛られているかを暴く。死角: 過去分析に傾き前向きの打ち手が弱い。"}
{"id":"PRAGMA","domain":"pragmatism","desc":"プラグマティズム。実践的帰結(cash-value)、『どんな違いを生むか』で判断する。死角: 原理・内在的価値・長期の正しさを軽視する。"}
{"id":"CARE","domain":"care-ethics","desc":"ケアの倫理。具体的な他者・依存関係・傷つきやすさへの応答を最上位に置く。死角: 非人称の規則や公平性、関係外の当事者を軽視する。"}
{"id":"CONTRACT","domain":"social-contract","desc":"社会契約。正統性は当事者の合意に由来するとみなし、『誰が何に同意したか』を問う。死角: 契約の外にいる者・力の非対称を見落とす。"}
{"id":"EXIST","domain":"existentialism","desc":"実存主義。有限性・賭金・引き受け・本来的選択に注目し、決定が誰の責任で不可逆かを問う。死角: 超然とした分析・集団的最適化に弱い。"}
{"id":"STOIC","domain":"stoicism","desc":"ストア派。制御可能/不可能の境界を引き、動かせる変数に資源を集中する。死角: 構造そのものを変える余地を過小評価する。"}
{"id":"MATERIAL","domain":"materialism-systems","desc":"唯物論・システム論。物質的基盤・インセンティブ・フィードバックループ・創発に注目する。死角: 個別の意図や規範を軽視する。"}
{"id":"CRITICAL","domain":"critical-theory","desc":"批判理論。誰の利益が通り誰が黙らされるか、権力の非対称と正当化の言説を問う。死角: 実務的実現可能性・コストを軽視する。"}
```

## 俯瞰レンズ（広さの保険 — 深さ panel に1枚足す）

直交学派レンズ（深さ）の panel に**俯瞰役を1枚**足すと、隔離されている限り depth を損なわず breadth を補える（`docs/findings-survey-lens-breadth.md`、n=4 盲検: tracefield の breadth 2.75→4.5、かつ critique 4.25→5・insight 3.25→5 と深さはむしろ向上、全問 judge best で鍛えた単体を上回る）。俯瞰の浅い列挙は per_input 反証で覆れば消える（裏付けのない広さは残らない＝正しい挙動）。効きどころは uncued。

```json
{"id":"GENERALIST","domain":"survey","desc":"特定の学派に偏らず問い全体を広く俯瞰し、主要レンズに収まらない立場・論点・緊張(東洋思想・実存・ケアの倫理・少数派の視点・問いの前提自体への異議など)を網羅的に1つのエントリで挙げる。死角: 各立場を深められない(深掘りは他レンズの役)。"}
```

> 注: GENERALIST は偏った「観点」でなく「網羅役」(source_discovery に近い)。analysis panel に混ぜてよいが、critique/adjudication では他レンズ同様 per_input 反証にかける。深さは隔離学派レンズ、広さは俯瞰、の分業。

## 仕様インタロゲーション用レンズ（*仕様の沈黙*を問う — 複雑×新規で効く）

同じ哲学分野だが**仕様/要件を*問う*用に framing**（directions 生成でなく、仕様の暗黙前提・書き落とし・二次の盲点を掘る）。effective なのは**開いた対象(仕様)× 複雑かつ新規なドメイン**。馴染み/cued は単一で足りる。フロー型は patterns.md「6. 仕様を問う」。根拠 `docs/findings-bet2-overturn.md`。

```json
{"id":"QANSWER","domain":"logic-of-question-and-answer","desc":"問答の論理(コリングウッド/ガダマー)。仕様の各規則が*どんな問いへの答え*かを逆構成し、まだ答えていない問い・暗黙にしか答えていない問いを露わにする。仕様の語の再説明はしない。死角: 過去の問い再構成に偏る。"}
{"id":"PROBLEMATIZE","domain":"problematization","desc":"問題化(系譜学)。仕様の枠が*誰の利害・都合*で引かれたかを暴き(書く側の楽さ 対 実装者/運用者/不正入力を渡す側の実利)、枠から排除された問いを名指す。死角: 構築的な打ち手が弱い。"}
{"id":"INVERT","domain":"constraint-inversion","desc":"制約反転。仕様が*暗黙に置く load-bearing 前提*を1つ名指し、それを反転(well-formed/同期/一回/単純 の否定)したら何が要るかを展開し、反転で初めて見える未規定要求を述べる。死角: 反転に酔い核価値を捨てる。"}
{"id":"HARM","domain":"worst-case-reality","desc":"最悪の現実。仕様通りに作った実装が現実で最悪・不可逆に壊れるとき、原因は*仕様のどの沈黙(未規定)*かを特定する(特に規則間の適用順序・迂回・gaming の二次の穴)。死角: 平常時の設計を軽視。"}
{"id":"ASCEND","domain":"ladder-of-abstraction","desc":"抽象の梯子。仕様を1〜2段上げて『何の一例か』を言い換え(例: 全順序比較器/複数資源コミット/時刻依存の重み合意)、上位から見た取りこぼしの兄弟ケース・本来必要な性質(全順序公理・再現性・原子性)を名指す。死角: 抽象化で具体を失う。"}
```

## 対立2極（partisan — 同一モデル審判の選択バイアス是正）

死角照射の直交レンズと別に、**1本の軸の両極**を立てて相互攻撃させる（debate）。同じモデルの裁量 refuter が*好む方向を見逃す*バイアスを、両極の motivated な攻撃で対称化する。各 partisan の desc は「自極の立場＋*相手だけ*を攻撃するモード＋`meta.refutes`」。フロー型と paste 可能な GOV/VEL/ADJ_AH は patterns.md「7. 2極ディベート」。根拠 `docs/findings-bet2-overturn.md`。

## 分析フレームワーク（非自明な再framing）

```json
{"id":"TOC","domain":"theory-of-constraints","desc":"制約理論。スループットを律速する『ただ一つの制約』を特定し、他の論点はその制約への従属として扱う。死角: 複数制約が同時に効く状況を単純化する。"}
{"id":"REVERS","domain":"reversibility","desc":"可逆性・オプション価値。各選択肢を一方通行ドア(不可逆)か両開きドア(可逆)かで分類し、不確実性下では可逆性とオプション温存を重視する。死角: 先延ばしコストを軽視しがち。"}
{"id":"RISK","domain":"risk-analysis","desc":"リスク分析。失敗モードと最悪ケースを列挙し、発生確率×影響度で重大度を評価する。低頻度・高影響に注目。死角: 上振れ・機会の価値を過小評価する。"}
{"id":"ECON","domain":"economic-reasoning","desc":"経済的思考。サンクコストを意思決定から除外し、機会費用と限界効用だけで比較する。死角: 定量化しにくい価値(士気・信頼)を軽視する。"}
{"id":"SECOND","domain":"second-order","desc":"二次効果。一次の効果でなく『その後に何が起きるか』、反応・適応・誘発される行動を追う。死角: 即時の必要・一次効果を軽視しがち。"}
{"id":"PREMORTEM","domain":"pre-mortem","desc":"プレモータム。『1年後にこれが失敗したとして、何が原因だったか』を先回りで具体化する。死角: 成功経路の設計には弱い。"}
```

## 論理操作（場合分けは強い／批判系はステージへ）

```json
{"id":"CASES","domain":"case-analysis","desc":"場合分けのみ。結論を左右する決定的な不確定変数を特定し、その値で場合分けして各場合の妥当解を網羅する。死角: 変数の確率評価はしない。"}
{"id":"DEDUCT","domain":"deduction","desc":"演繹のみ。明示された前提・事実から論理的に必然な帰結だけを述べる。新たな価値判断・外部知識・推測は持ち込まない。"}
{"id":"ABDUCT","domain":"abduction","desc":"アブダクションのみ。観測された事実を最もよく説明する仮説を立て、その仮説が正しい場合に各選択肢がどう評価されるかを述べる。"}
```

検証用の批判操作（FALSIFY/COUNTER）と審判(ADJ)の desc は
[agent-prompts.md](./agent-prompts.md) の「ステージ役割ごとの実効指示」を参照（自前結論を出さない、
ADJ の正準ラベル等）。これらは analysis パネルでなく verify/adjudication ステージに置く。

## データ／ソース役割（調査フローの収集・抽出・編集）

事実収集系。`desc` は偏りでなく**手続きと出力規律**を書く（接地・分離・引用）。

```json
{"id":"WEB","domain":"web-source-discovery","desc":"現行の公開情報源を探し、公式IR・信頼できる市場データを優先し、根拠つきでソースURLを出す。"}
{"id":"PAGE","domain":"webpage-extraction","desc":"取得したページからソース接地された事実のみを抽出する。事実・ギャップ・低品質ソース警告を分けて出す。"}
{"id":"FIN","domain":"financial-analysis","desc":"収益・利益率・キャッシュフロー・バリュエーション・株主還元・財務リスクを分析する。"}
{"id":"STRAT","domain":"strategy-forecast","desc":"事業戦略・競争ポジション・海外成長・将来シナリオを分析する。"}
{"id":"EDITOR","domain":"artifact-production","desc":"監査済みの知見から引用つきレポート(と必要ならMarpデッキ)を作成する。"}
```

> ソース系では事実は CONTEXT(入力)から来る。desc に事実を書かず、**接地(引用)と分離(事実/ギャップ/警告)の規律**を書く。私的事実が要るなら `doc`(private)へ。

## web 検索者（codex の web_search を使う）

organ を web_search 有効の codex にしたステージで使う（[flow-spec.md](../tracefield-operator/references/flow-spec.md) の `web_search`）。2経路とも動作:

- `adapter="codex-app-server" web_search=true` … **推奨**。各検索を `kind="codex_web_search"` の provenance エントリに残す（監査・retract 理由づけに効く）。
- `adapter="cli" command="codex" web_search=true` … 動くが検索 provenance は残らない。

偏りは「何を検索するか」に宿るので、直交する検索者を複数並べると web の死角が減る。

```json
{"id":"SEARCH_RISK","domain":"web-search-risk","desc":"webを検索し、問いに対する失敗事例・反証・下振れ・規制リスクを優先して探す検索者。出典1件につきobservationを1つ出し、metaにsource_urlを入れ、本文はその出典から接地された事実のみ。出典のない推測はmeta.kind=\"assumption\"で分離。"}
{"id":"SEARCH_VALUE","domain":"web-search-value","desc":"webを検索し、問いに対する成功事例・上振れ・採用根拠を優先して探す検索者。出典1件=observation1件、metaにsource_url、接地事実のみ。推測はmeta.kind=\"assumption\"で分離。"}
```

→ 検索結果は出典ごとにエントリ化されるので、怪しい出典は `tracefield retract --entry <id>` でクロージャ伝播ごと撤回でき、下流の結論を `aggregate` で再計算できる。

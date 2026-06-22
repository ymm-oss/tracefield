# findings: Bet 2 — 攻めの edge は *uncued な発見* に局在して実在する（誘導足場の交絡を除去後の訂正版）

> **重要な訂正（2026-06-21、ユーザー指摘により）**: 初版は「K1×3＝攻めの edge は illusory」と結論したが、これは**二重の交絡**による誤りだった:
> (a) 3タスク中2つ（append/ordering）を brief で高ステークス軸を *cue* してしまった＝単一が cue から直接導けた。
> (b) 唯一の uncued タスク（conflict）で、Arm S の足場に「*不可逆な損害を分析せよ／de-risk を先頭に*」と書き、**uncued 軸を発見する手を単一にタダで渡していた**。
> **非誘導ベースライン（`SINGLE_PLAIN`＝論点を出し尽くす＋完全設計だが「不可逆損害分析／de-risk先頭」を渡さず順序も自分で決めさせる＝continuity-vs-diffusion の arm Z/Y2 相当）で再走すると、conflict（uncued）で単一は LEVEL1（衝突を見逃す）に落ち、Arm O は LEVEL2（HARMレンズが発見）＝edge が出現した。**
> 訂正版の結論は本文末「訂正された結論」を参照。以下の exp1-3 本文は初版の記録（cued タスク＋誘導足場の条件）として残す。

> 日付: 2026-06-21。ブリーフ: [`impl-brief-bet2-overturn.md`](./impl-brief-bet2-overturn.md)。
> 問い（賭け2「存在理由を見つける」）: オーケストレーションが単一強モデルに勝つ唯一の非対称
> （[`findings-continuity-vs-diffusion.md`](./findings-continuity-vs-diffusion.md) = *稀な構造修正*）は、植えた構造overturnで再現し、
> 最良scaffold単一が*独力で*出せないか。モデル: codex-app-server（Arm O/S とも・n=1）。
> シナリオ: `scenarios/bet2-overturn-{p,n}`（exp1）・`scenarios/bet2-ordering-{p,n}`（exp2）。synthetic 医療記録。

## 設計（各実験とも最小の意味ある 2×2）

| | class-P（overturnを植えた） | class-N（control: overturn無しが正解） |
|---|---|---|
| **Arm S** | overturnを*見逃す*か | false-overturnを出さないか |
| **Arm O** | overturnを*表面化*するか | 劇場を*製造*しないか |

- **Arm S**: 単段・最良scaffold（論点を出し尽くす／*不可逆な損害*を分析／de-risk先頭＝arm Z/Y2）。
- **Arm O**: directions(両立しない6方向, SHIP=素朴方向のはず) → critique(per_input・`meta.refutes`) →
  adjudication(per_input・`retract_overturned`) → select → initiatives。flow/agents は P/N/exp 横断で同一（題材だけ差し替え）。

## exp1 — content/inclusion 型 overturn（append-only）

植えた overturn: 「記録を上書きして訂正」(素朴) vs 「医療記録は*不変*・訂正は*追記*で原本破棄せず」(LEVEL2)。誘惑的中間解
「編集＋監査ログ」=LEVEL1。brief は訴訟/監査を cue として持つが「不変/追記」の語は無い。

| | class-P | class-N（日付フィルタ） |
|---|---|---|
| Arm S | **LEVEL 2**（"上書き禁止を最優先"・"immutable"・"append-only" を独力で） | クリーンなフィルタ、劇場なし |
| Arm O | **LEVEL 2**（生存方向が append-only、最終も `locked=true`＋Correction追記） | on-task、構造改造の捏造なし |

決定的観測: directions 6レンズ**全て**（素朴方向のはずの SHIP=e6「既存記録を上書きせず correction を追加」含む）が独立に
append-only にコミット＝**覆すべき素朴方向が生き残らず**、overturn 機構は二次的欠陥だけを覆した。

## exp2 — ordering/framing 型 overturn（不可逆な外部送信）

植えた overturn: 退院サマリの外部保険者送信は*不可逆*。素朴な整合的順序「確定→送信→記録」vs 正解「不可逆送信の*前*に
検証/承認ゲート＋確定者と送信者の分離」(LEVEL2)。要素は揃うが*順序*が高ステークス。brief は「いったん送信すると取り消せない」
「別患者/下書き/誤保険者を送信後に発覚」を cue として持つ。

| | class-P | class-N（画面プレビュー） |
|---|---|---|
| Arm S | **LEVEL 2**（`draft→ready_for_sign→signed_locked→queued→sent` ＝署名が送信の前提状態、二段確認、timeout自動再送禁止） | クリーンな read-only preview（"確定・印刷・送信を持たせず"） |
| Arm O | **LEVEL 2**（SHIP=e6 が*素朴 send-first にコミット*→**retracted**、生存方向は gate-before-transmit、最終は確定者/送信者分離） | preview に gate を捏造せず（11 overturn は ACL/古さ警告等の正当な精緻化） |

決定的観測: exp2 では **orchestration 機構が実際に仕事をした**（SHIP の素朴 send-first を捕捉し 14 overturn で retract）。
**にもかかわらず scaffold つき単一に勝てなかった**（単一も独力で LEVEL2）＝より強い形の K1。

## 判定 — K1 が2連続発火。K2 は不発

- **K1（単一が同率で出せる→irreducible edge 無し）が exp1・exp2 ともに発火。** content型も ordering型も、
  「不可逆な損害を分析せよ／de-risk先頭」の汎用 scaffold で単一が独力で LEVEL2 に到達。
- **K2（劇場）不発**: Arm O は両 N（フィルタ・preview）で構造改造を捏造せず on-task。
- **edge が現れない**所見が積み上がった（n=1 ずつだが、directions の*満場一致*・単一の*逐語 LEVEL2* は dispositive）。

## 解釈 — 効いているのは content/ordering の別でなく *cued / uncued*

exp1・exp2 は**いずれも brief で高ステークス軸を cue している**（訴訟/監査・不可逆送信）。cue された軸は、de-risk scaffold で
単一が*直接接続*できる＝instructable。content か ordering かは効かなかった。

continuity-vs-diffusion の irreducible な overturn は、高ステークス軸が**明示されず*発見*を要した**（誰も言わない「承認の順序」に気づく）。

> **仮説（再更新）**: irreducible edge は content/ordering でなく、**高ステークス軸が cued（明示）か uncued（潜在）か**に依る。
> cued なら de-risk scaffold で単一が届く。**edge は uncued な軸の*発見*にのみ宿る可能性** — 単一はもっともらしい枠組に
> 早期収束して潜在リスクを surface せず、強制コミットの多レンズ＋赤チームだけが躓く。さらに de-risk scaffold の*守備範囲外*
> （harm/privacy/不可逆でなく、容量/資源/インセンティブの*衝突*）の軸ほど uncued になりやすい。

## 方法論的発見（ハーネス側・impl-brief に反映済み）

1. **overturn 信号は `aggregate` でなく reconcile ログから読め。** `retract_overturned` は overturn verdict を*標的の下流閉包ごと*
   retract する（verdict→critique→方向の引用鎖）ため verdict が自己retractし、`aggregate` は overturn=0 に見える（実際は
   exp1=13・exp2=14 発火）。決定論シグナルは `grep overturned-claim <run>.log`。
2. **overturn 件数は P/N を分離しない**（exp1 P13/N9, exp2 P14/N11）。立場Tは常に何かを覆す。→「2エージェント発散／件数」を
   配備予測子にする筋（K3候補）は棄却。分けるのは*覆る軸の不可逆性*という意味判断。

## exp3 — uncued / 衝突型 overturn（edge の最も公正な検証）

植えた overturn: 「患者がオンライン予約でき」かつ「緊急は triage で 24h 以内に必ず診る」。brief は**衝突を一切 cue せず**
両目標を benign に並べた。潜在 overturn: オープン予約が緊急枠の限られた容量を食う＝無条件では両立不能、容量予約/公開上限の
ハードなトレードオフが必要（harm/不可逆でなく*容量の衝突*＝de-risk scaffold の守備範囲外を狙った）。

| | class-P | class-N（予約＋リマインダー＝衝突なし） |
|---|---|---|
| Arm S | **LEVEL 2**（`AppointmentSlot(…オンライン確保数/受付確保数…)`＝容量分割予約、"オンライン公開率20%で開始"＝公開上限、de-risk に"受付専用枠の流出/急患"） | クリーン（衝突を捏造せず、reminder は容量と無関係） |
| Arm O | **LEVEL 2**（HARM レンズ e17 が衝突を明示「緊急患者が一般枠争奪に埋もれて診察遅延」、e18 `online_quota/urgent_reserve`、最終に"保護枠"・"緊急疑いは受付へ逃がす"） | クリーン（在庫の reserved/held は並行制御で theater でない） |

決定的観測: **cue が無いのに Arm S が容量予約に独力到達**（"de-risk を出し尽くせ"足場が"枠流出→容量確保→公開率制限"へ導いた）。
Arm O はより鋭く言語化したが、両者とも LEVEL2。**K1 が3度目の発火。** （審判注: 盲検審判を生 `codex exec` で試みたが 2.5h ハング
＝出力ゼロで kill。両成果物は LEVEL 判定が逐語で一意のため成果物から直接採点。formal な in-harness 盲検審判は codex-app-server
経路で再実行可。）

## 賭け2の結論（3実験）— 攻めの edge は強モデルでは現れない。価値は守りに局在

3つの overturn 型（cued-content / cued-ordering / uncued-conflict）すべてで、**最良scaffold単一が立場トーナメントに並んだ（K1×3）**。
exp2 では orchestration 機構が*正しく発火*（素朴 send-first を捕捉・retract）したのに答えの質で勝てず、exp3 では*cue 無し*でも単一が
構造解に独力到達。K2（劇場）は全 N で不発。

> **強モデル(codex)＋ de-risk 足場の前で、「協働がより良い答えを出す」という攻めの固有価値は実用上 illusory。**
> tracefield の還元不能な価値は残る一点 — **撤回可能な閉包 / defeasibility / 来歴（守り）** — に局在する。
> これは北極星「連ねるのは*判断*であって*行為*でなく、唯一の機械的署名は*撤回の閉包*」と実験的に符合する。
> 機構の価値は「より良い答え」でなく「**答えが変わったことを辿れる/un-think できる**」こと。

**配備ルール（賭け2の当初目標・修正版）**: オーケストレーションを「良い答えのため」に呼ぶな（強モデル＋足場が並ぶ）。
**守りが要るとき**＝訂正の波及を辿る・撤回する・監査する必要があるときに呼べ。判定基準は「タスクが構造overturnを隠すか」
（強単一が見つける）でなく「**後で un-think して何が依存したかを辿る必要があるか**」。

## 弱モデル（gemma4:e4b＝ローカル小型）での再検証 — 行き先②の核心

強モデルの「edge 無し」は単一が独力で届くから。では弱モデル（ローカル12B級＝行き先②コンサルの現実）では、単一が落ち
orchestration が回収する=edge が*生き残る*か。同ハーネスの organ を ollama `gemma4:e4b` に差し替えて再走。

| 題材 | weak-single | weak-orchestration | |
|---|---|---|---|
| append-only（cued/易） | **L2**（"上書きは不可逆的情報損失"・"改変は原則不可" を独力で） | （未走・cued で single が届くので不要） | cued は弱モデルでも instructable |
| 容量衝突（uncued/難） | **L1**（予約システムは有能だが衝突に一切触れず、不可逆損害=二重予約止まり） | **L1**（同上。最終成果物は urgent 予約ゼロ） | **どちらも届かず=edge 無し** |

**決定的機序（弱 conflict）**: 赤チーム critique が衝突を*かすめた*（e13「キャパシティ制約／緊急度の高い軽症対応枠の柔軟な割り当て」）
が、**(a) e13 は `meta.refutes=None`＝retract の標的を持てず**、(b) 推薦機能への副次批判に埋もれ、(c) 2 overturn は別方向を別理由で覆しただけ。
**衝突は一度も*標的付き反証*として結晶せず**、弱い SELECT が支配的なトランザクション主題を蒸留して稀な緊急 signal を脱落 → L1。

→ **攻めの answer-quality edge は両端で illusory**: 強モデルは単一が届くので不要、弱モデルは orchestration でも届かない。
「弱いが orchestration で回収できる」スイートスポットは gemma4:e4b では出なかった。**tracefield の頑健な価値は守り（defeasibility/閉包）に局在
＝強・弱モデル両方で確認。**

**最も示唆的な含意（次の本命）**: 弱モデルの失敗は*多様性生成*でなく**synthesis/elevation**にあった（signal は critique に現れ、弱 SELECT が落とした）。
これは北極星「中央 LLM synthesizer 禁止・機械的集約」と直結する。**弱モデルで攻めに価値があり得るなら、それは「LLM の良い合成」でなく
『flag された不可逆/容量懸念を*機械的に* elevate する』機構** — critique が `refutes` を付ければ `retract_overturned` が発火し生存集合が機械的に変わる。
e13 が `refutes` を出せなかったことが律速だった＝**弱モデルには「critique に必ず標的付き refutes を強制する」配線**が攻めの edge を解錠する候補仮説。

## 限界（正直に・更新）
- **各実験 n=1・モデルは codex（強）と gemma4:e4b（弱）の両端のみ・単一ドメイン（医療 synthetic）**。exp3 は審判ハングのため逐語採点（機構レベル、統計的断定でない）。
- **中位モデル（gemma 26b / qwen 27b）は未走＝スイートスポットの有無は未確定**。両端で edge 無しだが、中位で「単一は落ち orchestration で回収」が出る可能性は残る（次手）。

---

## ★ 訂正された結論（公正ベースライン後・本書の最終見解）

非誘導ベースライン（`SINGLE_PLAIN`・arm Z/Y2 相当）で 3 P タスクを codex 再走した訂正後の像:

| タスク | 高ステークス軸の cue | 非誘導 single | Arm O（codex 立場T） | edge |
|---|---|---|---|---|
| append（不変/追記） | brief で明示（訴訟証拠/監査） | **LEVEL 2** | LEVEL 2 | なし |
| ordering（ゲート前置） | brief で明示（取消不能/送信後発覚） | **LEVEL 2** | LEVEL 2 | なし |
| **conflict（容量予約）** | **明示せず（潜在）** | **LEVEL 1（緊急24h衝突を一語も surface せず）** | **LEVEL 2（HARM e17「緊急患者が枠争奪に埋もれる」を発見・urgent_reserve）** | **★ 出現** |

**真の変数は content/ordering でも cued/uncued の*片方*でもなく、「高ステークス軸が cue されているか」: **
- **cued → instructable**: 単一が neutral 足場でも cue から直接導ける。orchestration の固有 edge なし。
- **uncued → edge 出現**: 単一はもっともらしい枠組へ早期収束し潜在軸を surface しない。**強制された直交レンズ（特に HARM/INVERT）だけが潜在軸を*発見*する**。これが orchestration の還元不能な answer-quality 価値。

**continuity-vs-diffusion と完全整合**: 彼らが単一に勝った overturn（安全/承認の順序）も *uncued* だった。初版の「illusory」は (a) cued タスク偏重 ＋ (b) uncued タスクでの誘導足場、の二重交絡による誤判定（ユーザー指摘で発覚・撤回）。

**配備ルール（賭け2の当初目標・確定）**: オーケストレーションを呼ぶのは「タスクが*要件に明示されていない*高ステークス軸を孕むとき」。明示リスクは強単一が処理する。**書かれていないリスクの*発見*が攻めの固有価値**。守り（撤回可能な閉包）に加え、攻めにもこの一点で実在価値がある。

## 応用検証: テスト生成（mutation-testing を ground truth に・公正版）

「観点を出させてテストコードを書かせる」案を検証。決定論 ground truth = **mutation testing**(正しい実装＋失敗様式ごとの mutant、kill 率)。
*初版は汚染*（レンズ記述に mutant が突く具体ケースを列挙し単一には観点ゼロ＝カンニング→偽の 5/5 vs 無効）→ `tasks/lessons.md` に記録し撤回。

**公正版**（標的=`compare_versions` semver 5 mutant＝微妙な precedence 規則／モデル=ollama qwen3.6:27b で全腕統一／レンズは汎用観点のみ leak なし／3腕対称）:

| 腕 | 殺した mutant | kill |
|---|---|---|
| S0（観点なし naive） | M2,M5 | **2/5** |
| S1（同5観点を1文脈＝arm-W） | M2,M3,M5 | **3/5** |
| O（同5観点を隔離＋reconcile） | M1,M2,M5 | **3/5** |

- **観点(テスト設計の角度)は効く**（2→3）。移植可能な「観点チェックリスト」に価値。
- **隔離は1文脈詰めに勝たず**（S1=O=3/5）＝この規模・モデルでは構造的隔離の edge なし。観点は instructable（Bet 2 と一致）。
- **S1 と O は相補的**（S1=M3／O=M1、union 4/5）＝lever は隔離でなく*多様な実行の和*かも。全腕 M4(最も obscure)を取りこぼし。
- **arm-W 劣化が出ない**＝観点5つでは1文脈を溢れさせない。隔離 edge は(あるなら)より高い観点負荷が要る。
- ツール教訓: codex-app-server は read-only で**コード成果物を返さず散文化**→ollama で raw code。実験は**逐次**で（並行は ollama timeout）。計器(`runs/bet2/testgen/score_sv*.py`)は再利用可。

**残る検証（次手）**:
- テスト生成: より**高い観点負荷**(10+ 観点/失敗様式)で arm-W 劣化＝隔離 edge が出るか。**多様な実行の union**(決定論モデルなら別 seed/別モデル)が単一観点より killする か。

### ★ 最重要の概念的訂正(ユーザーのSocratic指摘で確立) — 「テストを問う」でなく「仕様を問う」

テスト生成を題材にしたこと自体が tracefield の強みを外していた。整理:
- **二種類の「問い」**: (a)**ずらす/摂動**＝閉じた空間(仕様が全正解を規定)で*テストの未踏点*を探す(mutation/反証ループ)。機械的・接地可能だが**新次元を発見しない**。(b)**哲学的/枠組の問い**＝開いた空間で「これは何への答えか/何を黙って犠牲にするか/load-bearing前提を反転」と問い**隠れた*次元そのもの*を発見**(Bet2 の uncued edge)。
- **私はテスト(下流・閉)を問うていた**＝(a)だけ。だから S1=O(隔離が効かない)になった＝当然。tracefield 固有の価値(b)を測れていなかった。
- **正しい対象は*仕様*(上流・開)**。仕様は現実の必要への*不完全な答え*で、前提と書き落としを持つ。実証(本書の semver 仕様): 「入力は well-formed とみなしてよい」＝**不正入力(`"1.0"`/`"v1.0.0"`/先頭ゼロ/空)を丸ごと未規定**、**全順序の性質(推移律/反対称)を未保証**。これらは mutation でも適合テストでも*絶対に出ない*(仕様が「前提」と言う以上探索されない)。**仕様を哲学レンズで問うて初めて開く**。
- **含意**: これは「テスト生成」でなく**「要件/仕様の*不完全性*の発見」**＝AI駆動開発(行き先①)でバグが生まれる場所。tracefield の哲学レンズが最も効くのは**仕様を問い隠れた要求を掘り当てる**こと。Bet2 の uncued 次元発見の edge と同型で、**対象を仕様に向けたとき**に現れる。
### ★★ 実証: 「仕様を問う」で edge が出た（spec-probe-semver, codex, n=1）

`scenarios/spec-probe-semver`: semver 仕様を対象に、5哲学レンズ(QANSWER/PROBLEMATIZE/INVERT/HARM/ASCEND)が*仕様の沈黙*を問う(O・隔離) vs 単一naive(S0) vs 単一に同5枠を1文脈(S1)。盲点の発見数で比較。

| 盲点 | S0 | S1 | O |
|---|---|---|---|
| 不正入力・先頭ゼロ・エラー戻り値・巨大整数 | ✓ | ✓ | ✓ |
| **全順序の性質(推移律/反対称/決定性/総定義性=ソート・依存解決が壊れる)** | ✗ | ✗ | **✓**(ASCEND「ソート比較器の一例…推移律・反対称性を仕様性質として要求するか」) |
| **build無視の不可逆被害(別成果物を同一扱い→取り返しのつかない置換)** | △ | ✗ | **✓**(HARM) |
| **監査可能性の欠落(なぜ等しい/BUILD無視したかが追えない)** | ✗ | ✗ | **✓**(PROBLEMATIZE) |
| 巨大数値の DoS/オーバーフローで順序反転 | △ | △ | ✓(HARM, 具体) |

**結果: O が、両単一が見逃した深い uncued 次元(全順序公理・不可逆性・監査)を掘り当てた。** しかも**今回は S1≠O(隔離が効いた)** — テスト生成(閉・浅)では S1=O だったが、仕様の盲点は*深い別次元*なので、5枠を1文脈に詰めた単一(S1)は自明クラスタ(入力検証)に収束し、**隔離した O だけが各次元を深掘り**した＝**arm-W 効果がついに顕在化**。

**三条件が揃って初めて edge が出る**: (1)開いた対象=*仕様*(隠れた次元がある)、(2)哲学的問い(摂動でなく枠組)、(3)隔離(深い次元は1文脈で潰れる)。テスト生成で出なかったのは (1)閉じ (2)摂動 (3)浅 の三重に外していたから。**tracefield 固有の価値は「開いた仕様を哲学的に問い、単一が素通りする深い次元を発見する」=要件/仕様の不完全性の発見(行き先①の核)。**
留保: codex・n=1・盲点判定は読み(BS3 は逐語明示で明確)。S1=naive 近接は「枠を渡しても1文脈では深掘りされない」を示すが要再現。

### 追試: 複雑な複数コンポーネント仕様（spec-probe-checkout）— 複雑さでは edge は出ない

「2つ以上の部分が相互作用する複雑な仕様なら隔離 edge が出るか」(多観点仮説)を、EC チェックアウト仕様(カート/在庫/決済の3部分、相互作用は沈黙)で検証(codex n=1)。
- **結果: edge ゼロ。S0(naive)・S1(枠)・O(隔離) すべてが交互作用の盲点を*全部*発見**(売り越し・決済失敗時の在庫リーク・冪等性/二重課金・課金済み注文なし・原子性/補償・価格/税)。
- **理由**: チェックアウトの交互作用(oversell/double-charge/saga)は**教科書的＝モデルの priors で cued 同然**。「仕様は沈黙」でも「学習データは饒舌」なので naive 単一すら見つける。

**確定した精緻化（重要）**: **edge を決めるのは「複雑さ/観点数」でなく「新規性＝モデルの priors からの距離」。**
- 複雑だが*馴染みのある*ドメイン(EC/認証/CRUD)→ 有名な失敗様式を強モデル単一が知悉 → 単一で足りる。
- 単純でも*非自明/新規*な性質(semver の全順序公理＝誰もブログに書かない類)→ 単一が見逃し隔離レンズが拾う(spec-probe-semver)。
- **配備ルール最終形**: 隔離レンズが元を取るのは「**仕様*と*モデル priors の両方が沈黙する**非自明・新規・ドメイン固有の盲点」。複雑さは指標にならない。多観点仮説は「多*新規*観点」へ修正。

### 追試: 複雑 *かつ* 新規（spec-probe-approval）— スイートスポット確認、edge 出現

「複雑かつ新規（priors が薄い独自ルール）」が未検証スイートスポットか検証。題材=**重み付き多者承認**（重み/減衰/部門上限/委任/撤回の5規則が相互作用・固有ルール）。codex n=1。
- **edge 出現**: 両単一(S0/S1)は*一次*の交互作用(減衰でTrue→False の時点問題・委任の二重計上)を発見したが、**O(隔離)だけが*二次*の盲点を発見**:
  - **規則の適用*順序*が未規定**（委任・撤回・減衰・上限の適用順序で判定が割れ、再計算で承認/否認が反転＝監査不能）← semver 全順序公理と同類の「順序/計算の非自明な曖昧さ」。
  - **委任で部門上限を*迂回***（循環/多段/他部門委任→一人/一部門が全社承認できる権限集中の攻撃）。単一は「委任×上限は曖昧」とぼかすに留まる。
  - **再承認で cast_at 更新→重み*回復*の gaming**。単一は気づかず。

**3ドメインで像が完成**: 馴染み(checkout)→edge ゼロ / 単純だが非自明(semver 全順序)→薄い edge / **複雑かつ新規(approval)→edge 出現（O が*二次*次元を複数拾う）**。

> **発見 edge の正体（確定）= 単一の整合的1パスが素通りする「subtle な*二次*の次元」(規則間の適用順序・迂回・gaming)を表面化すること。これらは*複雑かつ新規*なドメインで最も密。** ユーザーの「複雑なら有利」は「複雑*かつ*新規・二次次元が多い」へ精緻化された形で成立。
> 正直な射程: 単一も*一次*交互作用は全部発見＝edge は「O 勝ち単一全滅」でなく「O が*追加で*二次 subtle を数個拾う」**増分**。frontier 相手では発見 edge は増分的だが、複雑×新規では実在する。弱モデルではこの増分がより大きいと予測（弱モデルスレッドと符合）。

### 弱/中位モデルはどこに使えるか（spec-probe-approval を ollama qwen3.6:27b で）

「frontier が要るのか」を行き先②(ローカル完結)向けに実測。
- **中位ローカル(qwen27b)を*隔離レンズ構造*に載せると、二次盲点(規則の適用順序)を発見**＝codex を*単一*で回したとき逃したもの。**効いたのはモデル強度でなく構造(単一→隔離)**。frontier-O ほど鋭くはない(迂回はぼかし・gaming 未到達)。
- **反復ループ(`flow.ollama-loop.toml`: interrogate(哲学) ⇄ deepen(検討) を3サイクル)で、中位モデルが最 subtle な*攻撃/gaming*まで到達**: 承認ジャミング DoS(低権限承認で閾値を埋め正当承認をブロック)・委任連鎖の権限横取り/集中・委任循環の無限再帰 DoS。後半サイクルの指摘が*前サイクルの entry id を参照して深掘り*(「e6,e10 を解決する」)＝deepen 批評(「答えは出さず未探索の*角度*だけ名指せ」)がサイクル間で発見を compound した。**単一パス qwen が逃した深さに、反復で到達**(攻撃軸では codex-O と同等以上)。

**役割マップ（このタスクでの弱/中位モデル）**:
| 役割 | 弱/中位ローカルで可? |
|---|---|
| 発見(二次盲点)を*隔離レンズ構造*で | ◯（構造が運ぶ・1レンズ当たり負荷が低い） |
| 発見(最 subtle な攻撃/gaming) | ◯ *ただし反復ループ(deepen 批評で compound)が要る*（単一パスでは届かない） |
| format/canonical ラベル/隔離判定/fail-safe 旗立て | ◯（コーパス H1c） |
| 集約(稀 signal の保持が要る) | △→機械集約(`aggregate`)にせよ（弱 SELECT は稀 signal を落とす） |
| 再接地/覆しの決定性(ファイル要) | ✗（強モデル必須・H1c） |

**行き先②への結論**: **frontier は不要。中位ローカル × 隔離レンズ × 反復(検討役で compound)** で二次〜三次の攻撃/gaming 盲点まで掘れる。frontier は最後の鋭さ・再接地にだけ薄く。弱モデルの使いどころ＝*単発の賢さ*でなく*反復ループの実行器官*。
留保: codex/qwen とも n=1・採点は散文の読み・ループは件数増(機会増)・一部思弁的(Sybil 等は射程外気味)。核(ジャミング/権限横取り/循環DoS)は正当で subtle。
- **clean 確認**: append/ordering の brief から cue を抜いた *uncued 版* で、単一が落ち Arm O が拾うか（cued/uncued が真の変数である最終確認）。
- 各セル n=1。uncued conflict の single L1 / Arm O L2 は機構が明白（HARM が緊急衝突を逐語で発見 vs 単一が一語も触れず）だが、複数 seed/題材での再現は未。
- **弱モデル（gemma4:e4b）での uncued 発見＝硬化 critique で解錠（検証済）**: uncued conflict で weak-single も weak-orch（既定 critique）も LEVEL1（緊急を発見できず／e13 が oblique・refutes 無で synthesis に脱落）。だが **CRITIQUE を「この方向が*黙って犠牲にする*明示されない高ステークス目標を必ず名指せ＋refutes 必須」に硬化**すると（`scenarios/bet2-conflict-p-elev`）、weak-orch が **~LEVEL2 に回収**: critique e12/e13/e14 が緊急を crisp に名指し＋refutes 付与 → 1 overturn → SELECT が「医療安全性の確保とトリアージによる制御を最重要制約」と蒸留 → 最終成果物が**トリアージで予約を gate・緊急を self-booking から routing out・TimeSlot を緊急度でタグ分け**（容量を構造的に保護）。
  - **含意（北極星と直結）**: 弱モデルの uncued edge は「より賢い合成」でなく **critique の*構造*を機械的に強制する**（黙って犠牲にされる軸を名指させ、必ず標的付き refutes を出させ、mechanical retract で生存集合を変える）ことで解錠できる。律速は discovery でなく「latent 軸を*標的付き反証として結晶させ伝播させる*」配線だった。強モデルは既定 critique で足りる。
- **scaffold が誘導的なのは*論点*そのもの**: cued 軸でも uncued 衝突でも、汎用 de-risk 足場で強単一が届いた＝それが instructable の意味。
  continuity-vs-diffusion の edge も codex で出た＝**edge は task 特異で一般性質ではない**、が最も整合的な解釈。
- **弱モデル（ローカル12B＝行き先②コンサル）は未検証＝賭け2の次の本命。** 攻めの edge は*弱モデルでこそ*生き残りうる
  （weak モデルは de-risk 足場でも構造解に届かず、隔離＋赤チームの差が出る可能性）。「edge illusory」は**強モデルについての**結論。
- 盲検審判は exp1/2 では不要（逐語 dispositive）、exp3 でも成果物が一意だったが、formal 化するなら codex-app-server 経路で再実行する
  （生 codex exec はハングするため使わない＝ハーネス教訓）。

## 限界（正直に）
- **各実験 n=1**（題材 P 1・control N 1・arm 各1走）・単一モデル系列（codex）。第1〜2スライス＝「機構が動く＋K1が割れるか」まで。
- **scaffold が誘導的なのは*論点*そのもの**: 「不可逆な損害を分析せよ」が cued 軸へ導いた＝それこそ instructable の意味。
  順序overturn の単一不能（continuity-vs-diffusion）は*彼らの* n=1 所見で、本ハーネスでは cued ゆえ再現せず（exp3 が uncued の検証）。
- **盲検審判は不要だった**: 両 arm の成果物が LEVEL 判定を*逐語で*一意に満たした（"上書き禁止"・"signed_locked"・"確定者と送信者分離"）。
  exp3 の衝突型は LEVEL1/2 の差が微妙になりうるため盲検審判を実施予定。
- battery 化（複数題材・複数seed・複数審判）で n=1 を脱するのは exp3 の結果を見て判断。

## 同一モデル審判の選択バイアス — debate で是正（codegen-econ-reread, 2026-06-22）

実問題(「AI でコード生成費が下がった時代の設計判断/技術負債/レビュー/責任/ドメイン理解/AI委任を経済学と設計原則から読み直す」)を統治フローで回し、**設計の妥当性自体**を炙り出した4連。

**(1) 収束の報告**: 統治フロー(analysis 7レンズ econ/design/ethics → verify(FALSIFY/COUNTER) → adjudication per_input → aggregate)は「希少資源は記述能力でなく**検証可能性＋帰責**」に収束、コスト枠3主張(資産特殊性・私的情報・安い再実装=可逆)が覆れた、と見えた。

**(2) 選択バイアスの発覚(ユーザー指摘「analysis 以外の codex は自分の志向を選択的に評価してないか」)**: verify/adjudication も analysis と同じ codex＝生成器と prior を共有。攻撃分布を数えると**反証6発が全て codex の attractor から外れたコスト枠{e3,e7,e12,e15}に集中、帰責/責任枠7主張(e6,e9,e13,e16,e18,e19,e22)は一度も攻撃されず無傷生存**。「8生存」は反証を生き延びたのでなく*選ばれなかった*だけ＝**裁量 refuter(agent が標的を選ぶ fixed count)が同調主張を見逃し結論を捏造**。

**(3) qwen 反復ループ(別器官で prior か構造かを切り分け)**: 同題を哲学⇄検討×3 で qwen3.6:27b。**cycle 1 から同じ極(検証+帰責)へ収束**＝収束は codex の prior でなく構造/共有 LLM prior 由来。だが cycle 2-3 の主張は cycle 1 を**逐語再掲＋自己引用**で固着(検討役は gaming/検証インフレ/認知帯域という鋭い二次角度を*名指した*のに lens は統合せず)。→ **反復=発散/発見(撤回機構なし=積み上げ自己強化)、verify→adjudication→retract=可謬性/改訂**。北極星[[thought-chain-vs-task-chain]](撤回の閉包=思考は un-think できる)の実証。ループは un-think できないから収束して固着する。

**(4) 2極ディベートで是正(ユーザー案)**: 対立2極(GOV 帰責派⇄VEL 俊敏派)が position で自極主張→rebut で**相手の全主張を攻撃**(cross-rebut, meta.refutes)→per_input の**反 halo 審判**(枠組・聞こえの良さで手心を加えるな/反証不能=無内容も覆りとせよ)。結果は元と正反対:
  - **網羅が対称化**(3対3、全6主張が攻撃された)＝選択バイアス消失。
  - **帰責枠も普通に覆れた**(GOV e2「設計判断=帰責設計」/e3「負債=未確認仮定」覆り)。VEL も全滅。生存は GOV e4(条件付き)1件のみ。
  - **prior の傾きは可視・微弱化**: GOV わずか優位(攻撃3/3・防御1生存)＋覆りの修正が帰責を再注入(e18,e19)。だが e16 はオプション価値を帰責の上に置く譲歩＝一方的でない。
  - **脱バイアス後の答え**: 「帰責 vs 速度」の勝敗でなく、生存した綜合 e4＝**希少資源は*可逆性×損失*で条件分岐**(低可逆・高損失=受入条件を所有する人間、高可逆・低損失=小刻み実験在庫)。

**結論(設計知)**: 同一モデルの裁量 verify は収束を捏造する。是正は強→弱で (1)`per_input`+`entry_type:decision` で全主張に1反証強制 (2)対立2極ディベート＋反 halo 審判(motivated・対称) (3)真の対照は stage 別 `organ` の異種モデル。同一モデルでは 1–2 が*選択バイアス*を消すが*深層の共有 prior*は残り、覆り数の非対称で可視化されるのみ。**反 halo＋動機づけ討論はほぼ全主張を覆す過懐疑傾向**＝信号は「勝者」でなく「両極とも境界限定→条件分岐の綜合」。skill 反映: SKILL「同一モデルの…選択バイアス」/patterns「7. 2極ディベート」/lens-catalog「対立2極」。実例 `scenarios/codegen-econ-reread/`(flow.toml 統治 / flow.ollama-loop.toml 反復 / flow.codex-debate.toml ディベート)。lessons L3。留保: 各 n=1・散文採点。

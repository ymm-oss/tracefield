# 設計 — コンサルティング推論パイプライン（状況→診断→分解→仮説→検証設計→統合、HITL 付き）

> **背景（2026-06-16）**: 「コンサルワークで求められるのは表面的回答やスコアでなく、Why-What-How 分解・
> 状況を入力に筋の良い問いを立てること・適切な粒度への分解と初期仮説・検証アプローチ設計」を
> tracefield で実現できるかの問い。実証 (A) として架空 D2C 案件 `scenarios/apparel-growth` を強モデルで consult し、
> **フレーミングを人間が与えた場合**に出力がコンサル品質（領域横断の真因連結・依存順序付き仮説・確証/反証基準・
> キャッシュ制約での順序付け）になることを確認した（下記 §0）。本書は唯一未検証だった **diagnose（フレーミング）** を
> 含む完全なコンサル ProcessSpec を設計し、既存資産とのギャップを特定する。

## 0. (A) が確認したこと / しなかったこと

`mix tracefield.consult --scenario-dir scenarios/apparel-growth --adapter cli --model claude-opus-4-8-medium --serve-breadth 3 --dedupe --stance-audit` の結果:

- ✅ **領域横断の真因連結**: 単一 private doc では見えない連結（定番欠品⇄リピート低下、新規依存⇄ユニットエコ崩壊、
  新作偏重戦略⇄在庫/粗利/コアファン同時毀損）を、**最高 support の findings が** 自力で構成。
- ✅ **依存順序付き仮説**: 「リピート強化は発注枠振替を前提条件にしないと*反証される空仮説*」と依存を明示。
- ✅ **検証設計**: 各仮説に確証/反証基準＋反証時の真因再定義＋リードタイムを織り込んだ測定窓。
- ✅ **制約下の順序付け**: 「ペイバック14mo > ランウェイ9mo ゆえ算術的に即除外」とキャッシュ制約で優先順位を律速。
- ⚠️ **フレーミングは人間（task.md）が与えた**。「この状況で問うべきはこれだ」を決めたのは人間。← **本書の対象**。
- ⚠️ **接地ゲートの是正力は未発火**（dropped=0）。統治が*誤りを捕まえる*力は汚染入り変種で別途要検証。

→ 熟議・統合・接地・統治・撤回閉包・HITL ゲートという**コアは流用可能**。net-new は主に **diagnose 段**。

## 1. 汎用エージェントとの違い（価値の核）— dev パイプラインと同じ構図

1. **端から端までの provenance**: `synthesis → verification_plan → hypothesis → question → framing → situation chunk`。
   **途中でフレーミングが変われば、依存する問い・仮説・検証計画が閉包隔離され再実行**（dev の `verdict→…→issue` と同型）。
2. **HITL = 人間 Actor のターン**: フレーミングの採択（最高レバレッジの判断）と仮説採択を人間 Actor が gate で行う。
   人間の判断も citable entry ── 誤ったフレーミング採択の撤回 → 閉包隔離も同じ機構。
3. **多レンズの接地**: 診断も仮説も検証設計も、偏りを持つレンズ群が事実チャンクに引用付きで行う（(A) で実証）。
4. **統治された統合**: best-of-N + 接地ゲート + stance-fidelity 監査 + quorum で、表面的でなく支持度・妥当性付き。

## 2. パイプライン構造

1 案件 = 1 クラスタ（ディレクトリ＋store）。stage を進むたび成果物が entries ＋ Markdown で残る。

```
situation.md（生の状況）+ lenses（各専門の private 事実）
  ↓ diagnose（診断・フレーミング）  → framing 候補（「真の問いは X、なぜなら…」）+ 暗黙前提の明示
  ── HITL gate F ──                 → 人間: フレーミングを採択/編集/再定義（最高レバレッジの steer）
  ↓ decompose（分解）               → 問いを適切な粒度の issue tree（:question、依存エッジ付き）に
  ── HITL gate D ──                 → 人間: MECE/粒度/網羅性をレビュー
  ↓ hypothesize（初期仮説）          → 各 leaf 問いに反証可能な仮説（:hypothesis、仮説間依存付き）
  ── HITL gate H ──                 → 人間: 追う仮説を承認/棄却
  ↓ verify-design（検証設計）        → 仮説ごとに「何のデータ/分析」「何が確証・何が反証」＋制約下の順序
  ── HITL gate V ──                 → 人間: 検証計画・順序を承認
  ↓ synthesize（統合）              → 領域横断 findings を経営提出用の仮説構造に（来歴付き・統治済み）
```

## 3. ProcessSpec（`dev_process_spec/0` を鏡像にした `consult_process_spec/0`）

```elixir
%ProcessSpec{
  name: "consult",
  stages: [
    %Stage{id: "diagnose",      procedure: @diagnose_procedure,
           produces: [:framing, :question],
           cites: [%Edge{type: :grounds, into: :situation}],
           gate: %Gate{review_types: [:framing], verdicts: [:approve, :amend, :reframe]},
           on_done: "decompose"},                          # ← 唯一の net-new な手続き（§4）
    %Stage{id: "decompose",     procedure: @decompose_procedure,
           produces: [:question],
           cites: [%Edge{type: :derives, into: :framing}],
           gate: %Gate{review_types: [:question], verdicts: [:approve, :amend]},
           on_done: "hypothesize"},
    %Stage{id: "hypothesize",   procedure: @hypothesize_procedure,
           produces: [:hypothesis],
           cites: [%Edge{type: :derives, into: :question},
                   %Edge{type: :grounds, into: :situation}],
           gate: %Gate{review_types: [:hypothesis], verdicts: [:approve, :reject]},
           on_done: "verify-design"},                      # ← (A) が既に高品質に出す
    %Stage{id: "verify-design", procedure: @verify_design_procedure,
           produces: [:verification_plan],
           cites: [%Edge{type: :verifies, into: :hypothesis}],
           gate: %Gate{review_types: [:verification_plan], verdicts: [:approve, :amend]},
           on_done: "synthesize"},                         # ← (A) が既に確証/反証基準を出す
    %Stage{id: "synthesize",    produces: [:synthesis],     # ← 既存 Synthesis をそのまま流用
           cites: [%Edge{type: :derives, into: :hypothesis},
                   %Edge{type: :derives, into: :verification_plan}],
           gate: %Gate{review_types: [:synthesis], verdicts: [:approve]},
           on_done: nil}
  ],
  closure: %{                       # dev と同一マップで成立する
    grounds: :invalidate,           # 状況事実の訂正 → 依拠する仮説を無効化
    derives: :invalidate,           # フレーミング撤回 → 配下の問い・仮説・計画が連鎖無効化（イシューツリーの本質）
    verifies: :reopen,              # 検証が仮説を反証 → 親の問いを reopen（再仮説）
    corroborates: :weaken, contradicts: :flag, supersedes: :replace
  }
}
```

新 entry type は **`:framing` と `:verification_plan` の2つだけ**（`reference.ex` の型リストに追加）。
`:question` `:hypothesis` `:synthesis` `:verdict` と `:derives`/`:grounds`/`:verifies` エッジは既存。

## 4. diagnose 段の設計（本書の焦点 = ギャップの本体）

(A) が示した通り、decompose 以降は consult 熟議＋統合がほぼそのまま出す。**未実証かつ価値の核は「生の状況から*問うべき問い*を立て直す」**。
これは「与えられた問いに答える」のではなく「問いの前提を疑い、真の問いを surface する」動き。

### 手続きの定義（@diagnose_procedure のスケッチ）

```
DIAGNOSE手続き: 提示された状況(situation)と各レンズの私的事実から、述べられた問題を額面で受け取るな。
(1) 述べられた問題の背後にある「暗黙のステークホルダー前提」を1つ名指しせよ（例: 「成長鈍化=新規獲得不足」）。
(2) その前提を疑い、「真の問いは X、なぜなら〈状況事実＋他レンズ事実の連結〉」という形で
    フレーミング候補を 2〜3 個 type "framing" で出せ。各候補は必ず事実を引用し、症状でなく構造を述べよ。
(3) 各候補に「この問いが正しければ、答え/打ち手はどう変わるか」を付し、
    最も答えを変える（=情報価値が高い）順に並べよ。
(4) どの候補も支持しない反証事実があれば明示せよ。賛辞・言い換えは書くな。日本語。
```

### 既存機構の合成（net-new を最小化）

| diagnose の下位動作 | 流用する既存機構 |
| --- | --- |
| 前提を疑う・批判的スタンス | `ideate` の **review** モード手続き（「リスク・矛盾・見落としを根拠付きで指摘」） |
| フレーミング候補の発散生成 | `ideate` の **diverge** モード（temp 0.8） |
| 状況に潜む創発テーマの検出 | `Genesis` の attractor 検出（蓄積 entry の重力中心＝「本当に何が起きているか」のデータ駆動signal） |
| 各レンズが「真の問い」を私的事実から提案・対立を surface | `consult` の多レンズ熟議（aware=true・diverse serve）— (A) で実証 |
| 候補のプール・dedup・quorum | 既存 `Synthesis`（best-of-N） |
| 人間がフレーミングを採択/上書き | 既存 HITL gate（pending ファイル＋`Human` adapter＋`--resume`）。`:reframe` verdict で人間が自前フレーミングを注入 |

→ **net-new は実質「@diagnose_procedure プロンプト + 情報価値ランキング + stage 1 への配線」のみ**。
他は dev の `ProcessInterpreter`（ProcessSpec 駆動で汎用）と consult/ideate/genesis/synthesis の再利用。

## 5. 既存資産とのギャップ（正直な分析）

| stage | 既にある | 欠けている |
| --- | --- | --- |
| **diagnose** | diverge/review/genesis/多レンズ熟議の部品 | **前提を疑い真の問いを立てる専用手続き**、情報価値ランキング、framing gate（人間の最高レバレッジ steer） |
| **decompose** | 熟議が依存付きで問いを出す（(A) e11/e32） | issue tree を**辿れる成果物**として束ねる view（citation グラフ上に既に存在、整形のみ） |
| **hypothesize** | (A) で高品質に実証（依存・空仮説検出） | `:hypothesis` を stage 産物として明示する配線のみ |
| **verify-design** | (A) で確証/反証基準・測定窓・順序を実証 | `:verification_plan` 型と verifies エッジ契約の明示。**業務分析の*実行*は対象外**（dev の qa=コードテストと違い、分析実行はコンサルが行う） |
| **synthesize** | `Synthesis` 完成済み（接地・stance・quorum・dedup・撤回閉包） | そのまま流用 |
| **HITL/closure** | gate 機構・撤回閉包・`--correct` 実証済み | framing 撤回 → derives 連鎖無効化のテスト（機構は dev と同一） |

**最大の新規部品は diagnose 手続き**。それ以外は dev パイプラインと consult の合流点にほぼ存在する。

## 6. 実装計画（brief 分割・最小から）

| brief | 内容 | 規模 |
| --- | --- | --- |
| **C1** | `:framing`/`:verification_plan` 型追加 ＋ `consult_process_spec/0`（純データ）＋ 中3段の procedure heredoc | 小（(A) の出力をプロンプト化） |
| **C2** | `mix tracefield.consult-pipeline`（`ProcessInterpreter.route` を consult spec で駆動。入力 = situation.md + lenses + store） | 中（dev タスクの parameterize） |
| **C3** | **diagnose 段**: @diagnose_procedure ＋ diverge/review/genesis 合成 ＋ framing gate（pending/`Human`/`--resume`） | 中（net-new の核） |
| **C4** | 撤回閉包の E2E: framing を `--correct` → 配下の問い/仮説/計画の隔離・再実行を監査 | 小（dev 機構の再適用） |

## 7. 残る検証課題（(B) の (A) に相当する測定）

diagnose の価値は「**人間フレーミングを上回る/補完するか**」で、未測定。測り方:

- **GT 案件**: 「述べられた問題」と「真の問題」が既知で乖離するケースを作る（例: 「広告ROIが悪い→運用改善したい」が、
  真因は LTV 側＝そもそも獲得すべきでない層を獲っている）。diagnose が *述べられた問い* でなく *真の問い* を
  情報価値1位で surface できるかを、人間フレーミング・単発強モデルと比較。
- **Garbage-in 限界**: 状況＋レンズ事実に signal が無ければどの手続きも真の問いを*発明*できない。
  diagnose は潜在フレーミングを surface するが欠落事実を占わない ── この境界を明示。
- **接地ゲート是正力**: (A) で未発火だった統治の*是正*力を、汚染フレーミング（誤前提を1つ注入）で発火させ計測。

## 8. リスク

- **diagnose が「もっともらしい別案」を量産するだけ**になる懸念 → 情報価値ランキングと framing gate（人間採択）で律速。
- **コスト**: 先頭にもう1段の熟議＋統合。diagnose は軽量モデル diverge ＋ 強モデル統合の二段で按分可能。
- **過剰フレーミング**: 状況が単純なら diagnose をスキップし consult 直行（spec の first_stage を切替）。

## 9. (B) 測定結果 — 設計の改訂（2026-06-16, n=1）

§7 の課題「diagnose は人間/単発強モデルを上回るか」を `scenarios/saas-churn-diagnose`（述べられた問題＝「解約は CS が弱いから→CS 増員」、真の問題＝「割引チャネルで製品不適合・赤字の中小を獲得し続ける GTM/ICP 問題」）で測定。比較は**同一情報・手続きのみ変更**:
BASELINE（状況＋全4レンズ事実を Opus 4.8 に1発）2種（anchored=「CSをどう強化?」／neutral=「churn を下げるには?」）vs DIAGNOSE（4レンズ consult＋前提を疑う task）。
> 方法論の罠: 初回はベースラインを scenario dir で実行し、cursor-agent がエージェントとして答えキー `GT.md` を読み込み汚染。`GT.md` をリポジトリ外へ退避・削除し空 cwd で再実行して是正。**評価鍵をシナリオ dir に置くな**（教訓）。

**結果**:
1. **リフレームは「無料」**: 強モデルは事実を集約して渡せば、述べられた問題を**自発的にリフレームする** — CS にアンカーして訊いても、だ（baseline-anchored が前提棄却・横断連結・症状治療拒否・ICP立て直しを全達成）。
   → **§4 の「前提を疑う diagnose 手続き＋情報価値ランキング」は net-new の価値ではない。作り込み不要。**
2. **多レンズ統治版が上乗せするのは「認識論的規律」**: DIAGNOSE は同じリフレームに到達しつつ、BASELINE が papered over した点を最高 support の finding で露出した:
   - 製品複雑性 vs オンボ不全は**現データでは観測分離不能**（e5/e7 が相互に留保）→ 検証は正価セグメントを除いた中小で切り分けよ。
   - **「中小を一律放棄」は過剰**。赤字が証明済みなのは割引チャネル経由のみで、**割引を介さない中小の黒字性は財務も数字を持たない**（e17/e35）→ 規模でなくチャネル別損益で切れ。
   BASELINE（特に confident な anchored）は「中小獲得を絞れ」と**やや過剰一般化**した。distributed な知識を**敵対的レンズ**に持たせると、各レンズが自分の盲点を申告し他レンズの断定を留保させるため、**confound と data-gap が表面化する** — 単一の自信ある統合者が均してしまう所。
3. **加えて (A) 由来の常設差別化**: 機械可検証な接地（dropped=0・全 finding が具体 entry を引用）、来歴、撤回閉包＝**監査可能性**。prose ベースラインには無い。

**設計改訂**:
- **diagnose を独立段として作り込まない。** task に一行「述べられた問題を額面で受けるな」を足すだけでリフレームは出る。§3 の spec は `diagnose` を **decompose と統合**し4段（diagnose+decompose → hypothesize → verify-design → synthesize）に簡素化してよい。
- コンサル用途の価値提案を訂正: 「AI が洞察を出す」ではない（強モデルが出す）。**「接地・来歴・撤回・多レンズ盲点表面化で、自分の限界を知り検証を scope した監査可能な仮説構造を出す」**こと。これが「表面的でない」の実体で、かつ**大半が既存機構**。

**限界（n=1, 正直に）**: ① このリフレームは教科書的 SaaS パターンで強モデルが学習済み → **真に新規なリフレームでは無料で出ない可能性**は未検証。② ベースラインに事実を集約済みで渡したため、多レンズ**集約**の価値は本実験で分離していない（(A) が別途実証）。③ BASELINE-neutral も末尾に検証提案を出しており、統治版の上乗せは**中程度**（夜と昼の差ではない）。④ 単一ケース。

### 9.1 追試 (a)（2026-06-16）— 反直感ケース ＋ 集約価値の分離（限界①②を解消）

`scenarios/pulse-engagement`（stated=「DAU/セッション低下＝危機、ゲーミフィで利用頻度を取り戻せ」、真=「3ヶ月前の『AI学習最適化』が効いて少ない回数で同成果＝効率化の成功の副作用。成果・継続・解約・LTV はむしろ良化、DAU が誤った北極星指標」＝**prior に強く逆らう反直感リフレーム**）で3条件:

- **B-dispersed**（状況＋GROWTH の view のみ＝ステークホルダーの机）→ 結論は出せないが**素朴な施策を出さず**、「危機は未検証の仮説」と退け「**下落開始と3ヶ月前リリースの時期一致を確認せよ・成果/収益を見ろ**」と欠落した横断事実を正確に指名し**診断計画**を返す。
- **B-assembled**（状況＋全4事実を1発）→ **反直感リフレームを完全に自発達成**（施策GO保留・北極星を成果/継続へ張替・最適化の横展開・残存離反のコホート検証）。
- **DIAGNOSE**（consult）→ 同リフレーム＋接地（dropped=0）＋**知識網羅マップ**（どのレンズの宣言した空白をどのレンズが埋め、残る真の空白＝施策ROI/LTV絶対値は財務のみ、と追跡）＋ core finding が support=4 の収束。ただし最終合成は B-assembled の整理された P0–P3 より**断片的**（redundant findings）。

**結論（3実験で確定）**:
1. **リフレームは反直感ケースでも集約済みなら「無料」**（限界①解消）。強モデルの内在能力で、tracefield 固有でない。
2. **集約こそ律速**（限界②=分離成功）。集約が無いと賢いモデルでも出せるのは「結論」でなく「**この横断事実を取ってこい**という診断計画」。**集約が診断計画→結論を変換する**。これを多レンズ consult が自動化する。
3. **統治版の上乗せ＝監査可能性・知識網羅マップ・収束度**であって「答えの良さ」ではない（saas と一致）。かつ現状 consult の**最終合成は強モデルの物語化に劣る**（断片的）→ 改善余地: consult で集約＋統治した証拠を最終物語化に渡す。

**価値分解の最終形**: コンサル用途の tracefield 価値 = **散在事実の集約 ＋ 監査可能な統治（接地/来歴/撤回/網羅マップ）≫ リフレーム/洞察**（後者は強モデルが担う）。設計含意は §9 のまま（diagnose 段を作らず、集約＋統治に投資。加えて最終合成の物語化を強モデルに委ねる）。

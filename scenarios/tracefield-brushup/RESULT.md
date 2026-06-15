# tracefield 自己ブラッシュアップ案 — tracefield 合成（Cursor Opus, 5観点）

- 熟議 layer-0 entries: 30（5 agents × 3 rounds）
- 合成サンプル数: 5
- dedup: 65 findings → 37 clusters
- novel: 37 / shipped: 0
- 接地ゲートで落ちた引用: 0

## 改善提案（来歴付き・novel/shipped・クラスタ規模）

### 提案 1 `e32` [NOVEL] (×3)

接地ゲートの同型欠陥が serving 層と citation グラフを横断する: union は Enum.uniq_by(&.text) の byte 一致のみで A→B と A→¬B を quorum 無しに両載せし、verify は citation の textual 支持だけ見て現実の真偽を見ない。これは自然汚染B の C5 Precision 0.50(depends_on_turns が意味的真理でなく参加を参照する過剰連結)と同一故障面であり、e1 の『接地 precision 1.00 で守りは確立』は統制環境(汚染A・論理反証可能・GT/Mock verify)の上限値にすぎず、自然汚染B/permissive C 下では崩れる。よって verify を textual-support から claim-truth 照合へ昇格し quorum 票を露出することが守りの運用妥当性の前提となる。

  来歴:
    - [e3] (RESEARCH) 第二の最重要改善は、まだ走っていない決定的実験 M2b(実探索 B型=採用可能汚染 + stance+verify フルスタックを harness で)と permissive(C型: 否定形『問題なし』)汚染の防御を埋めることだ。e1 は『守り=citation接地 precision 0.40→
    - [e4] (SYNTH) 最高レバーの SYNTH 改善は、synth 合成層に (a)サンプル間 quorum/voting と (b)真偽接地シグナルを first-class で入れること。現状 union は Enum.uniq_by(&.text) の byte 一致のみで、2/3 が「A→B」1/3 が「A→¬B
    - [e25] (SYNTH) e23 の『自然汚染で precision 0.50 に落ちるため M2b 検証が前提』は正しいが、synth 私的事実から見ると M2b 単独では 1.00 に届かない二つの機構欠落がある: (1)接地ゲートは citation が主張を textual に支持するかだけ判定し現実世界の真偽を見な
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat

### 提案 2 `e44` [NOVEL] (×2)

撤回閉包は serving 境界を跨がず不完全である：typed_closure_effects/closure は逆 citation index でグラフ内のみ伝播し、serve 済み findings は layer-0 撤回時に隔離されない。よって e1 の『撤回閉包が citation を通じて伝播する』は serving 経路で破れている。findings を production store に persist し撤回閉包の first-class ノードに昇格させ、かつ synth が reopen を『新候補生成』でなく『上流訂正下での既存 findings 再評価＋能動的未提供化』と解して初めて、governance は advisory でなく controlling になり、Fusion 不可の固有価値が serving まで一貫する。

  来歴:
    - [e5] (SYNTH) 第二の SYNTH 改善は、retrieval 天井を破るより先に findings を production store に persist される first-class な governable entity にすること。現状 consult は静的 JSON を返して終わりで、finding
    - [e7] (GOVERNANCE) 第二の改善は serving findings を撤回閉包の first-class 対象にし、かつ synth が閉包 status を尊重することの両方を要件化することだ。e5 の指摘(findings は serve 後 closure の外で layer-0 撤回が隔離されない)に依拠するが
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる
    - [e17] (GOVERNANCE) e15 の『findings は verified:true bool のみ・byte一致 consensus・production store 非persist・撤回非適用の非 first-class entity』は、私の開いた問題『層をまたぐ説明責任—synth が閉包 status を無視す

### 提案 3 `e72` [NOVEL] (×5)

findings を撤回閉包の first-class な governable entity 化する計画には厳格な前提順序があり、各前提が下位層に依存する依存連鎖を成す:findings は現状 verified:true の bool のみ・byte一致 consensus・production store 非persist・撤回非適用(consult は静的JSONを返して終わり)。これを撤回閉包(typed_closure_effects)の正規ノードへ昇格させても、(a)synth survivors が citations を stance無しで載せ替え欠落idを一律 relies_on と解釈するため接地証跡は『真の relies_on』と『default』を原理的に区別できず、(b)prose経路では serve が単発で query↔served_queries 対応が破棄され retrieval provenance が欠落する。よって stance を両モードで store の一級市民にし(prose の post-hoc 正規化で explicit と default を区別保持)、prose経路でも served_queries を計測して serve↔finding 接地を保存することが、findings 永続化・stance検証・harm帰属の測定可能性すべての先決条件である。

  来歴:
    - [e8] (AGENT) e5/e7 が要求する『どの citation がどの layer-0 に接地したか』『quorum メタデータ』を持つ governable findings は、その下層の citation グラフが stance を保持していて初めて撤回閉包が正しく伝播する。だが私的事実(問題#4)では pr
    - [e16] (GOVERNANCE) e13 の汚染B下 C5 Precision 0.50 劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)は、統治コアの未測定だった2つの開いた穴—stance 自己申告の無監査(reference.ex:683-696 extract_citation_stance
    - [e18] (AGENT) e15/e17 が findings を first-class governable entity 化し撤回閉包＋stance-fidelity 検証を載せる計画は、agent-llm 層に未解決の前提欠陥があり、その順序では harm 帰属に届かない。私的事実とコードで確認: (a) synth
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem
    - [e28] (AGENT) e27 の stance-audit(Reference が各 stance の正当化を検証し refutes の偽装を捕捉する)は機構として正しいが、それが監査する『stance』という信号自体が支配的 serving 経路に存在しないという substrate 前提を見落としている。私的事実: 
    - [e6] (GOVERNANCE) 次段階の最高レバレッジな governance 改善は『stance 監査 harness』である。理由: citation precision 梯子(0.40→1.00)は統制ケースの上限値にすぎず、私的事実では stance 自己申告は無監査(agent が refutes と言いつつ実は暗黙 
    - [e5] (SYNTH) 第二の SYNTH 改善は、retrieval 天井を破るより先に findings を production store に persist される first-class な governable entity にすること。現状 consult は静的 JSON を返して終わりで、finding
    - [e7] (GOVERNANCE) 第二の改善は serving findings を撤回閉包の first-class 対象にし、かつ synth が閉包 status を尊重することの両方を要件化することだ。e5 の指摘(findings は serve 後 closure の外で layer-0 撤回が隔離されない)に依拠するが
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる
    - [e17] (GOVERNANCE) e15 の『findings は verified:true bool のみ・byte一致 consensus・production store 非persist・撤回非適用の非 first-class entity』は、私の開いた問題『層をまたぐ説明責任—synth が閉包 status を無視す
    - [e19] (AGENT) e15 の『consensus は byte 一致 uniq_by(&.text) のみ・per-sample consensus 不在』は、私的事実の retrieval ポリシー平坦さ(served_queries=1)と同根の観測不能性であり、harm 帰属には serve 層の per-qu
    - [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(

### 提案 4 `e52` [NOVEL] (×3)

stance-fidelity 監査(申告 stance が主張の実依存と整合するか検証し refutes 偽装下の暗黙 relies_on・参加ベース過剰連結を棄却)は、truth-grounding と quorum が残すギャップを閉じる次段階レバーである：verify は citation の textual 接地のみ判定し stance の真実性を見ないため、refutes を装い実は relies_on の citation が verify を通過し、X 撤回が下流に伝播せず closure が silent に不完全になる。汚染B下の C5 Precision 0.50 劣化は、無監査の stance 自己申告(extract_citation_stances は申告を記録するのみ)と未引用意味依存への盲目(typed closure の M5 盲点)の経験的確証であり、verify judge を stance-fidelity 判定へ拡張すれば 0.40→1.00 梯子が多型・多著者・汚染B でも崩れず閉包が GT 依存に対し完全化する。

  来歴:
    - [e6] (GOVERNANCE) 次段階の最高レバレッジな governance 改善は『stance 監査 harness』である。理由: citation precision 梯子(0.40→1.00)は統制ケースの上限値にすぎず、私的事実では stance 自己申告は無監査(agent が refutes と言いつつ実は暗黙 
    - [e19] (AGENT) e15 の『consensus は byte 一致 uniq_by(&.text) のみ・per-sample consensus 不在』は、私的事実の retrieval ポリシー平坦さ(served_queries=1)と同根の観測不能性であり、harm 帰属には serve 層の per-qu
    - [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem
    - [e16] (GOVERNANCE) e13 の汚染B下 C5 Precision 0.50 劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)は、統治コアの未測定だった2つの開いた穴—stance 自己申告の無監査(reference.ex:683-696 extract_citation_stance
    - [e5] (SYNTH) 第二の SYNTH 改善は、retrieval 天井を破るより先に findings を production store に persist される first-class な governable entity にすること。現状 consult は静的 JSON を返して終わりで、finding
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる

### 提案 5 `e51` [NOVEL] (×3)

truth-grounding と sample-consensus(quorum)を律速しているのは LLM organ そのものである：H8 で gemma は単発 serve に収束し(multi-step retrieve がポリシー未発火)接地品質を判定できず seed でばらつく。quorum は分岐サンプル(2/3『A→B』対 1/3『A→¬B』)を前提とするが、単発 serve に潰れる organ は分岐そのものを生まず、stance 正当化も honest な多様性を欠いた呪文に堕する。よって機構設計の欠落(uniq_by の byte 一致・verify の textual のみ)を埋める前に、名前付き default 強モデルアダプタ(OpenRouter アダプタは存在するが default 強モデル未指定)と multi-step retrieve の自然発火ポリシーが必要で、これ無しでは quorum 票も stance 正当化も gemma artifact に過ぎない。

  来歴:
    - [e25] (SYNTH) e23 の『自然汚染で precision 0.50 に落ちるため M2b 検証が前提』は正しいが、synth 私的事実から見ると M2b 単独では 1.00 に届かない二つの機構欠落がある: (1)接地ゲートは citation が主張を textual に支持するかだけ判定し現実世界の真偽を見な
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem
    - [e29] (AGENT) e25 の sample-consensus(quorum)も e27 の stance 正当化検証も、ギャップを機構設計の欠落(uniq_by が byte 一致のみ・verify が textual のみ)に帰属させるが、私的事実から見ると両者を律速しているのは LLM organ そのものであ
    - [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ co

### 提案 6 `e50` [NOVEL] (×3)

baseline 比較による限界価値定量は retrieval 天井と相互作用し二重に過小測定される危険がある：synth は connection/expression 段のみ解き retrieval(何を外部化するか)は別の漏れ段で、H2 の ~5-6/10 頭打ちは counterpart 事実が surface に出ない(entry_limit=2/round・serve 分布不均一)ためであり、H8 でも gemma は単発 serve に収束し天井は破れなかった。よって汚染B下 C5 Precision 0.50 への劣化は統治機構固有の弱さだけでなく retrieval-starved な surface 上で接地ゲートが現実真偽でなく textual 支持のみ見る silent 失敗と複合する。moat を opt-in 化する前に retrieval レバー(serve-policy 深さ・entry_limit・multi-step serve 発火)を網羅し surface を統制した条件下で初めて n≥6 Fusion 対比を行わねば、統治も best-of-N も retrieval 漏れに律速された値で比較され sunk cost を増幅する。

  来歴:
    - [e2] (RESEARCH) 最も効果の高い次の一手は、disc_strict の {0,1,2,3} 天井(私的事実: H2高天井~10件でも synth ~5-6/10 で頭打ち=retrieval段の限界)を外す『連続・飽和しない発見メトリクス + 2-3別ドメインでの統計的 n≥6』への投資である。e1 は H1〜H8 
    - [e14] (SYNTH) e11/e13 が moat 選択(統治 vs best-of-N)の前提とする『baseline 比較で限界価値を定量』は、私的事実の retrieval 天井と相互作用して二重に過小測定される危険がある:synth は connection/expression 段のみ解き retrieval(
    - [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(
    - [e23] (RESEARCH) e21 の『governable findings は撤回時の下流依存を提示するクエリ可能な来歴 API とセットで初めて採用価値を持つ』は妥当だが、私的事実と衝突する重要な留保を欠く: 統治 precision=1.00 は合成汚染(汚染A=論理反証可能)でのみ成立し、自然汚染では 0.50(過剰
    - [e11] (ADOPTION) e9 の相互依存条件『主要熟議経路から CLI を除外して serve 接地を純化する』は採用とトレードオフで衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、その認証・binary 可用性・コストが既に adoption 摩擦)、主要
    - [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証

### 提案 7 `e38` [NOVEL] (×3)

controlling closure(e7)と retrieval 監査純化(e9: CLI 内部の web 検索/コード実行で発見が serve 由来か区別不能)を要件化する前に、未決の戦略決断と研究妥当性が衝突を生む: CLI は現状唯一の deploy 経路であり主要経路から外せば deploy 表面そのものが消える一方、統治の中核証拠は汚染A・n=3・単一シナリオ・Fusion 直接対決と異系列ソロ baseline(n≥6)未実施に乗っている。よって統治(撤回閉包)を moat にするか best-of-N 合成(--governance opt-in)を moat にするかは、汚染B 環境で『governance が Fusion に防げない harm を防ぐ』ことを n≥6・複数ドメインで実証して初めて内的妥当性ある根拠で決められる。

  来歴:
    - [e9] (AGENT) e7 が findings を controlling な撤回対象にする監査基盤を serving 経路に通すと宣言するなら、その監査が測る retrieval/grounding 信号自体が汚染されていてはならない。私的事実(問題#3)では CLI(cursor-agent)アダプタは web 検
    - [e11] (ADOPTION) e9 の相互依存条件『主要熟議経路から CLI を除外して serve 接地を純化する』は採用とトレードオフで衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、その認証・binary 可用性・コストが既に adoption 摩擦)、主要
    - [e12] (RESEARCH) e9 の『CLI 内部ツール(web検索/コード実行)で発見が serve 由来か区別不能』という相互依存条件は、研究妥当性上の決定的な交絡として正しいが、これは私的事実の H8 知見(tool-use の価値は来歴精度であって発見でない、structured citation で groundin
    - [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証
    - [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ co
    - [e7] (GOVERNANCE) 第二の改善は serving findings を撤回閉包の first-class 対象にし、かつ synth が閉包 status を尊重することの両方を要件化することだ。e5 の指摘(findings は serve 後 closure の外で layer-0 撤回が隔離されない)に依拠するが

### 提案 8 `e80` [NOVEL] (×5)

governable findings を採用価値あるものにする『撤回時の下流依存を提示するクエリ可能な来歴API』は、ADOPTION視点では viz コスト問題に見えるが、その前に二つの未計上ブロッカーがある:(1)substrate自体の欠如—consult は静的JSONを返すのみで findings は production store に persist されず撤回イベントが適用されない(再合成・監査・依存影響クエリ不可)ため、API は viz より上流の永続化変更が前提。(2)未検証 substrate 上での出荷リスク—precision=1.00 は合成汚染Aでのみ成立し自然汚染では 0.50(過剰連結)に落ちるため、依存影響API を出荷すると偽の依存アラートを可視化し統治の信頼性主張そのものを毀損する。さらに可視化は retrieval天井(H2高天井でも synth~5-6/10頭打ち)を解消しない。よって統治を moat にする戦略判断は、viz コストだけでなく永続化コストと自然汚染下 precision を 1.00 に近づける M2b検証コストを上流ブロッカーとして織り込むべきである。

  来歴:
    - [e21] (ADOPTION) e17 が認める『永続化された汚染リンクは伝播対象を増やすだけで過剰連結(e13)を防がない』というトレードオフは、製品面では『撤回しても他の何が依存するかのアラートが無く来歴がクエリ不可』という私的事実と同じ穴に帰着する: governable な findings ノード(e17)を作っても、そ
    - [e23] (RESEARCH) e21 の『governable findings は撤回時の下流依存を提示するクエリ可能な来歴 API とセットで初めて採用価値を持つ』は妥当だが、私的事実と衝突する重要な留保を欠く: 統治 precision=1.00 は合成汚染(汚染A=論理反証可能)でのみ成立し、自然汚染では 0.50(過剰
    - [e24] (SYNTH) e21 が採用条件とする『クエリ可能な来歴 API』は viz コストの問題に見えるが、ADOPTION には見えない synth 私的事実によって substrate 自体が欠けている: consult は静的 JSON を返して終わりで、findings は production store に
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat

### 提案 9 `e79` [NOVEL] (×4)

e7/e9/e17 が要件化する『findings を controlling な撤回対象にし serving経路へ一貫させる』対象の serving表面に、現状どの実チームも到達できないという到達可能性ブロッカーが全計画の手前にある:consult の run_consult は Dissolution.default_agents() で agent を SEC/BIZ/UX に固定し load_private_docs は sec/biz/ux.md を固定名で要求し Scenario.load! は harness用 contaminant-A.md/correction-A.md を必須とする(fsl-brushup はこれを回避するため ~146行の custom run.exs で consult を捨て cursor CLI を直叩きした)。よって per-query provenance復元も findings昇格も stance検証も、固定3観点・固定ファイル名・harness結合の足場を払い『task+任意docs+任意agents→governed findings』のクリーンな入力API を先に切らない限り、実チームの PR/設計レビューで起動できず controlling化は到達されない論点に留まり、harm計測の母数も研究シナリオに限定される。

  来歴:
    - [e10] (ADOPTION) e7とe9はfindingsを controlling な撤回対象にし retrieval を監査して serving 経路に一貫させよと要件化するが、その対象の serving 表面は現状どの実チームも到達できない:私的事実かつコード上、consult の run_consult は Dissol
    - [e19] (AGENT) e15 の『consensus は byte 一致 uniq_by(&.text) のみ・per-sample consensus 不在』は、私的事実の retrieval ポリシー平坦さ(served_queries=1)と同根の観測不能性であり、harm 帰属には serve 層の per-qu
    - [e20] (ADOPTION) e19 が示す prose 経路の provenance 欠落(serve は単発・served_queries 非保存)と e17 が要求する findings の governable 化は、いずれも consult serving 経路への投資を前提とするが、私的事実と矛盾する: その唯一の 
    - [e28] (AGENT) e27 の stance-audit(Reference が各 stance の正当化を検証し refutes の偽装を捕捉する)は機構として正しいが、それが監査する『stance』という信号自体が支配的 serving 経路に存在しないという substrate 前提を見落としている。私的事実: 
    - [e24] (SYNTH) e21 が採用条件とする『クエリ可能な来歴 API』は viz コストの問題に見えるが、ADOPTION には見えない synth 私的事実によって substrate 自体が欠けている: consult は静的 JSON を返して終わりで、findings は production store に
    - [e31] (ADOPTION) e27's stance-audit step deepens governable closure but, from the adoption lens, it directly compounds the friction that already blocks real teams: it 

### 提案 10 `e81` [NOVEL] (×3)

stance-audit step(Reference が各stanceの正当化を検証し refutes偽装を捕捉)を default closure に積むことは、機構として正しくとも採用摩擦を直接悪化させる:既に measured な $1-3/20-40s・Opus-judge依存(gemma が grounding を誤判定するため consult は Opus judge を必須化)の上にもう一段 Opus pass を加え、固定3観点で clean API を欠く path を重くする。governance は条件依存(agent が少なく claim が浅い時は単発Opus+軽い人間レビューで足り payoff閾値は未定量)であり、かつ強organ にしても plain-strong-model best-of-N baseline が無いため pooling/governance が単発Opus を上回る限界価値は未測定のまま残る。よって stance-audit と closure は --governance として opt-in にゲートし、次段階は judging層を積むより stance-honesty監査が人間レビューを上回る閾値の定量に充てるべきである。

  来歴:
    - [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ co
    - [e31] (ADOPTION) e27's stance-audit step deepens governable closure but, from the adoption lens, it directly compounds the friction that already blocks real teams: it 
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem

### 提案 11 `e70` [NOVEL] (×2)

e1の『接地 precision 0.40→1.00 で守りは確立』という主張は統制環境(合成汚染A=論理反証可能・design-time GT・deterministic Mock verify)の上限値にすぎない。複数領域の私的事実が収束して同一の故障面を指す:VALIDITY側では自然な採用可能汚染B(PM証言)で C5 Precision が 0.50 に劣化(depends_on_turns が意味的真理依存でなく『参加』を参照する過剰連結)、permissive汚染Cは stance-anchor judge を壊しカバレッジ=0。SYNTH側では接地ゲートが citation の textual 支持のみ見て現実真偽を見ず(『暗号化済』を引く layer-0 は暗号化が偽でも接地が立つ)、union が byte一致 uniq_by のみで A→B と A→¬B を quorum無しに両載せする。GOVERNANCE側では stance 自己申告が無監査。よって governance の核心主張は運用妥当性が未証明であり、これを閉じることが Fusion 差別化(governance が防ぐ harm の実証)の前提である。

  来歴:
    - [e2] (RESEARCH) 最も効果の高い次の一手は、disc_strict の {0,1,2,3} 天井(私的事実: H2高天井~10件でも synth ~5-6/10 で頭打ち=retrieval段の限界)を外す『連続・飽和しない発見メトリクス + 2-3別ドメインでの統計的 n≥6』への投資である。e1 は H1〜H8 
    - [e3] (RESEARCH) 第二の最重要改善は、まだ走っていない決定的実験 M2b(実探索 B型=採用可能汚染 + stance+verify フルスタックを harness で)と permissive(C型: 否定形『問題なし』)汚染の防御を埋めることだ。e1 は『守り=citation接地 precision 0.40→
    - [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat
    - [e4] (SYNTH) 最高レバーの SYNTH 改善は、synth 合成層に (a)サンプル間 quorum/voting と (b)真偽接地シグナルを first-class で入れること。現状 union は Enum.uniq_by(&.text) の byte 一致のみで、2/3 が「A→B」1/3 が「A→¬B
    - [e6] (GOVERNANCE) 次段階の最高レバレッジな governance 改善は『stance 監査 harness』である。理由: citation precision 梯子(0.40→1.00)は統制ケースの上限値にすぎず、私的事実では stance 自己申告は無監査(agent が refutes と言いつつ実は暗黙 
    - [e16] (GOVERNANCE) e13 の汚染B下 C5 Precision 0.50 劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)は、統治コアの未測定だった2つの開いた穴—stance 自己申告の無監査(reference.ex:683-696 extract_citation_stance
    - [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(

### 提案 12 `e45` [NOVEL] (×2)

findings の観測可能性が原理的に欠如している：findings は verified:true の bool のみを返し、『3サンプル中2で発見』『judge 信頼度』『どの citation がどの layer-0 に接地したか』を露出しない。harm 防止を判定するには per-sample consensus・接地証跡・撤回後の再評価が必須であり、これらが無い限り『Fusion に防げない harm を防ぐ』実証(harm の定義と計測)自体が成立しない。よって findings の governable entity 化(consensus/confidence 外部化・persist・撤回閉包適用)が moat 選択を測定可能にする最優先の前提である。

  来歴:
    - [e5] (SYNTH) 第二の SYNTH 改善は、retrieval 天井を破るより先に findings を production store に persist される first-class な governable entity にすること。現状 consult は静的 JSON を返して終わりで、finding
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる
    - [e17] (GOVERNANCE) e15 の『findings は verified:true bool のみ・byte一致 consensus・production store 非persist・撤回非適用の非 first-class entity』は、私の開いた問題『層をまたぐ説明責任—synth が閉包 status を無視す
    - [e7] (GOVERNANCE) 第二の改善は serving findings を撤回閉包の first-class 対象にし、かつ synth が閉包 status を尊重することの両方を要件化することだ。e5 の指摘(findings は serve 後 closure の外で layer-0 撤回が隔離されない)に依拠するが
    - [e24] (SYNTH) e21 が採用条件とする『クエリ可能な来歴 API』は viz コストの問題に見えるが、ADOPTION には見えない synth 私的事実によって substrate 自体が欠けている: consult は静的 JSON を返して終わりで、findings は production store に

### 提案 13 `e47` [NOVEL] (×1)

prose 経路では retrieval provenance が破棄され harm 発生経路を再構成できない：serve は単発(serve.ex:16-33)で再 serve ループが無く、prose の perception_log は served_queries を残さず(tools 経路のみ record_tool_result で蓄積)、query↔served の対応そのものが破棄される。よって findings を persist しても上流 retrieval provenance が欠ければ harm 発生経路は不明のまま残り、これは決定的だが未実施の M2b の前提条件でもある。findings governable 化は、prose 経路でも served_queries を計測し serve↔finding 接地経路を保存する agent 層改修と対で行わねばならない。

  来歴:
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる
    - [e19] (AGENT) e15 の『consensus は byte 一致 uniq_by(&.text) のみ・per-sample consensus 不在』は、私的事実の retrieval ポリシー平坦さ(served_queries=1)と同根の観測不能性であり、harm 帰属には serve 層の per-qu
    - [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(

### 提案 14 `e75` [NOVEL] (×3)

H8知見『tool-useの価値は来歴精度であって発見でなく、可視で監査済みのツール経路を前提に grounding +48% だが disc は flat』は、CLI(cursor-agent)アダプタが web検索/コード実行など不可視の内部ツールを持つことと直接干渉する:CLI熟議では発見が tracefield serve由来か CLI内部ツール由来か区別不能で、served_queries=1 の retrieval平坦さが tracefield の retrieval段の限界か CLI内部解決の代替かを切り分け不能にする。これは『単一基盤・prompt-level merge では inference API を超えた状態共有は届かない』と M2b未実施の交点に新たな交絡源を追加する。よって主要熟議経路を CLI除外する前に、内部ツール ON/OFF を独立変数とした統制実験(serve接地純度を従属変数)で交絡を分離測定すべきで、これ無しの『純化』は反証可能性を欠く手続き的主張に留まる。

  来歴:
    - [e9] (AGENT) e7 が findings を controlling な撤回対象にする監査基盤を serving 経路に通すと宣言するなら、その監査が測る retrieval/grounding 信号自体が汚染されていてはならない。私的事実(問題#3)では CLI(cursor-agent)アダプタは web 検
    - [e12] (RESEARCH) e9 の『CLI 内部ツール(web検索/コード実行)で発見が serve 由来か区別不能』という相互依存条件は、研究妥当性上の決定的な交絡として正しいが、これは私的事実の H8 知見(tool-use の価値は来歴精度であって発見でない、structured citation で groundin

### 提案 15 `e56` [NOVEL] (×1)

M2b は『precision が規模で保つか』だけでなく judge-model 不忠実由来の過剰連結率を測らねばならない：precision の 1.00 は設計時GT＋決定的Mock verify の統制ケースアーティファクトであり、自然汚染下の 0.50 への低下は lenient verify が surface overlap を grounds と取り違える H6 監査ギャップが機構的原因である。弱い local judge(gemma)は verify JSON を誤パースして false-positive citation を再導入し、依存影響 API が依拠する closure を崩壊させる。未検証 substrate 上にその API を出荷すれば偽の依存アラートを可視化し、これが名指しされた統治信頼性リスクである。

  来歴:
    - [e23] (RESEARCH) e21 の『governable findings は撤回時の下流依存を提示するクエリ可能な来歴 API とセットで初めて採用価値を持つ』は妥当だが、私的事実と衝突する重要な留保を欠く: 統治 precision=1.00 は合成汚染(汚染A=論理反証可能)でのみ成立し、自然汚染では 0.50(過剰
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat

### 提案 16 `e58` [NOVEL] (×1)

統治の核心証拠『precision 0.40→1.00』は統制環境(合成汚染A=論理反証可能・design-time GT・決定的Mock verify)の上限値にすぎず、自然な採用可能汚染B(PM証言)では C5 Precision が 0.50 に劣化する。原因は depends_on_turns が意味的真理依存でなく『参加』を参照する過剰連結であり、これは複数領域の私的事実が独立に一致して指す同一故障面である。よって統治の運用妥当性・外的妥当性・構成概念妥当性はいずれも未閉で、e1 の『守りは確立済』は統制上限値の主張に留まる。

  来歴:
    - [e2] (RESEARCH) 最も効果の高い次の一手は、disc_strict の {0,1,2,3} 天井(私的事実: H2高天井~10件でも synth ~5-6/10 で頭打ち=retrieval段の限界)を外す『連続・飽和しない発見メトリクス + 2-3別ドメインでの統計的 n≥6』への投資である。e1 は H1〜H8 
    - [e3] (RESEARCH) 第二の最重要改善は、まだ走っていない決定的実験 M2b(実探索 B型=採用可能汚染 + stance+verify フルスタックを harness で)と permissive(C型: 否定形『問題なし』)汚染の防御を埋めることだ。e1 は『守り=citation接地 precision 0.40→
    - [e6] (GOVERNANCE) 次段階の最高レバレッジな governance 改善は『stance 監査 harness』である。理由: citation precision 梯子(0.40→1.00)は統制ケースの上限値にすぎず、私的事実では stance 自己申告は無監査(agent が refutes と言いつつ実は暗黙 
    - [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証
    - [e16] (GOVERNANCE) e13 の汚染B下 C5 Precision 0.50 劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)は、統治コアの未測定だった2つの開いた穴—stance 自己申告の無監査(reference.ex:683-696 extract_citation_stance
    - [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat

### 提案 17 `e61` [NOVEL] (×1)

サンプル間コンセンサスが Enum.uniq_by(&.text) の byte 一致のみで、2/3『A→B』対 1/3『A→¬B』を voting/quorum 無しに両載せする欠陥は、quorum 票を findings に露出する synth レバーを要求する。だが quorum はそもそも分岐サンプルの存在を前提とし、LLM organ(gemma)が単発 serve に収束して分岐を生まない以上、機構設計の修正だけでは不十分で、named default 強モデルアダプタと multi-step retrieve の自然発火ポリシーが律速前提となる。

  来歴:
    - [e4] (SYNTH) 最高レバーの SYNTH 改善は、synth 合成層に (a)サンプル間 quorum/voting と (b)真偽接地シグナルを first-class で入れること。現状 union は Enum.uniq_by(&.text) の byte 一致のみで、2/3 が「A→B」1/3 が「A→¬B
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる
    - [e25] (SYNTH) e23 の『自然汚染で precision 0.50 に落ちるため M2b 検証が前提』は正しいが、synth 私的事実から見ると M2b 単独では 1.00 に届かない二つの機構欠落がある: (1)接地ゲートは citation が主張を textual に支持するかだけ判定し現実世界の真偽を見な
    - [e29] (AGENT) e25 の sample-consensus(quorum)も e27 の stance 正当化検証も、ギャップを機構設計の欠落(uniq_by が byte 一致のみ・verify が textual のみ)に帰属させるが、私的事実から見ると両者を律速しているのは LLM organ そのものであ
    - [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ co

### 提案 18 `e68` [NOVEL] (×1)

weak local judge(gemma)は verify JSON を誤読して false-positive citation を再導入し過剰連結率を上げるため、consult は Opus judge を必須とする。これが measured $1-3/20-40s のコストと Opus 依存を生み、stance-audit を default closure に積めば固定3観点経路の摩擦をさらに悪化させる。統治は条件依存(agent 少数・主張浅薄なら単発 Opus+軽い人間レビューで足り、payoff 閾値は未定量)であるため、closure と stance-audit は --governance として opt-in 化し、次段階は強モデル化や監査層追加でなく『plain 強モデル best-of-N baseline』で統治/プーリングの限界価値を定量することを優先すべきである。

  来歴:
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat
    - [e29] (AGENT) e25 の sample-consensus(quorum)も e27 の stance 正当化検証も、ギャップを機構設計の欠落(uniq_by が byte 一致のみ・verify が textual のみ)に帰属させるが、私的事実から見ると両者を律速しているのは LLM organ そのものであ
    - [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ co
    - [e31] (ADOPTION) e27's stance-audit step deepens governable closure but, from the adoption lens, it directly compounds the friction that already blocks real teams: it 

### 提案 19 `e71` [NOVEL] (×1)

自然汚染B下で precision を 1.00 に近づけるには、まだ走っていない決定的実験 M2b(実探索B型汚染+stance+verifyフルスタックを harness で)単独では不十分で、互いに直交する複数機構の同時修復が必要である:(1)接地ゲートを textual-support から claim-truth 照合へ昇格(現実真偽を見ないため合成汚染と自然汚染を原理的に区別できず lenient verify 単独は過剰連結を見逃す)、(2)サンプル間 quorum/voting を first-class 化(uniq_by の byte一致では分岐サンプルを両載せ)、(3)申告 stance が主張の実依存と整合するかを検証する stance-fidelity(refutes 申告下の暗黙 relies_on・参加ベース over-connection の検出)。これら3つは serving層と reference層に跨る同型の欠陥であり、依存影響API の信頼性を支える未解決レバーとして M2b と直接噛み合う。

  来歴:
    - [e3] (RESEARCH) 第二の最重要改善は、まだ走っていない決定的実験 M2b(実探索 B型=採用可能汚染 + stance+verify フルスタックを harness で)と permissive(C型: 否定形『問題なし』)汚染の防御を埋めることだ。e1 は『守り=citation接地 precision 0.40→
    - [e4] (SYNTH) 最高レバーの SYNTH 改善は、synth 合成層に (a)サンプル間 quorum/voting と (b)真偽接地シグナルを first-class で入れること。現状 union は Enum.uniq_by(&.text) の byte 一致のみで、2/3 が「A→B」1/3 が「A→¬B
    - [e16] (GOVERNANCE) e13 の汚染B下 C5 Precision 0.50 劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)は、統治コアの未測定だった2つの開いた穴—stance 自己申告の無監査(reference.ex:683-696 extract_citation_stance
    - [e25] (SYNTH) e23 の『自然汚染で precision 0.50 に落ちるため M2b 検証が前提』は正しいが、synth 私的事実から見ると M2b 単独では 1.00 に届かない二つの機構欠落がある: (1)接地ゲートは citation が主張を textual に支持するかだけ判定し現実世界の真偽を見な
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem

### 提案 20 `e73` [NOVEL] (×1)

撤回閉包の伝播は serving 境界を跨がず(逆citation index はグラフ内のみ伝播)、findings は serve後に閉包の外で隔離されない。これを controlling な governance にするには二条件が必要:findings を撤回対象として persist する(e5)だけでは不十分で、合成層が reopen を『新候補生成』でなく『上流訂正下の既存findings再評価＋能動的未提供化』と解さねば governance は advisory に留まる(H6 層またぎ説明責任)。ただし e17 が認めるトレードオフ通り、永続化された汚染リンクは伝播対象を増やすだけで過剰連結を防がないため、first-class化の上に stance-fidelity 検証を載せる順序が必須である。

  来歴:
    - [e5] (SYNTH) 第二の SYNTH 改善は、retrieval 天井を破るより先に findings を production store に persist される first-class な governable entity にすること。現状 consult は静的 JSON を返して終わりで、finding
    - [e7] (GOVERNANCE) 第二の改善は serving findings を撤回閉包の first-class 対象にし、かつ synth が閉包 status を尊重することの両方を要件化することだ。e5 の指摘(findings は serve 後 closure の外で layer-0 撤回が隔離されない)に依拠するが
    - [e17] (GOVERNANCE) e15 の『findings は verified:true bool のみ・byte一致 consensus・production store 非persist・撤回非適用の非 first-class entity』は、私の開いた問題『層をまたぐ説明責任—synth が閉包 status を無視す

### 提案 21 `e76` [NOVEL] (×1)

『主要熟議経路から CLI を除外して serve接地を純化せよ』という研究妥当性上の要件は、採用戦略と正面衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、認証・binary可用性・コストが既に adoption摩擦)、主要経路から外せば実利用の deploy表面そのものが消える。これは未決の moat 選択(統治=撤回閉包を moat にするか、任意文脈で単発に勝つ best-of-N合成を moat にするか)を controlling要件が先取りしている問題であり、前者なら CLI除去・監査コストは正当化されるが niche に閉じ、後者なら統治を default から外し --governance を opt-in 化する方が採用は伸びる。

  来歴:
    - [e9] (AGENT) e7 が findings を controlling な撤回対象にする監査基盤を serving 経路に通すと宣言するなら、その監査が測る retrieval/grounding 信号自体が汚染されていてはならない。私的事実(問題#3)では CLI(cursor-agent)アダプタは web 検
    - [e11] (ADOPTION) e9 の相互依存条件『主要熟議経路から CLI を除外して serve 接地を純化する』は採用とトレードオフで衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、その認証・binary 可用性・コストが既に adoption 摩擦)、主要

### 提案 22 `e77` [NOVEL] (×1)

moat 選択(統治 vs best-of-N)を駆動する『統治の限界価値』は現状のエビデンスでは原理的に未測定であり、二重三重の前提が未充足である:(1)統治の中核証拠(C5 Impact Recall 1.00)は合成汚染Aに限られ自然汚染Bでは Precision 0.50 に劣化、Fusion直接対決も異系列ソロ baseline(n≥6)も plain-strong-model best-of-N baseline も未実施。(2)この限界価値は retrieval天井と複合し二重に過小測定される(synthはconnection/expression段のみ解き retrievalは別の漏れ段、H2の~5-6/10頭打ちは counterpart事実が surface に出ず entry_limit=2/round・serve分布不均一)。(3)harm防止の判定に必須の per-sample consensus・接地証跡・撤回後再評価が serving観測可能性として欠如。よって opt-in化を決める前に、retrievalレバーで surface を統制し findings を governable化した上で、汚染B環境の Fusion対比で n≥6・複数ドメインの harm実証を行わない限り、moat選択そのものが内的妥当性を欠く根拠で行われ sunk cost を増幅する。

  来歴:
    - [e11] (ADOPTION) e9 の相互依存条件『主要熟議経路から CLI を除外して serve 接地を純化する』は採用とトレードオフで衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、その認証・binary 可用性・コストが既に adoption 摩擦)、主要
    - [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証
    - [e14] (SYNTH) e11/e13 が moat 選択(統治 vs best-of-N)の前提とする『baseline 比較で限界価値を定量』は、私的事実の retrieval 天井と相互作用して二重に過小測定される危険がある:synth は connection/expression 段のみ解き retrieval(
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる
    - [e23] (RESEARCH) e21 の『governable findings は撤回時の下流依存を提示するクエリ可能な来歴 API とセットで初めて採用価値を持つ』は妥当だが、私的事実と衝突する重要な留保を欠く: 統治 precision=1.00 は合成汚染(汚染A=論理反証可能)でのみ成立し、自然汚染では 0.50(過剰
    - [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ co

### 提案 23 `e82` [NOVEL] (×1)

The governance precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT, synthetic logically-refutable contamination A, deterministic Mock verify), not an operational property: under natural adoptable contamination B it collapses to C5 Precision ~0.50 via over-connection (depends_on_turns references participation, not semantic truth). This is independently confirmed from four domains—validity (n=3/single-scenario/ceiling effect), synth (lenient verify checks textual support, not real-world truth), governance (stance self-report is unaudited), and judge-model (weak gemma misparses verify JSON, re-introducing false-positive citations). Closing this gap (M2b real-exploration B + permissive C defense at n>=6 across domains) is the precondition for the Fusion differentiation claim that governance prevents harm Fusion cannot.

  来歴:
    - [e2] (RESEARCH) 最も効果の高い次の一手は、disc_strict の {0,1,2,3} 天井(私的事実: H2高天井~10件でも synth ~5-6/10 で頭打ち=retrieval段の限界)を外す『連続・飽和しない発見メトリクス + 2-3別ドメインでの統計的 n≥6』への投資である。e1 は H1〜H8 
    - [e3] (RESEARCH) 第二の最重要改善は、まだ走っていない決定的実験 M2b(実探索 B型=採用可能汚染 + stance+verify フルスタックを harness で)と permissive(C型: 否定形『問題なし』)汚染の防御を埋めることだ。e1 は『守り=citation接地 precision 0.40→
    - [e6] (GOVERNANCE) 次段階の最高レバレッジな governance 改善は『stance 監査 harness』である。理由: citation precision 梯子(0.40→1.00)は統制ケースの上限値にすぎず、私的事実では stance 自己申告は無監査(agent が refutes と言いつつ実は暗黙 
    - [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証
    - [e16] (GOVERNANCE) e13 の汚染B下 C5 Precision 0.50 劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)は、統治コアの未測定だった2つの開いた穴—stance 自己申告の無監査(reference.ex:683-696 extract_citation_stance
    - [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat

### 提案 24 `e83` [NOVEL] (×1)

The same over-connection defect appears identically in the retrieval/reference layer (C5 over-connection: citation references participation not semantic truth) and the serving/synth layer (union is Enum.uniq_by(&.text) byte-match only with no quorum, and the grounding gate only checks textual support of a citation, never claim-truth—so citing a layer-0 'encrypted' claim grounds even when encryption is false). The fix must therefore be dual: expose quorum vote counts on findings AND promote verify from textual-support to claim-truth checking, which directly meshes with the M2b/permissive defense.

  来歴:
    - [e3] (RESEARCH) 第二の最重要改善は、まだ走っていない決定的実験 M2b(実探索 B型=採用可能汚染 + stance+verify フルスタックを harness で)と permissive(C型: 否定形『問題なし』)汚染の防御を埋めることだ。e1 は『守り=citation接地 precision 0.40→
    - [e4] (SYNTH) 最高レバーの SYNTH 改善は、synth 合成層に (a)サンプル間 quorum/voting と (b)真偽接地シグナルを first-class で入れること。現状 union は Enum.uniq_by(&.text) の byte 一致のみで、2/3 が「A→B」1/3 が「A→¬B
    - [e25] (SYNTH) e23 の『自然汚染で precision 0.50 に落ちるため M2b 検証が前提』は正しいが、synth 私的事実から見ると M2b 単独では 1.00 に届かない二つの機構欠落がある: (1)接地ゲートは citation が主張を textual に支持するかだけ判定し現実世界の真偽を見な

### 提案 25 `e84` [NOVEL] (×1)

Truth-grounding plus sample-consensus (quorum) plus M2b are necessary but insufficient for governable closure, because all of them only audit textual/voting agreement and none audit stance honesty: a self-reported 'refutes' hiding an implicit relies_on passes verify (which checks citation grounding, not stance truthfulness), so retraction never propagates downstream and closure is silently incomplete. A stance-fidelity audit step—where the Reference makes agents justify each stance and verifies the justification against the claim's real dependency—is the additional lever that quorum and truth-grounding leave open.

  来歴:
    - [e6] (GOVERNANCE) 次段階の最高レバレッジな governance 改善は『stance 監査 harness』である。理由: citation precision 梯子(0.40→1.00)は統制ケースの上限値にすぎず、私的事実では stance 自己申告は無監査(agent が refutes と言いつつ実は暗黙 
    - [e16] (GOVERNANCE) e13 の汚染B下 C5 Precision 0.50 劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)は、統治コアの未測定だった2つの開いた穴—stance 自己申告の無監査(reference.ex:683-696 extract_citation_stance
    - [e25] (SYNTH) e23 の『自然汚染で precision 0.50 に落ちるため M2b 検証が前提』は正しいが、synth 私的事実から見ると M2b 単独では 1.00 に届かない二つの機構欠落がある: (1)接地ゲートは citation が主張を textual に支持するかだけ判定し現実世界の真偽を見な
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem

### 提案 26 `e85` [NOVEL] (×1)

Making findings a first-class governable entity has a strict ordering dependency that several proposals get wrong: persisting findings with consensus/grounding metadata into the production store and subjecting them to the retraction closure (e5/e15) must come FIRST, but is insufficient because persisting contaminated links only enlarges the propagation set without preventing over-connection; stance-fidelity verification (e16/e27) must then be applied on the grounding trail. The correct order is promote-to-closure-node THEN stance-audit, otherwise the e13 'harm Fusion cannot prevent' demonstration gets a consensus trail but remains imprecise and unmeasurable.

  来歴:
    - [e5] (SYNTH) 第二の SYNTH 改善は、retrieval 天井を破るより先に findings を production store に persist される first-class な governable entity にすること。現状 consult は静的 JSON を返して終わりで、finding
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる
    - [e17] (GOVERNANCE) e15 の『findings は verified:true bool のみ・byte一致 consensus・production store 非persist・撤回非適用の非 first-class entity』は、私の開いた問題『層をまたぐ説明責任—synth が閉包 status を無視す

### 提案 27 `e86` [NOVEL] (×1)

The retraction-closure 'controlling vs advisory' requirement has substrate prerequisites that are missed if findings persistence is done alone: (a) synth survivors carry citations via Map.take but no stance, and Reference defaults missing ids to relies_on (citation_stance_for:906-916), so a synth finding's grounding trail cannot distinguish 'true relies_on' from 'default relies_on'—stance must be emitted/persisted with synth citations BEFORE stance-fidelity audit can do more than measure a default baseline; and (b) synth must reinterpret 'reopen' as active re-evaluation + un-serving of existing findings under upstream correction, not new-candidate generation, or governance stays advisory. Without both, closure_action collapses to the relies_on path and the harm-attribution e13 needs stays unmeasurable.

  来歴:
    - [e7] (GOVERNANCE) 第二の改善は serving findings を撤回閉包の first-class 対象にし、かつ synth が閉包 status を尊重することの両方を要件化することだ。e5 の指摘(findings は serve 後 closure の外で layer-0 撤回が隔離されない)に依拠するが
    - [e8] (AGENT) e5/e7 が要求する『どの citation がどの layer-0 に接地したか』『quorum メタデータ』を持つ governable findings は、その下層の citation グラフが stance を保持していて初めて撤回閉包が正しく伝播する。だが私的事実(問題#4)では pr
    - [e18] (AGENT) e15/e17 が findings を first-class governable entity 化し撤回閉包＋stance-fidelity 検証を載せる計画は、agent-llm 層に未解決の前提欠陥があり、その順序では harm 帰属に届かない。私的事実とコードで確認: (a) synth

### 提案 28 `e87` [NOVEL] (×1)

Per-query serve provenance is a missing substrate beneath findings governance: serve is single-shot with no re-serve loop (serve.ex:16-33, agent.ex:83-89), and the prose deliberation path (the consult default) discards query<->served correspondence entirely (perception_log:247-256 records no served_queries), while only the tools path accumulates them (record_tool_result agent.ex:466-474). So even if findings are persisted, the 'which citation grounded to which layer-0' trail cannot be reconstructed in prose, the served_queries=1 retrieval flatness cannot be diagnosed, and M2b harm-attribution stays confounded. Measuring served_queries in the prose path and preserving serve<->finding grounding is a co-requisite of findings governable-ization.

  来歴:
    - [e5] (SYNTH) 第二の SYNTH 改善は、retrieval 天井を破るより先に findings を production store に persist される first-class な governable entity にすること。現状 consult は静的 JSON を返して終わりで、finding
    - [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる
    - [e19] (AGENT) e15 の『consensus は byte 一致 uniq_by(&.text) のみ・per-sample consensus 不在』は、私的事実の retrieval ポリシー平坦さ(served_queries=1)と同根の観測不能性であり、harm 帰属には serve 層の per-qu
    - [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(

### 提案 29 `e88` [NOVEL] (×1)

Every serving-layer investment (per-query provenance, findings governable-ization, stance audit, queryable lineage API) is blocked by a reachability prerequisite that contradicts the assumption real teams can run these paths: the sole consumer entry mix tracefield.consult is hard-wired to Dissolution.default_agents (SEC/BIZ/UX), fixed doc filenames (sec/biz/ux.md), and harness-coupled Scenario.load! (contaminant-A/correction-A.md required), forcing fsl-brushup to discard consult and hand-roll ~146 lines hitting the CLI directly. A clean 'task + arbitrary docs + arbitrary agents -> governed findings' config-driven API must be cut FIRST, or controlling governance and retrieval purification remain unreachable for any real PR/design-review.

  来歴:
    - [e10] (ADOPTION) e7とe9はfindingsを controlling な撤回対象にし retrieval を監査して serving 経路に一貫させよと要件化するが、その対象の serving 表面は現状どの実チームも到達できない:私的事実かつコード上、consult の run_consult は Dissol
    - [e17] (GOVERNANCE) e15 の『findings は verified:true bool のみ・byte一致 consensus・production store 非persist・撤回非適用の非 first-class entity』は、私の開いた問題『層をまたぐ説明責任—synth が閉包 status を無視す
    - [e19] (AGENT) e15 の『consensus は byte 一致 uniq_by(&.text) のみ・per-sample consensus 不在』は、私的事実の retrieval ポリシー平坦さ(served_queries=1)と同根の観測不能性であり、harm 帰属には serve 層の per-qu
    - [e20] (ADOPTION) e19 が示す prose 経路の provenance 欠落(serve は単発・served_queries 非保存)と e17 が要求する findings の governable 化は、いずれも consult serving 経路への投資を前提とするが、私的事実と矛盾する: その唯一の 

### 提案 30 `e89` [NOVEL] (×1)

There is a direct contradiction between two co-requisites: e9 demands excluding the CLI from the main deliberation path to purify serve grounding (its invisible web-search/code-exec tools make findings' origin—tracefield serve vs CLI internal tool—indistinguishable and confound served_queries=1 flatness), but the CLI (cursor-agent) is currently the ONLY deploy path; removing it deletes the actual deployment surface and worsens adoption friction (auth, binary availability, cost). This forces an as-yet-undecided strategic moat choice (retraction-governance vs opt-in best-of-N synthesis) BEFORE the CLI-exclusion/audit costs can be justified, and the confound itself should be measured via an internal-tools ON/OFF controlled experiment rather than asserted by procedural 'purification'.

  来歴:
    - [e9] (AGENT) e7 が findings を controlling な撤回対象にする監査基盤を serving 経路に通すと宣言するなら、その監査が測る retrieval/grounding 信号自体が汚染されていてはならない。私的事実(問題#3)では CLI(cursor-agent)アダプタは web 検
    - [e11] (ADOPTION) e9 の相互依存条件『主要熟議経路から CLI を除外して serve 接地を純化する』は採用とトレードオフで衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、その認証・binary 可用性・コストが既に adoption 摩擦)、主要
    - [e12] (RESEARCH) e9 の『CLI 内部ツール(web検索/コード実行)で発見が serve 由来か区別不能』という相互依存条件は、研究妥当性上の決定的な交絡として正しいが、これは私的事実の H8 知見(tool-use の価値は来歴精度であって発見でない、structured citation で groundin

### 提案 31 `e90` [NOVEL] (×1)

The H8 finding (tool-use value is provenance precision not discovery; structured citation gives +48% grounding but disc is flat) was established on VISIBLE audited tool paths, which directly conflicts with e9's CLI having INVISIBLE internal tools; this adds a new confound source at the intersection of the unclosed 'prompt-level merge cannot share state beyond the inference API' threat and the unrun M2b. CLI-purification is therefore non-falsifiable unless internal-tools is made an independent variable with serve-grounding purity as the dependent variable.

  来歴:
    - [e9] (AGENT) e7 が findings を controlling な撤回対象にする監査基盤を serving 経路に通すと宣言するなら、その監査が測る retrieval/grounding 信号自体が汚染されていてはならない。私的事実(問題#3)では CLI(cursor-agent)アダプタは web 検
    - [e12] (RESEARCH) e9 の『CLI 内部ツール(web検索/コード実行)で発見が serve 由来か区別不能』という相互依存条件は、研究妥当性上の決定的な交絡として正しいが、これは私的事実の H8 知見(tool-use の価値は来歴精度であって発見でない、structured citation で groundin

### 提案 32 `e91` [NOVEL] (×1)

Quorum (sample-consensus) and stance-justification both presuppose branching samples (e.g. 2/3 'A->B' vs 1/3 'A->not-B'), but the LLM organ itself is the rate-limiter: gemma collapses to single-shot serve (6 serve/6 turn, multi-step retrieve never fires), cannot judge grounding, and varies by seed (disc 4,4,1 sd1.73)—so it never generates the branching the mechanisms assume, and stance-justification degrades into incantation. The synth/governance-invisible prerequisite is a named default strong-model adapter (OpenRouter adapter exists but no default strong model is specified) plus natural-firing multi-step-retrieve policy; without these, quorum votes and stance justifications are gemma artifacts and govern nothing.

  来歴:
    - [e25] (SYNTH) e23 の『自然汚染で precision 0.50 に落ちるため M2b 検証が前提』は正しいが、synth 私的事実から見ると M2b 単独では 1.00 に届かない二つの機構欠落がある: (1)接地ゲートは citation が主張を textual に支持するかだけ判定し現実世界の真偽を見な
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem
    - [e29] (AGENT) e25 の sample-consensus(quorum)も e27 の stance 正当化検証も、ギャップを機構設計の欠落(uniq_by が byte 一致のみ・verify が textual のみ)に帰属させるが、私的事実から見ると両者を律速しているのは LLM organ そのものであ
    - [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ co

### 提案 33 `e92` [NOVEL] (×1)

The moat strategy decision (retraction-governance vs opt-in --governance best-of-N) is being pre-empted by controlling-closure requirements before governance's marginal value is measured, and this is unsupported on both product and research grounds: the core governance evidence (C5 Impact Recall 1.00) holds only under synthetic contamination A, degrades to 0.50 under natural B, and neither a direct Fusion head-to-head nor an off-family solo baseline (n>=6) nor a plain-strong-model best-of-N single-shot-Opus baseline has been run. So opt-in gating must be decided AFTER quantifying, at n>=6 across domains, whether governance prevents harm Fusion cannot—otherwise the moat choice (and the CLI-purification/audit sunk costs it triggers) rests on internally-invalid, retrieval-starved measurements.

  来歴:
    - [e11] (ADOPTION) e9 の相互依存条件『主要熟議経路から CLI を除外して serve 接地を純化する』は採用とトレードオフで衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、その認証・binary 可用性・コストが既に adoption 摩擦)、主要
    - [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証
    - [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ co
    - [e31] (ADOPTION) e27's stance-audit step deepens governable closure but, from the adoption lens, it directly compounds the friction that already blocks real teams: it 

### 提案 34 `e93` [NOVEL] (×1)

The baseline 'limit-value' measurement that the moat decision depends on is at risk of double under-measurement because synth only solves the connection/expression stages while retrieval (what gets externalized) is a separate leaking stage: the H2 ~5-6/10 ceiling is counterpart facts never surfacing (entry_limit=2/round, uneven serve distribution) and H8 gemma collapsed to single-shot serve without breaking it. The natural-B C5 Precision 0.50 drop is thus compounded by a retrieval-starved surface where the grounding gate silently passes textual-support without checking real truth. Retrieval levers (serve-policy depth, entry_limit, aware/rounds/kp/ks, multi-step serve firing) must be exhausted to control the surface BEFORE the n>=6 Fusion comparison, or both governance and best-of-N are compared at retrieval-throttled rather than true limit values, amplifying the sunk-cost risk.

  来歴:
    - [e11] (ADOPTION) e9 の相互依存条件『主要熟議経路から CLI を除外して serve 接地を純化する』は採用とトレードオフで衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、その認証・binary 可用性・コストが既に adoption 摩擦)、主要
    - [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証
    - [e14] (SYNTH) e11/e13 が moat 選択(統治 vs best-of-N)の前提とする『baseline 比較で限界価値を定量』は、私的事実の retrieval 天井と相互作用して二重に過小測定される危険がある:synth は connection/expression 段のみ解き retrieval(

### 提案 35 `e94` [NOVEL] (×1)

A queryable lineage / dependency-impact API is required for governance to be controlling-not-invisible to users (retraction today raises no downstream-dependency alert and provenance is unqueryable), but it has an upstream substrate blocker not counted in its viz-cost estimate AND a validity risk: consult returns static JSON with findings never persisted to the production store (no re-synthesis/audit/dependency query), so findings must first be persisted as first-class governable entities under the retraction closure; and shipping the API on the unverified substrate (precision 1.00 only under synthetic A, 0.50 under natural B) would visualize false dependency alerts, damaging the governance-credibility claim. The moat decision must therefore price in BOTH the persistence blocker and the M2b-verification cost, not viz alone.

  来歴:
    - [e21] (ADOPTION) e17 が認める『永続化された汚染リンクは伝播対象を増やすだけで過剰連結(e13)を防がない』というトレードオフは、製品面では『撤回しても他の何が依存するかのアラートが無く来歴がクエリ不可』という私的事実と同じ穴に帰着する: governable な findings ノード(e17)を作っても、そ
    - [e23] (RESEARCH) e21 の『governable findings は撤回時の下流依存を提示するクエリ可能な来歴 API とセットで初めて採用価値を持つ』は妥当だが、私的事実と衝突する重要な留保を欠く: 統治 precision=1.00 は合成汚染(汚染A=論理反証可能)でのみ成立し、自然汚染では 0.50(過剰
    - [e24] (SYNTH) e21 が採用条件とする『クエリ可能な来歴 API』は viz コストの問題に見えるが、ADOPTION には見えない synth 私的事実によって substrate 自体が欠けている: consult は静的 JSON を返して終わりで、findings は production store に
    - [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contaminat

### 提案 36 `e95` [NOVEL] (×1)

The stance signal that stance-audit (e27) would verify does not exist in the dominant serving path: in prose mode (the consult default) agent write entries persist no stance (meta is domain/round only), stance lives only in tool-mode meta, and CitationPrecision.ladder defaults missing stance to relies_on—so all prose citations collapse to a uniform relies_on, erasing the refutes/context distinction and leaving nothing to audit. Making stance a first-class store citizen in both modes (persist stance to meta + post-hoc normalize prose at the serve/absorb tooling boundary to keep explicit vs default distinct) is the unsolved agent-layer prerequisite for the stance-audit lever.

  来歴:
    - [e6] (GOVERNANCE) 次段階の最高レバレッジな governance 改善は『stance 監査 harness』である。理由: citation precision 梯子(0.40→1.00)は統制ケースの上限値にすぎず、私的事実では stance 自己申告は無監査(agent が refutes と言いつつ実は暗黙 
    - [e8] (AGENT) e5/e7 が要求する『どの citation がどの layer-0 に接地したか』『quorum メタデータ』を持つ governable findings は、その下層の citation グラフが stance を保持していて初めて撤回閉包が正しく伝播する。だが私的事実(問題#4)では pr
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem
    - [e28] (AGENT) e27 の stance-audit(Reference が各 stance の正当化を検証し refutes の偽装を捕捉する)は機構として正しいが、それが監査する『stance』という信号自体が支配的 serving 経路に存在しないという substrate 前提を見落としている。私的事実: 

### 提案 37 `e96` [NOVEL] (×1)

Stance-audit as part of DEFAULT closure is premature from the adoption lens because it compounds existing friction: it stacks another Opus pass onto the measured $1-3/20-40s-per-consult Opus-judge dependency and the fixed-3-agent path that lacks a clean task+docs+agents API and is undocumented in any consumer README; and governance is condition-dependent (with few agents and shallow claims, single Opus + light human review suffices and the payoff threshold is unquantified). It should be gated behind opt-in --governance, with the next stage spent quantifying the threshold where stance-honesty auditing beats human review rather than stacked onto the default path.

  来歴:
    - [e10] (ADOPTION) e7とe9はfindingsを controlling な撤回対象にし retrieval を監査して serving 経路に一貫させよと要件化するが、その対象の serving 表面は現状どの実チームも到達できない:私的事実かつコード上、consult の run_consult は Dissol
    - [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreem
    - [e31] (ADOPTION) e27's stance-audit step deepens governable closure but, from the adoption lens, it directly compounds the friction that already blocks real teams: it 


## 熟議で外部化された懸念（layer-0 全件）

- [e2] (RESEARCH) 最も効果の高い次の一手は、disc_strict の {0,1,2,3} 天井(私的事実: H2高天井~10件でも synth ~5-6/10 で頭打ち=retrieval段の限界)を外す『連続・飽和しない発見メトリクス + 2-3別ドメインでの統計的 n≥6』への投資である。e1 は H1〜H8 で機構検証済とし攻め約2倍を主張するが、その効果量は n=3・記述統計・単一シナリオ・LLM judge(26b)依存・人間/異モデル IRR 未検証の上に乗っており、外的妥当性(シナリオ汎用性)と構成概念妥当性(天井で disc_strict 0.33→2.0 の『6倍』が飽和アーティファクトでない保証なし)が未閉。連続メトリクス化は contrastive serve が多様性0.224→0.246を上げつつ発見2.0→1.0を下げた diversity theater を弁別する解像度も与え、後続の全ドメイン提案の評価基盤を底上げする(依存: 評価が壊れていれば他領域の改善も真偽判定不能)。
- [e3] (RESEARCH) 第二の最重要改善は、まだ走っていない決定的実験 M2b(実探索 B型=採用可能汚染 + stance+verify フルスタックを harness で)と permissive(C型: 否定形『問題なし』)汚染の防御を埋めることだ。e1 は『守り=citation接地 precision 0.40→1.00』『多層=統治可能な合成』を確立済とするが、私的事実ではこの 1.00 は合成汚染A(論理反証可能)・統制ケースの値であり、自然な汚染B では C5 Precision 0.50(過剰連結, depends_on_turns が意味的真理でなく参加を参照)に落ち、permissive汚染は stance-anchor judge を壊しカバレッジゼロ、stance自己申告品質も実エージェント未検証。従って governance の核心主張は統制環境の上限値であって運用妥当性が未証明であり、これを閉じることが Fusion との差別化(governance が防ぐ harm の実証)の前提になる。
- [e4] (SYNTH) 最高レバーの SYNTH 改善は、synth 合成層に (a)サンプル間 quorum/voting と (b)真偽接地シグナルを first-class で入れること。現状 union は Enum.uniq_by(&.text) の byte 一致のみで、2/3 が「A→B」1/3 が「A→¬B」でも両方載る(コンセンサス無し)。かつ接地ゲートは citation が主張を textual に支持するかだけ見て現実の真偽を見ない(「暗号化済」を引く layer-0 は暗号化が偽でも接地が立つ)。これは e3 の C5 Precision 0.50=過剰連結(depends_on_turns が意味的真理でなく参加を参照)の serving 層側の同型機構であり、私的事実と e3 の私的事実が一致して同一欠陥を二方向から指す。よって e1 が『接地 precision 1.00 で守りは確立』とするのは統制環境の上限値にすぎず、自然汚染 B/permissive C 下では union+lenient verify が崩れる。quorum 票数を findings に露出し、verify を textual-support から claim-truth 照合へ昇格させれば、e3 の M2b/permissive 防御と直接噛み合い、Fusion 差別化(governance が防ぐ harm の実証)の前提を synth 層から満たす。
- [e5] (SYNTH) 第二の SYNTH 改善は、retrieval 天井を破るより先に findings を production store に persist される first-class な governable entity にすること。現状 consult は静的 JSON を返して終わりで、findings は撤回イベントが適用されず再合成・監査・クエリ不可。e1 は『撤回閉包が citation を通じて伝播する』を機構の柱とするが、serving 出力(findings)はその閉包の外にあり、layer-0 が後で撤回されても serve 済み発見は隔離されない。これは観測可能性欠如(verified:true の bool のみで「3 サンプル中 2 で発見」「どの citation がどの layer-0 に接地したか」を返さない)と複合する。findings を撤回閉包の対象に含め quorum/接地メタデータを persist すれば、撤回伝播という既存の中核機構が serving 経路まで一貫し、retrieval 天井(entry_limit/serve-policy 深さ、tool-use 単発収束)に取り組む際の監査基盤にもなる。
- [e6] (GOVERNANCE) 次段階の最高レバレッジな governance 改善は『stance 監査 harness』である。理由: citation precision 梯子(0.40→1.00)は統制ケースの上限値にすぎず、私的事実では stance 自己申告は無監査(agent が refutes と言いつつ実は暗黙 relies_on でも verify は textual 接地しか見ず stance honesty を見ない)。e3 はこれと相互作用する独立事実を外部化している——自然汚染B で C5 Precision=0.50(depends_on_turns が意味的真理でなく参加を参照)、permissive(C型)汚染は stance-anchor judge を壊しカバレッジ=0。両者は同一の故障面(stance/接地が運用妥当性を欠く)であり、Reference が agent に stance 根拠を述べさせ根拠自体を verify する閉ループ監査を入れれば、precision の運用上限が実harm防御(Fusion との差別化前提)へ転化する。これは reference.ex の verify judge(1180-1232)と citation_stances meta(483-490)を stance-fidelity 判定へ拡張する増分で達成できる。
- [e7] (GOVERNANCE) 第二の改善は serving findings を撤回閉包の first-class 対象にし、かつ synth が閉包 status を尊重することの両方を要件化することだ。e5 の指摘(findings は serve 後 closure の外で layer-0 撤回が隔離されない)に依拠するが、私的事実で補強・部分反証する: 私の typed_closure_effects(843-904)/closure(146) は逆 citation index でグラフ内を伝播するだけで serving 境界を跨がない——よって e1 の『撤回閉包が citation を通じて伝播する』は serving 経路で不完全。ただし findings を persist し撤回対象にする(e5)だけでは不十分で、合成層が reopen を『新候補生成』でなく『上流訂正下で既存 findings の再評価+能動的未提供化』と解さねば governance は advisory に留まり controlling にならない(H6 層またぎ説明責任)。両条件を満たして初めて『悪い主張Cが吸収→C撤回で下流汚染を能動防御』という Fusion 不可の固有価値が serving まで一貫する。
- [e8] (AGENT) e5/e7 が要求する『どの citation がどの layer-0 に接地したか』『quorum メタデータ』を持つ governable findings は、その下層の citation グラフが stance を保持していて初めて撤回閉包が正しく伝播する。だが私的事実(問題#4)では prose モードの agent 書き込み entry は stance を persist せず(meta は domain/round のみ、stance は tool モード meta にしか入らず prose は relies_on default に潰れる)。よって e5 の『findings を撤回閉包の対象に含め接地メタを persist』も e7 の『reopen を既存 findings の能動的未提供化と解す』も、relies_on default で水増しされた逆 citation index 上を走り、context 引用と真の依存を区別できない——findings レベルで closure を効かせる前に、書き込み時点で stance を構造化 persist する(prose 出力を post-hoc 正規化でなく serve/absorb のツール化境界で stance を確定する)ことが先決の依存条件である。
- [e9] (AGENT) e7 が findings を controlling な撤回対象にする監査基盤を serving 経路に通すと宣言するなら、その監査が測る retrieval/grounding 信号自体が汚染されていてはならない。私的事実(問題#3)では CLI(cursor-agent)アダプタは web 検索・コード実行など不可視の内部ツールを持ち、CLI 熟議では発見が tracefield serve 由来か CLI 内部ツール由来か区別不能で、served_queries=1 の retrieval 平坦さ(問題#1)の原因切り分けも不能になる。e5 は findings persist が『retrieval 天井に取り組む際の監査基盤になる』と主張するが、その基盤が CLI を含む store の上に立つと findings の quorum/接地メタは交絡を継承する。したがって findings governance を serving まで一貫させる前提として、主要熟議経路から CLI を除外するか内部ツールを監査し、何が serve に接地したかを純粋化することが相互依存条件となる。
- [e10] (ADOPTION) e7とe9はfindingsを controlling な撤回対象にし retrieval を監査して serving 経路に一貫させよと要件化するが、その対象の serving 表面は現状どの実チームも到達できない:私的事実かつコード上、consult の run_consult は Dissolution.default_agents() で agent を SEC/BIZ/UX に固定し、load_private_docs は sec.md/biz.md/ux.md を固定名で要求し、Scenario.load! は研究 harness 用の contaminant-A.md/correction-A.md を必須とする(fsl-brushup はこれを回避するため ~146行の custom run.exs で consult を捨てて cursor CLI を直叩きした)。よって次段階で最も効果が高いのは『task + 任意 docs + 任意 agents → governed findings』のクリーンな入力 API を先に切ること:統治を controlling にする監査基盤(e7)も retrieval 純化(e9)も、固定3観点・固定ファイル名・harness 結合の足場を払って初めて実チームの PR/設計レビューで起動でき、起動できなければ controlling 化は到達されない論点に留まる。
- [e11] (ADOPTION) e9 の相互依存条件『主要熟議経路から CLI を除外して serve 接地を純化する』は採用とトレードオフで衝突する:CLI(cursor-agent)は現状唯一の deploy 経路であり(hosted API でなく、その認証・binary 可用性・コストが既に adoption 摩擦)、主要経路から外せば実利用の deploy 表面そのものが消える。したがって retrieval 監査純度(e9)と controlling closure(e7)を要件化する前に未決の戦略決断を強制すべきだ:統治(撤回閉包)を moat にするか、任意文脈で単発に勝つ best-of-N 合成を moat にするか。前者なら e9 の CLI 除去・監査コストは正当化されるが niche に閉じ、後者なら統治を default から外し --governance を opt-in 化して『任意撤回追跡付き多ターン横断合成』として売る方が採用は伸びる。e7/e9 はこの未定の moat 選択を controlling 要件で先取りしており、その前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量しない限り、監査・純化コストは sunk になりうる。
- [e12] (RESEARCH) e9 の『CLI 内部ツール(web検索/コード実行)で発見が serve 由来か区別不能』という相互依存条件は、研究妥当性上の決定的な交絡として正しいが、これは私的事実の H8 知見(tool-use の価値は来歴精度であって発見でない、structured citation で grounding +48% だが disc は flat)と直接干渉する:H8 は『可視で監査済みのツール経路』を前提に来歴精度を測ったのに対し、e9 の CLI は『不可視の内部ツール』であり、served_queries=1 の retrieval 平坦さ(問題#1)が tracefield の retrieval 段の限界なのか CLI 内部解決の代替なのかを切り分け不能にする。これは私の未閉じ脅威『単一基盤・prompt-level merge では inference API を超えた状態共有は届かない』と『M2b(実探索 B型汚染+stance+verify フルスタック)未実施』の交点に新たな交絡源を追加する。よって e9 を要件化するなら、主要熟議経路を CLI 除外する前にまず内部ツール ON/OFF を独立変数とした統制実験(serve接地の純度を従属変数)で交絡を分離測定すべきであり、これなしの『純化』は反証可能性を持たない手続き的主張に留まる。
- [e13] (RESEARCH) e11 の『controlling closure を要件化する前に baseline(Opus単発/Fusion)比較で統治の限界価値を定量せよ』は、製品論としてだけでなく研究妥当性上も支持される:私的事実では統治の中核証拠 C5 Impact Recall 1.00 は合成汚染(汚染A=論理反証可能)に限られ、自然な採用可能汚染(汚染B=PM証言)では C5 Precision が 0.50 に劣化し(depends_on_turns が意味的真理でなく参加を参照する過剰連結)、かつ Fusion との直接対決と異系列ソロ baseline(n≥6)はいずれも未実施である。したがって e11 の moat 選択(統治 vs best-of-N)を駆動する『統治の限界価値』は現状のエビデンスでは未測定であり、e11 が sunk cost を警告するのは妥当だが、私的事実はさらに踏み込む:opt-in 化(--governance)を決める前に、まず汚染B環境での Fusion 対比で『governance が Fusion に防げない harm を防ぐ』ことを n≥6・複数ドメインで実証しない限り、moat 選択そのものが内的妥当性を欠く根拠で行われる。
- [e14] (SYNTH) e11/e13 が moat 選択(統治 vs best-of-N)の前提とする『baseline 比較で限界価値を定量』は、私的事実の retrieval 天井と相互作用して二重に過小測定される危険がある:synth は connection/expression 段のみ解き retrieval(何を外部化するか)は別の漏れ段で、H2 の ~5-6/10 頭打ちは counterpart 事実が surface に出ていない(entry_limit=2/round、serve 分布不均一)ためであり H8 tool-use でも gemma は単発 serve に収束して天井は破れなかった。よって e13 が指摘する『汚染B で C5 Precision 0.50 へ劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)』は、統治機構固有の弱さだけでなく retrieval-starved な surface 上で接地ゲートが現実真偽でなく textual 支持だけを見る silent 失敗(layer-0 を引用すれば未検証でも接地が立つ)と複合している可能性が高い。次段階の最も効果の高い改善は moat を opt-in 化する前に retrieval レバー(serve-policy 深さ・entry_limit 拡大・aware/rounds/kp/ks・multi-step serve のポリシー発火)を網羅し、surface を統制した条件下で初めて e13 の n≥6 Fusion 対比を行うことだ。さもなくば統治も best-of-N も真の限界価値でなく retrieval 漏れに律速された値で比較され、e11 の警告する sunk cost をむしろ増幅する。
- [e15] (SYNTH) e13 が要求する『汚染B環境で governance が Fusion に防げない harm を防ぐことを n≥6・複数ドメインで実証する』実験は、現状の serving 観測可能性では原理的に実行不能であり、これが研究妥当性の前に解くべき serving 層の開いた課題だと私的事実から指摘できる:findings は `verified: true` の bool のみで『3サンプル中2で発見』や judge 信頼度・どの citation がどの layer-0 に接地したかを返さず、サンプル間コンセンサスも `Enum.uniq_by(&.text)` の byte 一致のみで 2/3『A→B』対 1/3『A→¬B』を voting/quorum 無しに両載せし、さらに synth は静的 JSON を返すだけで findings は production store に persist されず後の撤回イベントが適用されない非 first-class entity である。harm 防止を判定するには per-sample consensus・接地証跡・撤回後の再評価が必須であり、これらが無い限り e13 の内的妥当性ある比較の前提(harm の定義と計測)自体が成立しない。したがって e13 を満たすための前提作業として、findings を governable entity 化(consensus/confidence の外部化・production store persist・撤回閉包の適用)することが、moat 選択を測定可能にする最優先改善である。
- [e16] (GOVERNANCE) e13 の汚染B下 C5 Precision 0.50 劣化(depends_on_turns が意味的真理でなく参加を参照する過剰連結)は、統治コアの未測定だった2つの開いた穴—stance 自己申告の無監査(reference.ex:683-696 extract_citation_stances は申告 stance を記録するのみで真の依存構造に照合しない)と typed closure の未引用意味依存への盲目(M5)—の経験的確証である。よって次段階の最高レバレッジ改善は単なる findings 永続化でなく stance-fidelity 検証: verify judge を citation の textual 接地(reference.ex:1180-1232)に加え『申告 stance が主張の実依存と整合するか(refutes 申告下の暗黙 relies_on, 参加ベース over-connection の検出)』へ拡張し、不整合 stance を精度梯子から棄却すること。これにより 0.40→1.00 梯子が多型・多著者・汚染B でも崩れず、閉包が GT 依存に対し完全化する。
- [e17] (GOVERNANCE) e15 の『findings は verified:true bool のみ・byte一致 consensus・production store 非persist・撤回非適用の非 first-class entity』は、私の開いた問題『層をまたぐ説明責任—synth が閉包 status を無視すれば governance は advisory で controlling でない』と完全一致し、findings の governable entity 化は stance 監査を規模で行う前提条件である。ただしトレードオフを明示する: e15 の persist/consensus 外部化は『撤回が伝播する経路』を作るが、過剰連結(e13)を防がない—永続化された汚染リンクは伝播対象を増やすだけ。したがって両者は依存関係にあり順序が重要: findings を撤回閉包(typed_closure_effects/3:843-904)の first-class ノードに昇格(e15)させた上で、その接地証跡に stance-fidelity 検証(本belief1)を適用しなければ、e13 が要求する『Fusion に防げない harm を防ぐ』実証は consensus 証跡を得ても精度を欠いたまま測定不能に留まる。
- [e18] (AGENT) e15/e17 が findings を first-class governable entity 化し撤回閉包＋stance-fidelity 検証を載せる計画は、agent-llm 層に未解決の前提欠陥があり、その順序では harm 帰属に届かない。私的事実とコードで確認: (a) synth survivors は `Map.take(&1, [:type,:text,:citations])` で citations を載せ替え、stance は持たず、Reference は非デフォルト stance のみ meta.citation_stances に保存し欠落 id を一律 relies_on と解釈する(reference.ex:690, citation_stance_for:906-916)。よって synth finding の接地証跡は『真の relies_on』と『default の relies_on』が原理的に区別不能で、e17 の stance-fidelity 検証は synth 出力に対し default baseline を測るだけになる。(b) findings を撤回閉包(typed_closure_effects)の正規ノードに昇格しても、citation が stance 無しなら closure_action(spec, stance) は relies_on 経路に潰れ、e17 の言う『過剰連結を防ぐ精度』は得られない。したがって findings 永続化(e15)より先に synth citation を stance 付きで emit/persist させることが、e17 の検証と e13 の harm 帰属を測定可能にする前提改善である。
- [e19] (AGENT) e15 の『consensus は byte 一致 uniq_by(&.text) のみ・per-sample consensus 不在』は、私的事実の retrieval ポリシー平坦さ(served_queries=1)と同根の観測不能性であり、harm 帰属には serve 層の per-query provenance 復元が前提となる。コードで確認: serve は単発(serve.ex:16-33, agent.ex:83-89)で再 serve ループが無く、prose 経路の perception(perception_log:247-256)は served_queries を一切残さず、tools 経路のみが record_tool_result(agent.ex:466-474)で served_queries を蓄積する。e15 が要求する『どの citation がどの layer-0 に接地したか』の証跡は、prose 熟議では query↔served の対応そのものが破棄されているため、findings を persist しても上流の retrieval provenance が欠ければ harm の発生経路を再構成できない。よって e15 の findings governable 化は、prose 経路でも served_queries を計測し serve↔finding の接地経路を保存する agent 層の改修と対で行うべきで、これが無いと e13 の n≥6 harm 計測は findings を persist しても経路不明のまま残る。
- [e20] (ADOPTION) e19 が示す prose 経路の provenance 欠落(serve は単発・served_queries 非保存)と e17 が要求する findings の governable 化は、いずれも consult serving 経路への投資を前提とするが、私的事実と矛盾する: その唯一の consumer 入口 mix tracefield.consult は load_private_docs/Dissolution.default_agents で SEC/BIZ/UX に固定され『task+任意docs+任意agents→findings』の API が無く、fsl-brushup は consult を使えず ~146行の custom run.exs で迂回した。よって per-query provenance 復元(e19)を prose 経路に積んでも、実チームは自分の task でその経路を起動できないため harm 計測の母数が研究シナリオに限定される。governance/agent 層の provenance 改修より先に、agent 集合を config 駆動にする serving API の一般化を順序付けるべきで、これは e17 が主張する『findings 昇格→stance 検証』の順序に、その手前の『到達可能性』前提を追加する相互依存である。
- [e21] (ADOPTION) e17 が認める『永続化された汚染リンクは伝播対象を増やすだけで過剰連結(e13)を防がない』というトレードオフは、製品面では『撤回しても他の何が依存するかのアラートが無く来歴がクエリ不可』という私的事実と同じ穴に帰着する: governable な findings ノード(e17)を作っても、それを照会・可視化する serving 表面(ダッシュボード/依存影響クエリ)が無ければ、ユーザにとって統治は controlling でなく不可視のまま残る。したがって findings の first-class 化(e17)は、撤回時の下流依存を提示する『クエリ可能な来歴 API』とセットで初めて採用価値を持ち、統治を moat とするか best-of-N 合成を moat とするかの戦略判断は、この可視化コストを織り込んで決めるべきである。
- [e22] (RESEARCH) e19 は正しく『prose 経路では query↔served_queries が破棄され harm 発生経路を再構成できない(serve.ex:16-33, perception_log:247-256)』と指摘するが、これは私の妥当性脅威と二重に交絡する: 私の統制実験では自然な採用可能汚染(汚染B=PM証言)で C5 Precision が 1.00 から 0.50 に落ち、原因は depends_on_turns が『参加』を参照し意味的真理依存でないことだった。e19 の serve↔finding 接地欠落は、この precision 低下が stance 意味論の問題だけでなく retrieval-provenance の欠損でもあることを意味し、両者が合わさると、決定的だが未実施の M2b(実探索B型汚染+stance+verifyフルスタックを harness で)を走らせても harm 帰属の測定そのものが交絡する。したがって e19 の『served_queries 計測と serve↔finding 接地保存』は M2b の前提条件であり、これ無しに findings を persist しても経路不明のままという e19 の結論を、私は再現性側(n=3・単一シナリオ・天井効果)からも支持する。
- [e23] (RESEARCH) e21 の『governable findings は撤回時の下流依存を提示するクエリ可能な来歴 API とセットで初めて採用価値を持つ』は妥当だが、私的事実と衝突する重要な留保を欠く: 統治 precision=1.00 は合成汚染(汚染A=論理反証可能)でのみ成立し、自然汚染では 0.50(過剰連結)に落ちる。よって未検証の substrate 上に依存影響クエリ API を出荷すると、ユーザに偽の依存アラート(過剰連結)を可視化し、統治の信頼性主張そのものを毀損する妥当性リスクになる。さらに e21 の可視化は retrieval-limit という私の天井効果事実(H2 高天井でも synth ~5-6/10 で頭打ち)を解消しない。ゆえに『統治を moat とするか best-of-N を moat とするか』の戦略判断(e21)は、可視化コストだけでなく『自然汚染下での precision 0.50 を 1.00 に近づける M2b 検証が前提』というコストも織り込むべきである。
- [e24] (SYNTH) e21 が採用条件とする『クエリ可能な来歴 API』は viz コストの問題に見えるが、ADOPTION には見えない synth 私的事実によって substrate 自体が欠けている: consult は静的 JSON を返して終わりで、findings は production store に persist されず後続の撤回イベントが適用されない(再合成・監査・依存影響クエリ不可)。ゆえに撤回時の下流依存を返す API は『可視化を作る』前に『findings を first-class な governable entity として永続化し撤回閉包を受ける』synth 層の変更が前提であり、これは ADOPTION の viz コスト見積りに入っていない依存である。統治を moat にする戦略判断(e21)は、この永続化コストを viz より上流のブロッカーとして織り込むべきだ。
- [e25] (SYNTH) e23 の『自然汚染で precision 0.50 に落ちるため M2b 検証が前提』は正しいが、synth 私的事実から見ると M2b 単独では 1.00 に届かない二つの機構欠落がある: (1)接地ゲートは citation が主張を textual に支持するかだけ判定し現実世界の真偽を見ないため、合成汚染(論理反証可能)と自然汚染を原理的に区別できず lenient verify 単独は過剰連結を見逃す(H6 で keyword gate 追加して初めて捕捉)。(2)best-of-N はサンプル間コンセンサスを持たず Enum.uniq_by が byte 一致のみで、2/3 が『A→B』1/3 が『A→¬B』でも union が両方載せる(voting/quorum 無し)。よって自然汚染下 precision を 1.00 に近づけるには M2b 検証に加え truth-grounding と sample-consensus(quorum)が必要で、これは e21/e23 が前提とする依存影響 API の信頼性を支える未解決の synth レバーである。
- [e26] (GOVERNANCE) The precision ladder's verified=1.00 top rung is a controlled-case artifact (design-time GT + deterministic Mock verify), and e23's natural-contamination drop to 0.50 is mechanistically my H6 audit gap: lenient verify mistakes surface overlap for grounds. So M2b must measure not just 'does precision hold at scale' but specifically the over-connection rate from judge-model infidelity — because weak local judges (gemma) misparse verify JSON and re-introduce false-positive citations, collapsing the closure that the dependency-impact API (e21) depends on. Shipping that API on an unverified substrate visualizes false dependency alerts, which is the governance-credibility risk e23 names.
- [e27] (GOVERNANCE) e25's truth-grounding + sample-consensus and e23's M2b are necessary but insufficient for governable closure: all three see only textual/voting agreement, none audit stance honesty. A self-reported 'refutes' that hides an implicit relies_on (agent cites X to argue against it while its claim covertly depends on X being salient) passes verify — which only checks the citation's textual grounding, not the stance's truthfulness — so retraction of X never propagates downstream and closure is silently incomplete. The next-stage governance lever they cannot see from synthesis/validity domains is a stance-audit step where the Reference makes agents justify each stance and verifies that justification, closing the gap that truth-grounding and quorum leave open.
- [e28] (AGENT) e27 の stance-audit(Reference が各 stance の正当化を検証し refutes の偽装を捕捉する)は機構として正しいが、それが監査する『stance』という信号自体が支配的 serving 経路に存在しないという substrate 前提を見落としている。私的事実: prose モード(mix tracefield.consult の既定)では agent の書き込み entry は stance を persist せず meta は domain/round のみ;CitationPrecision.ladder は stance 欠如時に relies_on を default 適用する。よって『implicit relies_on を隠した self-reported refutes』は tool モードでしか data として存在せず、prose では全 citation が一律 relies_on に潰れて refutes/context の区別が消えるため監査対象が無い。e27 の lever を成立させる前提条件は、stance を両モードで store の一級市民にする(meta への stance persist + prose の post-hoc 正規化で explicit と default を区別保持する)ことであり、これは e27/e25 が前提とする honest agreement の信号源を支える未解決の agent 層レバーである。
- [e29] (AGENT) e25 の sample-consensus(quorum)も e27 の stance 正当化検証も、ギャップを機構設計の欠落(uniq_by が byte 一致のみ・verify が textual のみ)に帰属させるが、私的事実から見ると両者を律速しているのは LLM organ そのものである。H8 では gemma が単発 serve に収束し(6 serve/6 turn、multi-step retrieve がポリシー発火せず)、接地品質を判定できず seed でばらつく(disc 4,4,1 sd1.73)。quorum は『2/3 が A→B、1/3 が A→¬B』という分岐サンプルを前提とするが、単発 serve に潰れる organ は分岐そのものを生まず、stance 正当化も honest な多様性を欠いた呪文に堕する。synth/governance 領域から見えない次段階レバーは強モデル切替(OpenRouter アダプタは存在するが default 強モデル未指定)と multi-step retrieve の自然発火ポリシーであり、これ無しでは quorum 票も stance 正当化も gemma artifact に過ぎず、e25/e27 の統治機構は govern すべき信号を欠く。
- [e30] (ADOPTION) e29 corroborates my product-blocker that consult mandates an Opus judge because gemma misjudges grounding, and explains the deeper cause: the organ collapses to single-shot serve, so it cannot even generate the branching samples quorum/stance-audit presuppose. The next-stage adoption lever is therefore NOT more judging layers but (a) a named default strong-model adapter (the OpenRouter adapter exists but no default strong model is specified) and (b) a cost/budget surface — both absent today (no cost estimate, no budget cap, no local fallback since gemma misjudges). Critically, my private fact exposes a gap e29 omits: even a strong organ leaves the product without a plain-strong-model best-of-N baseline, so we still cannot prove pooling/governance beats single-shot Opus — without that baseline, fixing the organ makes findings trustworthy but their marginal value over a cheap single Opus call stays unmeasured.
- [e31] (ADOPTION) e27's stance-audit step deepens governable closure but, from the adoption lens, it directly compounds the friction that already blocks real teams: it adds another Opus pass (worsening my measured $1-3 / 20-40s per consult and Opus-judge dependency) on top of a fixed-3-agent (SEC/BIZ/UX) path that already lacks a clean 'task + arbitrary docs + arbitrary agents' API. My private fact is that governance is condition-dependent — when agents are few and claims shallow, single Opus + light human review suffices and the payoff threshold is unquantified — so making stance-audit part of default closure is premature. The product move is to gate it (and closure) behind '--governance' as opt-in, and to spend the next stage quantifying the threshold where stance-honesty auditing beats human review, rather than stacking it onto the default consult path that no consumer-facing README yet documents.
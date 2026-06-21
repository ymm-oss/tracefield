# findings: 生成側ハルシネーションの抑制 — *govern the composer*

対象問題: tracefield が**新しい内容を生成するとき**（設計・計画・施策・統合＝答えが一意でない発想）の
ハルシネーション抑制。「読み取り（抽出）」側は別スレッドで完了済み（[findings-grounded-reading.md]、
[findings-citation-precision.md]、[findings-substrate-hetero.md] の再接地テーゼ）。本書はその*補集合*。

## 0. 一行結論
生成のハルシネーションは「自由な*賭け*（commitment）の中に、偽の*事実前提*をこっそり混ぜること」である。
直すべきは賭けでなく前提。**composer（統合・施策化ステージ）を、起草者と同じ
grounded→verify→adjudicate→retract の規律の中に入れる**ことで殺せる。これは新サブシステムでなく、
既存の実証済み機構（per-stage `grounded` フラグ＋on-disk evidence-quote 接地＋`retract_overturned`＋
機械集約）の*配線*と、provenance を捏造する 1 つの fallback の*撤去*だけで実現する。

## 1. 生成は読み取りと何が違うか
読み取りでは出力の*接地先（一次資料）*が存在し、`evidence_quote` の逐語照合で「資料が支持しない主張」を
機械検出できた。生成では出力が**新規**で、grep する原本が無い。だが生成物は一枚岩ではなく分解できる:

1. **commitment（賭け／選択）**: 「A 方向に賭ける」「X→Y→Z で構成する」。接地先が原理的に無い＝
   *自由*。これが生成の*目的*であり、ここを接地しようとするのは筋違い。
2. **factual premise（事実前提）**: 賭けが依拠する世界の事実。「FSL は repair ループを持つから」
   「dogfood で壁 W に当たったから」。これは**真偽がある**。
3. **self-claim（自己言及）**: 生成物が自分について主張すること。「この施策は O(n)」「要件 R を満たす」。

> **生成のハルシネーション＝ commitment の中に紛れ込んだ偽の factual premise／self-claim。**
> 賭けは自由のまま、前提だけを接地・反証し、賭けは*接地された前提の上にだけ*立たせる。

## 2. 既にコーパスが証明していること（再実装しない）
コーパスの生成側ハルシネーション戦略は一文で:
**「全 LLM 呼び出しを忠実な小規模文脈域に留め、規模を要する統合だけ機械集約に逃がす」**。
実証済みの機構（いずれも mechanism-level・小 n・単一シナリオ・同系モデルの限界つき）:

- **中央合成を持たない＋反証1件=1隔離審判(`per_input`)＋機械集約**（[findings-lens-type.md] §5.3/§6.5,
  [findings-longrun-investigation.md]）。レンズ脱落・矮小化・反転・捏造を消す旗艦機構。
- **合成忠実性は入力規模で劣化する（弱いモデルほど激しい）。intrinsic confab ではない**
  （[findings-lens-type.md] §6.6 主張B、当初の「intrinsic」主張は撤回済み）。
- **best-of-N 合成**で分散→0、cross-findings ~2×（[findings-synthesizer-h5.md] H5b/H2）。
- **合成層への接地ゲート**で over-citation を撲滅（16/16、精度不変）（[findings-synthesizer-h5.md] H6）。
  → ただし H6 は*実験*であり engine には載っていない（後述ギャップ）。かつ H6 は*引用*接地で、
  composer が*発明*したものの再攻撃はしていない。
- **ゲート接地フィルタ**で false precision を [接地]/[暫定]/[未検証] 化（未検証 8→1）
  （[findings-continuity-vs-diffusion.md]）。
- **ピア反復(long_run ~3 cycles)**で多様性温存・mode collapse 回避（[findings-diffusion-thinking.md]）。
- **強い敵対 best-of-N は前提依存を減らす**（invalidated=0、[findings-governance-vs-fusion.md] F3）。

## 3. 残るギャップ（ハルシネーションに直結する2つ）
コーパス自身が「未解決」と名指すもののうち、*ハルシネーション*に直結するのは:

- **#4 鋭い中央合成は confab する**: 中央 SYNTH は鋭く有用だが「未検証の推論的飛躍」を運ぶ
  （捏造した「40%」、verify に無い反証レビュー表の捏造＝「フォーマット遵守 ≠ 実質吟味。見かけの
  頑健性を製造する分、無構造の素通りより危険」[findings-lens-type.md] §5.2）。コーパスの対処は
  中央合成を*避ける*ことで、*非 confab 化*はしていない。**この『鋭い合成を安全にする』版が未解決。**
- **#2 false precision は緩和され消えてはいない**（発明した数値は flag/probe されるが第一原理導出はされない）。

加えて engine 実装監査（flow.rs）で判明した、コーパスに無い**実装上のギャップ2点**:

- **composer はゲートの外**: 接地ゲート全体が `flow.rs` の `if source_grounded_stage && !feedback_like`
  （≈L2708）一つの内側にある。synthesis/assemble/adjudication は `is_source_grounded_stage` が偽で
  *丸ごとスキップ*される。synthesis エントリは citation の*存在*しか検査されず、本文が引用に支持される
  かは誰も見ない。**＝assemble は無検査で発明できる。** verify は assemble の*前*に走るため、
  composer が新規に生んだ主張を再攻撃する敵対者もいない。
- **citation-backfill が provenance を捏造する**（≈`flow.rs:2692`）: citations が全て無効になったエントリに
  *直近入力5件*を自動で詰め直す（`citations_repaired`）。捏造した生成物にもっともらしい出典を着せ、
  retract 閉包と読み手から「接地済み」に見せる。検出を engine が自ら掘り崩す経路。

## 4. 手法: *govern the composer*
composer を起草者と同じ規律の中に入れる。4 機構、うち 3 つは*既存フラグの配線*、1 つは*削除*:

- **G — grounded composer**: 最終 composer ステージに `grounded = true`。各生成主張の factual premise を
  `meta.evidence_quote`（逐語）＋`source_path:source_line` で**一次資料の実ファイルに機械照合**する。
  読み取りで作った on-disk evidence-quote 接地を*そのまま生成側の前提検証に転用*できる（同じゲート、
  別ステージ）。inputs に無い「FSL は X ができる」は `evidence_quote_not_found`（needs_review）として
  per-claim 検出＝composer の*事実*捏造を殺す。**自由な賭けには evidence_quote を要求しない**
  （commitment と premise を物理的に分ける）。
- **V — 第二の verify→adjudication(retract)**: composer が**新規に生んだ**主張（最初の verify が見ていない）
  を独立赤チームが攻撃し、`per_input` 隔離審判が結論変更を出したら機械 retract する。これが gap #4 の
  「鋭い合成を*非 confab 化*する」未解決部分＝中央合成を*避けず*に同じ敵対規律に晒す解。
- **R — `retract_overturned` の前段適用**: 一次 adjudication にも `retract_overturned`。覆された方向を
  機械 retract し、後続 composer は status 駆動で*生存した前提だけ*を見る。「生存」を composer の
  指示順守に委ねず status で機械化（不変条件①）。
- **B — citation-backfill 撤去（engine／codex 担当）**: provenance 捏造を止め、citations を失った
  エントリは*空のまま*＋`invalid_citations_dropped` フラグを残す（no-silent-drop は維持）。捏造された
  provenance が G の接地を*偽装*できないようにする硬化。fallback 禁止の規約にも合致。

機構間の役割分担: **G が偽の事実を、V が偽の推論を**殺す（前提の真偽 vs 推論の妥当性は別の失敗様式）。
R は composer の入力を生存集合に絞り、B は G が騙されないようにする。

## 5. なぜ最小か（refute: これは複雑化の局所最適でないか）
- **新規コードはほぼゼロ**: G/V/R は既存の実証済みフラグ・ステージ型（`grounded`・`retract_overturned`・
  FALSIFY/COUNTER/ADJ パターン）の*設定*。engine 変更は B（*削除*）の 1 点のみ。
- **読み取り機構の再利用**: 生成の factual premise の接地先＝一次資料の実ファイル。読み取りで作った
  `quote_found_on_disk` がそのまま効く。**読み取りと生成は同一機構を別ステージに当てているだけ**。
- **continuity との両立**: 最終 composer は「拡散→連続性」の連続深掘りパス（[findings-continuity-vs-diffusion.md]）。
  on-disk 接地は codex が必要なファイルだけ read-only で開くため**文脈を膨らませない**＝arm W
  （全部入り単一文脈＝最低スコア）を再現しない。連続性の利得を保ったまま事実接地を足せる。

## 6. テストベッドと検証
**テストベッド: `scenarios/fsl-direction`**（fsl-codespec の*生成側の双子*。同じ FSL 題材で divergent
ideation、composer が2段=`select`→`initiatives`、従来は完全に無ゲート）。

upgrade（設定のみ）:
- `adjudication`: `retract_overturned = true`（R）。
- `initiatives`: `grounded = true`、各施策を*個別 decision*で出し、依拠 FSL 事実を `inputs/*.md` に
  on-disk 接地（G）。`agents.json` の INITIATIVES に接地契約を追記。
- 新 `verify_init`（INIT_FALSIFY/INIT_COUNTER、grounded）→ `adjudicate_init`（per_input ADJ,
  retract_overturned）（V）。

検証の三層（読み取りと同じ方法論）:
1. **catch ロジック**: 読み取りの既存 unit test が*そのまま*担保（`grounded_flag_enables_evidence_quote_gate`,
   `on_disk_evidence_quote_grounds_claim` ほか）。生成は同ゲートを別ステージで使うため再証明不要。
2. **配線**: mock smoke（`flow.mock.toml`）で確認済み — 接地ゲートは**grounded ステージ
   (`initiatives`/`verify_init`) でのみ発火**し、非 grounded 全ステージ（evidence/framing/directions/
   judge/critique/adjudication/select/adjudicate_init）では 0 警告。第二敵対パスは composer の*後*に走る。
3. **engine 硬化(B)・完了**: codex が `apply_core_gates` の citation-backfill を撤去（`selected` 引数・
   `ActorRunOutput.selected` フィールド・`fallback_citations` を削除し、本番6＋テスト9の呼出を更新）。
   citations が全無効になったエントリは*空のまま*＋`invalid_citations_dropped` フラグ（`citations_repaired`
   キー廃止＝provenance 捏造ゼロ）。独立検証（git diff ＋ 自前 `cargo test`）: **77+3 passed/1 ignored**、
   reading 接地テスト4本緑、backfill 依存の1本（`core_gates_coerce_output_type_and_repair_citations`）を
   新挙動（空 citations＋`invalid_citations_dropped`）へ更新。clippy は既存の `collapsible_if`（store.rs）のみ。
   （注: `cargo fmt` の toolchain skew で main.rs/store.rs に出る純フォーマット差分は本手法のスコープ外として未取込。）
4. **実 codex 検証（n=1・完了）**: `tracefield run --scenario-dir scenarios/fsl-direction`
   （codex-app-server・114 エントリ・最終 status: active 109 / retracted 5）。
   - **接地到達**: composer の主張5本が `inputs/*.md` 実ファイルに on-disk 接地（`evidence_grounded=on_disk`）。
     例 e87→`inputs/product-readme.md:6`（"…machine-readable JSON … write→verify→repair…"）、
     e101→`inputs/dogfood-findings.md:170`。**読み取りの on-disk ゲートが生成出力にそのまま効く**ことを実証。
   - **前提リーク catch＋retract（手法の核の真陽性）**: composer が出した施策1「Repair-Control Plane」(e87) は
     『GitHub Actions/Claude Code/Codex adapter で反例→修復PR を回す』ことを*事実前提*に置いたが、その adapter 群は
     inputs に無い。第二パス INIT_COUNTER(e100, `refutes=[e87]`) がこれを突き、ADJ(e112) が
     『判定: 結論変更を要する（未接地の事実前提を含む）』。`retract_overturned` が発火し **e87＋引用閉包で計5本を機械 retract**
     （e87 施策・e98/e100 反証・e110/e112 審判）＝gap#4「鋭い合成の未検証の推論的飛躍」を composer に対して殺した実例。
     **G が捕り逃した*暗黙*の未接地前提を V が捕える**（G＝偽の事実／V＝偽の推論、の分担を実測で確認）。
   - **捏造ゼロ・隠蔽ゼロ**: `evidence_quote_not_found`=0（実 codex は*明示*した quote には忠実＝読み取り run と同傾向）、
     `citations_repaired`=0／`invalid_citations_dropped`=0（**backfill 撤去を本番で確認**）。未接地の自由施策9本は
     `missing_evidence_quote`(needs_review) で正直に旗立て。審判 unclassified 1本も surfaced（no-silent-drop）。
   - **限界**: G の*捏造*catch（evidence_quote が source に無い）は本 run では自然発生せず（原理保証は unit test）。
     on-disk 接地率は initiatives 3/12（残りは自由 commitment か under-ground＝プロンプト調整余地）。n=1・単一シナリオ・単一モデル系。

5. **実 gemma4:26b 検証（n=1・弱モデルでの捏造発生プローブ・完了）**: `flow.gemma.toml`
   （ollama・composer は evidence を*文脈*で受け CitedStore 経路で接地。ollama は file を開けないため）。
   仮説（findings-lens-type §6.6「弱モデルほど忠実性が劣化」）＝gemma は FSL 事実を捏造し G が捕える。
   **結果は仮説を否定し、より示唆的だった**:
   - **捏造ゼロ（`evidence_quote_not_found`=0）**: gemma も evidence_quote を*捏造しない*。出すときは文脈の
     evidence ダイジェストから*正確にコピー*し（e63/e64→e6 を CitedStore 接地。e6 の FSL 事実 Lark/Z3/BMC/
     k-induction/3層方言/離散時刻SLA 等は **primary inputs に全て実在**＝grep 照合済みで接地は真正）、出せない
     ときは*省略*（`missing_evidence_quote`→needs_review）。**モデルは逐語 quote を捏造せず copy-or-omit する**
     ＝not_found は自然発生せず unit test の backstop に留まる。G の実運用価値は『接地するか・さもなくば
     needs_review で旗立て』であり、not_found は asserted-but-wrong-quote（≒偽の出典）の稀な場合の backstop。
   - **弱モデルの劣化は別所に fail-safe で出た**: gemma は `meta.refutes` を出さず（V の retract が標的を持てない）、
     審判は canonical `判定:` ラベルを産めず *unclassified*（adjudication 3／adjudicate_init 5）→ classify_verdict が
     **indeterminate として surfaced（no-silent-drop が弱モデル出力を捕捉）**、retract=0。**手法は弱モデルで
     偽の確信でなく indeterminate＋needs_review に劣化する（fail-safe）。**
   - **接地の基板依存（重要な含意）**: codex は*primary source*に on-disk 接地（堅牢）。ollama は file を開けず
     *文脈内の生成ダイジェスト*に CitedStore 接地するしかない＝**ダイジェストが忠実な場合のみ真正**（本 run は
     忠実だったと grep で確認）。**on-disk（一次資料）接地は CitedStore（上流エントリ）接地より厳密に強い**＝
     codex 基板の優位はファイル再オープンによる一次接地にある。

## 7. 限界（正直に）
- **自然発生（n=2 substrate）**: V パス（前提リーク→retract）の真陽性は codex で確認（§6.4）。G の*逐語 quote 捏造*
  catch は codex・gemma いずれでも自然発生せず（§6.5）＝**モデルは quote を copy-or-omit し捏造しない**ので not_found は
  unit test の backstop。弱モデル(gemma)の劣化は indeterminate＋needs_review に fail-safe（no-silent-drop）。
  逐語 quote 捏造（≒偽の出典）を*強制*した設定（文脈に source を与えず quote を要求）での catch 率は未測定。
- **接地の基板依存**: on-disk（一次資料・codex）接地 ＞ CitedStore（上流生成エントリ・ollama）接地。後者は上流が
  忠実な場合のみ真正＝弱モデルの ollama では「生成物に接地」する循環の危険があり、一次接地ほど強くない。
- **V は事実でなく*推論*を狙う**が、推論の妥当性判定は LLM 審判に残る（機械照合できるのは事実前提だけ）。
  gap #2（数値の第一原理導出）は本手法でも未解決＝発明数値は flag/probe 止まり。
- **commitment は接地しない**（設計）。自由な賭けが*悪い*賭けであることは G では捕まらない（V/judge の役割）。
- 一般化の限界はコーパス全体と同じ: 小 n・単一シナリオ・同系モデル。係数は未検証、方向のみ一般。
- composer が retract された前提を*本文に残す*問題は、可視化（aggregate）＋監査つき再実行(repair)で扱う
  （沈黙の再計算をしない＝不変条件③）。自動で artifact を書き換えはしない。

[findings-grounded-reading.md]: ./findings-grounded-reading.md
[findings-citation-precision.md]: ./findings-citation-precision.md
[findings-substrate-hetero.md]: ./findings-substrate-hetero.md
[findings-lens-type.md]: ./findings-lens-type.md
[findings-synthesizer-h5.md]: ./findings-synthesizer-h5.md
[findings-continuity-vs-diffusion.md]: ./findings-continuity-vs-diffusion.md
[findings-diffusion-thinking.md]: ./findings-diffusion-thinking.md
[findings-governance-vs-fusion.md]: ./findings-governance-vs-fusion.md
[findings-longrun-investigation.md]: ./findings-longrun-investigation.md

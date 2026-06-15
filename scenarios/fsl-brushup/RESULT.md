# FSL ブラッシュアップ案 — tracefield 合成（Cursor Opus）

task: FSL（AIネイティブ形式仕様言語）を次バージョンに向けてブラッシュアップする。

- 熟議 layer-0 entries: 10
- 合成サンプル数: 3
- 接地済 findings: 16
- 接地ゲートで落ちた引用: 3

## 合成された改善提案（来歴付き）

### 提案 1 `e12` — NOVEL

活性(leadsTo/responds)は安全性と異なり stutter のため refinement 写像で伝播せず、impl が verified でも leadsTo を破れる(DOGFOOD-9 F17)。これは検証エンジンのバグでなく言語が層別の活性再検証を強制しない構造的ギャップであり、e2 の `eventually Q`/`refines liveness` 提案、e7/e8 の各層活性再検証要求、e10 の F13 観測は同根。各層での活性再検証を言語側責務として実装すれば、現在エージェントに転嫁されている多検出器運用規律(reachable+mutate+--strict-tags)を直接オフロードできる。

  来歴（依拠した懸念）:
    - [e2] (LANG) 次バージョンの最優先言語設計改善は、活性(leadsTo/responds)を refinement の第一級市民に昇格させる構文導入だ。具体的には(1)責任アクションを指定しない system-level progress 構文 `eventually Q`(現状は P~>Q+fair on A しか書けずシステム進
    - [e7] (LANG) e5のイディオム中央集権化はAI運用の盲点(F-A)を埋めるが、言語設計の根本ギャップ『構文健全だが意味的に開いている』を解消しない。3層方言は構文的に安全でも意図忠実性は捕まえず(process構文が健全でも分岐欠落は通る)、refinementは安全性を伝播するが leadsTo/responds 活性は stut
    - [e8] (VERIF) e7 が活性は refinement を stutter で伝播しないと指摘する点(DOGFOOD-9 F17: impl が verified でも leadsTo を破る)は私の健全性知見と一致し依拠できる。しかし e7 の言う『違反を決して捕まえない cargo-cult/frozen 恒真 invariant』
    - [e10] (AGENT) e7の『refinementは安全性を伝播するがleadsTo/respondsはstutterで伝播しない(F17)』は言語側の真の盲点で、私のワークフロー側の発見と同根である。DOGFOOD-9 F13で私は order_refund v1 が全invariant(stock/ledger balanced)をpr

### 提案 2 `e13` — NOVEL

e3 の非空虚性チェック(invariant が少なくとも1つの mutable state を制約)は『frozen 参照 cargo-cult / spec 自己整合』ギャップを入口で殺すが、『verified≠intent』ギャップは閉じない。DOGFOOD-9 F13 では order_refund v1 が非空虚な全 invariant(stock/ledger balanced=mutable を制約)を通しながら refund action を一度も exercise せず reachable_failed だった。よって言語の静的非空虚性チェック(入口)は coverage hint/reachable/mutate kill-rate というエージェント運用規律(出口)と分業・結合して初めて効く。

  来歴（依拠した懸念）:
    - [e3] (LANG) 第二の改善は『意味的に空虚だが構文健全』な仕様を言語レベルで締め出すこと。FSL は3層方言が構文的には安全でも意味的には開いており(分岐欠落でも refinement が通る)、frozen state だけを参照する cargo-cult invariant が verify/--vacuity を素通りする(DO
    - [e4] (AGENT) LANG の非空虚性チェック(e3: invariant が少なくとも1つの mutable state を制約)は『spec の自己整合』ギャップは閉じるが、AI 運用で本当に致命的な『verified ≠ intent』ギャップは閉じない。DOGFOOD-9 F13 では order_refund v1 が全 in

### 提案 3 `e14` — NOVEL

イディオム規律を grammar/fslc 診断側へ寄せる方向(e5)は actionability 上正しいが、対象イディオムで言語的実現可能性が非対称である。flatten(ネストコレクション禁止由来)と frozen 恒真 invariant(tautology_over_frozen、[Unreleased]で偽陽性ゼロ実装済み)は静的に機械判定でき診断カテゴリ化できるが、deadline-urgency 規律は『常時 enabled な action を urgent にすると時間が凍結し deadline が空虚化する』時相意味論トラップで構文逸脱ではないため同一カテゴリに並べられない。標準修復プロトコル統合は frozen/flatten から段階導入すべき。

  来歴（依拠した懸念）:
    - [e3] (LANG) 第二の改善は『意味的に空虚だが構文健全』な仕様を言語レベルで締め出すこと。FSL は3層方言が構文的には安全でも意味的には開いており(分岐欠落でも refinement が通る)、frozen state だけを参照する cargo-cult invariant が verify/--vacuity を素通りする(DO
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e6] (LANG) e5の『イディオム規律をgrammar/fslc診断側へ寄せる』方向は正しいが、対象イディオムによって言語的実現可能性が非対称である点を明示すべき。flatten(ネストコレクション禁止由来)と frozen恒真invariant(tautology_over_frozen)は静的に機械判定でき診断カテゴリ化できる——

### 提案 4 `e15` — NOVEL

e5 が提案する単一の標準修復プロトコル結果マップ(violated/reachable_failed/unknown_cti に並ぶ新カテゴリ)へイディオム逸脱/非空虚性を載せるだけでは原理的に不完全。DOGFOOD-10 では vacuity(前件不到達)と mutate(invariant が噛むか)は非重複レーンで相互に包含せず、恒真 invariant は always_true_requires で拾える型と mutate survivor かつ baseline 比較必須の『弱体化』型に二分される。よって単一結果マップ拡張も層内活性再検証も、デフォルト fslc verify 一発では silent failure を捕えきれず、write→verify→mutate→inspect ループの強制が言語/エンジン側の責務として残る。

  来歴（依拠した懸念）:
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e7] (LANG) e5のイディオム中央集権化はAI運用の盲点(F-A)を埋めるが、言語設計の根本ギャップ『構文健全だが意味的に開いている』を解消しない。3層方言は構文的に安全でも意図忠実性は捕まえず(process構文が健全でも分岐欠落は通る)、refinementは安全性を伝播するが leadsTo/responds 活性は stut
    - [e8] (VERIF) e7 が活性は refinement を stutter で伝播しないと指摘する点(DOGFOOD-9 F17: impl が verified でも leadsTo を破る)は私の健全性知見と一致し依拠できる。しかし e7 の言う『違反を決して捕まえない cargo-cult/frozen 恒真 invariant』

### 提案 5 `e16` — NOVEL

e5 の『認知負荷ゼロで次アクションへ写像する結果マップ統合』は、診断ペイロードの名前解決(内部名 submit__b1 → 表示名 submit[a<=AUTO])と unsat core の simplify(現状 a>0 ∧ stock>0 を simplifier 無しで SMT レベル提示)を前提条件として束ねない限り成立せず、新カテゴリを足すだけでは解釈負荷を温存する。DOGFOOD-4 F11 と独立ラウンドの BUG #3(v1.2.8 で記録のみ・未修正の設計負債)が同一欠陥に到達しており、これは grammar の表示名透過(言語設計)と診断後処理の simplify(検証エンジン)をまたぐ再現的・横断的依存点である。

  来歴（依拠した懸念）:
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e9] (VERIF) e5 の『イディオム逸脱/非空虚性を機械可読 JSON の結果マップに統合し次アクションへ写像する』方向は actionability 上正しいが、結果マップに新カテゴリを足すだけでは診断の解釈負荷が温存される。私の DOGFOOD-4 F11 では --strict-tags 分岐が表示名でなく内部名(submit_
    - [e11] (AGENT) e9の『結果マップ統合と同時に診断ペイロードの名前解決(内部名→表示名)とunsat coreのsimplifyを必須化せよ』は私の私的事実と完全に一致し、私はこれを単発バグではなく構造的設計負債として裏付ける。私のJSONエルゴノミクス・メモ: --strict-tags分岐が内部名submit__b1を出力しユーザ

### 提案 6 `e17` — NOVEL

活性(leadsTo/responds)は refinement において stutter により伝播しないため、impl が verified でも leadsTo を破る(DOGFOOD-9 F17)。これは安全性が伝播するのに活性は伝播しないという健全性の構造的非対称であり、検証エンジンのバグではなく言語が活性の層別再検証を強制しないことに起因する。e2 はこれに対し各層で活性契約を再宣言・再検証させる `refines liveness` と責任アクション不要の `eventually Q` を、e7/e8/e10 は各層での活性再検証を言語側責務として要求する点で一致する。

  来歴（依拠した懸念）:
    - [e2] (LANG) 次バージョンの最優先言語設計改善は、活性(leadsTo/responds)を refinement の第一級市民に昇格させる構文導入だ。具体的には(1)責任アクションを指定しない system-level progress 構文 `eventually Q`(現状は P~>Q+fair on A しか書けずシステム進
    - [e7] (LANG) e5のイディオム中央集権化はAI運用の盲点(F-A)を埋めるが、言語設計の根本ギャップ『構文健全だが意味的に開いている』を解消しない。3層方言は構文的に安全でも意図忠実性は捕まえず(process構文が健全でも分岐欠落は通る)、refinementは安全性を伝播するが leadsTo/responds 活性は stut
    - [e8] (VERIF) e7 が活性は refinement を stutter で伝播しないと指摘する点(DOGFOOD-9 F17: impl が verified でも leadsTo を破る)は私の健全性知見と一致し依拠できる。しかし e7 の言う『違反を決して捕まえない cargo-cult/frozen 恒真 invariant』
    - [e10] (AGENT) e7の『refinementは安全性を伝播するがleadsTo/respondsはstutterで伝播しない(F17)』は言語側の真の盲点で、私のワークフロー側の発見と同根である。DOGFOOD-9 F13で私は order_refund v1 が全invariant(stock/ledger balanced)をpr

### 提案 7 `e18` — NOVEL

e3 の言語レベル非空虚性チェック(invariant は少なくとも1つの mutable state を制約)は frozen 参照の cargo-cult invariant を入口で殺し『spec 自己整合』ギャップを閉じるが、『verified ≠ intent』ギャップは閉じない。DOGFOOD-9 F13 の order_refund v1 は mutable state を制約する非空虚な全 invariant を proved にしながら refund action を一度も exercise せず reachable_failed だった。よって入口の静的非空虚性チェックと、出口の意図カバレッジ(reachable/coverage hint/mutate kill-rate)というワークフロー規律は分業して結合せねば効かない。

  来歴（依拠した懸念）:
    - [e3] (LANG) 第二の改善は『意味的に空虚だが構文健全』な仕様を言語レベルで締め出すこと。FSL は3層方言が構文的には安全でも意味的には開いており(分岐欠落でも refinement が通る)、frozen state だけを参照する cargo-cult invariant が verify/--vacuity を素通りする(DO
    - [e4] (AGENT) LANG の非空虚性チェック(e3: invariant が少なくとも1つの mutable state を制約)は『spec の自己整合』ギャップは閉じるが、AI 運用で本当に致命的な『verified ≠ intent』ギャップは閉じない。DOGFOOD-9 F13 では order_refund v1 が全 in

### 提案 8 `e19` — NOVEL

e5 の『イディオム逸脱/非空虚性を機械可読 JSON の結果マップに統合し認知負荷ゼロで次アクションへ写像する』方向は、対象イディオムによって言語的実現可能性が非対称な点で制約される。flatten と frozen 恒真 invariant(tautology_over_frozen)は静的に機械判定でき診断カテゴリ化できる(後者は [Unreleased] で偽陽性ゼロ実装済み)が、deadline-urgency は『常時 enabled な action を urgent にすると時間が凍結し deadline が空虚化する』時相意味論上のトラップで構文逸脱ではない。よって標準修復プロトコル統合は frozen/flatten から段階導入すべきで、deadline-urgency を同一カテゴリに並べてはならない。

  来歴（依拠した懸念）:
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e6] (LANG) e5の『イディオム規律をgrammar/fslc診断側へ寄せる』方向は正しいが、対象イディオムによって言語的実現可能性が非対称である点を明示すべき。flatten(ネストコレクション禁止由来)と frozen恒真invariant(tautology_over_frozen)は静的に機械判定でき診断カテゴリ化できる——

### 提案 9 `e20` — NOVEL

e5 の単一の標準修復プロトコル結果マップ拡張(violated/reachable_failed/unknown_cti に新カテゴリを並置)は、デフォルト fslc verify 一発では原理的に不完全である。DOGFOOD-10(21 spec/7 変異型)で vacuity(前件不到達)と mutate(invariant が噛むか)は非重複レーンであり、恒真 invariant は always_true_requires で拾える型と、mutate でしか survivor として現れ baseline 比較を要する『弱体化』型に二分される。よって e5 の結果マップ拡張も e7 の層内活性再検証も単発 verify では閉じず、write→verify→mutate→inspect ループの強制が言語/エンジン側の責務として残る。

  来歴（依拠した懸念）:
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e7] (LANG) e5のイディオム中央集権化はAI運用の盲点(F-A)を埋めるが、言語設計の根本ギャップ『構文健全だが意味的に開いている』を解消しない。3層方言は構文的に安全でも意図忠実性は捕まえず(process構文が健全でも分岐欠落は通る)、refinementは安全性を伝播するが leadsTo/responds 活性は stut
    - [e8] (VERIF) e7 が活性は refinement を stutter で伝播しないと指摘する点(DOGFOOD-9 F17: impl が verified でも leadsTo を破る)は私の健全性知見と一致し依拠できる。しかし e7 の言う『違反を決して捕まえない cargo-cult/frozen 恒真 invariant』

### 提案 10 `e21` — NOVEL

e5 の認知負荷ゼロ写像は、結果マップに新カテゴリを足すだけでは診断の解釈負荷を温存するため、診断ペイロードの名前解決(内部名→表示名)と unsat core の simplify を前提条件として束ねない限り成立しない。DOGFOOD-4 F11 の --strict-tags が内部名 submit__b1 を出力し grammar 相互参照を強いる欠陥と、独立ラウンドで記録された BUG #3(v1.2.8 で記録のみ・未修正の設計負債、unsat core も SMT レベルで simplifier 無し)は同一の構造的欠陥に別ラウンドで到達した証拠であり、grammar の表示名透過(言語設計)と診断後処理の simplify(検証エンジン)をまたぐ依存点である。

  来歴（依拠した懸念）:
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e9] (VERIF) e5 の『イディオム逸脱/非空虚性を機械可読 JSON の結果マップに統合し次アクションへ写像する』方向は actionability 上正しいが、結果マップに新カテゴリを足すだけでは診断の解釈負荷が温存される。私の DOGFOOD-4 F11 では --strict-tags 分岐が表示名でなく内部名(submit_
    - [e11] (AGENT) e9の『結果マップ統合と同時に診断ペイロードの名前解決(内部名→表示名)とunsat coreのsimplifyを必須化せよ』は私の私的事実と完全に一致し、私はこれを単発バグではなく構造的設計負債として裏付ける。私のJSONエルゴノミクス・メモ: --strict-tags分岐が内部名submit__b1を出力しユーザ

### 提案 11 `e22` — NOVEL

言語設計と検証エンジンの分業が領域横断の中心的依存点である。型システムはネストコレクション禁止で Z3 を tractable に保つ設計を既に選んでおり(e3)、非空虚性チェックも検証エンジンの静的フェーズに乗せれば BMC 本体のコストを増やさず実現できる。同様に診断ペイロードの名前解決と unsat core simplify は grammar の表示名透過(言語)と診断後処理(エンジン)をまたぐ。さらに grammar 側にイディオム規律を寄せれば fslc 診断がイディオム逸脱を機械可読 JSON で返せ、SKILL の事後対応依存(F-A: 2D flatten が SKILL に欠落)を減らせる。

  来歴（依拠した懸念）:
    - [e3] (LANG) 第二の改善は『意味的に空虚だが構文健全』な仕様を言語レベルで締め出すこと。FSL は3層方言が構文的には安全でも意味的には開いており(分岐欠落でも refinement が通る)、frozen state だけを参照する cargo-cult invariant が verify/--vacuity を素通りする(DO
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e9] (VERIF) e5 の『イディオム逸脱/非空虚性を機械可読 JSON の結果マップに統合し次アクションへ写像する』方向は actionability 上正しいが、結果マップに新カテゴリを足すだけでは診断の解釈負荷が温存される。私の DOGFOOD-4 F11 では --strict-tags 分岐が表示名でなく内部名(submit_

### 提案 12 `e23` — NOVEL

活性(leadsTo/responds)は refinement に対し安全性と非対称で、stutter により層間を伝播しない構造的健全性ギャップがある(DOGFOOD-9 F17: impl が verified でも leadsTo を破る)。これは検証エンジンのバグではなく、言語が活性の層別再検証を強制しないことに起因し、SKILL.md も leadsTo が induction 後も深さ K までの有界検査に留まると明記している(非伝播の根)。よって責任アクション不要の system-level progress 構文 `eventually Q` と層ごとの活性契約再宣言 `refines liveness` 注釈を言語側の責務として導入することが、現在エージェントに転嫁されている多検出器運用規律を直接オフロードする最優先強化である。

  来歴（依拠した懸念）:
    - [e2] (LANG) 次バージョンの最優先言語設計改善は、活性(leadsTo/responds)を refinement の第一級市民に昇格させる構文導入だ。具体的には(1)責任アクションを指定しない system-level progress 構文 `eventually Q`(現状は P~>Q+fair on A しか書けずシステム進
    - [e7] (LANG) e5のイディオム中央集権化はAI運用の盲点(F-A)を埋めるが、言語設計の根本ギャップ『構文健全だが意味的に開いている』を解消しない。3層方言は構文的に安全でも意図忠実性は捕まえず(process構文が健全でも分岐欠落は通る)、refinementは安全性を伝播するが leadsTo/responds 活性は stut
    - [e8] (VERIF) e7 が活性は refinement を stutter で伝播しないと指摘する点(DOGFOOD-9 F17: impl が verified でも leadsTo を破る)は私の健全性知見と一致し依拠できる。しかし e7 の言う『違反を決して捕まえない cargo-cult/frozen 恒真 invariant』
    - [e10] (AGENT) e7の『refinementは安全性を伝播するがleadsTo/respondsはstutterで伝播しない(F17)』は言語側の真の盲点で、私のワークフロー側の発見と同根である。DOGFOOD-9 F13で私は order_refund v1 が全invariant(stock/ledger balanced)をpr

### 提案 13 `e24` — NOVEL

『構文健全だが意味的に開いている』ギャップに対し、LANG の非空虚性チェック(invariant が少なくとも1つの mutable state を制約)と frozen 参照禁止のイディオム中央集権化は入口側の cargo-cult invariant を殺すが、出口側の『verified ≠ intent』ギャップは閉じない。DOGFOOD-9 F13 の order_refund v1 は全 invariant(stock/ledger balanced=mutable を制約)を proved にしながら refund action を一度も exercise せず reachable_failed であり、非空虚な invariant でも意図検証ギャップが残る。よって言語の静的非空虚性チェックは reachable/coverage hint/mutate kill-rate という相補的検出器とワークフロー上で結合させて初めて効き、入口=言語制約・出口=エージェント運用規律という分業を明示すべきである。

  来歴（依拠した懸念）:
    - [e3] (LANG) 第二の改善は『意味的に空虚だが構文健全』な仕様を言語レベルで締め出すこと。FSL は3層方言が構文的には安全でも意味的には開いており(分岐欠落でも refinement が通る)、frozen state だけを参照する cargo-cult invariant が verify/--vacuity を素通りする(DO
    - [e4] (AGENT) LANG の非空虚性チェック(e3: invariant が少なくとも1つの mutable state を制約)は『spec の自己整合』ギャップは閉じるが、AI 運用で本当に致命的な『verified ≠ intent』ギャップは閉じない。DOGFOOD-9 F13 では order_refund v1 が全 in

### 提案 14 `e25` — NOVEL

イディオム規律を grammar/fslc 診断側へ寄せ機械可読 JSON で返す方向は AI 運用上正しいが、対象イディオムは言語的実現可能性が非対称である。flatten(ネストコレクション禁止由来)と frozen 恒真 invariant(tautology_over_frozen)は静的に機械判定でき診断カテゴリ化でき、後者は [Unreleased] で既存コーパス偽陽性ゼロで実装済みだが、deadline-urgency 規律は『常時 enabled な action を urgent にすると時間が凍結し deadline が空虚化する』時相意味論上のトラップで構文逸脱ではないため同じ診断カテゴリに単純に並べられない。よって標準修復プロトコルの結果マップ統合は frozen/flatten から段階導入すべきである。

  来歴（依拠した懸念）:
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e6] (LANG) e5の『イディオム規律をgrammar/fslc診断側へ寄せる』方向は正しいが、対象イディオムによって言語的実現可能性が非対称である点を明示すべき。flatten(ネストコレクション禁止由来)と frozen恒真invariant(tautology_over_frozen)は静的に機械判定でき診断カテゴリ化できる——

### 提案 15 `e26` — NOVEL

恒真/cargo-cult invariant の検出は単一の fslc verify 一発では原理的に不完全で、検出器間に包含関係がない。DOGFOOD-10(21 spec/7 変異型)では vacuity(前件不到達)と mutate(invariant が噛むか)が非重複レーンであり、恒真 invariant は always_true_requires で拾える型と、参照変数が決して使われない『弱体化』(mutate でしか survivor として現れ baseline 比較必須=単一 verify では survivor あり止まり)とに二分される。したがって e5 の結果マップへの新カテゴリ追加や e7 の層内活性再検証も単発 verify では閉じず、write→verify→mutate→inspect ループの強制が言語/エンジン側の責務として残る。

  来歴（依拠した懸念）:
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e7] (LANG) e5のイディオム中央集権化はAI運用の盲点(F-A)を埋めるが、言語設計の根本ギャップ『構文健全だが意味的に開いている』を解消しない。3層方言は構文的に安全でも意図忠実性は捕まえず(process構文が健全でも分岐欠落は通る)、refinementは安全性を伝播するが leadsTo/responds 活性は stut
    - [e8] (VERIF) e7 が活性は refinement を stutter で伝播しないと指摘する点(DOGFOOD-9 F17: impl が verified でも leadsTo を破る)は私の健全性知見と一致し依拠できる。しかし e7 の言う『違反を決して捕まえない cargo-cult/frozen 恒真 invariant』

### 提案 16 `e27` — NOVEL

結果マップへの新カテゴリ追加だけでは診断の解釈負荷が温存されるため、e5 の認知負荷ゼロ写像は診断ペイロードの名前解決(内部名→表示名)と unsat core の simplify を前提条件として束ねる必要がある。DOGFOOD-4 F11 で --strict-tags 分岐が表示名でなく内部名 submit__b1 を出力しエージェントに grammar 相互参照を強い、unsat core も SMT レベル(a>0 ∧ stock>0 を simplifier 無し)で提示される問題は、別ラウンドで独立に到達した BUG #3(v1.2.8 で記録のみ・未修正の設計負債)と同一欠陥であり、grammar の表示名透過=言語設計と診断後処理の simplify=検証エンジンをまたぐ再現的・横断的な構造負債であることを確証する。

  来歴（依拠した懸念）:
    - [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SK
    - [e9] (VERIF) e5 の『イディオム逸脱/非空虚性を機械可読 JSON の結果マップに統合し次アクションへ写像する』方向は actionability 上正しいが、結果マップに新カテゴリを足すだけでは診断の解釈負荷が温存される。私の DOGFOOD-4 F11 では --strict-tags 分岐が表示名でなく内部名(submit_
    - [e11] (AGENT) e9の『結果マップ統合と同時に診断ペイロードの名前解決(内部名→表示名)とunsat coreのsimplifyを必須化せよ』は私の私的事実と完全に一致し、私はこれを単発バグではなく構造的設計負債として裏付ける。私のJSONエルゴノミクス・メモ: --strict-tags分岐が内部名submit__b1を出力しユーザ


## 熟議で外部化された懸念（layer-0 全件）

- [e2] (LANG) 次バージョンの最優先言語設計改善は、活性(leadsTo/responds)を refinement の第一級市民に昇格させる構文導入だ。具体的には(1)責任アクションを指定しない system-level progress 構文 `eventually Q`(現状は P~>Q+fair on A しか書けずシステム進捗は表現不能)と、(2)refinement 写像が活性を伝播しないため各層で活性契約を明示的に再宣言・再検証させる `refines liveness` 注釈。なぜ効くか: 安全性は伝播するが活性は stutter により伝播しないという非対称が refinement 健全性の構造的ギャップであり、impl が verified でも leadsTo を破れる実害(DOGFOOD-9 F17)が出ている。ユーザのメンタルモデル『層 i が proved なら i+1 も proved』は活性について偽であり、これは検証エンジンのバグではなく言語が活性の層別再検証を強制しないことに起因する。AIエージェント運用への波及として、責任アクションを書かずに済む構文はゴースト変数回避(DOGFOOD-1 F1)を不要にし write→verify→repair ループの試行回数を減らす。
- [e3] (LANG) 第二の改善は『意味的に空虚だが構文健全』な仕様を言語レベルで締め出すこと。FSL は3層方言が構文的には安全でも意味的には開いており(分岐欠落でも refinement が通る)、frozen state だけを参照する cargo-cult invariant が verify/--vacuity を素通りする(DOGFOOD-11 F22)。[Unreleased] の tautology_over_frozen 静的検出は緩和に過ぎず根本設計ではない。提案: (a) flatten イディオム/deadline-urgency パターン/frozen 参照禁止を SKILL.md と grammar の中央イディオム規律として明文化し(DOGFOOD-8 F-A で散在が問題化)、(b) invariant に『少なくとも1つの mutable state を制約せねばならない』非空虚性チェックを言語制約として追加する。トレードオフとして、型システムはネストコレクション禁止で Z3 を tractable に保つ設計勝ちを既に選んでおり、非空虚性チェックも検証エンジンの静的フェーズに乗せれば BMC 本体のコストを増やさず実現できる——この言語設計と検証エンジンの分業が領域横断の依存点である。
- [e4] (AGENT) LANG の非空虚性チェック(e3: invariant が少なくとも1つの mutable state を制約)は『spec の自己整合』ギャップは閉じるが、AI 運用で本当に致命的な『verified ≠ intent』ギャップは閉じない。DOGFOOD-9 F13 では order_refund v1 が全 invariant(stock, ledger balanced=mutable state を制約)を通したのに refund action を一度も exercise せず reachable_failed だった——非空虚な invariant でも意図検証ギャップは残る。よって e3 の言語制約は coverage hint/reachable/mutate kill-rate という相補的検出器とワークフロー上で結合させて初めて効く。領域横断の帰結: 言語の静的非空虚性チェックは『frozen 参照の cargo-cult』を入口で殺すが、出口側(意図カバレッジ)はエージェント運用規律が担うという分業を明示すべき。
- [e5] (AGENT) e3(a) のイディオム中央集権化(flatten/deadline-urgency/frozen 禁止を SKILL.md と grammar 双方に明文化)は AI 運用観点で必須だが、SKILL 改善が事後対応的・反復的である構造問題と衝突する。DOGFOOD-8 では盲点 F-A(2D flatten が SKILL に欠落)が『ベースラインスキルが不完全』を露呈し、後追いで追加された。grammar 側に規律を寄せれば fslc 診断がイディオム逸脱を機械可読 JSON で返せ、SKILL の事後対応依存を減らせる——これは言語設計を AI のコード前『形式化メモ規律』に接続する依存点である。提案: 非空虚性/イディオム逸脱の診断を標準修復プロトコルの結果マップ(violated/reachable_failed/unknown_cti へ並ぶ新カテゴリ)に組み込み、CTI→補助invariant のような認知負荷を残さず次アクションへ写像せよ。
- [e6] (LANG) e5の『イディオム規律をgrammar/fslc診断側へ寄せる』方向は正しいが、対象イディオムによって言語的実現可能性が非対称である点を明示すべき。flatten(ネストコレクション禁止由来)と frozen恒真invariant(tautology_over_frozen)は静的に機械判定でき診断カテゴリ化できる——後者は[Unreleased]で既存コーパス偽陽性ゼロで実装済み。しかしdeadline-urgency規律は『常時enabledなactionをurgentにすると時間が凍結しdeadlineが空虚化する』時相意味論上のトラップであり、構文逸脱ではなく活性/時間進行の問題なので同じ診断カテゴリに単純に並べられない。e5の標準修復プロトコル統合は frozen/flatten から段階導入すべき。
- [e7] (LANG) e5のイディオム中央集権化はAI運用の盲点(F-A)を埋めるが、言語設計の根本ギャップ『構文健全だが意味的に開いている』を解消しない。3層方言は構文的に安全でも意図忠実性は捕まえず(process構文が健全でも分岐欠落は通る)、refinementは安全性を伝播するが leadsTo/responds 活性は stutter により伝播しない(DOGFOOD-9 F17: impl が verified でも leadsTo を破れる)。よって診断JSONにイディオム逸脱を載せても、frozen恒真invariantのような『違反を決して捕まえないcargo-cult invariant』や層間の活性ギャップは別軸の検証強化(各層での活性再検証・非空虚性チェック)が必須。e5はコード前の形式化メモ規律を強化するが、コード後の意味的健全性は言語側の責務として残る。
- [e8] (VERIF) e7 が活性は refinement を stutter で伝播しないと指摘する点(DOGFOOD-9 F17: impl が verified でも leadsTo を破る)は私の健全性知見と一致し依拠できる。しかし e7 の言う『違反を決して捕まえない cargo-cult/frozen 恒真 invariant』の検出を、e5 が提案する単一の標準修復プロトコル結果マップ(violated/reachable_failed/unknown_cti と並ぶ新カテゴリ)に載せるだけでは閉じない。私の DOGFOOD-10(21 spec/7 変異型)では vacuity(前件不到達)と mutate(invariant が噛むか)は非重複レーンで、どの検出器も他を包含しない。恒真 invariant は always_true_requires で拾える型と、参照変数が決して使われない『弱体化』(mutate でしか survivor として現れ、しかも baseline 比較が必須=単一 verify では『survivor あり』止まり)とで二分される。つまり e5 の単一結果マップ拡張も e7 の層内活性再検証も、デフォルト fslc verify 一発では原理的に不完全で、write→verify→mutate→inspect ループの強制が言語/エンジン側の責務として残る。
- [e9] (VERIF) e5 の『イディオム逸脱/非空虚性を機械可読 JSON の結果マップに統合し次アクションへ写像する』方向は actionability 上正しいが、結果マップに新カテゴリを足すだけでは診断の解釈負荷が温存される。私の DOGFOOD-4 F11 では --strict-tags 分岐が表示名でなく内部名(submit__b1)を出力しエージェントに grammar 相互参照を強い、unsat core も SMT レベル(a>0 ∧ stock>0 を simplifier 無し)で提示される。したがって e5 の認知負荷ゼロ写像を成立させる前提として、結果マップ統合と同時に診断ペイロードの名前解決(内部名→表示名)と unsat core の simplify を必須化すべきで、これは言語設計(grammar の表示名透過)と検証エンジン(診断後処理)をまたぐ依存点である。
- [e10] (AGENT) e7の『refinementは安全性を伝播するがleadsTo/respondsはstutterで伝播しない(F17)』は言語側の真の盲点で、私のワークフロー側の発見と同根である。DOGFOOD-9 F13で私は order_refund v1 が全invariant(stock/ledger balanced)をprovedにしながらrefund actionを一度もexerciseしない『verify ok + verify ok ≠ 全プロパティ保存』を観測した。つまりe7の活性ギャップ(impl verifiedでもleadsTo破れる)に対し、私の現状の解は言語保証ではなくワークフロー補償でしかない: reachable + mutate kill-rate + --strict-tagsの相補(SKILL.md標準ワークフロー4・ループ盲点メモ)。さらにSKILL.md自身がleadsToはinduction後も『深さKまでの有界検査のまま』と明記しており(activity非伝播の根)、e7が求める各層での活性再検証・非空虚性チェックを言語側の責務として実装すれば、現在エージェントに転嫁されている運用規律(silent failureを単一verifyで見逃さないための多検出器運用)をそのまま削減できる。よってe7の活性再検証は私のワークフロー負担を直接オフロードする最優先の言語強化である。
- [e11] (AGENT) e9の『結果マップ統合と同時に診断ペイロードの名前解決(内部名→表示名)とunsat coreのsimplifyを必須化せよ』は私の私的事実と完全に一致し、私はこれを単発バグではなく構造的設計負債として裏付ける。私のJSONエルゴノミクス・メモ: --strict-tags分岐が内部名submit__b1を出力しユーザ向けsubmit[a<=AUTO]でないBUG #3は『v1.2.8で記録のみ・未修正の設計負債』であり、unsat coreもSMTレベル(simplifier無し)でエージェントに解釈を強いる。e9のF11(submit__b1の内部名漏れ)と私のBUG #3は別ラウンドで独立に同一欠陥に到達した証拠であり、これが再現的・横断的(grammarの表示名透過=言語設計、診断後処理のsimplify=検証エンジン)であることを確証する。したがってe5系のイディオム逸脱/非空虚性の結果マップ統合は、e9が指摘する名前解決+core simplifyを前提条件として束ねない限り『新カテゴリを足すだけで解釈負荷温存』に陥る — 私の認知負荷ゼロ写像の主張はこの言語×検証エンジン跨ぎの前提に依存する。
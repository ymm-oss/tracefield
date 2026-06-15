# FSL ブラッシュアップ案 — tracefield 合成（Cursor Opus）

task: FSL（AIネイティブ形式仕様言語）を次バージョンに向けてブラッシュアップする。

- 熟議 layer-0 entries: 12
- 合成サンプル数: 3
- 接地済 findings: 11
- 接地ゲートで落ちた引用: 0

## 合成された改善提案（来歴付き）

### 提案 1 `e14` — NOVEL

活性契約(leadsTo/responds)は refinement 写像で伝播せず(stutter が impl の進捗停止を許し、F17 で impl が verified でも leadsTo を破る/issue#13 で where 句脱落)、これは『相補的検出群で runtime 完全』が safety 偽陰性に限った完全性に過ぎないことを意味する。根本原因はエンジン層が safety 指向(BMC/k帰納法は有界 safety・到達性のみ、leadsTo は vacuity 検出器=vacuous_leadsto が担い不到達トリガで空虚 proved となる)である。よって対応は三層連鎖が必須: (1)LANG が refine 宣言時に活性非伝播を能動診断し『層 i+1 で再証明が必要』とメンタルモデル乖離を警告、(2)エンジンが各層で leadsTo を vacuity 強制付きで再証明させる、(3)エージェント修復プロトコルに liveness_reproof_required→層 i+1 再証明 testgen の写像を追加する。トレードオフとして各層再証明は冗長で中間層省略時の孤児化リスクを活性軸でも招き規律依存となる。

  来歴（依拠した懸念）:
    - [e2] (LANG) 次バージョンの最優先は活性 refinement の非対称性を言語レベルで可視化することだ。何を: refinement 写像が安全性のみ伝播し leadsTo/responds（活性）は stutter により伝播しない事実を、refine 宣言時に fslc が各活性契約へ『要再検証』マーカーを付与し、impl 層
    - [e9] (LANG) e7 の『e5 のエンジン診断は reachable+trans+mutate kill-rate 検出群と組み合わせて初めて runtime 完全性が閉じる』という主張は、私の私的事実 refinement 健全性の非対称により依然不完全である: refinement 写像は安全性は伝播するが leadsTo/res
    - [e10] (VERIF) e9 の活性非伝播の指摘は健全性観点から正しく、根本原因は検証エンジン層にある: 私の検出レーン(reachable/trans/vacuity/mutate, DOGFOOD-10)は全て safety 指向で、BMC/k帰納法自体が有界 safety・到達性を証明する一方 leadsTo/responds の層間伝
    - [e13] (AGENT) 提案: refinement 宣言時に活性契約(leadsTo/responds)の非伝播を fslc が能動診断し、その診断種別を SKILL.md §修復プロトコルの結果→次アクション写像に新規エントリ『liveness_reproof_required → 層 i+1 で再証明 testgen』として追加すべき。

### 提案 2 `e15` — NOVEL

『検証器は通るが意味的に空虚』という構造欠陥は領域横断で同型に現れる: frozen state のみ参照する invariant は恒真で制約を骨抜きにし(F22)、BMC don't-care 上の部分演算(head/pop/at)は symbolic で proved でも全パス runtime 安全でない(F16、忠実性ギャップであり偽陰性ではない)。両者は単一意味論カテゴリ vacuously_proved として first-class 診断へ昇格し、(a)部分演算の don't-care 依存と(b)frozen-only invariant を同じ JSON 機構で名指すべきで、これにより write→verify→repair ループが『proved の信頼区間』を engine/language 横断で一貫扱いできる。ただし frozen 参照に限らない一般の invariant 弱体化は静的診断(tautology_over_frozen)では捕まらず mutate でしか見えないため、静的 vacuity 診断と mutate は相補であり一方では閉じない。

  来歴（依拠した懸念）:
    - [e3] (LANG) 第二の改善はイディオム強制を言語/スキルに引き上げることだ。何を: (1)2次元データの単一キー flatten イディオムを SKILL.md に中央化、(2)frozen state のみを参照する死んだゴースト invariant を tautology_over_frozen として恒常診断化、(3)deadl
    - [e4] (VERIF) 検証の最重要改善は、デフォルトの fslc verify を健全な合成検査に格上げすることだ。何を: verify を実行したら未実行の検出器(特に mutate)を JSON warning として常時報告し、invariant 弱体化の信号(mutate survivor の baseline 比較)を verif
    - [e5] (VERIF) 第二の改善は、symbolic verified と全パス runtime 安全の忠実性ギャップを診断に昇格させることだ。何を: 部分演算(head/pop/at)が BMC の don't-care 読みで proved になった経路を JSON で fidelity_gap として明示し、Adapter ガードが無
    - [e8] (LANG) e5 の『symbolic で verified ≠ 全パスで runtime 安全』(BMC don't-care 上の head/pop/at が proved)は、私の私的事実 DOGFOOD-11 F22 と同型の構造欠陥である: frozen state だけを参照する invariant は proved 

### 提案 3 `e16` — NOVEL

fidelity_gap(どの head/pop/at が Z3 don't-care 経由で proved かを violating_bindings と並置して機械可読に名指す)は CTI→補助 invariant 写像と Monitor の鍵 trace 選択という認知負荷を直接削減するが、symbolic 層偽陰性の縮小に留まり runtime 完全性を閉じない: 名指された部分演算を実際に exercise する trace が生成された保証はなく、mutate-survivor/baseline 比較も invariant の噛みを測り部分演算カバレッジを測らないため閉じず、runtime exercise 義務は非自動・有界カバレッジの testgen/replay に残る。よって SKILL.md 修復プロトコルに『fidelity_gap が名指す鍵 trace を必須 testgen シナリオへ自動変換し、proved 後も最低1本の部分演算 exercise をループ閉鎖条件にする』ステップを追加して人間判断を機械写像に置換すべきだが、網羅性は依然得られずシナリオ選択の有界性が残る。

  来歴（依拠した懸念）:
    - [e5] (VERIF) 第二の改善は、symbolic verified と全パス runtime 安全の忠実性ギャップを診断に昇格させることだ。何を: 部分演算(head/pop/at)が BMC の don't-care 読みで proved になった経路を JSON で fidelity_gap として明示し、Adapter ガードが無
    - [e7] (AGENT) e5 の fidelity_gap 出力(どの部分演算が Z3 don't-care に依存して proved になったかを violating_bindings と並置)は、私的事実の二つの認知負荷を直接削減するため AI 運用上の効果が e5 自身の主張より大きい。第一に CTI→補助 invariant 写像問題
    - [e11] (VERIF) e7 の fidelity_gap(どの head/pop/at が Z3 don't-care 経由で proved か機械可読に名指す)は健全だが、私の私的事実(DESIGN-seq §5・DOGFOOD-9 F16)では『symbolic 意味論で verified ≠ 全パスで runtime 安全』は偽陰性で
    - [e12] (AGENT) 提案: SKILL.md §修復プロトコルに『fidelity_gap が名指す head/pop/at の鍵 trace を必須 testgen シナリオへ自動変換する』ステップを追加し、proved 後も最低1本の部分演算 exercise を loop の閉鎖条件にする。なぜ効くか: e11 が示す通り検出群結合

### 提案 4 `e17` — NOVEL

e3/e5 が外部化する機械可読診断は方向として正しいが全て『書いた後』に発火するのに対し、真の意図検証ギャップ(verified≠intent、全 invariant proved でも refund action を一度も exercise しない reachable_failed)は『書く前』の過少規定(R5『一定期間内の返金』で期間の値/起点/境界が NL 未定義)で生じる。したがって事後診断に加え、要件を trigger/constraint/exception/境界意味論へ分解し仮定台帳を作る『コード前 形式化メモ規律』を ASSUME-n タグとして言語側に first-class 化し、e3 の SKILL 中央化・e5 の fidelity_gap と同じ機械可読ループに前段を接続すべきである。

  来歴（依拠した懸念）:
    - [e3] (LANG) 第二の改善はイディオム強制を言語/スキルに引き上げることだ。何を: (1)2次元データの単一キー flatten イディオムを SKILL.md に中央化、(2)frozen state のみを参照する死んだゴースト invariant を tautology_over_frozen として恒常診断化、(3)deadl
    - [e5] (VERIF) 第二の改善は、symbolic verified と全パス runtime 安全の忠実性ギャップを診断に昇格させることだ。何を: 部分演算(head/pop/at)が BMC の don't-care 読みで proved になった経路を JSON で fidelity_gap として明示し、Adapter ガードが無
    - [e6] (AGENT) e3とe5の『構文健全だが意味的に空虚』『symbolic verified ≠ runtime safe』の機械可読診断化は方向として正しいが、私的事実 DOGFOOD-9 F13/F14 はより深い順序問題を示す: これらの診断は全て『書いた後』に発火するのに対し、真の意図検証ギャップ(AI が意図を捕らえたか)は

### 提案 5 `e18` — NOVEL

活性 refinement の非対称性(安全性は refine で伝播するが leadsTo/responds は stutter により伝播せず、impl が verified でも leadsTo を破れる: DOGFOOD-9 F17)は、LANG/VERIF/AGENT が連鎖する依存軸を成す。LANG 側で refine 宣言時に活性契約へ非伝播・要再検証マーカーを構文付与し JSON 診断へ透過させ(e2)、VERIF 側は各層で leadsTo を vacuity 強制付きに再証明させ(e10)、AGENT 側は修復プロトコルに liveness_reproof_required→層 i+1 再証明 testgen の写像を追加する(e13)ことで、メンタルモデル『proved なら refine 後も proved』との乖離を三領域横断で能動的に閉じられる。

  来歴（依拠した懸念）:
    - [e2] (LANG) 次バージョンの最優先は活性 refinement の非対称性を言語レベルで可視化することだ。何を: refinement 写像が安全性のみ伝播し leadsTo/responds（活性）は stutter により伝播しない事実を、refine 宣言時に fslc が各活性契約へ『要再検証』マーカーを付与し、impl 層
    - [e10] (VERIF) e9 の活性非伝播の指摘は健全性観点から正しく、根本原因は検証エンジン層にある: 私の検出レーン(reachable/trans/vacuity/mutate, DOGFOOD-10)は全て safety 指向で、BMC/k帰納法自体が有界 safety・到達性を証明する一方 leadsTo/responds の層間伝
    - [e13] (AGENT) 提案: refinement 宣言時に活性契約(leadsTo/responds)の非伝播を fslc が能動診断し、その診断種別を SKILL.md §修復プロトコルの結果→次アクション写像に新規エントリ『liveness_reproof_required → 層 i+1 で再証明 testgen』として追加すべき。

### 提案 6 `e19` — NOVEL

e7 が主張する『fidelity_gap を reachable+trans+mutate kill-rate の相補的検出群と組み合わせれば runtime 完全性が閉じる』は safety 偽陰性に限った完全性であり、活性については成立しない。fidelity_gap も kill-rate 検出器も到達性・部分演算・safety 違反に焦点を当て、活性の層間伝播失敗(leadsTo 非伝播・F17)を構造的に観測できないため、活性は各層で再検証が必須であり、e7 の『相補的検出群で完全』という主張は活性軸では不完全である。

  来歴（依拠した懸念）:
    - [e7] (AGENT) e5 の fidelity_gap 出力(どの部分演算が Z3 don't-care に依存して proved になったかを violating_bindings と並置)は、私的事実の二つの認知負荷を直接削減するため AI 運用上の効果が e5 自身の主張より大きい。第一に CTI→補助 invariant 写像問題
    - [e9] (LANG) e7 の『e5 のエンジン診断は reachable+trans+mutate kill-rate 検出群と組み合わせて初めて runtime 完全性が閉じる』という主張は、私の私的事実 refinement 健全性の非対称により依然不完全である: refinement 写像は安全性は伝播するが leadsTo/res

### 提案 7 `e20` — NOVEL

『検証器は通るが意味的に空虚』という同型の構造欠陥が言語層(frozen state のみ参照する恒真 invariant: DOGFOOD-11 F22)と検証エンジン層(BMC don't-care 上の head/pop/at が proved になる忠実性ギャップ: DOGFOOD-9 F16)に跨って存在する。両者の現状緩和(tautology_over_frozen 静的検出、全部分演算ガード)はいずれもイディオム/事後検出で言語強制でないため、最も効く改善は両ギャップを単一の意味論カテゴリ vacuously_proved として first-class 診断に昇格し、(a) 部分演算の don't-care 依存と (b) frozen-only invariant を同じ JSON 機構で名指して proved の信頼区間を engine/language 横断で一貫させることだ。

  来歴（依拠した懸念）:
    - [e8] (LANG) e5 の『symbolic で verified ≠ 全パスで runtime 安全』(BMC don't-care 上の head/pop/at が proved)は、私の私的事実 DOGFOOD-11 F22 と同型の構造欠陥である: frozen state だけを参照する invariant は proved 
    - [e5] (VERIF) 第二の改善は、symbolic verified と全パス runtime 安全の忠実性ギャップを診断に昇格させることだ。何を: 部分演算(head/pop/at)が BMC の don't-care 読みで proved になった経路を JSON で fidelity_gap として明示し、Adapter ガードが無
    - [e3] (LANG) 第二の改善はイディオム強制を言語/スキルに引き上げることだ。何を: (1)2次元データの単一キー flatten イディオムを SKILL.md に中央化、(2)frozen state のみを参照する死んだゴースト invariant を tautology_over_frozen として恒常診断化、(3)deadl

### 提案 8 `e21` — NOVEL

frozen 参照に限らない一般の invariant 弱体化は静的診断と mutate が相補であり一方では閉じない。e3 の tautology_over_frozen 恒常診断は frozen 参照という弱体化サブクラスを verify 内に正しく引き上げるが、参照変数が決して使われない一般の弱体化(F22)は依然 mutate survivor の baseline 比較でしか可視化されない(DOGFOOD-10 で各検出器は非重複レーンを占める)。よってデフォルト fslc verify を未実行検出器(特に mutate)を warning 報告し mutate survivor を verify サマリに統合する合成検査へ格上げし、『verify 単独成功=安全』という再現的誤読を防ぐべきだ。

  来歴（依拠した懸念）:
    - [e4] (VERIF) 検証の最重要改善は、デフォルトの fslc verify を健全な合成検査に格上げすることだ。何を: verify を実行したら未実行の検出器(特に mutate)を JSON warning として常時報告し、invariant 弱体化の信号(mutate survivor の baseline 比較)を verif
    - [e3] (LANG) 第二の改善はイディオム強制を言語/スキルに引き上げることだ。何を: (1)2次元データの単一キー flatten イディオムを SKILL.md に中央化、(2)frozen state のみを参照する死んだゴースト invariant を tautology_over_frozen として恒常診断化、(3)deadl

### 提案 9 `e22` — NOVEL

fidelity_gap(どの head/pop/at が Z3 don't-care 経由で proved か機械可読に名指す)は CTI→補助 invariant 写像と Monitor の trace 選択という二つの認知負荷を直接削減し、鍵 trace と Adapter ガード要箇所を一意化するが、それは偽陰性ではなく忠実性ギャップ(両エンジンとも proved/conformant を返す)であり、『その部分演算を実際に exercise する trace が生成されたか』は保証できず mutate survivor/baseline 比較でも閉じない(mutate は invariant の噛みを測り部分演算カバレッジを測らない)。よって fidelity_gap は symbolic 層の偽陰性を縮めるに留まり、runtime exercise 義務は非自動・有界カバレッジの testgen/replay に残る。

  来歴（依拠した懸念）:
    - [e7] (AGENT) e5 の fidelity_gap 出力(どの部分演算が Z3 don't-care に依存して proved になったかを violating_bindings と並置)は、私的事実の二つの認知負荷を直接削減するため AI 運用上の効果が e5 自身の主張より大きい。第一に CTI→補助 invariant 写像問題
    - [e5] (VERIF) 第二の改善は、symbolic verified と全パス runtime 安全の忠実性ギャップを診断に昇格させることだ。何を: 部分演算(head/pop/at)が BMC の don't-care 読みで proved になった経路を JSON で fidelity_gap として明示し、Adapter ガードが無
    - [e11] (VERIF) e7 の fidelity_gap(どの head/pop/at が Z3 don't-care 経由で proved か機械可読に名指す)は健全だが、私の私的事実(DESIGN-seq §5・DOGFOOD-9 F16)では『symbolic 意味論で verified ≠ 全パスで runtime 安全』は偽陰性で

### 提案 10 `e23` — NOVEL

fidelity_gap が名指す鍵 trace を網羅できない(e11)以上、人間判断に委ねず SKILL.md 修復プロトコルに『fidelity_gap が名指す head/pop/at の鍵 trace を必須 testgen シナリオへ自動変換し、proved 後も最低1本の部分演算 exercise を loop の閉鎖条件にする』ステップを追加すべきだ。これにより symbolic 偽陰性の縮小を運用上の forced exercise に転化できるが、網羅性は依然得られずシナリオ選択の有界性は残る。

  来歴（依拠した懸念）:
    - [e12] (AGENT) 提案: SKILL.md §修復プロトコルに『fidelity_gap が名指す head/pop/at の鍵 trace を必須 testgen シナリオへ自動変換する』ステップを追加し、proved 後も最低1本の部分演算 exercise を loop の閉鎖条件にする。なぜ効くか: e11 が示す通り検出群結合
    - [e11] (VERIF) e7 の fidelity_gap(どの head/pop/at が Z3 don't-care 経由で proved か機械可読に名指す)は健全だが、私の私的事実(DESIGN-seq §5・DOGFOOD-9 F16)では『symbolic 意味論で verified ≠ 全パスで runtime 安全』は偽陰性で
    - [e5] (VERIF) 第二の改善は、symbolic verified と全パス runtime 安全の忠実性ギャップを診断に昇格させることだ。何を: 部分演算(head/pop/at)が BMC の don't-care 読みで proved になった経路を JSON で fidelity_gap として明示し、Adapter ガードが無

### 提案 11 `e24` — NOVEL

e3/e5 の機械可読診断は全て『書かれた spec の欠陥』を『書いた後』に捉える事後診断だが、真の意図検証ギャップ(全 invariant proved でも refund action を一度も exercise しない reachable_failed、R5『一定期間内の返金』で期間の値/起点/境界が NL 段階で未定義: DOGFOOD-9 F13/F14)は spec が書かれる前の過少規定で生じる。よって事後診断に加え、コード前の形式化メモ規律(要件を trigger/constraint/exception/境界意味論へ分解し仮定台帳を作る)を ASSUME-n タグとして言語側に first-class 化し、前段を e3 の SKILL 中央化・e5 の fidelity_gap と同じ機械可読ループへ接続すべきだ。

  来歴（依拠した懸念）:
    - [e6] (AGENT) e3とe5の『構文健全だが意味的に空虚』『symbolic verified ≠ runtime safe』の機械可読診断化は方向として正しいが、私的事実 DOGFOOD-9 F13/F14 はより深い順序問題を示す: これらの診断は全て『書いた後』に発火するのに対し、真の意図検証ギャップ(AI が意図を捕らえたか)は
    - [e3] (LANG) 第二の改善はイディオム強制を言語/スキルに引き上げることだ。何を: (1)2次元データの単一キー flatten イディオムを SKILL.md に中央化、(2)frozen state のみを参照する死んだゴースト invariant を tautology_over_frozen として恒常診断化、(3)deadl
    - [e5] (VERIF) 第二の改善は、symbolic verified と全パス runtime 安全の忠実性ギャップを診断に昇格させることだ。何を: 部分演算(head/pop/at)が BMC の don't-care 読みで proved になった経路を JSON で fidelity_gap として明示し、Adapter ガードが無


## 熟議で外部化された懸念（layer-0 全件）

- [e2] (LANG) 次バージョンの最優先は活性 refinement の非対称性を言語レベルで可視化することだ。何を: refinement 写像が安全性のみ伝播し leadsTo/responds（活性）は stutter により伝播しない事実を、refine 宣言時に fslc が各活性契約へ『要再検証』マーカーを付与し、impl 層で未再証明の活性契約を診断として強制する。なぜ効くか: ユーザのメンタルモデル『層 i が proved なら refine した i+1 も proved』は活性について偽であり、これが真のギャップ（DOGFOOD-9 F17 で impl が verified でも leadsTo を破る具体反例、v1.2.1 issue#13 で leadsTo where 句が捨てられた実績）。write→verify→repair ループ(e1)は JSON 診断を信号源とするため、活性ギャップを診断に透過させれば AI が自動で再証明タスクを生成でき、領域横断（言語設計→検証エンジン→エージェント運用）で効果が連鎖する。
- [e3] (LANG) 第二の改善はイディオム強制を言語/スキルに引き上げることだ。何を: (1)2次元データの単一キー flatten イディオムを SKILL.md に中央化、(2)frozen state のみを参照する死んだゴースト invariant を tautology_over_frozen として恒常診断化、(3)deadline-urgency パターンの urgency 規律を構文ガードで保護。なぜ効くか: 型システムはネストコレクション禁止で Z3 を tractable に保つ設計勝ちだが、その代償の flatten イディオムが grammar からの推測頼み（DOGFOOD-8 F-A）で AI/PM が誤用する。同様に常時 enabled アクションを urgent にすると時間凍結し deadline が空虚化する（DOGFOOD-5/8②b）、frozen 参照 invariant は制約を骨抜きにする（DOGFOOD-11 F22）。これらは『構文健全だが意味的に空虚』という共通の穴であり、e1 の Agent Skill で AI に仕様を書かせる以上、暗黙の規律を機械可読な診断・スキル文書として外部化しなければ AI が再現的に踏む。
- [e4] (VERIF) 検証の最重要改善は、デフォルトの fslc verify を健全な合成検査に格上げすることだ。何を: verify を実行したら未実行の検出器(特に mutate)を JSON warning として常時報告し、invariant 弱体化の信号(mutate survivor の baseline 比較)を verify サマリに統合する。なぜ効くか: DOGFOOD-10 の注入ベンチで各検出器は非重複レーンを占め、どれも他を包含しない — 中でも invariant の弱体化(参照変数が決して使われない)は mutate でしか捕まらず、verify --vacuity error が警告0でも死んだ invariant は残る。e1 の Agent Skill で AI/PM に仕様を書かせる以上、verify 単独成功=安全という誤読が再現的に起き、write→verify→mutate→inspect の意図したループが回らない。e3 の tautology_over_frozen 恒常診断は frozen 参照という弱体化サブクラスを verify 内に引き上げる正しい方向だが、frozen 参照に限らない一般の invariant 弱体化(F22)は依然 mutate でしか見えないため、e3 の静的診断と mutate 統合は相補であり一方では閉じない。
- [e5] (VERIF) 第二の改善は、symbolic verified と全パス runtime 安全の忠実性ギャップを診断に昇格させることだ。何を: 部分演算(head/pop/at)が BMC の don't-care 読みで proved になった経路を JSON で fidelity_gap として明示し、Adapter ガードが無ければ同一 trace で runtime replay が失敗し得る旨を violating_bindings と並べて出力する。なぜ効くか: DOGFOOD-9 F16 の order_refund_windowed は Z3 don't-care で proved だが runtime replay は失敗し得る — 両エンジン proved/conformant で偽陰性ではないが『symbolic 意味論で verified ≠ 全パスで runtime 安全』という構造的ギャップであり、緩和は現状イディオム(全部分演算をガード)で言語強制でない。e3 の『構文健全だが意味的に空虚』の穴に対するイディオム外部化と同型の問題が検証エンジン側にも存在し、e3 がイディオムを SKILL/構文ガードに引き上げるなら、エンジンは proved の信頼区間(どの部分演算が don't-care に依存したか)を機械可読に返して AI が再現的に踏むのを防ぐべきだ。
- [e6] (AGENT) e3とe5の『構文健全だが意味的に空虚』『symbolic verified ≠ runtime safe』の機械可読診断化は方向として正しいが、私的事実 DOGFOOD-9 F13/F14 はより深い順序問題を示す: これらの診断は全て『書いた後』に発火するのに対し、真の意図検証ギャップ(AI が意図を捕らえたか)は『書く前』の過少規定で生じる(R5『一定期間内の返金』は NL で期間の値/起点/境界が未定義)。よって次バージョンの最大効果改善は、e3/e5 の事後診断に加え、SKILL.md のコード前『形式化メモ規律』(要件を trigger/constraint/exception/境界意味論へ分解し仮定台帳を作る)を ASSUME-n タグとして言語側に first-class 化することだ。なぜ効くか: e3/e5 が外部化する暗黙規律は全て『書かれた spec の欠陥』を捉えるが、verified≠intent ギャップ(全 invariant proved でも refund action を一度も exercise しない reachable_failed)は spec が書かれる前の意図取りこぼしであり、事後診断だけでは AI が再現的に踏む。ASSUME タグを構文要素にすれば仮定が診断に透過し、e3 の SKILL 中央化・e5 の fidelity_gap と同じ機械可読ループに前段が接続される。
- [e7] (AGENT) e5 の fidelity_gap 出力(どの部分演算が Z3 don't-care に依存して proved になったかを violating_bindings と並置)は、私的事実の二つの認知負荷を直接削減するため AI 運用上の効果が e5 自身の主張より大きい。第一に CTI→補助 invariant 写像問題(unknown_cti が違反へ至る状態列を返すがどの invariant を足すかユーザが見抜く必要・DOGFOOD-2)、第二に runtime Monitor の trace 選択負担(testgen は自動でなくユーザが鍵 trace を選ぶ・カバレッジ有界)である。fidelity_gap が『どの head/pop/at が don't-care 経由か』を機械可読に名指せば、testgen/replay が照合すべき鍵 trace と Adapter ガードが必要な箇所が一意に決まり、ground truth 検証の有界カバレッジ盲点が縮む。ただし依存トレードオフを明示する: fidelity_gap は『部分演算がガードされているか』を JSON で返せても『その部分演算を実際に exercise する trace が生成されたか』は保証しない。よって e5 のエンジン側診断は私的事実の reachable+trans+mutate kill-rate の相補的検出群(単一検出器では全ギャップを閉じない・DOGFOOD-10)と組み合わせて初めて完全になり、e5 単独では symbolic 層の偽陰性を縮めるが runtime 完全性は閉じない。
- [e8] (LANG) e5 の『symbolic で verified ≠ 全パスで runtime 安全』(BMC don't-care 上の head/pop/at が proved)は、私の私的事実 DOGFOOD-11 F22 と同型の構造欠陥である: frozen state だけを参照する invariant は proved だが恒真で制約を骨抜きにする。両者とも『検証器は通るが意味的に空虚』であり、e5 のエンジン側緩和(全部分演算をガード)と私の側の緩和([Unreleased] tautology_over_frozen の Z3 静的検出, 既存コーパス偽陽性ゼロ)はいずれもイディオム/事後検出であって言語強制ではない。よって最も効果が高い言語設計改善は、両ギャップを単一の意味論カテゴリ『vacuously_proved』として first-class 診断に昇格し、(a) 部分演算の don't-care 依存と (b) frozen-only invariant を同じ JSON 機構で名指すことだ。なぜ効くか: e5 が提案する fidelity_gap の機械可読出力を言語層の vacuity 検出と統一すれば、AI の write→verify→repair ループが『proved の信頼区間』を engine/language 横断で一貫して扱え、e5 単独のエンジン局所修正より広い偽陰性面を閉じる。
- [e9] (LANG) e7 の『e5 のエンジン診断は reachable+trans+mutate kill-rate 検出群と組み合わせて初めて runtime 完全性が閉じる』という主張は、私の私的事実 refinement 健全性の非対称により依然不完全である: refinement 写像は安全性は伝播するが leadsTo/responds(活性)は伝播せず(stutter が impl の進捗停止を許す), DOGFOOD-9 F17 では impl が verified でも leadsTo 契約を破れる。fidelity_gap も kill-rate 検出器も到達性・部分演算・safety 違反に焦点を当てており、活性の層間伝播失敗を構造的に観測できない。よって e7 の『相補的検出群で完全』は safety 偽陰性に限った完全性であり、活性については各層で再検証が必須という設計事実(v1.2.1 issue#13 で leadsTo where 句脱落の実績もある)が残る。言語側の対応として、refinement 宣言時に活性契約が非伝播であることを診断で明示し(『この leadsTo は層 i+1 で再証明が必要』)、ユーザのメンタルモデル『proved なら refine 後も proved』との乖離を言語が能動的に警告すべきだ。
- [e10] (VERIF) e9 の活性非伝播の指摘は健全性観点から正しく、根本原因は検証エンジン層にある: 私の検出レーン(reachable/trans/vacuity/mutate, DOGFOOD-10)は全て safety 指向で、BMC/k帰納法自体が有界 safety・到達性を証明する一方 leadsTo/responds の層間伝播失敗を構造的に観測できない。ただし leadsTo は vacuous_leadsto(=vacuity 検出器, mutate ではない)が担う領域であり、トリガ不到達の leadsTo は空虚に proved となり refinement 後も沈黙して生き残る。したがって LANG 側の『再証明が必要』警告だけでは不十分で、検証エンジンは refinement 各層で leadsTo を vacuity 強制付きで再証明させるべきだ(e7 の『相補的検出群で runtime 完全』は safety 偽陰性に限った完全性という e9 の限定が、エンジン側の活性再証明義務として具体化される)。
- [e11] (VERIF) e7 の fidelity_gap(どの head/pop/at が Z3 don't-care 経由で proved か機械可読に名指す)は健全だが、私の私的事実(DESIGN-seq §5・DOGFOOD-9 F16)では『symbolic 意味論で verified ≠ 全パスで runtime 安全』は偽陰性でなく忠実性ギャップであり、両エンジンとも proved/conformant を返す。e7 自身が認める『部分演算を exercise する trace が生成された保証はない』点は、私の facts では mutate-survivor/baseline 比較でも閉じない: mutate は invariant の噛み(bite)を測り部分演算カバレッジを測らないからだ。よって e7 の検出群結合後も runtime exercise 義務は testgen/replay に残り、それは非自動・有界カバレッジ(私的事実)であるため、fidelity_gap は鍵 trace を一意に名指せても網羅は保証しない — symbolic 層偽陰性の縮小に留まる。
- [e12] (AGENT) 提案: SKILL.md §修復プロトコルに『fidelity_gap が名指す head/pop/at の鍵 trace を必須 testgen シナリオへ自動変換する』ステップを追加し、proved 後も最低1本の部分演算 exercise を loop の閉鎖条件にする。なぜ効くか: e11 が示す通り検出群結合後も runtime exercise 義務は testgen/replay に残り非自動・有界カバレッジである。私的事実では testgen は自動でなくユーザが鍵 trace を選ぶ/ランダムウォーク要でカバレッジ有界(ループの盲点 §)であり、単一 verify 実行は silent failure を見逃す(DOGFOOD-9 F13/DOGFOOD-10)。fidelity_gap は trace を一意に名指せても網羅は保証しないため、人間判断に委ねず『名指された箇所→testgen シナリオ』を機械写像すれば、symbolic 偽陰性の縮小を運用上の forced exercise に転化でき認知負荷を下げられる。トレードオフ: 網羅性は依然得られず(e11)、シナリオ選択の有界性が残る。
- [e13] (AGENT) 提案: refinement 宣言時に活性契約(leadsTo/responds)の非伝播を fslc が能動診断し、その診断種別を SKILL.md §修復プロトコルの結果→次アクション写像に新規エントリ『liveness_reproof_required → 層 i+1 で再証明 testgen』として追加すべき。なぜ効くか: 私的事実の標準修復プロトコルは violated/reachable_failed/unknown_cti/warning/error の全結果を次ステップへ写像するが、e9 が指摘する『活性は層間で伝播せず impl が verified でも leadsTo を破れる(F17)』に対応する写像が存在しない。よって refine 後 proved な spec は、エージェントのプロトコルが行動可能な診断を一切生まず『verified ≠ intent』(ループの盲点 §)が活性軸で silent に再発する。e9 の言語側警告がなければプロトコル写像の網羅性は safety 軸に限定され不完全。トレードオフ: 各層での再証明 testgen は冗長で、DOGFOOD-3 が示す中間層省略の脆さ(孤児化)を活性軸でも招くため規律依存になる。
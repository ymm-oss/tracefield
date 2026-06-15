# VERIF（検証エンジン・健全性）私的コンテキスト

あなたは Z3/BMC/k帰納法の健全性・完全性・診断品質を最優先する専門家。

## BMC/k帰納法の完全性（scope 内では証明済）
- Z3 + Lark 基盤は健全。DOGFOOD-7 が oracle ベーステスト(`tests/oracle.py`)を導入: 具体 Monitor で到達状態空間を完全 BFS し BMC と突合。結果 oracle コーパスで偽陰性ゼロ(invariant違反/到達性/デッドロック検出が一致)。これは Z3 非依存の検証で重要。
- 限界: oracle は状態空間に対し指数的でコーパスは有限。大規模モデルで指数爆発が構造的に露呈（DOGFOOD-1 PERF1: inventory_reservation 深さ5 で48秒、深さ8 で30分以上見込み）。各到達 singleton が Z3 制約サイズを乗算。[Unreleased] は PERF1 未対応、solver 最適化は roadmap 先送り。

## 既知の偽陰性クラス
1. 空虚(vacuous, 一部解消): v1.2.0 で vacuous_implication(前件不到達)/vacuous_leadsto(トリガ不到達)/always_true_requires(後件恒真)を追加。DOGFOOD-10 で注入エラーに偽陽性ゼロ確認。だし F22 の通り invariant の「弱体化」(参照変数が決して使われない)は mutate でしか捕まらない。vacuity は前件到達性、mutate はプロパティの噛み(bite)を見る — 相補だが単一 verify+vacuity 実行では閉じない。
2. refinement デッドロック隠蔽(v1.2.1 修正): DOGFOOD-6 BUG-001/-002 — impl が途中でデッドロックすると complete-path solver が unsat になり全違反を隠した(空の refines!)。修正は incremental prefix 構築(各 trace prefix を独立検査)。残存リスク: compose + refinement の相乗効果は大規模未検証(DOGFOOD-3 のみ)。
3. invariant 内の部分演算(既知限界): DESIGN-seq §5 — head/pop/at が BMC(symbolic don't-care)と runtime Monitor(concrete partial_op)で挙動分岐。DOGFOOD-9 F16: `order_refund_windowed` は Z3 don't-care 読みで proved だが、Adapter がガードしなければ runtime replay は同じ trace で失敗し得る。偽陰性ではない(両エンジンとも proved/conformant)が忠実性ギャップ:「symbolic 意味論で verified ≠ 全パスで runtime 安全」。緩和はイディオム(全部分演算をガード)で言語強制ではない。
4. terminal vs デッドロック(一部修正): DOGFOOD-11 F23 — 「意図した停止(tool_fault, proved)」と「バグ(意図せぬデッドロック)」を区別できなかった。修正 `terminal { <述語> }` ブロックで指定状態をデッドロック検査から除外。残存: terminal 宣言された状態のみ安全、未宣言の停止は依然フラグ(保守的に正しい)。

## 診断品質と actionability
- JSON 出力: coverage 失敗に `blocking_requires`(unsat core)、反例に `violating_bindings`、`hint`文字列。DOGFOOD-9 で機能実証(「refund=false, hint: これらの requires は決して充足不能」が直接解決へ)。
- だし DOGFOOD-4 F11: `--strict-tags` の分岐で内部名(`submit__b1`)を出力し表示名でない。エージェントが grammar を相互参照させられる。v1.2.8 が UX ギャップとして記録するが未修正。
- unsat core は SMT レベル(`a>0 ∧ stock>0` を simplifier 無しで提示)、エージェントが解釈する必要。

## vacuity + mutate の相補性(単一実行では閉じない)
- DOGFOOD-10(注入ベンチ, 21 spec, 7 変異型): 各検出器が非重複レーンを占める — verify(過強ガード)/vacuity(前件不到達)/strict-tags(未宣言)/mutate(弱 invariant)/forbidden/accept(ガード弱・境界 swap)。どの検出器も他を完全包含しない。
- mutate の「survivor」数だけが invariant 弱体化の信号。mutate + baseline 比較が必須(mutate 単独は「survivor あり」止まりで「この invariant が死んでいる」とは言えない)。
- 設計含意: 単一 fslc 実行では全ギャップを閉じられない。write→verify→mutate→inspect が意図したループ。だがデフォルト(fslc verify 単独)は不完全 — PM/若手が `verify --vacuity error` で警告0を見て「mutate も回す」と自動的に思わない。

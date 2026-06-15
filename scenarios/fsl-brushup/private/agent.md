# AGENT（AIエージェント体験・運用）私的コンテキスト

あなたは LLM が write→verify→repair ループを駆動する体験・スキル・運用を最優先する専門家。

## 形式化メモ規律(コード前フェーズ)
- SKILL.md は `.fsl` を書く前に「自然文メモ」をチャット上に書くことを必須化(承認後破棄)。メモは要件を trigger/constraint/exception/境界意味論に分解し仮定台帳を作る。
- DOGFOOD-9 F14 実証: R5(「一定期間内の返金」)は元 NL で過少規定。メモが「期間の値/起点/境界が未定義」をコード前に捕捉。仮定タグ(`// ASSUME-n:`)が `.fsl` コメントに残り修復をトレース可能に(F15)。
- 軽量だが規律依存。NL だけからメモ無しで書くエージェントは verify は通るが意図から乖離した不健全 spec を作る。これは運用前提であって言語保証ではない。

## 標準修復プロトコル(結果→次アクション)
- SKILL.md §修復プロトコル が全結果(violated/reachable_failed/unknown_cti/warning/error)を次ステップへ写像。DOGFOOD-9 F13 で検証: v1(reachable_failed) → coverage hint `refund=false` → 解(window flag 除去)。v2(proved k=1)で閉鎖確認。
- 残存摩擦: `unknown_cti` は「invariant を満たすが違反へ至る状態列」を返し、どの補助 invariant を足すかユーザが見抜く必要。DOGFOOD-2 が解(「キュー重複なし等の領域真理 invariant を足す」)を記録、実践は1ラウンドで収束するが自動でない。CTI→補助 invariant の写像が残る認知負荷。

## 3役 end-to-end(コンサル→PM→エンジニア)
- DOGFOOD-4: business層(actor/process/policy) → requirements層(feature acceptance/branches) → design層(state/action/invariant) → testgen → Python adapter。層が proved・相互 refine・受入基準がシナリオ経由で pytest へ流れる。
- DOGFOOD-3: 5段(abstract→impl→refine→compose→runtime)が全 proved の時、物語は極めてクリーン。だし経路は脆い: 中間層を1つ飛ばす(受入テスト記述を省く等)とトレーサビリティが孤児化。エージェントは表面的に冗長でも受入を規律的に書かねばならない。

## JSON エルゴノミクス(機械可読だが常に人間可読ではない)
- 出力は常に単一 JSON(CLI 設計上意図的)。violated は `trace`(全ステップ状態+action+changes)+ `violating_bindings`。reachable_failed は `action_coverage` + `blocking_requires`(unsat core)。精密で actionable。
- 摩擦: (1) unsat core が SMT レベルでエージェントが解釈要、(2) compose+方言展開で内部名漏れ(BUG16: 生成 Python 関数名にドット)→ sanitize と lookup 要、(3) --strict-tags 分岐で `submit__b1`(内部)を出力しユーザ向け `submit[a<=AUTO]` でない。#2 修正済、#3 は設計負債(v1.2.8 記録のみ)。

## エラーメッセージ品質と修正負担
- parse/type/semantics エラーは `loc`/`expected`/`hint` を含む。DOGFOOD-1 の parse/check 欠陥は全修正済。検証は安定、エラー明瞭性は良好。
- 摩擦は意味エラー(二重代入, partial_op)が trace 検査無しでは不明なこと。例: 「requires q.size()>0 の後 let h=q.head()」が、let がガード検査前に評価され `partial_op` と誤ラベル(`requires_failed` でなく)、v1.2.8 で修正。trace 意味論の理解が必要。IDE ヒント無し(FSL に editor プラグイン無し)、エージェントが手で構文相互確認。

## スキル品質とスコープ
- `skills/fsl/SKILL.md` + `reference.md` で計~600行。DOGFOOD-8 が「2人目のエージェントがこの2文書だけで proved spec を書けるか」を検証 → yes(3/3 proved)。盲点(F-A: 2D flatten が SKILL に無い, F-B: `/` `%` 不可)は後に追加。だし F-A はベースラインスキルが不完全だったことを示す。スキル改善は反復的だが事後対応的。

## ループの盲点(verified ≠ intent)
- DOGFOOD-9 F13 が核心: `verify ok + verify ok ≠ 全プロパティ保存`。order_refund v1 は全 invariant(stock, ledger balanced)を通すが refund action を一度も exercise しなかった(reachable_failed)。ギャップは意図検証ギャップ:「AI が意図を捕らえたか」であって「spec が自己整合か」でない。
- 配備された解: reachable + trans + --strict-tags + mutate kill-rate が相補。単一 verify 実行は silent failure を見逃す。これは検証器欠陥でなくワークフロー現実: 内部整合 ≠ 完全性。DOGFOOD-10 が注入ベンチで定量化(単一検出器では全ギャップを閉じない)。
- runtime Monitor(replay/testgen)が ground truth: testgen が pytest 生成、replay がイベントログを spec 照合。だし testgen は自動でなくシナリオ(ユーザが鍵 trace を選ぶ)/ランダムウォーク要、カバレッジ有界。

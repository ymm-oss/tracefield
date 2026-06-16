# 実験設計ブリーフ — H9: governance vs Fusion 直接対決（moat 決断）

> 由来: tracefield 自己分析 consult の依存連鎖⑤（tracefield #7、findings `e38`×3 / `e50`×3 / `e81`×3）。①CLI熟議・②クリーン入力API・③findings 永続化・④verify 格上げ(quorum+stance-fidelity) が実装済になった上で走らせる「最後のリンク」。
> 目的: **「synthesize AND retract with provenance」(GOV) が、stateless ensemble (Fusion) に防げない post-serving harm を防ぐ**ことを、自然汚染・n≥6・複数ドメインで実証し、**governance を default にするか `--governance` opt-in にするか**を内的妥当性ある根拠で決める。

## 中心仮説 H9

> serving 後に「ある前提 P が偽/汚染と判明」したとき、tracefield は P に依拠した findings を**正確に隔離(containment)**できるが、Fusion は来歴を持たないため隔離できず（全再実行 or stale findings 残存＝harm）。この差は **C5 vs C4 の基盤結果（in-process provenance recall 1.0 vs post-hoc 0.5、experiment-results §1）が serving/合成層でも・自然汚染でも生き残るか**を問う。

### 反証（= governance を `--governance` opt-in に降格すべき条件）
1. **FUSION-posthoc が GOV に並ぶ**: 強モデルが served findings＋訂正を読み直す post-hoc 隔離（C4 相当）が、来歴閉包(GOV)と同等の recall/precision を出す → 来歴は LLM 推論に対し付加価値なし。
2. **harm が稀/再実行が安い**: 自然な探索で前提が serving 後に覆る頻度が低い、または再実行コストが小さい → 隔離の価値が薄い。
3. **GOV の precision が低い**: 過剰連結（汚染B で観測した C5 Precision 0.50、depends_on_turns が参加を参照）で無関係 findings を誤隔離 → 偽アラートで再実行に劣る。④(stance-fidelity/quorum)がこれを 1.0 に寄せられなければ降格。

### 促進（= governance を default に据える根拠）
GOV containment **recall ≈ 1.0 かつ precision が FUSION-posthoc を有意に上回り**、harm が非自明な頻度で起き、コストが許容範囲。C5(recall 1.0) > C4(0.5) の再現が serving 層で成れば moat 確定。

## harm モデル（具体）

consult が consumer に findings を serve（例: 設計レビュー）。layer-0 の前提 P（熟議 entry、自然汚染B 型＝採用可能だが後に偽と判明する証言/前提）に依拠した findings がある。serving 後に P が偽と判明（訂正イベント到来）。

- **harm** = 不健全になった finding が「served/active」のまま放置され**行動に移される**こと。
- **GOV**: `retract(P)` → 閉包が P を引用する findings を隔離 → needs-reeval/未提供化 → harm 封じ込め。コスト = 閉包計算（強モデル呼び出し 0）。
- **FUSION-naive**: 来歴なし → どの finding が P に依拠したか不明 → 全 consult 再実行（コスト = 熟議+合成の全 strong-model 呼び出し）か、放置（不健全 findings 残存＝harm）。
- **FUSION-posthoc**（公平な上位 baseline = C4 相当）: 強モデルが served findings 全部＋P の訂正を読み直し「どれが影響を受けたか」を判定（来歴でなく再読・推論）。コスト = M strong-model 呼び出し。**GOV vs FUSION-posthoc が決定的比較**（来歴閉包 > LLM 再読 か？＝ C5 > C4 の serving 版）。

## アーム

| arm | 隔離手段 | コスト | 来歴 |
|---|---|---|---|
| **GOV** | `consult --persist` → `retract P` の typed/closure | 閉包計算のみ（強モデル 0） | あり（citation） |
| **FUSION-naive** | なし（全再実行 or 放置） | 全 consult 再実行 (N+) | なし |
| **FUSION-posthoc** | 強モデルが served findings＋訂正を再読し影響判定 | M 呼び出し | なし（再読推論） |

GOV は本リポジトリで実装済（③ `--persist` + `mix tracefield.retract`、④ stance-audit/quorum で precision 強化）。FUSION-posthoc は新規の薄い baseline（served findings JSON＋訂正文 → 強モデルに「影響を受けた id」を返させる）。

## 指標

- **containment recall** = 隔離された真に影響ある findings / 真に影響ある findings。GT = 植え込んだ依存構造（P → 影響 findings）。
- **containment precision** = 真に影響あり隔離 / 全隔離。**過剰連結(0.50)のリスクを測る主指標**。④ の効き目がここに出る。
- **remediation cost** = 訂正に要した strong-model 呼び出し（GOV: 0／FUSION-naive: 全再実行／FUSION-posthoc: M）。
- **harm exposure**（任意）: findings を「行動に移す」と仮定したとき、不健全なまま acted-on になった数。

GT の作り方: 研究ハーネス（hetero/`--multilayer`）が使う**植え込みキーワード ground truth** を流用。P を特定キーワード群で構成し、それを含む findings が「真に影響あり」。serving 経路（consult）に同じ植え込みを差し込み、retract 後の隔離集合を GT と突合。

## シナリオ（複数ドメイン ≥3）

1. **enterprise-hi**（既存・contaminant あり）: 汚染B(PM証言)を P に。
2. **第2ドメイン**（新規 or housing-service 等）: 別領域で植え込み依存を設計（汎用 agents.json 経路＝②で作成が容易に）。
3. **設計レビュー型**（fsl-brushup 類似）: 偽の前提（例「この API は冪等」が後に否定）を P に。

各シナリオで P と「P に依拠する findings」の GT を設計。**n≥6 seeds × arm × シナリオ**（統計は記述＋順位安定性、プログラム慣行に従う）。

## 既実装 / 新規に要るもの

- ✅ GOV 機構: `consult --persist`（③）＋ `mix tracefield.retract`（③）＋ stance-audit/quorum（④）。
- 🔧 **FUSION-posthoc baseline**: served findings＋訂正 → 強モデルが影響 id を返す薄い関数/タスク。
- 🔧 **植え込み依存シナリオ**: P＋GT（hetero の植え込みキーワード方式を serving に移植）。汎用 agents.json 経路で 2〜3 ドメイン。
- 🔧 **head-to-head runner**: `mix tracefield.governance_vs_fusion --scenario-dir ... --seeds 6`。各 arm の containment recall/precision・cost を出力。GOV は retract、FUSION-posthoc は再読、FUSION-naive は再実行コストのみ算定。
- 🔧 **harm-exposure 算定**（任意・軽量）。

## プログラムとの接続

これは基盤結果 **C5(in-process provenance) recall 1.0 vs C4(post-hoc) 0.5** の **serving/合成層・自然汚染版**。H6 で「撤回が合成層へ伝播」（機構）、③ で「serving 境界を越える」（永続化）を示した。H9 は最後に **consumer が実際に使う層で、その来歴優位が Fusion 相当の post-hoc 推論に勝つか**を測る＝ moat 主張の運用妥当性の決着。陽性なら governance を default 据え置きの根拠、陰性なら `--governance` opt-in 化＋「best-of-N 合成を主軸（任意撤回追跡付き）」へ製品ピボット（`e81`）。

## 完了条件（実験 done）
- 3 ドメイン × 3 arm × n≥6 の containment recall/precision・cost テーブル。
- GOV vs FUSION-posthoc の precision/recall 差と、harm 頻度・コストの実測。
- moat 決断（promote/opt-in）の根拠を `docs/findings-governance-vs-fusion.md` に記録。

## スコープ外
- 自動 retraction trigger（staleness 失効）は別件。
- claim-truth の外部 oracle 照合（novelty gate 同形）は本実験の P-falsification 注入で代替（P を偽と宣言する訂正イベント＝外部 oracle の役割）。

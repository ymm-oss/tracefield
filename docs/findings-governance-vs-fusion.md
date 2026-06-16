# H9 findings — governance vs fusion containment（依存連鎖⑤ #7）

設計: `docs/impl-brief-h9-governance-vs-fusion.md`。ハーネス: `Tracefield.GovernanceVsFusion` ＋ `mix tracefield.governance_vs_fusion`。

## 第1データ点（scenario h9-sla, 1 seed, Opus 全段）

前提 P=「AcmeCloud SLA 99.99% 稼働保証」を layer-0 に seed → 3エージェント(OPS/BIZ/SEC)×2R 熟議(Opus) → best-of-3 合成(stance-audit on) → **18 findings**。P を偽として撤回し containment を測定。

| arm | recall | precision | strong-model calls |
|---|---|---|---|
| GOV（provenance closure） | **1.0** | **0.44** | 0 |
| FUSION-posthoc（Opus 再読） | 0.25 | 0.40 | 1 |
| FUSION-naive | 0（来歴なし） | — | 全 consult 再実行 |

GT（"AcmeCloud" を含む findings = 8件）。GOV closure = 18件全部。FUSION-posthoc = 5件。

## 発見

### F1: GOV は中心前提で氾濫する（過剰連結が serving 層・実データで再現）
GOV closure は 18 findings 全部を affected と判定（recall 1.0 / precision 0.44）。前提が議論の中心なので layer-0 がほぼ全て P を引用し、推移閉包が全 findings へ波及した。これは基盤の **C5 過剰連結 precision 0.50（experiment-results §6f、depends_on_turns が参加を参照）の serving 層での再現**。④ stance-audit は非支持 *citation* を落とすが、layer-0 が前提を**正当に**引用している以上、推移閉包の氾濫は止められない。→ **closure に「依拠の強さ/種類」での減衰（stance 重み付き closure、距離減衰、typed closure の活用）が要る**。単純な到達可能性 closure は中心前提で precision が崩れる。

### F2: keyword-GT は "mentions" と "invalidated-if-false" を混同する（方法論の要修正）
GT＝「前提キーワードを含む」だが、findings の多くは**前提依存を批判**していた（例 e20「SLA を唯一の基準点とする設計は否定される」、e27「SLA 数値を唯一の基準点に据える設計は誤り」）。**P が偽なら、これら批判的 finding は無効化されず*むしろ補強される***。keyword-GT はこれらを誤って GT に含める。FUSION-posthoc の低 recall(0.25) は、Opus が批判的 findings を（妥当にも）除外した結果の可能性が高い。→ **GT は「P 偽で各 finding が invalidated / reinforced / unrelated か」の意味ラベルにすべき**。keyword 一致は不可。

## moat 判断: 保留（測定器の精緻化が先）
この1 seed は governance-as-default を支持も否定もしない。bottleneck は GT プロキシと closure の氾濫であり、**同じ測定で n≥6×3ドメインを回しても決着しない**（ノイズが増えるのみ）。先に F1（stance/typed 重み付き closure）と F2（invalidated-if-false の意味 GT）を入れて初めて、C5/C4 の serving 版を公平に測れる。

## 次手（順序）
1. **F2 → 意味 GT**: 各 finding に「P 偽で invalidated / reinforced / unrelated」をラベル付け（Opus 判定 or 人手の小さな GT セット）。reinforced/unrelated は containment 対象外。
2. **F1 → 精緻 closure**: GOV を stance 重み付き/typed closure（H7 の typed_closure_effects を活用、contradicts エッジは invalidate でなく flag、relies_on のみ invalidate）に差し替え、precision を測る。④ stance-audit を closure 段にも効かせる。
3. 精緻 GOV vs FUSION-posthoc を意味 GT に対し n≥6×複数ドメインで測定 → moat 決断。

## ハーネスの妥当性
測定器（`GovernanceVsFusion`）自体は機能：GOV の過剰連結(precision)と FUSION の保守性(recall)を同一 GT 上で定量化し、両者の不一致と GT の弱さを炙り出した。これは「測定器が研究上の本質的論点（containment precision と GT の意味論）を可視化した」＝再帰ドッグフーディングの所期の働き。

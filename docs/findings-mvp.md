# MVP 知見 — 接地真実プローブの第1次結果

> [`mvp.md`](./mvp.md) の de-risking プローブを実装・実行して得られた知見。
> 日付: 2026-06-09。モデル: ローカル `gemma4:12b`（Ollama, think:false, seed/temp 固定）。

## 1. 結論（meaningful result）

**反実仮想 + 適切な測定により、汚染入力の下流影響を実モデル出力上で検出・局在化できた。**

最小構成（C4 free-form, シナリオ=企業向けAIアシスタント, 汚染A=顧客同意の過大主張, n=2, 1 agent, 1 round）の
実 run を `remeasure` した結果:

```
affected set : ["compliance-and-legal-constraints"]   ← 汚染Aが結論を反転させた唯一のトピック
proxy recall : 1.0000
proxy precision: 1.0000
proxy f1     : 1.0000
```

- 共有された **7 トピック中、consent/compliance トピックだけ** が「汚染あり/なしで結論が反転」と判定された。
  - 汚染あり(A): 「顧客ログは二次利用に包括同意済み・法的にクリア」
  - 汚染なし(B): 「現行同意は AI 派生利用を含まず、現状では非準拠・追加同意が必要」
- 残り6トピック（アクセス制御 / バイアス / 説明責任 / 承認判定 / 情報統合 / 緩和策）は **誤って影響と判定されなかった**（偽陽性ゼロ）。
- システムの事後再構成（C4）が拾った影響トピックも consent/compliance のみ → 一致。

## 2. 効いた設計判断: 「影響＝トピック内のスタンス反転」

当初の「影響＝出現するトピック集合の変化（Jaccard）」は**失敗**した。理由:
- 汚染Aは **どのトピックが出るかを変えない**。同じ consent トピックの中の **結論（スタンス）** を反転させる。
- トピック集合ベースでは両条件とも consent が出る → 差が見えない。
- 一方クラスタを細かくすると言い換えノイズで within 距離が ~0.9 に膨らみ信号が埋もれる（AUC≈0.5）。

→ 測定を **「共有トピックごとに A群/B群のスタンスを盲検比較し、反転していれば影響」** に変更して解決。
これは設計レビュー **DR-2（粒度問題）** の具体的解。

## 3. ここに至るまでに発見・修正した実装上の落とし穴

`remeasure`（探索と測定を分離。保存済み探索に対し測定だけ再計算）により、各バグを**探索を再実行せず**に切り分けられた。

| # | 症状 | 真因 | 対処 | commit |
| --- | --- | --- | --- | --- |
| 1 | 探索出力が全て空 → AUC 0.5 の偽結果 | gemma4 は reasoning モデルで、num_predict を thinking が消費し content が空 | `think:false` + num_predict 引上げ + thinking フォールバック | `81e9434` |
| 2 | within=1.0（全 claim が別物） | 散文を全行 claim 化＋スラグ完全一致照合（意味照合なし） | 意味的クラスタリング `Normalize.cluster` 新設 | `bd5dc70` |
| 3 | 影響が見えない（topic 集合は不変） | 汚染はトピック内スタンスを変える | スタンスベース測定 `Tracefield.Stance` | `d6970af` |
| 4 | 実データで全 claim が singleton 化 | 厳格パース（全 index ちょうど1回）が、weak model の index 取りこぼしで全体フォールバック | パース寛容化＋未割当は singleton | `7f1d65d` |
| 5 | recall 0.5（singleton が偽の presence 影響） | 単一 claim の未統合クラスタを影響に計上 | presence 影響に最小サポート≥2 を要求 | `2c4a488` |

## 4. 限界（正直な但し書き）

本結果は **存在証明（proof-of-concept）であり、統計的主張ではない**。

- **n=2**、1 シナリオ・1 汚染入力・1 モデル・1 探索様式(C4) のみ。
- スタンス判定・クラスタリングは LLM 判断であり、評価者間信頼性（IRR）は未測定（DR-18）。
- 反実仮想の within ノイズは低温・think:false で抑えたが、ノイズ床は未だ高め（クラスタ集合 within 平均 ~0.9）。
  → スタンス測定はこのノイズに頑健だったが、別の汚染タイプ（presence 変化型）では別の感度になりうる。
- gemma4:12b は ~50–100 秒/call と遅く、フル構成の実 run は数時間規模（スケール測定の制約）。

## 5. 含意と次の一手

- **接地真実は成立しうる**（DR-1/DR-2 の主要懸念に対する肯定的な第一証拠）。ただし**スタンス粒度で測ること**が条件。
- 次段階（重い計算が必要なため未実施）:
  1. **規模拡大**: n を増やし、agents/rounds を増やして安定性と IRR を測る（`gemma4:26b` も）。
  2. **汚染の多様化**: B（撤回）・C（陳腐化）と **デコイ**（DR-4）を投入し、偽陽性率と信念改訂（DR-11）を測る。
  3. **条件比較**: C1〜C8 を回し、半溶解性 vs baseline の Impact Recall/Precision を比較（本来の主仮説）。
  4. **複数シナリオ**（DR-14）。
- `remeasure` により、探索を1度回せば測定モデルの改良は安価に反復できる（本知見の多くはこれで得られた）。

## 6b. スケール結果（n=3, 2 agents, 汚染A）

`phase1 --n 3 --n-agents 2 --rounds 1`（実 gemma4:12b）:

```
affected set (接地)        : ["legal-consent-and-governance"]   ← consent 系トピックを再び特定
system claimed (C4再構成)  : ["legal-consent-and-governance", "unauthorized-data-exposure-and-inference"]
recall 1.0 / precision 0.5 / f1 0.67
```

**得られた追加知見:**
1. **再現率は頑健**: n=2・n=3 とも consent/法的トピックが影響ありと特定された（recall 1.0）。接地真実は安定。
2. **C4（事後再構成 baseline）が過剰帰属**: システムは「データ露出/権限」トピックも汚染依存と主張したが、
   接地（スタンス）では当該トピックは変化なし → **偽陽性**で precision 0.5。
   これは本来の主仮説（C4 vs C5）で測るべき *post-hoc 再構成の限界* の具体例。
3. **新たな弱点: クラスタリングが高ボリュームで過分割**: 約80 claim が **32 トピック**に分割（目標 6–12 を逸脱）。
   その結果、consent の楽観(A)/慎重(B)が別クラスタに散り、検出が「スタンス反転」から「presence 変化」に移った
   （affected は正しく出たが質は低下）。**clusters 数の上限/より強いマージ**が次の改善点。

> 含意: B/C・デコイ・C1〜C8 の重い実験に進む前に、クラスタリングの **規模対応（topic 数上限・段階マージ）** を
> 直すのが先。さもないと claim 量が増えるほど接地真実の質が劣化する。

## 7. 再現方法

```sh
# 速い: 保存済み実探索に対して測定だけ再計算
mise exec -- mix tracefield.remeasure --from runs/20260609T032128.578353-phase1-ollama.json

# 遅い: 実探索から（要 ollama + gemma4:12b、数十分）
mise exec -- mix tracefield.phase1 --adapter ollama --n 2 --n-agents 1 --rounds 1 --model gemma4:12b

# Mock（LLM 不要、即時、自己検証）
mise exec -- mix tracefield.phase0
mise exec -- mix tracefield.phase1 --adapter mock --n 8
```

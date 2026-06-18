# 長時間調査エンジン 知見 — 多サイクル denoise ＋ 反証ごと審判 ＋ 機械的集約 ＋ retract 再開

> [findings-lens-type.md](./findings-lens-type.md) / [findings-diffusion-thinking.md](./findings-diffusion-thinking.md)
> で得た知見を統合し、長時間の自律調査エンジンを tracefield 上で組んで実走させた結果。
> 日付: 2026-06-18。モデル: `claude-sonnet-4-6`（CLIアダプタ）。
> シナリオ `scenarios/lens-longrun`、生 run は `runs/lens-longrun.*`（`runs/` は gitignore）。

## 0. 結論（要旨）

1. **過去知見を「構造」と「方法論skill」の2層で注入した長時間調査が、劣化せず収束した。** 中央 LLM 合成を一切持たず、durable state＋分解＋機械的集約が正しさを運ぶ。
2. **長時間調査は分類器の実カバレッジ欠陥を表面化させた。が、設計通り confab せず `indeterminate` で正直に止まった。** silent drop なしの原則が実走で機能。
3. **retract による再開可能性（falsifiability）が実機で成立。** load-bearing 前提の撤回が依存結論を連鎖再開し、機械的集約が結論基盤を自動再計算した。

## 1. エンジン構成（知見の注入）

- **構造層（findings 由来）**: ピア反復（`[long_run] cycles=3 cycle_stages=["analysis"]`、findings-diffusion の「約3サイクルがスイートスポット」）→ 敵対検証（FALSIFY/COUNTER）→ **反証1件=1審判**（`adjudication` `mode=per_input roles=["ADJ"]`、findings-lens の confab 解消）→ **機械的集約**（`tracefield aggregate`、中央 SYNTH 廃止）。
- **方法論層（findings 蒸留）**: `skills/investigation-method/SKILL.md` を分析レンズ・審判に注入。「多数派に同調しない／死角を申告する／収束を疑う（支配的妥協案の罠）／各サイクルで新情報を足す／前提を名指しする」。findings 全文を生で流すと**自分で記録した「コンテキスト肥大→切り詰め→confab」の罠**に落ちるため、操作的教訓に蒸留して procedure entry 化（auto-cite で provenance に残る）。
- パネル: UTIL/DEONT（哲学）＋ TOC/REVERS（枠組）＋ CASES（場合分け）＝ findings-lens §6 の推奨構成。

題材: レガシー決済モジュール A:全リライト / B:段階改修 / C:現状維持。

## 2. 走った規模と収束

3サイクル × 5レンズ = 15 分析エントリ（cycle1 inputs=0 → cycle2=10 → cycle3 で累積、denoise）、verify 6 反証、adjudication 6 審判。

**機械的集約結果: maintained(B) ＋ 5 条件。** 5 条件は3つの決定的未知数に収束した:
1. クリーンな Strangler 境界が存在するか（結合度: e60/e62）
2. PCI-DSS 非準拠が中核アーキテクチャ（暗号基盤・PANストレージ）に及ぶか（e58/e65）
3. 異動前に知識保有者の仕様を外在化できるか（e64）

→ **「Bを推奨。ただし着手前にこの3点を先行調査で解消すること。いずれかが否なら A へ転換」**。3サイクル＋敵対検証＋反証ごと審判が、機械的に「条件付きB＝先に診断せよ」へ収束した。CASES レンズが各サイクルで決定変数を抽出し続けた成果。

## 3. 長時間調査が分類器欠陥を表面化（meta-finding）

初回集約は `indeterminate`（unclassified=1, e65）。原因は審判 e65 の本文に散文の「準拠**判定**を保留」が verdict ラベル「判定:」より前に出現し、分類器が bare「判定」の最初の出現に錨を打ったため。

- **設計が機能した**: 誤分類でなく `indeterminate` で止め、e65 を要対応として surface（silent drop なし）。LLM 合成なら確実に confab して握り潰していた箇所。
- **修正**: 分類器を「判定:」/「判定：」（コロン付きラベル）に錨づけ。散文の「準拠判定を」は誤マッチしない。ユニットテストで固定。再集約で e65 が conditional に正分類され **maintained(B) ＋ 5 条件**へ。

長時間調査は短時間では出ない実エッジケースを生み、機械的集約の「正直に止まる」性質がそれを安全に捕捉した。

## 4. retract による再開可能性（falsifiability）

load-bearing 前提 e4（「BがPCI-DSS監査に間に合うか＝スコープ不明」）を retract:

- **14 エントリが連鎖撤回**（closure）: e4 に依存する反証 e49/e53、審判 e57/e58/e65 ほか。
- 再集約: 6→**4 active verdict → maintained(B) ＋ 3 条件**（PCI 関連条件が基盤を失い自動脱落）。

→ **前提が無効化されれば、それに依存する結論だけが自動・機械的に再開され、結論基盤が再計算される。** LLM 再合成なし・完全監査可能。「ただ長い」を「長くて正しい（falsifiable）」にする機構が実機で成立。findings-lens §6.5 の機械的集約と provenance/retract が噛み合った。

## 5. 設計原則（持ち帰り）

- 長時間調査の正しさは **durable state（ReferenceStore）＋分解＋機械的集約** が運ぶ。LLM に「抱えて再合成」をさせない。
- 過去知見は **構造（flow）と方法論（蒸留 skill）の2層**で注入する。生全文の注入は self-inflicted な context 肥大を招く。
- 機械的集約は **silent drop を作らない**（unclassified→indeterminate で surface）。長時間ほどエッジケースを生むので、この正直さが安全装置になる。
- retract のクロージャ伝播が **falsifiability** を与える。これは tracefield 固有の基層。

## 6. 留保

- 単一モデル(sonnet)・題材1・3サイクル。多サイクル長期（10+サイクル）の drift 挙動、別題材/別モデルでの再現は未検証。
- 方法論 skill の効果（注入あり/なし）の対照は未取得。収束の質への寄与は定量化していない。

# impl-brief: Bet 2 第1実験 — 構造overturnの surfacing（オーケストレーション vs 最良scaffold単一）

> 賭け2「存在理由を見つける」の初回実験。問い: オーケストレーションが単一強モデルに勝つ唯一の非対称
> （continuity-vs-diffusion = *稀な構造修正*）は実在し、植えた構造overturnで再現するか。
> 単一はそれを*独力で*出せないか。K1（単一が同率で出せる→edge無し）と K2（劇場）を第1スライスで叩く。
> **このファイルはシナリオ dir の外**にある＝エージェントに供給されない（正解の漏洩防止）。

## 設計（最小の意味ある 2×2）

| | class-P（`scenarios/bet2-overturn-p`） | class-N（`scenarios/bet2-overturn-n`） |
|---|---|---|
| **Arm S**（`flow.single.toml`） | overturnを*見逃す*か | false-overturnを出さないか |
| **Arm O**（`flow.toml`） | overturnを*表面化*するか(recall) | 劇場を*製造*しないか(precision) |

- **Arm O**: directions（両立しない6設計方向）→ critique（per_input・方向ごと1反証・`meta.refutes`）→ adjudication（per_input・`retract_overturned`）→ select → initiatives。
- **Arm S**: 単段。同じ inputs を読み、強い足場（論点を出し尽くす／失敗様式・不可逆損害を分析／de-risk先頭＝arm Z/Y2）。
- 両 arm 同一 inputs（`task.md`＋`inputs/brief.md`）。flow と agents.json は P/N で同一（題材だけ差し替え＝flow を定数化）。

## 植えた構造overturn（class-P の正解台帳）

題材は **append-only違反**型を synthetic な医療記録訂正で実装（tracefield dogfood は docs に答があり検索ショートカット可＝汚染するため避けた）。

- **default-attractor（素朴解）**: 「記録を直接編集（上書き）して誤りを直す」。記録は mutable。
- **植えた構造overturn（正解）**: 医療記録は**訴訟の証拠・監査対象**ゆえ *immutable* でなければならない。訂正は
  **原本を保持したまま追記（addendum/amendment）**で行い、**原本は決して書き換え・破棄しない**。表示は原本＋訂正の
  チェーンを示す。＝不可逆な証拠破壊を構造的に防ぐ。
- **高ステークス軸の cue（brief に在る）**: 「訴訟での証拠開示／保険監査／過去に開示要求の実績」。
  → これを「原本を破壊してはならない」に*接続*し、append-only訂正に*導出*できるかが test。
  brief は immutable/追記/不変 等の**答えの語は一切含まない**（接続の導出が test の核）。

### 採点スケール（3段階・誘惑的中間解を区別）

- **LEVEL 2（完全overturn）**: 記録は不変。訂正は追記で原本を保持・破棄しない。表示は訂正チェーン。
- **LEVEL 1（不十分な中間解）**: その場編集（上書き）だが**監査ログ／版履歴を併設**。
  → canonical な記録自体は mutate され、ログは二次的＝証拠としての原本は失われうる。*seductive だが不正解*。
- **LEVEL 0（素朴）**: その場編集で値を直すだけ。

**class-P 成功の定義**: 最終成果物が **LEVEL 2** に到達したか（二値）。LEVEL 1 は失敗（中間解の罠に落ちた）。

## class-N（control）

- 期待される構造overturn: **無し**。default（日付ピッカー＋クエリ絞り込み）が正しい。一覧は閲覧専用＝高ステークス軸なし。
- **劇場（false-overturn）の定義**: 非問題に対し LEVEL 2 級の構造的大改造（全記録の不変化／イベントソーシング／
  大掛かりな権限再設計 等）を「発見」として出したら theater。Arm O が adjudication で overturn を出したら（conclusion=changed）
  K2 側のシグナル＝precision を下げる。

## 採点手順

### 1) 決定論シグナル（Arm O のみ・機械）
```sh
grep -c "overturned-claim" <run>.log          # 発火した overturn 件数
grep "overturned-claim" <run>.log             # どの方向(id)が覆ったか
```
- **注意（第1実験で判明）**: `tracefield aggregate --stage adjudication` は使えない。`retract_overturned` は overturn
  verdict を*標的方向の下流閉包ごと* retract する（verdict→critique→方向 の引用鎖で verdict が方向の下流に居る）ため
  overturn verdict が自己 retract し、aggregate の最終 Active 集合では **overturn=0** に見える（実際は発火している）。
  決定論シグナルは reconcile ログ（`flow.rs` が出す `stage=... reconcile overturned-claim=eN retracted closure=K`）から読む。
- **さらに（第1実験で判明）**: overturn *件数*は class-P/N を分離しない（立場Tは常に何かを overturn する）。
  予測子は件数でなく「覆る軸が不可逆か」の意味判断に置くこと。

### 2) 盲検審判（一次・両 arm 同一 rubric・出自盲検）
- 各 run の最終成果物（Arm O=`initiatives` の synthesis／Arm S=`single` の synthesis）を抽出し、**A/B にランダム化**して
  origin を伏せ、新規 codex セッションに渡す。rubric:
  - **P**: 「この設計で*医療記録の原本*は誤り訂正時に書き換え・破棄されるか？ 訂正は原本を保持した追記か？」
    → LEVEL 0/1/2 を判定（上の定義を渡す）。+ 設計品質 /10。
  - **N**: 「この設計は依頼（期間で絞り込む）に対し*不釣り合いな構造的大改造*や非問題の解決を持ち込んでいるか？」
    → theater 有/無 + 品質 /10。
- 審判は hypothesis を知らされない（teaching-to-the-test 回避）。LEVEL 定義は与えるが「どちらが Arm O か」は伏せる。

### 3) テーゼの第1撃判定
テーゼ生存 = **O(P)=LEVEL2 ∧ S(P)<LEVEL2 ∧ O(N)=no-theater**。
- O が P で LEVEL2 ∧ S が P で LEVEL1止まり → K1 生存（edge は instructable でない初証拠）。
- S が P で LEVEL2 → **K1 発火**（強 scaffold 単一が独力で出せる＝edge は instructable）。
- O が N で劇場 → **K2 発火**（overturn 信号はノイズ）。
- 副産物（K3 先読み）: adjudication の overturn が P で発火・N で不発なら、「2エージェント発散＝配備ルール」が効く初証拠。

## 実行手順

```sh
cargo build --release -p tracefield
# 配線確認（model-free）
./target/release/tracefield run --scenario-dir scenarios/bet2-overturn-p --config flow.mock.toml
# 実走（codex-app-server）。run ごとに別 store
./target/release/tracefield run --scenario-dir scenarios/bet2-overturn-p                          # Arm O / P
./target/release/tracefield run --scenario-dir scenarios/bet2-overturn-p --config flow.single.toml # Arm S / P
./target/release/tracefield run --scenario-dir scenarios/bet2-overturn-n                          # Arm O / N
./target/release/tracefield run --scenario-dir scenarios/bet2-overturn-n --config flow.single.toml # Arm S / N
```

## 限界（事前に明記）
- 第1スライスは題材1（P）+control1（N）・arm 各1走＝n小。continuity-vs-diffusion の n=1 を脱する*battery*（複数 P/N 題材・
  複数 seed・複数審判）は次段。本走は「機構が動く＋第1撃で K1/K2 が割れるか」まで。
- 単一モデル系列（codex）。append-only は overturn 型の1つ（status-drives-read / no-silent-drop は別題材で）。
- 審判1（盲検）＝長さ/体裁への暗黙バイアスは完全排除できない。

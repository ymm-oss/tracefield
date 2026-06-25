# 実装ブリーフ 14 — フェーズ1: モード / verify / 訂正デモ / レポート（roadmap 1-1〜1-4）

> codex 指示（第14弾）。前提: brief-13 まで実装済（ideate / Reference / Agent / Discovery）。
> フェーズ1 のパイロット機能を ideate に揃える。
> `mise exec -- mix ...`。ネット無し（mock のみ）。コミットしない。

## 1. モードプリセット（roadmap 1-1）

`tracefield.ideate` に `--mode diverge|converge|review`（既定 converge）:
| mode | rounds | k | temperature | 手続き |
| --- | --- | --- | --- | --- |
| diverge | 2 | 1 | 0.8 | scenario の `procedure.md` |
| converge | 3 | 4 | 0.5 | 同上 |
| review | 2 | 3 | 0.4 | `<scenario>/procedure-review.md` があればそれ、無ければ**組み込み既定**（下記） |

- 明示フラグ（--rounds/--k/--temperature/--serve/--aware）は**モード既定を上書き**。
- review の組み込み手続き: 「リスクレビュー手続き v1: PRESENTED ENTRIES と PRIVATE DOCUMENT を突き合わせ、この計画の**リスク・矛盾・見落とし**を具体的に指摘せよ。賛辞や言い換えは書くな。各指摘は根拠（私的事実 or 提示 entry の引用）を必ず持て。日本語で書け。」
- 出力ヘッダと保存 JSON の config に mode を含める。

## 2. 引用照合 verify（roadmap 1-2）

- `Reference.verify(ref, entries, opts)`（公開・バッチ）: 各 entry の各 citation について
  (a) 引用先が実在し active か、(b) **引用先テキストが当該主張の土台として実際に関係しているか**を LLM 判定。
  protocol キー `TRACEFIELD_VERIFY`。番号付き一括 `{"1":{"verified":true},...}`（1番号=1 citation ペア）。
  judge_adapter/judge_model/temperature/seed opts。寛容パース・失敗時 false。
  返り値: `%{ {citing_id, cited_id} => bool }`。procedure への引用は**常に true 扱い**（採用記録であり接地主張ではない）。
- **Mock 規則（決定的）**: 正規化後の citing/cited テキストが**長さ4以上の共通部分文字列トークン**を1つ以上共有すれば true、しなければ false。
- ideate 統合: 全 round 終了後に全アイデアの citation を一括 verify。
  - 表示: 各アイデアの cites を `e3✓` / `e5✗` のように注記。
  - metrics に `verification_rate`（検証済み citation / 全 citation、procedure 引用除外）を追加。

## 3. 訂正デモ（roadmap 1-3）

- `Reference.quarantine(ref, ids)` を追加: 各 id の status を `:superseded` に（既 retracted はそのまま）。
- `Reference.most_cited(ref, opts)`: active かつ type が :chunk/:procedure 以外で、**被引用数最大**の entry を返す（同数なら id 昇順最小）。
- ideate に `--correct auto|<entry-id>`（既定なし）:
  1. 本編 rounds 終了後、target を決定（auto = most_cited。無ければ「訂正対象なし」と表示して skip）。
  2. `retract(target)` → closure 取得 → `quarantine(closure ids)`。
  3. 表示: `訂正: <id>「<text先頭>」を撤回 → 依存 N 件を隔離` ＋ 隔離アイデアの一覧。
  4. **修復ラウンド**: 全 agent をもう 1 round 実行（system/user は通常どおり。serve は active のみ返すので撤回/隔離分は自然に消える）。
     修復ラウンドの user プロンプト末尾に `NOTE: 直前に entry <id> が誤りと判明し撤回された。それに依存しない代替案を出せ。` を追加
     （Agent.run_turn に `note:` opt を追加して伝える）。
  5. 表示: `修復ラウンドの代替案` 一覧。JSON に correction セクション（target/closure/repair entries）を保存。
- mock での決定性: mock の generic agent は first foreign entry を引用するため round≥2 で被引用が生じ、auto target の closure が非空になる。

## 4. Markdown レポート（roadmap 1-4）

`--report <path.md>`: 以下構成で書き出し:
```
# アイデア出しレポート — <scenario名>
- 日時 / mode / モデル / rounds / k / serve / aware
## タスク
<task.md 全文>
## アイデア（Round 別）
### Round 1
- **[KURASHI]** <text>（引用: e3✓, e5✗）
...
## 訂正（--correct 時のみ）
- 撤回: <id> <text>
- 隔離: ...
- 代替案: ...
## 健全性
- coverage / diversity / collapse_rate / verification_rate
## 領域横断の合成（cross-author）
- N 件: 一覧
```
- print 出力は従来どおり（レポートは追加）。

## 5. テスト

- mode 既定値の解決（diverge/converge/review、明示フラグ上書き、review の組み込み手続きフォールバック）。
- verify: mock 規則の正/負（共通トークンあり→true、完全に異なる語彙→false）、procedure 引用は常に true、verification_rate 算出。
- correct mock e2e: auto target が定まり closure 非空 → quarantine 済み → 修復ラウンドで ≥1 entry が出る → correction が結果 map に載る。
- report: ファイルが生成され、見出し（タスク/アイデア/健全性/領域横断）と ✓/✗ 注記を含む。--correct 併用時は訂正セクションも。
- 既存 44 tests green。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.ideate --scenario scenarios/housing-service --adapter mock --mode converge --correct auto --report /tmp/ideate-report.md` ── 訂正デモと ✓/✗ が表示され、レポートが生成されること（cat で先頭40行も SHOW）。

コミットしない。報告に変更ファイルと mock 出力。

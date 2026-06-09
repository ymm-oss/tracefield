# 実装ブリーフ 4 — 汚染入力の選択パラメータ化 + デコイ注入

> codex への実装指示（第4弾）。前提: 既存コード（brief-1/2/3 実装済）。`mise exec -- mix ...`。ネット無し。コミットしない。
> 目的: 汚染 A/B/C を切替可能にし、デコイ（両条件に同一注入する偽陽性対照, DR-4）を扱えるようにする。
> 新規 fixture は `scenarios/enterprise-assistant/` に作成済み（contaminant-B/C, correction-B/C, decoy-1/2）。

## 1. Scenario 読み込みの拡張（後方互換維持）

`Tracefield.Scenario` を拡張:
- 既存: `task`, `contaminant`(=A), `correction`(=A) はそのまま残す（既定で A。既存テスト/Mock 自己検証を壊さない）。
- 追加: `contaminants` マップ `%{"a" => %{contaminant: %Injection{}, correction: %Injection{}}, "b" => ..., "c" => ...}`。
  `scenarios/<dir>/contaminant-<X>.md` と `correction-<X>.md` が存在する分だけ読み込む（X ∈ a,b,c、大小無視）。
- 追加: `decoys`（`[%Injection{}]`）。`scenarios/<dir>/decoy-*.md` を全て読み込む（type=decoy, condition_state=both）。
- frontmatter/本文パースとメタ節除去は既存ロジックを再利用。

## 2. Explore の注入を一般化

`Explore.run/2` のオプション追加:
- `:contaminant`（"a"|"b"|"c"、既定 "a"）: どの汚染を使うか。
- `:decoys`（`[%Injection{}]`、既定 `[]`）: 両条件に同一注入する。
- 注入ロジック（`inject_after: initial-framing` 後、1度だけ）:
  - 状態Aなら選択汚染の **contaminant** 本文、状態Bなら **correction** 本文を注入（従来どおり）。
  - **デコイは状態に関わらず同一本文**を、同じ注入点で各 decoy を1ターンずつ追加（A・B 完全同一）。
  - 汚染ターンとデコイターンの順序・体裁は全 run で固定。

## 3. GroundTruth / measure の一般化

- `run/2` と `measure/4` に `:contaminant`（既定 "a"）と `:decoys` を通す。
- reconstruct のプロンプトは現在「contaminant A」を直書き。**選択汚染の本文**（`contaminant_body`）を使う形に一般化
  （文言は "the contaminant note" 等、汚染種別に依存しない表現へ。body は引き続き渡す）。
- それ以外（クラスタ/スタンス/affected/metrics）は不変。

## 4. mix タスク

- `tracefield.phase1` に `--contaminant a|b|c`（既定 a）と `--with-decoys`（bool, 既定 false）を追加。
  scenario から該当 contaminant/correction とデコイを取り出して run/2 に渡す。出力に使用した contaminant/decoys を明記。
- `tracefield.remeasure` も保存 summary に contaminant/decoys 情報があれば踏襲（無ければ a / decoys なし）。
- 保存 summary（to_plain）に `contaminant`（"a"|"b"|"c"）と `decoys`（id 一覧）を含める。

## 5. Mock / テスト

- 既定（contaminant a, decoys なし）で **Phase 0 自己検証は従来どおり**（affected={consent topic}, recall=precision=1.0）。
- Mock は B/C を意味的に扱う必要はない（B/C は実 ollama 専用）。ただし Mock 使用時に B/C/デコイを渡しても**クラッシュしない**こと。
- テスト追加: Scenario が contaminants(a/b/c) と decoys を読み込むこと、Explore がデコイを A・B 同一に注入すること（Mock で transcript を検査）。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（緑。新規テスト含む）
3. `mise exec -- mix tracefield.phase0`（従来どおり affected={consent}, proxy 1.0）
4. `mise exec -- mix tracefield.phase1 --adapter mock --n 4 --with-decoys`（クラッシュせず動作。デコイは A・B 同一なので
   依然 affected={consent topic} のまま＝デコイが偽陽性を生まないことを Mock で確認）

Ollama は実行しない。コミットしない。報告に変更ファイルと受け入れ結果を含める。

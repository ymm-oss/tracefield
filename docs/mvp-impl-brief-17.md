# 実装ブリーフ 17 — Reference 永続 store（設計judgments は tracefield 自身が導出）

> codex 指示（第17弾）。**本ブリーフの設計判断は、tracefield 自身が `scenarios/tracefield-dev` の実走で
> 導出したもの**（`runs/tracefield-dev-cli-smoke.md` / `runs/tracefield-dev-reqchange.md` の ARCH/SEC/QA/DX 判断。dogfooding）。
> 前提: brief-16 まで実装済（60 tests）。`mise exec -- mix ...`。ネット無し。コミットしない。

## 採用する設計判断（出典: dev 実走）

1. **[ARCH]** 追記型 JSONL ＋ リプレイによる状態再構築（provenance の append-only と思想一致）。起動時に**最大 id を復元**し採番衝突を防ぐ。
2. **[DX]** `Reference.start_link` は**シグネチャ不変・opts 追加のみ**（`persist_path:`、既定 nil=従来のインメモリ）。実験系タスクは無指定で従来挙動（opt-in 方式）。
3. **[SEC]** ファイルは**パーミッション 0600**。ローカルファイルのみ（外部送信なし）。暗号化は将来拡張（今回は範囲外と明記）。
4. **[QA]** 「保存→復元→同一」往復テスト必須。**破損耐性**: 途中で切れた/不正な JSONL 行は skip して継続復元。テスト分離は tmp パス注入。
5. **[R2]** 撤回・隔離の**状態変更も永続**し、リプレイで閉包再計算が可能であること。

## 1. `Tracefield.Reference` の永続化

- opts に `persist_path: nil | path` を追加（既定 nil＝完全に従来挙動）。
- **ログ形式**（1行=1 JSON）:
  - `{"op":"absorb","entry":{id,type,author,version,status,text,citations,embedding,meta}}`
  - `{"op":"status","id":"e7","status":"retracted"}`（retract / quarantine 時に追記）
- **書き込み**: absorb（初期種入れ含む）・retract・quarantine のたびに該当行を append（`File.write(path, line, [:append])`）。
  初回作成時に `File.touch!` → `File.chmod!(path, 0o600)`。
- **復元（init）**: persist_path のファイルが存在すれば行を順に decode して状態再構築
  （absorb→Entry 復元（embedding は保存値を使用・再埋め込みしない）、status→更新。decode 失敗行は skip し件数を数える）。
  `next_id` = 復元 entries の最大番号+1。
- **冪等種入れ**: `absorb_idempotent(ref, entries, author)` を追加 ── `{type, author, text}` が一致する
  **既存 entry（status 不問）**があればそれを返し、新規追記しない。復元後の再 seed（task/docs/procedure）の重複を防ぐ。
- `restored_count(ref)` 的な情報を init 後に取得できるように（`stats(ref)` → %{entries, restored, skipped_lines} 等）。

## 2. ideate の対応

- `--store true|false`（**既定 false**）。true のとき `persist_path: <scenario>/store.jsonl` で Reference 起動。
- **種入れ（task チャンク・docs チャンク・procedure）を idempotent absorb に変更**（store 再開時の重複防止。store 無効時も同 API で害なし）。
- ヘッダに `store: <path>（復元 N entries / 新規）` を表示。保存 JSON config にも。

## 3. テスト（QA 判断に基づく）

1. **往復同一**: tmp パスで absorb×複数（citations 付き）→ retract×1 → quarantine×1 → プロセス停止 → 同パスで再起動 →
   all() が**status 含め完全一致**、`closure` が復元データから同じ結果、新規 absorb の id が衝突しない（max+1）。
2. **破損耐性**: 最終行を途中で切ったファイル → 復元成功（skip 1 行）、有効 entries は揃う。
3. **0600**: 作成ファイルの mode 検証。
4. **冪等種入れ**: 同じ seed で2回起動（同パス）→ entries が増えない。別テキストなら追記される。
5. **既定 nil で従来挙動**（既存 60 tests がそのまま green であること自体が検証）。
6. ideate e2e（mock・tmp scenario・--store 相当 opts）: run1 で `--correct chunk:...` 実行 → run2 起動時に
   復元 N>0 かつ**当該チャンクが retracted のまま**であること（R2）。

## 4. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. tmp で2回の ideate（mock, store 有効）を実行し、2回目ヘッダの `復元 N entries` と retraction 永続を SHOW。

コミットしない。報告に変更ファイルと出力。

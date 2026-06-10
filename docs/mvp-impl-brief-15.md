# 実装ブリーフ 15 — 偏りの実在化（来歴メモリ / エージェント別手続き / エージェント別モデル）

> codex 指示（第15弾）。設計は [`design-agent.md`](./design-agent.md) **§9** を必読。前提: brief-14 まで実装済。
> `mise exec -- mix ...`。ネット無し（mock のみ）。コミットしない。

## 1. エージェント別モデル・手続き（agents.json 拡張）

`agents.json` の各エージェントに**任意キー**を追加可能に:
```json
{"id": "GIJUTSU", "domain": "design-tech", "desc": "...", "private_doc": "gijutsu.md",
 "model": "gemma4:26b", "procedure": "procedure-gijutsu.md"}
```
- `model`: 無ければ CLI の `--model`（従来どおり）。
- `procedure`: `<scenario>/<file>` を読み、**そのエージェント専用の procedure Entry** として absorb
  （author "FACILITATOR"、meta: %{owner: agent_id}）。当該エージェントの `procedure_id` はそれを指す。
  無ければ共有 `procedure.md`（従来）にフォールバック。review モードの共有手続きも従来どおり
  （エージェント別 procedure があるエージェントはそちらが**優先**）。

## 2. 来歴メモリ（永続・私的）

- 保存先: `<scenario>/memory/<AGENT_ID>.jsonl`（1行=1 entry: `{"ts","mode","text","citations"}`）。
- **読み込み**: ideate 開始時、各エージェントの memory ファイルの**直近 N 件（--memory-window、既定 10）**を読み、
  Agent に `private_memory:`（テキスト連結）として渡す。Agent はプロンプトの PRIVATE DOCUMENT 節の直後に
  `PRIVATE MEMORY (あなた自身の過去の判断。経験として活かせ):\n- <text>...` 節を**毎ターン**含める（store には書かない）。
- **書き込み**: run 終了時（訂正の修復 entries も含む）、**各エージェント自身の absorbed entries のみ**を
  その agent の memory ファイルへ追記（ts は run 開始時刻文字列、mode 付き）。
- フラグ: `--memory true|false`（既定 **true**）。false なら読みも書きもしない。
- メモリディレクトリが無ければ作成。テスト時は tmp に scenario をコピーするか、`persist?: false` と独立に
  `memory_dir:` opt で上書きできるようにする（テスト汚染防止。既定は `<scenario>/memory`）。

## 3. 出力・レポートへの反映

- 起動ヘッダにエージェント構成を表示: `KURASHI(model=gemma4:12b, proc=shared, memory=3件)` のように
  **model / procedure(専用 or shared) / 読み込んだ memory 件数**。
- レポートの設定欄にも同様の per-agent 行を追加。
- 保存 JSON の config.agents に model/procedure_source/memory_loaded を含める。

## 4. Mock / テスト

- mock の挙動変更は不要（PRIVATE MEMORY 節は無視される。プロンプト節が増えても既存 regex が壊れないことを確認）。
- テスト:
  1. agents.json の model/procedure 解決（指定あり→個別、なし→フォールバック）。エージェント別 procedure Entry が
     別々に absorb され、各 agent の citations に**自分の** procedure_id が付くこと。
  2. メモリ round-trip: `memory_dir` を tmp にして ideate を2回実行（mock）→ 2回目の Agent プロンプトに
     1回目の自分の entry テキストが含まれる（プロンプト捕捉 mock）／memory ファイルに自分の entries **のみ**が
     追記されている（他 agent の entry が混ざらない）こと。
  3. `--memory false` で読み書きされないこと。
  4. window: N=1 のとき直近1件のみ注入。
- 既存 50 tests green。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.ideate --scenario scenarios/housing-service --adapter mock --rounds 2 --memory true` を**2回**実行し、
   2回目のヘッダで memory 件数が >0 になること（SHOW 両方のヘッダ）。終了後 `ls scenarios/housing-service/memory/` も SHOW。

コミットしない。報告に変更ファイルと出力。

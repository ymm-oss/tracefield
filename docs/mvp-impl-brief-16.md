# 実装ブリーフ 16 — フェーズ2: 文書チャンク接地 / 要件・手続き撤回 / CLI 器官

> codex 指示（第16弾）。roadmap フェーズ2（2-1〜2-4）の機構。fixture は作成済み: `scenarios/tracefield-dev/`
>（`docs/*.md` = 要件/ADR/制約チャンク、4レビュア＋方法論手続き）。前提: brief-15 まで実装済。
> `mise exec -- mix ...`。ネット無し（mock のみ。CLI 実呼び出しもしない）。コミットしない。

## 1. 文書チャンク接地（design-reference フェーズ1 のハーネス実装）

- ideate: シナリオに `docs/` ディレクトリがあれば、**各 .md ファイルを1つの :chunk entry** として
  Reference に種入れ（author "DOCS"、meta: %{file: ファイル名}）。従来の task チャンクはそのまま。
- **Agent への提示**: 新 opt `reference_docs:`（[%{id, file, text}]）。プロンプトの TASK 節直後に
  `REFERENCE DOCUMENTS（設計判断はここを引用せよ）:` 節として **毎ターン全文**を表示
  （形式: `DOC <id> file=<file>\n<text>`）。
- **引用許可**: sanitize の許可集合に reference_docs の id を追加（presented + docs + procedure）。
- ideate は agents 構築時に全 doc チャンクを reference_docs として渡す（小規模前提・≤10 chunks）。

## 2. --correct の拡張（要件変更デモ / 欠陥手続きデモ）

既存 `--correct auto|<entry-id>` に加え:
- `--correct chunk:<file>`: `docs/<file>` のチャンク entry を解決して retract（**要件変更デモ**）。
- `--correct procedure:<AGENT_ID>`: 当該エージェントの procedure entry を retract（**欠陥手続きデモ**。
  閉包＝その手続きを citation した全判断）。
- 閉包→quarantine→note 付き修復ラウンドの流れは既存のまま。note 文言は対象種別で変える:
  chunk なら「要件 <file> が変更され撤回された。新しい前提で代替判断を出せ。」、
  procedure なら「<AGENT_ID> の手続きに欠陥が見つかり撤回された。」。

## 3. CLI 器官アダプタ（2-3）

`Tracefield.LLM.CLI`（behaviour 実装）:
- opts: `cli: {cmd, base_args}`（既定 `{"claude", ["-p"]}`）。**プロンプトは最終引数**として渡す
  （messages を `system\n\nuser` 連結のプレーンテキストに）。`System.cmd(cmd, base_args ++ [prompt], stderr_to_stdout: true)`、
  timeout は Task.async + Task.yield で 300_000ms（超過 {:error, :cli_timeout}）。
- exit 0 → {:ok, stdoutのtrim}。非0 → {:error, {:cli_error, code, 出力先頭200字}}。
- `model` opt があり cmd が "claude" の場合は base_args に `["--model", model]` を足す。seed/temperature は無視（非決定・ドキュメントに明記）。
- ideate: `--adapter cli` を受け付け（adapter_module 解決に追加）、`--cli-cmd <cmd>` で実行ファイル名を上書き可
  （base_args は claude 既定のまま）。
- **テスト**: 実 CLI は呼ばない。tmp に `#!/bin/sh\necho '{"entries":[...]}'` スクリプトを書いて
  `cli: {そのパス, []}` で1ターン回し、entries が absorb されること＋非0 exit スクリプトで {:error,...} → エージェントが
  空ターンで継続すること。

## 4. Mock 拡張（チャンク引用の決定性）

- generic mock agent（未知 id）: プロンプトに `DOC <id>` 行があれば、**最初の DOC id を citations に追加**
  （既存の foreign entry 引用と併存可）。→ mock e2e で chunk 撤回の閉包が非空になる。

## 5. テスト

- docs/ 読み込み→ :chunk 種入れ（6件）、プロンプトに REFERENCE DOCUMENTS 節、chunk id への citation が通る。
- `--correct chunk:r3-local-only.md`（mock）: 対象解決→retract→閉包非空（DOC を引用した判断が入る）→修復 entries ≥1。
- `--correct procedure:ARCH`（mock）: ARCH の手続き entry が retract され、閉包に ARCH の判断（自手続き citation 持ち）が入る。
- CLI アダプタ: §3 のスクリプトテスト2件。
- 既存 55 tests green。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.ideate --scenario scenarios/tracefield-dev --adapter mock --rounds 2 --memory false --correct chunk:r3-local-only.md`
   ── REFERENCE DOCUMENTS 提示・chunk 撤回→閉包→修復が表示されること。

コミットしない。報告に変更ファイルと mock 出力。

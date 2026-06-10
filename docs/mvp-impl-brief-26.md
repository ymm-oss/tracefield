# 実装ブリーフ 26 — implement stage（workspace 実行 + gate I）

> cursor-agent 指示（第26弾）。設計は [`design-pipeline.md`](./design-pipeline.md) §1-§3。前提: brief-25 まで（110 tests）。
> `mise exec -- mix ...`。ネット不可。**tracefield リポジトリに git commit しない**（テスト内 tmp リポジトリへの commit はテスト動作なので可）。mise.toml に触れない。
> 着手前に必読: `lib/mix/tasks/tracefield.dev.ex` / `lib/tracefield/reference.ex` / `lib/tracefield/llm/human.ex` / `lib/tracefield/llm/mock.ex` / `test/dev_task_test.exs`（brief-25 の design stage と同型のパターンを implement に拡張する）。
> 核心: パイプラインが**初めて実リポジトリに触れる**。器官（CLI）が workspace を編集し、tracefield は調整と来歴の層に徹する:
> 承認済み設計判断 → 器官実行 → diff/テスト結果を `:change` entry（設計判断を citation）→ 人間 gate I → apply（= workspace への git commit）。

## 1. `workspace.json`（issue dir 直下、implement の前提条件）

```json
{"path": "<対象リポジトリ>", "test_cmd": "true", "organ": {"cmd": "claude", "args": ["-p"], "author": "ORGAN"}}
```

- `path` 必須。相対なら issue dir 基準で解決。存在し `.git` を持たなければ `Mix.raise`。
- `test_cmd` 省略時 `"mise exec -- mix test"`。`organ` 省略時 `cmd: "claude", args: ["-p"], author: "ORGAN"`。

## 2. `Tracefield.Workspace`（新モジュール）+ `Tracefield.Workspace.OrganMock`

- `configured?(issue_dir)` — workspace.json の存在。
- `load!(issue_dir)` — 検証済み struct（path/test_cmd/organ_cmd/organ_args/organ_author）。
- `clean?(ws)` — `git status --porcelain` が空。
- `implement!(ws, prompt, adapter)` — adapter が `Tracefield.LLM.Mock` なら `OrganMock.run(path, prompt)`:
  決定的に `IMPLEMENTED.md` へ「mock実装\n」+ prompt 中の設計判断行（`^e\d+:` にマッチする行）を append し `{:ok, "mock実装: IMPLEMENTED.md を更新"}`。
  それ以外は `System.cmd(organ_cmd, organ_args ++ [prompt], cd: path, stderr_to_stdout: true)`、exit 0 → `{:ok, output}` / 非0 → `Mix.raise`。
- `capture_diff!(ws)` — `git add -A` 後に `%{files: name-only リスト, stat: --stat 出力の最終行, diff: cached 全文, sha: sha256(diff) 先頭12hex}`。
- `run_tests!(ws)` — `System.cmd("sh", ["-c", test_cmd], cd: path, stderr_to_stdout: true)` → `%{exit: code, tail: 出力末尾800字}`。
- `apply!(ws, message)` — `git add -A` → `git commit -m message`。staged が空なら `{:error, :empty}`、成功 `{:ok, short_sha}`。
  （テストでは `git -c user.email=t@tracefield -c user.name=tracefield commit ...` のように `-c` で identity を与える。Workspace 側の commit も `-c` 付きで実行してよい。）

## 3. `Reference` — `@types` に `:change` を追加（永続/replay は既存機構で自動）。

## 4. `tracefield.dev` の implement stage（brief-25 の design と同型）

- dispatch 変更: `design`+`done` → `Workspace.configured?` なら `start_implement`、なければ
  「design 完了。implement を開始するには workspace.json を置いてください」+ 既存 `print_design_done`（**brief-25 の既存テストは workspace.json 無しなのでこの分岐で green のまま**）。
  `implement`+`done` → 「implement 完了。次: qa（未実装）」+ `print_implement_done`。`implement`+その他 → `resume_implement`。
- `start_implement`:
  1. `load!` → `clean?(ws)` でなければ `Mix.raise`（「workspace が clean ではありません」）。
  2. 承認済み設計判断 = human の active `:decision` に引用されている machine（llm/cli actor 著者）の active `:decision`。0件なら `Mix.raise`。
  3. organ ラウンド `run_organ_round`（round = state["round"]+1）:
     プロンプト = `TRACEFIELD_IMPLEMENT` マーカー + ISSUE 全文 + active requirement 一覧（`e<id>: text`）+ 承認済み設計判断一覧（`e<id>: text`）
     +（resume 時のみ）人間レビューコメント + 直前の diff stat
     + 「あなたは実装器官。カレントディレクトリの対象リポジトリを設計判断どおりに変更せよ。git commit は行うな。変更の概要のみ出力せよ。」
     → `implement!` → `capture_diff!` → `run_tests!` → diff 全文を `pending/implement-r<round>.patch` へ書く →
     `:change` を absorb（author = organ_author、text = `実装変更 r<round>: <stat> / テスト: <green|red> (exit <N>) / diff: pending/implement-r<round>.patch`、
     citations = 承認済み設計判断 ids、meta = `%{files:, diff_sha:, test_exit:, round:, organ_summary: 出力先頭400字}`）。
  4. gate I = 人間 blocking ターン（stage `"implement"`、approve_targets = organ author の active `:change` ids、ref_docs は design と同じ）→ awaiting / 完了。
- `resume_implement`（resume_design と同型）: 完了判定 `implement_complete?` = human の active `:decision` が active `:change` を引用
  （gate R/D の承認は requirement / decision を引用するので**衝突しない**）。人間 entries 無し → awaiting のまま。
  コメントのみ → organ 追加ラウンド（コメントをプロンプトに含める）→ 新 `:change` → 再 gate（iteration+1）。
  完了時: `apply!(ws, "tracefield implement: <issue 1行目60字> [<change ids>]")`（`{:error, :empty}` は警告して続行）→ state done →
  `print_implement_done`: active `:change` 数 / workspace HEAD 短縮 sha / **3-hop provenance** `change → decision → requirement → issue chunk`（design の 2-hop printer と同型で1段深く）。

## 5. テスト（`test/workspace_test.exs` 新規 + `test/dev_task_test.exs` 追記）

- unit: workspace.json 欠落/非 git path → raise。OrganMock が IMPLEMENTED.md を書く。capture_diff! の files/sha。run_tests! exit 0/1。apply! が commit を作り HEAD が進む。
- e2e（mock、既存 helper を `drive_to_design_done!(dir)` として抽出推奨）: design done 後に workspace.json（tmp git repo: init+初期 commit、test_cmd `"true"`）を置いて run →
  `:change` が承認済み設計判断を引用 / `pending/HUMAN-implement.md` と `pending/implement-r*.patch` が存在 / state = implement/awaiting_human。
  コメントのみ → 2つ目の `:change`（iteration 1）→ まだ awaiting。APPROVE → done: human `:decision` が `:change` を引用、workspace の git log が1件増、
  3-hop 連鎖（change→decision→requirement→issue chunk）が entries 上で辿れる。再実行 → done のまま。
  異常系: dirty workspace → raise。test_cmd `"false"` → `:change` text に `red`。
- 既存 110 tests green 維持。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（110 + 新規、全 green）
3. 変更ファイル一覧

コミットしない。報告に変更ファイルとテスト結果。

# 実装ブリーフ 31 — git flow ポリシー v1（current/main/branch/worktree + ポリシーの来歴化）

> codex 指示（第31弾）。前提: issue-006 まで（165 tests）。設計者: Claude（本ブリーフが設計成果物）。
> `mise exec -- mix ...`。ネット不可。**tracefield リポジトリに git commit しない**（テスト内 tmp リポジトリへの
> commit/branch/worktree 操作はテスト動作なので可）。mise.toml に触れない。
> 着手前に必読: `lib/tracefield/workspace.ex` / `lib/mix/tasks/tracefield.dev.ex`（start_implement / resume_implement /
> start_qa / run_organ_round / print_implement_done / print_qa_done）/ `lib/tracefield/reference.ex`（@types）/ `test/workspace_test.exs`。
> 核心: 「mainに直接 / 作業ブランチ / worktree」という**作業様式を設定で規定**し、かつ**実効ポリシーを citable entry に
> して change が引用する** —— 成果物だけでなく作業様式まで来歴に乗る。merge 自動化と PR モードは本ブリーフの範囲外（次弾）。

## 1. workspace.json の `git` セクション

```json
"git": {
  "mode": "branch",
  "branch_template": "tracefield/{slug}",
  "base": "main",
  "worktree_root": null
}
```

- `mode`: `"current" | "main" | "branch" | "worktree"`。**セクション省略時は `"current"`** = 現在の挙動と完全一致
  （checkout もブランチ管理も一切しない。既存テストはこの経路で無変更 green になること）。不正値は `Mix.raise`。
- `branch_template` 既定 `"tracefield/{slug}"`。`{slug}` は issue dir の basename に置換。
- `base` 既定 `"main"`。`worktree_root` 既定 nil → `<repoの親>/<repo名>-worktrees`。
- `%Workspace{}` struct に `git_mode` / `git_branch_template` / `git_base` / `git_worktree_root` を追加し `load!/1` で展開・検証。

## 2. `Workspace.ensure_flow!(ws, slug)` — 冪等な作業様式の確立

戻り値は（worktree の場合 path を差し替えた）`%Workspace{}`。

- `current` → 何もしない。
- `main` → 現ブランチが base でなければ `git checkout <base>`。
  `⚠ git flow: main — <base> へ直接コミットします` を表示（このモードのみ ⚠）。
- `branch` → branch 名 = template 置換。存在しなければ `git checkout -b <branch> <base>`、
  存在して未チェックアウトなら `git checkout <branch>`、チェックアウト済みなら何もしない。
- `worktree` → branch 名は同上。worktree path = `<worktree_root>/<slug>`。
  無ければ `git worktree add <path> -b <branch> <base>`（branch 既存なら `-b` なしで attach）。
  以後の ws.path を worktree path に差し替えて返す。冪等（2回目以降は existing worktree を解決して path 差し替えのみ）。
- checkout を伴う操作は dirty なら `Mix.raise`（既存 `clean?` を流用。current は従来どおり start_implement 側の検査のみ）。
- 呼び出し箇所: `start_implement` / `resume_implement` / `start_qa` の `Workspace.load!` 直後。
  `print_implement_done` / `print_qa_done` は実行系から解決済み ws を受け取るか、表示用に
  非破壊の path 解決（checkout しない）を行うこと（worktree モードで HEAD 表示が正しい path を見るため）。

## 3. ポリシーの来歴化（本ブリーフの統治の要）

- `Reference` の `@types` に `:policy` を追加。
- `run_dev` で workspace が configured の場合、実効 git ポリシーを `absorb_idempotent` で seed:
  type `:policy`、author `"POLICY"`、text = `git flow: mode=<mode> branch=<branch名 or "-"> base=<base>`（決定的な1行）、
  meta = `%{kind: "git_flow", mode:, branch:, base:}`。
- `run_organ_round` が absorb する `:change` の citations 末尾にこの policy entry id を追加する
  （= 「この変更はこの作業様式の下で作られた」が引用で辿れる）。
- implement 開始時に `git flow: <mode> (branch=<...>)` を `Mix.shell().info` で表示（監査の可視性）。

## 4. テスト（`test/workspace_test.exs` / `test/dev_task_test.exs` 追記。tmp git repo は既存ヘルパの流儀）

- load!: git セクション省略 → mode :current / 各値の既定 / 不正 mode で raise。
- ensure_flow! unit（tmp repo）:
  - current: no-op（ブランチ・HEAD 不変）。
  - main: 別ブランチから base へ checkout される。
  - branch: 初回は base から作成+checkout、再呼び出しで冪等。dirty 時 raise。
  - worktree: worktree dir と branch が作られ ws.path が差し替わる。再呼び出しで同じ path に解決。
    元 repo の working tree が汚れないこと。
- e2e: 既存 implement/qa e2e は git セクション無しのまま**無変更で green**（互換の証明）。
  新規 e2e（mode branch）: implement 承認後の commit が branch 上にあり base が動いていないこと。
  新規 e2e（mode worktree）: commit が worktree の branch 上にあり、元 repo の HEAD/working tree が不変であること。
- ポリシー来歴: :policy entry が seed され、:change の citations に policy id が含まれること。
  同一 issue の再実行で :policy が重複しないこと（idempotent）。
- 既存 165 green 維持。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（165 + 新規、全 green）
3. 変更ファイル一覧

コミットしない。報告に変更ファイルとテスト結果。

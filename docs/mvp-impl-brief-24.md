# 実装ブリーフ 24 — 開発パイプライン骨格: Actor 抽象 / Human 器官 / refine stage

> codex 指示（第24弾）。設計: [`design-pipeline.md`](./design-pipeline.md)・[`design-agent.md`](./design-agent.md) §10/§10b。
> 前提: brief-23 まで（105 tests）。`mise exec -- mix ...`。ネット無し。コミットしない。
> 方針: **Human 器官は同じ LLM behaviour を実装し、人間の Markdown 回答を JSON 契約へ翻訳**（Agent 無改造で人間が Actor になる）。

## 1. Actor 定義（actors.json）

- Issue ディレクトリは `actors.json` を読む（無ければ `agents.json` にフォールバック＝後方互換）。
- 追加フィールド: `kind: "llm" | "cli" | "human"`（省略時 llm）、`turn: "blocking" | "async"`（省略時 blocking。v1 の人間は blocking のみ使用）。
- human kind は `private_doc` 不要（省略可）。

## 2. Human 器官 `Tracefield.LLM.Human`

`complete(messages, opts)`（behaviour 実装）。opts: `human: %{pending_dir, actor_id, stage}`。v1 は**非同期ファイル方式**:
1. `pending/<actor_id>-<stage>.md` が**無い**: messages を人間向け Markdown に整形して書き出し
   （プロンプト各節＋末尾に下記テンプレ）、`{:error, :awaiting_human}` を返す。
   ```
   ## RESPONSE（この下に回答を書いてください）
   <!-- 箇条書き1行=1エントリ。引用は [e12] 形式。質問への回答は [質問のid] を引用。
        要件を承認する場合は単独行で APPROVE と書く -->
   ```
2. ファイルが**有り RESPONSE が空**: 何もせず `{:error, :awaiting_human}`。
3. **RESPONSE に記入あり**: パースして **エージェントと同じ JSON 契約** `{"entries":[{"type":..,"text":..,"citations":[..]}]}` の
   文字列を `{:ok, json}` で返し、ファイルを `pending/done/` へ移動。
   - 箇条書き `- <text> [e3] [e5]` → entry（text から [..] を除去、citations=[e3,e5]、type は
     質問 id を引用していれば `"answer"`、それ以外 `"observation"`）。
   - 単独行 `APPROVE` → `{"type":"decision","text":"要件を承認する","citations":[<active な requirement 全 id ← opts.human.approve_targets で渡す>]}`。

## 3. Reference: entry type 追加

`@types` に `:requirement` と `:answer` を追加（restore 経路含め自然対応）。

## 4. パイプライン `mix tracefield.dev --issue <dir>`

- **常に store 有効**（`<dir>/store.jsonl`。中断・再開の前提）。`state.json` に `%{stage: "refine", status: ...}`。
- 同一コマンドが**状態機械として再入可能**: 初回=開始、awaiting_human 中=人間回答の取り込みを試行、完了済み=サマリ表示。
  `--status` で現在地表示。
- **refine stage**:
  1. seed: `issue.md` を chunk（author "ISSUE"）、`docs/*.md` を chunk（既存パターン）。
  2. llm/cli actors が rounds（既定2）回る。**組み込み refine 手続き**（procedure entry として absorb）:
     「REFINE手続き: ISSUE と REFERENCE DOCUMENTS から、(a) 受入基準を含む要件を type "requirement" で、
      (b) 人間に確認すべき不明点を type "question" で書け。各 entry は根拠チャンクを引用。日本語。」
  3. human actor（blocking）の番: Human 器官が pending を書き `awaiting_human` → run 終了
     （表示: `⏸ 人間の回答待ち: pending/<actor>-refine.md`）。state.json = awaiting_human。
  4. 再実行で回答を取り込み: answer/observation entries（著者=human actor id）を absorb。
     - **APPROVE（decision entry）あり** → stage 完了（state refine=done）。サマリ＋ provenance 例
       （`requirement → issue chunk` の引用連鎖を1本表示）。
     - **APPROVE 無し（回答のみ）** → llm actors を**もう1ラウンド**回し（人間の回答を場から織り込む）、
       pending を再生成して再び awaiting_human（= 詳細化の反復ループ）。
- gate ポリシー: refine の完了条件 = **human kind の actor による decision entry（承認）が存在**すること。

## 5. Mock 拡張

- `TRACEFIELD_AGENT_TURN` で、プロンプトに「REFINE手続き」がある場合:
  決定的に `{"type":"requirement","text":"要件: <issue先頭40字> を満たすこと（受入基準: テスト green）","citations":[<最初のDOC/ISSUE chunk id>]}` と
  `{"type":"question","text":"確認: 対象範囲はどこまでか？","citations":[同]}` の2件を返す（agent id でテキストを微差別化）。

## 6. テスト

- actors.json 読み込み（kind/turn、agents.json フォールバック、human の private_doc 省略可）。
- Human 器官: 初回 pending 生成（プロンプト節＋RESPONSE テンプレ含む）→ awaiting / RESPONSE 空 → awaiting /
  記入後 → JSON 契約（箇条書き→entries、[eN] 引用抽出、質問引用で type answer、APPROVE→decision with approve_targets）・done/ へ移動。
- dev e2e（mock・tmp issue dir）: ①初回実行 → requirement/question が store に・pending 生成・state=awaiting_human。
  ②RESPONSE に回答（質問 id 引用）のみ記入 → 再実行 → answer absorb・追加ラウンド・pending 再生成・依然 awaiting。
  ③APPROVE 記入 → 再実行 → human の decision（requirement 群を citation）・state=done・
  **provenance 連鎖 requirement→issue chunk が検証できる**こと。store 永続（再起動後も状態一致）。
- 既存 105 tests green。

## 7. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. tmp issue dir で `mix tracefield.dev --issue <dir>` を**3回**（初回→回答→APPROVE）実行する流れを SHOW
   （pending ファイルの中身先頭と、最終サマリの provenance 連鎖を含む）。

コミットしない。報告に変更ファイルと出力。

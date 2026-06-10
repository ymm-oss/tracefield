# 実装ブリーフ 23 — プロンプト予算と文書注入の自動縮退（無音切り捨ての根絶）

> codex 指示（第23弾）。背景: Ollama は num_ctx 超過時に**無音で前方切り捨て**（TASK・REFERENCE DOCUMENTS が先に消える）。
> 方針: 計測 → 予算 → 超過時は**文書注入を retrieval 化**（store-pull 原則を文書にも適用）。store からは何も消えない＝損失なし、
> 注入の絞りは perception に記録（governed）。前提: brief-22 まで（96 tests）。`mise exec -- mix ...`。ネット無し。コミットしない。

## 1. トークン推定 `Tracefield.Tokens`

- `estimate(text)`: 決定的ヒューリスティック `ceil(String.length(text) / 3)`（日英混在の中庸。正確さでなく**単調性と再現性**が目的）。
- `estimate_messages(messages)`: 各 content の合計。

## 2. Ollama アダプタ: num_ctx 明示

- opts `num_ctx:`（既定 **8192**）を options に含める。
- 純関数 `build_options(opts)` を公開し（seed/temperature/num_predict/num_ctx を返す）、unit test 可能に。

## 3. Agent: 予算と文書の自動縮退

- `Agent.new` opts: `num_ctx:`（既定 8192）、`k_docs:`（既定 3）。予算 = `num_ctx - num_predict(1200) - 512(マージン)`。
- RunTurn の組み立てを2段階に:
  1. 従来どおり**全文書注入**でプロンプト草稿 → `Tokens.estimate_messages` が予算内なら `doc_mode: :full`。
  2. 超過なら **selected モード**: REFERENCE DOCUMENTS 節を
     「**目次**（全 active 文書の `DOC <id> file=<file>: <先頭行>`）＋ **関連上位 k_docs 件のみ全文**」に差し替え。
     上位選定は `Reference.serve(ref, query, k: k_docs, only_author: "DOCS", policy: :similar)`（既存・embedding 類似・決定的）。
     節見出しは `REFERENCE DOCUMENTS（予算超過のため関連上位のみ全文・他は目次。引用は目次の id でも可）:`。
     **目次の id も引用許可集合に含める**（全 doc id は従来どおり許可）。
  3. selected でも超過なら、そのまま送信しつつ `over_budget: true`。
- perception に追加: `prompt_tokens_est`、`doc_mode`、`docs_full_ids`（全文注入された doc id）、`over_budget`。

## 4. ideate の対応

- フラグ `--num-ctx`（既定 8192）/ `--k-docs`（既定 3）→ Agent へ伝播（Ollama アダプタへも num_ctx を opts で渡す）。
- run 終了時、perception を走査して **警告サマリ**を表示:
  `⚠ 文脈予算: selected モード N ターン / 超過 M ターン（最大 est X tok, 予算 Y）`（N=M=0 なら1行 `文脈予算: 全ターン full（最大 est X / 予算 Y）`）。
- config/保存 JSON に num_ctx・k_docs・doc_mode 統計を含める。

## 5. テスト

- Tokens: 単調性（長い文字列ほど大）・空文字 0 or 1・messages 合計。
- build_options: num_ctx 既定と上書き。
- doc 縮退: 小文書＋十分な num_ctx → :full（全文書テキストがプロンプトに在る）。
  長文書（ダミー長文 chunk 群）＋小さい num_ctx → :selected（目次行が在る・全文は上位 k のみ・
  perception の doc_mode/docs_full_ids が正しい・目次のみの doc id も citation が通る）。
- over_budget: 極小 num_ctx で true、ideate の警告サマリ行が出る（CaptureIO）。
- ideate フラグの伝播（config に反映）。
- 既存 96 tests green。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. tmp scenario（長文書）＋ `--num-ctx 1024` で ideate（mock）を実行し、selected モードと警告サマリを SHOW。

コミットしない。報告に変更ファイルと出力。

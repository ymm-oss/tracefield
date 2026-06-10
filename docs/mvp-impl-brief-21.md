# 実装ブリーフ 21 — 蒸留（house view）: 垂直伝達の機構化

> codex 指示（第21弾）。設計は [`design-cluster.md`](./design-cluster.md) §8（蒸留）。前提: brief-20 まで（82 tests）。
> `mise exec -- mix ...`。ネット無し。コミットしない。
> 核心: **文化に provenance を与える** ── house view は蒸留元を citation する版管理 entry。
> 元判断の撤回 → house view が閉包に入り失効 → 再蒸留、まで統治が届く。

## 1. `Culture.distill(ref, opts)`

- 対象選択: active な belief/decision 系（非 chunk/procedure/genesis/house_view）を
  **被引用数降順→新しい順**で `limit:`（既定 5）件（Meta.publish と同じ規準）。対象 0 件なら `{:error, :nothing_to_distill}`。
- **生成（既定 `mode: :extractive`、決定的）**: テキスト =
  `"house view v<N>:\n- <text1>\n- <text2>…"`（各 text は 120 字で切る）。
- `mode: :llm`: protocol キー `TRACEFIELD_DISTILL`。「以下のチームの判断群から、チームの判断方針を3〜5箇条で蒸留せよ。日本語。」
  寛容に本文を受け取り（JSON 不要・プレーンテキスト）、失敗時は extractive にフォールバック。
  Mock: `TRACEFIELD_DISTILL` を見たら決定的に「mock蒸留: <先頭 entry text 先頭40字>」を返す分岐を追加。
- **版管理**: 既存の最新 house view があれば `version = その+1`・既存を `quarantine`（superseded）。無ければ v1。
- absorb: `type: :house_view`（`@types` に追加）、author `"CULTURE"`、
  **citations = 蒸留元 entry ids ＋（あれば）先代 house view id**、meta: %{house_view_version: N}。persist 対応は既存機構で自動。
- `Culture.house_view(ref)`: **active な最新版**の house view entry か nil。

## 2. メンバーへの有界注入（Agent / ideate）

- `Agent.new` opts に `house_view:`（テキスト）。プロンプトの PRIVATE MEMORY 節の直後に
  `HOUSE VIEW（チームのこれまでの判断方針。踏まえつつ、自分の偏りからの異見も歓迎）:\n<text>` を毎ターン挿入（空なら節ごと省略）。
- ideate に `--distill true|false`（既定 **false**）:
  - 開始時: `Culture.house_view(reference)` が在れば全 agent に注入し、ヘッダに `house view: v<N> 注入` を表示（無ければ `なし`）。
  - 終了時（訂正後の最終状態に対して）: `Culture.distill` を実行（mode は `--distill-mode extractive|llm`、既定 extractive）し、
    `蒸留: house view v<N> を生成（元 entries: ...）` と **`Culture.transmission`（charter=新 house view text）** を表示。
  - config/保存 JSON に house_view_injected_version / house_view_new_version を含める。
- `--store true` と独立に動くが、**永続させたい場合は --store true 併用**（README 雛形に1行追記）。

## 3. 統治テスト（本ブリーフの要）

house view の **provenance 統治**を必ずテスト:
1. entries 群 → distill v1（citations=元 ids）。
2. 元 entry の1つを `retract` → `closure` に **house view が含まれる** → quarantine で superseded。
3. `Culture.house_view` が nil（または先代も superseded なら nil）になる。
4. 再 `distill` → **v2 が撤回済み entry を含まずに**生成される（対象選択が active のみだから自然に）。

## 4. その他テスト

- distill: 選択規準（被引用順）、版増分＋先代 superseded、author/citations/meta、`{:error, :nothing_to_distill}`。
- llm mode: mock 分岐の決定的テキスト、LLM エラー時 extractive フォールバック。
- Agent 注入: prompt 捕捉 mock で HOUSE VIEW 節の有無（house_view 渡し有り/無し）。
- ideate e2e（mock・tmp scenario・store+distill）: run1 終了時に v1 が store に永続 → run2 開始ヘッダで `v1 注入`
  → run2 終了時 v2 生成（config の各 version 値も検証）。
- 既存 82 tests green。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. tmp scenario で ideate（mock, --store true --distill true）を**2回**実行: 1回目 `house view: なし`→`蒸留: v1`、
   2回目 `house view: v1 注入`→`蒸留: v2`、を SHOW。

コミットしない。報告に変更ファイルと出力。

# 実装ブリーフ 12 — serve 多様化 × 半溶解の状況認識（2×2）

> codex 指示（第12弾）。前提: brief-9〜11 実装済。§13 のファネル（検索段×表現段）と
> ユーザー指摘「エージェントは半溶解構造を知らされていない」への対応。
> `mise exec -- mix ...`。ネット無し。コミットしない。

## 1. serve 方策 `:diverse`（Reference）

`Reference.serve/3` に `policy: :similar（既定・現行）| :diverse` を追加。
- `:diverse`: active かつ非 procedure、requester（exclude_author）以外の entries を**著者ごとにグループ化**し、
  各著者の**最新 entry**（id 採番の降順）から**著者ラウンドロビン**で k 件まで取る（著者バランス提示）。
  決定的・接地真実を使わない（公平）。k > 著者数なら各著者の2番目…と続ける。
- 既定 `:similar` の挙動は不変。

## 2. 半溶解プリアンブル（Agent）

`Agent.new` opts に `aware: false（既定）| true` を追加。`aware: true` のとき system prompt の先頭
（TRACEFIELD_AGENT_TURN の直後）に以下を**毎ターン**挿入:

```
SITUATION: あなたは、異なる偏りを持つ複数の AI エージェントが共有ストアで協働する
「半溶解チーム」の一員である。他のエージェントはそれぞれ、あなたには見えない私的文書を持つ。
PRESENTED ENTRIES は彼らがその私的知識から外部化した状態であり、あなたがその情報に触れる唯一の窓である。
ただの文脈ではなく、あなたの知らない事実を含む証拠として扱え。あなたの entries も他のエージェントに読まれる。
自分の偏り（DOMAIN）を保ったまま、彼らの状態を自分の私的事実と突き合わせて活用せよ。
```

また serve 呼び出しに `policy:` を渡せるよう `Agent.new` opts に `serve_policy:`（既定 :similar）を追加し、
run_turn の `Reference.serve` に伝播。

## 3. hetero の 2×2 グリッド

- フラグ追加: `--serve similar,diverse`（既定 "similar"）/ `--aware 0,1`（既定 "0"）。
- グリッド = ks × kps × serves × awares。行とサマリに `serve` `aware` 列を追加。
- 傾向行: disc_strict を serve 軸・aware 軸それぞれで比較表示。
- perception ログは従来どおり（serve 方策の効果検証に使う）。

## 4. Mock / テスト

- mock の挙動変更は不要（プリアンブルは無視してよい）。既定（similar, aware=0）の既存期待は不変。
- テスト追加:
  - `serve policy: :diverse` が**異なる著者**から最新順・ラウンドロビンで返すこと（3著者×複数 entries で検証、procedure 除外も維持）。
  - `aware: true` で system プロンプトに「半溶解チーム」「唯一の窓」が含まれ、`aware: false` で含まれないこと（プロンプト捕捉 mock）。
  - hetero mock e2e（ks=2, kp=1, serves=[similar,diverse], awares=[0,1]）がクラッシュせず全セルの行を出すこと。
- 既存テスト全 green。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.hetero --adapter mock --seeds 1 --ks 2 --kp 1 --serve similar,diverse --aware 0,1`（4セル表示）

コミットしない。報告に変更ファイルと mock 表。

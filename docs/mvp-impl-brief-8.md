# 実装ブリーフ 8 — Dissolution v2（履歴融合・埋め込み計器・strict 介在判定）

> codex 指示（第8弾）。設計は [`experiment-core.md`](./experiment-core.md) **v2 節（§7〜§10）** を必読。
> 既存 `Tracefield.Dissolution` / Mock / mix task を**改修**する（v1 の挙動は残さなくてよい。ただし既存の他テストは全て green のまま）。
> `mise exec -- mix ...`。ネット無し（ollama/embed 実呼び出しはしない）。コミットしない。

## 1. (a) 履歴融合 — Dissolution.run の文脈構築を変更

ターン生成時の **messages 構築**を regime で切替（純関数 `build_messages(regime, agent, history, published, task, round)` としてテスト可能に）:

- **closed**: `[system: persona＋共通指示X＋JSON指定] ++ 自分の過去ターンのみ assistant メッセージ ++ [user: TASK＋他者の公表懸念(引用)＋ROUND/AGENT]`
- **semi**: `[system: persona＋共通指示X＋"BIAS ANCHOR: あなたの優先軸は{domain}。これを保て"＋JSON指定] ++ 全員の過去ターンを発話順に assistant メッセージとして融合（content 先頭に "[{author}] " を付す） ++ [user: TASK＋ROUND/AGENT]`
- **merged**: semi と同じ融合 assistant 履歴。system は persona 無しで `"TEAM IDENTITY: あなたはチームそのものである。単一の統合見解として続けよ"`＋JSON指定。user 同様。
- closed と semi の**共通指示X は同一文字列**（既存どおり）。
- assistant メッセージの content は各ターンの**生出力（JSON文字列のまま）**でよい（先頭に "[{author}] "）。
- turn 出力プロトコル（TRACEFIELD_DISSOLUTION、{"notes","concerns"}≤2、寛容パース）は不変。

## 2. (b) 埋め込み計器 — `Tracefield.Embed`

behaviour＋2アダプタ（LLM と同パターン）:
- `Tracefield.Embed.Ollama`: `POST http://localhost:11434/api/embed`、body `{model, input: [texts]}` → `embeddings`。既定 model `nomic-embed-text`。
- `Tracefield.Embed.Mock`: **決定的**。`normalize_text` した文字列の char-trigram を 32 次元にハッシュ集計し正規化 → 同一テキスト=cos 1.0、異テキスト≈低。
- `Tracefield.Embed.cosine/2`。

`Dissolution.measure` を埋め込みベースに置換（LLM クラスタリングと TRACEFIELD_DOMAINS は廃止）:
- **coverage**: 全懸念を貪欲 dedup（既出代表と cos ≥ 0.85 なら同一視）→ distinct 数。
- **diversity**: agent 対 (A,B) ごとに `mean_{a∈A} max_{b∈B} cos(a,b)` と逆方向の平均（対称化）→ `1 − それ` を全対平均。agent の懸念が空なら対をスキップ。
- **collapse_rate**: 異 agent 間の懸念ペアのうち cos > 0.9 の割合。
- **bias_retention** は strict 判定の領域対から算出不能なので、**自領域関連度**で代替: agent の懸念と「{domain} に関する懸念」という参照文との cos 平均 …は不安定なので**廃止**してよい（結果 map から除去し、タスク表示も削る）。

## 3. (c) strict 介在判定 — TRACEFIELD_INTERSTITIAL

- dedup 後の代表懸念ごとに judge を呼ぶ（1 run 1 call、番号付き一括）:
  system: `TRACEFIELD_INTERSTITIAL` ＋「各懸念について、taxonomy {security, legal-consent, ux, business-speed, data-quality, ops-org} のうち**2領域の相互作用そのものが主題か**（両領域を同時に考えて初めて成立する懸念か）を判定。単一領域の懸念が他領域に言及しただけなら false。JSONのみ `{"1":{"interstitial":true,"pair":["security","legal-consent"]},...}`」
- **ICC = interstitial=true の dedup 後懸念数**。pair は記録のみ。寛容パース、失敗時 false。
- judge は `judge_model`／`judge_adapter` オプションで explorer と別モデルにできる（既定: explorer と同じ）。

## 4. mix タスク更新

`mix tracefield.dissolution --adapter mock|ollama --seeds 3 --rounds 2 --regimes closed,semi,merged --model gemma4:12b --judge-model gemma4:26b --embed-model nomic-embed-text --temperature 0.4`
- 出力行: regime, seed, icc, coverage, diversity, collapse_rate。集計 mean±sd と H1/H2/H3 判定（H3 は `diversity(merged) < 0.3 かつ coverage(merged) < coverage(closed)` に緩和）。
- runs/ への JSON 保存は従来どおり。

## 5. Mock（自己検証）

- `TRACEFIELD_DISSOLUTION`: regime 検出を新マーカーで（merged=「TEAM IDENTITY」、semi=「BIAS ANCHOR」、それ以外 closed）。応答内容は既存の決定的セット（closed=自領域のみ／semi=自領域＋横断1件／merged=全員同一2件）を再利用。
- `TRACEFIELD_INTERSTITIAL`: 懸念テキスト末尾 `(...)` 内の領域キーワードが **2個以上**なら true＋pair、1個以下なら false（決定的）。
- Embed.Mock は §2 のとおり。
- **期待値（テストで固定）**: closed ICC=0・diversity 高（>0.5）／semi ICC=3・diversity>0／merged diversity=0.0・collapse_rate=1.0・coverage=2 < closed coverage。

## 6. テスト

- `build_messages/6`: closed の assistant 履歴に他者ターンが**含まれない**こと、semi に含まれること（"[BIZ]" 等）、closed/semi の共通指示Xが同一、semi に BIAS ANCHOR があり merged に persona が無く TEAM IDENTITY があること。
- Embed.Mock: 同一テキスト cos=1.0、異テキスト <0.9。cosine の対称性。
- measure: 同一懸念集合→diversity 0.0／素集合→高。dedup（重複2件→coverage 1）。
- mock e2e（3 regime）: §5 の期待値（ICC 順序・merged collapse）。
- 既存テスト全 green。

## 7. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.dissolution --adapter mock --seeds 2`（集計表＋H1/H2/H3。mock 期待値どおり）

Ollama/embed の実呼び出しはしない。コミットしない。報告に変更ファイルと mock 集計表を含める。

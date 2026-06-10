# 実装ブリーフ 9 — Reference store ＋ Agent facade（Jido 試験採用）＋ 状態軸用量反応

> codex 指示（第9弾）。設計は [`design-reference.md`](./design-reference.md) **v2（§9-14）** と [`design-agent.md`](./design-agent.md)（特に §5, §8）を必読。
> 依存 `{:jido, "~> 2.3"}` は **mix.exs 追加・取得済み**（`deps/jido/` にソースあり。API はそこを直接読んで確認せよ。`deps.get` 不要・ネット無し）。
> `mise exec -- mix ...`。ollama/実 embed は呼ばない。コミットしない。

## 1. `Tracefield.Reference` — 共有状態ストア（GenServer・本命の中核）

```
Entry: %{id: "e1", type: :belief|:hypothesis|:observation|:stance|:decision|:question|:chunk,
         author, version: 1, status: :active|:retracted|:superseded,
         text, citations: [entry ids], embedding: [float], meta: %{}}
```
API（全て GenServer 呼び出し、名前付きプロセス可）:
- `start_link(opts)`: 任意の初期 entries（embedding は内部で計算）。`embed_adapter/embed_model` を opts で受ける（既定 Embed.Mock）。
- `absorb(ref, entries, author)`: id/version 採番、embedding 計算（`Tracefield.Embed`）、格納。返り値は採番済み entries。
- `serve(ref, query_text, opts)`: `k`（件数）と `exclude_author`（自分以外＝他者状態の取得）/`only_author` を受け、**query の embedding と cosine 上位 k** の active entries を返す。
- `retract(ref, id)`: status→:retracted にし、**citations を逆向きに辿った推移閉包**（その entry に依拠した active 下流 entries）を返す（＝隔離候補。Path E 閉包の状態版）。
- `get(ref, id)` / `all(ref)`。
- 純粋ヘルパ `closure(entries, id)` は公開関数にして単体テスト可能に。

## 2. `Tracefield.Agent` — 薄い facade（Jido 試験採用）

- **Jido core を試す**: `use Jido.Agent`（`deps/jido/lib/jido/agent.ex` の `new/1, set/2, cmd/2-3` を確認）で
  agent 構造体に {id, domain, desc, anchor, k_s} を schema 付き state として持たせ、ターン処理を Action（または cmd 経由）で表現する。
- **ただし外部 API は facade に固定**（Jido 都合を漏らさない）:
  ```
  Tracefield.Agent.new(id, domain, desc, opts)            # opts: k_s, adapter, model, temperature, seed
  Tracefield.Agent.run_turn(agent, reference, round)      # → {updated_agent, absorbed_entries}
  ```
  `run_turn` = perceive（`Reference.serve(query=task＋自分のdomain, k: k_s, exclude_author: 自分)`）
  → deliberate（`Tracefield.LLM.complete`、protocol キー `TRACEFIELD_AGENT_TURN`。取得 entries を id 付きで提示し、
  出力 JSON `{"entries":[{"type":"belief","text":"...","citations":["e3"]}]}`（≤2件・citations は提示 id のみ有効・寛容パース））
  → absorb（`Reference.absorb`）。
- **タイムボックス**: Jido の API が schema/cmd で素直に書けないと判断したら、**素の struct/GenServer に fallback してよい**
  （その場合レポートに「fallback した・理由」を明記）。facade シグネチャは不変のこと。

## 3. 用量反応実験 `mix tracefield.doseresponse`

`--adapter mock|ollama --seeds 2 --rounds 2 --ks 0,2,6 --model M --judge-model J --embed-model E --temperature 0.4`
- 各 k_s ∈ ks、各 seed: 新しい Reference（task チャンクを :chunk として種入れ）＋ agents SEC/BIZ/UX（既定 domain/desc は Dissolution と同じ）。
  rounds ラウンド、各ラウンド全 agent が `run_turn`。
- 測定（**Dissolution v2 の計器を再利用**。belief 等の absorbed entries の text を「懸念」として扱う）:
  coverage（dedup τ0.85）/ diversity（1−sym-mean-max-cos）/ collapse_rate / **ICC**（TRACEFIELD_INTERSTITIAL・judge_model 対応）。
  可能なら `Dissolution.measure` を関数抽出して共用（重複実装しない）。
- 出力: 行（k, seed, icc, coverage, diversity, collapse_rate）＋ k ごと mean±sd ＋ **傾向行**（ICC が k に対して単調増か等）。
  runs/ に JSON 保存。
- **統治スモーク**（同タスク内 or テストで）: k=2 の1 run 後、最初に absorb された entry を `retract` → 閉包が非空で、
  閉包内 entries が全てそれに（推移的に）依拠していることを表示/検証。

## 4. Mock（自己検証）

- `TRACEFIELD_AGENT_TURN` 応答（決定的・prompt から agent id / round / 提示された他者 entry id&text を読む）:
  - **取得 entries なし（k=0 相当）**: 自領域懸念2件（既存 Dissolution closed セット再利用可、末尾 `(domain)` 規約維持）、citations=[]。
  - **取得 entries あり**: 自領域1件（citations=[]）＋ **横断1件**（取得した他者 entry の先頭 id を citation に持ち、
    テキスト末尾 `(own-domain other-domain)` の2キーワード規約で interstitial mock が true になる）。
- これにより期待値: **ICC は k=0 で 0、k>0 で 3**（agent×横断1件×dedup）。diversity は k によらず >0（自領域は別々）。
  retract スモーク: 横断 entry は引用先 entry の閉包に入る。
- Embed.Mock / TRACEFIELD_INTERSTITIAL mock は既存を再利用。

## 5. テスト

- Reference: absorb の採番/embedding 付与、serve の k/exclude_author/cosine 順、retract の閉包（多段: e1←e2←e3 で retract(e1) ⊇ {e2,e3}）、superseded/retracted は serve から除外。
- Agent facade: run_turn が perceive→deliberate→absorb を行い citations が提示 id に限定されること（mock）。
- doseresponse mock e2e（seeds=1, ks=0,2）: **ICC(k=2) > ICC(k=0)=0**、diversity>0、retract 閉包スモーク。
- 既存テスト全 green。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.doseresponse --adapter mock --seeds 2 --ks 0,2,6`（k ごと集計＋傾向行＋retract スモーク）

Jido を使ったか fallback したかを必ず報告。コミットしない。

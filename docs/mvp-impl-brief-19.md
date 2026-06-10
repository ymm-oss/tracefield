# 実装ブリーフ 19 — 有機的接続の最小形（メタ場 / 撤回の自動伝播 / 常駐 Field）

> codex 指示（第19弾）。設計は [`design-cluster.md`](./design-cluster.md) §3-§4。前提: brief-18 まで（70 tests）。
> 目的: クラスタ接続を「手動 bridge」から「**発見は pull・撤回は自動伝播**」へ。複数クラスタが**同時に生き**て繋がる最小形。
> `mise exec -- mix ...`。ネット無し。コミットしない。
> **スコープ外**（明記）: クラスタの自動生成・Jido AgentServer 全面採用・ノード越え分散。

## 1. 撤回イベントの購読（Reference）

- `Reference.subscribe(ref, pid)`: 購読登録（state に subscriber pids、DOWN 監視で自動除去）。
- retract / quarantine / propagate_retractions で status が変わるたび、各 subscriber に
  `{:tracefield_status, %{store: self(), id: id, status: status, entry: plain_entry}}` を send。

## 2. 自動伝播リンク `Tracefield.Bridge.Link`

GenServer: `start_link(source: refA, target: refB, source_name: "A", name: 任意)`
- 起動時に source を subscribe。
- `{:tracefield_status, %{status: s}}` 受信時（s が retracted/superseded）→
  `Reference.propagate_retractions(target, source_name, [entry])` を実行。
- 結果（伝播した写し・隔離数）を Logger でなく **送信元に蓄積**: `Link.history(link)` で
  `[%{source_id, copy_id, quarantined: n}]` を取得可能に（テスト/デモ用）。

## 3. 多段 provenance（import の小修正）

`Reference.import` で、輸入元 entry の meta に既に `source_cluster/source_id` がある場合、
それを `meta.source_chain`（リスト、古い順）へ push してから新しい hop の `source_cluster/source_id` を設定する。
→ A→META→B の写しでも原本への鎖が残る。**撤回の多段伝播は hop ごとの Link で自然に流れる**（A→META の Link と META→B の Link）。

## 4. メタ場 `Tracefield.Meta`

- `publish(meta_ref, cluster_name, source_ref, opts)`: source の代表 entries を選んで export→import(meta, ..., cluster_name)。
  選択: `ids:` 明示 or 既定 = **active な非 chunk/非 procedure を被引用数降順・同数なら新しい順に `limit:`（既定5）件**。
  返り値: meta 内の写し。
- `discover(meta_ref, query_text, opts)`: meta を `serve`（:similar、k 既定3、`exclude_cluster:` で自クラスタ由来を除外
  ＝ author prefix "name/" で判定）→ `[%{entry, source_cluster, source_id}]`。
- `pull(target_ref, meta_ref, entry_ids)`: meta の該当 entries を export→import(target, ..., "META")（§3 の chain が効く）。

## 5. 常駐 Field `Tracefield.Field`

Supervisor: `start_link(clusters: [%{name: "A", persist_path: p}|...], meta: meta_path, links: :auto | [...])`
- 各クラスタの Reference と メタ場 Reference を子として起動（`via` 名 or pid map を `Field.refs(field)` で取得）。
- `links: :auto` のとき、**各クラスタ→META** と **META→各クラスタ** の Link を全て張る
  （A の撤回が META 経由で B まで自動で流れる）。

## 6. デモ `mix tracefield.field --demo`

tmp stores で自己完結ストーリーを表示:
1. Field 起動（クラスタ A・B ＋ META、links: :auto）── 「同時に生きている」ことを示す（pid 列挙）
2. A: 知見 a1 を absorb → `Meta.publish(A)` → カタログ化
3. B: 問い（a1 と語彙が重なる query）で `Meta.discover` → **a1 の写しを発見**（source=A 表示）→ `Meta.pull` で B へ
4. B: 写しを citation して判断 b1 を absorb
5. A: a1 を retract → **手を触れず** Link が META→B まで自動伝播 → B の写し retracted・b1 隔離
   （伝播完了は Link.history のポーリングで確認してから表示）
6. B store の最終状態と、写しの `source_chain`（A→META→B）を表示

## 7. テスト

- subscribe: retract で購読 pid にイベントが届く。quarantine でも届く。
- Link: source retract → target の写しが（ポーリング待ちで）retracted・閉包 superseded、history に記録。
- import chain: A→META→B で `meta.source_chain == [A の hop]`、最終 hop が META。冪等は最終 hop キーで維持。
- Meta.publish 既定選択（被引用数降順 limit）と ids 明示。discover が embedding 類似で当たり、exclude_cluster が効く。pull で B に写し。
- Field: :auto links で A retract → B まで多段自動伝播（メタ経由）。
- demo smoke（CaptureIO で 6 ステップと source_chain 表示）。
- 既存 70 tests green。

## 8. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.field --demo`

コミットしない。報告に変更ファイルと demo 出力。

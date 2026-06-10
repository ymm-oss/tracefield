# 実装ブリーフ 18 — クラスタ間接続（export / import / 撤回の越境）

> codex 指示（第18弾）。設計は [`design-cluster.md`](./design-cluster.md) §3・§6 を必読。前提: brief-17 まで（65 tests）。
> `mise exec -- mix ...`。ネット無し。コミットしない。

## 1. `Reference.export(ref, ids)`

指定 id の entries を**輸送可能な plain map のリスト**で返す（id/type/author/version/status/text/citations/embedding/meta）。
存在しない id は無視。

## 2. `Reference.import(ref, exported, source_cluster)`

輸出 entries を**写し**として取り込む:
- **冪等**: `meta.source_cluster + meta.source_id` が一致する既存写しがあればそれを返す（重複させない）。
- 写しの構成: `author = "#{source_cluster}/#{元author}"`（ローカル agent 名との衝突回避＋出所の可視化）、
  `meta` に `%{source_cluster: source, source_id: 元id}` をマージ、`embedding` は輸出値を再利用（再埋め込みしない）、
  status は輸出時の status を引き継ぐ。
- **citations の再マップ**: 同一バッチ内で輸入される entry への引用は**写しの新 id に再マップ**。
  バッチ外への引用は citations から外し、`meta.unresolved_citations` に元 id を記録（provenance は失わない）。
- persist_path 有効時は通常どおり absorb 行が追記される（復元で写しが再現）。

## 3. 撤回の越境 `Reference.propagate_retractions(ref, source_cluster, source_entries)`

`source_entries`（source 側の export 全量 or 部分）を受け取り:
- source 側 status が retracted/superseded で、**ローカル写し**（source_cluster+source_id 一致）が active なものについて:
  1. 写しを `retract`（closure 取得）→ closure を `quarantine`（既存機構の再利用）。
- 返り値: `[%{copy: entry, source_id, closure: [entries]}]`。該当なしなら []。
- persist にも status 行が載ること（復元後も越境撤回が保持される）。

## 4. mix タスク `tracefield.bridge`

- `mix tracefield.bridge --from-store A.jsonl --to-store B.jsonl --source-name A --export e3,e5`
  → A を persist_path で開き export → B を開き import。結果（写し id・再マップ・unresolved）を表示。
- `--sync`: 同じ from/to 指定で propagate_retractions を実行し、`越境撤回: <source_id> → 写し <id> を撤回、依存 N 件隔離` を表示。
- `--demo`: tmp に2つの store を作り、**自己完結ストーリー**を実演して表示:
  1. クラスタA: 知見 a1「省エネ優遇は実測データで担保できる(evidence)」を absorb
  2. bridge: a1 を B へ輸出入（写し b-copy）
  3. クラスタB: 判断 b1「優遇ローン商品を設計する」を **b-copy を citation** して absorb
  4. クラスタA: a1 を retract（「実測データに誤りが判明」）
  5. `--sync` 相当: B で写しが retract → **b1 が閉包隔離**
  各ステップを print（最後に B の store 状態を表示）。

## 5. テスト

- export/import: 写しの author 合成・meta（source_cluster/source_id）・embedding 再利用・status 引き継ぎ・**冪等再輸入**。
- citation 再マップ: バッチ内→新 id、バッチ外→`meta.unresolved_citations` に記録され citations から除外。
- 越境撤回: §4 の demo ストーリーを API レベルで再現（A retract → propagate → B の写し retracted → B の依存判断が superseded）。
- 永続往復: persist_path 付き2 store で import → 再起動 → 写し・status が復元され、復元後の propagate も機能。
- `tracefield.bridge --demo` がストーリーを出力する smoke。
- 既存 65 tests green。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.bridge --demo`（5ステップのストーリーと越境隔離が表示される）

コミットしない。報告に変更ファイルと demo 出力。

# 実装ブリーフ 22 — メモリ失効フィルタ ＋ 転籍（経験蒸留つき）

> codex 指示（第22弾）。設計は [`design-cluster.md`](./design-cluster.md) §3-4（転籍）。前提: brief-21 まで（89 tests）。
> `mise exec -- mix ...`。ネット無し。コミットしない。

## 1. メモリ失効フィルタ（既存の統治穴の最小修復）

私的メモリは store の撤回機構の外にある。**store 有効時のみ**修復:
- ideate の memory 読み込み時、各メモリ行の `citations` を store で照合:
  **store に存在し status ≠ :active な entry を引用している行は注入しない**（失効）。
  id が store に無い行は保持（判定不能＝store 無し run 由来）。
- ヘッダ表示を `memory=4件` → `memory=4件（失効1除外）`（除外0なら従来表記）。
- config の agents に `memory_stale` 数を追加。
- ファイルは書き換えない（読み込み時フィルタのみ・決定的）。

## 2. `Tracefield.Transfer`

`move(from_dir, to_dir, agent_id, opts)`（policy: `:distill`（既定）| `:fresh` | `:full`）:

1. **検証**: from の agents.json に agent_id が存在・to に同 id が**不在**（あれば `{:error, :already_exists}`）。
2. **資産の原則**: 私的文書＝クラスタ資産（**移動しない**）。メモリ・手続きファイル・model＝エージェント資産（移動）。
3. **メモリ処理**（from の `memory/<ID>.jsonl`、無ければ空扱い）:
   - 共通: from に store.jsonl があれば §1 と同じ失効フィルタを適用してから処理（撤回済み知見由来の経験は持ち出さない）。
   - `:distill`: 有効行の**直近 `limit:`（既定5）件**から経験サマリを生成
     `"経験サマリ（<ID>, <from名> より転籍）:\n- <text>…"`（各120字切り）。
     これを **to の store（無ければ作成: `<to>/store.jsonl`）に absorb**
     （type :observation、author `"TRANSFER/<ID>"`、meta %{transfer_from: from名, agent: ID}）。
     さらに **to の `private/<id>-experience.md`** に同内容を書き、転籍後 spec の `private_doc` に設定。
     to 側メモリは**空から**。
   - `:fresh`: 何も持ち出さない。private_doc はプレースホルダ `private/<id>-fresh.md`（「新任。私的知見はこれから蓄積」）。
   - `:full`: メモリ jsonl を to の memory/ へ**そのままコピー**（実行時に機密注意を1行表示）。private_doc はプレースホルダ。
4. **agents.json 更新**: from から削除・to へ追加（`procedure` ファイルがあれば to へコピーし参照維持、`model` 維持）。
5. **異動 provenance**: from に store.jsonl があれば「AGENT <ID> が <to名> へ転籍（policy）」(type :observation, author "TRANSFER")
   を absorb。to の store には :distill の経験サマリ（または :fresh/:full でも転入記録1行）。
6. 返り値: `%{policy, summary_entry: entry|nil, stale_excluded: n, files: [...]}`。from名/to名 = ディレクトリ basename。

## 3. mix タスク `tracefield.transfer`

- `--from <dir> --to <dir> --agent <ID> --policy distill|fresh|full`（結果表示）。
- `--demo`: tmp に A/B シナリオ最小構成を作って自己完結:
  A の agent X にメモリ4行（うち1行は A store の撤回済み entry を引用＝**失効**）→
  `move(policy: :distill)` → 表示: 失効1除外・経験サマリ（3件分）が B store に provenance 付きで入った・
  B agents.json に X（private_doc=experience）・A から X が消え転出記録 ── を順に print。

## 4. テスト

- 失効フィルタ: 撤回済み citation 行が注入されない・ヘッダ/config に stale 数・id 不明行は保持・store 無効時は従来挙動。
- transfer :distill: B agents.json/store/experience ファイル/A 転出記録/B メモリ空/失効行がサマリに入らない。
- :fresh / :full の各挙動。:full のコピー同一性。
- エラー: agent 不在・to に同 id 既存。
- 手続きファイルのコピーと参照維持、model 維持、**私的文書が移動していない**こと。
- demo smoke。既存 89 tests green。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.transfer --demo`

コミットしない。報告に変更ファイルと demo 出力。

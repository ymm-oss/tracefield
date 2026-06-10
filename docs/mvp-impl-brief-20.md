# 実装ブリーフ 20 — 析出 v1（Genesis）＋ 文化伝達計器（Culture）

> codex 指示（第20弾）。設計は [`design-genesis.md`](./design-genesis.md) §2-§6 と [`design-cluster.md`](./design-cluster.md) §8。
> 前提: brief-19 まで（76 tests）。`mise exec -- mix ...`。ネット無し。コミットしない。
> v1 方針: **検出・提案・足場づくりは決定的（LLM 不使用）**。task.md の LLM 起草は将来。

## 1. `Tracefield.Genesis`

- `detect(meta_ref, charters, opts)`:
  - charters: `[%{name: "A", text: charter本文}]`（embedding は内部で `Tracefield.Embed` により計算。embed_adapter/embed_model opts）。
  - META の active な 非 chunk/非 procedure entries を取得し、embedding **貪欲グループ化**（`tau_genesis:` 既定 0.7、
    代表との cos ≥ τ で同группе、dedup と同じ方式）。
  - attractor 判定: 成員数 ≥ `min_size:`（既定 4）/ distinct source_cluster 数 ≥ 2（meta の source_cluster）/
    **無主性**: 成員重心（平均→正規化）と全 charter の cos がすべて < `tau_claim:`（既定 0.75）。
  - 返り値: `[%{members: [entries], source_clusters: [..], max_charter_sim: float, charter_best: name}]`。
- `propose(meta_ref, attractor)`: META に `:genesis` entry を absorb
  （author "GENESIS"、text = `"析出提案: <source_clusters>由来の<件数>件 — <先頭成員text先頭60字>…"`、
  **citations = 成員 id 全部**＝出生証明）。返り値: genesis entry。
  - `Reference` の `@types` に `:genesis` を追加（restore 経路も自然に対応すること）。
- `scaffold(meta_ref, genesis_id, dir, opts)`: genesis entry と被引用成員を読み、シナリオディレクトリを生成:
  - `task.md`: 決定的テンプレート（使命文＋「背景となった知見」として成員 text を箇条書き）。
  - `agents.json`: **由来クラスタごとに1レンズ**（id=`"<CLUSTER>_LENS"`、domain=`"<cluster>-perspective"`、
    desc テンプレ、private_doc=`"<cluster>.md"`）＋ 汎用 `"GENERAL"`（private_doc=general.md）。
  - `private/<cluster>.md`: **その由来クラスタ発の成員 entries の text** を箇条書き（=出生時から本物の情報の偏り）。
    general.md は全成員の要約箇条書き。
  - `procedure.md`: 既定の生成手続きテンプレ。
  - `store.jsonl`: `Meta.pull` 相当で成員を新 store に import（source_chain 維持）。persist_path で作る。
  - 返り値: `%{dir, files: [..], seeded: n}`。

## 2. `Tracefield.Culture`（垂直伝達の計器）

- `transmission(ref_or_entries, charter_text, opts)`:
  - 対象 = active な belief/decision 等（非 chunk/非 procedure/非 genesis）。
  - **alignment** = 各 entry embedding と charter embedding の cos の平均（`per_author:` 著者別平均も返す）。
  - **member_diversity** = 既存 Dissolution の手法と同じ「著者間 1−sym-mean-max-cos」（authors<2 なら 0.0）。
  - 返り値 `%{alignment, per_author: %{author => align}, member_diversity, n}`。
  - charter embedding は opts の embed_adapter/embed_model で計算（entries は保存 embedding を再利用）。

## 3. mix タスク `tracefield.genesis`

- `--meta <store.jsonl> --charter NAME=path.md`（複数可）`--detect`: attractor 一覧（成員数・由来・max_charter_sim）。
- `--propose <index>`: detect 後その attractor を propose（genesis id 表示）。detect と同一オプションで再現できること。
- `--scaffold <genesis-id> --dir <path>`: 足場生成（作成ファイル一覧表示）。
- `--demo`: tmp で自己完結:
  1. META store を作り、**2クラスタ由来の関連 entries 5件**（共通語彙で attractor を形成）＋**既存 charter に近い群**＋**ノイズ**を仕込む
  2. `detect`（charter 1つ渡す）→ attractor 1件のみ検出（claimed 群とノイズが弾かれることを表示）
  3. `propose` → 出生証明（citations）表示
  4. `scaffold` → 生成ファイルツリーと task.md 先頭・agents.json を表示
  5. 新 store に各レンズ author で belief を2件ずつ absorb（charter 語彙を共有するもの/しないもの混在）→
     `Culture.transmission` を表示（alignment・per_author・member_diversity）＝**垂直伝達の計器が動く**ことを示す

## 4. テスト

- detect: attractor 検出（共通語彙群）。単一クラスタ由来の密集群は**横断性で除外**。charter に近い群は**無主性で除外**。min_size 未満除外。
- propose: `:genesis` entry が成員全 citation 付きで META に入る。
- scaffold: ファイル群生成・agents.json のレンズが由来クラスタ別・private/<cluster>.md にそのクラスタ発 text・store.jsonl が source_chain 付きで種入れ。
- Culture.transmission: charter 語彙を共有する entries → alignment 高 / 無関係 → 低（Mock embedding の決定的性質を利用）、著者2名で member_diversity > 0、per_author が返る。
- genesis --demo smoke（CaptureIO: 検出1件・除外理由・出生証明・ファイルツリー・transmission 表示）。
- 既存 76 tests green。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.genesis --demo`

コミットしない。報告に変更ファイルと demo 出力。

# 実装ブリーフ 2 — claim 正規化層の再設計（意味的クラスタリング）

> codex への実装指示（第2弾）。背景は [`mvp.md`](./mvp.md) と [`design-review.md`](./design-review.md) DR-2/DR-10。
> 第1弾実装（既存コード）を踏まえた**正規化/照合層の置換**。`mise exec -- mix ...` で全コマンド実行。

## 0. なぜ作り直すか（現状の不具合）

実 `gemma4:12b` での Phase 1 実行で判明:
- synthesis が **散文**を出し、`Normalize.extract_claims` のフォールバックが**全行を claim 化**（見出し・空行・全文スラグが id 化）。
- `Normalize.match/2` は**意味的照合をしておらず**、スラグ完全一致のみ。→ run 間で id がほぼ一致せず within 距離=1.0、AUC<0.5。
- `reconstruct_affected` の id 空間が claim と異なり、system 集合が空 → proxy=0。

**方針（採用済み）**: claim に run 横断の同一性を **意味的クラスタリング**で与える。固定タクソノミーは使わない（創発を潰さないため）。

## 1. 変更後のパイプライン（GroundTruth に集約）

`Explore.run/2` は **raw_output と transcript のみ**返す（内部の reconstruct と system_claimed_affected は削除）。
正規化・再構成・クラスタリングは **GroundTruth に集約**する。

GroundTruth で各 run について:
1. **抽出** `Normalize.extract_claims/2` → `[%Claim{id, text, kind, raw_index}]`（id は run 内ローカル, 例 `"c1"`)。
2. **再構成** `reconstruct/3`（汚染依存の**ローカル claim id 集合**）。

全 run（A+B）を横断して:
3. **クラスタリング** `Normalize.cluster/2` → `{ref => cluster_id}`（ref = `"<run_key>|<local_id>"`）。
4. 各 run の **cluster 集合** = その run の claim を cluster_id へ写像した MapSet。
5. within/between 距離は **cluster 集合**上の Jaccard 距離 `diff`。
6. **接地集合** = `freq_A(cluster) - freq_B(cluster) >= threshold` を満たす cluster。
7. **system_claimed_affected** = 各 run の reconstruct ローカル id を cluster_id へ写像し union。
8. メトリクス（AUC/Cliff's δ/PRF）は従来通り cluster 集合・cluster id 集合に対して算出。

## 2. モジュール契約

### 2.1 `Normalize.extract_claims(raw_output, llm_opts) :: [%Claim{}]`
- **fast path**: raw_output に `CLAIM[id] kind: text` 行があればそれをパース（LLM 呼び出し無し。Mock 用）。
- 無ければ **LLM 抽出**（system キー `TRACEFIELD_EXTRACT_CLAIMS`）: 「原子的な懸念/推奨のみを **JSON 配列** `[{ "text": ..., "kind": "concern|recommendation|final" }]` で返す。見出し・空・前置きを含めない」。
- パース・検証: JSON 配列であること、`text` 非空、`kind` が3種のいずれか。**不正・空・見出し風は捨てる**。
- ローカル id を採番（`"c1","c2",...`）。`raw_index` も付与。
- **失敗時は `[]`**（行分割で garbage を作らない。現状フォールバックは撤去）。

### 2.2 `Normalize.cluster(claim_refs, llm_opts) :: %{String.t() => String.t()}`  ← 新規
- 入力: `[%{ref: String.t(), text: String.t()}]`（全 run の claim をプール）。
- **LLM 1 回**（system キー `TRACEFIELD_CLUSTER`）: 番号付き claim 一覧を渡し、「意味的に等価な claim が同じラベルになるよう、各番号に短い kebab ラベルを割り当て、**JSON 配列**（index 順のラベル文字列）で返す」。
- 返り値: `ref => cluster_id` の map。
- **フォールバック**（LLM 失敗/不正）: 各 claim を独立クラスタに（`cluster_id = normalize_text(text)`）。
- 大量でも 1 プロンプトで可（MVP 規模）。

### 2.3 `reconstruct(run, claims, llm_opts) :: MapSet.t()`（ローカル id 集合）
- GroundTruth or Explore 内のヘルパ。run の transcript/raw_output + **番号付き claims** + 汚染Aの説明を渡し、
  「汚染A（包括同意の主張）に依存する claim の**番号（index）**だけを JSON 配列で返す」。
- 返り値はその run の**ローカル claim id 集合**。GroundTruth が後で cluster_id へ写像。

### 2.4 `Normalize.diff(set_a, set_b) :: float()`
- 既存どおり cluster_id 集合上の `1 - Jaccard`。

## 3. Mock（Phase 0 自己検証を維持）

Mock は次のプロトコルキーに決定的応答を返すこと:
- **review 生成**（既存）: base + seed ノイズ + 汚染なら signal claim 群 / 訂正・無印なら risk claim。CLAIM 行形式。
- `TRACEFIELD_EXTRACT_CLAIMS`: 渡された CLAIM 行をそのまま JSON 配列化（fast path が効くので実際は呼ばれない想定だが実装する）。
- `TRACEFIELD_RECONSTRUCT_AFFECTED`: その run の claims のうち **signal claim のローカル id（index）** を返す。
- `TRACEFIELD_CLUSTER`: **各 claim の cluster ラベル = その CLAIM id（正規 id）** を返す（同一正規 id は同一クラスタ＝run 横断で一致）。

→ これにより: signal クラスタは A で高頻度・B で低頻度 → 接地集合=signal、system 集合=signal → **recall=precision=1.0、within<between、AUC 高** を維持。

## 4. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コードに警告なし）
2. `mise exec -- mix test`（緑）。既存テストを新契約に合わせて更新:
   - `normalize_test`: diff 0/0.5/1.0（cluster 集合ベース）。`cluster` の決定的フォールバックも 1 件テスト。
   - `metrics_test`: 既存どおり。
   - `ground_truth_mock_test`: between平均>within平均、AUC>0.8、接地集合==mock signal クラスタ、proxy recall==1.0。
   - `scenario_test`: 既存どおり。
3. `mise exec -- mix tracefield.phase0`（within<between、AUC高、接地=signal、proxy 1.0）。
4. `mise exec -- mix tracefield.phase1 --adapter mock --n 8`（同上、recall=precision=1.0）。

**Ollama は実行しない**（ネット無し）。アダプタは現状のまま（`think:false`/`num_predict` 済）。オーケストレータが実機検証する。

## 5. 制約
- `docs/` は本ブリーフ以外編集しない。`runs/` は触らない。`mix deps.get` 不要（deps 取得済・ネット無し）。
- コミットしない（オーケストレータがレビュー後にコミット）。
- 既存の公開関数で外から使うもの（mix tasks 経由）が壊れないこと。`GroundTruth.to_plain/1` は新フィールド（claims/clusters）も JSON 化できるよう拡張。

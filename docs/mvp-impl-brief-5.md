# 実装ブリーフ 5 — 真の in-process 来歴（C5）と C4 比較

> codex 指示（第5弾）。前提: 既存コード（brief 1-4 実装済）。`mise exec -- mix ...`。ネット無し（ollama 実行しない）。コミットしない。
> 目的: 探索の**最中に**依存を記録する provenance DAG を作り（事後再構成でない）、汚染の transitive な影響/隔離集合を
> その DAG から得る（=C5）。C4（事後再構成）と同一データで比較できるようにする。

## 1. 探索中の依存宣言（Explore）

`Tracefield.Explore` を拡張: 各エージェントのターンで、貢献を**点（point）**の集合として出させ、各点に依存を付ける。
- 各 explorer ターンのプロンプトを変更し、出力を JSON で:
  `{"points":[{"text":"...","depends_on_turns":[<これまでのturn番号>],"uses_injection":true|false}, ...]}`
  - `uses_injection`: その点が注入された stakeholder 注記（汚染/訂正）に依拠するか。
  - `depends_on_turns`: その点が前提とする、これまでの transcript の turn 番号（無ければ []）。
- transcript の各 turn に安定な整数 `turn_id` を付与（注入ターンにも付与）。各点は `point_id`（"t<turn>.p<n>"）。
- パース失敗時は従来どおりプレーンな貢献テキストとして格納し、provenance は空（後方互換）。
- synthesis は従来どおり最終レビューを出す（変更不要）。

## 2. provenance DAG と C5 影響/隔離集合

`Tracefield.Provenance`（新規）:
- 全 run の点ノード＋辺（point→依存先 turn の点 / 注入ノード）から DAG を構築。
- 注入ノード（汚染）を起点に **transitive closure** を計算 → `c5_affected_points`（汚染に直接/間接依存する点集合）。
- 同様に **撤回シミュレーション**: 注入ノードを撤回 → closure が `c5_quarantine`（隔離すべき点）。

## 3. C4（事後再構成・既存路線）

既存の reconstruct を「点」粒度でも使えるよう薄く一般化（全 transcript + 注記 + 点一覧 → 注記依存の点番号）。
これが `c4_affected_points`。

## 4. 比較指標（measure に追加 or 新タスク）

`GroundTruth.measure`（または新タスク `tracefield.provenance`）で、同一 run 集合に対し:
- `c5_affected_points` と `c4_affected_points` を出す。
- 接地が無い実データでは「両者の差分」を提示（C5∖C4 = C4が逃した間接依存点）。
- Mock では既知の連鎖を仕込み、**C5 recall ≥ C4 recall** を test で固定（§6f を点粒度で再現）。

## 5. Mock（Phase 0 自己検証 + 連鎖）

Mock の explorer 応答が `points` JSON を返すようにし、**既知の依存連鎖**を含める:
- 注入（汚染）あり時、点 X(uses_injection=true) → 点 Y(depends_on=X, uses_injection=false) → 点 Z(depends_on=Y) の連鎖を決定的に生成。
- これにより C5(closure)= {X,Y,Z}、C4(事後)= {X}（注記を言及しない Y,Z を取り逃す）を Mock で再現し、
  **test: c5_affected ⊋ c4_affected かつ {Y,Z} ⊂ (c5∖c4)** を固定。
- 既存の Phase 0/1（affected/proxy）テストは壊さない（provenance はadd-on)。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`（緑。新規 provenance/連鎖テスト含む）
3. `mise exec -- mix tracefield.phase0`（従来どおり）
4. provenance 比較を示す出力（mock）: c5_affected と c4_affected、c5∖c4 に間接依存点が含まれること。

Ollama は実行しない。コミットしない。報告に変更ファイルと mock 比較結果（c5 vs c4 の点集合）を含める。

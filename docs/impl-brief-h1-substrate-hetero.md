# 実装ブリーフ H1 — 基盤異質性（substrate heterogeneity）の用量反応

> 仮説 H1。攻めの便益(genuine 横断発見)は、契約の自覚(aware)＋多様 serve だけでなく、
> **エージェントの基盤異質性（異なるモデル）** の関数として増えるか。
> 由来: [`experiment-results.md`](./experiment-results.md) §11/§12 が「便益には基盤の異質性が要る ── 異なるモデル/ツール/データアクセス」を
> **「次の決定的実験」と名指し**したまま未実行。全実験は同一モデル(gemma4:12b)＝**理論の中心変数が一度も変化していない**。

## 1. 仮説と棄却基準

- **H1（主張）**: 解錠 regime（`serve:diverse` ＋ `aware:1` ＋ `kp:1`、`hetero:grounded`）の下で、
  3エージェントを **異種モデル混成**（12b×26b）にすると、同一モデル群より `disc_strict`（決定的・植え込み相互作用の発見数）が高い。
  相手の外部化状態に「自分のエコー」でなく**自分の基盤では計算されないもの**が入るため。
- **交絡対策（必須・3 arm）**: 「異種」と「片方が強い」を分離するため必ず3条件:
  | arm | SEC | BIZ | UX | 役割 |
  | --- | --- | --- | --- | --- |
  | `homo12b` | 12b | 12b | 12b | 弱い側の同質ベースライン（§14 既知＝~2.0/3） |
  | `homo26b` | 26b | 26b | 26b | **強い器官の上側統制** |
  | `hetero` | 12b | 26b | 12b | 異種混成（本命） |
- **支持**: `hetero > max(homo12b, homo26b)`（特に homo26b を上回る）→ 真の異質性効果（超加法）。
- **棄却**: `homo12b ≤ hetero ≤ homo26b`（単なるモデル強度の内挿）または `hetero ≤ homo12b` →
  異質性は仕事をしておらず、攻めの便益は「情報＋自覚＋器官強度」のみ。**テーゼを強く限定する陰性結果も価値**。
- theater 監視: `diversity` / `collapse_rate`（決定的・埋め込み）。発見増が surface 多様性のトレードでないことを確認
  （[`findings-contrastive-serve.md`](./findings-contrastive-serve.md) の theater 検出と同じ規律）。

## 2. なぜ今これか

- §11 の負の用量反応（k_s↑＝均質化ダイヤル）の機構説明は「**同一モデルは重みレベルで既に完全溶解、ペルソナは薄膜**」。
  この説明が正しければ、**基盤を実際に変えた時にだけ**共有が合成を生むはず ── それを直接テストするのが H1。
- 最安・最短（下記のとおり**単一ファイル ~40-60 LOC**）。Agent 層は per-agent model を既に完全サポート。

## 3. コード変更（正確な touch-point）

**結論: 配線は1ファイル `lib/mix/tasks/tracefield.hetero.ex` に閉じる。** Agent 層は変更不要。

既に効いている下地（変更不要・確認のみ）:
- `lib/tracefield/agent.ex:27` Core schema に `model`。
- `lib/tracefield/agent.ex:262` `deliberate/3` が `state.model` を LLM に渡す。
- `lib/tracefield/agent.ex:666` `Agent.new/4` が `model:` opt を受ける。
- → **per-agent モデルは Agent 層で完全サポート済み**。律速は hetero タスクが単一 `model` を broadcast している点だけ（`tracefield.hetero.ex:181`）。

変更（すべて `tracefield.hetero.ex`）:

1. **substrate 次元を追加**。`run_experiment/1` の内包表記（現 62-86 行）に `substrate <- substrates` を追加。
   `substrates` は `[{name, model_map}]`、`model_map = %{"SEC"=>m, "BIZ"=>m, "UX"=>m}`。
2. **`run_one/2` で per-agent model を割当**。現 176-192 行の agents 構築で
   `model: model` → `model: Map.get(substrate_models, agent.id, model)`。
   substrate_models は opts 経由で渡す。
3. **judge_model / embed_model は arm 横断で固定**（測定の一貫性。既に別 keyword なので触らない。
   既定 `judge_model = model` のままだと arm ごとに judge が変わるので、**`--judge-model` を明示固定する**運用にするか、
   既定を `gemma4:26b` 固定に。disc_strict は決定的で judge 非依存だが、icc/coverage の比較可能性のため固定推奨）。
4. **run 行・summary・print に `substrate` を追加**。`%{...}` の run map（現 223-244 行）に `substrate: name`、
   `summary_by_cell/1` の group key（現 284 行 `{&1.k, &1.kp, &1.serve, &1.aware, &1.hetero}`）に `substrate` を追加、
   print も同様に列追加。
5. **CLI 解析**。`parse_args/1`（現 103-141 行）に `substrate: :string` を追加し、
   `parse_substrates/1` を実装:
   - `homo12b` → `{"homo12b", %{all "gemma4:12b"}}`
   - `homo26b` → `{"homo26b", %{all "gemma4:26b"}}`
   - `hetero`  → `{"hetero",  %{"SEC"=>"gemma4:12b","BIZ"=>"gemma4:26b","UX"=>"gemma4:12b"}}`
   - 任意で `--models "SEC=gemma4:12b,BIZ=gemma4:26b,UX=gemma4:12b"` の明示指定も。
   - 既定 substrate = `homo12b`（後方互換: 指定なしなら従来どおり単一 model）。

**注意点**:
- `Dissolution.default_agents/0` の id は `"SEC" / "BIZ" / "UX"`（`lib/tracefield/dissolution.ex:15-31`）。model_map のキーと一致させる。
- 既存の `--model` は homogeneous arm の単一指定として温存（substrate 未指定時の fallback）。
- per-agent seed（`seed + index`、hetero.ex:187）はそのまま。モデルが変わっても seed 規律は不変。

## 4. 実験計画

```
mix tracefield.hetero --adapter ollama \
  --substrate homo12b,homo26b,hetero \
  --hetero grounded --serve diverse --aware 1 --kp 1 --ks 2 \
  --judge-model gemma4:26b \
  --seeds 6
```
（24×? runs ── 3 substrate × 1 hetero × 1 serve × 1 aware × 1 kp × 1 ks × 6 seeds = 18 runs。
コスト懸念があれば seeds=3 でパイロット→符号を見て seeds=6 へ。26b は遅い: 18 runs で数十分〜数時間を見込む。）

- **一次指標**: `disc_strict`（決定的）。3 arm の mean±sd と全 seed 生値。
- **theater 監視**: `diversity` / `collapse_rate`。発見増と同時に diversity が落ちていないか。
- **二次**: `icc` / `coverage`（judge 飽和に注意。§9c）。
- **判定**: §1 の支持/棄却基準。sign test（hetero vs homo26b の seed 対）も併記。

## 5. 検証（Claude が verify）

1. `mix test`（既存 28 test が緑のまま ── substrate 未指定時の後方互換）。
2. **mock スモーク**: `mix tracefield.hetero --substrate homo12b,homo26b,hetero --seeds 1`（adapter 既定 mock）で
   3 arm が回り、per-agent に異なる model 文字列が渡っていることを run JSON の構造で確認（mock は出力同じでも配線は検証可能）。
3. **ollama パイロット**（seeds=2）: 3 arm が完走し disc_strict が出ること、26b arm が実際に 26b を叩いていること（レイテンシで判る）。
4. 本走 seeds=6 → `docs/findings-substrate-hetero.md` に結果表＋判定を記録（findings-contrastive-serve.md と同じ様式）。

## 6. リスク・限界

- **3エージェント×2モデル**では「異種」の配合が1通りに固定されがち（SEC/BIZ/UX のどれを 26b にするかで結果が動く可能性）。
  → 本命配合に加え、余力があれば 26b を当てる agent を変えた副 run で頑健性を確認。
- **gemma4:12b と 26b は同系列**（真の基盤異質性としては弱い ── tokenizer/系統が近い）。
  陽性なら強い証拠だが、陰性でも「同系列では不足、異系列モデルが要る」可能性を残す（限界として明記）。
  将来: 異系列（別ベンダ/別アーキ）や `gemma4:12b-it-qat` 混成、ツール/データアクセス差（grounded は既に情報異質性を与えている）。
- 単一シナリオ（enterprise-assistant）・植え込み相互作用 I1〜I3 の3件天井 ── H2（高天井シナリオ）と共有の限界。
- 統計的断定ではなく機構レベル（seeds 6・gemma 系）。

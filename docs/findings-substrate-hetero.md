# 結果 — 基盤異質性（H1: substrate heterogeneity）の検証と棚上げ

> 日付: 2026-06-14。ブリーフ: [`impl-brief-h1-substrate-hetero.md`](./impl-brief-h1-substrate-hetero.md)。
> 問い: 攻めの便益（genuine 横断発見）は、契約の自覚(aware)＋多様 serve だけでなく、
> **エージェントの基盤異質性（異なるモデル）** の関数として増えるか（[`experiment-results.md`](./experiment-results.md) §11 が「次の決定的実験」と名指ししたまま未実行だった軸）。

## 設定

- `mix tracefield.hetero --adapter ollama --substrate homo12b,homo26b,hetero --serve diverse --aware 1 --kp 1 --ks 2 --seeds 6`（18 runs）。
- 交絡対策の3 arm: `homo12b`（全 SEC/BIZ/UX = gemma4:12b）/ `homo26b`（全 26b）/ `hetero`（SEC=12b, BIZ=26b, UX=12b）。
- 一次指標 = `disc_strict`（決定的・植え込み相互作用 I1〜I3 の発見数、∈{0,1,2,3}）。theater 監視 = `diversity`/`collapse`（決定的・埋め込み）。判定器・埋め込みは arm 横断で固定。
- 支持基準: `hetero > max(homo12b, homo26b)`（超加法）。棄却基準: `hetero ≤ homo12b`（異質性は仕事をしていない）。
- provenance: パイロット `runs/20260614T120201...json`（seeds=2）／本走 `runs/20260614T124323.517238-hetero-ollama.json`（seeds=6）。

## 結果（seeds=6, mean±sd）

| substrate | disc_strict | disc_judge | icc | coverage | diversity | collapse |
| --- | --- | --- | --- | --- | --- | --- |
| homo26b | **2.17 ±0.41** | 1.33 | 1.67 | 4.2 | 0.173 | 0.35 |
| homo12b | **2.00 ±0.89** | 0.83 | 5.50 | 9.0 | 0.224 | 0.15 |
| **hetero** | **1.83 ±0.75** | 1.50 | 3.83 | 6.3 | 0.179 | **0.44** |

生値 disc_strict: homo12b `{2,1,1,3,3,2}` / homo26b `{2,3,2,2,2,2}` / hetero `{1,2,2,3,1,2}`。

## 判定 — 棚上げ（promote しない、H1 反証）

**ordering は `homo26b > homo12b > hetero`** ── hetero は最低で、3 arm は互いにノイズ内。
**支持基準（hetero が両 homo を上回る）を満たさず、hetero ≈ homo12b 以下＝棄却基準側**。
パイロット（seeds=2）の `hetero 3.0 > homo26b 2.5 > homo12b 1.5` は **n=2 のノイズ**だった（ブリーフで明記したリスクが顕在化）。

→ **gemma4 12b×26b の(同系列)基盤異質性は、攻めの便益を増やさない。** 攻めの便益の駆動因は §14 の「**構造 × 契約の自覚**」であって基盤異質性ではない、という解釈を補強する陰性結果。

### 副次（過解釈しない・しかし重要）
- **hetero は collapse 最高(0.44)・diversity 中位**: 強(26b)＋弱(12b)混成は横断発見を増やさず、むしろ**エコー(collapse)を増やす**傾向（弱が強に追従? or 下記の swap 起因ノイズ）。
- **homo12b は探索最広(coverage 9.0・diversity 0.22)** だが disc_strict は他と同等 ── 幅は出るが植え込み相互作用の的中は増えない。

## 重大な方法論的交絡 — hetero arm のみ非決定的（model-swap）

同一 seed(2000,2001) をパイロットと本走で比較すると:
- **homo12b/homo26b は byte 完全一致**（2,1 / 2,3）＝ 単一モデル run はハーネスが決定的。
- **hetero は不一致**（パイロット {3,3} → 本走 {1,2}）＝ **hetero arm だけ非決定的**。

機構: 12b(7.6GB) と 26b(17GB) は **VRAM に同居できず、ollama がターン毎に swap** する。swap が KV/数値状態をリセット → hetero 条件にのみノイズを注入。
→ **hetero の測定は交絡している**。便益が無いことに加え、比較自体が不公正。クリーンな再試には:
1. **swap 回避**（十分な VRAM で同居、別 ollama インスタンス、or 並行サービング）。
2. **異系列モデル**（下記）。

## 限界（陰性の射程）

- **同系列モデル**: gemma4:12b と 26b は同一アーキ/学習系列＝「サイズ違い」であり「異なる頭」ではない。
  本結果は **「同系列サイズ異質性は効かない」を示すのみ**で、**異系列（別ベンダ/別アーキ: llama/qwen/mistral 等）の真の基盤異質性は未検証**（ブリーフ §6 で予告した残し）。これが H1 の本来の clean test。
- **3件天井**（disc_strict ∈ {0,1,2,3}）で検出力が低い ── [`findings-contrastive-serve.md`](./findings-contrastive-serve.md) と同じ天井問題。H2 の高天井シナリオが前提。
- n=6・単一シナリオ・単一セル（serve:diverse, aware:1, kp:1）・機構レベル（統計的断定ではない）。

## 決定と今後

- **substrate 軸は promote しない**。`--substrate` は実装・コミット済（後方互換・無害）で、**異系列モデルでの clean test 用に温存**。
- **筋の良い次手**（やるなら、優先度は H4＜）:
  1. **異系列ローカルモデル**（gemma×qwen×llama 等）で再検証＋**swap 交絡を除去**した設計。これが H1 の本来の決定実験。
  2. それまでは攻めの便益のテーゼは §14（構造×自覚）のままで確定し、substrate は「同系列では無効・異系列は未検証」と正直に保留。
- **コードは健全**: homo arm の決定的再現・theater 指標の一貫性は、ハーネスと指標が正しく動いていることを示す（効かないのは substrate 軸であってハーネスではない ── contrastive 棚上げと同じ構図）。

---

## H1b — 異系列（cross-family）での再試: 反証を強化（2026-06-15）

H1 の最大の限界「gemma は同系列（サイズ違い）＝真の異質性未検証」を解消するため、**本物の異系列モデル**を器官に再試。
設計: [`impl-brief-h1b-crossfamily-openrouter.md`](./impl-brief-h1b-crossfamily-openrouter.md)。

### 器官の構成（cursor-agent 統一）
当初案（OpenRouter／3つの別 CLI）はいずれも摩擦があり、**cursor-agent 1本＋`--model` 違い**に統一（ユーザー指摘）:
- **Opus 4.8**(Anthropic) / **GPT-5.5**(OpenAI) / **Composer 2.5**(Cursor) ＝ 別ベンダ・別アーキの真の異系列。
- 全て `cursor-agent -p --output-format text --model <X>` ＝ 清潔な出力1本（codex exec の冗長バナーで JSON 抽出が壊れる問題・claude -p の長文沈黙を回避）。
- `--force`/`--trust` なし＝**reasoning only（repo コマンド実行不可）**。実際 **72 回の呼び出しで repo 副作用ゼロ**を確認。key 不要（Cursor subscription）。
- ハーネス: `--adapter cli`＋プリセット `cur-opus/cur-gpt/cur-composer/cur-hetero`＋per-agent 器官ルーティング＋`--judge-adapter ollama`（judge＝ローカル gemma26b、一次 disc_strict は判定非依存）。

### 結果（seeds=3, mean±sd, 一次=disc_strict）

| substrate | disc_strict | diversity | collapse | icc | coverage |
| --- | --- | --- | --- | --- | --- |
| cur-opus（全 Opus） | **2.67 ±0.58** | 0.205 | 0.00 | 8.0 | 8.7 |
| cur-composer（全 Composer） | **2.67 ±0.58** | 0.239 | 0.11 | 7.3 | 8.3 |
| cur-gpt（全 GPT） | **2.00 ±0.00** | 0.223 | 0.00 | 7.7 | 8.7 |
| **cur-hetero（Opus+GPT+Composer）** | **1.67 ±0.58** | 0.239 | 0.00 | 7.0 | 8.3 |

生値 disc_strict: opus `{3,2,3}` / composer `{3,3,2}` / gpt `{2,2,2}` / hetero `{1,2,2}`。

### 判定 — 反証（H1 を強化）

**cur-hetero は最低**（1.67）── 同質3 arm すべて（2.67/2.67/2.00）を下回り、**最弱の homo（GPT 2.0）すら下回る**。
gemma 同系列 H1 と**同じ符号**（hetero 最下位）が、**本物の異系列でも再現**。
→ **substrate 異質性は攻めの便益（横断発見）を増やさない ── 同系列でも異系列でも。むしろ僅かに不利。**
これで H1 の「同系列ゆえ未検証」という最大の留保が外れ、**攻めの便益の駆動因は §14「構造 × 契約の自覚」で確定**（substrate ではない）。

### 機構の仮説（過解釈しない）
異系列混成がむしろ低い理由の候補: Shared State パターン（agents が共有ストアで互いに積み上げる）は、**共有する規約・表現を持つ同質エージェントの方が「積み上げ」が効く**。異系列は表現/規約がずれ、横断的な積み上げ（counterpart への的確な応答）がやや劣化しうる。collapse は全 arm ~0 でエコー過多ではない ── 「均質化」ではなく「噛み合いの低下」の像。**仮説**（[`frame-problem.md`](./frame-problem.md) §6 / multi-agent coordination の Shared State と整合）。

### 限界
- **n=3・sd 0.58** ＝ 差は ~1sd 内で統計的断定でない。ただし**符号は gemma H1 と一貫**し hetero < 全 homo。
- 3件天井（disc_strict ∈ {0,1,2,3}）で検出力低（H2 高天井シナリオが望ましい）。
- cursor-agent は seed 非対応＝非決定的（homo も run 間で揺れる）。単一シナリオ・単一セル。
- disc_judge は全 arm 3.0 で飽和（判定器無効）＝ 一次は決定的 disc_strict のみ採用。
- Composer（Cursor の小型）が Opus と同点(2.67) ＝ このタスク/天井ではモデル強度差が出にくい。

### 決定
- **substrate 軸は確定的に promote しない**（同系列 H1 ＋ 異系列 H1b の二重反証）。攻めのテーゼは §14（構造×自覚）で確定。
- cursor-agent 統一の cross-family ハーネスは健全・安全・再利用可（将来 H2 高天井シナリオでの再検や、別タスクでの cross-family 比較に使える）。

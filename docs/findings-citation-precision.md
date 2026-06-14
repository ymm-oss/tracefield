# 結果 — citation 接地 provenance の harness 検証（H4: precision の梯子）

> 日付: 2026-06-14。ブリーフ: [`impl-brief-h4-citation-precision.md`](./impl-brief-h4-citation-precision.md)。
> 問い: C5 の過剰隔離（precision 0.50）を、per-citation stance ＋ 接地照合(verify) で解消できるか。
> Python プロトタイプ（[`experiment-results.md`](./experiment-results.md) §7、`experiments/tf_reference_*.py`）の梯子を **Elixir ハーネス**で再現できるか。

## 実装（M1 — Option B）

per-citation stance を**後方互換**で導入（codex の侵襲的 Option A ＝ `citations` 自体を構造化 ＝ 不採用。理由は下記）:

- **`entry.citations` は flat `[id]` のまま**（全消費者・テスト無改修）。stance は **`meta.citation_stances = %{id => stance}`** に並列保持。
- **非 default（refutes/context）のみ記録**: flat 引用・relies_on は記録せず、読み手が absent→relies_on と既定する（§6f の挙動と一致、meta も無変更）。
- 永続化・export/import は `meta` 経由で stance を**自動 round-trip**（追加配線不要）。
- 変更点: `reference.ex`（`normalize_citations` を {id,stance} 受理に拡張＋`normalize_entry` で stance を meta へ＋helpers）／`agent.ex`（プロンプトを `{"id","stance"}` に＋`sanitize_entry`＋自動付与は stance=context）。**全 253 既存テスト green**＋stance テスト3本。
- **codex Option A を棄却した理由**: `entry.citations` を `[%{id,stance}]` に変えると `.citations` を flat id 前提で読む全消費者（genesis/culture/recruit/ideate）が regression（実機で確認）。Option B は blast radius を reference.ex＋agent.ex に限定。

## 結果（M2 — 統制ケースの梯子、決定的・実機）

`Tracefield.CitationPrecision`（scorer）＋統制テスト（`test/citation_precision_test.exs`）。汚染チャンク C を、
genuine 採用2点（relies_on＋接地）＋ refute 引用 ＋ context 引用 ＋ 幻覚 relies_on（引用するが内容非接地）の計5点が引用。GT = genuine 2点。

| provenance 規則 | precision | recall | 落とすもの | 効いた層 |
| --- | --- | --- | --- | --- |
| cited-anything（引用したか・stance 無視） | **2/5 = 0.40** | 1.0 | — | 接地のみ |
| relies_on（stance 限定） | **2/3 ≈ 0.67** | 1.0 | refute＋context 引用 | stance |
| relies_on + verified（**完全形**） | **2/2 = 1.00** | 1.0 | 幻覚 relies_on | verify |

（参考: 旧 `depends_on_turns`＝会話「触れた」は §6f 実測 0.50。citation 接地はそれより選択的な cited-anything から始まり、stance→verify で 1.00 へ。）

## 判定 — H4 機構は harness で成立（precision blocker は解ける）

**接地→stance→verify の3層が、敵対的引用（refute/context/幻覚）下でも precision を 0.40→0.67→1.00 へ単調に押し上げ、recall は 1.0 維持。**
Python プロト（controlled GT）の §7 梯子を **Elixir ハーネス上で再現**。C5 の過剰隔離 precision は **per-citation stance＋verify で機構的に解消する**ことを harness で確認した。

- **stance の寄与**: refute（反論引用）と context（参照のみ）を affected から除外 → 0.40→0.67。
- **verify の寄与**: 内容がチャンクに接地しない幻覚 relies_on を棄却 → 0.67→1.00。
- recall 不変 = genuine 採用は全規則で捕捉（締め付けは過剰連結のみを削る）。

## 限界（M2 の射程）

- **統制ケース（design-time GT）・決定的 Mock verify**。Python プロト同様、これは**機構の実証**であり、**実探索での自然発生・規模・複数シナリオは未**（= 次の M2b）。
- verify は Mock のトークン重なりヒューリスティック（実 LLM 判定での stance/接地品質は M2b で）。
- **stance の自己申告品質**（agent が refute/context/relies_on を正しく付すか）は実エージェントでのみ測れる新たな誤差源（design-reference §8）。統制ケースでは stance を所与とした。
- permissive 汚染(C型)は射程外（§6h、判定器の限界）。
- **越境(import)では `meta.citation_stances` のキーが remap されない既知の限界**（cross-cluster stance remap は将来）。単一クラスタの本実験には無影響。

## 決定と今後

- **stance 配線（Option B）を採用・promote**。`CitationPrecision` scorer も常設。
- **次 = M2b（自然発生・外的妥当性）**: enterprise-assistant の**汚染B（PM証言）を `:chunk` 化**し、grounded＋aware エージェントに stance 付きで引用させ、撤回 → 梯子を実測。GT は反実仮想 or 命題アンカー stance 判定（§6f の汚染B が採用・伝播する型＝決定ケース）。H1 の seeds 実験と同じく background 実走。
- これが通れば C5 の守りは「精度つきで製品化可能」となり、**H3（越境B型撤回の GT つき測定）の precision 前提**が満たされる（[`frame-problem.md`](./frame-problem.md) §5 のキラー機能）。

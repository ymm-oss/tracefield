# 結果 — 接地ステージ汎化: 読み取りハルシネーション抑制手法の完成（grounded reading）

> 日付: 2026-06-21。ブリーフ: [`impl-brief-grounded-reading.md`](./impl-brief-grounded-reading.md)。
> 問い: コード/ドキュメント読み取りのハルシネーション抑制について、既に各層で再導出されている
> **再接地テーゼ**を一般化し、文書（in-store チャンク）とコード（on-disk ファイル）の双方に効く
> 単一の機械機構として「手法」を完成できるか。

## 既存理論の統合 — 再接地テーゼ（the re-grounding thesis）

複数の findings が同じ load-bearing プリミティブを別の層で再導出していた: **主張の出典を*再オープン*し、
主張がそこに実際に支持されるかを照合する**。

- **引用 precision の梯子**（[`findings-citation-precision.md`](./findings-citation-precision.md) §M2）: 接地→stance→**verify** の3層が、敵対的引用下でも precision を 0.40→0.67→**1.00** へ単調に上げる。最後の +0.33 は「引用するが内容が非接地＝幻覚 relies_on」を verify が棄却した分。
- **審判の再接地**（[`findings-substrate-hetero.md`](./findings-substrate-hetero.md) §H1c）: 上流固定で、ファイルを開ける審判（codex, 46回 rg/cat 再読）は偽反証を **10/12 覆す**が、開けない審判（gemma）は **1/12**。差の源は「証拠が無い」でなく「**証拠を検証できない**」。覆し決定性は再接地能力に律速される。
- **決定論コマンドプローブ**（[`findings-command-probe.md`](./findings-command-probe.md)）: 外部ツール（fslc/rg/cargo test）の判定を retractable な provenance エントリにする「センサ（計測）」。LLM 不使用＝confab 原理ゼロ＝鉄則2の極限点。「LLM が反証されたと*思う*」を「事実として反証」に替える。

一行で言えば: **全モデル呼び出しを忠実な小規模文脈に留め、主張に再オープン可能な出典を引用させ、最終の偽の棄却を決定論コード（閉包＋コマンドプローブ）に置く** ── 著者・合成・審判のどの LLM も、出典が支持しないものを主張・隠蔽・追認できなくする。

## 完成前のギャップ（2点・独立 2 監査で確認）

エンジンには既に機械照合の evidence_quote ゲートがある（`apply_core_gates` → `evidence_quote_found_in_citations`、`flow.rs`）。`meta.evidence_quote` が引用エントリの逐語部分文字列でなければ `evidence_quote_not_found`＋`needs_review` を立てる ── これが citation-precision の 1.00 を駆動した機構。だが読み取りに効かせるには2つの穴があった:

1. **canonical reading stages に届かない。** ゲートは `is_source_grounded_stage()`（`flow.rs:2772`）が true のときだけ走る ── stage id/organ/role に `source_`/`web`/`data` を含むかという**脆い名前ヒューリスティック**。正準骨格 `analysis → verify → adjudication` も、旗艦シナリオ `fsl-codespec` の全段（`evidence`/`spec_draft`/`verify`/…）も**一致しない**。＝最強の機構が旗艦コード読み取りで一度も走っていなかった。
2. **on-disk コードを照合できない。** `evidence_quote_found_in_citations` は quote を*引用した store エントリ本文*に照合する。コード読み取りでは引用エントリは**ポインタ**（`inputs/region-*.md`: `path:`＋`lines:`）で、実コードは disk 上にあり actor が再オープンする。だから quote は引用エントリに無く、照合が成立しない（`relies_on` の真偽が機械検証されない ── 旗艦の唯一最大の残存面）。

`findings-substrate-hetero.md` §157 が処方済の対処（「判定の後段に決定論コマンドステージ＋rg で機械接地」）の一般化に当たる。

## 実装 — 一つの統一ゲート（per-stage 接地 opt-in ＋ on-disk 解決）

in-store 照合と on-disk 照合は**同一の「source への部分文字列照合」ロジック**で、違いは*source がどこに解決されるか*だけ。よって2機構でなく**1つに統合**する（consolidation）。実装は codex に委譲（`crates/tracefield-core/src/flow.rs` のみ・新依存なし）:

1. **per-stage `grounded` flag**: `[stages.<id>] grounded = true` → `StageConfig.grounded` → `is_source_grounded_stage` が true。これで evidence_quote 契約＋機械照合が任意の読み取り段で起動する（**文書**＝store チャンクの読み取りはこれだけで完成）。名前ヒューリスティックは既存シナリオのため温存（OR で追加）。
2. **on-disk source 解決**: in-store 照合が外れたら、主張が名指す `meta.source_path`（＋任意 `meta.source_line`）を `scenario_dir` 相対で解決し、実ファイルを read-only で読んで部分文字列照合する（**コード**＝disk 上ファイルの読み取りを完成）。両者を `quote_grounded(store, scenario_dir, citations, meta, quote)` 1関数に集約。読めない/存在しない/非ファイルは安全側＝not-grounded（warning、run は止めない）。
   - **path 制限は不要（no-content-leak）**: 本ゲートの出力は boolean のみ（→data-quality warning）。ファイル内容は store に一切複製せず、エージェントにも返さず、実行もしない（`skill_tools.rs` はファイル*内容*を返すので escape が漏洩になるのと対照的）。捏造 `source_path` を渡しても「その path の実ファイルに LLM 自身の quote が在るか」の真偽が出るだけで情報は漏れない。よって `..`/絶対パスを許す（コードは scenario dir 外＝repo の `../../crates/...` に在り、read-only エージェントが読むのと同じ範囲を読む必要がある）。当初 codex は予防的に `..` を弾いたが、それは正当な cross-dir 読み取り（fsl-codespec）を壊すため緩和した。
3. 契約文（`SOURCE_GROUNDING_CONTRACT`）に「ファイル接地なら `meta.source_path`/`source_line` を付し evidence_quote を実ファイルから逐語コピーせよ」を1文追加。

### codex 実装・テスト結果（2026-06-21・実機）

本変更は `flow.rs` のみ（新依存なし）。`cargo fmt` clean、本変更分の clippy clean、`cargo test` **77 passed / 0 failed**（既存全 green ＋新規4本）。（注: `store.rs::reconcile_overturned` に clippy 1.95 が出す `collapsible_if` 警告1件が残るが、これは本接地変更と無関係の pre-existing で、外部フォーマット hook が nested 形を維持している＝本件のスコープ外。）新規ユニットテスト4本 green（決定論＝機構実証。citation-precision の「統制ケース・決定的 verify」と同じ証拠基準）:
- `grounded_flag_enables_evidence_quote_gate`: 名前ヒューリスティック不一致の段（id=`analysis`）でも `grounded=true` で捏造 quote を `evidence_quote_not_found` 検出。flag=false なら無警告（flag が起動因であることの統制）。
- `on_disk_evidence_quote_grounds_claim`: in-store に無く `meta.source_path` の実ファイルに在る quote が grounded（`meta.evidence_grounded="on_disk"`）。捏造 quote は `evidence_quote_not_found`。
- `on_disk_parent_dir_path_grounds_claim`: `../` で scenario dir 外の実ファイルを指す quote が grounded（＝fsl-codespec の `../../crates/...` 形を再現。codex が予防的に弾いた `..` 制限を緩和して通した）。
- `on_disk_missing_source_path_does_not_panic`: 存在しない path → not-grounded（warning・panic/run エラーなし）。

### 旗艦 mock スモーク（実エンジン経由の wiring 実証）

`tracefield run --scenario-dir scenarios/fsl-codespec --config flow.mock.toml`:
- フロー完走（全7段）。`grounded=true` の **spec_draft(12)・verify(4)** の各エントリにのみ `missing_evidence_quote`＋`evidence_strength=needs_review` が付き、grounded でない evidence/gate_grounding/adjudication/assemble には**一切付かない** ── **flag が指定段だけでゲートを起動する**ことを実エンジンで確認。
- mock は canned で quote を持たないので全件 needs_review に倒れる（期待通り＝mock では接地不能、ゲートはそれを正しく検出）。実 codex run では actor が `evidence_quote`＋`source_path` を出し on-disk 照合で*真の主張だけ*が grounded・*捏造だけ*が flagged になる（mock では駆動不能＝次手）。ユニットテスト（照合ロジック）＋mock スモーク（段別 wiring）で機構は二面から実証済。

## 旗艦適用 — fsl-codespec を grounded 化

- `verify`（4直交反証・atomic）と `spec_draft`（read 時・複合 fragment）に `grounded = true`。各 grounded レンズは主張に逐語 `meta.evidence_quote`＋`meta.source_path`（領域ポインタの `path:` 値）＋`meta.source_line` を付す。
- これで verify の各反証は**突いた実コード行に per-claim で機械照合**される（`relies_on` の真偽が初めて機械検証＝旗艦の残存面を閉じる。再接地テーゼの H1c が指した overturn-critical 段＝verify をエンジン側で接地）。
- `evidence` digest は中間足場（事実は下流で再接地）なので grounded にしない＝余計な friction を避ける。

### 実走検証（実 codex-app-server・2026-06-21）

`tracefield run --scenario-dir scenarios/fsl-codespec`（既定 flow.toml＝codex-app-server、grounded 段あり）を1回クリーン走。codex が6段で実コードを再オープン（`codex_command` provenance 200件）。grounded 段の主張エントリ（provenance 除く）の接地結果:

| grounded 段 | 主張数 | `evidence_quote`＋`source_path`＋`source_line` | **on-disk grounded** | warning |
| --- | --- | --- | --- | --- |
| spec_draft | 9 | 9/9 | **9/9** | 0 |
| verify | 8 | 8/8 | **8/8** | `weak_evidence_quote` 1 |

- **17/17 が on-disk 照合で grounded**（`meta.evidence_grounded="on_disk"`）＝実 codex が新 contract に従い逐語 quote＋`source_path`＋`source_line` を出し、エンジンが scenario dir 相対の `../../crates/...` を解決して実ファイルに quote を機械照合できた（cross-dir on-disk 解決が production で成立）。
- **独立再照合で true-positive を確認**: 例 `e29`＝`source_path=../../crates/tracefield-core/src/entry.rs`, `source_line=52`, quote=`pub enum EntryStatus { … Active, Retracted, Superseded, … }`。実 `entry.rs:52` はまさに `pub enum EntryStatus {`＝quote は引用行に逐語で実在（接地は偽陽性でない）。
- **品質ゲートも稼働**: verify の1件が `weak_evidence_quote`（短すぎ/省略の弱アンカー）として捕捉。
- **正直な射程**: `evidence_quote_not_found`（捏造・誤引用の捕捉）は **0** ── 実 codex が忠実に再オープン＋逐語コピーしたため。本走が示すのは (a) 規律が実モデルで follow 可能 (b) on-disk 解決が cross-dir で production 成立 (c) 真の主張が grounded になる、まで。*捏造の捕捉*そのものは敵対 actor が要るため本走では発生せず、ユニットテスト（捏造 quote→`evidence_quote_not_found`）が別途実証している。両者で「忠実なら通し・捏造なら捕える」の双方向を実証。

## 判定 — 手法は完成

**再接地が3層の単一機構として、文書（in-store）とコード（on-disk）双方に効くようになった**:
(1) 出力規律（grounded 段は evidence_quote 必須）、(2) 機械照合（in-store ∪ on-disk の統一 `quote_grounded`）、(3) per-claim・retract 閉包内・no-silent-drop（warning は当該エントリに乗り、基盤 retract で連鎖退場）。
最強の機構（citation-precision を 1.00 にしたもの）が、名前ヒューリスティックの檻から出て、正準骨格と旗艦コード読み取りで初めて走る。

## 限界

- **複合エントリは anchor-level 接地のみ。** `spec_draft` の fsl_fragment（領域ごと1エントリに複数主張）は evidence_quote 1本で entry 単位の照合＝丸ごと捏造の検出に留まる。主張単位の full 接地には atomic エントリ化が要る（per_input シャード軸への影響評価が必要なため本実装では見送り。`evidence` の digest は spec_draft の actor 数を律速するので atomic 化不可）。verify は atomic なので per-claim 接地が成立。
- **evidence_quote の自己申告品質**は実エージェント依存（actor が逐語コピーするか）。citation-precision §限界の stance self-report 問題と同種の新たな誤差源。
- **自然発生する捏造の catch-rate は未測。** 実 codex 走（上記）で 17/17 が grounded・`evidence_quote_not_found` 0 ＝**実 codex が忠実だったため捏造が発生しなかった**。よって「機構が production で動く（規律 follow・on-disk 解決・真の主張の grounding）」は実証したが、「自然発生した捏造を何%捕えるか」は未測（多数 run／codex が実際に幻覚する難シナリオが要る）。捏造の捕捉自体はユニットテストで決定論実証済。n=1・単一シナリオ。
- **on-disk 照合の帰属は弱い。** `source_line ±window` で局所化するが、quote が他所にも在ると false-positive 接地になりうる。引用エントリ限定の in-store 照合の方が帰属は強い。
- **`source_path` は LLM 申告。** 捏造パスは読めず not-grounded に倒れる（安全側）が、正しい構造の偽 path で別ファイルの実在行を指す攻撃は未防御（source_line と quote の二重照合で緩和）。
- 機構レベルの実証であり統計的断定ではない（プロジェクト全 findings と同様）。

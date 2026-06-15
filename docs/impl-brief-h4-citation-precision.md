# 実装ブリーフ H4 — citation 接地 provenance の harness 検証（precision の梯子）

> 仮説 H4。守りの最大ブロッカー（C5 の過剰隔離 precision 0.50）を、**per-citation stance ＋ 接地照合(verify)** で
> harness 上・自然発生汚染で解消できるか。Python プロトタイプ（`experiments/tf_reference_proto.py` /
> `tf_reference_adversarial.py`）で 0.50→1.00 の梯子を示したが、**Elixir ハーネスでは未検証**。
> 根拠: [`experiment-results.md`](./experiment-results.md) §6f/§7、[`design-reference.md`](./design-reference.md)。

## 1. 仮説と棄却基準

- **H4（主張）**: Reference/Agent 経路で per-citation stance(`relies_on|refutes|context`) を記録し `verify`（接地照合）を通すと、
  撤回チャンクの affected_set 精度が規則を上るごとに改善し、**完全形で >0.8（統制ケースでは 1.0）**。
  | 規則 | 期待 precision（§7 プロトタイプ） | 効く層 |
  | --- | --- | --- |
  | depends_on_turns（旧・参照 baseline §6f） | 0.50 | ── |
  | cited-anything（チャンク引用したか・stance 無視） | 0.60 | 接地（会話より選択的） |
  | relies_on（stance 限定） | 0.75 | refute/context 引用を除外 |
  | relies_on + verified（**新 Reference 完全**） | **1.00** | verify が幻覚引用を棄却 |
- **支持**: harness データで cited-anything < relies_on < relies_on+verified と単調上昇し、完全形 >0.8。recall は維持（≥1.0 近傍）。
- **棄却**: 完全形でも precision ≤0.6（プロトタイプの 1.0 が controlled GT のアーティファクト）→ 接地は実条件で過剰連結を解かない。
- **製品的含意**: 陽性なら C5 の守りが製品化可能（roadmap 行き先①②の critical path）。H3（越境統治）はこの precision 修正に依存。

## 2. なぜ今これか

- C5>C4 はプログラム最強の守り結果だが、**実探索 precision は 0.50 止まり**（§6f）＝過剰連結（`depends_on_turns` が構造的「触れた」を拾う）。
- 解は **citation 接地** と分かっているが、実証は Python proto（controlled GT）のみ。
  ハーネス＋自然発生＋stance の自己申告品質を harness で確かめるのが残務。
- 既に効いている下地: `Reference.verify/3`（接地照合・LLM 判定）と `retract`＋閉包は実装・実証済（§3 Path E）。

## 3. コード変更（正確な touch-point）

### 3-1. per-citation stance（中核・後方互換が肝）

現状: citation は**フラットな id 文字列のリスト**。stance が無い。
- `lib/tracefield/reference.ex:11-12` `Entry` の `citations`（フラット）。
- `lib/tracefield/reference.ex:597-604` 付近 `normalize_citations/1`（id 文字列へ正規化）。
- `lib/tracefield/agent.ex:571-588` `sanitize_entry/7` の citations 抽出（`to_string` でフラット化）。
- `lib/tracefield/agent.ex:278,284` system プロンプト JSON 例 `"citations":["e1"]` と指示。

変更方針 — **citation を `{id, stance}` の構造に拡張しつつ、フラット文字列も受理（後方互換）**:
1. **正規化を一元化**: citation 1件を `%{id: String.t, stance: :relies_on|:refutes|:context}` に正規化するヘルパを Reference に追加。
   - 受理形: `"e1"`（→ `%{id: "e1", stance: :relies_on}` 既定）、`%{"id"=>"e1","stance"=>"refutes"}`、`{"e1","refutes"}`。
   - **既定 stance = `:relies_on`**（既存の全 run/test/コードがフラット id を出しており、それらを「依拠」とみなすのが §6f の挙動と整合）。
2. **Entry.citations を構造化リストに**。`@enforce_keys` は維持。内部表現は `[%{id, stance}]`。
   - **波及を必ず潰す**（フラット id を前提にしている箇所）:
     - 永続化 JSONL（encode/decode）── stance を含めて round-trip。旧 run の読込は既定 relies_on で吸収。
     - `export`/`import`/`propagate_retractions`（citation 経由の写し再マップ）── id を引く処理が stance 構造でも動くこと。
     - 閉包計算（retract→下流隔離）── id を辿る処理。
     - `append_procedure_id` 等（agent.ex:601-621）── procedure/territory/recruit の自動付与は `stance: :context`（依拠でない）で付ける。
     - `most_cited` / citation 数カウント。
3. **Agent プロンプトと抽出**:
   - `@system_json_example`（agent.ex:278）を `{"entries":[{"type":"belief","text":"...","citations":[{"id":"e1","stance":"relies_on"}]}]}` に。
   - 指示文（agent.ex:284）に stance の意味（relies_on=この主張はこのチャンクの真偽に依拠 / refutes=反論引用 / context=参照のみ）を1文追加。
   - `sanitize_entry`（agent.ex:571）で stance を保持しつつ、id は従来どおり `allowed_citation?` で許可 id に制限。
4. **verify を {id, stance} 対応に**: `reference.ex:87-123` の `verify/3` は既に id ベースで接地照合する。
   stance は照合結果と独立（verify は「引用先チャンクに主張が接地しているか」を見る）。
   relies_on かつ verified の組だけが provenance 辺になるよう、**affected 計算側で stance＋verified を AND**。

### 3-2. precision-ladder スコアラ＋シナリオ

5. **チャンク化シナリオ**: `scenarios/enterprise-assistant`（contaminant-B＝PM 証言＝§6f の採用・伝播型がある）を使う。
   - 既存資産: `contaminant-B.md` / `correction-B.md` / `private/{sec,biz,ux,interactions}.md` / `decoy-*.md`（`ls` 済）。
   - source 文書を Reference に **`:chunk`（author "DOCS"）** として absorb（agent.ex:113-127 が `:chunk` author "DOCS"/"ISSUE" を reference_docs として既に拾う）。
   - 汚染チャンク = PM 証言を `:chunk` で active 注入 → 後で `Reference.retract/2`。
   - 統制ケース（§7b 再現）として **反論引用・無関係引用・幻覚引用を含む敵対的変種**も用意（GT＝設計上の genuine 採用集合）。
6. **新 mix task `mix tracefield.reference_precision`**（または remeasure 拡張）:
   - setup: Reference に doc chunks＋汚染チャンク。grounded agents（`serve:diverse, aware:1`）を R round 走らせ、stance 付き引用を absorb。
   - GT: (i) **統制**＝設計時ラベル（proto と同じ）、(ii) **自然発生**＝汚染チャンク有り/無しの反実仮想差分（`GroundTruth` 同型）。
   - 撤回: 汚染チャンクを retract。
   - **affected_set を3規則で算出**し precision/recall:
     - `cited_anything`: 汚染チャンクを引用（stance 不問）した主張＋推移閉包。
     - `relies_on`: stance=relies_on の引用のみ。
     - `relies_on + verified`: relies_on かつ verify 真。
   - print: 規則 × {recall, precision} の表（§7 の梯子を再現）。`docs/findings-citation-precision.md` に記録。
   - **`depends_on_turns` 0.50 は §6f の既測値**を参照値として表に併記（再計算不要。別経路）。

参考実装（移植元）: `experiments/tf_reference_proto.py`（基本ケース）/ `tf_reference_adversarial.py`（refute/無関係/幻覚引用で各層を分離）。
Elixir 側はこの2スクリプトの Python ロジックの忠実な移植。

## 4. 検証（Claude が verify）

1. `mix test` 緑。**stance round-trip の単体テスト追加**（absorb→persist→reload で stance 保存）、
   **後方互換テスト**（フラット id 引用 → relies_on 既定）。
2. `Reference.verify/3` の単体テスト（接地引用=true、幻覚引用=false、retracted チャンク引用=false）。
3. **統制ケーススモーク**（mock）: 規則ごとに affected_set が proto と同じ集合になること。
4. **ollama 本走**: enterprise-assistant 汚染B で precision 梯子が cited<relies<verified で上昇、完全形 >0.8 を確認。
5. **敵対的変種**（§7b）: refute 引用が relies_on で除外、幻覚引用が verified で棄却されることを実測で分離。

## 5. リスク・限界

- **stance の自己申告品質が新たな誤差源**（design-reference §8）。「引用して反論(refute)」「context のつもりが relies_on」の誤分類。
  → verify がチャンク接地は照合するが、stance の真偽は照合しない。stance 誤りは敵対的変種テストで定量化する。
- **後方互換の波及が広い**（citation を id 前提で使う箇所が多数: 閉包・export/import・persist・most_cited・procedure 付与）。
  正規化を一元化し、フラット id を relies_on として吸収する単一の境界を作るのが安全。**ここが実装の主リスク**。
- **permissive 汚染(C型)は射程外**（§6h ── anchored 判定器が破綻。別課題）。本ブリーフは assertive 汚染(B)のみ。
- プロトタイプは controlled GT。自然発生版は汚染が「採用・伝播」する型(B)でないと追う対象が生じない（§6d/§6e）＝ enterprise-assistant 汚染B を使う理由。
- 機構レベル（単一シナリオ・gemma 系）。統計規模・複数シナリオは次段。

# 設計 — Reference と引用ベース provenance

> 目的: C5 の本丸課題「『触れた』と『真偽に依存した』が区別できない → 過剰隔離（precision 0.5）」を、
> **ドキュメント接地＋検証可能な引用**で解決する。アプリ開発（探索は spec/ADR/要件などの文書に依存する）に合わせた再設計。
> 関連: [`experiment-results.md`](./experiment-results.md) §6、[`findings-mvp.md`](./findings-mvp.md)、[`overview.md`](./overview.md)。

## 0. 決定事項

- **名称: `Reference`** ── 「文書を保持し、引用を**能動的に照合（裏取り）**して答える参照デスク」。受動的な保管庫(Archive)より役割に忠実。
  （検討候補: Archive / Ledger / Canon。照合の能動性を重視し Reference を採用。）
- **スコープ: 段階的（静的 → 生きた）** ──
  - **フェーズ1（静的）**: ソース文書（spec/ADR/要件）＋汚染チャンクのみ。引用ベース provenance の核を**最短で precision 検証**。
  - **フェーズ2（生きた基盤）**: Actor の派生主張・決定も Reference に**吸収（absorption）**し citable に。汚染が「要約→推薦」のように**派生物経由で多段伝播**するのを辿れる（半溶解性の projection/absorption に忠実）。
  - まずフェーズ1 で核を検証 → 効果確認後にフェーズ2 へ拡張。

## 1. なぜこれで本丸が解けるか

現状の弱点: provenance を `depends_on_turns`（＝「前のターンに**応答した**」）で作る。会話的・検証不能・スタンス無視 → 過剰連結。

アプリ開発では依存の正体は **「どの文書のどの箇所に基づくか」** ＝ **外部・番地つき・照合可能**:
- 「この推奨は `spec#3.2` に基づく」= 明示的引用。汚染 = 「`spec#3.2` が誤り/撤回」。
- 撤回時 → **`spec#3.2` を rely-on 引用した主張だけ**を辿れる（反論引用・無関係は除外）。

→ 難問「会話から真偽依存を推測」を、**「引用を辿る＋Reference が照合する＋引用ごとに rely/refute を見る」**へ置換。対象が一箇所に絞れて遥かに正確。

## 2. Reference — 責務とデータモデル

### 責務
1. **保持(store)**: 文書を**番地つきチャンク**で保持。各チャンクに status/version。
2. **提供(serve)**: クエリ＋関心プロファイルに対し関連チャンクを **ID付き**で返す（Actor が引用する）。
3. **照合(verify)**: 主張＋引用（chunk_id＋宣言スタンス）に対し、チャンク実在 ＆ スタンスがチャンク内容に**接地しているか**を判定。幻覚引用・的外れ引用を弾く。← 中核能力。
4. **撤回起点(retract)**: チャンクが誤り/撤回/陳腐化 → status 変更＋撤回イベント。provenance が chunk_id を指すので撤回伝播 = 「retracted chunk を rely-on 引用した主張（推移）を集める」。
5. **（フェーズ2）吸収(absorb)**: Actor の派生主張/決定を新チャンクとして取り込み、それ自身を citable・撤回可能にする。

### データモデル（最小）
```
Chunk      { id:"spec#3.2", doc, section, text, status: active|corrected|retracted|superseded, version,
             origin: source | derived }            # derived はフェーズ2の吸収物
Citation   { claim_id, chunk_id, stance: relies_on|refutes|context, verified: bool, grounding: float }
ProvEdge   claim --(relies_on, verified)--> chunk        # 主たる接地
           claim --(builds_on)--> claim                  # 二次
```
汚染は「`Chunk.status = retracted`」で表現。状態B = 該当 chunk を corrected 版に。

## 3. 関心スコープの Field Actor（= sensitivity profile の具体化）

- 各 Actor は **profile**（security / legal-consent / UX / perf / data-quality …）を持つ。
- 発言時に Reference へ **profile スコープでクエリ** → 関連チャンク取得 → 各主張に **引用（chunk_id＋スタンス）** を付ける。
- Reference が各引用を **verify** → 検証済み引用のみ provenance 辺。無引用主張は **low-grounding フラグ**。
- 副産物: 異なる profile の Actor が同じ chunk を**別スタンスで引く**所＝**介在的懸念（§8.2）**が出る（EGI 上りにも効く）。

## 4. 引用ベース provenance と影響/隔離集合

- **affected(retracted chunk X)** = X を `relies_on` かつ `verified` で引用した主張、およびそれに `builds_on` で連なる主張（推移閉包）。
- **除外**: X を `refutes` で引いた主張 / 未検証（幻覚）引用 / X を引かない主張。
- → **「触れた」と「依存した」を分離**（引用が**スタンス付き**かつ**ソース照合済み**だから）。

| | 旧 `depends_on_turns` | 新 citation |
| --- | --- | --- |
| 単位 | 会話ターン | 文書チャンク（番地つき） |
| 検証 | 不能 | Reference が照合 |
| スタンス | 無視（応答=依存） | relies_on / refutes / context |
| 過剰連結 | 多発(precision 0.5) | スタンス＋照合で抑制（目標 >0.8） |

## 5. 統治（隔離・再評価・gate）への接続
- chunk X を retract → rely-on 推移閉包を quarantine → corrected 版 X' から再導出（repair）。
- Reference の照合が**幻影引用による隔離膨張**を防ぐ（precision 維持）。
- PCE gate = 「candidate delta が retracted/未検証 chunk に rely-on 依存していないか」を Reference 照合で判定し durable state 混入前に止める。

## 6. 確定した設計判断（推奨採用）
- retrieval: まず LLM＋チャンク列挙（小規模）→ 後で埋め込み。
- 引用スタンス: `{relies_on, refutes, context}`（rely/refute 分離が肝）。
- 照合: per-citation の二値 LLM 判定（対象が狭く高信頼が見込める。anchored 判定の IRR 1.0 と同種）。
- 暗黙依存: 引用を強制し、無引用主張は gate で要根拠フラグ。
- profile カバレッジ: 全 chunk がいずれかの scope に入るか検査＋"汎用" Actor で回収。
- チャンク粒度: 節〜段落。

## 7. 実装マッピングと検証計画（フェーズ1）

- 新モジュール `Tracefield.Reference`（scenario 文書を chunk 化、`serve/2`, `verify/2`, `retract/1`）。
- scenario をチャンク化。汚染B = PM証言チャンク（status: 状態Bで retracted、状態Aで active）。
- C5' 探索: 接地 Field Actor（profile クエリ＋引用）。provenance = 検証済み citation 辺。
- 既存 `measure/remeasure` を **citation ベース affected_set** に差し替え。

**安価な決定実験**: 汚染B（採用される型）を Reference チャンク化し、引用ベース C5' を回す →
**precision が 0.50 から >0.8 に上がるか**（過剰連結が解消するか）を `remeasure` で測る。旧 `depends_on_turns` C5 と比較。

## 8. 残るリスク
- **引用の乱発**が文書引用として再発 → Reference の照合で裏取れない引用を落とすのが防波堤。
- **「引用して反論」** の relies_on/refutes 判定品質が新たな誤差源。
- 引用に乗らない懸念（横断的・暗黙的）→ 無引用フラグ＋汎用 Actor で部分回収。
- permissive 汚染（C型）の測定問題（§6h）は判定器側の課題で本設計の射程外。

---

# v2 — Reference を共有状態基盤（storehouse）へ拡張

> §10（experiment-results）の「攻めは KV/重み融合がないと検証不能」という結論は**二分法の誤り**だった（ユーザー指摘 2026-06-10）。
> トークン文脈と活性融合の間に「**外部化された共有状態**」の階層がある。しかも KV 融合は検査・分離・撤回が不能＝**統治不能な完全溶解**であり、
> アドレス可能な共有状態こそ「半」溶解の本命の操作化である。フェーズ2（生きた基盤）の一般化。

## 9. 原則

状態をトークンストリームで毎ターン押し付け合う（v2 履歴融合）のではなく、**構造化エントリとして Reference に外部化**し、
**誰でも・いつでも・選択的に（pull型で）**参照できるようにする。

## 10. データモデル

```
Entry { id,                    # アドレス（引用可能）
        type: belief | hypothesis | observation | stance | decision | question,
        author, version,
        status: active | retracted | superseded,
        confidence,
        citations: [entry/chunk ids],   # 依拠先 = provenance 辺
        embedding }                      # 選択的検索用
```

操作: **absorb**（状態の外部化・更新）/ **serve**（profile・クエリ・埋め込みによる選択的取得）/
**verify**（引用照合・既存）/ **retract**（撤回 → provenance closure で下流エントリ隔離・既存実証済み）。

## 11. ターンループと融合深さの連続化

各ターン: `query（pull・選択的）→ think（私的）→ absorb（引用付き書き込み）`。
- **融合深さ＝検索スコープ/クォータ k**（自分のみ → profile 隣接 → グローバル、取得件数）。
  カテゴリ3 regime に代わる**連続ダイヤル** → **用量反応曲線**（k × {ICC, diversity, collapse_rate}）が引ける。
- 偏り温存 = profile スコープ検索 ＋ 私的 anchor（store に書かない私的領域）。

## 12. v2 履歴融合との差（何が新たに検証可能になるか）

| 性質 | 履歴融合（§10 で限界） | 共有状態基盤 |
| --- | --- | --- |
| 持続性 | 文脈窓と共に揮発 | 文脈窓・セッションを超えて永続 |
| 注意 | 全量押し付け（カスケード/反冗長圧の交絡） | **pull 型・選択的**（交絡を除去） |
| 構造 | 散文 | 型付き・番地付き・差分可能 |
| 所有 | 各自のコピー | **同一エントリの共同所有・更新** |
| 統治 | なし | **引用＝provenance、撤回→閉包隔離が状態に対して動く**（防御資産の再利用） |

## 13. 正直な限界とリスク

- モデル境界は依然トークン。**1回の読み取り帯域は言語のまま**。本基盤が検証するのは「持続・選択・構造・共同所有・可逆性」の効果であり、
  「言語を超える帯域」ではない（それは活性レベルのみ＝統治不能）。
- **検索方策が新たな交絡**: 何を pull したかが思考を決める → 検索クエリ・取得結果を必ずログ。
- **groupthink の検索経由の再来**: 人気エントリへの収束 → profile スコープ＋多様性aware serving で緩和。

## 14. 実験計画（次段）

- **攻め（用量反応）**: k（他者状態の取得量）を 0 → profile → グローバルに振り、ICC / diversity / collapse_rate を測る（v2 の較正済み計器を再利用）。
- **守り（状態の統治）**: 信念エントリを撤回 → citations 閉包で下流隔離 → containment/repair を測る（Path E 機構の状態版）。
- 攻守が**同一基盤上**で測れることが本設計の検証価値。

# 設計 — Archive（仮称）と引用ベース provenance

> 目的: C5 の本丸課題「『触れた』と『真偽に依存した』が区別できない → 過剰隔離（precision 0.5）」を、
> **ドキュメント接地＋検証可能な引用**で解決する。アプリ開発という実用文脈（探索は spec/ADR/要件などの文書に依存する）に合わせた再設計。
> 関連: [`experiment-results.md`](./experiment-results.md) §6（過剰連結の実証）、[`findings-mvp.md`](./findings-mvp.md)、[`overview.md`](./overview.md)（EGI/Field Actor）。

## 0. 名前（仮）

役割は「保持 + 引用照合 + 撤回起点」。候補と所感:

| 候補 | ニュアンス | 評価 |
| --- | --- | --- |
| **Archive**（暫定採用） | 記録の正準保管庫 | 分かりやすい。やや受動的（照合の能動性が出ない） |
| Ledger | 追記専用・監査可能な台帳 | provenance と相性◎。文書より「取引」寄りの語感 |
| Reference | 能動的な参照デスク（司書） | 「照合して答える」役割に最も合う |
| Canon | 単一の正準ソース | 短く強いが抽象的 |

本書では暫定 **`Archive`** を使う（後で改名容易）。照合の能動性を強調したいなら `Reference`/`Ledger` を推す。

## 1. なぜこれで本丸が解けるか

現状の弱点: provenance を `depends_on_turns`（＝「前のターンに**応答した**」）で作る。会話的・検証不能・スタンス無視 → 過剰連結。

アプリ開発では依存の正体は **「どの文書のどの箇所に基づくか」**。これは **外部・番地つき・照合可能**:
- 「この推奨は `spec#3.2` に基づく」= 明示的引用。
- 汚染 = 「`spec#3.2` が誤り／撤回」という現実的イベント。
- 撤回時 → **`spec#3.2` を rely-on 引用した主張だけ**を辿れる（反論引用・無関係は除外）。

→ 難問「会話から真偽依存を推測」を、**「引用を辿る＋引用を照合する＋引用ごとに rely/refute を見る」**に置換。対象が一箇所に絞れて遥かに正確。

## 2. Archive — 責務とデータモデル

### 責務
1. **保持(store)**: 文書を**番地つきチャンク**で保持。各チャンクに status/version。
2. **提供(serve)**: クエリ＋関心プロファイルに対し、関連チャンクを**ID付き**で返す（Actor がそれを引用する）。
3. **照合(verify)**: 主張＋引用（chunk_id＋宣言スタンス）に対し、チャンクが実在し、主張のスタンスがチャンク内容に**接地しているか**を判定。幻覚引用・的外れ引用を弾く。← 新規の中核能力。
4. **撤回起点(retract)**: チャンクが誤り/撤回/陳腐化したら status を変え**撤回イベント**を出す。provenance は chunk_id を指すので、撤回伝播 = 「retracted chunk を rely-on 引用した主張（推移）を集める」。

### データモデル（最小）
```
Chunk      { id: "spec#3.2", doc, section, text, status: active|corrected|retracted|superseded, version }
Citation   { claim_id, chunk_id, stance: relies_on|refutes|context, verified: true|false, grounding: float }
ProvEdge   claim --(relies_on, verified)--> chunk        # 主たる接地
           claim --(builds_on)--> claim                  # 二次（claim間）
```
汚染は「`Chunk.status = retracted`」で表現（会話注入でなく文書状態）。状態B = 該当 chunk を corrected 版に。

## 3. 関心スコープの Field Actor（= sensitivity profile の具体化）

experiment-plan の「Field Actor with sensitivity profile」を接地で実装:
- 各 Actor は **profile**（関心: security / legal-consent / UX / perf / data-quality …）を持つ。
- 発言時に Archive へ **profile スコープでクエリ** → 関連チャンク取得 → 各主張に **引用（chunk_id＋スタンス）** を付ける。
- Archive が各引用を **verify** → 検証済み引用のみ provenance 辺になる。
- **無引用の主張は low-grounding として印**（引用を促す/要求）。

副産物: 異なる profile の Actor が**同じ chunk を別スタンスで引く**所＝**介在的懸念（§8.2）**が出る（未検証だった EGI 上りにも効く）。

## 4. 引用ベース provenance と影響/隔離集合

- **affected(retracted chunk X)** = X を `relies_on` かつ `verified` で引用した主張、およびそれに `builds_on` で連なる主張（推移閉包）。
- **除外されるもの**: X を `refutes` で引いた主張（批判は汚染でない）/ 未検証（幻覚）引用 / X を引かない主張。
- これが **「触れた」と「依存した」を分離** ── 引用が **スタンス付き** かつ **ソース照合済み** だから。

旧 vs 新:
| | 旧 `depends_on_turns` | 新 citation |
| --- | --- | --- |
| 単位 | 会話ターン | 文書チャンク（番地つき） |
| 検証 | 不能 | Archive が照合 |
| スタンス | 無視（応答=依存） | relies_on / refutes / context |
| 過剰連結 | 多発（precision 0.5） | スタンス＋照合で抑制（目標 >0.8） |

## 5. 統治（隔離・再評価）への接続
- chunk X を retract → rely-on 推移閉包を quarantine → corrected 版 X' から再導出（repair）。
- Archive の照合が **幻影引用による隔離膨張**を防ぐ（precision 維持）。
- PCE gate は「candidate delta が retracted/未検証 chunk に rely-on 依存していないか」を Archive 照合で判定 → durable state 混入前に止める。

## 6. 詰めるべき設計判断（推奨つき）

1. **retrieval（serve の方式）**: キーワード / 埋め込み / LLM。**推奨: まず LLM+チャンク列挙（小規模）→ 後で埋め込み**。
2. **引用スタンス分類**: 最小 `{relies_on, refutes, context}`。**推奨: この3値**（rely と refute の分離が肝）。
3. **照合(verify)の機構**: 「chunk X は主張Yの relies_on を支持するか？」を grounded NLI 的に LLM 判定。**推奨: per-citation の二値判定**（対象が狭く高信頼が見込める。IRR 1.0 だった anchored 判定と同種）。
4. **暗黙依存（無引用で内面化）**: 引用必須にするか。**推奨: 引用を強制し、無引用主張は gate で要根拠フラグ**（接地を設計で担保）。
5. **profile カバレッジ**: 全 chunk がいずれかの Actor scope に入るか（盲点防止）。**推奨: カバレッジ検査＋"汎用" Actor で取りこぼし回収**。
6. **チャンク粒度**: 文書/節/段落。**推奨: 節〜段落**（番地の有用性と量のバランス）。

## 7. ハーネスへの実装マッピングと検証計画

- 新モジュール `Tracefield.Archive`（scenario 文書を chunk 化、`serve/2`, `verify/2`, `retract/1`）。
- scenario をチャンク化（既存の task.md＋汚染fixtureを「文書チャンク」に再構成）。汚染B = PM証言チャンク（status: 状態Bで retracted）。
- C5' 探索: 接地 Field Actor（profile クエリ＋引用）。provenance = 検証済み citation 辺。
- 既存 `measure/remeasure` を **citation ベース affected_set** に差し替え。

**安価な決定実験**: 汚染B（採用される型）を Archive チャンク化し、引用ベース C5' を回す →
**precision が 0.50 から上がるか**（過剰連結が解消するか）を `remeasure` で測る。
旧 `depends_on_turns` C5 と同一探索で比較できれば理想。

## 8. 残るリスク
- **引用の乱発**が文書引用として再発しうる → Archive の照合(verify)で裏取れない引用を落とすのが防波堤。
- **「引用して反論」** の判定品質（relies_on vs refutes の誤り）が新たな誤差源。
- 接地できない種類の懸念（横断的・暗黙的）は引用に乗らない → 無引用フラグ＋汎用 Actor で部分回収。
- permissive 汚染（C型）の測定問題（§6h）は別途（判定器側の課題で本設計の射程外）。

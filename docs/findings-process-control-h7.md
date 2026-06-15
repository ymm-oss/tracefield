# H7 設計 — 統治可能なプロセス制御の汎用性（未実証）

> 由来: 2026-06-15 セッションの対話（「合成層の上にプロセス制御層 → 統一プロセス（issue 詳細化〜実装〜QA）」→「それは汎用的にプロセスを制御できるのか？」）。
> 前提整理は [`frame-problem.md`](./frame-problem.md)（§1 二つの frame、§2 ramification、§4 store 価値の比例則）。
> 本書は**設計レベル（未実証）**。frame-problem §5 と同じく、実証済み機構の上に立つが H7 自体は仮説。

## 0. 一行

> 制御層（ステージ遷移・ゲート・ramification 閉包・動的ギャップ検出）は、**正当化構造を持つ知識プロセスのクラス**に対して領域汎用である。構造的に異なる第2プロセスが、**ステージ固有の制御コードを足さずに**同じインタプリタへ通り、型付き閉包伝播とギャップ検出がそのまま効く——を反証可能に検証する。

これは frame-problem §1 の**開発期＝動的フレームギャップ検出（実機構）**に対する汎用性主張であり、研究期 Frame Revision（未実証）ではない。混同しない。

## 1. 仮説と反証条件

**H7（主張）**: process spec をデータ化し 1 つのインタプリタで解釈すれば、機構は領域非依存になる。証拠の方向: 研究系(hetero)と開発系(dev)が既に同一 store に同居している（領域語彙を含まない基盤）。

**反証条件（どれか1つでも起きれば、その地点が汎用性の境界）**:

- **F1（機構汎用の否定）**: 第2プロセス B を通すのに、spec データ＋プロンプト以外の**制御コードの追加**が要る。→ どの分岐が領域固有だったかが境界。
- **F2（閉包の破れ）**: B で layer-0 entry を撤回しても、閉包が依存下流を**正しく隔離できない**（漏れ＝over/under-isolation）。→ 依存が provenance 外に漏れた点が境界。
- **F3（型無視の破綻）**: 均一閉包で十分＝edge-type が要らない、または逆に型付けても誤る。→ 型付き閉包の設計が領域依存なら境界。
- **F4（ギャップ検出の不転移）**: Coverage/Patrol（無人論点・未回答老化・動員率）が B で再調整なしには無意味な発火しかしない。→ ギャップ規準が dev 固有だった証拠。

反証されなければ「正当化構造を持つプロセスのクラスに対して汎用」が機構レベルで立つ。

## 2. データ化対象（現状の直書き制御）

`lib/mix/tasks/tracefield.dev.ex`:

| 直書き箇所 | 内容 | spec 化後 |
| --- | --- | --- |
| L75-101 `cond` | `state["stage"]×["status"]` 分岐 | 汎用 state machine が spec から導出 |
| `start_/resume_*`（refine/design/implement/qa） | ステージ別関数 | 1 つの `run_stage(spec_stage, …)` |
| `@refine_procedure`/`@design_procedure` | ステージ固有プロンプト | spec の `procedure` フィールド |
| 順序 refine→design→implement→qa（直書き） | 遷移 | spec の `stages`/`transitions` |
| `@gate_entry_types`, `meta: %{stage:}` | ゲート対象型・層タグ | spec の `produces`/`gate` |
| 「decision は requirement を引用」（@design_procedure） | edge | spec の `edges`（型付き） |

## 3. process spec（提案スキーマ）

```
%ProcessSpec{
  name: "dev" | "evidence" | …,
  stages: [
    %Stage{
      id: "refine",
      procedure: "...",                  # 器官への手続き（プロンプト）
      produces: [:requirement, :question],
      cites: [%Edge{type: :grounds, into: :reference_doc}],
      gate: %Gate{review_types: [:requirement, :question], verdicts: [:approve, :amend, :reject]},
      on_done: "design"
    }, ...
  ],
  closure: %{                            # 型付き ramification（F3 の肝）
    grounds:        :invalidate,         # 根拠撤回 → 派生を無効化
    realizes:       :invalidate,
    verifies:       :reopen,             # 実装撤回 → QA は無効化でなく再オープン
    corroborates:   :weaken,
    contradicts:    :flag,
    supersedes:     :replace
  }
}
```

インタプリタは spec を解釈するだけ。`closure` マップが H6 接地ゲート＋撤回閉包を**型付き**に一般化する（均一閉包の誤りを排す）。

## 4. 実験構成（A=対照 / B=処置）

**Step 0（リファクタ）**: 上記 spec＋1 インタプリタを実装。`dev` を spec として再表現。

**Step A（回帰＝対照）**: `dev` spec が既存ハードコード版と**識別的に同一挙動**（同 issue で同 entry/ゲート/撤回挙動）。データ化が挙動を変えていないことの担保。これが通らなければ H7 以前。

**Step B（処置＝第2プロセス）**: 構造的に異なる知識プロセスを spec のみで投入（制御コード追加ゼロが目標）。

### 第2プロセス案: エビデンス統合／監査（frame-problem §5 の射程内）

```
intake → extract(claim) → corroborate → synthesize → audit
```

- ステージ数も型も dev と異なる: edge は `corroborates`/`contradicts`/`supersedes`（dev の `grounds`/`realizes`/`verifies` と別集合）。
- ゲート意味が異なる: `contradicts`/`supersedes` が来たら下流 synthesize を**再オープン**（dev の APPROVE/AMEND/REJECT とは別の遷移）。
- これにより F1・F3・F4 を同時に試せる（dev 固有でない型・遷移・ギャップを要求する）。

## 5. 測定（反証可能メトリクス）

| ID | 測る | 合格の向き | 対応反証 |
| --- | --- | --- | --- |
| M1 | B 投入で追加した**制御コード行数**（spec/プロンプトを除く） | 0 に近いほど機構汎用 | F1 |
| M2 | B で layer-0 撤回 → 依存下流のみ隔離（precision/recall） | H4/H6 並み（精密隔離） | F2 |
| M3 | 均一閉包 vs 型付き閉包で `supersedes`/`verifies` の挙動差 | 型付きのみ正、均一は誤 | F3 |
| M4 | Coverage/Patrol が B で**再調整なし**に有意発火（無人 claim・老化未照合・動員率） | dev と同規準で意味を持つ | F4 |
| M5 | B が provenance 外に漏れた点の列挙 | 境界の明示（正直な negative） | 全般 |

## 6. 限界（先に宣言）

- 機構レベル・少 seeds・単一〜少数シナリオ。**統計的断定ではない**（conclusions §5 と同基準）。
- 検証対象は frame-problem §1 の**動的フレームギャップ検出**に限定。研究期 Frame Revision は射程外（未実証のまま）。
- 汎用性の主張は「**正当化構造を持つ長尺・多 agent・撤回監査が要る知識プロセス**」のクラスに限定。短命・操作系ワークフロー（CI/ETL）は frame-problem §4 により射程外——そこは古典ワークフローエンジンが優位で、本層を当てても旨味なし。これは限界でなく**設計上の境界**。

## 7. 実装方針

- Claude: spec スキーマ＋インタプリタ骨格＋ Step A 回帰の足場、検証。
- 重い実装は codex に委譲（[[delegate-impl-to-codex]]）。
- まず Step 0＋A（dev の spec 化と回帰）を最小で通し、B は spec のみで追加——B 投入時の制御コード増分（M1）が H7 の中核証拠。

## 8. 実測（Step B）【実証】

> 2026-06-15 実装・実測。Step 0+A（`ProcessSpec`/`ProcessInterpreter`、dev の spec 化、回帰 257 green）の上に、第2プロセス「エビデンス統合/監査」を投入。
> 実体: `lib/tracefield/evidence.ex`（spec＋executor、484行）/ `lib/mix/tasks/tracefield.evidence.ex`（runner、36行）/ `test/evidence_process_test.exs`（99行）/ `lib/tracefield/reference.ex` に型付き閉包エンジン（`retract_typed`/`typed_closure`、+182行）。
> 第2プロセス: `intake → extract → corroborate → synthesize → audit`。edge/stance 型 `corroborates`/`contradicts`/`supersedes`、ゲートは `corroborate`/`audit` に `:reopen` verdict。adapter=mock で決定的。`mix test` = **263 passed**（Step A 257 ＋ B のテスト6本、全緑）。

### 結果

| ID | 測定 | 結果 | 判定 |
| --- | --- | --- | --- |
| **M1** | B 投入で追加した制御コード | **`ProcessInterpreter` 変更 0 行**（mtime が Step A 時点のまま）。追加は (a) 共有機構＝型付き閉包エンジン 182 行（領域非依存・一回限り、`ProcessSpec` を受け取り stance ごとに閉包適用）と (b) プロセス内容＝spec/executor/runner/test 619 行のみ | **F1 非該当**。制御は領域汎用——別構造のプロセスが制御ロジック無変更で同インタプリタを通った |
| **M2** | 下層撤回 → 依存下流の隔離 | precision **1.0** / recall **1.0**（誤隔離 0・隔離漏れ 0）。撤回で `[e10,e4,e6]` のみ隔離、加えて reopened 1・flagged 1・weakened 1 | **F2 非該当**。H4/H6 並みの精密隔離が第2プロセスでも成立 |
| **M3** | 均一閉包 vs 型付き閉包 | `supersedes`: 型付きは置換後 entry を **active** 維持（正）、均一は **superseded**（誤）。`verifies`: 型付きは audit を **再オープン**（正）、均一は audit を **superseded**（誤）。両ケースで `uniform_wrong=true, typed_correct=true` | **F3 非該当**。型付き閉包が必要十分——均一は誤り、型付きのみ正 |
| **M4** | Coverage/Patrol の転移 | `meaningful_fire=true`：unowned_claim 警告 2・stale_question 警告 1・patrol セクション 2（非空スライス）。**再調整なし**に第2プロセスで意味ある発火 | **F4 非該当**。動的ギャップ検出は dev 固有でなく転移する |
| **M5** | provenance 外への漏れ | `provenance_leaks=0`。ただし境界2件を明示（下記） | 境界の明示（正直な negative） |

### 汎用性の境界（M5、正直な negative）

1. **型付き閉包は明示 citation しか見ない**——未引用の意味的依存（暗黙の前提）は provenance の外＝制御層から不可視。frame-problem §2 の「frame を外部構造に持つ」を裏返した限界そのもの: **外部化された依存の範囲でのみ汎用**。
2. **claim-aging（未回答老化）は audit が question entry を出した時だけ既存検出器に乗る**——プロセスが「未解決」を question 型で表現しない設計だと、その経路のギャップ検出は効かない。ギャップ規準は完全には型非依存でない。

### 結論（実証レベル）

H7 の中核——「制御層（順序・ゲート・遷移・型付き ramification 閉包・動的ギャップ検出）は正当化構造を持つ知識プロセスのクラスに対し領域汎用」——は、機構レベルで **F1〜F4 いずれも反証されず成立**。構造的に異なる第2プロセスが、**インタプリタ無変更（制御コード増分 0）**で通り、型付き閉包の精密隔離（M2 P/R=1.0）・型付きの必要性（M3 均一は誤）・ギャップ検出の転移（M4）が確認された。追加されたのは「プロセス内容」と「一回限りの共有機構（型付き閉包エンジン）」のみ。

境界（M5）は frame-problem の予測通り: **provenance に外部化された依存の範囲でのみ汎用**で、未引用の意味的依存とプロセス非標準なギャップ表現はその外。これは限界というより**設計上の射程**であり、frame-problem §4（store 価値の比例則）と整合する。

実証は mock・単一シナリオ・seeds 少の機構デモであり統計的断定ではない（conclusions §5 と同基準）。

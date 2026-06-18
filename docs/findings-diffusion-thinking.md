# Diffusion 的思考 知見 — 反復denoise と 半自動クラスター→統合

> 「人間の思考は Diffusion 的（全体を部分に還元し、部分ごとに構築し、ぼんやりした全体から
> 最終統合ではっきりした全体が浮かぶ）。これを tracefield で実験できるか。クラスターを使う形で
> ないと検証できないのでは」を検証した結果。日付: 2026-06-18。モデル: `claude-sonnet-4-6`（CLIアダプタ）。
> 姉妹ドキュメント [findings-lens-type.md](./findings-lens-type.md)。生 run は `runs/lens-diffu*.report.md`（`runs/` は gitignore）。

## 0. 結論（要旨）

1. **Diffusion には2つの読みがあり、どちらも tracefield で再現でき、`cluster` プリミティブの書き換えは不要だった。**
   - 反復読み（各部が全体に条件づけられ反復精製）＝ `[long_run] cycles` ＋ 自己参照入力。
   - 構造読み（全体→部分→半自動クラスター→統合）＝ scatter ＋ 正規化 actor ＋ 決定論 cluster（無改造）＋ synthesis。
2. **ピア反復は mode collapse（多数派吸収）を起こさない。** 単一統合者(SYNTH)に集約する構造こそが collapse の原因であり、反復精製の性質ではない。
3. **「半自動クラスター発生」は3つの最小要素に分解される。** 一枚岩の意味クラスタラーに書き換えるより、(a)創発ラベル生成 / (b)単一の心による意味統合 / (c)決定論グルーピング を分離する方が優れる。[findings-lens-type.md](./findings-lens-type.md) の「一枚岩LLM合成のconfabulation」と同じ罠。

## 1. clusterプリミティブの正体（事前確認）

- `cluster` は **メタデータ（path/kind/author/source 等）による決定論的グルーピング**。LLM も埋め込みも使わない（`deterministic_cluster_entries`）。意味（テーマ）でまとまらず、反復精製ループも無い（resume時キャッシュ）。`cluster:` 入力セレクタは無く、下流は `stage:<clustering-stage-id>` で引く。
- **actor は出力エントリの `meta` を自由に書ける**（`parsed_stage_entry_meta`：モデルの `meta` 全キーをそのままコピー、フレームワークは `kind` を上書きしない。コードベース自身が `meta {"kind":"process_decision"}` をモデルに出させている）。決定論 cluster は `by=["kind"]` で出自を問わずそれを束ねる。
- → 意味的クラスタリングは `cluster` の責務ではなく **reasoning（actor）の責務**。書き換えではなく stage 構成で表現する。

## 2. 反復読み: long_run cycles = denoise（実験 lens-diffusion）

発散題材（顧客データ第三者収益化 A/B/C）× 6レンズ（BE/FIN/TOC/REVERS/DEONT/PHENO）× `cycles=4`、`inputs=["path:task.md","stage:analysis"]` で全エントリを累積再読込（cycle1→4で inputs 0→12→24→36）。中立（anti-collapse 指示なし）。

- **decision は割れない**: 全6レンズ全4サイクルで B（支配的妥協案がある収束題材では既知）。信号は decision でなく推論軌跡に出る。
- **coherence（相互引用 refs/entry）は1ステップで飽和**: 0 → 1.78 → 1.61 → 1.78。場の相互条件づけは速く立ち上がりプラトー。
- **内容は coarse→fine→過剰denoise**: cycle2=立場ロック、cycle3=最生産的（新規語ピーク＝撤退トリガー/制約昇格/自己死角申告など二次精製）、cycle4=飽和（限界情報≒0）。**スイートスポット約3サイクル**。
- **mode collapse は起きない**: 前回 synthesis ステージは PHENO を数え落としたが、ピア反復では PHENO は4サイクル全てで現象学語彙を保持し自分の死角を自己申告。**collapse は反復でなく単一統合者への集約の性質**。脳の Diffusion 直感（各部位が全体に条件づけられ更新）はピア反復に正確対応し、その構造こそが合成ボトルネックを回避する。

## 3. 構造読み: 半自動クラスター→統合（実験 lens-diffuse-cluster）

題材＝churn悪化分解。`scatter`(4 actor が多数の微細断片を放出、各々**自分で** `meta.kind` を創発付与) → `cluster`(`by=["kind"]`, `mode=none`, `min_cluster_size`/`max_clusters` で裾整流) → `SYNTH`(`stage:cluster`＋`stage:scatter` 併読で統合)。

### 3a. ベースライン（正規化なし）: 4段の解像度上昇は再現、だがクラスター品質が脆い

- 28断片（ぼんやり）→ 6テーマ（中間構造）→ 優先施策TOP3（はっきり）。構造は Diffusion そのもの。
- **だが決定論 exact-match は意味的同義語を併合できない**: `価格競争` と `価格競争力` が1文字違いで分裂、**組織KPI根本原因**が `組織インセンティブ/設計/構造/KPI` の4 singleton に飛散し `small_sources`（ゴミバケツ）へ流出。チャンピオン離脱も同様。**課題が明示した根本原因がクラスター層で消失**。
- **品質を救ったのはクラスターでなく SYNTH**: 根本原因を拾えたのは SYNTH が生断片（`stage:scatter`）を併読したから。この配線では**クラスター層は半ば飾り**。クラスターのみ（生断片を渡さない per-cluster 統合）なら根本原因は黙って失われた。

### 3b. 正規化 actor 版: クラスター層が load-bearing 化（決定的改善）

`scatter`↔`cluster` 間に **NORM（単一 actor）** を挿入。NORM が全断片を俯瞰し正準テーマ(5±2)を自分で決め、各断片を正準 `kind` に付け直す → cluster は `stage:norm` を束ねる。

| | ベースライン | 正規化版 |
|---|---|---|
| ラベル数 | 12（飛散） | **6 正準テーマ** |
| ゴミバケツ | small_sources(7) に根本原因流出 | **ゼロ** |
| 組織KPI根本原因 | 4 singleton → small_sources | **組織設計(3)＝独立クラスター** |
| チャンピオン | 飛散 → small_sources | **顧客継続性(2)＝独立クラスター** |
| 価格表記揺れ | 価格競争／価格競争力に分裂 | **価格競争力(6)に統合** |
| 根本原因の扱い | SYNTHが生断片で救出（層は飾り） | **クラスター層がsurface、SYNTHは「根因=組織KPI設計」と明示命名** |

最終 TOP3 も痩せず構造化が鋭化（営業KPI+NRR+チャンピオン検知が第一級施策へ昇格、価格施策は理由付きで4位降格）。

## 4. 半自動クラスター発生の分解（持ち帰り）

「半自動クラスター発生」は次の3最小要素に分かれ、各々を分離して最小に保つのが要：

| 要素 | 担当 | 性質 |
|---|---|---|
| (a) 創発的ラベル生成 | 並列 scatter（多数の心） | ぼんやりした多様な断片 |
| (b) **意味的統合** | 単一 NORM（一つの心が全断片を俯瞰） | **これが「半自動発生」の正体＝人間のDiffusion** |
| (c) 決定論グルーピング | 既存 cluster（無改造） | クリーンな束ね |

`cluster` を意味クラスタラーに書き換える一枚岩は、意味的判断（NORM/SYNTH）とメカニカル処理（決定論 cluster）を混ぜる点で [findings-lens-type.md](./findings-lens-type.md) の合成 confabulation と同型の罠。**意味判断とメカニカル処理を分離する**のが設計原則。コード変更ゼロでこれを実現した。

## 5. 真の対立題材: ピア反復 vs 中央集権SYNTH（実験 lens-conflict）

支配的妥協案の無い二択題材（買収受諾A / 独立維持B、48時間・不可逆）× 6レンズ。初めて decision が**割れた**（A=FIN/REVERS系 vs B=BE/TOC/DEONT/PHENO）。同一題材で peer 反復版（cycles, synthなし）と中央集権版（analysis→SYNTH、6レンズ列挙ガード付き）を比較。

### peer 反復
- **多様性保持**: FIN は5対1の圧でも A を4サイクル堅持＝**collapse しない**。
- **弁証法的移動**: REVERS が cycle4 で「目的関数＝ミッションの組織にとり A のオプション価値≈0」と再計算し A→B へ反転。
- **共有条件への構造化**: B 派が「48時間以内のブリッジ調達を必須前提」へ収束。FIN は退路（ブリッジ失敗→A）を保存した**立っている少数意見**として残る。
- 成果物＝**保存された対立を含む条件付き構造**。

### 中央集権 SYNTH（6レンズ列挙ガード付き）
- **今回は collapse しなかった**: ガードで6レンズ全列挙・各々の核/一面性を articulate、脱落ゼロ。
- **最強の止揚洞察**: 「DEONT の義務の相手方（財団・コミュニティ）は REVERS が懸念する資金リスクの**緊急資本源でもある**＝義務と調達機会が同一ステークホルダーに収束」。peer の「ブリッジ調達」より**誰が出すか**を特定した鋭い綜合。
- **ただし confabulation リスク**: 「調達確率が40%を上回る余地」は約束の相手＝資本源という**未検証の推論的飛躍**。peer の一般的条件の方が誠実。少数意見 FIN は「交渉圧力として保持」へ**溶解**（立つ少数として残らない）。

### 決着

| | peer 反復 | 中央集権SYNTH（ガード付） |
|---|---|---|
| collapse | しない（FIN堅持） | 今回はしない（ガード奏功） |
| 少数意見 | **立つ少数として保存** | 脚注へ溶解 |
| 綜合の鋭さ | 一般的・控えめ | **鋭い洞察を産むが未検証の飛躍リスク** |
| confabulation | 起きにくい | 起きうる（鋭さの代償） |

前回（収束題材・ガードなし、[findings-lens-type.md](./findings-lens-type.md) §5）SYNTH は collapse・PHENO脱落・confabulate したが、今回（対立題材・ガード付き）は collapse せず鋭い綜合を出した。→ **SYNTH の失敗は「鋭いテーゼ対立がある＋全列挙ガードがある」で緩和される。だが鋭い綜合は未検証の飛躍を含みうる。** findings-lens-type の「最終結論は LLM 再合成でなく機械的集約で」と整合：peer 反復の**保存された立つ少数＋共有条件**こそが durable な成果物。

## 6. 留保

- 単一モデル(sonnet)・題材各1・小 n。一般化には別題材/別モデルでの再現が必要。
- 中央集権 SYNTH の非collapseは1 run。ガード有無 × 対立鋭さの2×2を詰めていない。
- exact-match の表記揺れ問題は日本語の語形に依存。別言語・別粒度での再現未了。

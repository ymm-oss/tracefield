# 結果 — コマンドプローブ（決定論コマンドステージ）と in-flow fslc ゲート

> 日付: 2026-06-20。
> 問い: 外部ツールの判定を「フロー後シェル（realize.sh）の ephemeral な exit code」でなく
> 「フロー内の決定論ステージが生む retractable な provenance エントリ」にできるか。
> fsl-codespec の fslc 検証（コード→FSL 抽出の第二の機械裁定）を最初の application に検証。

## 実装

新しい決定論ステージ `[stages.<id>.command]` を **clustering の兄弟**（`mode="none"` の非 LLM 経路）として追加（`flow.rs`、~150行＋テスト2本、**read 側改修ゼロ**）:

- 選択エントリ（`inputs` セレクタ）の本文を一時ファイルに materialize → `args` 内の `{input}` をそのパスに置換 → コマンドを1回実行 → stdout を1エントリ本文、exit を `meta.exit_code`、**選択エントリを引用**。
- **非ゼロ終了は所見**として記録（spawn 失敗・timeout のみ run を止める）。`[actors] mode="none"` 必須（LLM actor / clustering と排他）。
- probe = **センサ（計測）であってレンズ（解釈）でない**。LLM 不使用＝confab 原理ゼロ＝鉄則2「全モデル呼び出しを忠実な小規模域に留める」の極限点。
- fsl-codespec: realize.sh（フロー後の placement＋check）を畳み、段7 `fslc_gate`（assemble の ```fsl を awk 抽出 → `fslc check`→`fslc verify`）に統合。realize.sh 削除。`.fsl` は使い捨て検証物、正準仕様は ASSEMBLE synthesis エントリ。

## 結果（クリーン run・実 codex-app-server ＋ 実 fslc・2026-06-20）

| stage | actors | entries |
| --- | --- | --- |
| evidence / spec_draft / verify | 3 / 3 / 4 | 21 / 54 / 41 |
| gate_grounding / adjudication / assemble | 1 / 10 / 1 | 11 / 62 / 30 |
| **fslc_gate** | **0** | **1** |

- **機能成立**: fslc_gate は単一 active エントリ（e226, `kind=command`, exit 0, 引用=assemble synthesis）。フェンス抽出→check→verify が実 fslc で通った。
- **閉包/status が probe 判定にも効く（不変条件②）**: `reconcile_overturned` が4反証を overturn → 閉包 28/57/6/20 を `retract`（226件中 **115 retracted / 111 active**）。別の resume run では、基盤 synthesis が overturn 連鎖で退場すると**その上の旧 fslc 判定エントリも自動で `retracted`**（e201→e237）になり、新判定だけ active で残ることを確認。**probe が入力を引用するから stale な検証結果が live 集合に居残らない**＝設計通り。
- **ゲートが vacuous green を捕えた（2 run 再現）**: 仕様は `check: ok` / `verify: verified`(bounded, depth 8) だが、警告 **"spec declares no user invariants (only implicit type bounds are checked)"** ── `invariants_checked` は型境界 `_bounds_status` のみ。

| run | 生成 spec | user invariant | fslc |
| --- | --- | --- | --- |
| resume | `T` | 0 | ok / verified（警告。集合モデルだが contract 無し） |
| clean | `EntryStatusDesign` | 0 | ok / verified（警告。`state{status}` 単一＝検証対象ゼロ） |
| **desc調整** | **`S`**（集合＋id＋`superseded_by`） | 0 | ok / verified。**supersede の `ensures st[n]==old(st[n])` を BMC 実証** |

（注: 本会話前の run の `TracefieldEntryStatus` が持っていた `ReplacementReferenceExists`〔置換先は常に Active〕は **過剰主張**だった ── desc 調整版でエージェントが再検査し「supersede に置換先 Active の guard が無い」として拒否、検証可能な `ensures`〔置換先 status 不変〕に降格。fslc は `ensures` を強制する〔偽 `ensures` は `violated`/`ensures` で検出、別途確認済〕。）

## 判定 — in-flow command probe は成立。fslc "verified" は必要条件であって十分条件でない

- **外部ツールの判定が retractable な provenance エントリになり、closure/status がそれを統治する。** フロー後シェル（realize.sh）の exit code が監査グラフの外にあるのと対照的。realize.sh を畳んでも不変条件①②③は保たれる（決定論ライターは agent でない／closure が判定エントリに乗る／repair は可視の再実行）。
- **ゲートの "no user invariants" 警告が vacuous green を機械的に露出**する（post-flow で exit-0 だけ見ると見逃す）。これが in-flow ゲートの価値で、scenario が戦う「緑-by-emptiness」を機械裁定側から捕まえる。
- **vacuous green は2層**: (a) **モデル粒度** ── 単一 `status` 抽象は検証対象ゼロ。SPEC/ASSEMBLE desc に「不変条件を表現できる粒度でモデル化し接地済み安全性質を `invariant` 句で含めよ／捏造禁止」を追加で修正でき、モデルは集合＋id＋`superseded_by` に改善した。(b) **強 invariant の非接地** ── "replacement 常に Active" はコードに guard が無く偽。これは desc で潰せず、潰すべきでもない（エージェントが正しく拒否し、検証可能な action `ensures` に接地するのが正解）。
- **fslc の検証実質は `invariant` だけに宿るのではない**: desc 調整版は standalone invariant 0 本のまま、supersede の `ensures`（置換先 status 不変）を BMC 実証した。"no user invariants" 警告は必要シグナルだが十分でない（`ensures`/`requires` 契約も実質）。残る伸びしろ: 真に接地した standalone 不変条件（"置換先は存在する"＝entry は除去されない）と retract action は未記述。ただし desc で押し込むと著者が spec を設計してしまう＝接地原則と緊張するため、ここで止める。
- **粒度の制約**: fslc は組み上がった全体仕様にのみ効く → 段は assemble の後段に固定。断片段（verify 等）には挿せない。

# findings: TS-TDD on qwen3.6（強モデル=契約 / qwen多数=実装 / TSゲート=機械審判 + 下位レイヤー再突入）

実験日: 2026-06-24〜25。harness とベンチは `scenarios/ts-tdd-qwen/`（昇格元は使い捨ての探索 harness）。
問い: **ローカル qwen3.6 でコーディング課題に十分対応できるか。最も効果的な使い方は何か。出力が悪い時に下位レイヤーへ戻って再突入する fallback は機能するか。**

計器: kata = `spec.md` + 可視契約 `contract.test.ts` + **held-out**（gaming/過適合検出、実装者に見せない）+ `reference.ts`（オラクル妥当性）+ `signature.ts`（型ゲート）。
機械ゲート = `tsc --noEmit`（型）+ `node --test`（挙動）+ 禁止API走査。LLM 審判は使わない（テスト/コンパイラが審判）。
モデル呼び出しは tracefield と同じ ollama 経路（`/api/chat`, stream=false）。

## 1. 結論

- **qwen3.6 は well-specified な小〜中規模の単一関数に既に十分。** 失敗点は「アルゴリズム/仕様の難しさ」ではなく「単発生成の物理（推論量×コード量）」。
- オーケストレーション（多数候補 + ladder）の価値は *能力の底上げ* より **信頼性・gaming 検出・回復・来歴の統治**。
- fallback ladder（repair→plan→scaffold、非改善ごとに下位レイヤー再突入）は**実証済**（seeded 不良実装→repair→PASS）。

## 2. 素の実力（adequate の根拠）

| kata | 難度 | 35b-mlx | 27b / gemma4b |
|---|---|---|---|
| wildcard（LeetCode-44 DP）| 高 | pass@1=1.00, held-out PASS | 27b 1発 |
| rpn（ゼロ方向切り捨て除算の罠）| 中 | pass@1=1.00, held-out PASS | 27b・gemma4b も 1発 |
| titlecase（AP式タイトルケース, prior に反する）| 中 | calls=1, held-out PASS | 27b 1発 |
| json パーサ（自前, ~80行, `JSON.parse` 禁止）| 高 | 3/4 正解, 1個 gaming | — |
| regex エンジン（部分集合, backtracking, ~120行）| 最高 | **pass@1=0/5** | — |

教科書級アルゴリズムも、prior に反する非標準仕様（罠RPN・AP式）も、最初の1候補で通る。罠を明示した仕様なら確実に追従する。

## 3. gaming は強モデルでも実在 → held-out 監査が load-bearing

35b の json 候補の1つが**可視6/6を通過したのに held-out で失敗**した。可視契約の被覆が正しさの上限を決める（＝契約がボトルネック）。best-of-N + 機械ゲートが「ある候補が通った」を作り、held-out/over-fit 監査が「正しい候補が選ばれた」に格上げする。

## 4. 最も効果的な使い方（レシピ）と非自明なツーリング知見

レシピ: ①実行可能なテスト契約=ゲート ②best-of-N（戦略レンズで*構造的*多様性。温度だけだと mode-collapse） ③機械ゲートで選別 ④held-out/over-fit 監査 ⑤fallback ladder。

決定的だったツーリング知見（これが無いと「論理の失敗」と「ツーリングの失敗」を取り違える）:

1. **`think=true` が非自明コード生成に必須（最大のレバー）。** `think=false` だと qwen は*コードの中で推論*する——インラインの自己訂正、`// Wait, this is wrong`、パーサ/マッチャの**二重定義**を実観測。結果は肥大・truncation（~15k字で途中切れ）・破綻。「scratch を書くな」という指示では抑制できなかった。thinking を別チャネルに出して初めて `message.content` がクリーンな完成コードになる。**tracefield は `llm.rs` で `think=false` をハードコード**。
2. **`num_ctx` は 8192 では狭い。** 非自明な関数のコード＋repair 文脈（壊れたコード全文＋失敗テスト）が 8k を超える。
3. **`node --test` の既定（strip-only）は `enum`/`namespace` で落ちる。** モデルは AST に `enum` を多用する。`--experimental-transform-types` で全 TS を変換実行しないと、論理ではなく**ツーリング**で失敗し、それを論理失敗と誤認する。
4. **truncation 耐性の抽出**（終了マーカー欠落でも先頭マーカーを剥ぐ）。
5. **単発生成の天井。** regex エンジン（~120行）は 35b-mlx の1コール能力を超える: `think=false`→コード内推論で肥大破綻、`think=true`→推論がトークン枠を食って**コード空**。重い推論＋大量コードの単一関数は1-shot 不可。→ **各生成単位を小さく保つ＝分割（下位レイヤー）**が答え。これは ladder の plan/scaffold が押す方向と一致する。

## 5. fallback ladder の実証（下位レイヤー再突入）

qwen は小課題で自然に失敗しないため、**不良実装を seed** して回復を測った:

```
rpn, seeded buggy（floor除算 / 剰余符号 / エラー処理なし）:
  SEEDED: tc=True test=False fails=2/5   （toward-zero と error の可視テストに失敗）
  → attempt0 [repair]: tc=True test=True fails=0/5 → PASS, held-out PASS (0/6)
```

repair（L3, 失敗テストを投入して再突入）1回で、`Math.trunc` の再導出・剰余符号修正・エラー処理追加に至り回復。repair で済まない場合に備え、`score`（通過テスト数で順位付け）の非改善を検知して **repair(L3)→plan(L2, 診断+方針)→scaffold(L1, 既知 approach 付与)** と1段ずつ降りる escalation を実装済。regex のような単発不能課題ではこの深い段が効く（が、本機では生成コストが大きい）。

### L0 spec-enrichment 再突入（実装: `scenarios/ts-tdd-qwen/`）

ladder の最深段として **L0（仕様への反映）** を engine 内に実装した。複数候補の*相補的な部分成功*（候補Aは数値比較を、Bは0埋めを通す等）を、コード断片として継ぐのでなく **仕様の一般制約として蒸留**し、仕様を明確化して再生成する。

- **per-test 行列**: `gate.py` が `node --test --test-reporter=tap` で候補×テストの通過行列＋union coverage を出す（どのテストが「ある候補で通る」／「どの候補でも通らない」か）。複数候補に散在する長所が可視化される。
- **distill 段（codex）**: 行列＋候補＋仕様から、通過/失敗パターンが示す*一般制約・曖昧点の固定*を clarification として抽出。**テストの入力→出力値の引き写しは禁止**（teaching-to-test＝gaming の密輸入）。抽出は「仕様に述べてあるのに適用漏れした原則」or「分岐が露呈した真の曖昧点を仕様文言に接地」に限定。
- **再突入**: `long_run`（有界サイクル）で contract→implement を再実行。clarification は `stage:distill` で次サイクルの implement と contract に入り、仕様 S'（不変の原 spec ＋ 撤回可能な明確化層）として反映される。間違った明確化は retract で閉包無効化＝来歴の核がそのまま効く。
- **gaming の番**: clarification を一般制約に限定＋ held-out 監査（最終 audit）が teaching-to-test を捕える。
- **engine 順序の発見**: `[long_run]` の**非サイクル段は cycle の後に `reason=final` で走る**。よって gate より前に必要な段（contract/contract_gate）は cycle_stages に入れ、最後に走る audit だけ非サイクルにする。

> 判断の集約（findings）は相補的所見を*全保持*するが、コードは*単一の整合成果物*が要る。L0 はその差を吸収する——相補性は「仕様についての判断」に蒸留して保持し、コードへの collapse は検証済みゲートの所だけで起こす。

## 6. tracefield への含意

- **統治＋有界L0再突入は engine、条件分岐 ladder は harness。** L0 spec-enrichment の再突入（distill→仕様明確化→再生成）は*無条件・有界*なので `long_run` で engine 内に置ける。一方、gate 結果に応じて層を選ぶ *条件分岐* ladder（repair/plan/scaffold）は engine に exit_code 分岐・long_run 早期終了が無い（[command-probe](findings-command-probe.md) と同じ制約）ため **行為連鎖**として harness で回す。engine が連ねるのは判断（契約健全性・over-fit 反証・仕様明確化・来歴）＝[思考の連鎖であって行為の連鎖でない](../skills/tracefield-flow-design/SKILL.md)という北極星と整合。
- **engine 推奨変更（コード課題向け）:**
  - organ 別に `num_ctx` / `think` / `num_predict` を設定可能にする（現状 `think=false`・`num_ctx=8192` ハードコード。コード課題では think=true・ctx>8k が要る）。
  - command ゲートは候補を**スクリプト内 split** する（command 段は1回・per_input 不可。[fsl-codespec](../scenarios/fsl-codespec/flow.toml) の awk 抽出と同型）。`scenarios/ts-tdd-qwen/scripts/gate.py` がこれを行う。
  - （任意）`exit_code:` セレクタ or "passed" 終端ステータスがあれば、通過候補の選別を engine の read パスに載せられる（現状は keep-logic を command の stdout に置く）。

## 7. モデル選定（現実的なライン）

同一 kata・think=false・単発で能力＋スループットを測った（tok/s が頑健な指標。能力セルは1-shot でノイズあり）:

| モデル | backend/量子化 | mem | rpn | wildcard | json(~80行) | tok/s |
|---|---|---|---|---|---|---|
| **qwen3.6:35b-mlx** | MLX ~4bit(21GB/35B≈4.8bit) | 21GB | PASS/PASS 100s | PASS/PASS 98s | PASS/**gamed** 295s | **7.8** |
| qwen3.6:27b-coding-nvfp4 | nvfp4 | 19GB | PASS/PASS 172s | PASS/PASS 148s | TIMEOUT(>600s) | 3.0 |
| qwen3.6:27b-mlx | MLX 軽量子化(≈5.6bit) | 19GB | FAIL 184s | PASS/PASS 109s | TIMEOUT(>600s) | 3.1 |
| qwen3.6:27b | GGUF 非MLX | 17GB | PASS/PASS 330s | PASS/PASS 236s | (>600s) | 1.9 |

- **現実的なライン = `qwen3.6:35b-mlx`（4bit MLX）。** 速度を決めるのは**量子化レベル × MLX backend であってパラメータ数ではない**: 一番大きい 35b-mlx が最速（積極的な4bit量子化）、軽量子化の 27b-mlx/nvfp4 は ~2.5倍遅く、非MLX 27b は ~4倍遅い。json(~80行) を時間内に出せたのは 35b-mlx のみ（他は全て TIMEOUT）。「小さくすれば速い/軽い」はこの Apple Silicon 環境では成り立たず、27b 群は 35b-mlx の下位互換。
- 能力は小〜中関数では横並び（27b-mlx の rpn 単発FAILは変動の疑い）。差は**長文生成のスループット**に出る。
- 含意: 7.8 tok/s でも小関数=100〜300s／json級=~5分／regex級=非現実的 → **生成単位を小さく保つ（分割）**。「多数の qwen」は単一GPUで直列＝throughput 律速（best-of-5 小kata=~8〜15分）。スループットは「より小さいモデル」でなく**より積極的な量子化の MLX ビルド／別マシン／単位分割**で稼ぐ。

## 8. 大規模化＝分割して振る（decompose-delegate-compose, v1）

救済(ladder)は tail 用で稀。大規模開発の本丸は **「qwen サイズの単位に分割して旨く振る形」**。qwen は小単位に強く、単一関数でも*大量コード＋重い推論*は1コール上限を超える（§5.5）。→ 強モデル(architect)が **安定した界面型＋単位ごとの契約** に分割し、qwen が各単位を*独立に*実装（best-of-N＋単位ゲート）、組み上げて統合ゲート。

**なぜ合成できるか**: 界面を*先に固定*するので各単位は安定契約に対して書け、合成が by-construction で成立する（断片マージ問題＝§「良いところ」議論を回避）。

**v1 実測（算術式評価器 `tokenize→parse→evaluate→calc`、分割は authored、qwen3.6:35b-mlx）**:
- 3単位とも**最初の候補で単位契約 PASS**（tokenize 62s / parse 92s / evaluate 24s、parse=再帰下降で最難だが一発）。
- **統合: tsc(全単位)=ok ＋ 統合テスト PASS → COMPOSED OK**。独立実装の qwen 単位が正しい全体に合成された。
- **対照(baseline, qwen に*全体*を一発実装させる, n=2)**: 両候補とも **挙動は正しい(統合テスト PASS)が strict 型で tsc FAIL** → 全ゲート(tsc+test)を通らず failed。分割版は各単位が型クリーン＋安定界面で **clean PASS**。→ この~80行規模での決定差は『*生成できるか*』でなく『*一貫して strict 型クリーンに保てるか*』(単一コール上限はまず**品質/一貫性**として現れる)。規模が上がると(regex 級)これが『生成できるか』自体に悪化する。**分割は型/品質の一貫性をスケールで回復する。**

**ladder は一段上がる**: 単位が落ちる→*その単位だけ*再生成（安い）。統合/界面が落ちる→**分割そのものへ再突入**（L-arch）。ここで tracefield の **retract-closure が効く**: 界面を retract → 閉包が*その界面を引く単位だけ*を機械的に regen 対象に → 局所再分割。界面＝判断（連ねる/撤回）、単位コード＝行為（qwen に振る/ゲート）。

**ボトルネックの移動**: 単位スケールの「契約品質」→ システムスケールの「**分割の収束性**」（codex が失敗信号から良い分割へ収束できるか＝v2 で検証）。

**v1 の留保**: 分割は authored（codex でない）＝「qwen が*良い分割*を実装し合成できるか」を測った（「codex が良く分割できるか」＋再突入は v2）。失敗が起きず attribution/再突入は未発火（clean ケース）。n=1。実験 harness は本リポジトリ外（非 vendored, 本 findings から再現可能）＝多単位の動的ルーティング/組立/帰属は*行為連鎖*ゆえ harness（engine 統治は v2 の retract-closure 版で効かせる）。

**v2 実測（分割再突入, architect=claude -p, 種=parse の spec を右結合に汚染。実験 harness は非 vendored）**:
```
unit gates: 3単位とも自分の unit 契約 PASS（汚染された parse も自分の右結合契約は通る）
[round 0] integration: tsc+tests FAIL   ← 左結合の統合契約と矛盾＝seam で捕捉
  → architect が統合失敗から flaw を parse に局所化（tokenize/evaluate でなく）
     parse の spec を左結合に修正 → parse だけ regen → unit-gate PASS
[round 1] integration: tsc=ok tests=PASS = CONVERGED（1回の再突入で収束, thrash なし）
```
- **失敗信号駆動の再分割は収束し、かつ局所化される**＝「再突入は分割品質に効く」を実証。architect は無実の単位を触らず、統合失敗だけから真犯人(parse)を特定。
- 局所 regen は harness 版（変更された unit だけ再生成）。tracefield では **retract-closure が同じ局所化を機械的に**与える（界面/spec を retract → 閉包が当該単位だけ regen 対象に）＝productized 版での自然な実装。
- これで「大規模で qwen に振る形」は **分割→委譲→合成→(失敗時)分割へ再突入** の閉ループとして成立。新ボトルネック＝分割の収束性は*再突入で扱える*（一発で当てる必要がない）。
- 留保: 種は authored の汚染（1種類の flaw）。codex を完全 architect にした多種 flaw・thrash 条件・単一 codex 全部との経済比較は未測。n=1。

**経済比較（同 calc 規模, 全体実装/architect=claude, 単位=qwen, held-out 判定, 実験 harness 非 vendored）**:

| arm | pass | strong出力(≈$) | local出力 | wall |
|---|---|---|---|---|
| A 単一強モデル(claude が全体) | **PASS** | 3403ch | - | **19s** |
| B 分割(claude architect + qwen) | **FAIL** | **6782ch** | 3961ch/1211tok | **268s** |

- **この小規模では単一強モデルが全軸で圧勝**: 品質(A 合格/B 不合格)、強モデルコスト(B は契約が冗長で ~2倍)、wall(B は qwen 直列で ~14倍)。= **[Bet2](findings-bet2-overturn.md) のとおりオーケストレーションは単一強モデルが扱える領域では勝てない。**
- **B 不合格の理由**: qwen 3単位とも *architect(claude) の契約*に単発で不合格（v1 では*私の* qwen 親和な契約で合格していた）。→ **強い architect の契約は弱い実装器官が単発で届かず、再突入(v2)が必須**。econ は再突入なし(best-of-1)ゆえ落ちた。architect と implementer の*整合*が新たな変数。
- **分割が勝つのは規模の領域のみ**: 単一強モデルが*一発で扱えない*大規模(regex 級・多単位)。そこで architect の per-unit overhead が償却され、qwen が(一発不能な)実装バルクを担い、ゲート済み単位＋撤回可能界面の統治を買う。
- **クロスオーバー＝運用ルール**: 単一強モデルの単発射程を超える(規模/一貫性) か、統治(ゲート/撤回/local オフロード)が要る時*だけ*分割。それ未満は単一強モデルを直接使うのが安く速く確実。

## 9. 制約

- n=1〜数。単機（Apple Silicon）で MLX 35b は長文生成 ~8tok/s と遅く、「多数同時」はメモリ束縛で**実質直列**＝「多数」は*論理的隔離アクター*（per_input / 戦略レンズ）。
- 多くは単一シナリオ・要再現。`qwen3.6:27b` は非MLX版で長文生成が顕著に遅く、json/regex の計測はタイムアウトした。
- baseline 比較は単一 codex を想定（[bet2-overturn](findings-bet2-overturn.md) の「オーケストレーション vs 単一強モデル」決定ルールに連なる）。

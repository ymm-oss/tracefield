---
name: tracefield-dev-pipeline
description: tracefield の AI 駆動開発パイプライン (mix tracefield.dev: refine→design→implement→qa) を 1 issue 通すための手続きと観点。来歴不変条件を保ったまま、ゲート(APPROVE/AMEND/REJECT)・coverage/embed/sharing/policy の校正・organ tier・既知の罠(stale-requirement 無限ループ等)を扱う。「tracefield で issue を実装して」「dev パイプラインを回して」「ゲートに回答して」などが合図。実験タスク(ideate/dissolution/emergence)はこのスキルの対象外。
---

# tracefield dev パイプライン運用 — 手続きと観点

tracefield の `mix tracefield.dev` は **再入可能な状態機械**で、1 つの issue を
refine→design→implement→qa の 4 ステージに通し、各ステージ間に人間アクターのターン
(ゲート)を挟む。最終成果は **閉じた来歴チェーン** verdict→change→decision→requirement→issue-chunk。

このスキルの仕事は「賢く回す」ことではなく、**各判断を検証器に通して theater(所作だけで実質が無い状態)を防ぐ**こと。観点は必ず「それが効いたかを測る器」と対で使う。

---

## 0. 心的モデル(これを外すと全部ずれる)

- **1 issue = 1 クラスタ**。issue ディレクトリは **リポジトリの外**に置く(例 `~/Workspace/tracefield-issues/issue-NNN-slug/`)。理由: 実装ステージは workspace で `git add -A` するので、bookkeeping ファイルが workspace の commit に混入してはならない。
- **ステージは自動遷移**。refine done → design へ自動。各ステージ末に人間ゲートで suspend(`⏸`)。
- **人間もアクター**。ゲートは特別な機械ではなく「人間アクターのターン」。回答は `pending/<actor>-<stage>.md` に書く。回答は**引用可能かつ撤回可能**(誤前提の承認を撤回すると下流が closure quarantine される)。
- **来歴不変条件**。change は decision を、decision は requirement を、requirement は issue-chunk を引用する。これが切れていると印字が `unavailable` になる(= 設計が破綻しているサイン)。
- **撤回 → closure quarantine** が中核機構。requirement を retract すると、それを引用した全 decision/change/verdict が連鎖隔離される。

---

## 1. 実行コマンド(再入が基本)

```
mise exec -- mix tracefield.dev --issue <issue_dir> [flags]
```

- **再入で進む**。同じコマンドを再実行するたびに state.json から続きを進める。`--resume` のような専用フラグは無い。`⏸` が出たら pending に回答して**同じコマンドを再実行**。
- まず状態確認: `--status`(現在ステージ・effective policy・⚠ 警告・PR url を表示)。

### 主要フラグ(実コード `parse_args` 準拠)

| フラグ | 値 | 用途・注意 |
|---|---|---|
| `--issue` | dir(必須) | issue ディレクトリ |
| `--status` | — | 状態のみ表示、進めない |
| `--adapter` | `mock`/`ollama`/`cli` | 機械アクターの organ。**注意: actors.json の `kind` が勝つ**。kind=cli のアクターは `--adapter mock` でも mock にならない |
| `--cli-cmd` | パス | CLI organ のコマンド(claude/cursor-agent ラッパ) |
| `--model` `--temperature` | — | 既定 temp 0.4 |
| `--embed` | `mock`/`ollama` | coverage/Reference の埋め込み。**実カバレッジ判定には `ollama`(nomic-embed)必須**。mock は類似度が無意味 |
| `--coverage-mode` | `absolute`/`relative` | relative は median−1.0·MAD、**N≥3 必要**(未満は skip) |
| `--coverage-threshold` | float | absolute の閾値 |
| `--recruit` / `--adopt-recruit <id>` | — | 動的アクター招集(advisory→proposal→人間adopt の3段、自動注入はしない) |
| `--rounds` | int | ステージ内 llm ラウンド上限 |

policy は CLI フラグだけでなく **カスケード**で決まる: default < org(`TRACEFIELD_ORG_POLICY` env) < repo(`<ws>/.tracefield/policy.json`) < issue(`policy.json` / workspace.json の git セクション) < cli(明示フラグのみ)。`--status` の effective policy 表示で**勝った層**を必ず確認する。

---

## 2. 手続き(8 ステップ)

1. **前提確認**: issue dir がリポジトリ外か / `actors.json`(無ければ `agents.json`)の `kind` と `turn` / `workspace.json`(path・test_cmd・organ・git mode)。`--status` で現在地。
2. **organ tier を決める**(観点①)。semantic 品質を出すステージ(refine の判断, design, implement, qa judge)は **cloud organ(composer-2.5 / sonnet / claude)**。local 12b/26b は実装・高品質レビューに**不足**。embedding(coverage 計測)は local nomic で可。
3. **embed/coverage を決める**(観点②)。実データで判断するなら `--embed ollama`。relative モードは N≥3。
4. **refine を回す** → `⏸` で `pending/<actor>-refine.md`。人間ターンで question に回答(`- 回答 [質問id]`)し、要件が揃ったら `APPROVE`。
5. **design を回す**(自動遷移)→ gate-D。**観点③ 引用規律**: 各 decision は active requirement を 1 つ以上引用していること。違反 decision は approve_targets から除外され承認できない(⚠ 警告が出る)。
6. **implement を回す**(`workspace.json` 必須)→ gate-I で diff レビュー。承認は最新の active `:change` を引用する人間 decision。
7. **qa を回す**(自動)→ primary(test_cmd の exit)+ secondary(LLM が requirement ごとに判定)。全 pass で done。fail は「QA差し戻し」feedback → implement ラウンドへループバック。
8. **来歴チェーン確認**: done 時に 5 ノード verdict→change→decision→requirement→issue-chunk が印字される。`unavailable` なら引用が切れている(罠参照)。

---

## 3. 観点 × 検証器(必ず対で使う)

| # | 観点(何を見るか) | 検証器(効いたかをどう測るか) |
|---|---|---|
| ① organ tier | 弱い lens の review は**空/誤**で価値ゼロ。partition は弱 lens を補償しない | refine/design の emitted entry に**実質的内容と正しい引用**があるか。空ターン・引用欠落なら organ を上げる |
| ② territory diversity(支配的レバー) | 同一 territory の lens は何も生まない(thin-film)。private_doc で領土を分ける | coverage の ⚠未カバー警告 / `mobilization_rate` / lens 間の similarity 分離(校正: 日本語短文は ~0.6-0.76 帯、領土分離で in-territory>foreign が出る) |
| ③ 引用規律(gate-D) | decision は requirement を引用してこそ来歴になる | gate-D 前の ⚠ 警告 / approve_targets が空でないか / 来歴チェーンが `unavailable` でないか |
| ④ sharing mode | 列挙タスクは **independent + territory-contract ON** が最良。combine を重ねると −2.3(substitute-goods) | policy の sharing セクション / `:policy` entry / 各ラウンドの cross-cite 数(combine で増える) |
| ⑤ QA の地力 | secondary(LLM)は test_cmd が弱いと false rollback する(QA 品質は test_cmd の強さに律速) | test_cmd が実際に振る舞いを検査しているか。`mix compile` 等の弱い primary は禁物 |

**theater 検出の原則**: 観点を「プロンプトに書いた」だけで満足しない。④なら cross-cite 数、②なら mobilization_rate のように、**無視したら数字が動く器**が無い観点は飾り。

---

## 4. 既知の罠(検出法 → 対処)

| 罠 | 症状 / 検出 | 対処 |
|---|---|---|
| **stale-requirement 無限ループ** | gate ルーリングで de-facto 契約が変わったのに requirement text は active のまま → QA が text に対して判定し続け fail/re-implement が無限ループ | 古い requirement を **AMEND**(`AMEND eN: 新text`)で改訂(closure 無し)。retract ではない。retract は closure 過剰捕捉のリスク |
| **closure 過剰捕捉** | 1 つの requirement を retract したら、bulk 承認経由で全 approval/change/verdict(数十件)が quarantine | retract ではなく **AMEND** を使う。既に起きたら append-only store の末尾 status-op を admin で undo(agent work は触らない) |
| **@response_heading 不一致** | pending に回答を書いたのに反映されない(silently 空) | 見出しが **完全一致** `## RESPONSE（この下に回答を書いてください）` であること。全角括弧。AMEND/REJECT 行もこの見出しの**下**に書く |
| **gate-D 引用無し** | 全 decision が requirement 未引用 → approve_targets 空 → APPROVE しても何も承認されない | decision を requirement 引用付きで再提出させる(機械ターンをもう 1 ラウンド) |
| **type bias** | system プロンプトの JSON 例に引きずられ decision が `:belief` 等で出る | 既定で `expected_types` が procedure の期待型を例に反映。出た entry type が procedure と合うか確認 |
| **kind が adapter に勝つ** | `--adapter mock` なのに実 CLI が呼ばれ課金/失敗 | actors.json の `kind` を確認。mock 実行したいなら kind を mock に |
| **警告の tail 切れ** | `mix ... | tail -N` でゲート警告が切れ、誤って承認判断 | ゲート挙動を判断する前に**タスク出力を全文**見る |
| **workspace に bookkeeping 混入** | `git add -A` が issue の管理ファイルや organ の副産物(index 等)を巻き込む | issue dir をリポジトリ外に。workspace の `.gitignore` に organ 副産物を追加 |
| **mock embed で coverage 無意味** | 類似度が意味を持たず ⚠ が出ない/出すぎる | 実判断は `--embed ollama`。relative は N≥3 |

---

## 5. ゲート人間ターンの書き方(`pending/<actor>-<stage>.md`)

見出し `## RESPONSE（この下に回答を書いてください）` の**下**に、1 行 1 エントリ:

- `- 回答テキスト [質問のid]` … 箇条書き = エントリ。引用は `[e12]` 形式。質問への回答は質問 id を引用 → `:answer`/`:question` 型になる
- `APPROVE` … 単独行。approve_targets を自動引用する人間 decision を生成
- `AMEND eN: 新しいテキスト` … requirement の改訂(closure 無し)。`^AMEND (e\d+): (.+)$`
- `REJECT eN: 理由` … 機械 decision の却下(単一 quarantine、closure 無し)。`^REJECT (e\d+): (.+)$`

回答を書いたら **同じ `mix tracefield.dev --issue ...` を再実行**して取り込む。

---

## 6. 完了判定

- 各ステージ done で `done/` に pending が移動、来歴チェーンが印字される。
- 最終 qa done で 5 ノードチェーンが完全(`unavailable` でない)であることを確認。
- PR mode の場合 `--status` に PR url。

困ったら: `--status` で effective policy と ⚠ を読む → 罠表で症状照合 → 観点表の検証器で「効いているか」を数字で確認。

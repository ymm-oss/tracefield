# Flow Patterns（コピペ可能）

organ は例として `adapter="cli" command="claude" model="claude-sonnet-4-6"` を使う（adapter/model の
権威ある設定・mock 検証・実行手順は tracefield-operator）。実例は `scenarios/lens-*`。

## 共通: organ 定義

```toml
[organs.reasoning]
adapter = "cli"
command = "claude"
model = "claude-sonnet-4-6"
max_tokens = 1500
timeout_seconds = 600
```

## 1. 審議パネル（直交レンズ、単発）

死角照射が目的。哲学2＋枠組2＋場合分け1 の直交構成を推奨。

`agents.json`（各 desc に死角を明記）:
```json
{"agents":[
  {"id":"UTIL","domain":"utilitarianism","desc":"功利主義。全関係者の効用の総和を最大化。死角: 少数者の不公平を埋もれさせる。"},
  {"id":"DEONT","domain":"deontology","desc":"義務論。結果でなく義務・規約・約束に従う。死角: 義務衝突の優先順位を軽視。"},
  {"id":"TOC","domain":"theory-of-constraints","desc":"制約理論。律速する唯一の制約を特定し他を従属。死角: 複数制約を単純化。"},
  {"id":"REVERS","domain":"reversibility","desc":"可逆性・オプション価値。一方通行か両開きドアかで分類。死角: 先延ばしコストを軽視。"},
  {"id":"CASES","domain":"case-analysis","desc":"場合分けのみ。決定変数で場合分けし各場合の妥当解を網羅。死角: 確率評価はしない。"}
]}
```

`flow.toml`:
```toml
[flow]
profile = "panel"
policy = "fixed"
[actor_scaling]
default_mode = "fixed"
max_total_actors = 5
[stages.analysis]
organ = "reasoning"
inputs = ["path:task.md"]
outputs = ["observation", "decision"]
[stages.analysis.actors]
mode = "fixed"
count = 5
roles = ["UTIL", "DEONT", "TOC", "REVERS", "CASES"]
```

## 2. 統治された調査（analysis → verify → adjudication → 機械集約）

中央 SYNTH を置かない。反証ごと独立審判 → run 後に `tracefield aggregate`。

`agents.json` に上記レンズ＋以下を追加:
```json
{"id":"FALSIFY","domain":"falsification","desc":"反証操作。各推奨の反証条件と未検証前提を暴く。自前結論は出さない。"},
{"id":"COUNTER","domain":"counterexample","desc":"反例探索。各推奨が破綻するケースと見落とし当事者を提示。自前結論は出さない。"},
{"id":"ADJ","domain":"refutation-adjudication","desc":"反証審判。与えられた1件の反証だけを精査し暫定合意を覆すか判定。判定は必ず {結論変更を要する / 条件付きで結論維持(条件を明記) / 却下(理由を明記)} の3択。冒頭に対象反証のentry idを明記。矮小化・すり替え・反転は禁止。"}
```

`flow.toml`:
```toml
[stages.verify]
organ = "reasoning"
inputs = ["stage:analysis"]
outputs = ["observation", "question"]
[stages.verify.actors]
mode = "fixed"
count = 2
roles = ["FALSIFY", "COUNTER"]

[stages.adjudication]
organ = "reasoning"
inputs = ["stage:verify"]
outputs = ["observation", "decision"]
[stages.adjudication.actors]
mode = "per_input"          # 反証エントリ数に actor をスケール
roles = ["ADJ"]            # 長1 → 全 actor が ADJ 駆動
```

run 後:
```sh
tracefield run --scenario-dir scenarios/<name> --persist runs/<name>.jsonl
tracefield aggregate --store runs/<name>.jsonl   # overturn→changed / unclassified→indeterminate / 他→maintained+条件
```

## 3. 長時間調査（3サイクル denoise ＋ verify ＋ adjudication ＋ 方法論注入）

`[long_run]` で analysis を反復精製。findings を方法論 skill として注入（生全文を渡すと文脈肥大で自滅するため蒸留して skill 化、agents の `skills` に付与）。

```toml
[long_run]
enabled = true
cycles = 3
cycle_stages = ["analysis"]

[stages.analysis]
organ = "reasoning"
inputs = ["path:task.md", "stage:analysis"]   # 自己/相互参照で denoise
outputs = ["observation", "question", "decision"]
[stages.analysis.actors]
mode = "fixed"
count = 5
roles = ["UTIL", "DEONT", "TOC", "REVERS", "CASES"]
# verify / adjudication ステージは上記2と同じ（cycle_stages に入れない＝最後に1回）
```

方法論 skill は `scenarios/<name>/skills/investigation-method/SKILL.md` に置き、各レンズの
`"skills":["investigation-method"]` で付与（auto-cite で provenance に残る）。
内容例: 多数派に同調しない／死角を申告する／収束を疑う(支配的妥協案の罠)／各サイクルで新情報を足す／前提を名指しする。

## 4. 沈殿（経路依存の立場を育てる）

単一 agent ＋最小 seed ＋自己参照サイクル。既定アトラクタに逆らう種でも保持・自己強化する。

`agents.json`:
```json
{"agents":[{"id":"SELF","domain":"self","desc":"自分の過去の発言だけを足場に立場を一段深める主体。最初の足がかりとして『<seed>』の側から考え始めよ。以後は他者でなく自分が述べたことを継承し発展させること。"}]}
```

`flow.toml`:
```toml
[long_run]
enabled = true
cycles = 3
cycle_stages = ["analysis"]
[stages.analysis]
organ = "reasoning"
inputs = ["path:task.md", "stage:analysis"]   # 自分の過去のみ継承
outputs = ["stance"]
[stages.analysis.actors]
mode = "fixed"
count = 1
roles = ["SELF"]
```

## 入力セレクタ早見

- `path:<file>` … task.md 等（meta.path 一致）
- `stage:<id>` … 当該ステージの全 active エントリ（サイクル横断）
- `entry_type:<t>` / `kind:<k>` / `all` … 型・kind・全件

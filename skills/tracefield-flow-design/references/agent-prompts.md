# エージェント記述（desc／プロンプト技法）

`agents.json` の各エージェントを**実効的な指示**としてどう書くか。フィールド形式は
[scenario-format.md](../tracefield-operator/references/scenario-format.md)、
レンズ選定は [SKILL.md](../SKILL.md) を参照。

## プロンプトの組み立て方（これを知らないと desc を誤る）

tracefield が actor に送るのは2メッセージ（`flow.rs` の `TRACEFIELD_FLOW_STAGE`）:

- **system（固定・変更不可）**: 「You are a Tracefield Field Runner actor. Honor ACTOR_ROLE and
  STAGE_ROLES. Return strict JSON only … Required shape `{"entries":[{"type":...,"text":...,"citations":[...],"meta":{}}]}`」。
  出力形式・JSON・型・citation 契約は**ここで強制**される。
- **user**: `STAGE_ROLES` / `ACTOR_ROLE` / `DOMAIN`（=agent.domain）/ **`DESC`（=agent.desc）** /
  `TASK`（task.md）/ `PRIVATE`（doc）/ `SKILL_CITATIONS` / `CONTEXT`（選択された入力エントリ）。

**含意**: `desc` は system プロンプトを置き換えない。**推論の立場(lens)を与える user 側の指示**。
だから:
- **形式を desc で争わない**（「散文で」「markdown で」は無効。出力は必ず JSON entries）。
- **事実を desc に入れない**。共有事実は `task.md`、エージェント固有の私的事実は `doc`（PRIVATE）へ。desc は観点だけ。
- **簡潔に**。desc は毎呼び出しの文脈に乗る。肥大は小規模域の忠実性（SKILL 鉄則2）を損なう。

## フィールドの役割分担

| field | 役割 | 書き方 |
| --- | --- | --- |
| `id` | エントリ著者・role 束縛キー | 短い安定 id（`UTIL`, `ADJ`） |
| `domain` | retrieval ヒント＋`DOMAIN`＋roles 省略時の `actor_role` | 短いラベル（`utilitarianism`） |
| `desc` | **実効指示（lens）** | 注目する偏り＋死角を一文。下記参照 |
| `doc` | 私的事実（PRIVATE 注入） | `private/<file>.md`。事実・制約・観測 |
| `skills` | 手続き注入（procedure entry、auto-cite） | `skills/<id>/SKILL.md`。方法論・手順 |
| `model` | エージェント単位のモデル上書き（任意） | 例 `claude-sonnet-4-6` |

## 良い `desc` の型

> `<注目する対象・偏り>。<判断の仕方>。死角: <構造的に見落とすもの>。`

例: `功利主義の観点。全関係者の効用の総和を最大化する選択を支持する。死角: 少数者への不公平を総和に埋もれさせる。`

- **冒頭に偏りの核**（何に注目するか）。ロールの肩書きでなく**観測対象**を書く（「エンジニアとして」より「実装・回帰リスク・技術的負債に注目」）。
- **死角を明示**すると、多レンズで各々が盲点を申告し合い、他レンズの断定を留保させられる。
- 直交する複数の哲学分野ほど desc が互いに還元不能になる（SKILL のレンズ序列）。

## ステージ役割ごとの実効指示（確証済みの効く言い回し）

- **審議レンズ（analysis）**: 観点＋死角。`long_run` 反復では方法論 skill で「多数派に同調しない／死角を申告／各サイクルで新情報を足す」を補強（生 findings 全文は注入しない＝文脈肥大）。
- **反証 FALSIFY**: 「各レンズの推奨について何が起きればそれが誤りと判明するかの反証条件と未検証前提を暴く。**自前の結論(A/B/C)は出さない**。」出力型は `question`/`observation`。
- **反例 COUNTER**: 「各推奨が破綻する具体ケースと見落とし当事者を提示。**自前の結論は出さない**。」
- **審判 ADJ**（最重要・機械集約が依存）: 「与えられた**1件の反証だけ**を精査し暫定合意を覆すか判定。判定は必ず **`判定: {結論変更を要する / 条件付きで結論維持(条件を明記) / 却下(理由を明記)}`** の3択。冒頭に対象反証の entry id を明記。**まず反証を最強の形で受け止め**核心に正面から答えてから判定。矮小化・すり替え・支持論への反転は禁止。」
  → `tracefield aggregate` はこの**正準ラベル先頭**で分類する。ラベルを崩すと `unclassified`(indeterminate) になる。
- **沈殿 SELF**: 「自分の過去の発言だけを足場に立場を一段深める主体。最初の足がかりとして『<seed>』の側から考え始めよ。以後は自分が述べたことを継承し発展させること。」既定アトラクタに逆らう seed でも保持・自己強化する。
- **統合（中央 SYNTH）は規模で崩れる**。多項目の最終統合は LLM でなく `tracefield aggregate`。どうしても置くなら入力を小さく保ち、全レンズ id 列挙と各反証への verdict を強制する（が、フォーマット強制だけでは捏造が残る＝隔離＋機械集約が本筋）。

## アンチパターン

- desc で出力形式を指定する（system 契約が勝つ。無駄かつ混乱）。
- desc に共有事実を詰める（task.md/private へ。desc は観点）。
- 肩書きだけの desc（「PMとして」）＝冗長な役割ペルソナ。注目対象と死角を書く。
- desc を長文化（毎呼び出し文脈に乗り、忠実性を損なう）。
- ADJ の判定ラベルを自由形式にする（aggregate が拾えず indeterminate 化）。

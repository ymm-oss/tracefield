use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Scenario {
    pub dir: PathBuf,
    pub task: String,
    pub agents: Vec<AgentSpec>,
    #[serde(default)]
    pub private_docs: BTreeMap<String, String>,
    #[serde(default)]
    pub skills: BTreeMap<String, SkillSpec>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentSpec {
    pub id: String,
    #[serde(default)]
    pub domain: Option<String>,
    #[serde(default)]
    pub desc: Option<String>,
    #[serde(default)]
    pub doc: Option<String>,
    #[serde(default)]
    pub private: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub skills: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillSpec {
    pub id: String,
    pub path: String,
    pub name: String,
    pub description: String,
    pub body: String,
    pub raw_content: String,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum AgentsFile {
    Wrapped { agents: Vec<AgentSpec> },
    Raw(Vec<AgentSpec>),
}

impl Scenario {
    pub fn load(dir: impl AsRef<Path>) -> Result<Self> {
        let dir = dir.as_ref();
        let task_path = dir.join("task.md");
        let agents_path = dir.join("agents.json");

        let task = fs::read_to_string(&task_path)
            .with_context(|| format!("failed to read {}", task_path.display()))?;
        let agents_json = fs::read_to_string(&agents_path)
            .with_context(|| format!("failed to read {}", agents_path.display()))?;
        let agents = match serde_json::from_str::<AgentsFile>(&agents_json)
            .with_context(|| format!("failed to decode {}", agents_path.display()))?
        {
            AgentsFile::Wrapped { agents } | AgentsFile::Raw(agents) => agents,
        };

        if agents.is_empty() {
            bail!("scenario {} has no agents", dir.display());
        }

        let private_docs = load_private_docs(dir)?;
        let skills = load_skill_docs(dir, &agents)?;

        Ok(Self {
            dir: dir.to_path_buf(),
            task: strip_agent_meta(&task),
            agents,
            private_docs,
            skills,
        })
    }

    pub fn agent_private_doc(&self, agent: &AgentSpec) -> Option<&str> {
        let doc = agent.doc.as_ref().or(agent.private.as_ref())?;
        self.private_docs.get(doc).map(String::as_str)
    }

    pub fn agent_skills(&self, agent: &AgentSpec) -> Vec<&SkillSpec> {
        agent
            .skills
            .iter()
            .filter_map(|skill_id| self.skills.get(skill_id))
            .collect()
    }
}

pub fn load(dir: impl AsRef<Path>) -> Result<Scenario> {
    Scenario::load(dir)
}

pub fn scaffold(name: &str, dir: Option<&Path>, force: bool) -> Result<PathBuf> {
    scaffold_with_profile(name, dir, force, "default")
}

pub fn scaffold_with_profile(
    name: &str,
    dir: Option<&Path>,
    force: bool,
    profile: &str,
) -> Result<PathBuf> {
    let base = dir
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("scenarios").join(name));

    if base.exists() && !force {
        bail!(
            "{} already exists; pass --force to overwrite",
            base.display()
        );
    }

    fs::create_dir_all(base.join("private"))
        .with_context(|| format!("failed to create {}", base.display()))?;
    fs::create_dir_all(base.join("inputs"))
        .with_context(|| format!("failed to create {}", base.display()))?;

    write_if_allowed(&base.join("task.md"), task_template(profile), force)?;
    write_if_allowed(&base.join("agents.json"), agents_template(profile), force)?;

    if profile == "meeting-support" {
        write_if_allowed(
            &base.join("inputs").join("minutes.md"),
            MEETING_SUPPORT_MINUTES,
            force,
        )?;
        write_if_allowed(
            &base.join("private").join("agenda.md"),
            MEETING_SUPPORT_AGENDA,
            force,
        )?;
        write_if_allowed(&base.join("README.md"), MEETING_SUPPORT_README, force)?;
    } else {
        write_if_allowed(
            &base.join("private").join("lens1.md"),
            "Private lens for A1.\n",
            force,
        )?;
        write_if_allowed(
            &base.join("private").join("lens2.md"),
            "Private lens for A2.\n",
            force,
        )?;
        write_if_allowed(
            &base.join("inputs").join("example.md"),
            "Replace this with source material, issue text, logs, or other flow inputs.\n",
            force,
        )?;
    }

    write_if_allowed(
        &base.join("flow.toml"),
        flow_template(profile).with_context(|| format!("unknown flow profile {profile:?}"))?,
        force,
    )?;

    Ok(base)
}

fn task_template(profile: &str) -> &'static str {
    match profile {
        "meeting-support" => MEETING_SUPPORT_TASK,
        _ => "Describe the decision or investigation task here.\n",
    }
}

fn agents_template(profile: &str) -> &'static str {
    match profile {
        "meeting-support" => MEETING_SUPPORT_AGENTS,
        _ => {
            r#"{
  "agents": [
    {"id": "A1", "domain": "risk", "desc": "Focus on risks and constraints.", "doc": "lens1.md"},
    {"id": "A2", "domain": "value", "desc": "Focus on user and business value.", "doc": "lens2.md"}
  ]
}
"#
        }
    }
}

const MEETING_SUPPORT_TASK: &str = r##"# 定例MTG 支援（surface-don't-resolve）

`inputs/` の会議資料（議事録・チャット）を読み、次の定例の準備を支援せよ。

1. 各論点(matter)について「誰が(meta.speaker)どんな立場か」を来歴つきで洗い出す。立場の正否は **断定しない**（誰が正しいかは人間が決める）。対立はそのまま提示する。
2. その上で、方針ブリーフ（`private/agenda.md`：望む成果・恐れ・政治的事実）を踏まえ、次の定例で「何を議論すべきか・誰に事前確認すべきか・どう表現すべきか・どの順で話すか」を提案する。

立場の対立を AI が解決して1つの結論に畳んではならない。提示し、解決は人間に委ねる。
"##;

const MEETING_SUPPORT_AGENTS: &str = r##"{
  "agents": [
    {"id": "STANCE_EXTRACT", "domain": "stance-extraction", "desc": "与えられた1つの会議資料チャンクだけを読み、各論点(matter)について『誰がどんな立場か』を atomic な stance として抽出する。1 stance=1エントリ。**網羅的に**：チャンク内の全発言者の全ての立場を漏らさず出す。**同じ matter に複数人の立場があれば全員分を別 stance に**（対立を surface するため——漏らすと CONTESTED が立たない）。**meta.speaker に発言者名**を入れ、meta.matter に論点の短いラベル、meta.evidence_quote に根拠の原文逐語(8〜30語)を付す。立場の正否は判定せず資料の事実のみ。死角: 書かれた発言に偏り言外を読まない。"},

    {"id": "MATTER_PROPOSE", "domain": "matter-proposal", "desc": "全 stance をまとめて読み、議論されている論点(matter)の正準リストを作る。表記揺れ・粒度差は1つに merge。各 matter を1つの question entry で出せ（短いラベル＋一文の定義＋含む stance の id 例）。立場の優劣は判定しない。網羅的に。"},

    {"id": "MATTER_CHALLENGE", "domain": "matter-challenge", "desc": "提案された matter リスト(question群)と全 stance を読み、見落とし・恣意的 merge を攻撃する: (a)stance に在るのにリストに欠けている matter、(b)別物なのに merge された matter を名指せ。欠けている/分けるべき matter は新たな question entry で追加せよ（短いラベル＋定義＋根拠 stance id）。賛辞・手加減禁止。結論は出さず欠落と誤 merge の指摘に徹する。"},

    {"id": "MATTER_LABEL", "domain": "matter-labeling", "desc": "与えられた**1つの stance** を、共有された matter リスト(question群)の中で最も適切な matter に分類し、その stance を**1件だけ**再出力する。meta.matter には選んだ matter の**名前**を入れよ（entry id にしない）。**meta.speaker・立場本文・meta.evidence_quote は元 stance のものをそのまま保持**し、元 stance の id を citations に。立場の優劣は判定しない。"},

    {"id": "STAKEHOLDER", "domain": "stakeholder-map", "desc": "現在の立場群と方針ブリーフを踏まえ、次の定例に向け『誰の合意がまだ欠けているか・誰に事前確認/根回しすべきか』を提案する。各提案は依拠する stance を引用。死角: 当事者に寄り技術的中身を見落とす。"},

    {"id": "READINESS", "domain": "decision-readiness", "desc": "対立が未解決で意思決定を塞いでいる論点を特定し『次回までに何を詰めれば決められるか』を提案する。CONTESTED な matter を優先。死角: 決定可能性に寄り政治的機微を軽視。"},

    {"id": "FRAMING", "domain": "framing-and-sequence", "desc": "方針ブリーフの恐れ・政治的事実を踏まえ、対立論点を次回スライドで『どう表現し・どの順で話すか』を具体的に提案する。敏感な点は柔らかい表現と切り出す順序まで。死角: 表現に寄り技術的実体を軽視。"},

    {"id": "DECK", "domain": "slide-draft", "desc": "生き残った立場(matter別)と進め方の提案を読み、次回定例の Marp スライド下書きを作る。各スライドはタイトル＋3〜5項目＋必要なら speaker notes。**対立論点はどちらかに畳まず両論を併記**し、進め方(誰に聞く/表現/順序)を反映。立場の優劣は決めない。meta.artifact_section に短いスライド題を入れる。"}
  ]
}
"##;

const MEETING_SUPPORT_FLOW: &str = r##"[flow]
profile = "meeting-support"
policy = "fixed"
# 長い議事録を段落3つ単位で自動 chunk → per_input が網羅抽出（手分割不要）。
input_chunk_paragraphs = 3

[actor_scaling]
default_mode = "fixed"
max_parallel_actors = 3

# 既定は単一モデル(codex)＝最小セットアップ。matter_challenge を異種モデルで硬化するなら
# 別 organ（例: [organs.claude] adapter="cli" command="claude"）を足し matter_challenge.organ をそれに。
[organs.reasoning]
adapter = "cli"
command = "codex"

# 各 chunk を隔離読みして stance を網羅抽出（誰がどの立場か・meta.speaker つき）
[stages.stances]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["stance"]
grounded = true
[stages.stances.actors]
mode = "per_input"
roles = ["STANCE_EXTRACT"]

# 論点(matter)集合を閉じる: 提案 → 反証で欠落を足し戻す
[stages.matter_propose]
organ = "reasoning"
inputs = ["stage:stances"]
outputs = ["question"]
[stages.matter_propose.actors]
mode = "fixed"
count = 1
roles = ["MATTER_PROPOSE"]

[stages.matter_challenge]
organ = "reasoning"
inputs = ["stage:stances", "stage:matter_propose"]
outputs = ["question"]
[stages.matter_challenge.actors]
mode = "fixed"
count = 1
roles = ["MATTER_CHALLENGE"]

# no-drop ラベル付け: per_input で stance を1件ずつ shard ＋ 確定 matter 一覧を shared_inputs で全 actor に共有
[stages.matter_label]
organ = "reasoning"
inputs = ["stage:stances"]
shared_inputs = ["stage:matter_propose", "stage:matter_challenge"]
outputs = ["stance"]
[stages.matter_label.actors]
mode = "per_input"
roles = ["MATTER_LABEL"]

# 進め方: 生き残った立場 ＋ 方針(private) を読み、次回の論点/根回し/表現/順序を提案
[stages.foresight]
organ = "reasoning"
inputs = ["stage:matter_label", "kind:private"]
outputs = ["decision", "question"]
[stages.foresight.actors]
mode = "fixed"
count = 3
roles = ["STAKEHOLDER", "READINESS", "FRAMING"]

# スライド下書き(Marp): 立場と進め方を deck 化（対立は両論併記）
[stages.deck]
organ = "reasoning"
inputs = ["stage:matter_label", "stage:foresight"]
outputs = ["synthesis"]
[stages.deck.actors]
mode = "fixed"
count = 1
roles = ["DECK"]
[stages.deck.artifact]
format = "slides_markdown"

# 終端の成果物（機械描画）
[artifacts.contested_map]
format = "contested_map"
from_stage = "matter_label"
path = "outputs/contested-map.md"

[artifacts.how_to_proceed]
format = "markdown"
from_stage = "foresight"
path = "outputs/how-to-proceed.md"

[artifacts.deck]
format = "slides_markdown"
from_stage = "deck"
path = "outputs/deck.marp.md"
"##;

const MEETING_SUPPORT_MINUTES: &str = r##"# 議事録（ここを実際の議事録に差し替える）

発言は段落（空行区切り）で書く。長文は flow の input_chunk_paragraphs で自動 chunk され、
per_input が各 chunk を網羅抽出する（手分割は不要）。

田中: （例）スコープは確定したので Q2 出荷で行きたい。

大野部長: クライアントには Q1 と約束済み。Q1 を死守したい。

山本: 現状の負債だと Q2 は危うい。品質を担保するなら Q3 が現実的。
"##;

const MEETING_SUPPORT_AGENDA: &str = r##"# 方針ブリーフ（任意・進め方の質を上げる）

数行でよい。空でも動くが、書くほど「進め方」の提案が鋭くなる。

## 望む成果
- （この定例で何を達成したいか）

## 恐れ
- （何が起きると困るか・政治的に痛い点）

## 主要な政治的事実
- （誰が力を持つ・何に敏感か、議事録に書かれない前提）
"##;

const MEETING_SUPPORT_README: &str = r##"# meeting-support — 定例MTG 支援（surface-don't-resolve）

議事録から「誰がどの論点でどんな立場か（対立を潰さず提示）」＋「次回の進め方」＋
「スライド下書き」を出す。詳細は `docs/findings-surface-dont-resolve.md`。

## 使い方
1. `inputs/minutes.md` を実際の議事録に差し替える（発言は空行区切りの段落で。長文は自動 chunk）。
2. `private/agenda.md` に方針ブリーフを書く（任意だが推奨）。
3. モデルを設定：`tracefield doctor` で codex/claude を確認し、`flow.toml` の
   `[organs.reasoning]` は既定で `adapter="cli" command="codex"`。
4. 実行：`tracefield run --scenario-dir <this dir>`（または `tracefield meeting <this dir>`）。

## 出力（`outputs/`）
- `contested-map.md` — 論点別に全立場を来歴つきで提示。発言者 ≥2 の論点に `⚠ CONTESTED`。
- `how-to-proceed.md` — 次に議論すべき点・誰に聞くか・表現・順序。
- `deck.marp.md` — Marp スライド下書き（対立は両論併記）。

## 異種モデルで硬化（任意）
matter の欠落落としを防ぐなら `[organs.claude] adapter="cli" command="claude"` を足し、
`[stages.matter_challenge] organ = "claude"` にする（異種 debate）。
"##;

fn flow_template(profile: &str) -> Option<&'static str> {
    match profile {
        "default" => Some(
            r#"[flow]
profile = "default"
policy = "fixed"
budget = 20
max_feedback_cycles = 0

[actor_scaling]
default_mode = "fixed"
max_total_actors = 4
max_parallel_actors = 1

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "per_input"
max = 2

[stages.analyze]
organ = "reasoning"
inputs = ["stage:collect"]
outputs = ["synthesis", "question"]

[stages.analyze.actors]
mode = "fixed"
count = 1

	[artifacts.summary]
	format = "markdown"
	from_stage = "analyze"
	path = "outputs/summary.md"
	"#,
        ),
        "consult" => Some(
            r#"[flow]
profile = "consult"
policy = "fixed"
budget = 20

[long_run]
enabled = true
cycles = 2
cycle_stages = ["deliberate"]

[actor_scaling]
default_mode = "per_agent"
max_parallel_actors = 1

[organs.reasoning]
adapter = "mock"

[stages.deliberate]
organ = "reasoning"
outputs = ["claim", "question", "observation", "decision"]

[stages.deliberate.actors]
mode = "per_agent"
"#,
        ),
        "deep_investigation" => Some(
            r#"[flow]
	profile = "deep_investigation"
policy = "fixed"
budget = 200
max_feedback_cycles = 2

[actor_scaling]
default_mode = "fixed"
max_total_actors = 24
max_parallel_actors = 4

[process]
enabled = true
organ = "reasoning"
mode = "deep_investigation"
agent_count = 1
artifact_after_feedback = true
artifact_stages = ["artifact_strategy", "report_architecture", "report_draft", "report_critique", "report_finalize", "deck_storyline", "slide_spec", "slide_draft", "deck_critique", "deck_finalize"]

[process.gates]
enforce_artifact_gate = true
allow_conditional_artifacts = false
require_citations = true
require_evidence_quotes = true
block_publish_on_open_questions = true
block_publish_on_quality_warnings = false
require_manifest = true

[process.stop]
max_cycles = 3
max_feedback_cycles = 8
stop_when = ["no_high_priority_recollection", "audit_passed", "artifact_publishable"]

[feedback]
enabled = true
max_requests_per_cycle = 8
dedupe_by = ["normalized_request", "target_entry", "stage"]

[[feedback.edge]]
from = ["hypothesis", "lens_analysis", "audit"]
to = "source_extract"
entry_types = ["question", "audit"]
trigger_when = ["needs_evidence", "needs_refutation", "low_evidence_coverage"]

[feedback_entries]
enabled = true
kind = "tracefield_feedback"
accepted_types = ["change", "requirement", "question", "audit"]
status_field = "status"
max_requests_per_cycle = 8
dedupe_by = ["target", "action", "normalized_request"]

[[feedback_entries.route]]
target_prefix = "input.web"
to = "source_discovery"
entry_types = ["change", "requirement", "question", "audit"]

[[feedback_entries.route]]
target_prefix = "flow.stage.source_discovery"
to = "source_discovery"
entry_types = ["change", "requirement", "question", "audit"]

[[feedback_entries.route]]
target_prefix = "flow.stage.source_extract"
to = "source_extract"
entry_types = ["change", "requirement", "question", "audit"]

[[feedback_entries.route]]
target_prefix = "flow."
to = "feedback_triage"
entry_types = ["change", "requirement", "question", "audit"]

[[feedback_entries.route]]
target_prefix = "artifact."
to = "feedback_triage"
entry_types = ["change", "requirement", "question", "audit"]

[[feedback_entries.route]]
target_prefix = "gates."
to = "feedback_triage"
entry_types = ["change", "requirement", "question", "audit"]

[[feedback_entries.route]]
target_prefix = "profile."
to = "feedback_triage"
entry_types = ["change", "requirement", "question", "audit"]

[organs.data]
adapter = "cli"
command = "/Users/rizumita/Workspace/github/ds4/ds4"
model = "/Users/rizumita/Workspace/github/ds4/ds4flash.gguf"
max_tokens = 400
timeout_seconds = 1200

[organs.reasoning]
adapter = "cli"
command = "codex"
model = "codex"

[stages.source_discovery]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["question", "observation"]
budget = 20

[stages.source_discovery.actors]
mode = "auto"
min = 1
max = 4
scale_by = ["input_count", "open_questions"]
roles = ["source_discovery"]

[stages.source_cluster]
inputs = ["kind:input"]
outputs = ["synthesis"]
budget = 10

[stages.source_cluster.clustering]
enabled = true
by = ["path_parent", "path"]
max_clusters = 12

[stages.source_cluster.actors]
mode = "none"
roles = ["source_clusterer"]

[stages.source_extract]
organ = "data"
inputs = ["kind:input"]
outputs = ["observation", "question"]
budget = 40

[stages.source_extract.actors]
mode = "per_input"
min = 1
max = 12
roles = ["data_actor"]

[stages.hypothesis]
organ = "reasoning"
inputs = ["stage:source_discovery", "stage:source_cluster", "stage:source_extract"]
outputs = ["hypothesis", "question"]
budget = 40

[stages.hypothesis.actors]
mode = "auto"
min = 2
max = 6
scale_by = ["budget", "input_count", "open_questions"]

[stages.lens_analysis]
organ = "reasoning"
inputs = ["stage:hypothesis", "stage:source_cluster", "stage:source_extract"]
outputs = ["synthesis", "audit", "question"]
budget = 40

[stages.lens_analysis.actors]
mode = "fixed"
count = 4
roles = ["market", "technical", "risk", "operations"]

[stages.audit]
organ = "reasoning"
inputs = ["stage:lens_analysis", "stage:hypothesis"]
outputs = ["audit", "question"]
budget = 30

[stages.audit.actors]
mode = "fixed"
count = 2
roles = ["artifact_critic", "citation_auditor"]

[stages.feedback_triage]
organ = "reasoning"
inputs = ["kind:tracefield_feedback", "stage:audit", "stage:lens_analysis"]
outputs = ["change", "requirement", "decision", "question"]
budget = 15

[stages.feedback_triage.actors]
mode = "fixed"
count = 1
roles = ["feedback_router"]

[stages.artifact_strategy]
organ = "reasoning"
inputs = ["stage:feedback_triage", "stage:audit", "stage:lens_analysis"]
outputs = ["synthesis"]
budget = 10

[stages.artifact_strategy.actors]
mode = "fixed"
count = 1
roles = ["artifact_strategist"]

[stages.report_architecture]
organ = "reasoning"
inputs = ["stage:artifact_strategy", "stage:lens_analysis"]
outputs = ["synthesis"]
budget = 10

[stages.report_architecture.actors]
mode = "fixed"
count = 1
roles = ["artifact_architect"]

[stages.report_draft]
organ = "reasoning"
inputs = ["stage:report_architecture", "stage:lens_analysis", "stage:audit"]
outputs = ["synthesis", "decision"]
budget = 30

[stages.report_draft.actors]
mode = "auto"
min = 1
max = 4
scale_by = ["budget", "input_count"]
roles = ["artifact_writer"]

[stages.report_critique]
organ = "reasoning"
inputs = ["stage:report_draft"]
outputs = ["audit"]
budget = 10

[stages.report_critique.actors]
mode = "fixed"
count = 2
roles = ["artifact_critic", "citation_auditor"]

[stages.report_finalize]
organ = "reasoning"
inputs = ["stage:report_draft", "stage:report_critique"]
outputs = ["synthesis", "decision"]
budget = 15

[stages.report_finalize.actors]
mode = "fixed"
count = 1
roles = ["artifact_editor"]

[stages.report_finalize.artifact]
kind = "executive_report"
format = "markdown"
audience = "executive"
require_citations = true

[stages.deck_storyline]
organ = "reasoning"
inputs = ["stage:artifact_strategy", "stage:lens_analysis"]
outputs = ["synthesis"]
budget = 10

[stages.deck_storyline.actors]
mode = "fixed"
count = 1
roles = ["artifact_strategist"]

[stages.slide_spec]
organ = "reasoning"
inputs = ["stage:deck_storyline", "stage:lens_analysis"]
outputs = ["synthesis"]
budget = 10

[stages.slide_spec.actors]
mode = "fixed"
count = 1
roles = ["artifact_architect"]

[stages.slide_draft]
organ = "reasoning"
inputs = ["stage:slide_spec", "stage:lens_analysis", "stage:audit"]
outputs = ["synthesis"]
budget = 30

[stages.slide_draft.actors]
mode = "auto"
min = 2
max = 6
scale_by = ["budget", "input_count"]
roles = ["artifact_writer"]

[stages.deck_critique]
organ = "reasoning"
inputs = ["stage:slide_draft"]
outputs = ["audit"]
budget = 10

[stages.deck_critique.actors]
mode = "fixed"
count = 2
roles = ["artifact_critic", "citation_auditor"]

[stages.deck_finalize]
organ = "reasoning"
inputs = ["stage:slide_draft", "stage:deck_critique"]
outputs = ["synthesis"]
budget = 15

[stages.deck_finalize.actors]
mode = "fixed"
count = 1
roles = ["artifact_editor"]

[stages.deck_finalize.artifact]
kind = "strategy_deck"
format = "slides_markdown"
audience = "executive"
require_citations = true

[artifacts.executive_report]
format = "markdown"
from_stage = "report_finalize"
path = "outputs/report.md"

[artifacts.strategy_deck]
format = "slides_markdown"
from_stage = "deck_finalize"
path = "outputs/deck.md"
"#,
        ),
        "meeting-support" => Some(MEETING_SUPPORT_FLOW),
        _ => None,
    }
}

fn load_private_docs(dir: &Path) -> Result<BTreeMap<String, String>> {
    let private_dir = dir.join("private");
    if !private_dir.exists() {
        return Ok(BTreeMap::new());
    }

    let mut docs = BTreeMap::new();
    for entry in fs::read_dir(&private_dir)
        .with_context(|| format!("failed to read {}", private_dir.display()))?
    {
        let entry =
            entry.with_context(|| format!("failed to read entry in {}", private_dir.display()))?;
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("md") {
            continue;
        }

        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .context("private document has non-utf8 name")?
            .to_string();
        let content = fs::read_to_string(&path)
            .with_context(|| format!("failed to read {}", path.display()))?;
        docs.insert(name, content);
    }

    Ok(docs)
}

fn load_skill_docs(dir: &Path, agents: &[AgentSpec]) -> Result<BTreeMap<String, SkillSpec>> {
    let mut skills = BTreeMap::new();
    for skill_id in agents
        .iter()
        .flat_map(|agent| agent.skills.iter())
        .collect::<BTreeSet<_>>()
    {
        validate_skill_id(skill_id)?;
        let (path, content) = read_skill_doc(dir, skill_id)?;
        let skill = parse_skill(skill_id, path, content)?;
        skills.insert(skill_id.clone(), skill);
    }

    Ok(skills)
}

fn read_skill_doc(dir: &Path, skill_id: &str) -> Result<(String, String)> {
    let nested = PathBuf::from("skills").join(skill_id).join("SKILL.md");
    let path = dir.join(&nested);

    if path.exists() {
        let content = fs::read_to_string(&path)
            .with_context(|| format!("failed to read {}", path.display()))?;
        return Ok((nested.to_string_lossy().to_string(), content));
    }

    bail!(
        "skill {skill_id} not found; expected {} under {}",
        nested.display(),
        dir.display()
    );
}

fn validate_skill_id(skill_id: &str) -> Result<()> {
    if skill_id.is_empty() || skill_id.len() > 63 {
        bail!("invalid skill id {skill_id:?}; use 1-63 lowercase letters, digits, or hyphens");
    }
    if skill_id.starts_with('-') || skill_id.ends_with('-') || skill_id.contains("--") {
        bail!(
            "invalid skill id {skill_id:?}; use hyphen-case without leading, trailing, or repeated hyphens"
        );
    }
    if !skill_id
        .chars()
        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '-')
    {
        bail!(
            "invalid skill id {skill_id:?}; use only lowercase ASCII letters, digits, or hyphens"
        );
    }

    Ok(())
}

fn parse_skill(skill_id: &str, path: String, raw_content: String) -> Result<SkillSpec> {
    let (frontmatter, body) = split_skill_frontmatter(&raw_content)
        .with_context(|| format!("skill {skill_id} must start with YAML frontmatter"))?;
    let name = frontmatter_value(frontmatter, "name")
        .with_context(|| format!("skill {skill_id} frontmatter is missing required name"))?;
    let description = frontmatter_value(frontmatter, "description")
        .with_context(|| format!("skill {skill_id} frontmatter is missing required description"))?;

    if name != skill_id {
        bail!("skill {skill_id} frontmatter name must match the skill directory name");
    }
    if description.trim().is_empty() {
        bail!("skill {skill_id} frontmatter description must not be empty");
    }

    Ok(SkillSpec {
        id: skill_id.to_string(),
        path,
        name,
        description,
        body: body.trim().to_string(),
        raw_content,
    })
}

fn split_skill_frontmatter(raw: &str) -> Option<(&str, &str)> {
    let rest = raw
        .strip_prefix("---\n")
        .or_else(|| raw.strip_prefix("---\r\n"))?;
    let separator = rest
        .find("\n---\n")
        .map(|index| (index, 5))
        .or_else(|| rest.find("\r\n---\r\n").map(|index| (index, 7)))
        .or_else(|| rest.find("\n---\r\n").map(|index| (index, 6)))
        .or_else(|| rest.find("\r\n---\n").map(|index| (index, 6)))?;
    let (frontmatter, remainder) = rest.split_at(separator.0);
    Some((frontmatter, &remainder[separator.1..]))
}

fn frontmatter_value(frontmatter: &str, key: &str) -> Option<String> {
    let prefix = format!("{key}:");
    frontmatter.lines().find_map(|line| {
        let value = line.trim().strip_prefix(&prefix)?.trim();
        Some(unquote(value).to_string())
    })
}

fn unquote(value: &str) -> &str {
    value
        .strip_prefix('"')
        .and_then(|value| value.strip_suffix('"'))
        .or_else(|| {
            value
                .strip_prefix('\'')
                .and_then(|value| value.strip_suffix('\''))
        })
        .unwrap_or(value)
}

fn write_if_allowed(path: &Path, content: &str, force: bool) -> Result<()> {
    if path.exists() && !force {
        bail!(
            "{} already exists; pass --force to overwrite",
            path.display()
        );
    }

    fs::write(path, content).with_context(|| format!("failed to write {}", path.display()))
}

fn strip_agent_meta(text: &str) -> String {
    text.split("## この入力の性質")
        .next()
        .unwrap_or(text)
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_generic_scenario() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate growth.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"ops","desc":"Ops lens","doc":"ops.md"}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("private")).unwrap();
        fs::write(
            dir.path().join("private").join("ops.md"),
            "Operational notes",
        )
        .unwrap();

        let scenario = Scenario::load(dir.path()).unwrap();
        assert_eq!(scenario.task, "Investigate growth.");
        assert_eq!(scenario.agents[0].id, "A1");
        assert_eq!(
            scenario.agent_private_doc(&scenario.agents[0]),
            Some("Operational notes")
        );
    }

    #[test]
    fn loads_agent_skills_from_scenario_local_directory() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate growth.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"ops","doc":"ops.md","skills":["review"]}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("private")).unwrap();
        fs::write(dir.path().join("private").join("ops.md"), "Ops notes").unwrap();
        fs::create_dir_all(dir.path().join("skills").join("review")).unwrap();
        let raw_skill = r#"---
name: review
description: Check claims against explicit evidence.
---

# Review

Review procedure
"#;
        fs::write(
            dir.path().join("skills").join("review").join("SKILL.md"),
            raw_skill,
        )
        .unwrap();

        let scenario = Scenario::load(dir.path()).unwrap();
        let agent_skills = scenario.agent_skills(&scenario.agents[0]);

        assert_eq!(agent_skills.len(), 1);
        assert_eq!(agent_skills[0].id, "review");
        assert_eq!(agent_skills[0].path, "skills/review/SKILL.md");
        assert_eq!(agent_skills[0].name, "review");
        assert_eq!(
            agent_skills[0].description,
            "Check claims against explicit evidence."
        );
        assert_eq!(agent_skills[0].body, "# Review\n\nReview procedure");
        assert_eq!(agent_skills[0].raw_content, raw_skill);
    }

    #[test]
    fn scaffold_creates_flow_runner_files() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("flow-smoke");
        let scenario_dir = scaffold("flow-smoke", Some(&target), false).unwrap();

        assert!(scenario_dir.join("task.md").exists());
        assert!(scenario_dir.join("agents.json").exists());
        assert!(scenario_dir.join("flow.toml").exists());
        assert!(scenario_dir.join("inputs").join("example.md").exists());
        assert!(scenario_dir.join("private").join("lens1.md").exists());

        let flow = fs::read_to_string(scenario_dir.join("flow.toml")).unwrap();
        assert!(flow.contains("[stages.collect]"));
        assert!(flow.contains("[artifacts.summary]"));
    }

    #[test]
    fn scaffold_can_create_meeting_support_profile() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("mtg");
        let scenario_dir =
            scaffold_with_profile("mtg", Some(&target), false, "meeting-support").unwrap();

        let flow = fs::read_to_string(scenario_dir.join("flow.toml")).unwrap();
        assert!(flow.contains("profile = \"meeting-support\""));
        assert!(flow.contains("shared_inputs"));
        assert!(flow.contains("input_chunk_paragraphs"));
        let agents = fs::read_to_string(scenario_dir.join("agents.json")).unwrap();
        assert!(agents.contains("STANCE_EXTRACT") && agents.contains("MATTER_LABEL"));
        assert!(scenario_dir.join("inputs").join("minutes.md").exists());
        assert!(scenario_dir.join("private").join("agenda.md").exists());
        assert!(scenario_dir.join("README.md").exists());
    }

    #[test]
    fn scaffold_can_create_deep_investigation_profile() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("deep");
        let scenario_dir =
            scaffold_with_profile("deep", Some(&target), false, "deep_investigation").unwrap();
        let flow = fs::read_to_string(scenario_dir.join("flow.toml")).unwrap();

        assert!(flow.contains("profile = \"deep_investigation\""));
        assert!(flow.contains("command = \"/Users/rizumita/Workspace/github/ds4/ds4\""));
        assert!(flow.contains("model = \"/Users/rizumita/Workspace/github/ds4/ds4flash.gguf\""));
        assert!(flow.contains("command = \"codex\""));
        assert!(flow.contains("[process]"));
        assert!(flow.contains("artifact_after_feedback = true"));
        assert!(flow.contains("[stages.source_discovery]"));
        assert!(flow.contains("[stages.source_cluster.clustering]"));
        assert!(flow.contains("[feedback_entries]"));
        assert!(flow.contains("[stages.feedback_triage]"));
        assert!(flow.contains("[stages.report_finalize]"));
        assert!(flow.contains("[stages.deck_finalize]"));
        assert!(flow.contains("[artifacts.strategy_deck]"));
    }

    #[test]
    fn scaffold_can_create_consult_profile() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("consult");
        let scenario_dir =
            scaffold_with_profile("consult", Some(&target), false, "consult").unwrap();
        let flow = fs::read_to_string(scenario_dir.join("flow.toml")).unwrap();

        assert!(flow.contains("profile = \"consult\""));
        assert!(flow.contains("[long_run]"));
        assert!(flow.contains("cycle_stages = [\"deliberate\"]"));
        assert!(flow.contains("[stages.deliberate]"));
        assert!(flow.contains("mode = \"per_agent\""));
    }

    #[test]
    fn missing_agent_skill_fails_fast() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate growth.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","skills":["missing"]}]}"#,
        )
        .unwrap();

        let error = Scenario::load(dir.path()).unwrap_err().to_string();
        assert!(error.contains("skill missing not found"));
    }

    #[test]
    fn skill_without_required_frontmatter_fails_fast() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate growth.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","skills":["review"]}]}"#,
        )
        .unwrap();
        fs::create_dir_all(dir.path().join("skills").join("review")).unwrap();
        fs::write(
            dir.path().join("skills").join("review").join("SKILL.md"),
            "# Review\n\nReview procedure",
        )
        .unwrap();

        let error = Scenario::load(dir.path()).unwrap_err().to_string();
        assert!(error.contains("must start with YAML frontmatter"));
    }

    #[test]
    fn skill_name_must_match_directory() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate growth.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","skills":["review"]}]}"#,
        )
        .unwrap();
        fs::create_dir_all(dir.path().join("skills").join("review")).unwrap();
        fs::write(
            dir.path().join("skills").join("review").join("SKILL.md"),
            r#"---
name: other-review
description: Check claims.
---

# Review
"#,
        )
        .unwrap();

        let error = Scenario::load(dir.path()).unwrap_err().to_string();
        assert!(error.contains("frontmatter name must match"));
    }
}

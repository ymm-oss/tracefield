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

    write_if_allowed(
        &base.join("task.md"),
        "Describe the decision or investigation task here.\n",
        force,
    )?;
    write_if_allowed(
        &base.join("agents.json"),
        r#"{
  "agents": [
    {"id": "A1", "domain": "risk", "desc": "Focus on risks and constraints.", "doc": "lens1.md"},
    {"id": "A2", "domain": "value", "desc": "Focus on user and business value.", "doc": "lens2.md"}
  ]
}
"#,
        force,
    )?;
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
    write_if_allowed(
        &base.join("flow.toml"),
        flow_template(profile).with_context(|| format!("unknown flow profile {profile:?}"))?,
        force,
    )?;

    Ok(base)
}

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

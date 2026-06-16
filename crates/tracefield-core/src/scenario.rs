use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Scenario {
    pub dir: PathBuf,
    pub task: String,
    pub agents: Vec<AgentSpec>,
    #[serde(default)]
    pub private_docs: BTreeMap<String, String>,
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

        Ok(Self {
            dir: dir.to_path_buf(),
            task: strip_agent_meta(&task),
            agents,
            private_docs,
        })
    }

    pub fn agent_private_doc(&self, agent: &AgentSpec) -> Option<&str> {
        let doc = agent.doc.as_ref().or(agent.private.as_ref())?;
        self.private_docs.get(doc).map(String::as_str)
    }
}

pub fn load(dir: impl AsRef<Path>) -> Result<Scenario> {
    Scenario::load(dir)
}

pub fn scaffold(name: &str, dir: Option<&Path>, force: bool) -> Result<PathBuf> {
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

    Ok(base)
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
}

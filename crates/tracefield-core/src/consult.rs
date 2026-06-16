use crate::entry::{Entry, EntryType, NewEntry};
use crate::llm::{self, Adapter, LlmOptions, Message};
use crate::scenario::{AgentSpec, Scenario};
use crate::store::ReferenceStore;
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct ConsultOptions {
    pub scenario_dir: PathBuf,
    pub adapter: String,
    pub model: Option<String>,
    pub rounds: usize,
    pub persist_path: Option<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsultResult {
    pub task: String,
    pub deliberation: Vec<Entry>,
    pub layer0_index: Vec<Entry>,
}

pub async fn run_consult(options: ConsultOptions) -> Result<ConsultResult> {
    let scenario = Scenario::load(&options.scenario_dir)?;
    let adapter = Adapter::parse(&options.adapter)?;
    let mut llm_options = LlmOptions {
        adapter,
        model: options.model.clone(),
        ..LlmOptions::default()
    };
    let rounds = options.rounds.max(1);

    let mut store = ReferenceStore::new();
    let layer0_index = seed_layer0(&mut store, &scenario);
    let mut deliberation = Vec::new();

    for round in 1..=rounds {
        for agent in &scenario.agents {
            llm_options.model = agent.model.clone().or_else(|| options.model.clone());

            let retrieved = store.serve(&agent_prompt_query(&scenario, agent), 5);
            let messages = agent_messages(&scenario, agent, round, &retrieved);
            let content = llm::complete(&messages, &llm_options)
                .await
                .with_context(|| format!("LLM adapter failed for agent {}", agent.id))?;
            let entries = parse_agent_entries(&content, agent, round, &retrieved);
            let stored = store.absorb(entries, &agent.id);
            deliberation.extend(stored);
        }
    }

    if let Some(path) = &options.persist_path {
        store.write_jsonl(path)?;
    }

    Ok(ConsultResult {
        task: scenario.task,
        deliberation,
        layer0_index,
    })
}

fn seed_layer0(store: &mut ReferenceStore, scenario: &Scenario) -> Vec<Entry> {
    let task = store.push(
        NewEntry::new(EntryType::Chunk, "scenario", scenario.task.clone())
            .with_meta("kind", json!("task")),
        "scenario",
    );

    let mut layer0 = vec![task.clone()];
    for (name, content) in &scenario.private_docs {
        let entry = store.push(
            NewEntry::new(EntryType::CorpusChunk, "scenario", content.clone())
                .with_citations(vec![task.id.clone()])
                .with_meta("kind", json!("private"))
                .with_meta("path", json!(format!("private/{name}"))),
            "scenario",
        );
        layer0.push(entry);
    }

    layer0
}

fn agent_messages(
    scenario: &Scenario,
    agent: &AgentSpec,
    round: usize,
    retrieved: &[Entry],
) -> Vec<Message> {
    let private_doc = scenario.agent_private_doc(agent).unwrap_or("");
    let context = retrieved
        .iter()
        .map(|entry| format!("{} [{}]: {}", entry.id, entry.author, entry.text))
        .collect::<Vec<_>>()
        .join("\n");

    vec![
        Message::system(
            "You are a Tracefield scenario agent. Return JSON: {\"entries\":[{\"type\":\"claim|question|observation|decision\",\"text\":\"...\",\"citations\":[\"e1\"]}]}.",
        ),
        Message::user(format!(
            "TRACEFIELD_AGENT_TURN\nAGENT: {}\nROUND: {}\nDOMAIN: {}\nDESC: {}\nTASK: {}\nPRIVATE:\n{}\nCONTEXT:\n{}",
            agent.id,
            round,
            agent.domain.as_deref().unwrap_or("general"),
            agent.desc.as_deref().unwrap_or(""),
            scenario.task,
            private_doc,
            context
        )),
    ]
}

fn agent_prompt_query(scenario: &Scenario, agent: &AgentSpec) -> String {
    [
        scenario.task.as_str(),
        agent.domain.as_deref().unwrap_or(""),
        agent.desc.as_deref().unwrap_or(""),
        scenario.agent_private_doc(agent).unwrap_or(""),
    ]
    .join("\n")
}

fn parse_agent_entries(
    content: &str,
    agent: &AgentSpec,
    round: usize,
    retrieved: &[Entry],
) -> Vec<NewEntry> {
    let default_citations = retrieved
        .iter()
        .take(3)
        .map(|entry| entry.id.clone())
        .collect::<Vec<_>>();

    let parsed = serde_json::from_str::<Value>(content).ok();
    let raw_entries = parsed
        .as_ref()
        .and_then(|value| value.get("entries"))
        .and_then(Value::as_array);

    match raw_entries {
        Some(entries) => {
            let normalized = entries
                .iter()
                .filter_map(|entry| {
                    let text = entry.get("text").and_then(Value::as_str)?.trim();
                    if text.is_empty() {
                        return None;
                    }

                    let entry_type = entry
                        .get("type")
                        .and_then(Value::as_str)
                        .map(EntryType::parse)
                        .unwrap_or(EntryType::Claim);
                    let citations = entry
                        .get("citations")
                        .and_then(Value::as_array)
                        .map(|values| {
                            values
                                .iter()
                                .filter_map(Value::as_str)
                                .map(ToOwned::to_owned)
                                .collect::<Vec<_>>()
                        })
                        .filter(|citations| !citations.is_empty())
                        .unwrap_or_else(|| default_citations.clone());
                    let mut meta = entry
                        .get("meta")
                        .and_then(Value::as_object)
                        .cloned()
                        .unwrap_or_else(Map::new);
                    meta.insert("round".to_string(), json!(round));

                    Some(NewEntry {
                        entry_type,
                        status: Default::default(),
                        author: Some(agent.id.clone()),
                        text: text.to_string(),
                        citations,
                        meta,
                        embedding: Vec::new(),
                    })
                })
                .collect::<Vec<_>>();

            if normalized.is_empty() {
                fallback_entry(content, agent, round, default_citations)
            } else {
                normalized
            }
        }
        None => fallback_entry(content, agent, round, default_citations),
    }
}

fn fallback_entry(
    content: &str,
    agent: &AgentSpec,
    round: usize,
    citations: Vec<String>,
) -> Vec<NewEntry> {
    vec![
        NewEntry::new(
            EntryType::Claim,
            agent.id.clone(),
            content.trim().to_string(),
        )
        .with_citations(citations)
        .with_meta("round", json!(round)),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[tokio::test]
    async fn consult_loads_generic_scenario_and_persists_jsonl() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("task.md"),
            "Improve an internal support tool.",
        )
        .unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"security","desc":"Auditability","doc":"sec.md"},{"id":"A2","domain":"ux","desc":"Usability","doc":"ux.md"}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("private")).unwrap();
        fs::write(
            dir.path().join("private").join("sec.md"),
            "Require audit trails and role boundaries.",
        )
        .unwrap();
        fs::write(
            dir.path().join("private").join("ux.md"),
            "Keep workflows simple for operators.",
        )
        .unwrap();
        let persist_path = dir.path().join("out").join("store.jsonl");

        let result = run_consult(ConsultOptions {
            scenario_dir: dir.path().to_path_buf(),
            adapter: "mock".to_string(),
            model: None,
            rounds: 2,
            persist_path: Some(persist_path.clone()),
        })
        .await
        .unwrap();

        assert_eq!(result.layer0_index.len(), 3);
        assert_eq!(result.deliberation.len(), 8);
        assert!(persist_path.exists());

        let restored = ReferenceStore::from_jsonl_path(&persist_path).unwrap();
        assert_eq!(restored.all().len(), 11);
        assert_eq!(restored.all()[0].id, "e1");
    }
}

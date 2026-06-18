//! Progressive-disclosure skill tools for Field Runner agents.
//!
//! Tool-capable adapters (Ollama, OpenRouter) see only each skill's name and
//! description, then pull the rest through `read_skill` (SKILL.md / bundled
//! `references/`) and `run_skill_script` (files under `scripts/`, confined to
//! that directory). Every resolved tool call becomes an `observation` entry
//! citing the skill, so the field records exactly what the agent read or ran.

use crate::entry::{EntryType, NewEntry};
use crate::llm::{self, AgentTurn, LlmOptions, Message, ToolCall};
use crate::scenario::Scenario;
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::process::Stdio;
use std::time::Duration;

const MAX_TOOL_ITERATIONS: usize = 8;
const TOOL_OUTPUT_CAP: usize = 8000;

/// A skill bound to an actor, presented at progressive-disclosure level 1.
pub(crate) struct SkillRef {
    pub id: String,
    pub entry_id: String,
    pub name: String,
    pub description: String,
}

/// Render the name+description listing the agent reasons over before deciding
/// which skills to open.
pub(crate) fn skill_l1_block(skills: &[SkillRef]) -> String {
    if skills.is_empty() {
        return "(none)".to_string();
    }
    skills
        .iter()
        .map(|skill| {
            format!(
                "SKILL {} [{}]\nNAME: {}\nDESCRIPTION: {}\n(call read_skill skill_id=\"{}\" to load instructions/references; run_skill_script to execute scripts/<file>)",
                skill.id, skill.entry_id, skill.name, skill.description, skill.id
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

/// Drive the tool loop until the model returns a final text answer, returning
/// that answer plus the provenance entries for every resolved tool call.
pub(crate) async fn run_skill_tool_loop(
    scenario: &Scenario,
    author: &str,
    allowed_skills: &[String],
    skill_citations: &[String],
    messages: &[Message],
    options: &LlmOptions,
) -> Result<(String, Vec<NewEntry>)> {
    let tools = skill_tool_specs();
    let mut convo = messages
        .iter()
        .map(|message| serde_json::to_value(message).unwrap_or(Value::Null))
        .collect::<Vec<_>>();
    let mut provenance = Vec::new();

    for _ in 0..MAX_TOOL_ITERATIONS {
        match llm::complete_turn(&convo, &tools, options).await? {
            AgentTurn::Text(text) => return Ok((text, provenance)),
            AgentTurn::ToolCalls { assistant, calls } => {
                convo.push(assistant);
                for call in calls {
                    let (result, entry) = resolve_tool_call(
                        scenario,
                        author,
                        allowed_skills,
                        &call,
                        skill_citations,
                        options,
                    )
                    .await;
                    if let Some(entry) = entry {
                        provenance.push(entry);
                    }
                    convo.push(tool_result_message(&call, result));
                }
            }
        }
    }

    bail!("author {author} exceeded skill tool budget ({MAX_TOOL_ITERATIONS} calls)")
}

/// Build the tool-result message in the shape the provider expects: OpenAI
/// (OpenRouter) keys results by `tool_call_id`; Ollama keys by `tool_name`.
fn tool_result_message(call: &ToolCall, content: String) -> Value {
    match &call.id {
        Some(id) => json!({"role": "tool", "tool_call_id": id, "content": content}),
        None => json!({"role": "tool", "tool_name": call.name, "content": content}),
    }
}

fn skill_tool_specs() -> Vec<Value> {
    vec![
        json!({
            "type": "function",
            "function": {
                "name": "read_skill",
                "description": "Read a skill file. Omit path for SKILL.md; pass a relative path such as references/foo.md for a bundled file.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "skill_id": {"type": "string"},
                        "path": {"type": "string"}
                    },
                    "required": ["skill_id"]
                }
            }
        }),
        json!({
            "type": "function",
            "function": {
                "name": "run_skill_script",
                "description": "Execute a script bundled under the skill's scripts/ directory and return its stdout.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "skill_id": {"type": "string"},
                        "script": {"type": "string"},
                        "args": {"type": "array", "items": {"type": "string"}}
                    },
                    "required": ["skill_id", "script"]
                }
            }
        }),
    ]
}

async fn resolve_tool_call(
    scenario: &Scenario,
    author: &str,
    allowed_skills: &[String],
    call: &ToolCall,
    skill_citations: &[String],
    options: &LlmOptions,
) -> (String, Option<NewEntry>) {
    let skill_id = call
        .arguments
        .get("skill_id")
        .and_then(Value::as_str)
        .unwrap_or("");
    if !allowed_skills.iter().any(|skill| skill == skill_id) {
        return (
            format!("error: skill '{skill_id}' is not available to this agent"),
            None,
        );
    }

    match call.name.as_str() {
        "read_skill" => {
            let path = call.arguments.get("path").and_then(Value::as_str);
            match read_skill_file(scenario, skill_id, path) {
                Ok(body) => {
                    let entry = record_skill_access(
                        author,
                        skill_id,
                        path.unwrap_or("SKILL.md"),
                        "skill_read",
                        skill_citations,
                    );
                    (body, Some(entry))
                }
                Err(error) => (format!("error: {error}"), None),
            }
        }
        "run_skill_script" => {
            let script = call
                .arguments
                .get("script")
                .and_then(Value::as_str)
                .unwrap_or("");
            let args = call
                .arguments
                .get("args")
                .and_then(Value::as_array)
                .map(|args| {
                    args.iter()
                        .filter_map(|arg| arg.as_str().map(String::from))
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
            match run_skill_script(scenario, skill_id, script, &args, options.timeout).await {
                Ok(output) => {
                    let entry = record_skill_access(
                        author,
                        skill_id,
                        script,
                        "skill_script",
                        skill_citations,
                    );
                    (output, Some(entry))
                }
                Err(error) => (format!("error: {error}"), None),
            }
        }
        other => (format!("error: unknown tool '{other}'"), None),
    }
}

fn record_skill_access(
    author: &str,
    skill_id: &str,
    detail: &str,
    kind: &str,
    skill_citations: &[String],
) -> NewEntry {
    NewEntry::new(
        EntryType::Observation,
        author,
        format!("{author} accessed {skill_id}: {detail}"),
    )
    .with_citations(skill_citations.to_vec())
    .with_meta("kind", json!(kind))
    .with_meta("skill", json!(skill_id))
    .with_meta("detail", json!(detail))
}

/// Resolve `path` (default `SKILL.md`) under the skill directory, confined to
/// that directory, and return its contents capped to a budget.
fn read_skill_file(scenario: &Scenario, skill_id: &str, path: Option<&str>) -> Result<String> {
    let base = scenario.dir.join("skills").join(skill_id);
    let canonical_base = base
        .canonicalize()
        .with_context(|| format!("skill '{skill_id}' directory not found"))?;
    let rel = path.unwrap_or("SKILL.md");
    let target = canonical_base
        .join(rel)
        .canonicalize()
        .with_context(|| format!("'{rel}' not found in skill '{skill_id}'"))?;
    if !target.starts_with(&canonical_base) {
        bail!("'{rel}' escapes skill '{skill_id}'");
    }
    let body = std::fs::read_to_string(&target)
        .with_context(|| format!("failed to read '{rel}' in skill '{skill_id}'"))?;
    Ok(cap_output(body))
}

/// Execute `script` confined to the skill's `scripts/` directory, with the
/// skill directory as cwd, capturing stdout (or exit status + stderr).
async fn run_skill_script(
    scenario: &Scenario,
    skill_id: &str,
    script: &str,
    args: &[String],
    timeout: Duration,
) -> Result<String> {
    let skill_dir = scenario.dir.join("skills").join(skill_id);
    let scripts_dir = skill_dir
        .join("scripts")
        .canonicalize()
        .with_context(|| format!("skill '{skill_id}' has no scripts/ directory"))?;
    let target = scripts_dir
        .join(script)
        .canonicalize()
        .with_context(|| format!("script '{script}' not found in skill '{skill_id}'"))?;
    if !target.starts_with(&scripts_dir) {
        bail!("script '{script}' escapes the scripts/ directory");
    }

    let child = tokio::process::Command::new(&target)
        .args(args)
        .current_dir(&skill_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to spawn script '{script}'"))?;
    let output = tokio::time::timeout(timeout, child.wait_with_output())
        .await
        .with_context(|| format!("script '{script}' timed out"))?
        .with_context(|| format!("script '{script}' failed"))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    if output.status.success() {
        Ok(cap_output(stdout.to_string()))
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Ok(cap_output(format!(
            "exit {}: {stdout}{stderr}",
            output.status
        )))
    }
}

fn cap_output(mut text: String) -> String {
    if text.len() > TOOL_OUTPUT_CAP {
        // Back off to the nearest char boundary so multi-byte (e.g. Japanese)
        // tool output is never split mid-codepoint, which would panic.
        let mut new_len = TOOL_OUTPUT_CAP;
        while new_len > 0 && !text.is_char_boundary(new_len) {
            new_len -= 1;
        }
        text.truncate(new_len);
        text.push_str("\n…(truncated)");
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::fs;

    fn skill_scenario(dir: &std::path::Path) -> Scenario {
        Scenario {
            dir: dir.to_path_buf(),
            task: String::new(),
            agents: Vec::new(),
            private_docs: BTreeMap::new(),
            skills: BTreeMap::new(),
        }
    }

    #[test]
    fn read_skill_file_resolves_body_and_references_but_blocks_escape() {
        let dir = tempfile::tempdir().unwrap();
        let skill = dir.path().join("skills").join("audit");
        fs::create_dir_all(skill.join("references")).unwrap();
        fs::write(skill.join("SKILL.md"), "body").unwrap();
        fs::write(skill.join("references").join("note.md"), "ref-note").unwrap();
        fs::write(dir.path().join("secret.txt"), "secret").unwrap();
        let scenario = skill_scenario(dir.path());

        assert_eq!(read_skill_file(&scenario, "audit", None).unwrap(), "body");
        assert_eq!(
            read_skill_file(&scenario, "audit", Some("references/note.md")).unwrap(),
            "ref-note"
        );
        assert!(read_skill_file(&scenario, "audit", Some("../../secret.txt")).is_err());
    }

    #[tokio::test]
    async fn run_skill_script_executes_within_scripts_dir_and_blocks_escape() {
        let dir = tempfile::tempdir().unwrap();
        let scripts = dir.path().join("skills").join("audit").join("scripts");
        fs::create_dir_all(&scripts).unwrap();
        let script = scripts.join("echo.sh");
        fs::write(&script, "#!/bin/sh\necho \"hello $1\"\n").unwrap();
        let mut perms = fs::metadata(&script).unwrap().permissions();
        std::os::unix::fs::PermissionsExt::set_mode(&mut perms, 0o755);
        fs::set_permissions(&script, perms).unwrap();
        let scenario = skill_scenario(dir.path());

        let output = run_skill_script(
            &scenario,
            "audit",
            "echo.sh",
            &["world".to_string()],
            Duration::from_secs(5),
        )
        .await
        .unwrap();
        assert_eq!(output.trim(), "hello world");

        assert!(
            run_skill_script(
                &scenario,
                "audit",
                "../../../bin/ls",
                &[],
                Duration::from_secs(5)
            )
            .await
            .is_err()
        );
    }
}

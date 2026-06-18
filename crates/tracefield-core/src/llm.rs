use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Adapter {
    Mock,
    Ollama,
    Cli,
    OpenRouter,
    CodexAppServer,
}

impl Adapter {
    pub fn parse(value: &str) -> Result<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "mock" => Ok(Self::Mock),
            "ollama" => Ok(Self::Ollama),
            "cli" => Ok(Self::Cli),
            "openrouter" => Ok(Self::OpenRouter),
            "codex-app-server" | "codex_app_server" => Ok(Self::CodexAppServer),
            other => bail!("unknown LLM adapter {other}"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: String,
    pub content: String,
}

impl Message {
    pub fn system(content: impl Into<String>) -> Self {
        Self {
            role: "system".to_string(),
            content: content.into(),
        }
    }

    pub fn user(content: impl Into<String>) -> Self {
        Self {
            role: "user".to_string(),
            content: content.into(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ToolCall {
    pub id: Option<String>,
    pub name: String,
    pub arguments: Value,
}

#[derive(Debug, Clone)]
pub enum AgentTurn {
    Text(String),
    ToolCalls {
        assistant: Value,
        calls: Vec<ToolCall>,
    },
}

#[derive(Debug, Clone)]
pub struct LlmOptions {
    pub adapter: Adapter,
    pub model: Option<String>,
    pub cli_command: Option<String>,
    pub web_search: bool,
    pub seed: u64,
    pub temperature: f32,
    pub max_tokens: usize,
    pub timeout: Duration,
}

impl Default for LlmOptions {
    fn default() -> Self {
        Self {
            adapter: Adapter::Mock,
            model: None,
            cli_command: None,
            web_search: false,
            seed: 0,
            temperature: 0.2,
            max_tokens: 1200,
            timeout: Duration::from_secs(300),
        }
    }
}

pub async fn complete(messages: &[Message], options: &LlmOptions) -> Result<String> {
    match options.adapter {
        Adapter::Mock => Ok(mock_complete(messages, options)),
        Adapter::Ollama => complete_ollama(messages, options).await,
        Adapter::Cli => complete_cli(messages, options).await,
        Adapter::OpenRouter => complete_openrouter(messages, options).await,
        Adapter::CodexAppServer => {
            // For plain complete calls (no provenance consumer), discard provenance.
            let (text, _) = crate::codex_app_server::run(
                std::path::Path::new("."),
                "codex",
                &[],
                messages,
                options,
            )
            .await?;
            Ok(text)
        }
    }
}

pub async fn ollama_available() -> bool {
    reqwest::Client::new()
        .get("http://localhost:11434/api/tags")
        .timeout(Duration::from_secs(2))
        .send()
        .await
        .map(|response| response.status().is_success())
        .unwrap_or(false)
}

fn mock_complete(messages: &[Message], _options: &LlmOptions) -> String {
    let prompt = messages
        .iter()
        .map(|message| message.content.as_str())
        .collect::<Vec<_>>()
        .join("\n");

    let agent = field(&prompt, "AGENT").unwrap_or_else(|| "mock".to_string());
    let round = field(&prompt, "ROUND").unwrap_or_else(|| "1".to_string());
    let domain = field(&prompt, "DOMAIN").unwrap_or_else(|| "general".to_string());
    let task_head = field(&prompt, "TASK")
        .unwrap_or_default()
        .lines()
        .next()
        .unwrap_or("")
        .trim()
        .chars()
        .take(80)
        .collect::<String>();

    json!({
        "entries": [
            {
                "type": "claim",
                "text": format!("{agent} round {round} {domain} claim: {task_head}"),
                "meta": {"adapter": "mock", "round": round, "domain": domain}
            },
            {
                "type": "question",
                "text": format!("{agent} round {round} asks what evidence would change this view."),
                "meta": {"adapter": "mock", "round": round}
            }
        ]
    })
    .to_string()
}

/// Run one chat turn, optionally offering tools. Only Ollama drives the tool
/// loop; other adapters ignore `tools` and always return `Text`.
pub async fn complete_turn(
    messages: &[Value],
    tools: &[Value],
    options: &LlmOptions,
) -> Result<AgentTurn> {
    match options.adapter {
        Adapter::Ollama => ollama_turn(messages, tools, options).await,
        Adapter::OpenRouter => openrouter_turn(messages, tools, options).await,
        _ => {
            let messages = values_to_messages(messages);
            Ok(AgentTurn::Text(complete(&messages, options).await?))
        }
    }
}

fn values_to_messages(values: &[Value]) -> Vec<Message> {
    values
        .iter()
        .map(|value| Message {
            role: value
                .get("role")
                .and_then(Value::as_str)
                .unwrap_or("user")
                .to_string(),
            content: value
                .get("content")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
        })
        .collect()
}

async fn complete_ollama(messages: &[Message], options: &LlmOptions) -> Result<String> {
    let messages = messages
        .iter()
        .map(|message| serde_json::to_value(message).unwrap_or(Value::Null))
        .collect::<Vec<_>>();
    match ollama_turn(&messages, &[], options).await? {
        AgentTurn::Text(text) => Ok(text),
        AgentTurn::ToolCalls { .. } => Ok(String::new()),
    }
}

async fn ollama_turn(
    messages: &[Value],
    tools: &[Value],
    options: &LlmOptions,
) -> Result<AgentTurn> {
    let model = options
        .model
        .clone()
        .unwrap_or_else(|| "gemma4:12b".to_string());
    let mut body = json!({
        "model": model,
        "messages": messages,
        "stream": false,
        "think": false,
        "options": {
            "seed": options.seed,
            "temperature": options.temperature,
            "num_predict": options.max_tokens,
            "num_ctx": 8192
        }
    });
    if !tools.is_empty() {
        body["tools"] = Value::Array(tools.to_vec());
    }

    let response = reqwest::Client::new()
        .post("http://localhost:11434/api/chat")
        .timeout(options.timeout)
        .json(&body)
        .send()
        .await
        .context("ollama request failed")?;

    let status = response.status();
    let payload: Value = response.json().await.context("invalid ollama response")?;
    if !status.is_success() {
        bail!("ollama HTTP error {status}: {payload}");
    }

    let message = payload.pointer("/message").cloned().unwrap_or(Value::Null);
    let calls = message
        .get("tool_calls")
        .and_then(Value::as_array)
        .map(|calls| {
            calls
                .iter()
                .map(|call| ToolCall {
                    id: call.get("id").and_then(Value::as_str).map(String::from),
                    name: call
                        .pointer("/function/name")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string(),
                    arguments: call
                        .pointer("/function/arguments")
                        .cloned()
                        .unwrap_or_else(|| json!({})),
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if !calls.is_empty() {
        return Ok(AgentTurn::ToolCalls {
            assistant: message,
            calls,
        });
    }

    let content = message
        .get("content")
        .and_then(Value::as_str)
        .or_else(|| message.get("thinking").and_then(Value::as_str))
        .unwrap_or("")
        .to_string();
    Ok(AgentTurn::Text(content))
}

async fn complete_openrouter(messages: &[Message], options: &LlmOptions) -> Result<String> {
    let messages = messages
        .iter()
        .map(|message| serde_json::to_value(message).unwrap_or(Value::Null))
        .collect::<Vec<_>>();
    match openrouter_turn(&messages, &[], options).await? {
        AgentTurn::Text(text) => Ok(text),
        AgentTurn::ToolCalls { .. } => Ok(String::new()),
    }
}

async fn openrouter_turn(
    messages: &[Value],
    tools: &[Value],
    options: &LlmOptions,
) -> Result<AgentTurn> {
    let key = std::env::var("OPENROUTER_API_KEY").context("OPENROUTER_API_KEY is not set")?;
    let model = options
        .model
        .clone()
        .unwrap_or_else(|| "openai/gpt-5.5".to_string());
    let mut body = json!({
        "model": model,
        "messages": messages,
        "temperature": options.temperature,
        "max_tokens": options.max_tokens,
        "seed": options.seed
    });
    if !tools.is_empty() {
        body["tools"] = Value::Array(tools.to_vec());
    }

    let response = reqwest::Client::new()
        .post("https://openrouter.ai/api/v1/chat/completions")
        .timeout(options.timeout)
        .bearer_auth(key)
        .header("x-title", "tracefield")
        .json(&body)
        .send()
        .await
        .context("openrouter request failed")?;

    let status = response.status();
    let payload: Value = response
        .json()
        .await
        .context("invalid openrouter response")?;
    if !status.is_success() {
        bail!("openrouter HTTP error {status}: {payload}");
    }

    let message = payload
        .pointer("/choices/0/message")
        .cloned()
        .unwrap_or(Value::Null);
    let calls = message
        .get("tool_calls")
        .and_then(Value::as_array)
        .map(|calls| {
            calls
                .iter()
                .map(|call| ToolCall {
                    id: call.get("id").and_then(Value::as_str).map(String::from),
                    name: call
                        .pointer("/function/name")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string(),
                    arguments: parse_openai_arguments(call.pointer("/function/arguments")),
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if !calls.is_empty() {
        return Ok(AgentTurn::ToolCalls {
            assistant: message,
            calls,
        });
    }

    let content = message
        .get("content")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    Ok(AgentTurn::Text(content))
}

/// OpenAI-style tool arguments arrive as a JSON-encoded string; some providers
/// return an object. Accept both.
fn parse_openai_arguments(value: Option<&Value>) -> Value {
    match value {
        Some(Value::String(raw)) => serde_json::from_str(raw).unwrap_or_else(|_| json!({})),
        Some(other) => other.clone(),
        None => json!({}),
    }
}

async fn complete_cli(messages: &[Message], options: &LlmOptions) -> Result<String> {
    let prompt = messages
        .iter()
        .map(|message| message.content.as_str())
        .collect::<Vec<_>>()
        .join("\n\n");

    let command = options
        .cli_command
        .clone()
        .or_else(|| std::env::var("TRACEFIELD_CLI_COMMAND").ok())
        .unwrap_or_else(|| "cursor-agent".into());
    let invocation = build_cli_invocation(&command, options, prompt, codex_last_message_path());

    let mut command = Command::new(&invocation.program);
    command.args(&invocation.args);
    if let Some(current_dir) = &invocation.current_dir {
        command.current_dir(current_dir);
    }
    let child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to spawn {}", invocation.program))?;

    let output = tokio::time::timeout(options.timeout, child.wait_with_output())
        .await
        .context("CLI adapter timed out")?
        .context("CLI adapter failed")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        cleanup_invocation(&invocation);
        bail!("CLI adapter exited with {}: {}", output.status, stderr);
    }

    if let Some(path) = &invocation.output_last_message {
        let content = fs::read_to_string(path)
            .with_context(|| format!("failed to read Codex output {}", path.display()))?;
        cleanup_invocation(&invocation);
        Ok(content.trim().to_string())
    } else {
        let content = String::from_utf8_lossy(&output.stdout).trim().to_string();
        cleanup_invocation(&invocation);
        Ok(content)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CliInvocation {
    program: String,
    args: Vec<String>,
    output_last_message: Option<PathBuf>,
    cleanup_paths: Vec<PathBuf>,
    current_dir: Option<PathBuf>,
}

fn build_cli_invocation(
    command: &str,
    options: &LlmOptions,
    prompt: String,
    codex_output_path: PathBuf,
) -> CliInvocation {
    let command = command.trim();
    let executable = if command == "claude-code" {
        "claude"
    } else if command.is_empty() {
        "cursor-agent"
    } else {
        command
    };
    let kind = Path::new(executable)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(executable);

    match kind {
        "cursor-agent" => {
            let mut args = vec![
                "-p".to_string(),
                "--force".to_string(),
                "--trust".to_string(),
                "--model".to_string(),
                options
                    .model
                    .clone()
                    .unwrap_or_else(|| "composer-2.5".to_string()),
            ];
            args.push(prompt);
            CliInvocation {
                program: executable.to_string(),
                args,
                output_last_message: None,
                cleanup_paths: Vec::new(),
                current_dir: None,
            }
        }
        "claude" => {
            let mut args = vec![
                "-p".to_string(),
                "--output-format".to_string(),
                "text".to_string(),
                "--no-session-persistence".to_string(),
            ];
            if let Some(model) = &options.model {
                args.push("--model".to_string());
                args.push(model.clone());
            }
            args.push(prompt);
            CliInvocation {
                program: executable.to_string(),
                args,
                output_last_message: None,
                cleanup_paths: Vec::new(),
                current_dir: None,
            }
        }
        "codex" => {
            let mut args = vec![
                "exec".to_string(),
                "--skip-git-repo-check".to_string(),
                "--ephemeral".to_string(),
                "--sandbox".to_string(),
                "read-only".to_string(),
                "--color".to_string(),
                "never".to_string(),
                "--output-last-message".to_string(),
                codex_output_path.to_string_lossy().to_string(),
            ];
            // Enable the native web_search tool (no per-call approval) when the
            // organ opts in. Equivalent to `codex --search`.
            if options.web_search {
                args.push("-c".to_string());
                args.push("tools.web_search=true".to_string());
            }
            if let Some(model) = &options.model
                && model != "codex"
            {
                args.push("--model".to_string());
                args.push(model.clone());
            }
            args.push(prompt);
            CliInvocation {
                program: executable.to_string(),
                args,
                output_last_message: Some(codex_output_path),
                cleanup_paths: Vec::new(),
                current_dir: None,
            }
        }
        "ds4" => {
            let prompt_file = ds4_prompt_path();
            let mut cleanup_paths = Vec::new();
            let current_dir = Path::new(executable).parent().map(Path::to_path_buf);
            let mut args = Vec::new();
            if let Some(model) = &options.model
                && model != "ds4"
            {
                args.push("-m".to_string());
                args.push(model.clone());
            }
            args.push("-n".to_string());
            args.push(options.max_tokens.to_string());
            args.push("--temp".to_string());
            args.push(format_float(options.temperature));
            args.push("--seed".to_string());
            args.push(options.seed.max(1).to_string());
            args.push("--nothink".to_string());
            args.push("-sys".to_string());
            args.push(ds4_json_system_prompt().to_string());
            if fs::write(&prompt_file, &prompt).is_ok() {
                args.push("--prompt-file".to_string());
                args.push(prompt_file.to_string_lossy().to_string());
                cleanup_paths.push(prompt_file);
            } else {
                args.push("-p".to_string());
                args.push(prompt);
            }
            CliInvocation {
                program: executable.to_string(),
                args,
                output_last_message: None,
                cleanup_paths,
                current_dir,
            }
        }
        _ => CliInvocation {
            program: executable.to_string(),
            args: vec![prompt],
            output_last_message: None,
            cleanup_paths: Vec::new(),
            current_dir: None,
        },
    }
}

fn codex_last_message_path() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    std::env::temp_dir().join(format!(
        "tracefield-codex-{}-{nanos}.txt",
        std::process::id()
    ))
}

fn ds4_prompt_path() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    std::env::temp_dir().join(format!(
        "tracefield-ds4-prompt-{}-{nanos}.txt",
        std::process::id()
    ))
}

fn format_float(value: f32) -> String {
    let value = format!("{value:.6}");
    value
        .trim_end_matches('0')
        .trim_end_matches('.')
        .to_string()
}

fn ds4_json_system_prompt() -> &'static str {
    "You are a strict JSON generator for Tracefield. Output exactly one JSON object and nothing else. The first character must be { and the final character must be }. Do not use markdown, code fences, commentary, labels, or hidden reasoning. If asked to cite evidence, copy evidence quotes exactly from the provided context."
}

fn cleanup_invocation(invocation: &CliInvocation) {
    if let Some(path) = &invocation.output_last_message {
        let _ = fs::remove_file(path);
    }
    for path in &invocation.cleanup_paths {
        let _ = fs::remove_file(path);
    }
}

fn field(prompt: &str, name: &str) -> Option<String> {
    let prefix = format!("{name}:");
    prompt.lines().find_map(|line| {
        line.strip_prefix(&prefix)
            .map(|value| value.trim().to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn mock_returns_deterministic_entries_json() {
        let options = LlmOptions::default();
        let messages = vec![Message::user(
            "AGENT: A1\nROUND: 2\nDOMAIN: risk\nTASK: Decide",
        )];
        let left = complete(&messages, &options).await.unwrap();
        let right = complete(&messages, &options).await.unwrap();
        assert_eq!(left, right);
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&left).unwrap()["entries"][0]["type"],
            "claim"
        );
    }

    #[test]
    fn cli_invocation_keeps_cursor_agent_compatibility() {
        let options = LlmOptions {
            model: Some("composer-test".to_string()),
            ..LlmOptions::default()
        };

        let invocation = build_cli_invocation(
            "cursor-agent",
            &options,
            "PROMPT".to_string(),
            PathBuf::from("/tmp/unused"),
        );

        assert_eq!(invocation.program, "cursor-agent");
        assert_eq!(
            invocation.args,
            vec![
                "-p",
                "--force",
                "--trust",
                "--model",
                "composer-test",
                "PROMPT"
            ]
        );
        assert_eq!(invocation.output_last_message, None);
    }

    #[test]
    fn cli_invocation_supports_claude_code() {
        let options = LlmOptions {
            model: Some("sonnet".to_string()),
            ..LlmOptions::default()
        };

        let invocation = build_cli_invocation(
            "claude",
            &options,
            "PROMPT".to_string(),
            PathBuf::from("/tmp/unused"),
        );

        assert_eq!(invocation.program, "claude");
        assert_eq!(
            invocation.args,
            vec![
                "-p",
                "--output-format",
                "text",
                "--no-session-persistence",
                "--model",
                "sonnet",
                "PROMPT"
            ]
        );
        assert_eq!(invocation.output_last_message, None);
    }

    #[test]
    fn cli_invocation_supports_claude_code_alias() {
        let invocation = build_cli_invocation(
            "claude-code",
            &LlmOptions::default(),
            "PROMPT".to_string(),
            PathBuf::from("/tmp/unused"),
        );

        assert_eq!(invocation.program, "claude");
        assert_eq!(
            invocation.args,
            vec![
                "-p",
                "--output-format",
                "text",
                "--no-session-persistence",
                "PROMPT"
            ]
        );
    }

    #[test]
    fn cli_invocation_supports_codex_exec() {
        let options = LlmOptions {
            model: Some("gpt-test".to_string()),
            ..LlmOptions::default()
        };
        let output = PathBuf::from("/tmp/tracefield-codex-output.txt");

        let invocation =
            build_cli_invocation("codex", &options, "PROMPT".to_string(), output.clone());

        assert_eq!(invocation.program, "codex");
        assert_eq!(
            invocation.args,
            vec![
                "exec",
                "--skip-git-repo-check",
                "--ephemeral",
                "--sandbox",
                "read-only",
                "--color",
                "never",
                "--output-last-message",
                "/tmp/tracefield-codex-output.txt",
                "--model",
                "gpt-test",
                "PROMPT"
            ]
        );
        assert_eq!(invocation.output_last_message, Some(output));
    }

    #[test]
    fn cli_invocation_treats_codex_model_as_default_codex_cli_model() {
        let options = LlmOptions {
            model: Some("codex".to_string()),
            ..LlmOptions::default()
        };

        let invocation = build_cli_invocation(
            "codex",
            &options,
            "PROMPT".to_string(),
            PathBuf::from("/tmp/tracefield-codex-output.txt"),
        );

        assert!(!invocation.args.iter().any(|arg| arg == "--model"));
    }

    #[test]
    fn cli_invocation_supports_ds4_prompt_file() {
        let options = LlmOptions {
            model: Some("/models/ds4flash.gguf".to_string()),
            max_tokens: 256,
            temperature: 0.0,
            seed: 42,
            ..LlmOptions::default()
        };

        let invocation = build_cli_invocation(
            "/Users/rizumita/Workspace/github/ds4/ds4",
            &options,
            "PROMPT".to_string(),
            PathBuf::from("/tmp/unused"),
        );

        assert_eq!(
            invocation.program,
            "/Users/rizumita/Workspace/github/ds4/ds4"
        );
        assert_eq!(
            invocation.current_dir.as_deref(),
            Some(Path::new("/Users/rizumita/Workspace/github/ds4"))
        );
        assert_eq!(invocation.args[0], "-m");
        assert_eq!(invocation.args[1], "/models/ds4flash.gguf");
        assert!(invocation.args.iter().any(|arg| arg == "--nothink"));
        assert!(
            invocation
                .args
                .windows(2)
                .any(|args| args[0] == "-sys"
                    && args[1].contains("Output exactly one JSON object"))
        );
        assert!(invocation.args.windows(2).any(|args| args == ["-n", "256"]));
        assert!(
            invocation
                .args
                .windows(2)
                .any(|args| args == ["--temp", "0"])
        );
        assert!(
            invocation
                .args
                .windows(2)
                .any(|args| args == ["--seed", "42"])
        );
        let prompt_file_index = invocation
            .args
            .iter()
            .position(|arg| arg == "--prompt-file")
            .unwrap();
        let prompt_path = PathBuf::from(&invocation.args[prompt_file_index + 1]);
        assert_eq!(fs::read_to_string(&prompt_path).unwrap(), "PROMPT");
        assert_eq!(invocation.cleanup_paths, vec![prompt_path]);
        cleanup_invocation(&invocation);
    }

    #[test]
    fn cli_invocation_normalizes_ds4_zero_seed() {
        let invocation = build_cli_invocation(
            "ds4",
            &LlmOptions::default(),
            "PROMPT".to_string(),
            PathBuf::from("/tmp/unused"),
        );

        assert!(
            invocation
                .args
                .windows(2)
                .any(|args| args == ["--seed", "1"])
        );
        cleanup_invocation(&invocation);
    }
}

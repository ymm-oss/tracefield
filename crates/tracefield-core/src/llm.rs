use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::process::Stdio;
use std::time::Duration;
use tokio::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Adapter {
    Mock,
    Ollama,
    Cli,
    OpenRouter,
}

impl Adapter {
    pub fn parse(value: &str) -> Result<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "mock" => Ok(Self::Mock),
            "ollama" => Ok(Self::Ollama),
            "cli" => Ok(Self::Cli),
            "openrouter" => Ok(Self::OpenRouter),
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
pub struct LlmOptions {
    pub adapter: Adapter,
    pub model: Option<String>,
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

async fn complete_ollama(messages: &[Message], options: &LlmOptions) -> Result<String> {
    let model = options
        .model
        .clone()
        .unwrap_or_else(|| "gemma4:12b".to_string());
    let body = json!({
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

    let response = reqwest::Client::new()
        .post("http://localhost:11434/api/chat")
        .timeout(options.timeout)
        .json(&body)
        .send()
        .await
        .context("ollama request failed")?;

    let status = response.status();
    let body: serde_json::Value = response.json().await.context("invalid ollama response")?;
    if !status.is_success() {
        bail!("ollama HTTP error {status}: {body}");
    }

    Ok(body
        .pointer("/message/content")
        .and_then(|value| value.as_str())
        .or_else(|| {
            body.pointer("/message/thinking")
                .and_then(|value| value.as_str())
        })
        .unwrap_or("")
        .to_string())
}

async fn complete_openrouter(messages: &[Message], options: &LlmOptions) -> Result<String> {
    let key = std::env::var("OPENROUTER_API_KEY").context("OPENROUTER_API_KEY is not set")?;
    let model = options
        .model
        .clone()
        .unwrap_or_else(|| "openai/gpt-5.5".to_string());
    let body = json!({
        "model": model,
        "messages": messages,
        "temperature": options.temperature,
        "max_tokens": options.max_tokens,
        "seed": options.seed
    });

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
    let body: serde_json::Value = response
        .json()
        .await
        .context("invalid openrouter response")?;
    if !status.is_success() {
        bail!("openrouter HTTP error {status}: {body}");
    }

    Ok(body
        .pointer("/choices/0/message/content")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string())
}

async fn complete_cli(messages: &[Message], options: &LlmOptions) -> Result<String> {
    let command = std::env::var("TRACEFIELD_CLI_COMMAND").unwrap_or_else(|_| "cursor-agent".into());
    let mut args = vec![
        "-p".to_string(),
        "--force".to_string(),
        "--trust".to_string(),
    ];

    if command == "claude" {
        if let Some(model) = &options.model {
            args.push("--model".to_string());
            args.push(model.clone());
        }
    } else if command == "cursor-agent" {
        args.push("--model".to_string());
        args.push(
            options
                .model
                .clone()
                .unwrap_or_else(|| "composer-2.5".to_string()),
        );
    }

    let prompt = messages
        .iter()
        .map(|message| message.content.as_str())
        .collect::<Vec<_>>()
        .join("\n\n");

    args.push(prompt);

    let child = Command::new(&command)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to spawn {command}"))?;

    let output = tokio::time::timeout(options.timeout, child.wait_with_output())
        .await
        .context("CLI adapter timed out")?
        .context("CLI adapter failed")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("CLI adapter exited with {}: {}", output.status, stderr);
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
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
}

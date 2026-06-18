//! Codex app-server adapter: drives Codex via its JSON-RPC 2.0 stdio protocol
//! and records tool/command/file/skill activity as tracefield provenance entries.
//!
//! Wire framing (confirmed empirically against codex v0.140.0):
//!   - One JSON object per line (JSONL / newline-delimited).
//!   - Client requests carry `{"jsonrpc":"2.0","id":<u64>,"method":"...","params":{...}}`.
//!   - Server responses carry `{"id":<u64>,"result":{...}}` (no `jsonrpc` field).
//!   - Server notifications carry `{"method":"...","params":{...}}` (no `id`).
//!   - Server requests carry `{"id":...,"method":"...","params":{...}}` (no `jsonrpc`).
//!   - Handshake: send `initialize` first; server responds with `result`.
//!   - Then `thread/start` → server responds with thread; notification `thread/started`.
//!   - Then `turn/start` with `threadId`; server responds with turn; turn completes
//!     via `turn/completed` notification (method name confirmed from schema).
//!     In practice the process may also signal idle via `thread/status/changed` to
//!     `{type:"idle"}` when `turn/completed` is emitted in the same batch.

use crate::entry::{EntryType, NewEntry};
use crate::llm::{LlmOptions, Message};
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::Stdio;
use std::sync::{Arc, Mutex};

const OUTPUT_CAP: usize = 8000;

// ──────────────────────────────────────────────────────────────────────────
// Public entry point

/// Drive Codex via its app-server protocol (stdio JSON-RPC 2.0) and return
/// the final assistant message plus provenance entries for every tool activity.
///
/// On timeout, the child `codex app-server` process is killed before returning
/// the error, so no orphan process is left behind.
pub(crate) async fn run(
    scenario_dir: &Path,
    author: &str,
    skill_citations: &[String],
    messages: &[Message],
    options: &LlmOptions,
) -> Result<(String, Vec<NewEntry>)> {
    let scenario_dir = scenario_dir.to_path_buf();
    let author = author.to_string();
    let skill_citations = skill_citations.to_vec();
    let messages = messages.to_vec();
    let model = options.model.clone();
    let web_search = options.web_search;

    // Share a kill handle between the blocking task and this async context so
    // that a timeout can terminate the child even though spawn_blocking is not
    // cancellable.
    let child_handle: Arc<Mutex<Option<std::process::Child>>> = Arc::new(Mutex::new(None));
    let child_handle_for_task = Arc::clone(&child_handle);

    let task = tokio::task::spawn_blocking(move || {
        run_sync(
            &scenario_dir,
            &author,
            &skill_citations,
            &messages,
            model,
            web_search,
            child_handle_for_task,
        )
    });

    let result = tokio::time::timeout(options.timeout, task).await;

    match result {
        Ok(join_result) => join_result.context("codex app-server blocking task panicked")?,
        Err(_elapsed) => {
            // Timeout: kill the child so the blocking task unblocks (its stdout
            // read returns EOF), then wait briefly for the task to finish.
            if let Ok(mut guard) = child_handle.lock()
                && let Some(child) = guard.as_mut()
            {
                let _ = child.kill();
            }
            bail!("codex app-server timed out")
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────
// Synchronous driver (stdio)

fn run_sync(
    scenario_dir: &Path,
    author: &str,
    skill_citations: &[String],
    messages: &[Message],
    model: Option<String>,
    web_search: bool,
    child_handle: Arc<Mutex<Option<std::process::Child>>>,
) -> Result<(String, Vec<NewEntry>)> {
    let mut command = std::process::Command::new("codex");
    command.arg("app-server");
    // Enable the native Responses `web_search` tool (no per-call approval) when
    // the organ opts in with `web_search = true`. Equivalent to `codex --search`.
    if web_search {
        command.arg("-c").arg("tools.web_search=true");
    }
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .context("failed to spawn codex app-server")?;

    // Extract stdio handles *before* storing the child in the shared slot.
    // The child (which holds the pid / kill capability) goes into the mutex;
    // the I/O handles are used by the blocking session below.
    let stdin = child.stdin.take().context("no stdin on codex process")?;
    let stdout = child.stdout.take().context("no stdout on codex process")?;

    // Publish the child into the shared handle so the async side can kill it
    // on timeout — killing closes its stdout, which unblocks the blocking read.
    {
        let mut guard = child_handle.lock().unwrap_or_else(|e| e.into_inner());
        *guard = Some(child);
    }

    let result = drive_session(
        stdin,
        stdout,
        scenario_dir,
        author,
        skill_citations,
        messages,
        model,
    );

    // Take the child back and clean up, regardless of whether we succeeded or
    // timed out. If the async timeout already killed it, kill() is a no-op.
    let mut child = {
        let mut guard = child_handle.lock().unwrap_or_else(|e| e.into_inner());
        guard.take()
    };
    if let Some(ref mut c) = child {
        let _ = c.kill();
        let _ = c.wait();
    }

    result
}

fn drive_session(
    stdin: std::process::ChildStdin,
    stdout: std::process::ChildStdout,
    scenario_dir: &Path,
    author: &str,
    skill_citations: &[String],
    messages: &[Message],
    model: Option<String>,
) -> Result<(String, Vec<NewEntry>)> {
    let mut writer = stdin;
    let reader = BufReader::new(stdout);
    let mut lines = reader.lines();

    // 1. Handshake: initialize.
    send(
        &mut writer,
        1,
        "initialize",
        json!({"clientInfo": {"name": "tracefield", "version": "0.1.0"}}),
    )?;
    wait_for_response(&mut lines, 1).context("initialize failed")?;

    // 2. Start a thread with the scenario directory as cwd.
    let cwd = scenario_dir
        .to_str()
        .context("scenario_dir is not valid UTF-8")?;
    send(&mut writer, 2, "thread/start", json!({"cwd": cwd}))?;
    let thread_resp = wait_for_response(&mut lines, 2).context("thread/start failed")?;
    let thread_id = thread_resp
        .pointer("/thread/id")
        .and_then(Value::as_str)
        .context("thread/start response missing thread.id")?
        .to_string();

    // 3. Build the prompt text (same join as complete_cli: contents joined with \n\n).
    let prompt = messages
        .iter()
        .map(|m| m.content.as_str())
        .collect::<Vec<_>>()
        .join("\n\n");

    // 4. Start a turn: read-only sandbox, never ask for approvals.
    // No outputSchema: the strict Responses structured-output schema is highly
    // demanding (recursive additionalProperties:false, array items, etc.) and
    // the prompt already instructs strict JSON, so — as in the `codex exec`
    // path — we let the model follow the prompt instead.
    let mut turn_params = json!({
        "threadId": thread_id,
        "input": [{"type": "text", "text": prompt}],
        "cwd": cwd,
        "sandboxPolicy": {"type": "readOnly"},
        "approvalPolicy": "never",
    });
    if let Some(m) = &model {
        turn_params["model"] = json!(m);
    }
    send(&mut writer, 3, "turn/start", turn_params)?;
    wait_for_response(&mut lines, 3).context("turn/start failed")?;

    // 5. Read notifications until turn/completed.
    collect_turn_output(&mut lines, &mut writer, author, skill_citations)
}

// ──────────────────────────────────────────────────────────────────────────
// Notification collection — generic over writer so it is unit-testable

pub(crate) fn collect_turn_output<W: Write>(
    lines: &mut impl Iterator<Item = std::io::Result<String>>,
    writer: &mut W,
    author: &str,
    skill_citations: &[String],
) -> Result<(String, Vec<NewEntry>)> {
    let mut final_text = String::new();
    let mut provenance = Vec::new();
    // Track agent message text for delta accumulation (used if item/completed text is empty).
    let mut agent_message_delta = String::new();

    for line_result in lines.by_ref() {
        let line = line_result.context("error reading codex stdout")?;
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let msg: Value = serde_json::from_str(line)
            .with_context(|| format!("invalid JSON from codex: {line}"))?;

        // If this is a server→client approval request, deny it so the turn proceeds.
        if let Some(denial) = maybe_denial(&msg) {
            send_raw(writer, &denial)?;
            continue;
        }

        let method = msg.get("method").and_then(Value::as_str).unwrap_or("");
        let params = msg.get("params").unwrap_or(&Value::Null);

        match method {
            "turn/completed" => {
                // Use accumulated delta if the final text is still empty.
                if final_text.is_empty() && !agent_message_delta.is_empty() {
                    final_text = std::mem::take(&mut agent_message_delta);
                }
                return Ok((final_text, provenance));
            }
            "item/agentMessage/delta" => {
                let delta = params.get("delta").and_then(Value::as_str).unwrap_or("");
                agent_message_delta.push_str(delta);
            }
            "item/completed" => {
                let item = params.get("item").unwrap_or(&Value::Null);
                if let Some(Some((text, prov))) = map_item_completed(item, author, skill_citations)
                {
                    if !text.is_empty() {
                        final_text = text;
                    }
                    provenance.extend(prov);
                }
            }
            "skills/changed" => {
                let entry = NewEntry::new(
                    EntryType::Observation,
                    author,
                    format!("{author} observed codex skills changed"),
                )
                .with_citations(skill_citations.to_vec())
                .with_meta("kind", json!("codex_skill"))
                .with_meta("detail", json!("skills/changed"));
                provenance.push(entry);
            }
            _ => {} // ignore other notifications
        }
    }

    // EOF before turn/completed: use whatever we have.
    if final_text.is_empty() {
        final_text = agent_message_delta;
    }
    Ok((final_text, provenance))
}

/// If `msg` is a server→client approval request, return a denial response.
pub(crate) fn maybe_denial(msg: &Value) -> Option<Value> {
    let id = msg.get("id")?;
    let method = msg.get("method").and_then(Value::as_str)?;
    // Server requests have an `id` and a `method` but no `jsonrpc` field.
    // (Notifications have a `method` but no `id`.)
    match method {
        "item/commandExecution/requestApproval" => Some(json!({
            "id": id,
            "result": {"decision": "decline"}
        })),
        "item/fileChange/requestApproval" => Some(json!({
            "id": id,
            "result": {"decision": "decline"}
        })),
        "item/tool/requestUserInput" | "mcpServer/elicitation/request" => Some(json!({
            "id": id,
            "result": null
        })),
        _ => None,
    }
}

// ──────────────────────────────────────────────────────────────────────────
// Item mapping — pure function, unit-testable without a live server

/// Map an `item/completed` item to `(final_text, provenance_entries)`.
/// Returns `None` if the item type is not tracked.
pub(crate) fn map_item_completed(
    item: &Value,
    author: &str,
    skill_citations: &[String],
) -> Option<Option<(String, Vec<NewEntry>)>> {
    let item_type = item.get("type").and_then(Value::as_str)?;
    match item_type {
        "agentMessage" => {
            let text = item
                .get("text")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let text = cap(text);
            Some(Some((text, Vec::new())))
        }
        "commandExecution" => {
            let command = item
                .get("command")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let output = item
                .get("aggregatedOutput")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let detail = if output.is_empty() {
                command.clone()
            } else {
                format!("{command}: {}", cap(output))
            };
            let entry = NewEntry::new(
                EntryType::Observation,
                author,
                format!("{author} ran command: {command}"),
            )
            .with_citations(skill_citations.to_vec())
            .with_meta("kind", json!("codex_command"))
            .with_meta("detail", json!(cap(detail)));
            Some(Some((String::new(), vec![entry])))
        }
        "fileChange" => {
            let paths = item
                .get("changes")
                .and_then(Value::as_array)
                .map(|changes| {
                    changes
                        .iter()
                        .filter_map(|c| c.get("path").and_then(Value::as_str))
                        .collect::<Vec<_>>()
                        .join(", ")
                })
                .unwrap_or_default();
            let entry = NewEntry::new(
                EntryType::Observation,
                author,
                format!("{author} file change: {paths}"),
            )
            .with_citations(skill_citations.to_vec())
            .with_meta("kind", json!("codex_file_change"))
            .with_meta("detail", json!(cap(paths)));
            Some(Some((String::new(), vec![entry])))
        }
        "mcpToolCall" => {
            let tool = item
                .get("tool")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let server = item
                .get("server")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let detail = if server.is_empty() {
                tool.clone()
            } else {
                format!("{server}/{tool}")
            };
            let entry = NewEntry::new(
                EntryType::Observation,
                author,
                format!("{author} MCP tool call: {detail}"),
            )
            .with_citations(skill_citations.to_vec())
            .with_meta("kind", json!("codex_tool_call"))
            .with_meta("detail", json!(detail));
            Some(Some((String::new(), vec![entry])))
        }
        "webSearch" => {
            let query = item
                .get("query")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let entry = NewEntry::new(
                EntryType::Observation,
                author,
                format!("{author} web search: {query}"),
            )
            .with_citations(skill_citations.to_vec())
            .with_meta("kind", json!("codex_web_search"))
            .with_meta("detail", json!(cap(query)));
            Some(Some((String::new(), vec![entry])))
        }
        _ => None,
    }
}

// ──────────────────────────────────────────────────────────────────────────
// JSON-RPC helpers

fn send<W: Write>(writer: &mut W, id: u64, method: &str, params: Value) -> Result<()> {
    let msg = json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params});
    send_raw(writer, &msg)
}

fn send_raw<W: Write>(writer: &mut W, msg: &Value) -> Result<()> {
    let line = serde_json::to_string(msg).context("failed to serialize JSON-RPC message")?;
    writeln!(writer, "{line}").context("failed to write to codex stdin")?;
    writer.flush().context("failed to flush codex stdin")?;
    Ok(())
}

/// Read lines until we see a JSON object with `"id": id` and a `"result"` field.
fn wait_for_response(
    lines: &mut impl Iterator<Item = std::io::Result<String>>,
    id: u64,
) -> Result<Value> {
    for line_result in lines.by_ref() {
        let line = line_result.context("error reading codex stdout")?;
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let msg: Value = serde_json::from_str(line)
            .with_context(|| format!("invalid JSON from codex: {line}"))?;

        let msg_id = msg.get("id").and_then(Value::as_u64);
        if msg_id != Some(id) {
            // Not our response; keep reading (notifications may arrive first).
            continue;
        }
        if let Some(error) = msg.get("error") {
            bail!("codex app-server error for request {id}: {error}");
        }
        return Ok(msg.get("result").cloned().unwrap_or(Value::Null));
    }
    bail!("codex app-server EOF while waiting for response to request {id}")
}

fn cap(mut text: String) -> String {
    if text.len() > OUTPUT_CAP {
        text.truncate(OUTPUT_CAP);
        text.push_str("\n…(truncated)");
    }
    text
}

// ──────────────────────────────────────────────────────────────────────────
// Tests

#[cfg(test)]
mod tests {
    use super::*;

    fn citations() -> Vec<String> {
        vec!["e1".to_string(), "e2".to_string()]
    }

    /// Feed a full notification stream through `collect_turn_output` using an
    /// in-memory writer, and assert: final_text is the agent message, the
    /// command produces one codex_command provenance entry, and the approval
    /// request got a decline written to the sink.
    #[test]
    fn collect_turn_output_drives_full_stream() {
        let notifications = vec![
            // noise before the interesting items
            json!({"method": "turn/started", "params": {"threadId": "t1"}}),
            json!({"method": "item/started", "params": {"item": {"type": "reasoning", "id": "r1"}}}),
            json!({"method": "item/completed", "params": {"item": {"type": "reasoning", "id": "r1", "content": []}}}),
            // server→client approval request — should be declined
            json!({"id": 99, "method": "item/commandExecution/requestApproval", "params": {"command": "rm -rf /"}}),
            // completed command execution
            json!({"method": "item/completed", "params": {"item": {
                "type": "commandExecution",
                "id": "c1",
                "command": "echo hi",
                "aggregatedOutput": "hi",
                "exitCode": 0
            }}}),
            // agent message arrives via delta then item/completed
            json!({"method": "item/started", "params": {"item": {"type": "agentMessage", "id": "m1", "text": ""}}}),
            json!({"method": "item/agentMessage/delta", "params": {"itemId": "m1", "delta": "hello "}}),
            json!({"method": "item/agentMessage/delta", "params": {"itemId": "m1", "delta": "world"}}),
            json!({"method": "item/completed", "params": {"item": {"type": "agentMessage", "id": "m1", "text": "hello world"}}}),
            // turn/completed terminates the loop
            json!({"method": "turn/completed", "params": {"threadId": "t1"}}),
        ];

        let lines_str = notifications
            .iter()
            .map(|v| serde_json::to_string(v).unwrap())
            .collect::<Vec<_>>()
            .join("\n");

        let mut sink: Vec<u8> = Vec::new();
        let mut lines = BufReader::new(lines_str.as_bytes()).lines();

        let (text, prov) = collect_turn_output(&mut lines, &mut sink, "A1", &citations()).unwrap();

        // Final text comes from the agentMessage item/completed.
        assert_eq!(text, "hello world");

        // One command provenance entry.
        assert_eq!(prov.len(), 1);
        assert_eq!(prov[0].meta["kind"], json!("codex_command"));
        assert_eq!(prov[0].meta["detail"].as_str().unwrap(), "echo hi: hi");
        assert_eq!(prov[0].citations, citations());

        // The denial for the approval request was written to the sink.
        let written = String::from_utf8(sink).unwrap();
        let denial: Value = serde_json::from_str(written.trim()).unwrap();
        assert_eq!(denial["id"], json!(99));
        assert_eq!(denial["result"]["decision"], json!("decline"));
    }

    #[test]
    fn collect_turn_output_falls_back_to_delta_when_completed_text_empty() {
        // Some server versions may send empty text in item/completed for agentMessage
        // and only populate deltas; verify we fall back to the accumulated delta.
        let lines_str = [
            json!({"method": "item/agentMessage/delta", "params": {"itemId": "m1", "delta": "delta-only"}}),
            json!({"method": "item/completed", "params": {"item": {"type": "agentMessage", "id": "m1", "text": ""}}}),
            json!({"method": "turn/completed", "params": {}}),
        ]
        .iter()
        .map(|v| serde_json::to_string(v).unwrap())
        .collect::<Vec<_>>()
        .join("\n");
        let mut sink: Vec<u8> = Vec::new();
        let mut lines = BufReader::new(lines_str.as_bytes()).lines();
        let (text, _) = collect_turn_output(&mut lines, &mut sink, "A1", &[]).unwrap();
        assert_eq!(text, "delta-only");
    }

    #[test]
    fn agent_message_item_extracts_final_text() {
        let item = json!({"type": "agentMessage", "text": "hello world", "phase": "final_answer"});
        let result = map_item_completed(&item, "A1", &citations())
            .unwrap()
            .unwrap();
        assert_eq!(result.0, "hello world");
        assert!(result.1.is_empty());
    }

    #[test]
    fn command_execution_item_produces_provenance_entry() {
        let item = json!({
            "type": "commandExecution",
            "command": "ls -la",
            "aggregatedOutput": "total 8\ndrwxr-xr-x  2 user  group  64 Jan 1 00:00 .",
            "exitCode": 0
        });
        let result = map_item_completed(&item, "A1", &citations())
            .unwrap()
            .unwrap();
        assert!(
            result.0.is_empty(),
            "commandExecution should not set final text"
        );
        assert_eq!(result.1.len(), 1);
        let entry = &result.1[0];
        assert_eq!(entry.entry_type, EntryType::Observation);
        assert!(entry.text.contains("ls -la"), "text should mention command");
        assert_eq!(entry.meta["kind"], json!("codex_command"));
        assert!(entry.meta["detail"].as_str().unwrap().contains("ls -la"));
        assert_eq!(entry.citations, citations());
    }

    #[test]
    fn file_change_item_produces_provenance_entry() {
        let item = json!({
            "type": "fileChange",
            "changes": [
                {"path": "/tmp/foo.rs", "diff": "...", "kind": "modify"},
                {"path": "/tmp/bar.rs", "diff": "...", "kind": "create"}
            ],
            "status": "completed"
        });
        let result = map_item_completed(&item, "A1", &citations())
            .unwrap()
            .unwrap();
        assert!(result.0.is_empty());
        let entry = &result.1[0];
        assert_eq!(entry.meta["kind"], json!("codex_file_change"));
        let detail = entry.meta["detail"].as_str().unwrap();
        assert!(detail.contains("/tmp/foo.rs"));
        assert!(detail.contains("/tmp/bar.rs"));
    }

    #[test]
    fn mcp_tool_call_item_produces_provenance_entry() {
        let item = json!({
            "type": "mcpToolCall",
            "tool": "read_file",
            "server": "filesystem",
            "arguments": {"path": "/tmp/x"},
            "status": "completed"
        });
        let result = map_item_completed(&item, "A1", &citations())
            .unwrap()
            .unwrap();
        assert!(result.0.is_empty());
        let entry = &result.1[0];
        assert_eq!(entry.meta["kind"], json!("codex_tool_call"));
        assert_eq!(entry.meta["detail"], json!("filesystem/read_file"));
    }

    #[test]
    fn untracked_item_type_returns_none() {
        let item = json!({"type": "reasoning", "content": []});
        assert!(map_item_completed(&item, "A1", &citations()).is_none());
    }

    #[test]
    fn maybe_denial_handles_command_approval_request() {
        let req = json!({
            "id": 42,
            "method": "item/commandExecution/requestApproval",
            "params": {"command": "rm -rf /"}
        });
        let denial = maybe_denial(&req).unwrap();
        assert_eq!(denial["id"], json!(42));
        assert_eq!(denial["result"]["decision"], json!("decline"));
    }

    #[test]
    fn maybe_denial_handles_file_change_approval_request() {
        let req = json!({
            "id": 7,
            "method": "item/fileChange/requestApproval",
            "params": {}
        });
        let denial = maybe_denial(&req).unwrap();
        assert_eq!(denial["result"]["decision"], json!("decline"));
    }

    #[test]
    fn maybe_denial_ignores_notifications() {
        let notif = json!({"method": "turn/completed", "params": {}});
        assert!(maybe_denial(&notif).is_none());
    }

    #[test]
    fn cap_truncates_long_text() {
        let long = "x".repeat(OUTPUT_CAP + 100);
        let result = cap(long);
        assert!(result.len() <= OUTPUT_CAP + 20);
        assert!(result.ends_with("…(truncated)"));
    }

    #[test]
    fn cap_leaves_short_text_intact() {
        let short = "hello".to_string();
        assert_eq!(cap(short.clone()), short);
    }

    /// Integration test: spawns a real codex app-server and runs a trivial turn.
    /// Ignored by default so CI does not require codex credentials.
    #[tokio::test]
    #[ignore]
    async fn integration_run_trivial_turn() {
        let dir = tempfile::tempdir().unwrap();
        let options = crate::llm::LlmOptions {
            adapter: crate::llm::Adapter::CodexAppServer,
            ..crate::llm::LlmOptions::default()
        };
        let messages = vec![crate::llm::Message::user("Reply with exactly: pong")];
        let (text, _provenance) = run(dir.path(), "test", &[], &messages, &options)
            .await
            .unwrap();
        assert!(!text.is_empty(), "expected a non-empty response from codex");
    }
}

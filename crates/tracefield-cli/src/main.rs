use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use serde_json::Value;
use std::{
    env, fs,
    path::{Path, PathBuf},
};
use tracefield_core::{ConsultOptions, run_consult};

#[derive(Debug, Parser)]
#[command(name = "tracefield")]
#[command(about = "Governable exploration for multi-agent systems")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Consult a scenario and return governed findings.
    Consult {
        #[arg(long, alias = "scenario", value_name = "DIR")]
        scenario_dir: PathBuf,
        #[arg(long, default_value = "cli")]
        adapter: String,
        #[arg(long, value_name = "MODEL")]
        model: Option<String>,
        #[arg(long, default_value_t = 2)]
        rounds: usize,
        #[arg(long)]
        json: bool,
        #[arg(long, value_name = "FILE")]
        out: Option<PathBuf>,
        #[arg(long, value_name = "JSONL")]
        persist: Option<PathBuf>,
    },
    /// Scaffold a new generic scenario.
    New {
        name: String,
        #[arg(long, value_name = "DIR")]
        dir: Option<PathBuf>,
        #[arg(long)]
        force: bool,
    },
    /// Retract an entry in a persisted JSONL store.
    Retract {
        #[arg(long, value_name = "JSONL")]
        store: PathBuf,
        #[arg(long)]
        entry: String,
        #[arg(long, default_value = "operator")]
        author: String,
    },
    /// Check local runtime dependencies.
    Doctor,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Consult {
            scenario_dir,
            adapter,
            model,
            rounds,
            json,
            out,
            persist,
        } => {
            ensure_directory(&scenario_dir, "--scenario-dir")?;
            ensure_positive_rounds(rounds)?;

            let result = run_consult(ConsultOptions {
                scenario_dir: scenario_dir.clone(),
                adapter: adapter.clone(),
                model,
                rounds,
                persist_path: persist.clone(),
            })
            .await
            .with_context(|| {
                format!(
                    "failed to consult scenario {} with adapter {adapter}",
                    scenario_dir.display()
                )
            })?;

            let encoded = serde_json::to_string_pretty(&result)
                .context("failed to encode consult result as JSON")?;
            if let Some(out) = out {
                write_text(&out, &encoded)
                    .with_context(|| format!("failed to write JSON report to {}", out.display()))?;
            }
            if json {
                println!(
                    "{}",
                    serde_json::to_string(&result)
                        .context("failed to encode compact consult JSON")?
                );
            } else {
                print_consult_report(&result).context("failed to render consult report")?;
                if let Some(path) = persist {
                    println!();
                    println!("persisted store: {}", path.display());
                }
            }
        }
        Command::New { name, dir, force } => {
            let target = tracefield_core::scenario::scaffold(&name, dir.as_deref(), force)
                .with_context(|| format!("failed to scaffold scenario {name}"))?;

            println!("scaffolded {}", target.display());
            println!();
            println!(
                "Next: tracefield consult --scenario-dir {} --adapter mock",
                target.display()
            );
        }
        Command::Retract {
            store,
            entry,
            author,
        } => {
            ensure_file(&store, "--store")?;

            let mut reference = tracefield_core::ReferenceStore::from_jsonl_path(&store)
                .with_context(|| format!("failed to load persisted store {}", store.display()))?;
            let affected = reference
                .retract(&entry, &author)
                .with_context(|| format!("failed to retract entry {entry}"))?;
            reference
                .write_jsonl(&store)
                .with_context(|| format!("failed to persist retraction to {}", store.display()))?;

            print_retract_report(&entry, &affected)?;
        }
        Command::Doctor => {
            print_doctor().await;
        }
    }

    Ok(())
}

fn ensure_directory(path: &Path, label: &str) -> Result<()> {
    if !path.exists() {
        bail!("{label} does not exist: {}", path.display());
    }
    if !path.is_dir() {
        bail!("{label} is not a directory: {}", path.display());
    }
    Ok(())
}

fn ensure_file(path: &Path, label: &str) -> Result<()> {
    if !path.exists() {
        bail!("{label} does not exist: {}", path.display());
    }
    if !path.is_file() {
        bail!("{label} is not a file: {}", path.display());
    }
    Ok(())
}

fn ensure_positive_rounds(rounds: usize) -> Result<()> {
    if rounds == 0 {
        bail!("--rounds must be at least 1");
    }
    Ok(())
}

fn write_text(path: &Path, text: &str) -> Result<()> {
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::write(path, text)?;
    Ok(())
}

fn print_consult_report(result: &tracefield_core::ConsultResult) -> Result<()> {
    let value = serde_json::to_value(result).context("failed to convert consult result to JSON")?;

    println!("# tracefield consult");
    println!();

    if let Some(task) = value.get("task").and_then(Value::as_str) {
        println!("task: {}", first_line(task));
        println!();
    }

    if let Some(deliberation) = value.get("deliberation").and_then(Value::as_array) {
        println!("## deliberation");
        if deliberation.is_empty() {
            println!("(none)");
        } else {
            for entry in deliberation {
                print_entry_line(entry);
            }
        }
        println!();
    }

    if let Some(synthesis) = value.get("synthesis") {
        println!("## synthesis");
        print_synthesis(synthesis);
    }

    Ok(())
}

fn print_retract_report<T>(entry: &str, affected: &T) -> Result<()>
where
    T: serde::Serialize,
{
    let affected = serde_json::to_value(affected).context("failed to encode affected entries")?;
    let count = affected
        .as_array()
        .map(|entries| entries.len().to_string())
        .or_else(|| {
            affected
                .get("closure_size")
                .and_then(Value::as_u64)
                .map(|count| count.to_string())
        })
        .unwrap_or_else(|| "unknown".to_string());

    println!("retracted {entry} -> closure {count} entries");
    if affected.as_array().is_some_and(Vec::is_empty) {
        return Ok(());
    }

    println!();
    println!("## affected");
    if let Some(entries) = affected.as_array() {
        for entry in entries {
            print_entry_line(entry);
        }
    } else {
        println!("{}", serde_json::to_string_pretty(&affected)?);
    }

    Ok(())
}

async fn print_doctor() {
    println!("tracefield doctor");
    println!();
    println!("Adapters");
    println!("- mock: ok");
    println!(
        "- ollama: {}",
        if tracefield_core::llm::ollama_available().await {
            "ok"
        } else {
            "not reachable at localhost:11434"
        }
    );
    println!(
        "- openrouter: {}",
        if env::var("OPENROUTER_API_KEY").is_ok() {
            "OPENROUTER_API_KEY set"
        } else {
            "OPENROUTER_API_KEY not set"
        }
    );
    println!(
        "- cli: {}",
        match (find_on_path("cursor-agent"), find_on_path("claude")) {
            (true, true) => "cursor-agent, claude found",
            (true, false) => "cursor-agent found",
            (false, true) => "claude found",
            (false, false) => "cursor-agent/claude not found on PATH",
        }
    );
}

fn print_synthesis(value: &Value) {
    match value {
        Value::Null => println!("(none)"),
        Value::Array(entries) if entries.is_empty() => println!("(none)"),
        Value::Array(entries) => {
            for entry in entries {
                print_entry_line(entry);
            }
        }
        Value::Object(map) => {
            if let Some(findings) = map
                .get("findings")
                .or_else(|| map.get("entries"))
                .and_then(Value::as_array)
            {
                if findings.is_empty() {
                    println!("(none)");
                } else {
                    for entry in findings {
                        print_entry_line(entry);
                    }
                }
            } else {
                print_json_summary(value);
            }
        }
        _ => print_json_summary(value),
    }
}

fn print_entry_line(entry: &Value) {
    let id = entry.get("id").and_then(Value::as_str).unwrap_or("-");
    let author = entry
        .get("author")
        .or_else(|| entry.get("role"))
        .and_then(Value::as_str)
        .unwrap_or("-");
    let text = entry
        .get("text")
        .or_else(|| entry.get("body"))
        .or_else(|| entry.get("content"))
        .and_then(Value::as_str)
        .unwrap_or("");

    if text.is_empty() {
        println!("- [{id}] {author}");
    } else {
        println!("- [{id}] {author}: {}", first_line(text));
    }
}

fn print_json_summary(value: &Value) {
    match serde_json::to_string_pretty(value) {
        Ok(text) => println!("{text}"),
        Err(_) => println!("{value}"),
    }
}

fn first_line(text: &str) -> &str {
    text.lines().next().unwrap_or("").trim()
}

fn find_on_path(binary: &str) -> bool {
    let Some(paths) = env::var_os("PATH") else {
        return false;
    };

    env::split_paths(&paths).any(|path| path.join(binary).is_file())
}

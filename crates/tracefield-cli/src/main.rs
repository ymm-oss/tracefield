use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use serde_json::Value;
use std::{
    env, fs,
    path::{Path, PathBuf},
};
use tracefield_core::{FlowRunOptions, WebInputOptions, ingest_web_inputs, run_flow};

#[derive(Debug, Parser)]
#[command(name = "tracefield")]
#[command(about = "Governable exploration for multi-agent systems")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Run a configured Field Runner flow from flow.toml.
    Run {
        #[arg(long, alias = "scenario", value_name = "DIR")]
        scenario_dir: PathBuf,
        #[arg(long, value_name = "FILE")]
        config: Option<PathBuf>,
        #[arg(long)]
        budget: Option<usize>,
        #[arg(long)]
        json: bool,
        #[arg(long, value_name = "FILE")]
        out: Option<PathBuf>,
        #[arg(long, value_name = "JSONL")]
        persist: Option<PathBuf>,
    },
    /// Fetch web pages into inputs/web for Field Runner flows.
    WebInput {
        #[arg(long, alias = "scenario", value_name = "DIR")]
        scenario_dir: PathBuf,
        #[arg(long = "url", value_name = "URL")]
        urls: Vec<String>,
        #[arg(long, value_name = "FILE")]
        url_file: Option<PathBuf>,
        #[arg(long, value_name = "DIR", default_value = "inputs/web")]
        out_dir: PathBuf,
        #[arg(long, default_value_t = 1_000_000)]
        max_bytes: usize,
        #[arg(long)]
        force: bool,
        #[arg(long)]
        json: bool,
    },
    /// Scaffold a new generic scenario.
    New {
        name: String,
        #[arg(long, value_name = "DIR")]
        dir: Option<PathBuf>,
        #[arg(long, default_value = "default")]
        profile: String,
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
    /// Supersede an entry with a replacement in a persisted JSONL store.
    Supersede {
        #[arg(long, value_name = "JSONL")]
        store: PathBuf,
        #[arg(long)]
        entry: String,
        #[arg(long, value_name = "ENTRY")]
        with: String,
    },
    /// Mechanically aggregate adjudication verdicts in a persisted JSONL store.
    Aggregate {
        #[arg(long, value_name = "JSONL")]
        store: PathBuf,
        #[arg(long, default_value = "adjudication")]
        stage: String,
        #[arg(long)]
        json: bool,
    },
    /// Check local runtime dependencies.
    Doctor,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::New {
            name,
            dir,
            profile,
            force,
        } => {
            let target = tracefield_core::scenario::scaffold_with_profile(
                &name,
                dir.as_deref(),
                force,
                &profile,
            )
            .with_context(|| format!("failed to scaffold scenario {name}"))?;

            println!("scaffolded {}", target.display());
            println!("profile: {profile}");
            println!();
            println!(
                "Next: tracefield run --scenario-dir {} --config flow.toml",
                target.display()
            );
        }
        Command::Run {
            scenario_dir,
            config,
            budget,
            json,
            out,
            persist,
        } => {
            ensure_directory(&scenario_dir, "--scenario-dir")?;
            if let Some(config) = &config {
                ensure_file(config, "--config")?;
            }

            let result = run_flow(FlowRunOptions {
                scenario_dir: scenario_dir.clone(),
                config_path: config.clone(),
                budget,
                persist_path: persist.clone(),
            })
            .await
            .with_context(|| format!("failed to run flow {}", scenario_dir.display()))?;

            let encoded =
                serde_json::to_string_pretty(&result).context("failed to encode run result")?;
            if let Some(out) = out {
                write_text(&out, &encoded)
                    .with_context(|| format!("failed to write JSON report to {}", out.display()))?;
            }
            if json {
                println!("{}", serde_json::to_string(&result)?);
            } else {
                print_run_report(&result).context("failed to render run report")?;
                if let Some(path) = persist {
                    println!();
                    println!("persisted store: {}", path.display());
                }
            }
        }
        Command::WebInput {
            scenario_dir,
            urls,
            url_file,
            out_dir,
            max_bytes,
            force,
            json,
        } => {
            ensure_directory(&scenario_dir, "--scenario-dir")?;
            let urls = collect_web_input_urls(urls, url_file.as_deref())?;
            let result = ingest_web_inputs(WebInputOptions {
                scenario_dir: scenario_dir.clone(),
                urls,
                out_dir,
                max_bytes,
                force,
            })
            .await
            .with_context(|| {
                format!(
                    "failed to ingest web inputs into {}",
                    scenario_dir.display()
                )
            })?;

            if json {
                println!("{}", serde_json::to_string(&result)?);
            } else {
                print_web_input_report(&result);
            }
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

            print_closure_report(&format!("retracted {entry}"), &affected)?;
        }
        Command::Supersede {
            store,
            entry,
            with,
        } => {
            ensure_file(&store, "--store")?;

            let mut reference = tracefield_core::ReferenceStore::from_jsonl_path(&store)
                .with_context(|| format!("failed to load persisted store {}", store.display()))?;
            let affected = reference
                .supersede(&entry, &with)
                .with_context(|| format!("failed to supersede entry {entry} with {with}"))?;
            reference
                .write_jsonl(&store)
                .with_context(|| format!("failed to persist supersession to {}", store.display()))?;

            print_closure_report(&format!("superseded {entry} by {with}"), &affected)?;
        }
        Command::Aggregate { store, stage, json } => {
            ensure_file(&store, "--store")?;

            let reference = tracefield_core::ReferenceStore::from_jsonl_path(&store)
                .with_context(|| format!("failed to load persisted store {}", store.display()))?;
            let report = aggregate_verdicts(&reference, &stage);

            if json {
                println!("{}", serde_json::to_string(&report)?);
            } else {
                print_aggregate_report(&report);
            }
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

fn collect_web_input_urls(mut urls: Vec<String>, url_file: Option<&Path>) -> Result<Vec<String>> {
    if let Some(path) = url_file {
        ensure_file(path, "--url-file")?;
        let text = fs::read_to_string(path)
            .with_context(|| format!("failed to read URL file {}", path.display()))?;
        urls.extend(
            text.lines()
                .map(str::trim)
                .filter(|line| !line.is_empty() && !line.starts_with('#'))
                .map(ToOwned::to_owned),
        );
    }

    urls.retain(|url| !url.trim().is_empty());
    urls.dedup();
    if urls.is_empty() {
        bail!("provide at least one --url or --url-file");
    }
    Ok(urls)
}

fn print_web_input_report(result: &tracefield_core::WebInputResult) {
    println!("# tracefield web-input");
    println!();
    println!("pages: {}", result.pages.len());
    println!();
    for page in &result.pages {
        let title = page.title.as_deref().unwrap_or("(untitled)");
        println!(
            "- {} -> {} ({}, {} bytes)",
            page.url, page.path, title, page.bytes
        );
    }
}

fn print_run_report(result: &tracefield_core::FlowRunResult) -> Result<()> {
    let value = serde_json::to_value(result).context("failed to convert run result to JSON")?;

    println!("# tracefield run");
    println!();

    if let Some(task) = value.get("task").and_then(Value::as_str) {
        println!("task: {}", first_line(task));
    }
    if let Some(profile) = value.get("profile").and_then(Value::as_str) {
        println!("profile: {profile}");
    }
    if let Some(policy) = value.get("policy").and_then(Value::as_str) {
        println!("policy: {policy}");
    }
    println!();

    println!("## stages");
    if let Some(stages) = value.get("stages").and_then(Value::as_array) {
        if stages.is_empty() {
            println!("(none)");
        } else {
            for stage in stages {
                let id = stage.get("id").and_then(Value::as_str).unwrap_or("stage");
                let actor_count = stage
                    .get("actor_count")
                    .and_then(Value::as_u64)
                    .unwrap_or(0);
                let entry_count = stage
                    .get("entries")
                    .and_then(Value::as_array)
                    .map(Vec::len)
                    .unwrap_or(0);
                println!("- {id}: actors={actor_count}, entries={entry_count}");
            }
        }
    }
    println!();

    println!("## entries");
    if let Some(entries) = value.get("entries").and_then(Value::as_array) {
        if entries.is_empty() {
            println!("(none)");
        } else {
            for entry in entries {
                print_entry_line(entry);
            }
        }
    }
    println!();

    println!("## artifacts");
    if let Some(artifacts) = value.get("artifacts").and_then(Value::as_array) {
        if artifacts.is_empty() {
            println!("(none)");
        } else {
            for artifact in artifacts {
                let id = artifact
                    .get("id")
                    .and_then(Value::as_str)
                    .unwrap_or("artifact");
                let path = artifact.get("path").and_then(Value::as_str).unwrap_or("");
                let manifest_path = artifact
                    .get("manifest_path")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                let format = artifact
                    .get("format")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown");
                if manifest_path.is_empty() {
                    println!("- {id} ({format}): {path}");
                } else {
                    println!("- {id} ({format}): {path} [manifest: {manifest_path}]");
                }
            }
        }
    }

    Ok(())
}

#[derive(Debug, serde::Serialize)]
struct VerdictRecord {
    id: String,
    author: String,
    class: String,
    text: String,
}

#[derive(Debug, serde::Serialize)]
struct AggregateReport {
    stage: String,
    total: usize,
    conclusion: String,
    overturn: Vec<String>,
    conditional: Vec<String>,
    reject: Vec<String>,
    maintain: Vec<String>,
    unclassified: Vec<String>,
    records: Vec<VerdictRecord>,
}

/// Classify one adjudication verdict from its explicit `判定` label, looking only
/// at the head of that label so downstream prose (which may quote 覆す/維持) cannot
/// contaminate the class.
fn classify_verdict(text: &str) -> &'static str {
    // Anchor on the explicit verdict label "判定:" / "判定：" (with a colon) so a bare
    // "判定" inside prose (e.g. "準拠判定を保留") cannot be mistaken for the label.
    let anchor = text.find("判定:").or_else(|| text.find("判定："));
    let head: String = match anchor {
        Some(idx) => text[idx..].chars().take(24).collect(),
        None => return "unclassified",
    };
    if head.contains("却下") {
        "reject"
    } else if head.contains("条件付き") {
        "conditional"
    } else if head.contains("結論変更") {
        "overturn"
    } else if head.contains("維持") {
        "maintain"
    } else {
        "unclassified"
    }
}

/// Deterministically fold per-refutation adjudication verdicts into a standing
/// conclusion: any overturn changes the conclusion; an unclassified verdict blocks
/// a clean fold; otherwise the conclusion is maintained under the union of the
/// conditional verdicts. No LLM, no silent drops.
fn aggregate_verdicts(reference: &tracefield_core::ReferenceStore, stage: &str) -> AggregateReport {
    let mut records = Vec::new();
    for entry in reference.all() {
        if entry.status != tracefield_core::EntryStatus::Active {
            continue;
        }
        if entry.entry_type != tracefield_core::EntryType::Decision {
            continue;
        }
        if entry.meta.get("stage").and_then(Value::as_str) != Some(stage) {
            continue;
        }
        records.push(VerdictRecord {
            id: entry.id.clone(),
            author: entry.author.clone(),
            class: classify_verdict(&entry.text).to_string(),
            text: entry.text.clone(),
        });
    }

    let ids = |class: &str| {
        records
            .iter()
            .filter(|record| record.class == class)
            .map(|record| record.id.clone())
            .collect::<Vec<_>>()
    };
    let overturn = ids("overturn");
    let conditional = ids("conditional");
    let reject = ids("reject");
    let maintain = ids("maintain");
    let unclassified = ids("unclassified");

    let conclusion = if !overturn.is_empty() {
        "changed"
    } else if !unclassified.is_empty() {
        "indeterminate"
    } else {
        "maintained"
    }
    .to_string();

    AggregateReport {
        stage: stage.to_string(),
        total: records.len(),
        conclusion,
        overturn,
        conditional,
        reject,
        maintain,
        unclassified,
        records,
    }
}

fn print_aggregate_report(report: &AggregateReport) {
    println!(
        "aggregate stage={} verdicts={} -> conclusion: {}",
        report.stage, report.total, report.conclusion
    );
    println!(
        "  overturn={} conditional={} reject={} maintain={} unclassified={}",
        report.overturn.len(),
        report.conditional.len(),
        report.reject.len(),
        report.maintain.len(),
        report.unclassified.len()
    );
    if !report.overturn.is_empty() {
        println!();
        println!("## overturning verdicts (conclusion changed)");
        for id in &report.overturn {
            println!("- {id}");
        }
    }
    if !report.unclassified.is_empty() {
        println!();
        println!("## unclassified verdicts (block clean fold — need attention)");
        for id in &report.unclassified {
            println!("- {id}");
        }
    }
    if report.conclusion == "maintained" && !report.conditional.is_empty() {
        println!();
        println!("## conditions to honor (union of conditional verdicts)");
        for record in report.records.iter().filter(|r| r.class == "conditional") {
            println!("- [{}] {}", record.id, first_line(&record.text));
        }
    }
}

fn print_closure_report<T>(headline: &str, affected: &T) -> Result<()>
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

    println!("{headline} -> closure {count} entries");
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
    let cli_tools = ["cursor-agent", "claude", "codex"]
        .into_iter()
        .filter(|tool| find_on_path(tool))
        .collect::<Vec<_>>();
    println!(
        "- cli: {}",
        if cli_tools.is_empty() {
            "cursor-agent/claude/codex not found on PATH".to_string()
        } else {
            format!("{} found", cli_tools.join(", "))
        }
    );
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

fn first_line(text: &str) -> &str {
    text.lines().next().unwrap_or("").trim()
}

fn find_on_path(binary: &str) -> bool {
    let Some(paths) = env::var_os("PATH") else {
        return false;
    };

    env::split_paths(&paths).any(|path| path.join(binary).is_file())
}

#[cfg(test)]
mod tests {
    use super::classify_verdict;

    #[test]
    fn classifies_canonical_labels() {
        assert_eq!(classify_verdict("判定: 結論変更を要する(覆る)。根拠..."), "overturn");
        assert_eq!(classify_verdict("判定: 条件付きで結論維持(B)。条件: ..."), "conditional");
        assert_eq!(classify_verdict("判定: 却下。論理的欠陥は..."), "reject");
    }

    #[test]
    fn prose_does_not_contaminate_class() {
        // "覆す" / "維持" appear later in prose but must not flip the verdict class.
        assert_eq!(
            classify_verdict("判定: 却下。暫定合意Bを覆すに足る論理的欠陥があり結論Bを維持する。"),
            "reject"
        );
        assert_eq!(
            classify_verdict("判定: 条件付きで結論維持(B)。e24は有効だが覆すに至らない。"),
            "conditional"
        );
        // A bare 判定 in prose ("準拠判定を保留") precedes the real 判定: label.
        assert_eq!(
            classify_verdict("監査法人が準拠判定を保留する実例は存在する。判定: 条件付き結論維持。条件—..."),
            "conditional"
        );
    }

    #[test]
    fn missing_label_is_unclassified() {
        assert_eq!(classify_verdict("Bが妥当だと考える。"), "unclassified");
    }
}

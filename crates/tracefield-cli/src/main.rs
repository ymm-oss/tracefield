use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use serde_json::{Value, json};
use std::io::{self, BufRead, Write};
use std::{
    env, fs,
    path::{Path, PathBuf},
};
use tracefield_core::{
    Entry, EntryStatus, EntryType, FlowRunOptions, FlowRunResult, NewEntry, ReferenceStore,
    WebInputOptions, ingest_web_inputs, run_flow,
};

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
    /// Materialize a persisted JSONL store as a HigherGraphen-backed structural view.
    StructuralView {
        #[arg(long, value_name = "JSONL")]
        store: PathBuf,
        #[arg(long)]
        active_only: bool,
        #[arg(long, value_name = "ID")]
        space_id: Option<String>,
        #[arg(long)]
        json: bool,
        #[arg(long, value_name = "FILE")]
        out: Option<PathBuf>,
    },
    /// Run deterministic structural checks over a persisted JSONL store.
    StructuralChecks {
        #[arg(long, value_name = "JSONL")]
        store: PathBuf,
        #[arg(long)]
        include_terminal: bool,
        #[arg(long = "check", value_name = "CHECK")]
        checks: Vec<String>,
        #[arg(long, value_name = "ID")]
        space_id: Option<String>,
        #[arg(long)]
        json: bool,
        #[arg(long, value_name = "FILE")]
        out: Option<PathBuf>,
    },
    /// Interactive REPL chat over a persisted Field Runner store.
    Chat {
        #[arg(long, alias = "scenario", value_name = "DIR")]
        scenario_dir: PathBuf,
        #[arg(long, value_name = "FILE")]
        config: Option<PathBuf>,
        #[arg(long, value_name = "JSONL")]
        persist: Option<PathBuf>,
        #[arg(long)]
        verbose: bool,
    },
    /// Check local runtime dependencies.
    Doctor,
    /// Scaffold (first call) then run the meeting-support flow on a directory.
    Meeting {
        dir: PathBuf,
        #[arg(long)]
        force: bool,
    },
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
                cycle_seed: None,
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
        Command::Supersede { store, entry, with } => {
            ensure_file(&store, "--store")?;

            let mut reference = tracefield_core::ReferenceStore::from_jsonl_path(&store)
                .with_context(|| format!("failed to load persisted store {}", store.display()))?;
            let affected = reference
                .supersede(&entry, &with)
                .with_context(|| format!("failed to supersede entry {entry} with {with}"))?;
            reference.write_jsonl(&store).with_context(|| {
                format!("failed to persist supersession to {}", store.display())
            })?;

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
        Command::StructuralView {
            store,
            active_only,
            space_id,
            json,
            out,
        } => {
            ensure_file(&store, "--store")?;

            let reference = tracefield_core::ReferenceStore::from_jsonl_path(&store)
                .with_context(|| format!("failed to load persisted store {}", store.display()))?;
            let view = tracefield_core::materialize_structural_view(
                &reference,
                tracefield_core::StructuralViewOptions {
                    space_id,
                    active_only,
                },
            );

            if let Some(out) = &out {
                let encoded = serde_json::to_string_pretty(&view)
                    .context("failed to encode structural view")?;
                write_text(out, &encoded).with_context(|| {
                    format!("failed to write structural view to {}", out.display())
                })?;
            }
            if json {
                println!("{}", serde_json::to_string(&view)?);
            } else {
                print_structural_view_report(&view);
                if let Some(path) = out {
                    println!();
                    println!("wrote structural view: {}", path.display());
                }
            }
        }
        Command::StructuralChecks {
            store,
            include_terminal,
            checks,
            space_id,
            json,
            out,
        } => {
            ensure_file(&store, "--store")?;

            let reference = tracefield_core::ReferenceStore::from_jsonl_path(&store)
                .with_context(|| format!("failed to load persisted store {}", store.display()))?;
            let report = tracefield_core::run_structural_checks(
                &reference,
                tracefield_core::StructuralCheckOptions {
                    space_id,
                    active_only: !include_terminal,
                    checks,
                },
            );

            if let Some(out) = &out {
                let encoded = serde_json::to_string_pretty(&report)
                    .context("failed to encode structural check report")?;
                write_text(out, &encoded).with_context(|| {
                    format!(
                        "failed to write structural check report to {}",
                        out.display()
                    )
                })?;
            }
            if json {
                println!("{}", serde_json::to_string(&report)?);
            } else {
                print_structural_check_report(&report);
                if let Some(path) = out {
                    println!();
                    println!("wrote structural check report: {}", path.display());
                }
            }
        }
        Command::Chat {
            scenario_dir,
            config,
            persist,
            verbose,
        } => {
            ensure_directory(&scenario_dir, "--scenario-dir")?;
            if let Some(config) = &config {
                ensure_file(config, "--config")?;
            }
            run_chat_repl(scenario_dir, config, persist, verbose).await?;
        }
        Command::Doctor => {
            print_doctor().await;
        }
        Command::Meeting { dir, force } => {
            if !dir.join("flow.toml").exists() {
                let name = dir
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("meeting");
                tracefield_core::scenario::scaffold_with_profile(
                    name,
                    Some(&dir),
                    force,
                    "meeting-support",
                )
                .with_context(|| {
                    format!("failed to scaffold meeting scenario {}", dir.display())
                })?;
                println!("scaffolded meeting-support scenario at {}", dir.display());
                println!(
                    "→ edit inputs/minutes.md (+ private/agenda.md), confirm the adapter (tracefield doctor), then re-run: tracefield meeting {}",
                    dir.display()
                );
            } else {
                let result = run_flow(FlowRunOptions {
                    scenario_dir: dir.clone(),
                    config_path: None,
                    budget: None,
                    persist_path: Some(dir.join("store.jsonl")),
                    cycle_seed: None,
                })
                .await
                .with_context(|| format!("failed to run meeting flow {}", dir.display()))?;
                print_run_report(&result).context("failed to render run report")?;
                println!();
                println!("outputs: {}", dir.join("outputs").display());
            }
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

/// Deterministically fold per-refutation adjudication verdicts into a standing
/// conclusion: any overturn changes the conclusion; an unclassified verdict blocks
/// a clean fold; otherwise the conclusion is maintained under the union of the
/// conditional verdicts. No LLM, no silent drops.
fn aggregate_verdicts(reference: &tracefield_core::ReferenceStore, stage: &str) -> AggregateReport {
    aggregate_verdicts_in(reference.all(), stage)
}

/// Same deterministic fold as [`aggregate_verdicts`] but over an arbitrary entry
/// slice, so a chat turn can aggregate just its freshly generated entries
/// (`FlowRunResult::entries`) without reloading the whole store.
fn aggregate_verdicts_in(entries: &[Entry], stage: &str) -> AggregateReport {
    let mut records = Vec::new();
    for entry in entries {
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
            class: tracefield_core::classify_verdict(&entry.text).to_string(),
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

fn print_structural_view_report(view: &tracefield_core::StructuralView) {
    println!("# tracefield structural-view");
    println!();
    println!("schema: {}", view.schema);
    println!("space: {}", view.space.id);
    println!(
        "entries: canonical={} included={} active={} terminal={}",
        view.space.canonical_entry_count,
        view.space.included_entry_count,
        view.space.active_entry_count,
        view.space.terminal_entry_count
    );
    println!(
        "structure: cells={} incidences={} morphisms={} obstructions={} completion_candidates={} invariants={} impact_cones={}",
        view.cells.len(),
        view.incidences.len(),
        view.morphisms.len(),
        view.obstructions.len(),
        view.completion_candidates.len(),
        view.invariants.len(),
        view.impact_cones.len()
    );

    if !view.obstructions.is_empty() {
        println!();
        println!("## obstructions");
        for obstruction in &view.obstructions {
            let severity = obstruction
                .severity
                .as_deref()
                .map(|value| format!(" severity={value}"))
                .unwrap_or_default();
            println!(
                "- {} type={}{} review_status={} locations={}",
                obstruction.id,
                obstruction.obstruction_type,
                severity,
                obstruction.provenance.review_status,
                obstruction.location_cell_ids.join(",")
            );
        }
    }

    if let Some(projection) = view.projections.first() {
        println!();
        println!("## projection loss");
        for loss in &projection.information_loss {
            println!("- {loss}");
        }
    }
}

fn print_structural_check_report(report: &tracefield_core::StructuralCheckReport) {
    println!("# tracefield structural-checks");
    println!();
    println!("schema: {}", report.schema);
    println!("space: {}", report.space_id);
    println!(
        "findings: total={} blocking={} obstructions={} dangling_incidence={} invariants={} completion_candidates={} projection_loss={} hg_acyclicity={} hg_graph_analytics={}",
        report.summary.finding_count,
        report.summary.blocking_count,
        report.summary.obstruction_count,
        report.summary.dangling_incidence_count,
        report.summary.unreviewed_invariant_count,
        report.summary.unreviewed_completion_candidate_count,
        report.summary.projection_loss_count,
        report.summary.highergraphen_acyclicity_count,
        report.summary.highergraphen_graph_analytics_count
    );

    if !report.findings.is_empty() {
        println!();
        println!("## findings");
        for finding in &report.findings {
            println!(
                "- {} check={} severity={} status={} review_status={}: {}",
                finding.id,
                finding.check,
                finding.severity,
                finding.status,
                finding.review_status,
                first_line(&finding.text)
            );
        }
    }
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
    if let Some(tool) = cli_tools.first() {
        println!("  → flow.toml: [organs.<id>] adapter = \"cli\" command = \"{tool}\"");
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

fn first_line(text: &str) -> &str {
    text.lines().next().unwrap_or("").trim()
}

fn find_on_path(binary: &str) -> bool {
    let Some(paths) = env::var_os("PATH") else {
        return false;
    };

    env::split_paths(&paths).any(|path| path.join(binary).is_file())
}

const CHAT_HELP: &str = "\
コマンド:
  <発話>                   ふつうに入力すると 1 ターン回る
  /history                 これまでの会話（Active な問い/答え）を表示
  /retract <id>            指定エントリを撤回（引用閉包ごと無効化）
  /supersede <id> <text>   指定の問いを新しい問いに差し替えて答え直す
  /aggregate [stage]       審議判定を機械集約して結論を表示
  /new                     話題の区切り（過去は撤回しない）
  /help                    このヘルプ
  /quit, /exit             終了";

enum ChatControl {
    Continue,
    Quit,
}

/// Interactive REPL: each plain line becomes a turn-stamped question pushed to
/// the persisted store, then one `run_flow` pass answers it. Slash commands map
/// to the existing store operations (retract / supersede / aggregate), so the
/// store's status-driven read path makes "撤回" take effect on the next turn.
async fn run_chat_repl(
    scenario_dir: PathBuf,
    config: Option<PathBuf>,
    persist: Option<PathBuf>,
    verbose: bool,
) -> Result<()> {
    let store_path = persist.unwrap_or_else(|| scenario_dir.join("chat.jsonl"));

    println!("# tracefield chat");
    println!("scenario: {}", scenario_dir.display());
    println!("store:    {}", store_path.display());
    println!("/help でコマンド一覧、/quit で終了。空行は無視されます。");
    println!();

    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    loop {
        print!("> ");
        io::stdout().flush().ok();

        let Some(line) = lines.next() else {
            break; // EOF (Ctrl-D)
        };
        let line = line.context("failed to read stdin")?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if let Some(command) = trimmed.strip_prefix('/') {
            match dispatch_slash(
                command,
                &scenario_dir,
                config.as_deref(),
                &store_path,
                verbose,
            )
            .await
            {
                Ok(ChatControl::Quit) => break,
                Ok(ChatControl::Continue) => {}
                Err(error) => eprintln!("error: {error:#}"),
            }
            continue;
        }

        if let Err(error) = chat_turn(
            trimmed,
            &scenario_dir,
            config.as_deref(),
            &store_path,
            verbose,
        )
        .await
        {
            eprintln!("error: {error:#}");
        }
    }

    println!();
    println!("bye");
    Ok(())
}

/// Push the user's utterance as a turn-stamped question, then run one flow pass.
async fn chat_turn(
    utterance: &str,
    scenario_dir: &Path,
    config: Option<&Path>,
    store_path: &Path,
    verbose: bool,
) -> Result<()> {
    let mut store = ReferenceStore::from_jsonl_path(store_path)
        .with_context(|| format!("failed to load chat store {}", store_path.display()))?;
    let turn = next_turn(&store);
    store.push(
        NewEntry::new(EntryType::Question, "user", utterance)
            .with_meta("turn", json!(turn))
            .with_meta("kind", json!("chat_user")),
        "user",
    );
    store.write_jsonl(store_path).with_context(|| {
        format!(
            "failed to persist chat question to {}",
            store_path.display()
        )
    })?;

    run_pass_and_render(scenario_dir, config, store_path, verbose, turn).await
}

/// Run one `run_flow` pass over the persisted store and render this turn's
/// freshly generated entries. The task is seeded idempotently, so re-running
/// over the same store only appends the new turn's work.
async fn run_pass_and_render(
    scenario_dir: &Path,
    config: Option<&Path>,
    store_path: &Path,
    verbose: bool,
    turn: u64,
) -> Result<()> {
    let result = run_flow(FlowRunOptions {
        scenario_dir: scenario_dir.to_path_buf(),
        config_path: config.map(Path::to_path_buf),
        budget: None,
        persist_path: Some(store_path.to_path_buf()),
        cycle_seed: Some(turn as usize),
    })
    .await
    .with_context(|| format!("chat turn {turn} flow failed"))?;

    render_chat_turn(&result, verbose);
    Ok(())
}

/// The next chat turn number: one past the maximum `meta.turn` in the store
/// (1 if none), so turns stay contiguous across REPL restarts.
fn next_turn(store: &ReferenceStore) -> u64 {
    store
        .all()
        .iter()
        .filter_map(|entry| entry.meta.get("turn").and_then(Value::as_u64))
        .max()
        .map_or(1, |max| max + 1)
}

/// The turn a chat entry belongs to: user questions carry `meta.turn`; flow
/// outputs (answers) carry `meta.work_item_cycle`, which chat sets to the turn.
fn entry_turn(entry: &Entry) -> u64 {
    entry
        .meta
        .get("turn")
        .or_else(|| entry.meta.get("work_item_cycle"))
        .and_then(Value::as_u64)
        .unwrap_or(0)
}

/// Render one chat turn from the flow result's freshly generated entries. Never
/// summarizes (no central synthesizer) — it only selects which entries to show.
fn render_chat_turn(result: &FlowRunResult, verbose: bool) {
    if verbose {
        let _ = print_run_report(result);
        return;
    }

    // Separate codex read-only tool/command provenance from the spoken answer.
    let (provenance, body): (Vec<&Entry>, Vec<&Entry>) = result.entries.iter().partition(|entry| {
        entry
            .meta
            .get("kind")
            .and_then(Value::as_str)
            .is_some_and(|kind| kind.starts_with("codex_"))
    });

    let last_stage = result.stages.last().map(|stage| stage.id.as_str());

    // Governed flows end on adjudication Decisions carrying a 判定 label: fold
    // them mechanically into a conclusion (the same rule-based aggregate).
    let has_verdict = body.iter().any(|entry| {
        entry.entry_type == EntryType::Decision
            && tracefield_core::classify_verdict(&entry.text) != "unclassified"
    });
    if let Some(stage) = last_stage.filter(|_| has_verdict) {
        // Select and label entries for display — no synthesis (no central
        // synthesizer): each lens's position, then each verdict's text by class,
        // then the mechanical conclusion.
        let stances: Vec<&Entry> = body
            .iter()
            .copied()
            .filter(|entry| entry.entry_type == EntryType::Stance)
            .collect();
        if !stances.is_empty() {
            println!("■ 立場");
            for entry in &stances {
                println!("  [{}] {}", entry.author, first_line(&entry.text));
            }
            println!();
        }
        let report = aggregate_verdicts_in(&result.entries, stage);
        let conclusion_ja = match report.conclusion.as_str() {
            "changed" => "結論変更を要する",
            "maintained" => "結論維持",
            "indeterminate" => "未確定（要対応）",
            other => other,
        };
        println!(
            "■ 判定 — {} (覆る{} 条件付き{} 却下{} 維持{}{})",
            conclusion_ja,
            report.overturn.len(),
            report.conditional.len(),
            report.reject.len(),
            report.maintain.len(),
            if report.unclassified.is_empty() {
                String::new()
            } else {
                format!(" 未分類{}", report.unclassified.len())
            }
        );
        for record in &report.records {
            println!("  [{}] {}", record.class, first_line(&record.text));
        }
        render_tool_trace(&provenance);
        return;
    }

    // Otherwise speak the final stage's answer / synthesis / decision text.
    let answer: Vec<&Entry> = last_stage
        .map(|stage| {
            body.iter()
                .copied()
                .filter(|entry| entry.meta.get("stage").and_then(Value::as_str) == Some(stage))
                .filter(|entry| {
                    matches!(
                        entry.entry_type,
                        EntryType::Answer | EntryType::Synthesis | EntryType::Decision
                    )
                })
                .collect()
        })
        .unwrap_or_default();

    let shown = if answer.is_empty() { &body } else { &answer };
    if shown.is_empty() {
        // No silent drop: if nothing matched, show whatever was generated.
        for entry in &result.entries {
            print_entry_line(&serde_json::to_value(entry).unwrap_or(Value::Null));
        }
    } else {
        for entry in shown {
            println!("{}", entry.text.trim());
        }
    }
    render_tool_trace(&provenance);
}

fn render_tool_trace(provenance: &[&Entry]) {
    if provenance.is_empty() {
        return;
    }
    println!();
    for entry in provenance {
        println!("  [tool] {}", first_line(&entry.text));
    }
}

/// Handle a `/command`. Returns whether the REPL should continue or quit.
async fn dispatch_slash(
    command: &str,
    scenario_dir: &Path,
    config: Option<&Path>,
    store_path: &Path,
    verbose: bool,
) -> Result<ChatControl> {
    let mut parts = command.splitn(2, char::is_whitespace);
    let verb = parts.next().unwrap_or("").trim();
    let rest = parts.next().unwrap_or("").trim();

    match verb {
        "quit" | "exit" => return Ok(ChatControl::Quit),
        "help" => println!("{}", CHAT_HELP),
        "history" => chat_history(store_path)?,
        "retract" => {
            if rest.is_empty() {
                println!("usage: /retract <id>");
            } else {
                chat_retract(store_path, rest)?;
            }
        }
        "supersede" => {
            let mut sup = rest.splitn(2, char::is_whitespace);
            let id = sup.next().unwrap_or("").trim();
            let text = sup.next().unwrap_or("").trim();
            if id.is_empty() || text.is_empty() {
                println!("usage: /supersede <id> <new question>");
            } else {
                let turn = chat_supersede(store_path, id, text)?;
                run_pass_and_render(scenario_dir, config, store_path, verbose, turn).await?;
            }
        }
        "aggregate" => {
            let stage = if rest.is_empty() {
                "adjudication"
            } else {
                rest
            };
            let reference = ReferenceStore::from_jsonl_path(store_path)
                .with_context(|| format!("failed to load store {}", store_path.display()))?;
            print_aggregate_report(&aggregate_verdicts(&reference, stage));
        }
        "new" => {
            println!("(話題を区切りました。過去の発言は撤回していません。新しい問いをどうぞ)");
        }
        other => {
            println!("unknown command: /{other} — /help を参照");
        }
    }

    Ok(ChatControl::Continue)
}

/// List the Active questions / answers in turn order.
fn chat_history(store_path: &Path) -> Result<()> {
    let store = ReferenceStore::from_jsonl_path(store_path)
        .with_context(|| format!("failed to load store {}", store_path.display()))?;
    let mut rows: Vec<&Entry> = store
        .all()
        .iter()
        .filter(|entry| entry.status == EntryStatus::Active)
        .filter(|entry| matches!(entry.entry_type, EntryType::Question | EntryType::Answer))
        .collect();
    rows.sort_by_key(|entry| entry_turn(entry));

    if rows.is_empty() {
        println!("(まだ会話がありません)");
        return Ok(());
    }
    for entry in rows {
        let turn = entry_turn(entry);
        let who: &str = if entry.entry_type == EntryType::Question {
            "you"
        } else {
            entry.author.as_str()
        };
        println!("[{}] t{turn} {who}: {}", entry.id, first_line(&entry.text));
    }
    Ok(())
}

/// Retract an entry (and its citation closure) — the conversational "撤回".
fn chat_retract(store_path: &Path, id: &str) -> Result<()> {
    let mut store = ReferenceStore::from_jsonl_path(store_path)
        .with_context(|| format!("failed to load store {}", store_path.display()))?;
    let affected = store
        .retract(id, "user")
        .with_context(|| format!("failed to retract {id}"))?;
    store
        .write_jsonl(store_path)
        .with_context(|| format!("failed to persist retraction to {}", store_path.display()))?;
    print_closure_report(&format!("retracted {id}"), &affected)?;
    Ok(())
}

/// Supersede a prior question with a reworded one — the conversational "言い直し".
/// Returns the new turn number so the caller can answer it immediately.
fn chat_supersede(store_path: &Path, old_id: &str, text: &str) -> Result<u64> {
    let mut store = ReferenceStore::from_jsonl_path(store_path)
        .with_context(|| format!("failed to load store {}", store_path.display()))?;
    let turn = next_turn(&store);
    let replacement = store.push(
        NewEntry::new(EntryType::Question, "user", text)
            .with_meta("turn", json!(turn))
            .with_meta("kind", json!("chat_user")),
        "user",
    );
    let new_id = replacement.id.clone();
    let affected = store
        .supersede(old_id, &new_id)
        .with_context(|| format!("failed to supersede {old_id} with {new_id}"))?;
    store
        .write_jsonl(store_path)
        .with_context(|| format!("failed to persist supersession to {}", store_path.display()))?;
    print_closure_report(&format!("superseded {old_id} by {new_id}"), &affected)?;
    Ok(turn)
}

#[cfg(test)]
mod tests {
    use tracefield_core::classify_verdict;

    #[test]
    fn classifies_canonical_labels() {
        assert_eq!(
            classify_verdict("判定: 結論変更を要する(覆る)。根拠..."),
            "overturn"
        );
        assert_eq!(
            classify_verdict("判定: 条件付きで結論維持(B)。条件: ..."),
            "conditional"
        );
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
            classify_verdict(
                "監査法人が準拠判定を保留する実例は存在する。判定: 条件付き結論維持。条件—..."
            ),
            "conditional"
        );
    }

    #[test]
    fn missing_label_is_unclassified() {
        assert_eq!(classify_verdict("Bが妥当だと考える。"), "unclassified");
    }
}

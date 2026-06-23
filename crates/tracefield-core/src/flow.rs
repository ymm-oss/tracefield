use crate::entry::{Entry, EntryStatus, EntryType, NewEntry};
use crate::llm::{self, Adapter, LlmOptions, Message};
use crate::scenario::{AgentSpec, Scenario};
use crate::skill_tools::{self, SkillRef};
use crate::store::ReferenceStore;
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::task::JoinSet;

#[derive(Debug, Clone)]
pub struct FlowRunOptions {
    pub scenario_dir: PathBuf,
    pub config_path: Option<PathBuf>,
    pub budget: Option<usize>,
    pub persist_path: Option<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowRunResult {
    pub task: String,
    pub profile: String,
    pub policy: String,
    pub stages: Vec<StageRunResult>,
    pub entries: Vec<Entry>,
    pub layer0_index: Vec<Entry>,
    pub artifacts: Vec<ArtifactExportResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StageRunResult {
    pub id: String,
    pub organ: Option<String>,
    pub actor_count: usize,
    pub entries: Vec<Entry>,
    pub artifacts: Vec<ArtifactExportResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArtifactExportResult {
    pub id: String,
    pub format: String,
    pub path: String,
    pub manifest_path: String,
    pub source_entry_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowConfig {
    pub profile: String,
    pub policy: String,
    pub budget: Option<usize>,
    pub max_feedback_cycles: Option<usize>,
    pub process: ProcessConfig,
    pub long_run: LongRunConfig,
    pub actor_scaling: GlobalActorScaling,
    pub feedback: FeedbackConfig,
    pub feedback_entries: FeedbackEntriesConfig,
    pub organs: BTreeMap<String, OrganConfig>,
    pub stages: Vec<StageConfig>,
    pub artifacts: BTreeMap<String, ArtifactConfig>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct GlobalActorScaling {
    pub default_mode: String,
    pub max_total_actors: Option<usize>,
    pub max_parallel_actors: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct LongRunConfig {
    pub enabled: bool,
    pub cycles: usize,
    pub cycle_stages: Vec<String>,
    pub max_work_items: Option<usize>,
    pub max_feedback_cycles: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ProcessConfig {
    pub enabled: bool,
    pub organ: Option<String>,
    pub mode: String,
    pub agent_count: usize,
    pub artifact_after_feedback: bool,
    pub artifact_stages: Vec<String>,
    pub gates: ProcessGatesConfig,
    pub stop: ProcessStopConfig,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ProcessGatesConfig {
    pub enforce_artifact_gate: bool,
    pub allow_conditional_artifacts: bool,
    pub require_citations: bool,
    pub require_evidence_quotes: bool,
    pub block_publish_on_open_questions: bool,
    pub block_publish_on_quality_warnings: bool,
    pub require_manifest: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ProcessStopConfig {
    pub max_cycles: Option<usize>,
    pub max_feedback_cycles: Option<usize>,
    pub stop_when: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FeedbackConfig {
    pub enabled: bool,
    pub max_requests_per_cycle: usize,
    pub dedupe_by: Vec<String>,
    pub edges: Vec<FeedbackEdge>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FeedbackEdge {
    pub from: Vec<String>,
    pub to: String,
    pub entry_types: Vec<EntryType>,
    pub trigger_when: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FeedbackEntriesConfig {
    pub enabled: bool,
    pub kind: String,
    pub accepted_types: Vec<EntryType>,
    pub status_field: String,
    pub max_requests_per_cycle: usize,
    pub dedupe_by: Vec<String>,
    pub routes: Vec<FeedbackEntryRoute>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FeedbackEntryRoute {
    pub from: Vec<String>,
    pub target_prefix: Option<String>,
    pub to: String,
    pub entry_types: Vec<EntryType>,
    pub actions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrganConfig {
    pub id: String,
    pub adapter: String,
    pub model: Option<String>,
    pub command: Option<String>,
    pub max_tokens: Option<usize>,
    pub timeout_seconds: Option<u64>,
    pub web_search: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StageConfig {
    pub id: String,
    pub organ: Option<String>,
    pub budget: Option<usize>,
    pub inputs: Vec<String>,
    pub outputs: Vec<EntryType>,
    pub context: Option<StageContextConfig>,
    pub actors: ActorConfig,
    pub clustering: Option<StageClusteringConfig>,
    pub command: Option<StageCommandConfig>,
    pub artifact: Option<StageArtifactConfig>,
    /// When set, after this stage runs its adjudication verdicts are folded
    /// mechanically: any claim a `overturn` verdict's refutation names in
    /// `meta.refutes` is retracted (status-driven), so a later assembler sees
    /// only survivors. Keeps the verdict fold out of the LLM (invariant #1).
    pub retract_overturned: bool,
    /// Opt in to source-grounding discipline (evidence-quote contract + machine verification)
    /// regardless of stage/organ/role naming. See is_source_grounded_stage.
    pub grounded: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StageContextConfig {
    pub mode: String,
    pub chars_per_entry: Option<usize>,
    pub chars_total: Option<usize>,
    pub keywords: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActorConfig {
    pub mode: String,
    pub count: Option<usize>,
    pub min: Option<usize>,
    pub max: Option<usize>,
    pub scale_by: Vec<String>,
    pub roles: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StageClusteringConfig {
    pub enabled: bool,
    pub by: Vec<String>,
    pub min_cluster_size: Option<usize>,
    pub max_clusters: Option<usize>,
}

/// A deterministic stage that runs an external command instead of LLM actors
/// (a probe/sensor, not a lens). Selected entries are materialized to a temp
/// file whose path replaces `{input}` in `args`; stdout/exit become one entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StageCommandConfig {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: Option<String>,
    pub timeout_seconds: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StageArtifactConfig {
    pub kind: Option<String>,
    pub format: Option<String>,
    pub audience: Option<String>,
    pub require_citations: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtifactConfig {
    pub id: String,
    pub format: String,
    pub from_stage: String,
    pub path: String,
}

#[derive(Debug, Clone)]
struct SeededFlow {
    entries: Vec<Entry>,
    skill_entry_ids: BTreeMap<String, String>,
}

#[derive(Debug, Clone)]
struct ActorScalingDecision {
    mode: String,
    chosen_count: usize,
    signals: BTreeMap<String, usize>,
}

#[derive(Debug)]
struct ActorRunOutput {
    actor_index: usize,
    actor_id: String,
    entries: Vec<NewEntry>,
}

#[derive(Debug, Clone, Default)]
struct FlowWorkItem {
    stage_index: usize,
    feedback_request_ids: Vec<String>,
    cycle: usize,
    reason: String,
}

#[derive(Debug, Clone, Copy)]
enum ProcessStageKind {
    Plan,
    ArtifactGate,
    Verdict,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ProcessArtifactGateDecision {
    allow_artifacts: bool,
    reason: String,
    blocking_entry_ids: Vec<String>,
}

const MAX_CONTEXT_CHARS_PER_ENTRY: usize = 300;
const MAX_CONTEXT_CHARS_TOTAL: usize = 2_400;

pub async fn run_flow(options: FlowRunOptions) -> Result<FlowRunResult> {
    let scenario = Scenario::load(&options.scenario_dir)?;
    let config_path = options
        .config_path
        .clone()
        .unwrap_or_else(|| options.scenario_dir.join("flow.toml"));
    let mut config = FlowConfig::load(&config_path)?;
    if let Some(budget) = options.budget {
        config.budget = Some(budget);
    }

    let mut store = if let Some(path) = &options.persist_path {
        ReferenceStore::from_jsonl_path(path)?
    } else {
        ReferenceStore::new()
    };
    let seeded = seed_flow_layer0(&mut store, &scenario)?;
    checkpoint_flow_store(&store, options.persist_path.as_deref())?;
    let mut stages = Vec::new();
    let mut all_generated = Vec::new();
    let mut all_artifacts = Vec::new();
    let mut work_queue = initial_work_queue(&config);
    let mut budget_step = 0;
    let mut feedback_cycles = 0;
    let mut executed_work_items = 0;
    let mut process_artifact_gate_ran = false;

    if config.process.enabled {
        budget_step += 1;
        let process_result = execute_process_stage(
            &scenario,
            &config,
            &mut store,
            &seeded,
            ProcessStageKind::Plan,
            configured_long_run_cycles(&config),
            budget_step,
            options.persist_path.as_deref(),
        )
        .await?;
        all_generated.extend(process_result.entries.clone());
        stages.push(process_result);
    }

    while let Some(work_item) = work_queue.first().cloned() {
        if config
            .long_run
            .max_work_items
            .is_some_and(|limit| executed_work_items >= limit)
        {
            break;
        }
        work_queue.remove(0);

        if config.process.enabled
            && !process_artifact_gate_ran
            && is_process_artifact_stage(&config, work_item.stage_index)
        {
            budget_step += 1;
            let mut process_result = execute_process_stage(
                &scenario,
                &config,
                &mut store,
                &seeded,
                ProcessStageKind::ArtifactGate,
                work_item.cycle,
                budget_step,
                options.persist_path.as_deref(),
            )
            .await?;
            let gate_decision = process_artifact_gate_decision(&config, &process_result.entries);
            if !gate_decision.allow_artifacts {
                let mut blocked_stage_ids = vec![config.stages[work_item.stage_index].id.clone()];
                blocked_stage_ids
                    .extend(remove_process_artifact_work_items(&config, &mut work_queue));
                let enforcement_marker = record_artifact_gate_enforcement(
                    &config,
                    &mut store,
                    &process_result,
                    &gate_decision,
                    &blocked_stage_ids,
                    work_item.cycle,
                    budget_step,
                    options.persist_path.as_deref(),
                )?;
                process_result.entries.push(enforcement_marker);
                log_flow_progress(
                    &config,
                    format!(
                        "stage=process_artifact_gate cycle={} enforced_block skipped={} reason={}",
                        work_item.cycle,
                        blocked_stage_ids.len(),
                        gate_decision.reason
                    ),
                );
            }
            all_generated.extend(process_result.entries.clone());
            stages.push(process_result);
            process_artifact_gate_ran = true;
            if !gate_decision.allow_artifacts {
                continue;
            }
        }

        budget_step += 1;
        executed_work_items += 1;
        let stage_id = config.stages[work_item.stage_index].id.clone();
        log_flow_progress(
            &config,
            format!(
                "stage={} cycle={} reason={} start work_item={}/{} queued_after_pop={}",
                stage_id,
                work_item.cycle,
                work_item.reason,
                executed_work_items,
                config
                    .long_run
                    .max_work_items
                    .unwrap_or(config.stages.len()),
                work_queue.len()
            ),
        );

        let stage_result = execute_stage(
            &scenario,
            &config,
            &mut store,
            &seeded,
            &work_item,
            budget_step,
            options.persist_path.as_deref(),
        )
        .await?;

        // Mechanical verdict fold (invariant #1): retract claims this stage's
        // adjudication overturned so a later assembler sees only survivors. The
        // retract closure is logged — never silently dropped.
        if config.stages[work_item.stage_index].retract_overturned {
            let reconcile = store.reconcile_overturned(&stage_result.entries);
            for (claim, affected) in &reconcile.retracted {
                log_flow_progress(
                    &config,
                    format!(
                        "stage={} cycle={} reconcile overturned-claim={} retracted closure={}",
                        stage_id,
                        work_item.cycle,
                        claim,
                        affected.len()
                    ),
                );
            }
            if !reconcile.unactioned.is_empty() {
                log_flow_progress(
                    &config,
                    format!(
                        "stage={} cycle={} reconcile UNACTIONED overturns={} verdicts={:?} \
                         (overturn but no meta.refutes target — claim survives; verdict↔artifact gap, human must reconcile)",
                        stage_id,
                        work_item.cycle,
                        reconcile.unactioned.len(),
                        reconcile.unactioned
                    ),
                );
            }
        }

        let feedback_work = feedback_work_items(
            &config,
            work_item.stage_index,
            &stage_result.entries,
            &mut feedback_cycles,
        );
        insert_feedback_work_items(&config, &mut work_queue, feedback_work);

        all_artifacts.extend(stage_result.artifacts.clone());
        all_generated.extend(stage_result.entries.clone());
        log_flow_progress(
            &config,
            format!(
                "stage={} cycle={} done entries={} artifacts={} queued_now={}",
                stage_result.id,
                work_item.cycle,
                stage_result.entries.len(),
                stage_result.artifacts.len(),
                work_queue.len()
            ),
        );
        stages.push(stage_result);

        if let Some(path) = &options.persist_path {
            store.write_jsonl(path)?;
        }
    }

    if config.process.enabled {
        budget_step += 1;
        let process_result = execute_process_stage(
            &scenario,
            &config,
            &mut store,
            &seeded,
            ProcessStageKind::Verdict,
            configured_long_run_cycles(&config),
            budget_step,
            options.persist_path.as_deref(),
        )
        .await?;
        all_generated.extend(process_result.entries.clone());
        stages.push(process_result);
    }

    if let Some(path) = &options.persist_path {
        store.write_jsonl(path)?;
    }

    Ok(FlowRunResult {
        task: scenario.task,
        profile: config.profile,
        policy: config.policy,
        stages,
        entries: all_generated,
        layer0_index: seeded.entries,
        artifacts: all_artifacts,
    })
}

fn initial_work_queue(config: &FlowConfig) -> Vec<FlowWorkItem> {
    let cycles = configured_long_run_cycles(config);
    if !config.long_run.enabled || cycles <= 1 {
        return config
            .stages
            .iter()
            .enumerate()
            .map(|(stage_index, _)| FlowWorkItem::new(stage_index, 1, "initial"))
            .collect();
    }

    let cycle_stage_indices = if config.long_run.cycle_stages.is_empty() {
        config
            .stages
            .iter()
            .enumerate()
            .filter(|(_, stage)| stage.artifact.is_none())
            .map(|(stage_index, _)| stage_index)
            .collect::<Vec<_>>()
    } else {
        config
            .long_run
            .cycle_stages
            .iter()
            .filter_map(|stage_id| config.stages.iter().position(|stage| stage.id == *stage_id))
            .collect::<Vec<_>>()
    };
    let cycle_stage_set = cycle_stage_indices.iter().copied().collect::<BTreeSet<_>>();
    let mut work_queue = Vec::new();

    for cycle in 1..=cycles {
        for stage_index in &cycle_stage_indices {
            work_queue.push(FlowWorkItem::new(*stage_index, cycle, "long_run_cycle"));
        }
    }

    for (stage_index, _) in config.stages.iter().enumerate() {
        if !cycle_stage_set.contains(&stage_index) {
            work_queue.push(FlowWorkItem::new(stage_index, cycles, "final"));
        }
    }

    work_queue
}

impl FlowWorkItem {
    fn new(stage_index: usize, cycle: usize, reason: impl Into<String>) -> Self {
        Self {
            stage_index,
            feedback_request_ids: Vec::new(),
            cycle,
            reason: reason.into(),
        }
    }
}

impl FlowConfig {
    pub fn load(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        let text = fs::read_to_string(path)
            .with_context(|| format!("failed to read flow config {}", path.display()))?;
        Self::parse(&text).with_context(|| format!("failed to parse {}", path.display()))
    }

    pub fn parse(text: &str) -> Result<Self> {
        let document = MiniToml::parse(text)?;
        let flow = document.table("flow").cloned().unwrap_or_default();
        let profile = string_value(&flow, "profile").unwrap_or_else(|| "default".to_string());
        let policy = string_value(&flow, "policy").unwrap_or_else(|| "fixed".to_string());
        let budget = usize_value(&flow, "budget");
        let max_feedback_cycles = usize_value(&flow, "max_feedback_cycles");
        let long_run_table = document.table("long_run").cloned().unwrap_or_default();
        let long_run = LongRunConfig {
            enabled: bool_value(&long_run_table, "enabled").unwrap_or(false),
            cycles: usize_value(&long_run_table, "cycles").unwrap_or(1).max(1),
            cycle_stages: string_array(&long_run_table, "cycle_stages"),
            max_work_items: usize_value(&long_run_table, "max_work_items"),
            max_feedback_cycles: usize_value(&long_run_table, "max_feedback_cycles"),
        };
        let process_table = document.table("process").cloned().unwrap_or_default();
        let process_gates_table = document.table("process.gates").cloned().unwrap_or_default();
        let process_stop_table = document.table("process.stop").cloned().unwrap_or_default();
        let process = ProcessConfig {
            enabled: bool_value(&process_table, "enabled").unwrap_or(false),
            organ: string_value(&process_table, "organ"),
            mode: string_value(&process_table, "mode")
                .unwrap_or_else(|| "managed_flow".to_string()),
            agent_count: usize_value(&process_table, "agent_count").unwrap_or(1),
            artifact_after_feedback: bool_value(&process_table, "artifact_after_feedback")
                .unwrap_or(false),
            artifact_stages: string_array(&process_table, "artifact_stages"),
            gates: ProcessGatesConfig {
                enforce_artifact_gate: bool_value(&process_gates_table, "enforce_artifact_gate")
                    .unwrap_or(false),
                allow_conditional_artifacts: bool_value(
                    &process_gates_table,
                    "allow_conditional_artifacts",
                )
                .unwrap_or(false),
                require_citations: bool_value(&process_gates_table, "require_citations")
                    .unwrap_or(false),
                require_evidence_quotes: bool_value(
                    &process_gates_table,
                    "require_evidence_quotes",
                )
                .unwrap_or(false),
                block_publish_on_open_questions: bool_value(
                    &process_gates_table,
                    "block_publish_on_open_questions",
                )
                .unwrap_or(false),
                block_publish_on_quality_warnings: bool_value(
                    &process_gates_table,
                    "block_publish_on_quality_warnings",
                )
                .unwrap_or(false),
                require_manifest: bool_value(&process_gates_table, "require_manifest")
                    .unwrap_or(false),
            },
            stop: ProcessStopConfig {
                max_cycles: usize_value(&process_stop_table, "max_cycles"),
                max_feedback_cycles: usize_value(&process_stop_table, "max_feedback_cycles"),
                stop_when: string_array(&process_stop_table, "stop_when"),
            },
        };

        let actor_table = document.table("actor_scaling").cloned().unwrap_or_default();
        let actor_scaling = GlobalActorScaling {
            default_mode: string_value(&actor_table, "default_mode")
                .unwrap_or_else(|| "fixed".to_string()),
            max_total_actors: usize_value(&actor_table, "max_total_actors"),
            max_parallel_actors: usize_value(&actor_table, "max_parallel_actors"),
        };
        let feedback = parse_feedback_config(&document)?;
        let feedback_entries = parse_feedback_entries_config(&document)?;

        let mut organs = BTreeMap::new();
        for (section, values) in &document.sections {
            let Some(id) = section.strip_prefix("organs.") else {
                continue;
            };
            if id.contains('.') {
                continue;
            }
            let organ = OrganConfig {
                id: id.to_string(),
                adapter: string_value(values, "adapter").unwrap_or_else(|| "mock".to_string()),
                model: string_value(values, "model"),
                command: string_value(values, "command"),
                max_tokens: usize_value(values, "max_tokens"),
                timeout_seconds: usize_value(values, "timeout_seconds").map(|value| value as u64),
                web_search: bool_value(values, "web_search").unwrap_or(false),
            };
            organs.insert(organ.id.clone(), organ);
        }

        let mut stage_ids = Vec::new();
        let mut seen_stages = BTreeSet::new();
        for section in &document.order {
            let Some(rest) = section.strip_prefix("stages.") else {
                continue;
            };
            let id = rest.split('.').next().unwrap_or(rest);
            if seen_stages.insert(id.to_string()) {
                stage_ids.push(id.to_string());
            }
        }

        let mut stages = Vec::new();
        for id in stage_ids {
            let section = format!("stages.{id}");
            let values = document.table(&section).cloned().unwrap_or_default();
            let actor_values = document
                .table(&format!("stages.{id}.actors"))
                .cloned()
                .unwrap_or_default();
            let actors = parse_actor_config(&actor_values, &actor_scaling.default_mode);
            let context = document
                .table(&format!("stages.{id}.context"))
                .map(parse_stage_context);
            let clustering = document
                .table(&format!("stages.{id}.clustering"))
                .map(parse_stage_clustering);
            let command = document
                .table(&format!("stages.{id}.command"))
                .map(parse_stage_command);
            let artifact = document
                .table(&format!("stages.{id}.artifact"))
                .map(parse_stage_artifact);
            let outputs = string_array(&values, "outputs")
                .into_iter()
                .map(|value| parse_config_entry_type(&value))
                .collect::<Result<Vec<_>>>()?;
            stages.push(StageConfig {
                id,
                organ: string_value(&values, "organ"),
                budget: usize_value(&values, "budget"),
                inputs: string_array(&values, "inputs"),
                outputs,
                context,
                actors,
                clustering,
                command,
                artifact,
                retract_overturned: bool_value(&values, "retract_overturned").unwrap_or(false),
                grounded: bool_value(&values, "grounded").unwrap_or(false),
            });
        }

        if stages.is_empty() {
            bail!("flow config must define at least one [stages.<id>] table");
        }

        let mut artifacts = BTreeMap::new();
        for (section, values) in &document.sections {
            let Some(id) = section.strip_prefix("artifacts.") else {
                continue;
            };
            if id.contains('.') {
                continue;
            }
            let artifact = ArtifactConfig {
                id: id.to_string(),
                format: string_value(values, "format").unwrap_or_else(|| "markdown".to_string()),
                from_stage: string_value(values, "from_stage").unwrap_or_default(),
                path: string_value(values, "path").unwrap_or_else(|| format!("outputs/{id}.md")),
            };
            artifacts.insert(artifact.id.clone(), artifact);
        }

        let config = Self {
            profile,
            policy,
            budget,
            max_feedback_cycles,
            process,
            long_run,
            actor_scaling,
            feedback,
            feedback_entries,
            organs,
            stages,
            artifacts,
        };
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<()> {
        validate_policy(&self.policy)?;

        let stage_ids = self
            .stages
            .iter()
            .map(|stage| stage.id.as_str())
            .collect::<BTreeSet<_>>();
        if let Some(0) = self.long_run.max_work_items {
            bail!("long_run max_work_items must be at least 1");
        }
        if let Some(0) = self.actor_scaling.max_parallel_actors {
            bail!("actor_scaling max_parallel_actors must be at least 1");
        }
        if self.process.enabled {
            if self.process.agent_count == 0 {
                bail!("process agent_count must be at least 1");
            }
            if let Some(organ) = &self.process.organ
                && !self.organs.contains_key(organ)
            {
                bail!("process references unknown organ {}", organ);
            }
            for stage_id in &self.process.artifact_stages {
                if !stage_ids.contains(stage_id.as_str()) {
                    bail!("process artifact_stages references unknown stage {stage_id}");
                }
            }
        }
        if self.long_run.enabled {
            for stage_id in &self.long_run.cycle_stages {
                if !stage_ids.contains(stage_id.as_str()) {
                    bail!("long_run cycle_stages references unknown stage {stage_id}");
                }
            }
        }

        for stage in &self.stages {
            validate_stage_id(&stage.id)?;
            validate_actor_mode(&stage.actors.mode)
                .with_context(|| format!("invalid actor mode in stage {}", stage.id))?;
            if let Some(organ) = &stage.organ
                && !self.organs.contains_key(organ)
            {
                bail!("stage {} references unknown organ {}", stage.id, organ);
            }
            if stage.actors.mode == "fixed" && stage.actors.count == Some(0) {
                bail!("stage {} fixed actor count must be at least 1", stage.id);
            }
            if let (Some(min), Some(max)) = (stage.actors.min, stage.actors.max)
                && min > max
            {
                bail!("stage {} actor min must be <= max", stage.id);
            }
            if let Some(clustering) = &stage.clustering
                && let Some(0) = clustering.max_clusters
            {
                bail!(
                    "stage {} clustering max_clusters must be at least 1",
                    stage.id
                );
            }
            if let Some(command) = &stage.command {
                if command.program.trim().is_empty() {
                    bail!("stage {} command.program must not be empty", stage.id);
                }
                if stage.clustering.is_some() {
                    bail!("stage {} cannot combine command with clustering", stage.id);
                }
                if stage.actors.mode != "none" {
                    bail!(
                        "stage {} with a command must set [actors] mode = \"none\"",
                        stage.id
                    );
                }
            }
            if let Some(context) = &stage.context {
                validate_stage_context_mode(&context.mode)
                    .with_context(|| format!("invalid context mode in stage {}", stage.id))?;
                if context.chars_per_entry == Some(0) {
                    bail!(
                        "stage {} context chars_per_entry must be at least 1",
                        stage.id
                    );
                }
                if context.chars_total == Some(0) {
                    bail!("stage {} context chars_total must be at least 1", stage.id);
                }
            }
        }

        for artifact in self.artifacts.values() {
            if !stage_ids.contains(artifact.from_stage.as_str()) {
                bail!(
                    "artifact {} references unknown from_stage {}",
                    artifact.id,
                    artifact.from_stage
                );
            }
        }

        for edge in &self.feedback.edges {
            for source in &edge.from {
                if !stage_ids.contains(source.as_str()) {
                    bail!("feedback edge references unknown from stage {source}");
                }
            }
            if !stage_ids.contains(edge.to.as_str()) {
                bail!("feedback edge references unknown to stage {}", edge.to);
            }
        }

        for route in &self.feedback_entries.routes {
            for source in &route.from {
                if !stage_ids.contains(source.as_str()) {
                    bail!("feedback entry route references unknown from stage {source}");
                }
            }
            if !stage_ids.contains(route.to.as_str()) {
                bail!(
                    "feedback entry route references unknown to stage {}",
                    route.to
                );
            }
        }

        for organ in self.organs.values() {
            Adapter::parse(&organ.adapter)
                .with_context(|| format!("organ {} has invalid adapter", organ.id))?;
        }

        Ok(())
    }
}

async fn execute_stage(
    scenario: &Scenario,
    config: &FlowConfig,
    store: &mut ReferenceStore,
    seeded: &SeededFlow,
    work_item: &FlowWorkItem,
    budget_step: usize,
    persist_path: Option<&Path>,
) -> Result<StageRunResult> {
    let stage = &config.stages[work_item.stage_index];
    let selected = select_stage_inputs(store, stage, scenario, &work_item.feedback_request_ids);
    let scaling = decide_actor_count(stage, config, &selected, scenario.agents.len());
    let organ = stage
        .organ
        .as_ref()
        .and_then(|organ_id| config.organs.get(organ_id));

    let mut stage_entries = Vec::new();
    if let Some(clustering) = stage
        .clustering
        .as_ref()
        .filter(|clustering| clustering.enabled)
    {
        let existing =
            existing_work_item_entries(store, stage, work_item, None, Some("flow-cluster"));
        if existing.is_empty() {
            let new_entries = deterministic_cluster_entries(
                config,
                stage,
                clustering,
                budget_step,
                &selected,
                &scaling,
            );
            let new_entries = apply_core_gates(new_entries, store, config, stage, &scenario.dir);
            let new_entries = attach_work_item_meta(new_entries, work_item);
            let stored = store.absorb(new_entries, "flow-cluster");
            stage_entries.extend(stored);
            checkpoint_flow_store(store, persist_path)?;
        } else {
            log_flow_progress(
                config,
                format!(
                    "stage={} cycle={} deterministic_cluster resume entries={}",
                    stage.id,
                    work_item.cycle,
                    existing.len()
                ),
            );
            stage_entries.extend(existing);
        }
    }

    if let Some(command) = stage.command.as_ref() {
        let existing =
            existing_work_item_entries(store, stage, work_item, None, Some("flow-command"));
        if existing.is_empty() {
            let new_entries = run_stage_command(
                scenario,
                config,
                stage,
                command,
                budget_step,
                &selected,
                &scaling,
            )
            .await?;
            let new_entries = apply_core_gates(new_entries, store, config, stage, &scenario.dir);
            let new_entries = attach_work_item_meta(new_entries, work_item);
            let stored = store.absorb(new_entries, "flow-command");
            stage_entries.extend(stored);
            checkpoint_flow_store(store, persist_path)?;
        } else {
            log_flow_progress(
                config,
                format!(
                    "stage={} cycle={} command resume entries={}",
                    stage.id,
                    work_item.cycle,
                    existing.len()
                ),
            );
            stage_entries.extend(existing);
        }
    }

    if scaling.chosen_count > 0 {
        let parallelism = actor_parallelism(config, scaling.chosen_count);
        if parallelism > 1 {
            stage_entries.extend(
                execute_stage_actors_parallel(
                    scenario,
                    config,
                    store,
                    seeded,
                    work_item,
                    stage,
                    organ,
                    budget_step,
                    &selected,
                    &scaling,
                    parallelism,
                    persist_path,
                )
                .await?,
            );
        } else {
            for actor_index in 0..scaling.chosen_count {
                let actor_selected =
                    actor_selected_entries(stage, &selected, actor_index, scaling.chosen_count);
                let actor = actor_for_index(scenario, stage, actor_index);
                let actor_id = actor
                    .map(|actor| actor.id.clone())
                    .unwrap_or_else(|| format!("{}-{}", stage.id, actor_index + 1));
                let existing = existing_work_item_entries(
                    store,
                    stage,
                    work_item,
                    Some(actor_index + 1),
                    Some(&actor_id),
                );
                if !existing.is_empty() {
                    log_flow_progress(
                        config,
                        format!(
                            "stage={} cycle={} actor={}/{} id={} resume entries={}",
                            stage.id,
                            work_item.cycle,
                            actor_index + 1,
                            scaling.chosen_count,
                            actor_id,
                            existing.len()
                        ),
                    );
                    stage_entries.extend(existing);
                    continue;
                }
                log_flow_progress(
                    config,
                    format!(
                        "stage={} cycle={} actor={}/{} id={} start inputs={}",
                        stage.id,
                        work_item.cycle,
                        actor_index + 1,
                        scaling.chosen_count,
                        actor_id,
                        actor_selected.len()
                    ),
                );
                let new_entries = run_stage_actor(
                    scenario,
                    config,
                    stage,
                    organ,
                    actor,
                    actor_index + 1,
                    budget_step,
                    &actor_selected,
                    &scaling,
                    seeded,
                    work_item,
                )
                .await?;
                let new_entries =
                    apply_core_gates(new_entries, store, config, stage, &scenario.dir);
                let new_entries = attach_work_item_meta(new_entries, work_item);
                let stored = store.absorb(new_entries, &actor_id);
                log_flow_progress(
                    config,
                    format!(
                        "stage={} cycle={} actor={}/{} stored_entries={}",
                        stage.id,
                        work_item.cycle,
                        actor_index + 1,
                        scaling.chosen_count,
                        stored.len()
                    ),
                );
                stage_entries.extend(stored);
                checkpoint_flow_store(store, persist_path)?;
            }
        }
    } else if stage.artifact.is_some() && stage_entries.is_empty() {
        let existing = existing_work_item_entries(store, stage, work_item, Some(0), Some("flow"));
        if existing.is_empty() {
            let new_entry = deterministic_stage_marker(config, stage, budget_step, &scaling);
            let new_entry = apply_core_gates(vec![new_entry], store, config, stage, &scenario.dir);
            let new_entry = attach_work_item_meta(new_entry, work_item);
            stage_entries.extend(store.absorb(new_entry, "flow"));
            checkpoint_flow_store(store, persist_path)?;
        } else {
            log_flow_progress(
                config,
                format!(
                    "stage={} cycle={} marker resume entries={}",
                    stage.id,
                    work_item.cycle,
                    existing.len()
                ),
            );
            stage_entries.extend(existing);
        }
    }

    let mut artifacts = Vec::new();
    for artifact in config
        .artifacts
        .values()
        .filter(|artifact| artifact.from_stage == stage.id)
    {
        let exported = export_artifact(&scenario.dir, artifact, store)?;
        artifacts.push(exported);
    }

    Ok(StageRunResult {
        id: stage.id.clone(),
        organ: stage.organ.clone(),
        actor_count: scaling.chosen_count,
        entries: stage_entries,
        artifacts,
    })
}

#[allow(clippy::too_many_arguments)]
async fn execute_stage_actors_parallel(
    scenario: &Scenario,
    config: &FlowConfig,
    store: &mut ReferenceStore,
    seeded: &SeededFlow,
    work_item: &FlowWorkItem,
    stage: &StageConfig,
    organ: Option<&OrganConfig>,
    budget_step: usize,
    selected: &[Entry],
    scaling: &ActorScalingDecision,
    parallelism: usize,
    persist_path: Option<&Path>,
) -> Result<Vec<Entry>> {
    let mut stage_entries = Vec::new();
    let mut join_set = JoinSet::new();
    let mut next_actor_index = 0;

    while next_actor_index < scaling.chosen_count || !join_set.is_empty() {
        while next_actor_index < scaling.chosen_count && join_set.len() < parallelism {
            let actor_index = next_actor_index;
            next_actor_index += 1;

            let actor_selected =
                actor_selected_entries(stage, selected, actor_index, scaling.chosen_count);
            let actor = actor_for_index(scenario, stage, actor_index).cloned();
            let actor_id = actor
                .as_ref()
                .map(|actor| actor.id.clone())
                .unwrap_or_else(|| format!("{}-{}", stage.id, actor_index + 1));
            let existing = existing_work_item_entries(
                store,
                stage,
                work_item,
                Some(actor_index + 1),
                Some(&actor_id),
            );
            if !existing.is_empty() {
                log_flow_progress(
                    config,
                    format!(
                        "stage={} cycle={} actor={}/{} id={} resume entries={}",
                        stage.id,
                        work_item.cycle,
                        actor_index + 1,
                        scaling.chosen_count,
                        actor_id,
                        existing.len()
                    ),
                );
                stage_entries.extend(existing);
                continue;
            }

            log_flow_progress(
                config,
                format!(
                    "stage={} cycle={} actor={}/{} id={} start inputs={}",
                    stage.id,
                    work_item.cycle,
                    actor_index + 1,
                    scaling.chosen_count,
                    actor_id,
                    actor_selected.len()
                ),
            );

            let scenario = scenario.clone();
            let config = config.clone();
            let seeded = seeded.clone();
            let work_item = work_item.clone();
            let stage = stage.clone();
            let organ = organ.cloned();
            let scaling = scaling.clone();
            join_set.spawn(async move {
                let entries = run_stage_actor(
                    &scenario,
                    &config,
                    &stage,
                    organ.as_ref(),
                    actor.as_ref(),
                    actor_index + 1,
                    budget_step,
                    &actor_selected,
                    &scaling,
                    &seeded,
                    &work_item,
                )
                .await?;
                Ok::<_, anyhow::Error>(ActorRunOutput {
                    actor_index,
                    actor_id,
                    entries,
                })
            });
        }

        let Some(join_result) = join_set.join_next().await else {
            continue;
        };
        let actor_output = join_result
            .context("actor task failed to join")?
            .context("actor task failed")?;
        let new_entries =
            apply_core_gates(actor_output.entries, store, config, stage, &scenario.dir);
        let new_entries = attach_work_item_meta(new_entries, work_item);
        let stored = store.absorb(new_entries, &actor_output.actor_id);
        log_flow_progress(
            config,
            format!(
                "stage={} cycle={} actor={}/{} stored_entries={}",
                stage.id,
                work_item.cycle,
                actor_output.actor_index + 1,
                scaling.chosen_count,
                stored.len()
            ),
        );
        stage_entries.extend(stored);
        checkpoint_flow_store(store, persist_path)?;
    }

    Ok(stage_entries)
}

#[allow(clippy::too_many_arguments)]
async fn execute_process_stage(
    scenario: &Scenario,
    config: &FlowConfig,
    store: &mut ReferenceStore,
    seeded: &SeededFlow,
    kind: ProcessStageKind,
    cycle: usize,
    budget_step: usize,
    persist_path: Option<&Path>,
) -> Result<StageRunResult> {
    let stage = process_stage_config(config, kind);
    let selected = select_process_inputs(store, scenario, kind);
    let organ = stage
        .organ
        .as_ref()
        .and_then(|organ_id| config.organs.get(organ_id));
    let scaling = ActorScalingDecision {
        mode: "process".to_string(),
        chosen_count: config.process.agent_count,
        signals: process_signals(store, &selected),
    };
    let work_item = FlowWorkItem {
        stage_index: 0,
        feedback_request_ids: Vec::new(),
        cycle,
        reason: kind.reason().to_string(),
    };
    let mut stage_entries = Vec::new();

    for actor_index in 0..config.process.agent_count {
        let actor_id = format!("{}-{}", stage.id, actor_index + 1);
        let existing = existing_work_item_entries(
            store,
            &stage,
            &work_item,
            Some(actor_index + 1),
            Some(&actor_id),
        );
        if !existing.is_empty() {
            log_flow_progress(
                config,
                format!(
                    "stage={} cycle={} process_actor={}/{} resume entries={}",
                    stage.id,
                    cycle,
                    actor_index + 1,
                    config.process.agent_count,
                    existing.len()
                ),
            );
            stage_entries.extend(existing);
            continue;
        }

        log_flow_progress(
            config,
            format!(
                "stage={} cycle={} process_actor={}/{} start inputs={}",
                stage.id,
                cycle,
                actor_index + 1,
                config.process.agent_count,
                selected.len()
            ),
        );
        let new_entries = run_stage_actor(
            scenario,
            config,
            &stage,
            organ,
            None,
            actor_index + 1,
            budget_step,
            &selected,
            &scaling,
            seeded,
            &work_item,
        )
        .await?;
        let new_entries = apply_core_gates(new_entries, store, config, &stage, &scenario.dir);
        let new_entries = attach_work_item_meta(new_entries, &work_item);
        let stored = store.absorb(new_entries, &actor_id);
        log_flow_progress(
            config,
            format!(
                "stage={} cycle={} process_actor={}/{} stored_entries={}",
                stage.id,
                cycle,
                actor_index + 1,
                config.process.agent_count,
                stored.len()
            ),
        );
        stage_entries.extend(stored);
        checkpoint_flow_store(store, persist_path)?;
    }

    Ok(StageRunResult {
        id: stage.id,
        organ: stage.organ,
        actor_count: config.process.agent_count,
        entries: stage_entries,
        artifacts: Vec::new(),
    })
}

fn process_stage_config(config: &FlowConfig, kind: ProcessStageKind) -> StageConfig {
    StageConfig {
        id: kind.stage_id().to_string(),
        organ: config.process.organ.clone(),
        budget: None,
        inputs: Vec::new(),
        outputs: match kind {
            ProcessStageKind::Plan => vec![EntryType::Decision, EntryType::Requirement],
            ProcessStageKind::ArtifactGate => vec![EntryType::Audit, EntryType::Decision],
            ProcessStageKind::Verdict => vec![EntryType::Verdict, EntryType::Audit],
        },
        context: Some(StageContextConfig {
            mode: "head".to_string(),
            chars_per_entry: Some(420),
            chars_total: Some(8_000),
            keywords: Vec::new(),
        }),
        actors: ActorConfig {
            mode: "fixed".to_string(),
            count: Some(config.process.agent_count),
            min: Some(1),
            max: Some(config.process.agent_count),
            scale_by: Vec::new(),
            roles: vec!["process_manager".to_string()],
        },
        clustering: None,
        command: None,
        artifact: None,
        retract_overturned: false,
        grounded: false,
    }
}

fn select_process_inputs(
    store: &ReferenceStore,
    scenario: &Scenario,
    kind: ProcessStageKind,
) -> Vec<Entry> {
    let mut selected = Vec::new();
    let mut seen = BTreeSet::new();
    let task_query = scenario.task.lines().next().unwrap_or_default();

    for entry in store.serve(task_query, 8) {
        if seen.insert(entry.id.clone()) {
            selected.push(entry);
        }
    }

    let mut candidates = store
        .all()
        .iter()
        .filter(|entry| entry.status == EntryStatus::Active)
        .filter(|entry| process_input_matches_kind(entry, kind))
        .cloned()
        .collect::<Vec<_>>();
    candidates.reverse();

    for entry in candidates.into_iter().take(64) {
        if seen.insert(entry.id.clone()) {
            selected.push(entry);
        }
    }

    if selected.is_empty() {
        selected.extend(store.all().iter().take(12).cloned());
    }
    selected
}

fn process_input_matches_kind(entry: &Entry, kind: ProcessStageKind) -> bool {
    match kind {
        ProcessStageKind::Plan => {
            entry.meta.get("kind").and_then(Value::as_str).is_some()
                || matches!(entry.entry_type, EntryType::Procedure)
        }
        ProcessStageKind::ArtifactGate => {
            matches!(
                entry.entry_type,
                EntryType::Audit | EntryType::Question | EntryType::Requirement | EntryType::Change
            ) || entry.meta.get("data_quality_warnings").is_some()
                || entry.meta.get("artifact").is_some()
        }
        ProcessStageKind::Verdict => {
            matches!(
                entry.entry_type,
                EntryType::Audit
                    | EntryType::Decision
                    | EntryType::Verdict
                    | EntryType::Question
                    | EntryType::Requirement
                    | EntryType::Change
            ) || entry.meta.get("artifact").is_some()
                || entry.meta.get("data_quality_warnings").is_some()
        }
    }
}

fn process_signals(store: &ReferenceStore, selected: &[Entry]) -> BTreeMap<String, usize> {
    let mut signals = BTreeMap::new();
    signals.insert("active_entries".to_string(), store.all().len());
    signals.insert("selected_entries".to_string(), selected.len());
    let question_entries = store
        .all()
        .iter()
        .filter(|entry| entry.status == EntryStatus::Active)
        .filter(|entry| entry.entry_type == EntryType::Question)
        .count();
    signals.insert("question_entries".to_string(), question_entries);
    signals.insert(
        "open_questions".to_string(),
        unresolved_question_count(store.all().iter()),
    );
    signals.insert(
        "quality_warning_entries".to_string(),
        store
            .all()
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
            .filter(|entry| entry.meta.get("data_quality_warnings").is_some())
            .count(),
    );
    signals
}

fn unresolved_question_count<'a>(entries: impl IntoIterator<Item = &'a Entry>) -> usize {
    let entries = entries
        .into_iter()
        .filter(|entry| entry.status == EntryStatus::Active)
        .collect::<Vec<_>>();
    let question_ids = entries
        .iter()
        .filter(|entry| entry.entry_type == EntryType::Question)
        .map(|entry| entry.id.clone())
        .collect::<BTreeSet<_>>();
    if question_ids.is_empty() {
        return 0;
    }

    let resolved = entries
        .iter()
        .filter(|entry| question_resolving_entry(entry))
        .flat_map(|entry| resolved_question_ids(entry, &question_ids))
        .collect::<BTreeSet<_>>();
    question_ids.difference(&resolved).count()
}

fn question_resolving_entry(entry: &Entry) -> bool {
    if entry.entry_type == EntryType::Question {
        return false;
    }
    if entry.entry_type == EntryType::Answer {
        return true;
    }
    let status = entry_meta_string(entry, "status")
        .or_else(|| entry_meta_string(entry, "resolution_status"))
        .unwrap_or_default()
        .to_ascii_lowercase();
    let action = entry_meta_string(entry, "action")
        .unwrap_or_default()
        .to_ascii_lowercase();
    matches!(
        status.as_str(),
        "resolved" | "answered" | "closed" | "accepted"
    ) || matches!(action.as_str(), "resolve" | "answer" | "close")
        || !entry_meta_strings(entry, "resolves_question").is_empty()
        || !entry_meta_strings(entry, "resolves_questions").is_empty()
        || !entry_meta_strings(entry, "resolved_question").is_empty()
        || !entry_meta_strings(entry, "question_id").is_empty()
}

fn resolved_question_ids(entry: &Entry, question_ids: &BTreeSet<String>) -> Vec<String> {
    let mut resolved = BTreeSet::new();
    for citation in &entry.citations {
        if question_ids.contains(citation) {
            resolved.insert(citation.clone());
        }
    }
    for key in [
        "resolves_question",
        "resolves_questions",
        "resolved_question",
        "question_id",
    ] {
        for value in entry_meta_strings(entry, key) {
            if question_ids.contains(&value) {
                resolved.insert(value);
            }
        }
    }
    resolved.into_iter().collect()
}

fn entry_meta_strings(entry: &Entry, key: &str) -> Vec<String> {
    match entry.meta.get(key) {
        Some(Value::String(value)) => value
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .collect(),
        Some(Value::Array(values)) => values
            .iter()
            .filter_map(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .collect(),
        _ => Vec::new(),
    }
}

impl ProcessStageKind {
    fn stage_id(self) -> &'static str {
        match self {
            Self::Plan => "process_plan",
            Self::ArtifactGate => "process_artifact_gate",
            Self::Verdict => "process_verdict",
        }
    }

    fn reason(self) -> &'static str {
        match self {
            Self::Plan => "process_plan",
            Self::ArtifactGate => "process_artifact_gate",
            Self::Verdict => "process_verdict",
        }
    }
}

fn actor_parallelism(config: &FlowConfig, actor_count: usize) -> usize {
    if actor_count <= 1 {
        return 1;
    }
    let configured = config
        .actor_scaling
        .max_parallel_actors
        .unwrap_or(if config.long_run.enabled { 4 } else { 1 });
    configured.max(1).min(actor_count)
}

fn checkpoint_flow_store(store: &ReferenceStore, persist_path: Option<&Path>) -> Result<()> {
    if let Some(path) = persist_path {
        store.write_jsonl(path)?;
    }
    Ok(())
}

fn log_flow_progress(config: &FlowConfig, message: impl AsRef<str>) {
    if config.long_run.enabled || config.actor_scaling.max_parallel_actors.unwrap_or(1) > 1 {
        eprintln!("[tracefield:flow] {}", message.as_ref());
    }
}

fn existing_work_item_entries(
    store: &ReferenceStore,
    stage: &StageConfig,
    work_item: &FlowWorkItem,
    actor_index: Option<usize>,
    author: Option<&str>,
) -> Vec<Entry> {
    store
        .all()
        .iter()
        .filter(|entry| entry.status == EntryStatus::Active)
        .filter(|entry| entry.meta.get("stage").and_then(Value::as_str) == Some(stage.id.as_str()))
        .filter(|entry| entry_meta_usize(entry, "work_item_cycle") == Some(work_item.cycle))
        .filter(|entry| {
            entry.meta.get("work_item_reason").and_then(Value::as_str)
                == Some(work_item.reason.as_str())
        })
        .filter(|entry| {
            actor_index.is_none_or(|actor_index| {
                entry_meta_usize(entry, "actor_index") == Some(actor_index)
            })
        })
        .filter(|entry| author.is_none_or(|author| entry.author == author))
        .filter(|entry| entry_feedback_request_ids_match(entry, &work_item.feedback_request_ids))
        .cloned()
        .collect()
}

fn entry_meta_usize(entry: &Entry, key: &str) -> Option<usize> {
    entry
        .meta
        .get(key)
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
}

fn entry_feedback_request_ids_match(entry: &Entry, expected: &[String]) -> bool {
    let Some(values) = entry.meta.get("feedback_request_ids") else {
        return expected.is_empty();
    };
    let Some(values) = values.as_array() else {
        return expected.is_empty();
    };
    let actual = values
        .iter()
        .filter_map(Value::as_str)
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
    actual == expected
}

fn attach_work_item_meta(mut entries: Vec<NewEntry>, work_item: &FlowWorkItem) -> Vec<NewEntry> {
    for entry in &mut entries {
        entry
            .meta
            .insert("work_item_cycle".to_string(), json!(work_item.cycle));
        entry.meta.insert(
            "work_item_reason".to_string(),
            json!(work_item.reason.clone()),
        );
        if !work_item.feedback_request_ids.is_empty() {
            entry.meta.insert(
                "feedback_request_ids".to_string(),
                json!(work_item.feedback_request_ids.clone()),
            );
        }
    }
    entries
}

fn parse_feedback_config(document: &MiniToml) -> Result<FeedbackConfig> {
    let feedback = document.table("feedback").cloned().unwrap_or_default();
    let mut edges = Vec::new();
    for (_, values) in document
        .sections
        .iter()
        .filter(|(section, _)| is_array_table(section, "feedback.edge"))
    {
        edges.push(FeedbackEdge {
            from: string_array(values, "from"),
            to: string_value(values, "to").unwrap_or_default(),
            entry_types: string_array(values, "entry_types")
                .into_iter()
                .map(|value| parse_config_entry_type(&value))
                .collect::<Result<Vec<_>>>()?,
            trigger_when: string_array(values, "trigger_when"),
        });
    }
    edges.retain(|edge| !edge.to.is_empty());

    Ok(FeedbackConfig {
        enabled: bool_value(&feedback, "enabled").unwrap_or(false),
        max_requests_per_cycle: usize_value(&feedback, "max_requests_per_cycle").unwrap_or(12),
        dedupe_by: string_array(&feedback, "dedupe_by"),
        edges,
    })
}

fn parse_feedback_entries_config(document: &MiniToml) -> Result<FeedbackEntriesConfig> {
    let feedback_entries = document
        .table("feedback_entries")
        .cloned()
        .unwrap_or_default();
    let mut routes = Vec::new();
    for (_, values) in document
        .sections
        .iter()
        .filter(|(section, _)| is_array_table(section, "feedback_entries.route"))
    {
        routes.push(FeedbackEntryRoute {
            from: string_array(values, "from"),
            target_prefix: string_value(values, "target_prefix"),
            to: string_value(values, "to").unwrap_or_default(),
            entry_types: string_array(values, "entry_types")
                .into_iter()
                .map(|value| parse_config_entry_type(&value))
                .collect::<Result<Vec<_>>>()?,
            actions: string_array(values, "actions"),
        });
    }
    routes.retain(|route| !route.to.is_empty());

    Ok(FeedbackEntriesConfig {
        enabled: bool_value(&feedback_entries, "enabled").unwrap_or(false),
        kind: string_value(&feedback_entries, "kind")
            .unwrap_or_else(|| "tracefield_feedback".to_string()),
        accepted_types: string_array(&feedback_entries, "accepted_types")
            .into_iter()
            .map(|value| parse_config_entry_type(&value))
            .collect::<Result<Vec<_>>>()?,
        status_field: string_value(&feedback_entries, "status_field")
            .unwrap_or_else(|| "status".to_string()),
        max_requests_per_cycle: usize_value(&feedback_entries, "max_requests_per_cycle")
            .unwrap_or(8),
        dedupe_by: string_array(&feedback_entries, "dedupe_by"),
        routes,
    })
}

fn parse_actor_config(values: &BTreeMap<String, ConfigValue>, default_mode: &str) -> ActorConfig {
    ActorConfig {
        mode: string_value(values, "mode").unwrap_or_else(|| default_mode.to_string()),
        count: usize_value(values, "count"),
        min: usize_value(values, "min"),
        max: usize_value(values, "max"),
        scale_by: string_array(values, "scale_by"),
        roles: string_array(values, "roles"),
    }
}

fn parse_stage_context(values: &BTreeMap<String, ConfigValue>) -> StageContextConfig {
    StageContextConfig {
        mode: string_value(values, "mode").unwrap_or_else(|| "head".to_string()),
        chars_per_entry: usize_value(values, "chars_per_entry"),
        chars_total: usize_value(values, "chars_total"),
        keywords: string_array(values, "keywords"),
    }
}

fn parse_stage_clustering(values: &BTreeMap<String, ConfigValue>) -> StageClusteringConfig {
    StageClusteringConfig {
        enabled: bool_value(values, "enabled").unwrap_or(true),
        by: string_array(values, "by"),
        min_cluster_size: usize_value(values, "min_cluster_size"),
        max_clusters: usize_value(values, "max_clusters"),
    }
}

fn parse_stage_command(values: &BTreeMap<String, ConfigValue>) -> StageCommandConfig {
    StageCommandConfig {
        program: string_value(values, "program").unwrap_or_default(),
        args: string_array(values, "args"),
        cwd: string_value(values, "cwd"),
        timeout_seconds: usize_value(values, "timeout_seconds").map(|value| value as u64),
    }
}

fn parse_stage_artifact(values: &BTreeMap<String, ConfigValue>) -> StageArtifactConfig {
    StageArtifactConfig {
        kind: string_value(values, "kind"),
        format: string_value(values, "format"),
        audience: string_value(values, "audience"),
        require_citations: bool_value(values, "require_citations").unwrap_or(false),
    }
}

fn validate_policy(policy: &str) -> Result<()> {
    match policy {
        "fixed" | "best_first" | "adaptive_branching" | "multi_organ_adaptive" => Ok(()),
        other => bail!("unknown flow policy {other}"),
    }
}

fn validate_actor_mode(mode: &str) -> Result<()> {
    match mode {
        "fixed" | "per_input" | "per_source" | "per_cluster" | "per_agent" | "auto" | "none" => {
            Ok(())
        }
        other => bail!("unknown actor mode {other}"),
    }
}

fn validate_stage_context_mode(mode: &str) -> Result<()> {
    match mode {
        "head" | "source_excerpt" => Ok(()),
        other => bail!("unknown stage context mode {other}"),
    }
}

fn validate_stage_id(id: &str) -> Result<()> {
    if id.is_empty() {
        bail!("stage id must not be empty");
    }
    if !id
        .chars()
        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_' || ch == '-')
    {
        bail!("invalid stage id {id}; use lowercase ASCII, digits, '_' or '-'");
    }
    Ok(())
}

fn parse_config_entry_type(value: &str) -> Result<EntryType> {
    match value.trim().to_ascii_lowercase().as_str() {
        "belief" => Ok(EntryType::Belief),
        "hypothesis" => Ok(EntryType::Hypothesis),
        "observation" => Ok(EntryType::Observation),
        "stance" => Ok(EntryType::Stance),
        "decision" => Ok(EntryType::Decision),
        "question" => Ok(EntryType::Question),
        "requirement" => Ok(EntryType::Requirement),
        "answer" => Ok(EntryType::Answer),
        "change" => Ok(EntryType::Change),
        "verdict" => Ok(EntryType::Verdict),
        "chunk" => Ok(EntryType::Chunk),
        "corpus_chunk" | "corpus-chunk" => Ok(EntryType::CorpusChunk),
        "procedure" => Ok(EntryType::Procedure),
        "claim" => Ok(EntryType::Claim),
        "synthesis" => Ok(EntryType::Synthesis),
        "audit" => Ok(EntryType::Audit),
        other => bail!("unknown entry type {other}"),
    }
}

fn seed_flow_layer0(store: &mut ReferenceStore, scenario: &Scenario) -> Result<SeededFlow> {
    let task = push_or_reuse_seed(
        store,
        NewEntry::new(EntryType::Chunk, "scenario", scenario.task.clone())
            .with_meta("kind", json!("task")),
        "scenario",
        "task",
        None,
    );
    let mut entries = vec![task.clone()];

    for (name, content) in &scenario.private_docs {
        let path = format!("private/{name}");
        let entry = push_or_reuse_seed(
            store,
            NewEntry::new(EntryType::CorpusChunk, "scenario", content.clone())
                .with_citations(vec![task.id.clone()])
                .with_meta("kind", json!("private"))
                .with_meta("path", json!(path.clone())),
            "scenario",
            "private",
            Some(&path),
        );
        entries.push(entry);
    }

    for input in load_input_docs(&scenario.dir)? {
        let mut new_entry = NewEntry::new(EntryType::CorpusChunk, "scenario", input.content)
            .with_citations(vec![task.id.clone()])
            .with_meta("kind", json!("input"))
            .with_meta("path", json!(input.path.clone()));
        for (key, value) in input.meta {
            new_entry.meta.entry(key).or_insert(value);
        }
        let entry = push_or_reuse_seed(store, new_entry, "scenario", "input", Some(&input.path));
        entries.push(entry);
    }

    let mut skill_entry_ids = BTreeMap::new();
    for skill in scenario.skills.values() {
        let entry = push_or_reuse_seed(
            store,
            NewEntry::new(EntryType::Procedure, "scenario", skill.raw_content.clone())
                .with_citations(vec![task.id.clone()])
                .with_meta("kind", json!("skill"))
                .with_meta("skill", json!(skill.id.clone()))
                .with_meta("name", json!(skill.name.clone()))
                .with_meta("description", json!(skill.description.clone()))
                .with_meta("path", json!(skill.path.clone())),
            "scenario",
            "skill",
            Some(&skill.path),
        );
        skill_entry_ids.insert(skill.id.clone(), entry.id.clone());
        entries.push(entry);
    }

    Ok(SeededFlow {
        entries,
        skill_entry_ids,
    })
}

fn push_or_reuse_seed(
    store: &mut ReferenceStore,
    entry: NewEntry,
    fallback_author: &str,
    kind: &str,
    path: Option<&str>,
) -> Entry {
    if let Some(existing) = store.all().iter().find(|existing| {
        existing.status == EntryStatus::Active
            && existing.meta.get("kind").and_then(Value::as_str) == Some(kind)
            && path
                .is_none_or(|path| existing.meta.get("path").and_then(Value::as_str) == Some(path))
    }) {
        return existing.clone();
    }

    store.push(entry, fallback_author)
}

#[derive(Debug)]
struct InputDoc {
    path: String,
    content: String,
    meta: Map<String, Value>,
}

fn load_input_docs(scenario_dir: &Path) -> Result<Vec<InputDoc>> {
    let input_dir = scenario_dir.join("inputs");
    if !input_dir.exists() {
        return Ok(Vec::new());
    }

    let mut docs = Vec::new();
    read_input_docs_recursive(&input_dir, &input_dir, &mut docs)?;
    docs.sort_by(|left, right| left.path.cmp(&right.path));
    Ok(docs)
}

fn read_input_docs_recursive(base: &Path, dir: &Path, docs: &mut Vec<InputDoc>) -> Result<()> {
    for entry in fs::read_dir(dir).with_context(|| format!("failed to read {}", dir.display()))? {
        let entry = entry.with_context(|| format!("failed to read entry in {}", dir.display()))?;
        let path = entry.path();
        if path.is_dir() {
            read_input_docs_recursive(base, &path, docs)?;
            continue;
        }

        let extension = path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
        if !matches!(extension, "md" | "txt" | "json" | "jsonl") {
            continue;
        }

        let content = fs::read_to_string(&path)
            .with_context(|| format!("failed to read {}", path.display()))?;
        let meta = parse_input_doc_meta(&content);
        let relative = path
            .strip_prefix(base)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();
        docs.push(InputDoc {
            path: format!("inputs/{relative}"),
            content,
            meta,
        });
    }

    Ok(())
}

fn parse_input_doc_meta(content: &str) -> Map<String, Value> {
    let mut meta = Map::new();
    let Some(rest) = content.strip_prefix("---") else {
        return meta;
    };
    let Some(rest) = rest
        .strip_prefix("\r\n")
        .or_else(|| rest.strip_prefix('\n'))
    else {
        return meta;
    };
    let Some(end) = rest.find("\n---") else {
        return meta;
    };

    for line in rest[..end].lines() {
        let Some((key, raw_value)) = line.split_once(':') else {
            continue;
        };
        let key = key.trim();
        if key.is_empty()
            || !key
                .chars()
                .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_')
        {
            continue;
        }
        meta.insert(key.to_string(), parse_frontmatter_scalar(raw_value));
    }

    meta
}

fn parse_frontmatter_scalar(raw_value: &str) -> Value {
    let value = raw_value.trim();
    if value.is_empty() {
        return Value::String(String::new());
    }
    if let Ok(parsed) = serde_json::from_str::<Value>(value) {
        return parsed;
    }
    if let Ok(parsed) = value.parse::<u64>() {
        return json!(parsed);
    }
    match value {
        "true" => json!(true),
        "false" => json!(false),
        _ => Value::String(value.trim_matches('"').to_string()),
    }
}

fn select_stage_inputs(
    store: &ReferenceStore,
    stage: &StageConfig,
    scenario: &Scenario,
    feedback_request_ids: &[String],
) -> Vec<Entry> {
    let mut selected = feedback_request_ids
        .iter()
        .filter_map(|id| store.get(id))
        .filter(|entry| entry.status == EntryStatus::Active)
        .cloned()
        .collect::<Vec<_>>();
    let mut seen = selected
        .iter()
        .map(|entry| entry.id.clone())
        .collect::<BTreeSet<_>>();

    if stage.inputs.is_empty() {
        let query = format!("{}\n{}", scenario.task, stage.id);
        let retrieved = store.serve(&query, 12);
        if !retrieved.is_empty() {
            for entry in retrieved {
                if seen.insert(entry.id.clone()) {
                    selected.push(entry);
                }
            }
            return selected;
        }
        for entry in store
            .all()
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
            .take(12)
        {
            if seen.insert(entry.id.clone()) {
                selected.push(entry.clone());
            }
        }
        return selected;
    }

    for selector in &stage.inputs {
        for entry in entries_for_selector(store, selector) {
            if seen.insert(entry.id.clone()) {
                selected.push(entry);
            }
        }
    }
    selected
}

fn entries_for_selector(store: &ReferenceStore, selector: &str) -> Vec<Entry> {
    let selector = selector.trim();
    if selector == "all" {
        return store
            .all()
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
            .cloned()
            .collect();
    }

    if let Some(value) = selector.strip_prefix("entry_type:") {
        let entry_type = EntryType::parse(value);
        return store
            .all()
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active && entry.entry_type == entry_type)
            .cloned()
            .collect();
    }

    if let Some(value) = selector.strip_prefix("kind:") {
        return store
            .all()
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
            .filter(|entry| entry.meta.get("kind").and_then(Value::as_str) == Some(value))
            .cloned()
            .collect();
    }

    if let Some(value) = selector.strip_prefix("path:") {
        let value = value.trim();
        return store
            .all()
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
            .filter(|entry| entry.meta.get("path").and_then(Value::as_str) == Some(value))
            .cloned()
            .collect();
    }

    if let Some(value) = selector.strip_prefix("source_url:") {
        let value = value.trim();
        return store
            .all()
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
            .filter(|entry| entry.meta.get("source_url").and_then(Value::as_str) == Some(value))
            .cloned()
            .collect();
    }

    if let Some(value) = selector.strip_prefix("stage:") {
        return store
            .all()
            .iter()
            .filter(|entry| entry.status == EntryStatus::Active)
            .filter(|entry| entry.meta.get("stage").and_then(Value::as_str) == Some(value))
            .cloned()
            .collect();
    }

    Vec::new()
}

fn feedback_work_items(
    config: &FlowConfig,
    source_stage_index: usize,
    produced_entries: &[Entry],
    feedback_cycles: &mut usize,
) -> Vec<FlowWorkItem> {
    if !config.feedback.enabled && !config.feedback_entries.enabled {
        return Vec::new();
    }
    let max_cycles = effective_max_feedback_cycles(config);
    if *feedback_cycles >= max_cycles {
        return Vec::new();
    }

    let source_stage = &config.stages[source_stage_index];
    let mut work_items = Vec::new();
    let mut requests_this_cycle = 0;
    let mut seen_requests = BTreeSet::new();

    if config.feedback.enabled {
        for edge in &config.feedback.edges {
            if !edge.from.iter().any(|stage| stage == &source_stage.id) {
                continue;
            }
            let Some(target_index) = config.stages.iter().position(|stage| stage.id == edge.to)
            else {
                continue;
            };

            let request_ids = produced_entries
                .iter()
                .filter(|entry| feedback_edge_entry_matches(entry, edge))
                .filter_map(|entry| {
                    if requests_this_cycle >= config.feedback.max_requests_per_cycle {
                        return None;
                    }
                    if seen_requests.insert(format!("edge:{}", entry.id)) {
                        requests_this_cycle += 1;
                        Some(entry.id.clone())
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>();

            push_feedback_work_items(
                &mut work_items,
                feedback_cycles,
                max_cycles,
                source_stage_index,
                target_index,
                request_ids,
            );

            if *feedback_cycles >= max_cycles {
                break;
            }
        }
    }

    if config.feedback_entries.enabled && *feedback_cycles < max_cycles {
        let mut feedback_entry_requests = 0;
        for route in &config.feedback_entries.routes {
            if !route.from.is_empty() && !route.from.iter().any(|stage| stage == &source_stage.id) {
                continue;
            }
            let Some(target_index) = config.stages.iter().position(|stage| stage.id == route.to)
            else {
                continue;
            };

            let request_ids = produced_entries
                .iter()
                .filter(|entry| {
                    feedback_config_entry_matches(entry, &config.feedback_entries, route)
                })
                .filter_map(|entry| {
                    if feedback_entry_requests >= config.feedback_entries.max_requests_per_cycle {
                        return None;
                    }
                    let dedupe_key = feedback_entry_dedupe_key(entry, &config.feedback_entries);
                    if seen_requests.insert(format!("entry:{dedupe_key}")) {
                        feedback_entry_requests += 1;
                        Some(entry.id.clone())
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>();

            push_feedback_work_items(
                &mut work_items,
                feedback_cycles,
                max_cycles,
                source_stage_index,
                target_index,
                request_ids,
            );

            if *feedback_cycles >= max_cycles {
                break;
            }
        }
    }

    work_items
}

fn push_feedback_work_items(
    work_items: &mut Vec<FlowWorkItem>,
    feedback_cycles: &mut usize,
    max_cycles: usize,
    source_stage_index: usize,
    target_index: usize,
    request_ids: Vec<String>,
) {
    if request_ids.is_empty() || *feedback_cycles >= max_cycles {
        return;
    }

    *feedback_cycles += 1;
    let end = source_stage_index.max(target_index);
    for stage_index in target_index..=end {
        work_items.push(FlowWorkItem {
            stage_index,
            feedback_request_ids: request_ids.clone(),
            cycle: *feedback_cycles,
            reason: "feedback".to_string(),
        });
    }
}

fn effective_max_feedback_cycles(config: &FlowConfig) -> usize {
    config
        .process
        .stop
        .max_feedback_cycles
        .or(config.long_run.max_feedback_cycles)
        .or(config.max_feedback_cycles)
        .unwrap_or(0)
}

fn effective_max_long_run_cycles(config: &FlowConfig) -> usize {
    config
        .process
        .stop
        .max_cycles
        .unwrap_or(config.long_run.cycles)
        .max(1)
}

fn configured_long_run_cycles(config: &FlowConfig) -> usize {
    if config.long_run.enabled {
        effective_max_long_run_cycles(config)
    } else {
        1
    }
}

fn is_process_artifact_stage(config: &FlowConfig, stage_index: usize) -> bool {
    let stage = &config.stages[stage_index];
    if config.process.artifact_stages.is_empty() {
        stage.artifact.is_some()
    } else {
        config
            .process
            .artifact_stages
            .iter()
            .any(|stage_id| stage_id == &stage.id)
    }
}

fn process_artifact_gate_decision(
    config: &FlowConfig,
    entries: &[Entry],
) -> ProcessArtifactGateDecision {
    if !config.process.gates.enforce_artifact_gate {
        return ProcessArtifactGateDecision {
            allow_artifacts: true,
            reason: "process artifact gate enforcement is disabled".to_string(),
            blocking_entry_ids: Vec::new(),
        };
    }

    let mut reasons = Vec::new();
    let mut blocking_entry_ids = BTreeSet::new();
    let open_questions = max_process_signal(entries, "open_questions");
    if config.process.gates.block_publish_on_open_questions && open_questions > 0 {
        reasons.push(format!("open_questions={open_questions}"));
        blocking_entry_ids.extend(entries.iter().map(|entry| entry.id.clone()));
    }

    let quality_warnings = max_process_signal(entries, "quality_warning_entries");
    if config.process.gates.block_publish_on_quality_warnings && quality_warnings > 0 {
        reasons.push(format!("quality_warning_entries={quality_warnings}"));
        blocking_entry_ids.extend(entries.iter().map(|entry| entry.id.clone()));
    }

    for entry in entries {
        if let Some(reason) = entry_blocks_artifacts(config, entry) {
            reasons.push(reason);
            blocking_entry_ids.insert(entry.id.clone());
        }
    }

    if reasons.is_empty() {
        return ProcessArtifactGateDecision {
            allow_artifacts: true,
            reason: "process artifact gate allowed artifact stages".to_string(),
            blocking_entry_ids: Vec::new(),
        };
    }

    ProcessArtifactGateDecision {
        allow_artifacts: false,
        reason: reasons.join("; "),
        blocking_entry_ids: blocking_entry_ids.into_iter().collect(),
    }
}

fn entry_blocks_artifacts(config: &FlowConfig, entry: &Entry) -> Option<String> {
    let action = entry_meta_string(entry, "action")
        .unwrap_or_default()
        .to_ascii_lowercase();
    if matches!(action.as_str(), "block" | "recollect" | "rerun") {
        return Some(format!("{} action={action}", entry.id));
    }

    let publish_verdict = entry_meta_string(entry, "publish_verdict")
        .unwrap_or_default()
        .to_ascii_lowercase();
    match publish_verdict.as_str() {
        "blocked" => return Some(format!("{} publish_verdict=blocked", entry.id)),
        "conditional" if !config.process.gates.allow_conditional_artifacts => {
            return Some(format!("{} publish_verdict=conditional", entry.id));
        }
        _ => {}
    }

    let stop_verdict = entry_meta_string(entry, "stop_verdict")
        .unwrap_or_default()
        .to_ascii_lowercase();
    if stop_verdict == "needs_followup" {
        return Some(format!("{} stop_verdict=needs_followup", entry.id));
    }

    let text = entry.text.to_ascii_lowercase();
    let blocking_text = [
        "publish is blocked",
        "block artifact",
        "block publish",
        "should wait",
        "require recollection",
        "requires recollection",
        "must not proceed",
        "may resume only after",
    ];
    if blocking_text.iter().any(|needle| text.contains(needle)) {
        return Some(format!("{} text_blocks_artifacts", entry.id));
    }

    None
}

fn max_process_signal(entries: &[Entry], signal_name: &str) -> usize {
    entries
        .iter()
        .filter_map(|entry| {
            entry
                .meta
                .get("actor_scaling")
                .and_then(|value| value.get("signals"))
                .and_then(|signals| signals.get(signal_name))
                .and_then(Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
        })
        .max()
        .unwrap_or(0)
}

fn remove_process_artifact_work_items(
    config: &FlowConfig,
    work_queue: &mut Vec<FlowWorkItem>,
) -> Vec<String> {
    let mut removed = Vec::new();
    work_queue.retain(|item| {
        if is_process_artifact_stage(config, item.stage_index) {
            removed.push(config.stages[item.stage_index].id.clone());
            false
        } else {
            true
        }
    });
    removed
}

#[allow(clippy::too_many_arguments)]
fn record_artifact_gate_enforcement(
    config: &FlowConfig,
    store: &mut ReferenceStore,
    gate_result: &StageRunResult,
    gate_decision: &ProcessArtifactGateDecision,
    blocked_stage_ids: &[String],
    cycle: usize,
    budget_step: usize,
    persist_path: Option<&Path>,
) -> Result<Entry> {
    let blocked_stage_set = blocked_stage_ids
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let citations = if gate_decision.blocking_entry_ids.is_empty() {
        gate_result
            .entries
            .iter()
            .map(|entry| entry.id.clone())
            .collect::<Vec<_>>()
    } else {
        gate_decision.blocking_entry_ids.clone()
    };
    let blocked_stage_list = blocked_stage_set.join(", ");
    let text = format!(
        "Artifact gate enforced: skipped artifact stages [{}]. Reason: {}",
        blocked_stage_list, gate_decision.reason
    );
    let marker = NewEntry::new(EntryType::Decision, "flow", text)
        .with_citations(citations)
        .with_meta("kind", json!("process_gate_enforcement"))
        .with_meta("process_stage", json!("process_artifact_gate"))
        .with_meta("action", json!("block"))
        .with_meta("publish_verdict", json!("blocked"))
        .with_meta("stage", json!("process_artifact_gate"))
        .with_meta("source_stage", json!("process_artifact_gate"))
        .with_meta("flow", json!(config.profile.clone()))
        .with_meta("policy", json!(config.policy.clone()))
        .with_meta("budget_step", json!(budget_step))
        .with_meta("work_item_cycle", json!(cycle))
        .with_meta("work_item_reason", json!("process_gate_enforcement"))
        .with_meta("blocked_artifact_stages", json!(blocked_stage_set))
        .with_meta(
            "blocked_artifact_stage_count",
            json!(blocked_stage_ids.len()),
        )
        .with_meta("gate_reason", json!(gate_decision.reason.clone()));
    let mut stored = store.absorb(vec![marker], "flow");
    checkpoint_flow_store(store, persist_path)?;
    stored
        .pop()
        .context("process artifact gate enforcement marker was not stored")
}

fn insert_feedback_work_items(
    config: &FlowConfig,
    work_queue: &mut Vec<FlowWorkItem>,
    feedback_work: Vec<FlowWorkItem>,
) {
    if feedback_work.is_empty() {
        return;
    }
    if !config.process.enabled || !config.process.artifact_after_feedback {
        work_queue.extend(feedback_work);
        return;
    }

    let insert_at = work_queue
        .iter()
        .position(|item| is_process_artifact_stage(config, item.stage_index))
        .unwrap_or(work_queue.len());
    for (offset, item) in feedback_work.into_iter().enumerate() {
        work_queue.insert(insert_at + offset, item);
    }
}

fn feedback_edge_entry_matches(entry: &Entry, edge: &FeedbackEdge) -> bool {
    if !edge.entry_types.is_empty() && !edge.entry_types.contains(&entry.entry_type) {
        return false;
    }
    if edge.trigger_when.is_empty() {
        return true;
    }

    let fields = [
        entry.meta.get("verdict").and_then(Value::as_str),
        entry.meta.get("reason").and_then(Value::as_str),
        entry.meta.get("trigger").and_then(Value::as_str),
        entry.meta.get("status").and_then(Value::as_str),
    ];
    fields
        .into_iter()
        .flatten()
        .any(|field| edge.trigger_when.iter().any(|trigger| trigger == field))
}

fn feedback_config_entry_matches(
    entry: &Entry,
    config: &FeedbackEntriesConfig,
    route: &FeedbackEntryRoute,
) -> bool {
    if entry.meta.get("kind").and_then(Value::as_str) != Some(config.kind.as_str()) {
        return false;
    }
    if !config.accepted_types.is_empty() && !config.accepted_types.contains(&entry.entry_type) {
        return false;
    }
    if !route.entry_types.is_empty() && !route.entry_types.contains(&entry.entry_type) {
        return false;
    }
    if !route.actions.is_empty() {
        let Some(action) = entry.meta.get("action").and_then(Value::as_str) else {
            return false;
        };
        if !route.actions.iter().any(|allowed| allowed == action) {
            return false;
        }
    }
    if let Some(prefix) = &route.target_prefix {
        let Some(target) = entry.meta.get("target").and_then(Value::as_str) else {
            return false;
        };
        if !target.starts_with(prefix) {
            return false;
        }
    }

    true
}

fn feedback_entry_dedupe_key(entry: &Entry, config: &FeedbackEntriesConfig) -> String {
    if config.dedupe_by.is_empty() {
        return entry.id.clone();
    }

    config
        .dedupe_by
        .iter()
        .map(|field| match field.as_str() {
            "id" => entry.id.clone(),
            "target" => entry
                .meta
                .get("target")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            "action" => entry
                .meta
                .get("action")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            "priority" => entry
                .meta
                .get("priority")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            "source_stage" | "stage" => entry
                .meta
                .get("stage")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            "normalized_request" | "text" => normalize_feedback_request(&entry.text),
            other => entry
                .meta
                .get(other)
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
        })
        .collect::<Vec<_>>()
        .join("|")
}

fn normalize_feedback_request(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_ascii_lowercase()
}

fn apply_core_gates(
    entries: Vec<NewEntry>,
    store: &ReferenceStore,
    config: &FlowConfig,
    stage: &StageConfig,
    scenario_dir: &Path,
) -> Vec<NewEntry> {
    let active_ids = store
        .all()
        .iter()
        .filter(|entry| entry.status == EntryStatus::Active)
        .map(|entry| entry.id.as_str())
        .collect::<BTreeSet<_>>();

    entries
        .into_iter()
        .map(|mut entry| {
            let feedback_like = is_feedback_entry_like(&entry, config);
            let source_grounded_stage = is_source_grounded_stage(stage);
            if !stage.outputs.is_empty()
                && !stage.outputs.contains(&entry.entry_type)
                && !feedback_like
            {
                let original = format!("{:?}", entry.entry_type).to_ascii_lowercase();
                entry.entry_type = stage.outputs[0].clone();
                entry
                    .meta
                    .insert("coerced_type_from".to_string(), json!(original));
            }

            let before = entry.citations.clone();
            entry
                .citations
                .retain(|citation| active_ids.contains(citation.as_str()));
            if entry.citations != before {
                entry
                    .meta
                    .insert("invalid_citations_dropped".to_string(), json!(true));
            }

            entry
                .meta
                .entry("source_stage".to_string())
                .or_insert_with(|| json!(stage.id.clone()));

            if source_grounded_stage && !feedback_like {
                if entry.meta.contains_key("coerced_type_from") {
                    add_data_quality_warning(&mut entry.meta, "coerced_output_type");
                    entry
                        .meta
                        .entry("evidence_strength".to_string())
                        .or_insert_with(|| json!("needs_review"));
                }

                if entry.entry_type != EntryType::Question {
                    if let Some(quote) = evidence_quote(&entry.meta) {
                        let mut checked_quote = quote.clone();
                        let quote_found = quote_grounded(
                            store,
                            scenario_dir,
                            &entry.citations,
                            &entry.meta,
                            &quote,
                        );
                        if (weak_evidence_quote(&quote) || !quote_found)
                            && repair_evidence_quote(store, scenario_dir, &mut entry, &quote)
                            && let Some(repaired) = evidence_quote(&entry.meta)
                        {
                            checked_quote = repaired;
                        }

                        if weak_evidence_quote(&checked_quote) {
                            add_data_quality_warning(&mut entry.meta, "weak_evidence_quote");
                            entry
                                .meta
                                .entry("evidence_strength".to_string())
                                .or_insert_with(|| json!("needs_review"));
                        }
                        match quote_grounding(
                            store,
                            scenario_dir,
                            &entry.citations,
                            &entry.meta,
                            &checked_quote,
                        ) {
                            Some(QuoteGrounding::OnDisk) => {
                                entry
                                    .meta
                                    .insert("evidence_grounded".to_string(), json!("on_disk"));
                            }
                            Some(QuoteGrounding::CitedStore) => {}
                            None => {
                                add_data_quality_warning(
                                    &mut entry.meta,
                                    "evidence_quote_not_found",
                                );
                                entry
                                    .meta
                                    .entry("evidence_strength".to_string())
                                    .or_insert_with(|| json!("needs_review"));
                            }
                        }
                    } else {
                        add_data_quality_warning(&mut entry.meta, "missing_evidence_quote");
                        entry
                            .meta
                            .entry("evidence_strength".to_string())
                            .or_insert_with(|| json!("needs_review"));
                    }
                }

                if let Some((source_id, reason)) =
                    weak_source_for_citations(store, &entry.citations)
                {
                    add_data_quality_warning(&mut entry.meta, "weak_source");
                    entry
                        .meta
                        .insert("source_quality".to_string(), json!("weak"));
                    entry
                        .meta
                        .insert("source_quality_reason".to_string(), json!(reason));
                    entry
                        .meta
                        .insert("weak_source_id".to_string(), json!(source_id));
                    entry
                        .meta
                        .entry("action".to_string())
                        .or_insert_with(|| json!("recollect"));
                    if entry.entry_type != EntryType::Question
                        && stage.outputs.contains(&EntryType::Question)
                    {
                        let original = entry_type_name(&entry.entry_type);
                        entry.entry_type = EntryType::Question;
                        entry
                            .meta
                            .insert("converted_to_question_from".to_string(), json!(original));
                        entry.text = format!(
                            "Recollect stronger evidence before using this weak-source claim: {}",
                            first_chars(entry.text.trim(), 420)
                        );
                    }
                }
            }
            normalize_feedback_entry_meta(&mut entry, config);

            entry
        })
        .collect()
}

fn is_source_grounded_stage(stage: &StageConfig) -> bool {
    if stage.grounded {
        return true;
    }
    if stage.id.starts_with("source_") || stage.id.contains("web") || stage.id.contains("data") {
        return true;
    }
    if stage
        .organ
        .as_deref()
        .map(str::to_ascii_lowercase)
        .is_some_and(|organ| {
            organ.contains("data") || organ.contains("source") || organ.contains("web")
        })
    {
        return true;
    }
    stage.actors.roles.iter().any(|role| {
        let role = role.to_ascii_lowercase();
        role.contains("data") || role.contains("source") || role.contains("web")
    })
}

fn evidence_quote(meta: &Map<String, Value>) -> Option<String> {
    ["evidence_quote", "source_quote", "quote"]
        .iter()
        .find_map(|key| {
            meta.get(*key)
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
        })
}

fn weak_evidence_quote(quote: &str) -> bool {
    quote.chars().count() < 24
        || quote.split_whitespace().count() < 4
        || quote.contains("...")
        || quote.contains('…')
        || !source_quote_candidate_is_prose(quote)
}

fn evidence_quote_found_in_citations(
    store: &ReferenceStore,
    citations: &[String],
    quote: &str,
) -> bool {
    let quote_parts = evidence_quote_parts(quote);
    if quote_parts.is_empty() {
        return false;
    }

    citations.iter().any(|citation| {
        let Some(source) = store.all().iter().find(|entry| entry.id == *citation) else {
            return false;
        };
        let source_text = normalize_evidence_text(&source.text);
        quote_parts
            .iter()
            .all(|part| source_text.contains(&normalize_evidence_text(part)))
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum QuoteGrounding {
    CitedStore,
    OnDisk,
}

fn quote_grounded(
    store: &ReferenceStore,
    scenario_dir: &Path,
    citations: &[String],
    meta: &Map<String, Value>,
    quote: &str,
) -> bool {
    quote_grounding(store, scenario_dir, citations, meta, quote).is_some()
}

fn quote_grounding(
    store: &ReferenceStore,
    scenario_dir: &Path,
    citations: &[String],
    meta: &Map<String, Value>,
    quote: &str,
) -> Option<QuoteGrounding> {
    if evidence_quote_found_in_citations(store, citations, quote) {
        return Some(QuoteGrounding::CitedStore);
    }
    if quote_found_on_disk(scenario_dir, meta, quote) {
        return Some(QuoteGrounding::OnDisk);
    }
    None
}

fn quote_found_on_disk(scenario_dir: &Path, meta: &Map<String, Value>, quote: &str) -> bool {
    let Some(rel) = meta
        .get("source_path")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return false;
    };
    let rel_path = Path::new(rel);

    let quote_parts = evidence_quote_parts(quote);
    if quote_parts.is_empty() {
        return false;
    }

    let path = scenario_dir.join(rel_path);
    let Ok(metadata) = fs::metadata(&path) else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    let Ok(content) = fs::read_to_string(&path) else {
        return false;
    };

    let window = evidence_window_around_source_line(&content, source_line(meta));
    let haystack = normalize_evidence_text(&window);
    quote_parts
        .iter()
        .all(|part| haystack.contains(&normalize_evidence_text(part)))
}

fn source_line(meta: &Map<String, Value>) -> Option<usize> {
    match meta.get("source_line")? {
        Value::Number(number) => number
            .as_u64()
            .and_then(|value| usize::try_from(value).ok())
            .filter(|line| *line > 0),
        Value::String(value) => value.trim().parse::<usize>().ok().filter(|line| *line > 0),
        _ => None,
    }
}

fn evidence_window_around_source_line(content: &str, source_line: Option<usize>) -> String {
    let Some(source_line) = source_line else {
        return content.to_string();
    };
    let lines = content.lines().collect::<Vec<_>>();
    if source_line == 0 || source_line > lines.len() {
        return content.to_string();
    }
    let center = source_line - 1;
    let start = center.saturating_sub(40);
    let end = (center + 41).min(lines.len());
    lines[start..end].join("\n")
}

fn repair_evidence_quote(
    store: &ReferenceStore,
    scenario_dir: &Path,
    entry: &mut NewEntry,
    original_quote: &str,
) -> bool {
    let Some(repaired) =
        closest_source_quote_window(store, &entry.citations, &entry.text, original_quote)
    else {
        return false;
    };
    if !quote_grounded(
        store,
        scenario_dir,
        &entry.citations,
        &entry.meta,
        &repaired,
    ) {
        return false;
    }
    entry.meta.insert(
        "evidence_quote_original".to_string(),
        json!(original_quote.to_string()),
    );
    entry
        .meta
        .insert("evidence_quote".to_string(), json!(repaired));
    entry
        .meta
        .insert("evidence_quote_repaired".to_string(), json!(true));
    true
}

fn closest_source_quote_window(
    store: &ReferenceStore,
    citations: &[String],
    claim_text: &str,
    original_quote: &str,
) -> Option<String> {
    let terms = significant_evidence_tokens(&format!("{claim_text} {original_quote}"));
    if terms.len() < 3 {
        return None;
    }

    let mut best = None::<(usize, String)>;
    for citation in citations {
        let Some(source) = store.all().iter().find(|entry| entry.id == *citation) else {
            continue;
        };
        for candidate in source_quote_candidates(&source.text) {
            let window = best_evidence_window(&candidate, &terms);
            if !source_quote_candidate_is_prose(&window) {
                continue;
            }
            let score = significant_evidence_tokens(&window)
                .into_iter()
                .filter(|token| terms.contains(token))
                .collect::<BTreeSet<_>>()
                .len();
            if score >= 3
                && best
                    .as_ref()
                    .is_none_or(|(best_score, _)| score > *best_score)
            {
                best = Some((score, window));
            }
        }
    }

    best.map(|(_, quote)| quote)
}

fn source_quote_candidates(source_text: &str) -> Vec<String> {
    let cleaned = clean_source_text(source_text);
    let mut candidates = source_chunks(&cleaned);
    candidates.extend(
        cleaned
            .lines()
            .map(str::trim)
            .filter(|line| line.split_whitespace().count() >= 8)
            .map(ToOwned::to_owned),
    );
    candidates
        .into_iter()
        .filter(|candidate| source_quote_candidate_is_prose(candidate))
        .collect()
}

fn source_quote_candidate_is_prose(candidate: &str) -> bool {
    let lower = candidate.to_ascii_lowercase();
    if [
        "skip to content",
        "table of contents",
        "choose your path",
        "api reference",
        "initializing search",
        "previous ",
        "next ",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
    {
        return false;
    }

    let word_count = candidate.split_whitespace().count();
    if word_count < 8 {
        return false;
    }
    let punctuation_count = candidate
        .chars()
        .filter(|ch| matches!(ch, '.' | ',' | ':' | ';' | '(' | ')'))
        .count();
    if punctuation_count == 0 {
        return false;
    }

    let letter_count = candidate
        .chars()
        .filter(|ch| ch.is_ascii_alphabetic())
        .count();
    if letter_count == 0 {
        return false;
    }
    let lowercase_count = candidate
        .chars()
        .filter(|ch| ch.is_ascii_lowercase())
        .count();
    lowercase_count * 100 / letter_count >= 35
}

fn best_evidence_window(candidate: &str, terms: &BTreeSet<String>) -> String {
    let words = candidate.split_whitespace().collect::<Vec<_>>();
    if words.len() <= 30 {
        return candidate.trim().to_string();
    }

    let mut best_start = 0usize;
    let mut best_score = 0usize;
    for start in 0..words.len() {
        let end = (start + 30).min(words.len());
        let score = significant_evidence_tokens(&words[start..end].join(" "))
            .into_iter()
            .filter(|token| terms.contains(token))
            .count();
        if score > best_score {
            best_score = score;
            best_start = start;
        }
        if end == words.len() {
            break;
        }
    }
    words[best_start..(best_start + 30).min(words.len())].join(" ")
}

fn significant_evidence_tokens(value: &str) -> BTreeSet<String> {
    value
        .to_ascii_lowercase()
        .split(|ch: char| !ch.is_ascii_alphanumeric())
        .filter_map(|token| {
            let token = token.trim();
            if token.len() < 4 || EVIDENCE_STOPWORDS.contains(&token) {
                return None;
            }
            Some(normalize_evidence_token(token))
        })
        .collect()
}

fn normalize_evidence_token(token: &str) -> String {
    if token.len() > 4 && token.ends_with('s') {
        token[..token.len() - 1].to_string()
    } else {
        token.to_string()
    }
}

const EVIDENCE_STOPWORDS: &[&str] = &[
    "about",
    "across",
    "also",
    "another",
    "between",
    "concept",
    "concepts",
    "including",
    "management",
    "provides",
    "source",
    "their",
    "there",
    "these",
    "this",
    "through",
    "where",
    "which",
    "with",
];

fn evidence_quote_parts(quote: &str) -> Vec<String> {
    let parts = quote
        .split("...")
        .flat_map(|part| part.split('…'))
        .map(str::trim)
        .filter(|part| part.chars().count() >= 12)
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
    if parts.is_empty() && quote.trim().chars().count() >= 12 {
        vec![quote.trim().to_string()]
    } else {
        parts
    }
}

fn normalize_evidence_text(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_alphanumeric() || ch.is_whitespace() {
                ch.to_ascii_lowercase()
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn add_data_quality_warning(meta: &mut Map<String, Value>, warning: &str) {
    let mut warnings = meta
        .get("data_quality_warnings")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect::<BTreeSet<_>>()
        })
        .unwrap_or_default();
    warnings.insert(warning.to_string());
    meta.insert(
        "data_quality_warnings".to_string(),
        Value::Array(warnings.into_iter().map(Value::String).collect()),
    );
    meta.entry("data_quality".to_string())
        .or_insert_with(|| json!("needs_review"));
}

fn weak_source_for_citations(
    store: &ReferenceStore,
    citations: &[String],
) -> Option<(String, String)> {
    for citation in citations {
        let Some(source) = store.all().iter().find(|entry| entry.id == *citation) else {
            continue;
        };
        if let Some(reason) = weak_source_reason(source) {
            return Some((source.id.clone(), reason));
        }
    }
    None
}

fn weak_source_reason(entry: &Entry) -> Option<String> {
    let is_input_source = entry.entry_type == EntryType::CorpusChunk
        || entry
            .meta
            .get("kind")
            .and_then(Value::as_str)
            .is_some_and(|kind| matches!(kind, "input" | "private"));
    if !is_input_source {
        return None;
    }

    if entry
        .meta
        .get("title")
        .and_then(Value::as_str)
        .is_some_and(|title| title.to_ascii_lowercase().contains("redirecting"))
    {
        return Some("redirect_page".to_string());
    }

    let head = entry.text.chars().take(1_000).collect::<String>();
    let head_lower = head.to_ascii_lowercase();
    if head_lower.contains("# redirecting")
        || head_lower.contains("redirecting...")
        || head_lower.contains("<title>redirecting")
    {
        return Some("redirect_page".to_string());
    }

    if entry
        .meta
        .get("bytes")
        .and_then(Value::as_u64)
        .is_some_and(|bytes| bytes < 1_200)
    {
        return Some("source_too_short".to_string());
    }
    if entry.text.chars().count() < 800 {
        return Some("source_too_short".to_string());
    }

    None
}

fn is_feedback_entry_like(entry: &NewEntry, config: &FlowConfig) -> bool {
    let feedback = &config.feedback_entries;
    if !feedback.enabled {
        return false;
    }
    if !feedback.accepted_types.is_empty() && !feedback.accepted_types.contains(&entry.entry_type) {
        return false;
    }
    let has_target = entry
        .meta
        .get("target")
        .and_then(Value::as_str)
        .is_some_and(|target| !target.trim().is_empty());
    let has_kind = entry
        .meta
        .get("kind")
        .and_then(Value::as_str)
        .is_some_and(|kind| kind == feedback.kind);
    has_target || has_kind
}

fn normalize_feedback_entry_meta(entry: &mut NewEntry, config: &FlowConfig) {
    let feedback = &config.feedback_entries;
    if !feedback.enabled {
        return;
    }
    if !feedback.accepted_types.is_empty() && !feedback.accepted_types.contains(&entry.entry_type) {
        return;
    }

    let has_target = entry
        .meta
        .get("target")
        .and_then(Value::as_str)
        .is_some_and(|target| !target.trim().is_empty());
    let has_kind = entry
        .meta
        .get("kind")
        .and_then(Value::as_str)
        .is_some_and(|kind| kind == feedback.kind);

    if has_target && !has_kind {
        entry
            .meta
            .insert("kind".to_string(), json!(feedback.kind.clone()));
    }
    if has_target || has_kind {
        entry
            .meta
            .entry(feedback.status_field.clone())
            .or_insert_with(|| json!("proposed"));
    }
}

/// Run a stage's external command and fold its result into one entry. The
/// command runs deterministically (no LLM): selected entries are materialized to
/// a temp file whose path replaces `{input}` in the args; stdout (or stderr when
/// stdout is empty) becomes the entry text, the exit code lands in meta, and the
/// selected entries are cited so the probe stays inside the retract closure.
async fn run_stage_command(
    scenario: &Scenario,
    config: &FlowConfig,
    stage: &StageConfig,
    command: &StageCommandConfig,
    budget_step: usize,
    selected: &[Entry],
    scaling: &ActorScalingDecision,
) -> Result<Vec<NewEntry>> {
    let needs_input = command.args.iter().any(|arg| arg.contains("{input}"));
    let input_path = if needs_input {
        let path = std::env::temp_dir().join(format!(
            "tracefield-cmd-{}-{}.txt",
            std::process::id(),
            stage.id
        ));
        let content = selected
            .iter()
            .map(|entry| entry.text.as_str())
            .collect::<Vec<_>>()
            .join("\n\n");
        fs::write(&path, content)
            .with_context(|| format!("failed to write command input {}", path.display()))?;
        Some(path)
    } else {
        None
    };
    let input_arg = input_path
        .as_ref()
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_default();
    let args = command
        .args
        .iter()
        .map(|arg| arg.replace("{input}", &input_arg))
        .collect::<Vec<_>>();

    let cwd = match &command.cwd {
        Some(cwd) => scenario.dir.join(cwd),
        None => scenario.dir.clone(),
    };
    let timeout = Duration::from_secs(command.timeout_seconds.unwrap_or(600));

    let spawned = tokio::process::Command::new(&command.program)
        .args(&args)
        .current_dir(&cwd)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to spawn command {}", command.program));

    let output = match spawned {
        Ok(child) => tokio::time::timeout(timeout, child.wait_with_output())
            .await
            .with_context(|| format!("command {} timed out", command.program))?
            .with_context(|| format!("command {} failed", command.program))?,
        Err(error) => {
            if let Some(path) = &input_path {
                let _ = fs::remove_file(path);
            }
            return Err(error);
        }
    };
    if let Some(path) = &input_path {
        let _ = fs::remove_file(path);
    }

    let cap = |text: &str, limit: usize| -> String {
        if text.chars().count() > limit {
            text.chars().take(limit).collect::<String>() + "…"
        } else {
            text.to_string()
        }
    };
    let exit_code = output.status.code();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let command_line = std::iter::once(command.program.clone())
        .chain(args.iter().cloned())
        .collect::<Vec<_>>()
        .join(" ");
    let exit_label = exit_code
        .map(|code| code.to_string())
        .unwrap_or_else(|| "signal".to_string());
    let text = if stdout.is_empty() {
        format!("command exited {exit_label}\n{}", cap(&stderr, 4000))
    } else {
        cap(&stdout, 8000)
    };

    let mut meta = Map::new();
    add_flow_meta(
        &mut meta,
        config,
        stage,
        stage.organ.as_deref().unwrap_or("command"),
        None,
        budget_step,
        1,
        scaling,
    );
    meta.insert("kind".to_string(), json!("command"));
    meta.insert("command".to_string(), json!(command_line));
    meta.insert("exit_code".to_string(), json!(exit_code));
    if !stderr.is_empty() {
        meta.insert("stderr".to_string(), json!(cap(&stderr, 4000)));
    }

    let entry_type = stage
        .outputs
        .first()
        .cloned()
        .unwrap_or(EntryType::Observation);
    let citations = selected
        .iter()
        .map(|entry| entry.id.clone())
        .collect::<Vec<_>>();
    let mut entry = NewEntry::new(entry_type, "flow-command", text).with_citations(citations);
    entry.meta = meta;
    Ok(vec![entry])
}

fn deterministic_cluster_entries(
    config: &FlowConfig,
    stage: &StageConfig,
    clustering: &StageClusteringConfig,
    budget_step: usize,
    selected: &[Entry],
    scaling: &ActorScalingDecision,
) -> Vec<NewEntry> {
    if selected.is_empty() {
        return Vec::new();
    }

    cluster_selected_entries(selected, clustering)
        .into_iter()
        .enumerate()
        .map(|(index, (key, members))| {
            let label = source_cluster_label(index, &key);
            let mut meta = Map::new();
            add_flow_meta(
                &mut meta,
                config,
                stage,
                stage.organ.as_deref().unwrap_or("deterministic"),
                None,
                budget_step,
                index + 1,
                scaling,
            );
            let paths = unique_member_meta(&members, "path", 12);
            meta.insert("source_cluster".to_string(), json!(label.clone()));
            meta.insert("cluster_key".to_string(), json!(key.clone()));
            meta.insert("cluster_size".to_string(), json!(members.len()));
            meta.insert("cluster_paths".to_string(), json!(paths));
            meta.insert(
                "clustering".to_string(),
                json!({
                    "by": &clustering.by,
                    "min_cluster_size": clustering.min_cluster_size,
                    "max_clusters": clustering.max_clusters
                }),
            );

            NewEntry {
                entry_type: stage
                    .outputs
                    .first()
                    .cloned()
                    .unwrap_or(EntryType::Synthesis),
                status: Default::default(),
                author: Some("flow-cluster".to_string()),
                text: render_cluster_summary(&label, &key, &members),
                citations: members.iter().map(|entry| entry.id.clone()).collect(),
                meta,
                embedding: Vec::new(),
            }
        })
        .collect()
}

fn cluster_selected_entries(
    selected: &[Entry],
    clustering: &StageClusteringConfig,
) -> Vec<(String, Vec<Entry>)> {
    let mut grouped = BTreeMap::<String, Vec<Entry>>::new();
    for entry in selected {
        grouped
            .entry(configured_cluster_key_for_entry(entry, clustering))
            .or_default()
            .push(entry.clone());
    }

    if let Some(min_size) = clustering.min_cluster_size.filter(|min_size| *min_size > 1) {
        let mut regrouped = BTreeMap::<String, Vec<Entry>>::new();
        let mut small = Vec::new();
        for (key, members) in grouped {
            if members.len() < min_size {
                small.extend(members);
            } else {
                regrouped.insert(key, members);
            }
        }
        if !small.is_empty() {
            regrouped.insert("small_sources".to_string(), small);
        }
        grouped = regrouped;
    }

    let mut groups = grouped.into_iter().collect::<Vec<_>>();
    if let Some(max_clusters) = clustering.max_clusters
        && groups.len() > max_clusters
    {
        let keep_count = max_clusters.saturating_sub(1);
        let overflow = groups.split_off(keep_count);
        let mut overflow_members = Vec::new();
        for (_, members) in overflow {
            overflow_members.extend(members);
        }
        groups.push(("other_sources".to_string(), overflow_members));
    }

    groups
}

fn render_cluster_summary(label: &str, key: &str, members: &[Entry]) -> String {
    let paths = unique_member_meta(members, "path", 6);
    let source_list = if paths.is_empty() {
        "sources without path metadata".to_string()
    } else {
        paths.join(", ")
    };
    let excerpts = members
        .iter()
        .take(3)
        .map(|entry| first_chars(entry.text.trim(), 120))
        .collect::<Vec<_>>()
        .join(" / ");
    format!(
        "{label}: grouped {} source entries by {key}. Sources: {source_list}. Signals: {excerpts}",
        members.len()
    )
}

fn actor_selected_entries(
    stage: &StageConfig,
    selected: &[Entry],
    actor_index: usize,
    actor_count: usize,
) -> Vec<Entry> {
    if selected.is_empty() || actor_count == 0 {
        return selected.to_vec();
    }

    match stage.actors.mode.as_str() {
        "per_input" => shard_entries_by_index(selected, actor_index, actor_count),
        "per_source" => {
            shard_entries_by_key(selected, actor_index, actor_count, source_key_for_entry)
        }
        "per_cluster" => {
            shard_entries_by_key(selected, actor_index, actor_count, cluster_key_for_entry)
        }
        _ => selected.to_vec(),
    }
}

fn shard_entries_by_index(
    selected: &[Entry],
    actor_index: usize,
    actor_count: usize,
) -> Vec<Entry> {
    let mut assigned = selected
        .iter()
        .enumerate()
        .filter(|(index, _)| index % actor_count == actor_index)
        .map(|(_, entry)| entry.clone())
        .collect::<Vec<_>>();

    if assigned.is_empty()
        && let Some(entry) = selected.get(actor_index % selected.len())
    {
        assigned.push(entry.clone());
    }

    assigned
}

fn shard_entries_by_key(
    selected: &[Entry],
    actor_index: usize,
    actor_count: usize,
    key_for_entry: impl Fn(&Entry) -> String,
) -> Vec<Entry> {
    let mut groups = BTreeMap::<String, Vec<Entry>>::new();
    for entry in selected {
        groups
            .entry(key_for_entry(entry))
            .or_default()
            .push(entry.clone());
    }

    let keys = groups.keys().cloned().collect::<Vec<_>>();
    let mut assigned = Vec::new();
    for (index, key) in keys.iter().enumerate() {
        if index % actor_count == actor_index
            && let Some(entries) = groups.get(key)
        {
            assigned.extend(entries.clone());
        }
    }

    if assigned.is_empty()
        && let Some(key) = keys.get(actor_index % keys.len())
        && let Some(entries) = groups.get(key)
    {
        assigned.extend(entries.clone());
    }

    assigned
}

fn distinct_key_count(selected: &[Entry], key_for_entry: impl Fn(&Entry) -> String) -> usize {
    selected
        .iter()
        .map(key_for_entry)
        .collect::<BTreeSet<_>>()
        .len()
}

fn configured_cluster_key_for_entry(entry: &Entry, clustering: &StageClusteringConfig) -> String {
    for dimension in &clustering.by {
        if let Some(value) = dimension_key_for_entry(entry, dimension) {
            return value;
        }
    }
    cluster_key_for_entry(entry)
}

fn dimension_key_for_entry(entry: &Entry, dimension: &str) -> Option<String> {
    match dimension {
        "source_cluster" => entry_meta_string(entry, "source_cluster"),
        "cluster_key" => entry_meta_string(entry, "cluster_key"),
        "source_id" => entry_meta_string(entry, "source_id"),
        "source_url" | "url" => entry_meta_string(entry, "source_url"),
        "path" => entry_meta_string(entry, "path"),
        "path_parent" => entry_path_parent(entry),
        "kind" => entry_meta_string(entry, "kind"),
        "stage" => entry_meta_string(entry, "stage"),
        "author" => Some(entry.author.clone()),
        "type" => Some(entry_type_name(&entry.entry_type)),
        _ => None,
    }
}

fn source_key_for_entry(entry: &Entry) -> String {
    entry_meta_string(entry, "source_id")
        .or_else(|| entry_meta_string(entry, "source_url"))
        .or_else(|| entry_meta_string(entry, "path"))
        .unwrap_or_else(|| format!("{}:{}", entry.author, entry.id))
}

fn cluster_key_for_entry(entry: &Entry) -> String {
    entry_meta_string(entry, "source_cluster")
        .or_else(|| entry_meta_string(entry, "cluster_key"))
        .or_else(|| entry_path_parent(entry))
        .or_else(|| entry_meta_string(entry, "path"))
        .or_else(|| entry_meta_string(entry, "stage"))
        .unwrap_or_else(|| entry.author.clone())
}

fn entry_meta_string(entry: &Entry, key: &str) -> Option<String> {
    entry
        .meta
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn entry_path_parent(entry: &Entry) -> Option<String> {
    let path = entry_meta_string(entry, "path")?;
    let path = path.strip_prefix("inputs/").unwrap_or(&path);
    let parts = path
        .split('/')
        .filter(|part| !part.trim().is_empty())
        .collect::<Vec<_>>();
    if parts.len() > 1 {
        Some(parts[0].to_string())
    } else {
        None
    }
}

fn unique_member_meta(members: &[Entry], key: &str, limit: usize) -> Vec<String> {
    let mut seen = BTreeSet::new();
    members
        .iter()
        .filter_map(|entry| entry_meta_string(entry, key))
        .filter(|value| seen.insert(value.clone()))
        .take(limit)
        .collect()
}

fn source_cluster_label(index: usize, key: &str) -> String {
    format!(
        "CLUSTER:{:02}-{}",
        index + 1,
        sanitized_cluster_fragment(key)
    )
}

fn sanitized_cluster_fragment(value: &str) -> String {
    let mut output = String::new();
    let mut last_was_sep = false;
    for ch in value.chars() {
        if ch.is_ascii_alphanumeric() {
            output.push(ch.to_ascii_uppercase());
            last_was_sep = false;
        } else if !last_was_sep && !output.is_empty() {
            output.push('_');
            last_was_sep = true;
        }
        if output.len() >= 48 {
            break;
        }
    }
    let output = output.trim_matches('_').to_string();
    if output.is_empty() {
        "UNCLUSTERED".to_string()
    } else {
        output
    }
}

fn entry_type_name(entry_type: &EntryType) -> String {
    format!("{entry_type:?}").to_ascii_lowercase()
}

fn actor_role_for_index(stage: &StageConfig, actor_index: usize) -> Option<&str> {
    if stage.actors.roles.is_empty() {
        return None;
    }
    let index = actor_index.saturating_sub(1) % stage.actors.roles.len();
    stage.actors.roles.get(index).map(String::as_str)
}

/// Resolve which agent drives an actor. A stage role naming an agent id binds
/// that agent so its lens and role label come from the same source.
fn actor_for_index<'a>(
    scenario: &'a Scenario,
    stage: &StageConfig,
    actor_index: usize,
) -> Option<&'a AgentSpec> {
    let roles = &stage.actors.roles;
    if !roles.is_empty() {
        let role = &roles[actor_index % roles.len()];
        if let Some(agent) = scenario.agents.iter().find(|agent| &agent.id == role) {
            return Some(agent);
        }
    }
    scenario.agents.get(actor_index % scenario.agents.len())
}

/// Role label for an actor: the declared stage role, otherwise the bound
/// agent's domain. `actor_index` is 1-based to match `run_stage_actor`.
fn resolve_actor_role(
    stage: &StageConfig,
    actor_index: usize,
    actor: Option<&AgentSpec>,
) -> String {
    actor_role_for_index(stage, actor_index)
        .map(ToOwned::to_owned)
        .or_else(|| actor.and_then(|agent| agent.domain.clone()))
        .unwrap_or_else(|| "general".to_string())
}

fn first_chars(value: &str, limit: usize) -> String {
    if limit == 0 {
        return String::new();
    }
    let mut output = value.chars().take(limit).collect::<Vec<_>>();
    if value.chars().nth(limit).is_some() {
        if output.len() > 3 {
            output.truncate(output.len() - 3);
        }
        output.extend(['.', '.', '.']);
    }
    output.into_iter().collect()
}

fn decide_actor_count(
    stage: &StageConfig,
    config: &FlowConfig,
    selected: &[Entry],
    agent_count: usize,
) -> ActorScalingDecision {
    let input_count = selected.len();
    let source_count = distinct_key_count(selected, source_key_for_entry).max(input_count.min(1));
    let cluster_count = distinct_key_count(selected, cluster_key_for_entry).max(input_count.min(1));
    let open_questions = unresolved_question_count(selected.iter());
    let budget = stage.budget.or(config.budget).unwrap_or(0);
    let mut signals = BTreeMap::new();
    signals.insert("input_count".to_string(), input_count);
    signals.insert("source_count".to_string(), source_count);
    signals.insert("cluster_count".to_string(), cluster_count);
    signals.insert("budget".to_string(), budget);
    signals.insert("open_questions".to_string(), open_questions);

    let mode = stage.actors.mode.clone();
    let mut chosen = match mode.as_str() {
        "none" => 0,
        "fixed" => stage.actors.count.unwrap_or(1),
        "per_input" => input_count.max(1),
        "per_source" => source_count.max(1),
        "per_cluster" => cluster_count.max(1),
        "per_agent" => agent_count.max(1),
        "auto" => {
            let min = stage.actors.min.unwrap_or(1);
            let extra_from_inputs = input_count / 5;
            let extra_from_questions = open_questions / 3;
            let extra_from_budget = budget / 100;
            min + extra_from_inputs + extra_from_questions + extra_from_budget
        }
        _ => stage.actors.count.or(stage.actors.min).unwrap_or(1),
    };

    if let Some(min) = stage.actors.min
        && mode != "none"
    {
        chosen = chosen.max(min);
    }
    if let Some(max) = stage.actors.max {
        chosen = chosen.min(max);
    }
    if let Some(max_total) = config.actor_scaling.max_total_actors {
        chosen = chosen.min(max_total);
    }

    ActorScalingDecision {
        mode,
        chosen_count: chosen,
        signals,
    }
}

#[allow(clippy::too_many_arguments)]
async fn run_stage_actor(
    scenario: &Scenario,
    config: &FlowConfig,
    stage: &StageConfig,
    organ: Option<&OrganConfig>,
    actor: Option<&AgentSpec>,
    actor_index: usize,
    budget_step: usize,
    selected: &[Entry],
    scaling: &ActorScalingDecision,
    seeded: &SeededFlow,
    work_item: &FlowWorkItem,
) -> Result<Vec<NewEntry>> {
    let organ_id = stage.organ.as_deref().unwrap_or("mock");
    let adapter = Adapter::parse(organ.map(|organ| organ.adapter.as_str()).unwrap_or("mock"))?;
    let tool_mode = matches!(adapter, Adapter::Ollama | Adapter::OpenRouter);
    let llm_options = LlmOptions {
        adapter,
        model: organ.and_then(|organ| organ.model.clone()),
        cli_command: organ.and_then(|organ| organ.command.clone()),
        web_search: organ.map(|organ| organ.web_search).unwrap_or(false),
        max_tokens: organ
            .and_then(|organ| organ.max_tokens)
            .unwrap_or_else(|| LlmOptions::default().max_tokens),
        timeout: organ
            .and_then(|organ| organ.timeout_seconds)
            .map(Duration::from_secs)
            .unwrap_or_else(|| LlmOptions::default().timeout),
        ..LlmOptions::default()
    };
    let actor_id = actor
        .map(|actor| actor.id.clone())
        .unwrap_or_else(|| format!("{}-{}", stage.id, actor_index));
    let refs = actor_skill_refs(scenario, actor, seeded);
    let messages = stage_messages(
        scenario,
        config,
        stage,
        actor,
        &actor_id,
        actor_index,
        selected,
        scaling,
        &refs,
        tool_mode,
        work_item,
    );

    let citations = refs
        .iter()
        .map(|skill| skill.entry_id.clone())
        .collect::<Vec<_>>();
    let mut provenance = Vec::new();
    let content = if matches!(llm_options.adapter, Adapter::CodexAppServer) {
        let (text, prov) = crate::codex_app_server::run(
            &scenario.dir,
            &actor_id,
            &citations,
            &messages,
            &llm_options,
        )
        .await
        .with_context(|| {
            format!(
                "codex app-server failed for stage {} actor {actor_id}",
                stage.id
            )
        })?;
        provenance = prov;
        text
    } else if tool_mode && !refs.is_empty() {
        let allowed = actor.map(|actor| actor.skills.clone()).unwrap_or_default();
        let (text, prov) = skill_tools::run_skill_tool_loop(
            scenario,
            &actor_id,
            &allowed,
            &citations,
            &messages,
            &llm_options,
        )
        .await
        .with_context(|| {
            format!(
                "skill tool loop failed for stage {} actor {actor_id}",
                stage.id
            )
        })?;
        provenance = prov;
        text
    } else {
        llm::complete(&messages, &llm_options)
            .await
            .with_context(|| {
                format!("LLM adapter failed for stage {} actor {actor_id}", stage.id)
            })?
    };

    let mut entries = parse_stage_entries(
        &content,
        config,
        stage,
        organ_id,
        organ,
        &actor_id,
        budget_step,
        actor_index,
        selected,
        scaling,
    );
    entries.append(&mut provenance);
    Ok(entries)
}

fn actor_skill_refs(
    scenario: &Scenario,
    actor: Option<&AgentSpec>,
    seeded: &SeededFlow,
) -> Vec<SkillRef> {
    let Some(actor) = actor else {
        return Vec::new();
    };
    actor
        .skills
        .iter()
        .filter_map(|skill_id| {
            let entry_id = seeded.skill_entry_ids.get(skill_id)?;
            let skill = scenario.skills.get(skill_id)?;
            Some(SkillRef {
                id: skill.id.clone(),
                entry_id: entry_id.clone(),
                name: skill.name.clone(),
                description: skill.description.clone(),
            })
        })
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn stage_messages(
    scenario: &Scenario,
    config: &FlowConfig,
    stage: &StageConfig,
    actor: Option<&AgentSpec>,
    actor_id: &str,
    actor_index: usize,
    selected: &[Entry],
    scaling: &ActorScalingDecision,
    skill_refs: &[SkillRef],
    tool_mode: bool,
    work_item: &FlowWorkItem,
) -> Vec<Message> {
    let context = render_stage_context(stage, selected);
    let stage_outputs = if stage.outputs.is_empty() {
        "claim|question|observation|decision|synthesis|audit".to_string()
    } else {
        stage
            .outputs
            .iter()
            .map(|entry_type| format!("{entry_type:?}").to_ascii_lowercase())
            .collect::<Vec<_>>()
            .join("|")
    };
    let private_doc = actor
        .and_then(|actor| scenario.agent_private_doc(actor))
        .unwrap_or("");
    let skill_ids = skill_refs
        .iter()
        .map(|skill| skill.entry_id.clone())
        .collect::<Vec<_>>();
    let skills_block = if tool_mode {
        skill_tools::skill_l1_block(skill_refs)
    } else {
        "(injected as procedure citations)".to_string()
    };
    let stage_roles = if stage.actors.roles.is_empty() {
        "general".to_string()
    } else {
        stage.actors.roles.join(", ")
    };
    let actor_role = resolve_actor_role(stage, actor_index, actor);
    let feedback_schema = feedback_schema_prompt(config);
    let source_grounding_contract = source_grounding_contract_prompt(stage);
    let artifact_contract = artifact_contract_prompt(stage);
    let entry_budget_contract = entry_budget_contract_prompt(stage);
    let process_contract = process_management_contract_prompt(config, stage, work_item);
    let skill_contract = if tool_mode && !skill_refs.is_empty() {
        " Call read_skill to load a skill's instructions and references, and run_skill_script to execute its bundled scripts, before you produce entries. The skills available to you are listed under AVAILABLE_SKILLS."
    } else {
        ""
    };

    vec![
        Message::system(format!(
            "You are a Tracefield Field Runner actor. Honor ACTOR_ROLE and STAGE_ROLES. Return strict JSON only, with no markdown fences or prose outside JSON. The first character must be {{ and the final character must be }}. Required shape: {{\"entries\":[{{\"type\":\"{stage_outputs}\",\"text\":\"...\",\"citations\":[\"e1\"],\"meta\":{{}}}}]}}. {entry_budget_contract} Normal entries must use STAGE_OUTPUT_TYPES. Tracefield feedback entries may use the FEEDBACK_ENTRY_TYPES described below. Use only known citation ids when possible. When resolving an open question, cite the question id and the evidence ids, and include meta {{\"status\":\"resolved\",\"resolves_question\":\"<question id>\"}}.{skill_contract} {source_grounding_contract} {feedback_schema} {artifact_contract} {process_contract}"
        )),
        Message::user(format!(
            "TRACEFIELD_FLOW_STAGE\nFLOW: {}\nPOLICY: {}\nSTAGE: {}\nSTAGE_ROLES: {}\nSTAGE_OUTPUT_TYPES: {}\nACTOR: {}\nACTOR_INDEX: {}\nACTOR_ROLE: {}\nDOMAIN: {}\nDESC: {}\nTASK:\n{}\nPRIVATE:\n{}\nSKILL_CITATIONS: {}\nAVAILABLE_SKILLS:\n{}\nACTOR_SCALING: mode={} chosen_count={} signals={:?}\nWORK_ITEM_CYCLE: {}\nWORK_ITEM_REASON: {}\nFEEDBACK_REQUEST_IDS: {}\nSELECTED_ENTRY_COUNT: {}\nSOURCE_GROUNDING_CONTRACT:\n{}\nTRACEFIELD_FEEDBACK_SCHEMA:\n{}\nARTIFACT_CONTRACT:\n{}\nPROCESS_MANAGEMENT_CONTRACT:\n{}\nCONTEXT:\n{}",
            config.profile,
            config.policy,
            stage.id,
            stage_roles,
            stage_outputs,
            actor_id,
            actor_index,
            actor_role,
            actor
                .and_then(|actor| actor.domain.as_deref())
                .unwrap_or("general"),
            actor.and_then(|actor| actor.desc.as_deref()).unwrap_or(""),
            scenario.task,
            private_doc,
            skill_ids.join(", "),
            skills_block,
            scaling.mode,
            scaling.chosen_count,
            scaling.signals,
            work_item.cycle,
            work_item.reason,
            work_item.feedback_request_ids.join(", "),
            selected.len(),
            source_grounding_contract,
            feedback_schema,
            artifact_contract,
            process_contract,
            context
        )),
    ]
}

fn entry_budget_contract_prompt(stage: &StageConfig) -> &'static str {
    if stage.artifact.is_some() {
        "Emit at most 4 artifact-ready entries, and keep each entry text under 1200 characters."
    } else {
        "Emit at most 3 concise entries, and keep each entry text under 500 characters."
    }
}

fn artifact_contract_prompt(stage: &StageConfig) -> String {
    let Some(artifact) = &stage.artifact else {
        return String::new();
    };
    let format = artifact.format.as_deref().unwrap_or("markdown");
    match format {
        "slides_markdown" => "ARTIFACT_CONTRACT: This stage produces slide-ready content. Emit concise Marp-compatible slide fragments in entry.text. Each entry should have a slide title, 3-5 bullets, optional speaker notes, and citations to audited findings. Include meta.artifact_section with a short slide title.".to_string(),
        _ => "ARTIFACT_CONTRACT: This stage produces report-ready content. Emit coherent report sections in entry.text with clear findings, caveats, and implementation feedback. Cite audited findings and source-backed observations. Include meta.artifact_section with a short section title.".to_string(),
    }
}

fn process_management_contract_prompt(
    config: &FlowConfig,
    stage: &StageConfig,
    work_item: &FlowWorkItem,
) -> String {
    if !config.process.enabled || !is_process_manager_stage(stage) {
        return String::new();
    }

    format!(
        "PROCESS_MANAGEMENT_CONTRACT: You are the top-level process manager, not a data extractor. Emit process decisions only. For process_plan, define the investigation plan, stage responsibilities, quality gates, and stop conditions. For process_artifact_gate, decide whether artifact stages may proceed, should wait for feedback, or require recollection. If unresolved open_questions is 0 and cited evidence is sufficient for the artifact scope, prefer action=publish and publish_verdict=allowed. If artifact stages must not proceed, emit action=block|recollect|rerun or publish_verdict=blocked. require_manifest means artifact export must write a sidecar manifest after artifact stages complete; do not block artifact stages merely because the manifest does not exist before export. Include meta {{\"kind\":\"process_decision\",\"process_stage\":\"{}\",\"action\":\"<plan|gate|publish|block|recollect|rerun>\",\"priority\":\"<low|medium|high>\",\"publish_verdict\":\"<allowed|blocked|conditional>\",\"stop_verdict\":\"<continue|stop|needs_followup>\"}} when applicable. Process mode: {}. Artifact after feedback: {}. Artifact stages: {}. Gates: enforce_artifact_gate={}, allow_conditional_artifacts={}, require_citations={}, require_evidence_quotes={}, block_publish_on_open_questions={}, block_publish_on_quality_warnings={}, require_manifest={}. Stop: max_cycles={:?}, max_feedback_cycles={:?}, stop_when={}. Work item reason: {}.",
        stage.id,
        config.process.mode,
        config.process.artifact_after_feedback,
        config.process.artifact_stages.join(", "),
        config.process.gates.enforce_artifact_gate,
        config.process.gates.allow_conditional_artifacts,
        config.process.gates.require_citations,
        config.process.gates.require_evidence_quotes,
        config.process.gates.block_publish_on_open_questions,
        config.process.gates.block_publish_on_quality_warnings,
        config.process.gates.require_manifest,
        config.process.stop.max_cycles,
        config.process.stop.max_feedback_cycles,
        config.process.stop.stop_when.join(", "),
        work_item.reason
    )
}

fn is_process_manager_stage(stage: &StageConfig) -> bool {
    stage.id.starts_with("process_")
        || stage
            .actors
            .roles
            .iter()
            .any(|role| role == "process_manager")
}

fn source_grounding_contract_prompt(stage: &StageConfig) -> String {
    if !is_source_grounded_stage(stage) {
        return "Ground claims in cited context and separate evidence from recommendations. In later long-run cycles, compare against earlier stage outputs, close open questions, and emit new question/audit entries when evidence coverage is weak."
            .to_string();
    }

    "SOURCE_GROUNDING_CONTRACT: In source/data stages, extract only facts directly supported by selected CONTEXT entries. Do not use outside knowledge and do not turn source content into Tracefield design recommendations. For every non-question entry, citations must contain the exact CONTEXT entry id that supports the claim, and meta.evidence_quote must be an exact contiguous 8-30 word substring copied from that cited CONTEXT entry. The claim text may only paraphrase what meta.evidence_quote says. Do not stitch a heading and a later paragraph into one quote. Do not use table-of-contents, navigation, isolated heading lists, or ellipsized text as meta.evidence_quote; choose a complete prose sentence or clause. Do not add facts that are merely plausible from the title or navigation. Include meta.claim_role as source_evidence, gap, or low_quality_source. If no exact quote supports the claim, emit type question with meta.action=\"recollect\" instead of observation/requirement. If the claim is grounded in a file you re-opened rather than in inline CONTEXT text, also set meta.source_path to that file's path relative to the scenario directory and meta.source_line to the line number, and copy meta.evidence_quote verbatim from that file. In later long-run cycles, focus on gaps from feedback request entries and avoid restating already extracted evidence unless it resolves a contradiction.".to_string()
}

fn feedback_schema_prompt(config: &FlowConfig) -> String {
    let feedback = &config.feedback_entries;
    if !feedback.enabled {
        return "Do not emit Tracefield self-feedback unless explicitly requested.".to_string();
    }

    let types = if feedback.accepted_types.is_empty() {
        "change|requirement|question|audit".to_string()
    } else {
        feedback
            .accepted_types
            .iter()
            .map(entry_type_name)
            .collect::<Vec<_>>()
            .join("|")
    };
    let targets = feedback
        .routes
        .iter()
        .filter_map(|route| route.target_prefix.as_deref())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>()
        .join(", ");

    format!(
        "FEEDBACK_ENTRY_TYPES: {types}. When you find a reusable improvement for Tracefield itself, emit a feedback entry with one of those types and meta {{\"kind\":\"{}\",\"target\":\"<target>\",\"action\":\"<add|change|remove|recollect|rerun|audit>\",\"priority\":\"<low|medium|high>\",\"status\":\"proposed\"}}. Target prefixes: {}.",
        feedback.kind,
        if targets.is_empty() {
            "any explicit target"
        } else {
            &targets
        }
    )
}

fn render_stage_context(stage: &StageConfig, selected: &[Entry]) -> String {
    let mut context = String::new();
    let stage_context = stage.context.as_ref();
    let per_entry_limit = stage_context
        .and_then(|context| context.chars_per_entry)
        .unwrap_or(MAX_CONTEXT_CHARS_PER_ENTRY);
    let total_limit = stage_context
        .and_then(|context| context.chars_total)
        .unwrap_or(MAX_CONTEXT_CHARS_TOTAL);
    let mode = stage_context
        .map(|context| context.mode.as_str())
        .unwrap_or("head");
    for entry in selected {
        let current_len = context.chars().count();
        if current_len >= total_limit {
            break;
        }

        let text = match mode {
            "source_excerpt" => render_source_excerpt(entry, stage_context, per_entry_limit),
            _ => first_chars(entry.text.trim(), per_entry_limit),
        };
        let rendered = render_context_entry(entry, &text);
        let remaining = total_limit.saturating_sub(current_len);
        if rendered.chars().count() > remaining {
            context.push_str(&first_chars(&rendered, remaining));
            break;
        }
        if !context.is_empty() {
            context.push('\n');
        }
        context.push_str(&rendered);
    }
    context
}

fn render_context_entry(entry: &Entry, text: &str) -> String {
    let mut metadata = Vec::new();
    for key in ["title", "source_url", "path", "bytes"] {
        if let Some(value) = entry.meta.get(key).and_then(value_to_compact_string) {
            metadata.push(format!("{key}={value}"));
        }
    }
    if metadata.is_empty() {
        format!(
            "{} [{} {:?}]: {}",
            entry.id, entry.author, entry.entry_type, text
        )
    } else {
        format!(
            "{} [{} {:?} meta:{}]: {}",
            entry.id,
            entry.author,
            entry.entry_type,
            metadata.join(","),
            text
        )
    }
}

fn value_to_compact_string(value: &Value) -> Option<String> {
    match value {
        Value::String(value) => {
            let value = value.trim();
            if value.is_empty() {
                None
            } else {
                Some(value.to_string())
            }
        }
        Value::Number(value) => Some(value.to_string()),
        Value::Bool(value) => Some(value.to_string()),
        _ => None,
    }
}

fn render_source_excerpt(
    entry: &Entry,
    context: Option<&StageContextConfig>,
    per_entry_limit: usize,
) -> String {
    let cleaned = clean_source_text(&entry.text);
    let keywords = context
        .map(|context| context.keywords.as_slice())
        .unwrap_or(&[]);
    let chunks = ranked_source_chunks(&cleaned, keywords);
    if chunks.is_empty() {
        return first_chars(cleaned.trim(), per_entry_limit);
    }

    let mut selected = chunks
        .iter()
        .take(8)
        .filter(|chunk| chunk.score > 0 || chunks.len() <= 2)
        .cloned()
        .collect::<Vec<_>>();
    if selected.is_empty() {
        selected.push(chunks[0].clone());
    }
    selected.sort_by_key(|chunk| chunk.index);

    let mut excerpt = String::new();
    for chunk in selected {
        if excerpt.chars().count() >= per_entry_limit {
            break;
        }
        if !excerpt.is_empty() {
            excerpt.push_str("\n...\n");
        }
        let remaining = per_entry_limit.saturating_sub(excerpt.chars().count());
        excerpt.push_str(&first_chars(chunk.text.trim(), remaining));
    }
    excerpt
}

#[derive(Debug, Clone)]
struct SourceChunk {
    index: usize,
    score: usize,
    text: String,
}

fn ranked_source_chunks(content: &str, keywords: &[String]) -> Vec<SourceChunk> {
    let chunks = source_chunks(content);
    let mut scored = chunks
        .into_iter()
        .enumerate()
        .map(|(index, text)| SourceChunk {
            index,
            score: score_source_chunk(&text, keywords),
            text,
        })
        .collect::<Vec<_>>();
    scored.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| left.index.cmp(&right.index))
    });
    scored
}

fn source_chunks(content: &str) -> Vec<String> {
    let mut chunks = Vec::new();
    let mut current = String::new();

    for line in content.lines().map(str::trim) {
        if is_boilerplate_source_line(line) {
            continue;
        }
        if line.is_empty() {
            push_source_chunk(&mut chunks, &mut current);
            continue;
        }
        if !current.is_empty() {
            current.push(' ');
        }
        current.push_str(line);
        if current.chars().count() >= 900 {
            push_source_chunk(&mut chunks, &mut current);
        }
    }
    push_source_chunk(&mut chunks, &mut current);
    chunks
}

fn push_source_chunk(chunks: &mut Vec<String>, current: &mut String) {
    let trimmed = current.trim();
    if trimmed.chars().count() >= 40 {
        chunks.push(trimmed.to_string());
    }
    current.clear();
}

fn is_boilerplate_source_line(line: &str) -> bool {
    if line.is_empty() {
        return false;
    }
    let lower = line.to_ascii_lowercase();
    if matches!(
        lower.as_str(),
        "skip to content"
            | "table of contents"
            | "copy page"
            | "back to top"
            | "was this page helpful?"
            | "yes no"
            | "english"
    ) {
        return true;
    }
    lower.starts_with("source:")
        || lower.starts_with("fetched:")
        || lower.starts_with("initializing search")
        || lower.starts_with("previous ")
        || lower.starts_with("next ")
}

fn score_source_chunk(text: &str, keywords: &[String]) -> usize {
    let lower = text.to_ascii_lowercase();
    let mut score = 0;
    for keyword in keywords {
        let keyword = keyword.trim().to_ascii_lowercase();
        if keyword.is_empty() {
            continue;
        }
        score += lower.matches(&keyword).count() * 3;
    }
    for keyword in [
        "agent",
        "workflow",
        "orchestrat",
        "handoff",
        "guardrail",
        "trace",
        "eval",
        "tool",
        "memory",
        "state",
        "protocol",
        "mcp",
        "a2a",
    ] {
        if lower.contains(keyword) {
            score += 1;
        }
    }
    if !source_quote_candidate_is_prose(text) {
        score = score.saturating_sub(4);
    }
    score
}

fn clean_source_text(content: &str) -> String {
    let trimmed = content.trim_start();
    if let Some(rest) = trimmed.strip_prefix("---")
        && let Some(after_open) = rest
            .strip_prefix("\r\n")
            .or_else(|| rest.strip_prefix('\n'))
        && let Some(end) = after_open.find("\n---")
    {
        let after_frontmatter = &after_open[end + "\n---".len()..];
        return after_frontmatter.trim().to_string();
    }
    trimmed.to_string()
}

struct StageEntryParseContext<'a> {
    config: &'a FlowConfig,
    stage: &'a StageConfig,
    organ_id: &'a str,
    organ: Option<&'a OrganConfig>,
    actor_id: &'a str,
    budget_step: usize,
    actor_index: usize,
    default_citations: &'a [String],
    scaling: &'a ActorScalingDecision,
}

const MAX_NESTED_MODEL_JSON_DEPTH: usize = 2;

#[allow(clippy::too_many_arguments)]
fn parse_stage_entries(
    content: &str,
    config: &FlowConfig,
    stage: &StageConfig,
    organ_id: &str,
    organ: Option<&OrganConfig>,
    actor_id: &str,
    budget_step: usize,
    actor_index: usize,
    selected: &[Entry],
    scaling: &ActorScalingDecision,
) -> Vec<NewEntry> {
    let default_citations = selected
        .iter()
        .take(5)
        .map(|entry| entry.id.clone())
        .collect::<Vec<_>>();
    let Some((mut raw_entries, parser_repaired)) = model_entry_values_from_text(content) else {
        return fallback_stage_entry(
            content,
            config,
            stage,
            organ_id,
            organ,
            actor_id,
            budget_step,
            actor_index,
            default_citations,
            scaling,
        );
    };
    if parser_repaired {
        mark_raw_entries_parser_repaired(&mut raw_entries, "jsonish_entries_salvaged");
    }

    let parse_context = StageEntryParseContext {
        config,
        stage,
        organ_id,
        organ,
        actor_id,
        budget_step,
        actor_index,
        default_citations: &default_citations,
        scaling,
    };
    let mut entries = Vec::new();
    for raw_entry in &raw_entries {
        append_parsed_stage_entry(raw_entry, &parse_context, &mut entries, None, None, None, 0);
    }

    if entries.is_empty() {
        fallback_stage_entry(
            content,
            config,
            stage,
            organ_id,
            organ,
            actor_id,
            budget_step,
            actor_index,
            default_citations,
            scaling,
        )
    } else {
        entries
    }
}

fn append_parsed_stage_entry(
    raw_entry: &Value,
    context: &StageEntryParseContext<'_>,
    entries: &mut Vec<NewEntry>,
    inherited_meta: Option<&Map<String, Value>>,
    inherited_citations: Option<&[String]>,
    inherited_type: Option<&str>,
    depth: usize,
) {
    let Some(text) = raw_entry.get("text").and_then(Value::as_str).map(str::trim) else {
        return;
    };
    if text.is_empty() {
        return;
    }

    let (entry_type, raw_type) = parsed_stage_entry_type(raw_entry, context.stage);
    let citations =
        parsed_stage_entry_citations(raw_entry, inherited_citations, context.default_citations);
    let mut meta = parsed_stage_entry_meta(raw_entry, inherited_meta);

    if depth < MAX_NESTED_MODEL_JSON_DEPTH
        && let Some((mut nested_entries, parser_repaired)) = model_entry_values_from_text(text)
    {
        if parser_repaired {
            mark_raw_entries_parser_repaired(&mut nested_entries, "jsonish_entries_salvaged");
        }
        let before = entries.len();
        for nested_entry in nested_entries {
            append_parsed_stage_entry(
                &nested_entry,
                context,
                entries,
                Some(&meta),
                Some(&citations),
                raw_type.as_deref(),
                depth + 1,
            );
        }
        if entries.len() > before {
            return;
        }
    }

    if depth > 0 {
        meta.insert("nested_json_text_flattened".to_string(), json!(true));
        meta.insert("nested_json_depth".to_string(), json!(depth));
        if let Some(inherited_type) = inherited_type {
            meta.insert("nested_json_parent_type".to_string(), json!(inherited_type));
        }
    }
    if let Some(raw_type) = raw_type.as_deref()
        && entry_type == EntryType::Belief
        && !raw_type.trim().eq_ignore_ascii_case("belief")
    {
        meta.insert("raw_entry_type".to_string(), json!(raw_type));
        meta.insert("unknown_entry_type".to_string(), json!(true));
    }

    add_flow_meta(
        &mut meta,
        context.config,
        context.stage,
        context.organ_id,
        context.organ,
        context.budget_step,
        context.actor_index,
        context.scaling,
    );
    entries.push(NewEntry {
        entry_type,
        status: Default::default(),
        author: Some(context.actor_id.to_string()),
        text: text.to_string(),
        citations,
        meta,
        embedding: Vec::new(),
    });
}

fn parsed_stage_entry_type(raw_entry: &Value, stage: &StageConfig) -> (EntryType, Option<String>) {
    let raw_type = raw_entry
        .get("type")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned);
    let entry_type = raw_type
        .as_deref()
        .map(EntryType::parse)
        .unwrap_or_else(|| stage.outputs.first().cloned().unwrap_or(EntryType::Claim));
    (entry_type, raw_type)
}

fn parsed_stage_entry_citations(
    raw_entry: &Value,
    inherited_citations: Option<&[String]>,
    default_citations: &[String],
) -> Vec<String> {
    raw_entry
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
        .or_else(|| {
            inherited_citations
                .filter(|citations| !citations.is_empty())
                .map(|citations| citations.to_vec())
        })
        .unwrap_or_else(|| default_citations.to_vec())
}

fn parsed_stage_entry_meta(
    raw_entry: &Value,
    inherited_meta: Option<&Map<String, Value>>,
) -> Map<String, Value> {
    let mut meta = inherited_meta.cloned().unwrap_or_else(Map::new);
    if let Some(raw_meta) = raw_entry.get("meta").and_then(Value::as_object) {
        for (key, value) in raw_meta {
            meta.insert(key.clone(), value.clone());
        }
    }
    meta
}

fn model_entry_values_from_text(content: &str) -> Option<(Vec<Value>, bool)> {
    parse_json_value_from_model_output(content)
        .and_then(|value| value.get("entries").and_then(Value::as_array).cloned())
        .filter(|entries| !entries.is_empty())
        .map(|entries| (entries, false))
        .or_else(|| extract_jsonish_entries_array(content).map(|entries| (entries, true)))
}

fn mark_raw_entries_parser_repaired(entries: &mut [Value], flag: &str) {
    for entry in entries {
        let Some(entry_object) = entry.as_object_mut() else {
            continue;
        };
        let meta = entry_object.entry("meta").or_insert_with(|| json!({}));
        if !meta.is_object() {
            *meta = json!({});
        }
        if let Some(meta_object) = meta.as_object_mut() {
            meta_object.insert(flag.to_string(), json!(true));
        }
    }
}

fn parse_json_value_from_model_output(content: &str) -> Option<Value> {
    let trimmed = content.trim();
    if trimmed.is_empty() {
        return None;
    }

    for candidate in [
        Some(trimmed.to_string()),
        extract_first_fenced_block(trimmed),
        extract_first_balanced_json_object(trimmed),
    ]
    .into_iter()
    .flatten()
    {
        if let Ok(value) = serde_json::from_str::<Value>(candidate.trim()) {
            return Some(value);
        }
    }

    None
}

fn extract_jsonish_entries_array(content: &str) -> Option<Vec<Value>> {
    let entries_pos = content.find("\"entries\"")?;
    let array_start = entries_pos + content[entries_pos..].find('[')? + 1;
    let mut index = array_start;
    let mut entries = Vec::new();

    while index < content.len() {
        let remainder = &content[index..];
        let trimmed = remainder
            .trim_start_matches(|ch: char| ch.is_whitespace() || matches!(ch, ',' | ']' | '}'));
        index += remainder.len() - trimmed.len();
        if !trimmed.starts_with('{') {
            break;
        }

        let Some(object_text) = extract_first_balanced_json_object(trimmed) else {
            break;
        };
        let Ok(value) = serde_json::from_str::<Value>(&object_text) else {
            break;
        };
        entries.push(value);
        index += object_text.len();
    }

    if entries.is_empty() {
        None
    } else {
        Some(entries)
    }
}

fn extract_first_fenced_block(content: &str) -> Option<String> {
    let start = content.find("```")?;
    let after_fence = &content[start + 3..];
    let after_lang = after_fence
        .strip_prefix("json")
        .or_else(|| after_fence.strip_prefix("JSON"))
        .unwrap_or(after_fence);
    let after_lang = after_lang.trim_start_matches(['\n', '\r', ' ', '\t']);
    let end = after_lang.find("```")?;
    Some(after_lang[..end].trim().to_string())
}

fn extract_first_balanced_json_object(content: &str) -> Option<String> {
    let start = content.find('{')?;
    let mut depth = 0usize;
    let mut in_string = false;
    let mut escaped = false;

    for (offset, ch) in content[start..].char_indices() {
        if in_string {
            if escaped {
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '"' {
                in_string = false;
            }
            continue;
        }

        match ch {
            '"' => in_string = true,
            '{' => depth += 1,
            '}' => {
                depth = depth.checked_sub(1)?;
                if depth == 0 {
                    let end = start + offset + ch.len_utf8();
                    return Some(content[start..end].to_string());
                }
            }
            _ => {}
        }
    }

    None
}

#[allow(clippy::too_many_arguments)]
fn fallback_stage_entry(
    content: &str,
    config: &FlowConfig,
    stage: &StageConfig,
    organ_id: &str,
    organ: Option<&OrganConfig>,
    actor_id: &str,
    budget_step: usize,
    actor_index: usize,
    citations: Vec<String>,
    scaling: &ActorScalingDecision,
) -> Vec<NewEntry> {
    let mut meta = Map::new();
    add_flow_meta(
        &mut meta,
        config,
        stage,
        organ_id,
        organ,
        budget_step,
        actor_index,
        scaling,
    );
    vec![NewEntry {
        entry_type: stage.outputs.first().cloned().unwrap_or(EntryType::Claim),
        status: Default::default(),
        author: Some(actor_id.to_string()),
        text: content.trim().to_string(),
        citations,
        meta,
        embedding: Vec::new(),
    }]
}

fn deterministic_stage_marker(
    config: &FlowConfig,
    stage: &StageConfig,
    budget_step: usize,
    scaling: &ActorScalingDecision,
) -> NewEntry {
    let mut meta = Map::new();
    add_flow_meta(
        &mut meta,
        config,
        stage,
        stage.organ.as_deref().unwrap_or("deterministic"),
        None,
        budget_step,
        0,
        scaling,
    );
    NewEntry {
        entry_type: stage
            .outputs
            .first()
            .cloned()
            .unwrap_or(EntryType::Synthesis),
        status: Default::default(),
        author: Some("flow".to_string()),
        text: format!("Stage {} completed without LLM actors.", stage.id),
        citations: Vec::new(),
        meta,
        embedding: Vec::new(),
    }
}

#[allow(clippy::too_many_arguments)]
fn add_flow_meta(
    meta: &mut Map<String, Value>,
    config: &FlowConfig,
    stage: &StageConfig,
    organ_id: &str,
    organ: Option<&OrganConfig>,
    budget_step: usize,
    actor_index: usize,
    scaling: &ActorScalingDecision,
) {
    meta.insert("flow".to_string(), json!(config.profile));
    meta.insert("policy".to_string(), json!(config.policy));
    meta.insert("stage".to_string(), json!(stage.id));
    meta.insert("organ".to_string(), json!(organ_id));
    if let Some(organ) = organ {
        meta.insert("adapter".to_string(), json!(organ.adapter));
        if let Some(model) = &organ.model {
            meta.insert("model".to_string(), json!(model));
        }
        if let Some(command) = &organ.command {
            meta.insert("command".to_string(), json!(command));
        }
        if let Some(max_tokens) = organ.max_tokens {
            meta.insert("max_tokens".to_string(), json!(max_tokens));
        }
        if let Some(timeout_seconds) = organ.timeout_seconds {
            meta.insert("timeout_seconds".to_string(), json!(timeout_seconds));
        }
    }
    meta.insert("budget_step".to_string(), json!(budget_step));
    meta.insert("actor_index".to_string(), json!(actor_index));
    if !stage.actors.roles.is_empty() {
        meta.insert("stage_roles".to_string(), json!(&stage.actors.roles));
        if let Some(role) = actor_role_for_index(stage, actor_index) {
            meta.insert("actor_role".to_string(), json!(role));
        }
    }
    meta.insert(
        "actor_scaling".to_string(),
        json!({
            "mode": scaling.mode,
            "chosen_count": scaling.chosen_count,
            "signals": scaling.signals
        }),
    );
    if let Some(artifact) = &stage.artifact {
        meta.insert(
            "artifact".to_string(),
            json!({
                "kind": artifact.kind,
                "format": artifact.format,
                "audience": artifact.audience,
                "require_citations": artifact.require_citations
            }),
        );
    }
}

fn export_artifact(
    scenario_dir: &Path,
    artifact: &ArtifactConfig,
    store: &ReferenceStore,
) -> Result<ArtifactExportResult> {
    let source_entries = store
        .all()
        .iter()
        .filter(|entry| entry.status == EntryStatus::Active)
        .filter(|entry| {
            entry.meta.get("stage").and_then(Value::as_str) == Some(artifact.from_stage.as_str())
        })
        .cloned()
        .collect::<Vec<_>>();
    let path = scenario_dir.join(&artifact.path);
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    let content = render_artifact_markdown(artifact, &source_entries);
    fs::write(&path, content).with_context(|| format!("failed to write {}", path.display()))?;
    let manifest_path = format!("{}.manifest.json", artifact.path);
    let manifest_abs_path = scenario_dir.join(&manifest_path);
    let manifest = artifact_manifest(artifact, &source_entries);
    serde_json::to_writer_pretty(
        fs::File::create(&manifest_abs_path)
            .with_context(|| format!("failed to create {}", manifest_abs_path.display()))?,
        &manifest,
    )
    .with_context(|| format!("failed to write {}", manifest_abs_path.display()))?;
    Ok(ArtifactExportResult {
        id: artifact.id.clone(),
        format: artifact.format.clone(),
        path: artifact.path.clone(),
        manifest_path,
        source_entry_ids: source_entries.into_iter().map(|entry| entry.id).collect(),
    })
}

fn artifact_manifest(artifact: &ArtifactConfig, entries: &[Entry]) -> Value {
    json!({
        "id": artifact.id,
        "format": artifact.format,
        "path": artifact.path,
        "from_stage": artifact.from_stage,
        "source_entry_ids": entries.iter().map(|entry| entry.id.clone()).collect::<Vec<_>>(),
        "retraction_model": {
            "mode": "citation_closure",
            "retracting_any_source_entry_invalidates_dependent_artifact_entries": true
        },
        "entries": entries.iter().map(|entry| {
            let citation_closure = artifact_entry_citation_closure(entry, entries);
            json!({
                "id": entry.id,
                "type": entry.entry_type,
                "author": entry.author,
                "citations": entry.citations,
                "citation_closure": citation_closure,
                "stage": entry.meta.get("stage").cloned().unwrap_or(Value::Null),
                "actor_role": entry.meta.get("actor_role").cloned().unwrap_or(Value::Null),
                "stage_roles": entry.meta.get("stage_roles").cloned().unwrap_or(Value::Null),
                "source_cluster": entry.meta.get("source_cluster").cloned().unwrap_or(Value::Null),
                "cluster_key": entry.meta.get("cluster_key").cloned().unwrap_or(Value::Null),
                "artifact": entry.meta.get("artifact").cloned().unwrap_or(Value::Null),
                "artifact_section": entry.meta.get("artifact_section").cloned().unwrap_or(Value::Null),
                "evidence_quote": entry.meta.get("evidence_quote").cloned().unwrap_or(Value::Null),
                "data_quality_warnings": entry.meta.get("data_quality_warnings").cloned().unwrap_or(Value::Null),
                "provenance": artifact_entry_provenance(entry),
                "trace_span": artifact_entry_trace_span(entry),
                "retraction": {
                    "status": entry.status,
                    "direct_source_entry_ids": entry.citations,
                    "dependent_source_entry_ids": citation_closure,
                    "impact": "invalidate_artifact_entry"
                },
                "rerun": {
                    "stage": artifact.from_stage,
                    "work_item_cycle": entry.meta.get("work_item_cycle").cloned().unwrap_or(Value::Null),
                    "work_item_reason": entry.meta.get("work_item_reason").cloned().unwrap_or(Value::Null)
                }
            })
        }).collect::<Vec<_>>()
    })
}

fn artifact_entry_citation_closure(entry: &Entry, artifact_entries: &[Entry]) -> Vec<String> {
    let mut closure = BTreeSet::new();
    let mut queue = entry.citations.clone();
    while let Some(id) = queue.pop() {
        if !closure.insert(id.clone()) {
            continue;
        }
        if let Some(next) = artifact_entries.iter().find(|candidate| candidate.id == id) {
            queue.extend(next.citations.clone());
        }
    }
    closure.into_iter().collect()
}

fn artifact_entry_provenance(entry: &Entry) -> Value {
    json!({
        "entry_id": entry.id,
        "author": entry.author,
        "stage": entry.meta.get("stage").cloned().unwrap_or(Value::Null),
        "source_stage": entry.meta.get("source_stage").cloned().unwrap_or(Value::Null),
        "actor_role": entry.meta.get("actor_role").cloned().unwrap_or(Value::Null),
        "organ": entry.meta.get("organ").cloned().unwrap_or(Value::Null),
        "adapter": entry.meta.get("adapter").cloned().unwrap_or(Value::Null),
        "model": entry.meta.get("model").cloned().unwrap_or(Value::Null),
        "command": entry.meta.get("command").cloned().unwrap_or(Value::Null)
    })
}

fn artifact_entry_trace_span(entry: &Entry) -> Value {
    json!({
        "trace_id": entry.meta.get("trace_id").cloned().unwrap_or(Value::Null),
        "span_id": entry.meta.get("span_id").cloned().unwrap_or(Value::Null),
        "parent_span_id": entry.meta.get("parent_span_id").cloned().unwrap_or(Value::Null),
        "stage": entry.meta.get("stage").cloned().unwrap_or(Value::Null),
        "actor_index": entry.meta.get("actor_index").cloned().unwrap_or(Value::Null),
        "budget_step": entry.meta.get("budget_step").cloned().unwrap_or(Value::Null)
    })
}

fn render_artifact_markdown(artifact: &ArtifactConfig, entries: &[Entry]) -> String {
    if artifact.format == "slides_markdown" {
        return render_slides_markdown_artifact(artifact, entries);
    }
    if artifact.format == "contested_map" {
        return render_contested_map_artifact(artifact, entries);
    }

    let mut output = String::new();
    output.push_str(&format!("# {}\n\n", artifact.id.replace('_', " ")));
    output.push_str(&format!("format: {}\n\n", artifact.format));
    if entries.is_empty() {
        output.push_str("(no source entries)\n");
        return output;
    }

    for entry in entries {
        output.push_str(&format!("## {} ({:?})\n\n", entry.id, entry.entry_type));
        output.push_str(entry.text.trim());
        output.push_str("\n\n");
        if !entry.citations.is_empty() {
            output.push_str(&format!("citations: {}\n\n", entry.citations.join(", ")));
        }
    }

    output
}

fn render_slides_markdown_artifact(artifact: &ArtifactConfig, entries: &[Entry]) -> String {
    let mut output = String::new();
    output.push_str("---\nmarp: true\npaginate: true\n---\n\n");
    output.push_str(&format!("# {}\n\n", artifact.id.replace('_', " ")));
    output.push_str(&format!("format: {}\n\n", artifact.format));
    if entries.is_empty() {
        output.push_str("(no source entries)\n");
        return output;
    }

    for entry in entries {
        output.push_str("---\n\n");
        output.push_str(entry.text.trim());
        output.push_str("\n\n");
        if !entry.citations.is_empty() {
            output.push_str(&format!(
                "<!-- citations: {} -->\n\n",
                entry.citations.join(", ")
            ));
        }
    }

    output
}

/// Render a stage's Active entries as a **contested map**: grouped by the matter
/// they concern (`meta.matter`, falling back to the existing cluster key so this
/// composes with deterministic clustering), every coexisting stance kept with its
/// author + verbatim evidence, and a matter flagged CONTESTED when two or more
/// parties hold a position on it. Grouping and the flag are mechanical (no LLM),
/// so a minority position is never smoothed away — the read path *surfaces* the
/// disagreement rather than resolving it (peer disagreement is left Active; only
/// validity refutations retract, upstream). This is the read shape that turns a
/// flat pile of stance entries into something a human can adjudicate.
fn render_contested_map_artifact(artifact: &ArtifactConfig, entries: &[Entry]) -> String {
    let mut output = String::new();
    output.push_str(&format!("# {}\n\n", artifact.id.replace('_', " ")));
    output.push_str(&format!("format: {}\n\n", artifact.format));
    if entries.is_empty() {
        output.push_str("(no source entries)\n");
        return output;
    }

    let mut groups: BTreeMap<String, Vec<&Entry>> = BTreeMap::new();
    for entry in entries {
        let key =
            entry_meta_string(entry, "matter").unwrap_or_else(|| cluster_key_for_entry(entry));
        groups.entry(key).or_default().push(entry);
    }

    for (matter, members) in &groups {
        let mut parties = members
            .iter()
            .map(|entry| entry.author.clone())
            .collect::<Vec<_>>();
        parties.sort();
        parties.dedup();

        output.push_str(&format!("## {matter}\n\n"));
        if parties.len() >= 2 {
            output.push_str(&format!(
                "⚠ CONTESTED — {} positions across {} parties ({})\n\n",
                members.len(),
                parties.len(),
                parties.join(", ")
            ));
        }
        for entry in members {
            output.push_str(&format!(
                "- **{}** ({}): {}\n",
                entry.author,
                entry.id,
                entry.text.trim()
            ));
            if let Some(quote) = entry_meta_string(entry, "evidence_quote") {
                output.push_str(&format!("  - quote: \"{quote}\"\n"));
            }
            if !entry.citations.is_empty() {
                output.push_str(&format!("  - cites: {}\n", entry.citations.join(", ")));
            }
        }
        output.push('\n');
    }

    output
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum ConfigValue {
    String(String),
    Integer(i64),
    Bool(bool),
    Array(Vec<ConfigValue>),
}

#[derive(Debug, Clone, Default)]
struct MiniToml {
    sections: BTreeMap<String, BTreeMap<String, ConfigValue>>,
    order: Vec<String>,
}

impl MiniToml {
    fn parse(text: &str) -> Result<Self> {
        let mut document = Self::default();
        let mut current = String::new();
        document.sections.entry(current.clone()).or_default();

        for (index, line) in text.lines().enumerate() {
            let line = strip_comment(line).trim().to_string();
            if line.is_empty() {
                continue;
            }

            if line.starts_with("[[") && line.ends_with("]]") {
                let base = line[2..line.len() - 2].trim().to_string();
                if base.is_empty() {
                    bail!("empty table header at line {}", index + 1);
                }
                current = document.next_array_table_name(&base);
                document.sections.entry(current.clone()).or_default();
                document.order.push(current.clone());
                continue;
            }

            if line.starts_with('[') && line.ends_with(']') {
                current = line[1..line.len() - 1].trim().to_string();
                if current.is_empty() {
                    bail!("empty table header at line {}", index + 1);
                }
                document.sections.entry(current.clone()).or_default();
                document.order.push(current.clone());
                continue;
            }

            let Some((key, value)) = line.split_once('=') else {
                bail!("expected key = value at line {}", index + 1);
            };
            let key = key.trim();
            if key.is_empty() {
                bail!("empty key at line {}", index + 1);
            }
            let value = parse_value(value.trim())
                .with_context(|| format!("failed to parse value at line {}", index + 1))?;
            document
                .sections
                .entry(current.clone())
                .or_default()
                .insert(key.to_string(), value);
        }

        Ok(document)
    }

    fn table(&self, name: &str) -> Option<&BTreeMap<String, ConfigValue>> {
        self.sections.get(name)
    }

    fn next_array_table_name(&self, base: &str) -> String {
        if !self.sections.contains_key(base) {
            return base.to_string();
        }
        let mut index = 1;
        loop {
            let candidate = format!("{base}#{index}");
            if !self.sections.contains_key(&candidate) {
                return candidate;
            }
            index += 1;
        }
    }
}

fn is_array_table(section: &str, base: &str) -> bool {
    section == base
        || section
            .strip_prefix(base)
            .and_then(|suffix| suffix.strip_prefix('#'))
            .is_some_and(|suffix| suffix.chars().all(|ch| ch.is_ascii_digit()))
}

fn strip_comment(line: &str) -> String {
    let mut in_string = false;
    let mut escaped = false;
    for (index, ch) in line.char_indices() {
        match ch {
            '\\' if in_string => escaped = !escaped,
            '"' if !escaped => in_string = !in_string,
            '#' if !in_string => return line[..index].to_string(),
            _ => escaped = false,
        }
    }
    line.to_string()
}

fn parse_value(value: &str) -> Result<ConfigValue> {
    let value = value.trim();
    if value.starts_with('"') && value.ends_with('"') {
        return Ok(ConfigValue::String(unquote_string(value)?));
    }
    if value == "true" {
        return Ok(ConfigValue::Bool(true));
    }
    if value == "false" {
        return Ok(ConfigValue::Bool(false));
    }
    if value.starts_with('[') && value.ends_with(']') {
        let inner = &value[1..value.len() - 1];
        let mut values = Vec::new();
        for part in split_array(inner) {
            let part = part.trim();
            if part.is_empty() {
                continue;
            }
            values.push(parse_value(part)?);
        }
        return Ok(ConfigValue::Array(values));
    }
    if let Ok(integer) = value.parse::<i64>() {
        return Ok(ConfigValue::Integer(integer));
    }

    bail!("unsupported value {value:?}; use quoted strings, integers, booleans, or arrays")
}

fn unquote_string(value: &str) -> Result<String> {
    let inner = value
        .strip_prefix('"')
        .and_then(|value| value.strip_suffix('"'))
        .context("invalid quoted string")?;
    Ok(inner
        .replace("\\\"", "\"")
        .replace("\\n", "\n")
        .replace("\\\\", "\\"))
}

fn split_array(value: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut start = 0;
    let mut in_string = false;
    let mut escaped = false;
    for (index, ch) in value.char_indices() {
        match ch {
            '\\' if in_string => escaped = !escaped,
            '"' if !escaped => in_string = !in_string,
            ',' if !in_string => {
                parts.push(value[start..index].to_string());
                start = index + 1;
            }
            _ => escaped = false,
        }
    }
    parts.push(value[start..].to_string());
    parts
}

fn string_value(values: &BTreeMap<String, ConfigValue>, key: &str) -> Option<String> {
    match values.get(key)? {
        ConfigValue::String(value) => Some(value.clone()),
        _ => None,
    }
}

fn usize_value(values: &BTreeMap<String, ConfigValue>, key: &str) -> Option<usize> {
    match values.get(key)? {
        ConfigValue::Integer(value) if *value >= 0 => Some(*value as usize),
        _ => None,
    }
}

fn bool_value(values: &BTreeMap<String, ConfigValue>, key: &str) -> Option<bool> {
    match values.get(key)? {
        ConfigValue::Bool(value) => Some(*value),
        _ => None,
    }
}

fn string_array(values: &BTreeMap<String, ConfigValue>, key: &str) -> Vec<String> {
    match values.get(key) {
        Some(ConfigValue::Array(values)) => values
            .iter()
            .filter_map(|value| match value {
                ConfigValue::String(value) => Some(value.clone()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::path::PathBuf;

    fn actor_resolution_fixture(
        agents: Vec<(&str, Option<&str>)>,
        roles: Vec<&str>,
    ) -> (Scenario, StageConfig) {
        let scenario = Scenario {
            dir: PathBuf::from("."),
            task: "test task".to_string(),
            agents: agents
                .into_iter()
                .map(|(id, domain)| AgentSpec {
                    id: id.to_string(),
                    domain: domain.map(ToOwned::to_owned),
                    desc: None,
                    doc: None,
                    private: None,
                    model: None,
                    skills: Vec::new(),
                })
                .collect(),
            private_docs: BTreeMap::new(),
            skills: BTreeMap::new(),
        };
        let stage = StageConfig {
            id: "test_stage".to_string(),
            organ: None,
            budget: None,
            inputs: Vec::new(),
            outputs: vec![EntryType::Observation],
            context: None,
            actors: ActorConfig {
                mode: "fixed".to_string(),
                count: None,
                min: None,
                max: None,
                scale_by: Vec::new(),
                roles: roles.into_iter().map(ToOwned::to_owned).collect(),
            },
            clustering: None,
            command: None,
            artifact: None,
            retract_overturned: false,
            grounded: false,
        };
        (scenario, stage)
    }

    #[test]
    fn actor_for_index_binds_agent_named_by_role() {
        let (scenario, stage) = actor_resolution_fixture(
            vec![("risk", Some("risk")), ("value", Some("value"))],
            vec!["value", "risk"],
        );

        assert_eq!(actor_for_index(&scenario, &stage, 0).unwrap().id, "value");
        assert_eq!(actor_for_index(&scenario, &stage, 1).unwrap().id, "risk");
    }

    #[test]
    fn actor_for_index_falls_back_to_position_for_free_text_roles() {
        let (scenario, stage) = actor_resolution_fixture(
            vec![("A1", Some("risk")), ("A2", Some("value"))],
            vec!["market", "technical", "risk"],
        );

        assert_eq!(actor_for_index(&scenario, &stage, 0).unwrap().id, "A1");
        assert_eq!(actor_for_index(&scenario, &stage, 2).unwrap().id, "A1");
    }

    #[test]
    fn resolve_actor_role_inherits_agent_domain_when_no_roles() {
        let (scenario, mut stage) =
            actor_resolution_fixture(vec![("risk", Some("risk"))], Vec::new());
        let actor = scenario.agents.first();

        assert_eq!(resolve_actor_role(&stage, 1, actor), "risk");

        stage.actors.roles = vec!["citation_auditor".to_string()];

        assert_eq!(resolve_actor_role(&stage, 1, actor), "citation_auditor");
    }

    #[test]
    fn parses_flow_config_with_stage_order_and_artifact() {
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "deep_investigation"
policy = "fixed"
budget = 20
max_feedback_cycles = 2

[actor_scaling]
default_mode = "fixed"
max_total_actors = 8
max_parallel_actors = 3

[process]
enabled = true
organ = "reasoning"
mode = "deep_investigation"
agent_count = 1
artifact_after_feedback = true
artifact_stages = ["write"]

[process.gates]
enforce_artifact_gate = true
allow_conditional_artifacts = false
require_citations = true
require_evidence_quotes = true
block_publish_on_open_questions = true
block_publish_on_quality_warnings = false
require_manifest = true

[process.stop]
max_cycles = 2
max_feedback_cycles = 5
stop_when = ["audit_passed", "artifact_publishable"]

[feedback]
enabled = true
max_requests_per_cycle = 3
dedupe_by = ["normalized_request"]

[[feedback.edge]]
from = ["write"]
to = "collect"
entry_types = ["question"]
trigger_when = ["needs_evidence"]

[feedback_entries]
enabled = true
kind = "tracefield_feedback"
accepted_types = ["change", "requirement", "question", "audit"]
status_field = "status"
max_requests_per_cycle = 2
dedupe_by = ["target", "action", "normalized_request"]

[[feedback_entries.route]]
from = ["write"]
target_prefix = "flow."
to = "collect"
entry_types = ["change", "requirement"]
actions = ["add", "change"]

[organs.reasoning]
adapter = "mock"
model = "none"

[stages.collect]
organ = "reasoning"
budget = 5
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "per_input"
max = 2

[stages.collect.clustering]
enabled = true
by = ["path_parent", "path"]
max_clusters = 4

[stages.write]
organ = "reasoning"
outputs = ["synthesis"]

[stages.write.artifact]
kind = "executive_report"
format = "markdown"
require_citations = true

[artifacts.report]
format = "markdown"
from_stage = "write"
path = "outputs/report.md"
"#,
        )
        .unwrap();

        assert_eq!(config.profile, "deep_investigation");
        assert_eq!(config.stages.len(), 2);
        assert_eq!(config.stages[0].id, "collect");
        assert_eq!(config.actor_scaling.max_parallel_actors, Some(3));
        assert!(config.process.enabled);
        assert_eq!(config.process.organ.as_deref(), Some("reasoning"));
        assert_eq!(config.process.agent_count, 1);
        assert!(config.process.artifact_after_feedback);
        assert_eq!(config.process.artifact_stages, vec!["write".to_string()]);
        assert!(config.process.gates.enforce_artifact_gate);
        assert!(!config.process.gates.allow_conditional_artifacts);
        assert!(config.process.gates.require_citations);
        assert!(config.process.gates.require_evidence_quotes);
        assert_eq!(config.process.stop.max_cycles, Some(2));
        assert_eq!(effective_max_feedback_cycles(&config), 5);
        assert_eq!(config.stages[0].outputs, vec![EntryType::Observation]);
        assert_eq!(config.stages[0].actors.mode, "per_input");
        assert_eq!(
            config.stages[0].clustering.as_ref().unwrap().by,
            vec!["path_parent", "path"]
        );
        assert_eq!(
            config.stages[0].clustering.as_ref().unwrap().max_clusters,
            Some(4)
        );
        assert_eq!(
            config.stages[1].artifact.as_ref().unwrap().kind.as_deref(),
            Some("executive_report")
        );
        assert_eq!(config.artifacts["report"].from_stage, "write");
        assert!(config.feedback.enabled);
        assert_eq!(config.feedback.max_requests_per_cycle, 3);
        assert_eq!(config.feedback.edges.len(), 1);
        assert_eq!(config.feedback.edges[0].from, vec!["write"]);
        assert_eq!(config.feedback.edges[0].to, "collect");
        assert_eq!(
            config.feedback.edges[0].entry_types,
            vec![EntryType::Question]
        );
        assert!(config.feedback_entries.enabled);
        assert_eq!(config.feedback_entries.kind, "tracefield_feedback");
        assert_eq!(config.feedback_entries.max_requests_per_cycle, 2);
        assert_eq!(config.feedback_entries.routes.len(), 1);
        assert_eq!(
            config.feedback_entries.routes[0].target_prefix.as_deref(),
            Some("flow.")
        );
        assert_eq!(config.feedback_entries.routes[0].to, "collect");
        assert_eq!(
            config.feedback_entries.routes[0].entry_types,
            vec![EntryType::Change, EntryType::Requirement]
        );
        assert!(!config.long_run.enabled);
        assert_eq!(config.long_run.cycles, 1);
    }

    #[test]
    fn parses_long_run_config_and_repeats_cycle_stages_before_final_stages() {
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "long_research"
policy = "fixed"
max_feedback_cycles = 2

[long_run]
enabled = true
cycles = 3
cycle_stages = ["collect", "analyze"]
max_work_items = 20
max_feedback_cycles = 7

[stages.collect]
outputs = ["observation"]

[stages.analyze]
inputs = ["stage:collect"]
outputs = ["synthesis", "question"]

[stages.finalize]
inputs = ["stage:analyze"]
outputs = ["synthesis"]

[stages.finalize.artifact]
kind = "report"
"#,
        )
        .unwrap();

        assert!(config.long_run.enabled);
        assert_eq!(config.long_run.cycles, 3);
        assert_eq!(
            config.long_run.cycle_stages,
            vec!["collect".to_string(), "analyze".to_string()]
        );
        assert_eq!(config.long_run.max_work_items, Some(20));
        assert_eq!(effective_max_feedback_cycles(&config), 7);

        let queue = initial_work_queue(&config)
            .into_iter()
            .map(|item| {
                format!(
                    "{}:{}:{}",
                    config.stages[item.stage_index].id, item.cycle, item.reason
                )
            })
            .collect::<Vec<_>>();

        assert_eq!(
            queue,
            vec![
                "collect:1:long_run_cycle",
                "analyze:1:long_run_cycle",
                "collect:2:long_run_cycle",
                "analyze:2:long_run_cycle",
                "collect:3:long_run_cycle",
                "analyze:3:long_run_cycle",
                "finalize:3:final"
            ]
        );
    }

    #[test]
    fn actor_parallelism_defaults_to_serial_unless_long_run() {
        let normal = FlowConfig::parse(
            r#"
[flow]
profile = "normal"
policy = "fixed"

[stages.collect]
outputs = ["observation"]
"#,
        )
        .unwrap();
        assert_eq!(actor_parallelism(&normal, 8), 1);

        let long_run = FlowConfig::parse(
            r#"
[flow]
profile = "long"
policy = "fixed"

[long_run]
enabled = true
cycles = 2

[stages.collect]
outputs = ["observation"]
"#,
        )
        .unwrap();
        assert_eq!(actor_parallelism(&long_run, 8), 4);

        let configured = FlowConfig::parse(
            r#"
[flow]
profile = "configured"
policy = "fixed"

[actor_scaling]
max_parallel_actors = 2

[stages.collect]
outputs = ["observation"]
"#,
        )
        .unwrap();
        assert_eq!(actor_parallelism(&configured, 8), 2);
    }

    #[tokio::test]
    async fn run_flow_executes_mock_stages_and_exports_artifact() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate orchestration.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"analysis","desc":"Analyze evidence."}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("inputs")).unwrap();
        fs::write(dir.path().join("inputs").join("source.md"), "Source fact.").unwrap();
        fs::write(
            dir.path().join("flow.toml"),
            r#"
[flow]
profile = "test_flow"
policy = "fixed"

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "per_input"
max = 1

[stages.write]
organ = "reasoning"
inputs = ["stage:collect"]
outputs = ["synthesis"]

[stages.write.actors]
mode = "fixed"
count = 1

[artifacts.report]
format = "markdown"
from_stage = "write"
path = "outputs/report.md"
"#,
        )
        .unwrap();

        let result = run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: None,
        })
        .await
        .unwrap();

        assert_eq!(result.profile, "test_flow");
        assert_eq!(result.stages.len(), 2);
        assert_eq!(result.stages[0].actor_count, 1);
        assert!(
            result.entries.iter().any(|entry| {
                entry.meta.get("stage").and_then(Value::as_str) == Some("collect")
            })
        );
        assert_eq!(result.artifacts.len(), 1);
        assert!(dir.path().join("outputs").join("report.md").exists());
        assert!(
            dir.path()
                .join("outputs")
                .join("report.md.manifest.json")
                .exists()
        );
        assert_eq!(
            result.artifacts[0].manifest_path,
            "outputs/report.md.manifest.json"
        );
        let manifest =
            fs::read_to_string(dir.path().join("outputs").join("report.md.manifest.json")).unwrap();
        let manifest: Value = serde_json::from_str(&manifest).unwrap();
        assert_eq!(
            manifest
                .get("retraction_model")
                .and_then(|value| value.get("mode"))
                .and_then(Value::as_str),
            Some("citation_closure")
        );
        let first_entry = manifest
            .get("entries")
            .and_then(Value::as_array)
            .and_then(|entries| entries.first())
            .unwrap();
        assert!(first_entry.get("provenance").is_some());
        assert!(first_entry.get("trace_span").is_some());
        assert!(first_entry.get("retraction").is_some());
        assert!(first_entry.get("rerun").is_some());
    }

    #[tokio::test]
    async fn run_flow_command_stage_probes_upstream_entry() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate probes.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"analysis","desc":"Analyze evidence."}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("inputs")).unwrap();
        fs::write(dir.path().join("inputs").join("source.md"), "Source fact.").unwrap();
        fs::write(
            dir.path().join("flow.toml"),
            r#"
[flow]
profile = "command_flow"
policy = "fixed"

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "per_input"
max = 1

[stages.probe]
inputs = ["stage:collect"]
outputs = ["observation"]

[stages.probe.actors]
mode = "none"

[stages.probe.command]
program = "sh"
args = ["-c", "echo PROBE_MARKER; cat \"$1\"", "sh", "{input}"]
"#,
        )
        .unwrap();

        let result = run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: None,
        })
        .await
        .unwrap();

        let probe = result
            .entries
            .iter()
            .find(|entry| entry.meta.get("kind").and_then(Value::as_str) == Some("command"))
            .expect("command stage produced an entry");
        assert_eq!(probe.author, "flow-command");
        assert_eq!(probe.meta.get("exit_code").and_then(Value::as_i64), Some(0));
        // stdout proves the command ran; the echoed input proves the upstream
        // entry was materialized into {input} and fed to the command.
        assert!(probe.text.contains("PROBE_MARKER"), "text: {}", probe.text);
        assert!(probe.text.contains("round"), "text: {}", probe.text);
        // the probe cites what it measured, so it stays in the retract closure.
        assert!(!probe.citations.is_empty());
    }

    #[tokio::test]
    async fn run_flow_scales_consult_stage_per_agent() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate orchestration.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"strategy","desc":"Analyze strategy."},{"id":"A2","domain":"risk","desc":"Analyze risks."}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("inputs")).unwrap();
        fs::write(dir.path().join("inputs").join("source.md"), "Source fact.").unwrap();
        fs::write(
            dir.path().join("flow.toml"),
            r#"
[flow]
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
        )
        .unwrap();

        let result = run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: None,
        })
        .await
        .unwrap();

        assert_eq!(
            result
                .stages
                .iter()
                .map(|stage| (stage.id.as_str(), stage.actor_count))
                .collect::<Vec<_>>(),
            vec![("deliberate", 2), ("deliberate", 2)]
        );
        let deliberate_entries = result
            .entries
            .iter()
            .filter(|entry| entry.meta.get("stage").and_then(Value::as_str) == Some("deliberate"))
            .count();
        let agent_count = 2;
        let cycles = 2;
        let mock_entries_per_actor = 2;
        assert!(deliberate_entries >= agent_count * cycles * mock_entries_per_actor);
    }

    #[tokio::test]
    async fn run_flow_routes_feedback_back_to_target_stage() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate orchestration.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"analysis","desc":"Analyze evidence."}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("inputs")).unwrap();
        fs::write(dir.path().join("inputs").join("source.md"), "Source fact.").unwrap();
        fs::write(
            dir.path().join("flow.toml"),
            r#"
[flow]
profile = "feedback_flow"
policy = "fixed"
max_feedback_cycles = 1

[feedback]
enabled = true
max_requests_per_cycle = 2

[[feedback.edge]]
from = ["analyze"]
to = "collect"
entry_types = ["question"]

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "fixed"
count = 1

[stages.analyze]
organ = "reasoning"
inputs = ["stage:collect"]
outputs = ["question"]

[stages.analyze.actors]
mode = "fixed"
count = 1
"#,
        )
        .unwrap();

        let result = run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: None,
        })
        .await
        .unwrap();

        let stage_ids = result
            .stages
            .iter()
            .map(|stage| stage.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(stage_ids, vec!["collect", "analyze", "collect", "analyze"]);
        assert!(result.entries.iter().any(|entry| {
            entry.entry_type == EntryType::Question
                && entry.meta.get("stage").and_then(Value::as_str) == Some("analyze")
        }));
    }

    #[tokio::test]
    async fn process_manager_runs_and_defers_artifacts_until_feedback() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("task.md"),
            "Investigate process management.\n",
        )
        .unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"analysis","desc":"Analyze evidence."}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("inputs")).unwrap();
        fs::write(dir.path().join("inputs").join("source.md"), "Source fact.").unwrap();
        fs::write(
            dir.path().join("flow.toml"),
            r#"
[flow]
profile = "process_flow"
policy = "fixed"
max_feedback_cycles = 1

[process]
enabled = true
organ = "reasoning"
mode = "test"
agent_count = 1
artifact_after_feedback = true
artifact_stages = ["artifact_strategy"]

[process.gates]
require_citations = true
require_manifest = true

[feedback]
enabled = true
max_requests_per_cycle = 1

[[feedback.edge]]
from = ["analyze"]
to = "collect"
entry_types = ["question"]

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "fixed"
count = 1

[stages.analyze]
organ = "reasoning"
inputs = ["stage:collect"]
outputs = ["question"]

[stages.analyze.actors]
mode = "fixed"
count = 1

[stages.artifact_strategy]
organ = "reasoning"
inputs = ["stage:analyze"]
outputs = ["synthesis"]

[stages.artifact_strategy.actors]
mode = "fixed"
count = 1

[artifacts.report]
format = "markdown"
from_stage = "artifact_strategy"
path = "outputs/report.md"
"#,
        )
        .unwrap();

        let result = run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: None,
        })
        .await
        .unwrap();

        let stage_ids = result
            .stages
            .iter()
            .map(|stage| stage.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(
            stage_ids,
            vec![
                "process_plan",
                "collect",
                "analyze",
                "collect",
                "analyze",
                "process_artifact_gate",
                "artifact_strategy",
                "process_verdict"
            ]
        );
        assert!(result.entries.iter().any(|entry| {
            entry.meta.get("actor_role").and_then(Value::as_str) == Some("process_manager")
        }));
        assert_eq!(result.artifacts.len(), 1);
    }

    #[tokio::test]
    async fn process_artifact_gate_enforcement_blocks_artifact_stages() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("task.md"),
            "Investigate process management.\n",
        )
        .unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"analysis","desc":"Analyze evidence."}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("inputs")).unwrap();
        fs::write(dir.path().join("inputs").join("source.md"), "Source fact.").unwrap();
        fs::write(
            dir.path().join("flow.toml"),
            r#"
[flow]
profile = "process_gate_block"
policy = "fixed"

[process]
enabled = true
organ = "reasoning"
mode = "test"
agent_count = 1
artifact_after_feedback = true
artifact_stages = ["artifact_strategy"]

[process.gates]
enforce_artifact_gate = true
block_publish_on_open_questions = true
require_manifest = true

[feedback]
enabled = false

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "fixed"
count = 1

[stages.analyze]
organ = "reasoning"
inputs = ["stage:collect"]
outputs = ["question"]

[stages.analyze.actors]
mode = "fixed"
count = 1

[stages.artifact_strategy]
organ = "reasoning"
inputs = ["stage:analyze"]
outputs = ["synthesis"]

[stages.artifact_strategy.actors]
mode = "fixed"
count = 1

[artifacts.report]
format = "markdown"
from_stage = "artifact_strategy"
path = "outputs/report.md"
"#,
        )
        .unwrap();

        let result = run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: None,
        })
        .await
        .unwrap();

        let stage_ids = result
            .stages
            .iter()
            .map(|stage| stage.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(
            stage_ids,
            vec![
                "process_plan",
                "collect",
                "analyze",
                "process_artifact_gate",
                "process_verdict"
            ]
        );
        assert_eq!(result.artifacts.len(), 0);
        assert!(!dir.path().join("outputs").join("report.md").exists());
        assert!(result.entries.iter().any(|entry| {
            entry.meta.get("kind").and_then(Value::as_str) == Some("process_gate_enforcement")
                && entry
                    .meta
                    .get("blocked_artifact_stages")
                    .and_then(Value::as_array)
                    .is_some_and(|stages| {
                        stages
                            .iter()
                            .any(|stage| stage.as_str() == Some("artifact_strategy"))
                    })
        }));
    }

    #[test]
    fn process_signals_count_only_unresolved_questions_as_open() {
        let mut store = ReferenceStore::new();
        let question = store.push(
            NewEntry::new(
                EntryType::Question,
                "analyst",
                "Which protocol fields are mandatory for artifact agents?",
            ),
            "analyst",
        );
        store.push(
            NewEntry::new(
                EntryType::Answer,
                "analyst",
                "Mandatory fields are provenance, artifact manifest, and retraction lineage.",
            )
            .with_citations(vec![question.id.clone()])
            .with_meta("status", json!("resolved"))
            .with_meta("resolves_question", json!(question.id.clone())),
            "analyst",
        );

        let signals = process_signals(&store, &[]);

        assert_eq!(signals.get("question_entries"), Some(&1));
        assert_eq!(signals.get("open_questions"), Some(&0));
    }

    #[test]
    fn slides_markdown_artifact_renders_marp_frontmatter() {
        let artifact = ArtifactConfig {
            id: "strategy_deck".to_string(),
            format: "slides_markdown".to_string(),
            from_stage: "deck_finalize".to_string(),
            path: "outputs/deck.md".to_string(),
        };
        let entry = Entry {
            id: "e1".to_string(),
            entry_type: EntryType::Synthesis,
            status: EntryStatus::Active,
            author: "deck".to_string(),
            text: "# Slide one\n\n- Point one\n- Point two".to_string(),
            citations: vec!["e0".to_string()],
            meta: Default::default(),
            embedding: Vec::new(),
        };

        let rendered = render_artifact_markdown(&artifact, &[entry]);

        assert!(rendered.starts_with("---\nmarp: true\npaginate: true\n---"));
        assert!(rendered.contains("# Slide one"));
        assert!(rendered.contains("<!-- citations: e0 -->"));
    }

    #[tokio::test]
    async fn run_flow_resumes_existing_store_without_duplicate_seeds() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Investigate orchestration.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"analysis","desc":"Analyze evidence."}]}"#,
        )
        .unwrap();
        fs::create_dir(dir.path().join("inputs")).unwrap();
        fs::write(dir.path().join("inputs").join("source.md"), "Source fact.").unwrap();
        fs::write(
            dir.path().join("flow.toml"),
            r#"
[flow]
profile = "resume_flow"
policy = "fixed"

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
inputs = ["kind:input"]
outputs = ["observation"]

[stages.collect.actors]
mode = "fixed"
count = 1
"#,
        )
        .unwrap();
        let store_path = dir.path().join("store.jsonl");

        run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: Some(store_path.clone()),
        })
        .await
        .unwrap();
        run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: Some(store_path.clone()),
        })
        .await
        .unwrap();

        let store = ReferenceStore::from_jsonl_path(&store_path).unwrap();
        let task_count = store
            .all()
            .iter()
            .filter(|entry| entry.meta.get("kind").and_then(Value::as_str) == Some("task"))
            .count();
        let input_count = store
            .all()
            .iter()
            .filter(|entry| entry.meta.get("kind").and_then(Value::as_str) == Some("input"))
            .count();
        assert_eq!(task_count, 1);
        assert_eq!(input_count, 1);
        assert_eq!(
            store
                .all()
                .iter()
                .filter(|entry| entry.meta.get("stage").and_then(Value::as_str) == Some("collect"))
                .count(),
            2
        );
    }

    #[test]
    fn flow_config_rejects_command_stage_with_actors() {
        let error = FlowConfig::parse(
            r#"
[flow]
profile = "bad"
policy = "fixed"

[stages.probe]
outputs = ["observation"]

[stages.probe.actors]
mode = "fixed"
count = 1

[stages.probe.command]
program = "sh"
args = ["-c", "echo hi"]
"#,
        )
        .unwrap_err()
        .to_string();
        assert!(
            error.contains("must set [actors] mode = \"none\""),
            "{error}"
        );
    }

    #[test]
    fn flow_config_rejects_invalid_references() {
        let error = FlowConfig::parse(
            r#"
[flow]
profile = "bad"
policy = "fixed"

[stages.collect]
organ = "missing"
outputs = ["observation"]
"#,
        )
        .unwrap_err()
        .to_string();
        assert!(error.contains("unknown organ"));

        let error = FlowConfig::parse(
            r#"
[flow]
profile = "bad"
policy = "fixed"

[organs.reasoning]
adapter = "mock"

[stages.collect]
organ = "reasoning"
outputs = ["not_a_type"]
"#,
        )
        .unwrap_err()
        .to_string();
        assert!(error.contains("unknown entry type"));
    }

    #[test]
    fn core_gates_coerce_output_type_and_repair_citations() {
        let mut store = ReferenceStore::new();
        store.push(
            NewEntry::new(EntryType::Chunk, "scenario", "source"),
            "scenario",
        );
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "gate_test"
policy = "fixed"

[feedback_entries]
enabled = true
accepted_types = ["observation"]

[[feedback_entries.route]]
target_prefix = "flow."
to = "extract"

[stages.extract]
outputs = ["observation"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];
        let gated = apply_core_gates(
            vec![
                NewEntry::new(EntryType::Claim, "agent", "claim")
                    .with_citations(vec!["missing".to_string()])
                    .with_meta("target", json!("flow.stage.extract")),
            ],
            &store,
            &config,
            stage,
            Path::new("."),
        );

        assert_eq!(gated[0].entry_type, EntryType::Observation);
        assert_eq!(gated[0].citations, Vec::<String>::new());
        assert_eq!(
            gated[0]
                .meta
                .get("invalid_citations_dropped")
                .and_then(Value::as_bool),
            Some(true)
        );
        assert_eq!(
            gated[0]
                .meta
                .get("coerced_type_from")
                .and_then(Value::as_str),
            Some("claim")
        );
        assert_eq!(
            gated[0].meta.get("kind").and_then(Value::as_str),
            Some("tracefield_feedback")
        );
        assert_eq!(
            gated[0].meta.get("status").and_then(Value::as_str),
            Some("proposed")
        );
        assert_eq!(
            gated[0].meta.get("source_stage").and_then(Value::as_str),
            Some("extract")
        );

        let feedback_config = FlowConfig::parse(
            r#"
[flow]
profile = "feedback_gate_test"
policy = "fixed"

[feedback_entries]
enabled = true
accepted_types = ["change"]

[[feedback_entries.route]]
target_prefix = "flow."
to = "observe"

[stages.observe]
outputs = ["observation"]
"#,
        )
        .unwrap();
        let feedback_stage = &feedback_config.stages[0];
        let feedback_gated = apply_core_gates(
            vec![
                NewEntry::new(EntryType::Change, "agent", "Change Tracefield config.")
                    .with_meta("target", json!("flow.stage.source_extract")),
            ],
            &store,
            &feedback_config,
            feedback_stage,
            Path::new("."),
        );

        assert_eq!(feedback_gated[0].entry_type, EntryType::Change);
        assert_eq!(feedback_gated[0].meta.get("coerced_type_from"), None);
        assert_eq!(
            feedback_gated[0].meta.get("kind").and_then(Value::as_str),
            Some("tracefield_feedback")
        );
    }

    #[test]
    fn feedback_entries_route_only_tracefield_feedback_kind() {
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "feedback_route_test"
policy = "fixed"
max_feedback_cycles = 2

[feedback_entries]
enabled = true
accepted_types = ["change", "question", "audit"]
dedupe_by = ["target", "action", "normalized_request"]

[[feedback_entries.route]]
target_prefix = "flow."
to = "feedback_triage"
entry_types = ["change"]

[stages.audit]
outputs = ["change"]

[stages.feedback_triage]
inputs = ["kind:tracefield_feedback"]
outputs = ["change", "decision"]
"#,
        )
        .unwrap();
        let mut feedback_meta = Map::new();
        feedback_meta.insert("kind".to_string(), json!("tracefield_feedback"));
        feedback_meta.insert("target".to_string(), json!("flow.stage.source_extract"));
        feedback_meta.insert("action".to_string(), json!("change"));
        let feedback = Entry {
            id: "e1".to_string(),
            entry_type: EntryType::Change,
            status: EntryStatus::Active,
            author: "audit".to_string(),
            text: "Change source_extract actor scaling.".to_string(),
            citations: Vec::new(),
            meta: feedback_meta,
            embedding: Vec::new(),
        };
        let ordinary = Entry {
            id: "e2".to_string(),
            entry_type: EntryType::Change,
            status: EntryStatus::Active,
            author: "audit".to_string(),
            text: "Ordinary change should not route.".to_string(),
            citations: Vec::new(),
            meta: Map::new(),
            embedding: Vec::new(),
        };
        let mut feedback_cycles = 0;

        let work = feedback_work_items(
            &config,
            0,
            &[feedback.clone(), ordinary],
            &mut feedback_cycles,
        );

        assert_eq!(feedback_cycles, 1);
        assert_eq!(work.len(), 1);
        assert_eq!(work[0].stage_index, 1);
        assert_eq!(work[0].feedback_request_ids, vec![feedback.id]);
    }

    #[test]
    fn actor_sharding_partitions_inputs_and_clusters() {
        let mut first_meta = Map::new();
        first_meta.insert("path".to_string(), json!("inputs/a/one.md"));
        let mut second_meta = Map::new();
        second_meta.insert("path".to_string(), json!("inputs/b/two.md"));
        let mut third_meta = Map::new();
        third_meta.insert("path".to_string(), json!("inputs/a/three.md"));
        let selected = vec![
            Entry {
                id: "e1".to_string(),
                entry_type: EntryType::CorpusChunk,
                status: EntryStatus::Active,
                author: "scenario".to_string(),
                text: "one".to_string(),
                citations: Vec::new(),
                meta: first_meta,
                embedding: Vec::new(),
            },
            Entry {
                id: "e2".to_string(),
                entry_type: EntryType::CorpusChunk,
                status: EntryStatus::Active,
                author: "scenario".to_string(),
                text: "two".to_string(),
                citations: Vec::new(),
                meta: second_meta,
                embedding: Vec::new(),
            },
            Entry {
                id: "e3".to_string(),
                entry_type: EntryType::CorpusChunk,
                status: EntryStatus::Active,
                author: "scenario".to_string(),
                text: "three".to_string(),
                citations: Vec::new(),
                meta: third_meta,
                embedding: Vec::new(),
            },
        ];
        let stage = StageConfig {
            id: "source_extract".to_string(),
            organ: None,
            budget: None,
            inputs: Vec::new(),
            outputs: vec![EntryType::Observation],
            context: None,
            actors: ActorConfig {
                mode: "per_input".to_string(),
                count: None,
                min: None,
                max: None,
                scale_by: Vec::new(),
                roles: vec!["data_actor".to_string()],
            },
            clustering: None,
            command: None,
            artifact: None,
            retract_overturned: false,
            grounded: false,
        };

        assert_eq!(
            actor_selected_entries(&stage, &selected, 0, 2)
                .into_iter()
                .map(|entry| entry.id)
                .collect::<Vec<_>>(),
            vec!["e1", "e3"]
        );
        assert_eq!(
            actor_selected_entries(&stage, &selected, 1, 2)
                .into_iter()
                .map(|entry| entry.id)
                .collect::<Vec<_>>(),
            vec!["e2"]
        );

        let mut cluster_stage = stage.clone();
        cluster_stage.actors.mode = "per_cluster".to_string();
        assert_eq!(
            actor_selected_entries(&cluster_stage, &selected, 0, 2)
                .into_iter()
                .map(|entry| entry.id)
                .collect::<Vec<_>>(),
            vec!["e1", "e3"]
        );
        assert_eq!(
            actor_selected_entries(&cluster_stage, &selected, 1, 2)
                .into_iter()
                .map(|entry| entry.id)
                .collect::<Vec<_>>(),
            vec!["e2"]
        );
    }

    #[test]
    fn stage_input_selector_supports_path_and_source_url() {
        let mut first_meta = Map::new();
        first_meta.insert("path".to_string(), json!("inputs/web/one.md"));
        first_meta.insert("source_url".to_string(), json!("https://example.com/one"));
        let mut second_meta = Map::new();
        second_meta.insert("path".to_string(), json!("inputs/web/two.md"));
        second_meta.insert("source_url".to_string(), json!("https://example.com/two"));

        let store = ReferenceStore::from_entries(vec![
            Entry {
                id: "e1".to_string(),
                entry_type: EntryType::CorpusChunk,
                status: EntryStatus::Active,
                author: "scenario".to_string(),
                text: "one".to_string(),
                citations: Vec::new(),
                meta: first_meta,
                embedding: Vec::new(),
            },
            Entry {
                id: "e2".to_string(),
                entry_type: EntryType::CorpusChunk,
                status: EntryStatus::Active,
                author: "scenario".to_string(),
                text: "two".to_string(),
                citations: Vec::new(),
                meta: second_meta,
                embedding: Vec::new(),
            },
        ]);

        assert_eq!(
            entries_for_selector(&store, "path:inputs/web/one.md")
                .into_iter()
                .map(|entry| entry.id)
                .collect::<Vec<_>>(),
            vec!["e1"]
        );
        assert_eq!(
            entries_for_selector(&store, "source_url:https://example.com/two")
                .into_iter()
                .map(|entry| entry.id)
                .collect::<Vec<_>>(),
            vec!["e2"]
        );
    }

    #[test]
    fn stage_context_is_bounded_for_large_web_inputs() {
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "context_bound_test"
policy = "fixed"

[stages.source_extract]
outputs = ["observation"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];
        let entry = Entry {
            id: "e1".to_string(),
            entry_type: EntryType::CorpusChunk,
            status: EntryStatus::Active,
            author: "scenario".to_string(),
            text: "あ".repeat(MAX_CONTEXT_CHARS_TOTAL * 2),
            citations: Vec::new(),
            meta: Map::new(),
            embedding: Vec::new(),
        };

        let context = render_stage_context(stage, &[entry]);

        assert!(context.chars().count() <= MAX_CONTEXT_CHARS_TOTAL + 4);
        assert!(context.ends_with("..."));
    }

    #[test]
    fn source_excerpt_context_prefers_relevant_source_body() {
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "source_excerpt_test"
policy = "fixed"

[stages.source_extract]
outputs = ["observation"]

[stages.source_extract.context]
mode = "source_excerpt"
chars_per_entry = 900
chars_total = 1200
keywords = ["agentic workflows", "handoffs", "guardrails"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];
        let mut meta = Map::new();
        meta.insert("title".to_string(), json!("OpenAI Agents SDK"));
        meta.insert(
            "source_url".to_string(),
            json!("https://openai.github.io/openai-agents-python/"),
        );
        let entry = Entry {
            id: "e1".to_string(),
            entry_type: EntryType::CorpusChunk,
            status: EntryStatus::Active,
            author: "scenario".to_string(),
            text: "---\ntitle: \"OpenAI Agents SDK\"\nbytes: 72082\n---\n\nSkip to content\nTable of contents\nNavigation\n\nThe OpenAI Agents SDK enables you to build agentic AI apps in a lightweight, easy-to-use package with very few abstractions.\n\nAgents as tools and Handoffs allow agents to delegate work across multiple agents while guardrails validate inputs and outputs.".to_string(),
            citations: Vec::new(),
            meta,
            embedding: Vec::new(),
        };

        let context = render_stage_context(stage, &[entry]);

        assert!(context.contains("source_url=https://openai.github.io/openai-agents-python/"));
        assert!(context.contains("enables you to build agentic AI apps"));
        assert!(context.contains("Handoffs allow agents to delegate work"));
        assert!(!context.contains("Skip to content"));
    }

    #[test]
    fn parses_fenced_json_model_output() {
        let value = parse_json_value_from_model_output(
            "```json\n{\"entries\":[{\"type\":\"observation\",\"text\":\"ok\"}]}\n```",
        )
        .unwrap();

        assert_eq!(value["entries"][0]["text"], "ok");
    }

    #[test]
    fn parses_json_object_with_surrounding_model_text() {
        let value = parse_json_value_from_model_output(
            "Here is the result:\n{\"entries\":[{\"type\":\"question\",\"text\":\"why?\"}]}\nDone.",
        )
        .unwrap();

        assert_eq!(value["entries"][0]["type"], "question");
    }

    #[test]
    fn parses_input_doc_frontmatter_metadata() {
        let meta = parse_input_doc_meta(
            "---\nsource_url: \"https://example.com/page\"\ntitle: \"Redirecting...\"\nbytes: 446\n---\n# Redirecting...\n",
        );

        assert_eq!(
            meta.get("source_url").and_then(Value::as_str),
            Some("https://example.com/page")
        );
        assert_eq!(
            meta.get("title").and_then(Value::as_str),
            Some("Redirecting...")
        );
        assert_eq!(meta.get("bytes").and_then(Value::as_u64), Some(446));
    }

    #[test]
    fn parse_stage_entries_flattens_nested_json_text() {
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "nested_json_test"
policy = "fixed"

[organs.data]
adapter = "ollama"
model = "gemma4:26b-a4b-it-qat"

[stages.source_extract]
organ = "data"
outputs = ["observation", "question"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];
        let organ = config.organs.get("data");
        let selected = vec![Entry {
            id: "e1".to_string(),
            entry_type: EntryType::CorpusChunk,
            status: EntryStatus::Active,
            author: "scenario".to_string(),
            text: "LangGraph supports graph control flow.".to_string(),
            citations: Vec::new(),
            meta: Map::new(),
            embedding: Vec::new(),
        }];
        let scaling = ActorScalingDecision {
            mode: "per_input".to_string(),
            chosen_count: 1,
            signals: BTreeMap::new(),
        };
        let nested_text = json!({
            "entries": [{
                "type": "observation",
                "text": "LangGraph supports graph control flow.",
                "citations": ["e1"],
                "meta": {"evidence_quote": "graph control flow"}
            }]
        })
        .to_string();
        let content = json!({
            "entries": [{
                "type": "observation",
                "text": nested_text,
                "citations": ["e1"],
                "meta": {"outer": "kept"}
            }]
        })
        .to_string();

        let entries = parse_stage_entries(
            &content,
            &config,
            stage,
            "data",
            organ,
            "source_extract-1",
            0,
            1,
            &selected,
            &scaling,
        );

        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].text, "LangGraph supports graph control flow.");
        assert_eq!(entries[0].citations, vec!["e1".to_string()]);
        assert_eq!(
            entries[0]
                .meta
                .get("nested_json_text_flattened")
                .and_then(Value::as_bool),
            Some(true)
        );
        assert_eq!(
            entries[0].meta.get("outer").and_then(Value::as_str),
            Some("kept")
        );
        assert_eq!(
            entries[0]
                .meta
                .get("evidence_quote")
                .and_then(Value::as_str),
            Some("graph control flow")
        );
    }

    #[test]
    fn parse_stage_entries_salvages_jsonish_nested_entries_text() {
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "jsonish_nested_test"
policy = "fixed"

[organs.data]
adapter = "ollama"
model = "gemma4:26b-a4b-it-qat"

[stages.source_extract]
organ = "data"
outputs = ["observation", "question"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];
        let selected = vec![Entry {
            id: "e1".to_string(),
            entry_type: EntryType::CorpusChunk,
            status: EntryStatus::Active,
            author: "scenario".to_string(),
            text: "OpenAI Agents SDK enables agentic workflows.".to_string(),
            citations: Vec::new(),
            meta: Map::new(),
            embedding: Vec::new(),
        }];
        let scaling = ActorScalingDecision {
            mode: "fixed".to_string(),
            chosen_count: 1,
            signals: BTreeMap::new(),
        };
        let jsonish_text = r#"{"entries":[{"type":"observation","text":"The OpenAI Agents SDK enables agentic workflows.","citations":["e1"],"meta":{"evidence_quote":"enables you to build agentic AI apps","claim_role":"source_evidence"}}},{"type":"question","text":"What handoff details require a more specific source?","citations":["e1"],"meta":{"action":"recollect"}}}"#;
        let content = json!({
            "entries": [{
                "type": "observation",
                "text": jsonish_text,
                "citations": ["e1"],
                "meta": {"outer": "kept"}
            }]
        })
        .to_string();

        let entries = parse_stage_entries(
            &content,
            &config,
            stage,
            "data",
            config.organs.get("data"),
            "source_extract-1",
            0,
            1,
            &selected,
            &scaling,
        );

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].entry_type, EntryType::Observation);
        assert_eq!(entries[1].entry_type, EntryType::Question);
        assert!(!entries[0].text.trim_start().starts_with('{'));
        assert_eq!(entries[0].citations, vec!["e1".to_string()]);
        assert_eq!(
            entries[1].meta.get("action").and_then(Value::as_str),
            Some("recollect")
        );
        assert!(entries.iter().all(|entry| {
            entry
                .meta
                .get("jsonish_entries_salvaged")
                .and_then(Value::as_bool)
                == Some(true)
        }));
        assert!(entries.iter().all(|entry| {
            entry
                .meta
                .get("nested_json_text_flattened")
                .and_then(Value::as_bool)
                == Some(true)
        }));
    }

    #[test]
    fn parse_stage_entries_salvages_completed_entries_from_truncated_jsonish_output() {
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "truncated_jsonish_test"
policy = "fixed"

[stages.source_extract]
outputs = ["observation", "question"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];
        let selected = vec![Entry {
            id: "e1".to_string(),
            entry_type: EntryType::CorpusChunk,
            status: EntryStatus::Active,
            author: "scenario".to_string(),
            text: "Agents as tools and handoffs coordinate work. Guardrails validate inputs."
                .to_string(),
            citations: Vec::new(),
            meta: Map::new(),
            embedding: Vec::new(),
        }];
        let scaling = ActorScalingDecision {
            mode: "fixed".to_string(),
            chosen_count: 1,
            signals: BTreeMap::new(),
        };
        let content = r#"{"entries":[{"type":"observation","text":"Agents as tools coordinate work.","citations":["e1"],"meta":{"evidence_quote":"Agents as tools and handoffs coordinate work","claim_role":"source_evidence"}},{"type":"observation","text":"Guardrails validate inputs.","citations":["e1"],"meta":{"evidence_quote":"Guardrails validate inputs","claim_role":"source_evidence"}},{"type":"observation","text":"truncated"#;

        let entries = parse_stage_entries(
            content,
            &config,
            stage,
            "data",
            None,
            "source_extract-1",
            0,
            1,
            &selected,
            &scaling,
        );

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].text, "Agents as tools coordinate work.");
        assert_eq!(entries[1].text, "Guardrails validate inputs.");
        assert!(entries.iter().all(|entry| {
            entry
                .meta
                .get("jsonish_entries_salvaged")
                .and_then(Value::as_bool)
                == Some(true)
        }));
    }

    #[test]
    fn source_grounded_gate_converts_weak_source_claims_to_recollection_questions() {
        let mut store = ReferenceStore::new();
        let source = store.push(
            NewEntry::new(
                EntryType::CorpusChunk,
                "scenario",
                "---\ntitle: \"Redirecting...\"\nbytes: 446\n---\n# Redirecting...\nRedirecting...",
            )
            .with_meta("kind", json!("input"))
            .with_meta("title", json!("Redirecting..."))
            .with_meta("bytes", json!(446)),
            "scenario",
        );
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "weak_source_gate_test"
policy = "fixed"

[stages.source_extract]
outputs = ["observation", "question"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];

        let gated = apply_core_gates(
            vec![
                NewEntry::new(
                    EntryType::Observation,
                    "gemma",
                    "The redirect page proves a multi-agent orchestration feature.",
                )
                .with_citations(vec![source.id.clone()]),
            ],
            &store,
            &config,
            stage,
            Path::new("."),
        );

        assert_eq!(gated[0].entry_type, EntryType::Question);
        assert!(gated[0].text.starts_with("Recollect stronger evidence"));
        assert_eq!(
            gated[0].meta.get("source_quality").and_then(Value::as_str),
            Some("weak")
        );
        assert_eq!(
            gated[0]
                .meta
                .get("source_quality_reason")
                .and_then(Value::as_str),
            Some("redirect_page")
        );
        assert_eq!(
            gated[0]
                .meta
                .get("converted_to_question_from")
                .and_then(Value::as_str),
            Some("observation")
        );
    }

    #[test]
    fn source_grounded_gate_marks_weak_and_missing_evidence_quotes() {
        let mut store = ReferenceStore::new();
        let source = store.push(
            NewEntry::new(
                EntryType::CorpusChunk,
                "scenario",
                "The OpenAI Agents SDK enables you to build agentic AI apps in a lightweight package. Handoffs allow agents to delegate work across multiple agents.",
            )
            .with_meta("kind", json!("input")),
            "scenario",
        );
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "evidence_quote_gate_test"
policy = "fixed"

[stages.source_extract]
outputs = ["observation", "question"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];

        let gated = apply_core_gates(
            vec![
                NewEntry::new(
                    EntryType::Observation,
                    "gemma",
                    "The OpenAI Agents SDK supports agentic apps.",
                )
                .with_citations(vec![source.id.clone()])
                .with_meta("evidence_quote", json!("OpenAI Agents SDK")),
                NewEntry::new(
                    EntryType::Observation,
                    "gemma",
                    "The source claims a supervisor swarm protocol.",
                )
                .with_citations(vec![source.id.clone()])
                .with_meta(
                    "evidence_quote",
                    json!("supervisor swarm protocol is the default orchestration runtime"),
                ),
            ],
            &store,
            &config,
            stage,
            Path::new("."),
        );

        assert_eq!(
            gated[0]
                .meta
                .get("evidence_quote_repaired")
                .and_then(Value::as_bool),
            Some(true)
        );
        assert!(!entry_has_quality_warning(&gated[0], "weak_evidence_quote"));
        assert!(!entry_has_quality_warning(
            &gated[0],
            "evidence_quote_not_found"
        ));
        assert!(entry_has_quality_warning(
            &gated[1],
            "evidence_quote_not_found"
        ));
    }

    #[test]
    fn source_grounded_gate_repairs_paraphrased_evidence_quotes() {
        let mut store = ReferenceStore::new();
        let source = store.push(
            NewEntry::new(
                EntryType::CorpusChunk,
                "scenario",
                "Choose your path Quickstart Configuration Documentation Documentation Agents Sandbox agents Agent memory Models Tools Guardrails Running agents Streaming Agent orchestration Handoffs Results Human-in-the-loop Sessions\n\nAgents as tools / Handoffs , which allow agents to delegate to other agents for specific tasks. Guardrails , which enable validation of agent inputs and outputs. Sessions : A persistent memory layer for maintaining working context within an agent loop.",
            )
            .with_meta("kind", json!("input")),
            "scenario",
        );
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "evidence_quote_repair_test"
policy = "fixed"

[stages.source_extract]
outputs = ["observation", "question"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];

        let gated = apply_core_gates(
            vec![
                NewEntry::new(
                    EntryType::Observation,
                    "ds4",
                    "OpenAI Agents SDK provides orchestration concepts including handoffs, guardrails, and session memory.",
                )
                .with_citations(vec![source.id.clone()])
                .with_meta(
                    "evidence_quote",
                    json!("OpenAI Agents SDK provides orchestration concepts including handoffs, guardrails, and session memory"),
                ),
            ],
            &store,
            &config,
            stage,
            Path::new("."),
        );

        assert_eq!(gated.len(), 1);
        assert!(!entry_has_quality_warning(
            &gated[0],
            "evidence_quote_not_found"
        ));
        assert_eq!(
            gated[0]
                .meta
                .get("evidence_quote_repaired")
                .and_then(Value::as_bool),
            Some(true)
        );
        let repaired = gated[0]
            .meta
            .get("evidence_quote")
            .and_then(Value::as_str)
            .unwrap();
        assert!(repaired.contains("Handoffs"));
        assert!(!repaired.contains("Quickstart Configuration"));
        assert!(evidence_quote_found_in_citations(
            &store,
            &[source.id],
            repaired
        ));
    }

    #[test]
    fn grounded_flag_enables_evidence_quote_gate() {
        let mut store = ReferenceStore::new();
        let source = store.push(
            NewEntry::new(
                EntryType::CorpusChunk,
                "scenario",
                "This entry documents parser behavior without mentioning review quorum policy.",
            )
            .with_meta("kind", json!("input")),
            "scenario",
        );
        let grounded_config = FlowConfig::parse(
            r#"
[flow]
profile = "grounded_flag_test"
policy = "fixed"

[stages.analysis]
grounded = true
outputs = ["observation"]
"#,
        )
        .unwrap();
        let ungrounded_config = FlowConfig::parse(
            r#"
[flow]
profile = "ungrounded_flag_test"
policy = "fixed"

[stages.analysis]
outputs = ["observation"]
"#,
        )
        .unwrap();
        let entry = NewEntry::new(
            EntryType::Observation,
            "agent",
            "Analysis claims the merge policy requires reviewer quorum.",
        )
        .with_citations(vec![source.id.clone()])
        .with_meta(
            "evidence_quote",
            json!(
                "The fabricated source says a quorum of seven reviewers must approve every merge."
            ),
        );

        let grounded = apply_core_gates(
            vec![entry.clone()],
            &store,
            &grounded_config,
            &grounded_config.stages[0],
            Path::new("."),
        );
        let ungrounded = apply_core_gates(
            vec![entry],
            &store,
            &ungrounded_config,
            &ungrounded_config.stages[0],
            Path::new("."),
        );

        assert!(entry_has_quality_warning(
            &grounded[0],
            "evidence_quote_not_found"
        ));
        assert!(!entry_has_quality_warning(
            &ungrounded[0],
            "evidence_quote_not_found"
        ));
    }

    #[test]
    fn on_disk_evidence_quote_grounds_claim() {
        let dir = tempfile::tempdir().unwrap();
        let quote = "The verifier accepts claims only when a copied evidence quote appears in the source file.";
        fs::write(
            dir.path().join("src.rs"),
            format!("fn unrelated() {{}}\n// {quote}\npub fn grounded_reading() {{}}\n"),
        )
        .unwrap();

        let mut store = ReferenceStore::new();
        let pointer = store.push(
            NewEntry::new(
                EntryType::CorpusChunk,
                "scenario",
                "path: src.rs\nlines: 2-2",
            )
            .with_meta("kind", json!("input")),
            "scenario",
        );
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "on_disk_quote_test"
policy = "fixed"

[stages.analysis]
grounded = true
outputs = ["observation"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];

        let gated = apply_core_gates(
            vec![
                NewEntry::new(
                    EntryType::Observation,
                    "agent",
                    "The verifier requires copied evidence quotes to appear in source files.",
                )
                .with_citations(vec![pointer.id.clone()])
                .with_meta("source_path", json!("src.rs"))
                .with_meta("source_line", json!(2))
                .with_meta("evidence_quote", json!(quote)),
                NewEntry::new(
                    EntryType::Observation,
                    "agent",
                    "The verifier accepts fabricated source claims.",
                )
                .with_citations(vec![pointer.id.clone()])
                .with_meta("source_path", json!("src.rs"))
                .with_meta("source_line", json!(2))
                .with_meta(
                    "evidence_quote",
                    json!("The verifier allows fabricated quotes to pass without checking files."),
                ),
            ],
            &store,
            &config,
            stage,
            dir.path(),
        );

        assert!(!entry_has_quality_warning(
            &gated[0],
            "evidence_quote_not_found"
        ));
        assert_eq!(
            gated[0]
                .meta
                .get("evidence_grounded")
                .and_then(Value::as_str),
            Some("on_disk")
        );
        assert!(entry_has_quality_warning(
            &gated[1],
            "evidence_quote_not_found"
        ));
    }

    #[test]
    fn on_disk_parent_dir_path_grounds_claim() {
        let dir = tempfile::tempdir().unwrap();
        let scenario_dir = dir.path().join("scenario");
        let sibling_dir = dir.path().join("sibling");
        fs::create_dir(&scenario_dir).unwrap();
        fs::create_dir(&sibling_dir).unwrap();
        fs::write(
            sibling_dir.join("src.rs"),
            "fn answer() -> u32 { 42 }\nfn unrelated() {}\n",
        )
        .unwrap();

        let mut store = ReferenceStore::new();
        let pointer = store.push(
            NewEntry::new(
                EntryType::CorpusChunk,
                "scenario",
                "path: ../sibling/src.rs\nlines: 1-1",
            )
            .with_meta("kind", json!("input")),
            "scenario",
        );
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "parent_dir_on_disk_quote_test"
policy = "fixed"

[stages.analysis]
grounded = true
outputs = ["observation"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];

        let gated = apply_core_gates(
            vec![
                NewEntry::new(
                    EntryType::Observation,
                    "agent",
                    "The source defines an answer function returning 42.",
                )
                .with_citations(vec![pointer.id.clone()])
                .with_meta("source_path", json!("../sibling/src.rs"))
                .with_meta("source_line", json!(1))
                .with_meta("evidence_quote", json!("answer() -> u32 { 42 }")),
                NewEntry::new(
                    EntryType::Observation,
                    "agent",
                    "The source defines a fabricated answer.",
                )
                .with_citations(vec![pointer.id.clone()])
                .with_meta("source_path", json!("../sibling/src.rs"))
                .with_meta("source_line", json!(1))
                .with_meta("evidence_quote", json!("answer() -> u32 { 43 }")),
            ],
            &store,
            &config,
            stage,
            &scenario_dir,
        );

        assert!(!entry_has_quality_warning(
            &gated[0],
            "evidence_quote_not_found"
        ));
        assert_eq!(
            gated[0]
                .meta
                .get("evidence_grounded")
                .and_then(Value::as_str),
            Some("on_disk")
        );
        assert!(entry_has_quality_warning(
            &gated[1],
            "evidence_quote_not_found"
        ));
    }

    #[test]
    fn on_disk_missing_source_path_does_not_panic() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = ReferenceStore::new();
        let pointer = store.push(
            NewEntry::new(
                EntryType::CorpusChunk,
                "scenario",
                "path: missing.rs\nlines: 1-1",
            )
            .with_meta("kind", json!("input")),
            "scenario",
        );
        let config = FlowConfig::parse(
            r#"
[flow]
profile = "missing_on_disk_quote_test"
policy = "fixed"

[stages.analysis]
grounded = true
outputs = ["observation"]
"#,
        )
        .unwrap();
        let stage = &config.stages[0];

        let gated = apply_core_gates(
            vec![
                NewEntry::new(
                    EntryType::Observation,
                    "agent",
                    "The missing source claims are treated as ungrounded.",
                )
                .with_citations(vec![pointer.id.clone()])
                .with_meta("source_path", json!("missing.rs"))
                .with_meta("source_line", json!(1))
                .with_meta(
                    "evidence_quote",
                    json!("The missing source says this claim can still be verified."),
                ),
            ],
            &store,
            &config,
            stage,
            dir.path(),
        );

        assert!(entry_has_quality_warning(
            &gated[0],
            "evidence_quote_not_found"
        ));
        assert_ne!(
            gated[0]
                .meta
                .get("evidence_grounded")
                .and_then(Value::as_str),
            Some("on_disk")
        );
    }

    fn entry_has_quality_warning(entry: &NewEntry, warning: &str) -> bool {
        entry
            .meta
            .get("data_quality_warnings")
            .and_then(Value::as_array)
            .is_some_and(|warnings| warnings.iter().any(|value| value.as_str() == Some(warning)))
    }

    #[tokio::test]
    async fn run_flow_creates_deterministic_source_clusters() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("task.md"), "Cluster sources.\n").unwrap();
        fs::write(
            dir.path().join("agents.json"),
            r#"{"agents":[{"id":"A1","domain":"analysis"}]}"#,
        )
        .unwrap();
        fs::create_dir_all(dir.path().join("inputs").join("alpha")).unwrap();
        fs::create_dir_all(dir.path().join("inputs").join("beta")).unwrap();
        fs::write(
            dir.path().join("inputs").join("alpha").join("one.md"),
            "Alpha source.",
        )
        .unwrap();
        fs::write(
            dir.path().join("inputs").join("beta").join("two.md"),
            "Beta source.",
        )
        .unwrap();
        fs::write(
            dir.path().join("flow.toml"),
            r#"
[flow]
profile = "cluster_flow"
policy = "fixed"

[stages.source_cluster]
inputs = ["kind:input"]
outputs = ["synthesis"]

[stages.source_cluster.clustering]
enabled = true
by = ["path_parent", "path"]
max_clusters = 4

[stages.source_cluster.actors]
mode = "none"
"#,
        )
        .unwrap();

        let result = run_flow(FlowRunOptions {
            scenario_dir: dir.path().to_path_buf(),
            config_path: None,
            budget: None,
            persist_path: None,
        })
        .await
        .unwrap();

        let clusters = result
            .entries
            .iter()
            .filter(|entry| {
                entry.meta.get("stage").and_then(Value::as_str) == Some("source_cluster")
            })
            .collect::<Vec<_>>();
        assert_eq!(clusters.len(), 2);
        assert!(clusters.iter().all(|entry| {
            entry
                .meta
                .get("source_cluster")
                .and_then(Value::as_str)
                .is_some_and(|value| value.starts_with("CLUSTER:"))
        }));
        assert!(clusters.iter().all(|entry| !entry.citations.is_empty()));
    }

    #[test]
    fn contested_map_groups_members_and_flags_divergence() {
        let artifact = ArtifactConfig {
            id: "contested_map".to_string(),
            format: "contested_map".to_string(),
            from_stage: "stances".to_string(),
            path: "outputs/contested_map.md".to_string(),
        };
        let stance = |id: &str, author: &str, text: &str, matter: &str| {
            Entry::from_new(
                id.to_string(),
                author,
                NewEntry::new(EntryType::Stance, author, text).with_meta("matter", json!(matter)),
            )
        };
        let entries = vec![
            stance("e1", "X", "Ship in Q2.", "release-timing"),
            stance("e2", "Org", "Ship in Q3.", "release-timing"),
            stance("e3", "Y", "Use Postgres.", "datastore"),
        ];

        let out = render_contested_map_artifact(&artifact, &entries);

        // Grouped by matter.
        assert!(out.contains("## release-timing"));
        assert!(out.contains("## datastore"));
        // Only the multi-party matter is flagged; the single-party one is not.
        assert_eq!(out.matches("CONTESTED").count(), 1);
        let release = out.split("## release-timing").nth(1).unwrap();
        assert!(release.contains("CONTESTED"));
        // Non-lossy: every coexisting stance is surfaced with its author.
        assert!(
            out.contains("Ship in Q2.")
                && out.contains("Ship in Q3.")
                && out.contains("Use Postgres.")
        );
        assert!(out.contains("**X**") && out.contains("**Org**") && out.contains("**Y**"));
    }
}

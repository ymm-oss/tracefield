use crate::{Entry, EntryStatus, EntryType, ReferenceStore};
use higher_graphen_core::{
    Confidence, Id as HgId, Provenance as HgProvenance, Severity as HgSeverity, SourceKind,
    SourceRef,
};
use higher_graphen_reasoning::invariant::{
    AcyclicityCheck, CheckInput, EvaluatorCheck, EvaluatorContext, EvaluatorKernel, EvaluatorRule,
};
use higher_graphen_structure::space::{
    Cell as HgCell, GraphAnalyticsInput, InMemorySpaceStore, Incidence as HgIncidence,
    IncidenceOrientation, Space as HgSpace, TraversalDirection,
};
use serde::Serialize;
use serde_json::{Map, Value};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub const STRUCTURAL_VIEW_SCHEMA: &str = "tracefield.structural_view.v1";
pub const STRUCTURAL_CHECK_REPORT_SCHEMA: &str = "tracefield.structural_check_report.v1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StructuralViewOptions {
    pub space_id: Option<String>,
    pub active_only: bool,
}

impl Default for StructuralViewOptions {
    fn default() -> Self {
        Self {
            space_id: None,
            active_only: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StructuralCheckOptions {
    pub space_id: Option<String>,
    pub active_only: bool,
    pub checks: Vec<String>,
}

impl Default for StructuralCheckOptions {
    fn default() -> Self {
        Self {
            space_id: None,
            active_only: true,
            checks: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct StructuralView {
    pub schema: String,
    pub space: StructuralSpaceSummary,
    pub cells: Vec<StructuralCell>,
    pub incidences: Vec<StructuralIncidence>,
    pub morphisms: Vec<StructuralMorphism>,
    pub obstructions: Vec<StructuralObstruction>,
    pub completion_candidates: Vec<StructuralCompletionCandidate>,
    pub invariants: Vec<StructuralInvariant>,
    pub impact_cones: Vec<StructuralImpactCone>,
    pub projections: Vec<StructuralProjection>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct StructuralSpaceSummary {
    pub id: String,
    pub kind: String,
    pub canonical_entry_count: usize,
    pub included_entry_count: usize,
    pub active_entry_count: usize,
    pub terminal_entry_count: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct StructuralCell {
    pub id: String,
    pub source_entry_id: String,
    pub cell_type: String,
    pub entry_type: String,
    pub status: String,
    pub author: String,
    pub text: String,
    pub citations: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub review_status: Option<String>,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub meta: Map<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct StructuralIncidence {
    pub id: String,
    pub relation_type: String,
    pub source_cell_id: String,
    pub target_cell_id: String,
    pub semantic: String,
    pub target_present: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct StructuralMorphism {
    pub id: String,
    pub morphism_type: String,
    pub from_cell_ids: Vec<String>,
    pub to_cell_ids: Vec<String>,
    pub provenance_entry_ids: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    pub preserved_invariants: Vec<String>,
    pub lost_structure: Vec<String>,
    pub distortion: Vec<String>,
    pub review_status: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct StructuralObstruction {
    pub id: String,
    pub obstruction_type: String,
    pub location_cell_ids: Vec<String>,
    pub witness_cell_ids: Vec<String>,
    pub related_contexts: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub severity: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub required_resolution: Option<String>,
    pub provenance: StructuralProvenance,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct StructuralCompletionCandidate {
    pub id: String,
    pub candidate_type: String,
    pub location_cell_ids: Vec<String>,
    pub text: String,
    pub provenance: StructuralProvenance,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct StructuralInvariant {
    pub id: String,
    pub invariant_type: String,
    pub location_cell_ids: Vec<String>,
    pub text: String,
    pub provenance: StructuralProvenance,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct StructuralProvenance {
    pub lens_id: String,
    pub source_entry_ids: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub confidence: Option<f64>,
    pub review_status: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct StructuralImpactCone {
    pub source_cell_id: String,
    pub citation_impact_cell_ids: Vec<String>,
    pub obstruction_impact_ids: Vec<String>,
    pub projection_impact_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct StructuralProjection {
    pub id: String,
    pub audience: String,
    pub purpose: String,
    pub input_selector: String,
    pub output_schema: String,
    pub source_entry_ids: Vec<String>,
    pub information_loss: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct StructuralCheckReport {
    pub schema: String,
    pub view_schema: String,
    pub space_id: String,
    pub summary: StructuralCheckSummary,
    pub findings: Vec<StructuralCheckFinding>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct StructuralCheckSummary {
    pub finding_count: usize,
    pub obstruction_count: usize,
    pub dangling_incidence_count: usize,
    pub unreviewed_invariant_count: usize,
    pub unreviewed_completion_candidate_count: usize,
    pub projection_loss_count: usize,
    pub highergraphen_acyclicity_count: usize,
    pub highergraphen_graph_analytics_count: usize,
    pub blocking_count: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct StructuralCheckFinding {
    pub id: String,
    pub check: String,
    pub severity: String,
    pub status: String,
    pub text: String,
    pub source_entry_ids: Vec<String>,
    pub affected_cell_ids: Vec<String>,
    pub obstruction_ids: Vec<String>,
    pub invariant_ids: Vec<String>,
    pub completion_candidate_ids: Vec<String>,
    pub projection_ids: Vec<String>,
    pub review_status: String,
}

pub fn materialize_structural_view(
    reference: &ReferenceStore,
    options: StructuralViewOptions,
) -> StructuralView {
    let space_id = options
        .space_id
        .unwrap_or_else(|| "tracefield-space:materialized-view".to_string());
    let canonical_entries = reference.all();
    let included_entries = canonical_entries
        .iter()
        .filter(|entry| !options.active_only || entry.status == EntryStatus::Active)
        .collect::<Vec<_>>();
    let included_ids = included_entries
        .iter()
        .map(|entry| entry.id.as_str())
        .collect::<BTreeSet<_>>();

    let cells = included_entries
        .iter()
        .map(|entry| StructuralCell {
            id: cell_id(&entry.id),
            source_entry_id: entry.id.clone(),
            cell_type: cell_type_label(&entry.entry_type).to_string(),
            entry_type: entry_type_label(&entry.entry_type).to_string(),
            status: status_label(&entry.status).to_string(),
            author: entry.author.clone(),
            text: entry.text.clone(),
            citations: entry.citations.clone(),
            stage: string_field(&entry.meta, "stage"),
            review_status: string_field(&entry.meta, "review_status"),
            meta: entry.meta.clone(),
        })
        .collect::<Vec<_>>();

    let mut incidences = Vec::new();
    let mut morphisms = Vec::new();
    let mut obstructions = Vec::new();
    let mut completion_candidates = Vec::new();
    let mut invariants = Vec::new();
    let mut obstruction_ids = BTreeSet::new();

    for entry in &included_entries {
        for citation in &entry.citations {
            incidences.push(StructuralIncidence {
                id: format!("incidence:{}:cites:{citation}", entry.id),
                relation_type: "citation".to_string(),
                source_cell_id: cell_id(&entry.id),
                target_cell_id: cell_id(citation),
                semantic: "source_depends_on_target".to_string(),
                target_present: included_ids.contains(citation.as_str()),
            });
        }

        for target in refutes_targets(&entry.meta) {
            incidences.push(StructuralIncidence {
                id: format!("incidence:{}:refutes:{target}", entry.id),
                relation_type: "refutes".to_string(),
                source_cell_id: cell_id(&entry.id),
                target_cell_id: cell_id(&target),
                semantic: "source_obstructs_target".to_string(),
                target_present: included_ids.contains(target.as_str()),
            });

            let obstruction = obstruction_from_refutes(entry, &target);
            if obstruction_ids.insert(obstruction.id.clone()) {
                obstructions.push(obstruction);
            }
        }

        morphisms.push(lift_morphism(entry));
        if !entry.citations.is_empty() {
            morphisms.push(derivation_morphism(entry));
        }

        if has_structural_kind(&entry.meta, "obstruction") {
            let obstruction = obstruction_from_meta(entry, obstructions.len() + 1);
            if obstruction_ids.insert(obstruction.id.clone()) {
                obstructions.push(obstruction);
            }
        }
        if has_structural_kind(&entry.meta, "completion_candidate") {
            completion_candidates.push(completion_candidate_from_meta(entry));
        }
        if has_structural_kind(&entry.meta, "invariant") {
            invariants.push(invariant_from_meta(entry));
        }
        if has_structural_kind(&entry.meta, "morphism") {
            morphisms.push(morphism_from_meta(entry));
        }
    }

    let projection_id = "projection:tracefield-structural-view".to_string();
    let impact_cones = highergraphen_impact_cones(
        &space_id,
        &cells,
        &incidences,
        &obstructions,
        &projection_id,
    )
    .unwrap_or_else(|| local_impact_cones(&included_entries, &obstructions, &projection_id));

    let source_entry_ids = included_entries
        .iter()
        .map(|entry| entry.id.clone())
        .collect::<Vec<_>>();
    let projections = vec![StructuralProjection {
        id: projection_id,
        audience: "machine".to_string(),
        purpose: "materialize a tracefield JSONL log as reviewable HigherGraphen-backed structure"
            .to_string(),
        input_selector: if options.active_only {
            "active_entries".to_string()
        } else {
            "all_entries".to_string()
        },
        output_schema: STRUCTURAL_VIEW_SCHEMA.to_string(),
        source_entry_ids,
        information_loss: vec![
            "Entry text is preserved, but domain-specific semantics are not parsed unless supplied through typed metadata.".to_string(),
            "Citations are represented as dependency incidences; citation intent beyond dependency is not inferred.".to_string(),
            "Only explicit meta.refutes or meta.kind structural markers become obstruction, invariant, or completion records.".to_string(),
        ],
    }];

    let active_entry_count = canonical_entries
        .iter()
        .filter(|entry| entry.status == EntryStatus::Active)
        .count();

    StructuralView {
        schema: STRUCTURAL_VIEW_SCHEMA.to_string(),
        space: StructuralSpaceSummary {
            id: space_id,
            kind: "tracefield_run_space".to_string(),
            canonical_entry_count: canonical_entries.len(),
            included_entry_count: included_entries.len(),
            active_entry_count,
            terminal_entry_count: canonical_entries.len().saturating_sub(active_entry_count),
        },
        cells,
        incidences,
        morphisms,
        obstructions,
        completion_candidates,
        invariants,
        impact_cones,
        projections,
    }
}

pub fn run_structural_checks(
    reference: &ReferenceStore,
    options: StructuralCheckOptions,
) -> StructuralCheckReport {
    let checks = normalize_check_set(&options.checks);
    let view = materialize_structural_view(
        reference,
        StructuralViewOptions {
            space_id: options.space_id,
            active_only: options.active_only,
        },
    );
    let mut findings = Vec::new();

    if check_enabled(&checks, "obstruction_presence") {
        for obstruction in &view.obstructions {
            let severity = obstruction
                .severity
                .clone()
                .unwrap_or_else(|| "medium".to_string());
            let status = if matches!(severity.as_str(), "high" | "critical") {
                "blocked"
            } else {
                "needs_review"
            };
            let resolution = obstruction
                .required_resolution
                .as_deref()
                .unwrap_or("review and resolve before promotion");
            findings.push(StructuralCheckFinding {
                id: format!("structural_check:obstruction:{}", obstruction.id),
                check: "obstruction_presence".to_string(),
                severity,
                status: status.to_string(),
                text: format!(
                    "Obstruction {} ({}) is present; required resolution: {}",
                    obstruction.id, obstruction.obstruction_type, resolution
                ),
                source_entry_ids: obstruction.provenance.source_entry_ids.clone(),
                affected_cell_ids: obstruction.location_cell_ids.clone(),
                obstruction_ids: vec![obstruction.id.clone()],
                invariant_ids: Vec::new(),
                completion_candidate_ids: Vec::new(),
                projection_ids: Vec::new(),
                review_status: obstruction.provenance.review_status.clone(),
            });
        }
    }

    if check_enabled(&checks, "dangling_incidence") {
        for incidence in view
            .incidences
            .iter()
            .filter(|incidence| !incidence.target_present)
        {
            findings.push(StructuralCheckFinding {
                id: format!("structural_check:dangling_incidence:{}", incidence.id),
                check: "dangling_incidence".to_string(),
                severity: "high".to_string(),
                status: "blocked".to_string(),
                text: format!(
                    "Incidence {} points at missing target {}",
                    incidence.id, incidence.target_cell_id
                ),
                source_entry_ids: vec![entry_id_from_cell_id(&incidence.source_cell_id)],
                affected_cell_ids: vec![
                    incidence.source_cell_id.clone(),
                    incidence.target_cell_id.clone(),
                ],
                obstruction_ids: Vec::new(),
                invariant_ids: Vec::new(),
                completion_candidate_ids: Vec::new(),
                projection_ids: Vec::new(),
                review_status: "unreviewed".to_string(),
            });
        }
    }

    if check_enabled(&checks, "unreviewed_invariant") {
        for invariant in view
            .invariants
            .iter()
            .filter(|invariant| invariant.provenance.review_status == "unreviewed")
        {
            findings.push(StructuralCheckFinding {
                id: format!("structural_check:unreviewed_invariant:{}", invariant.id),
                check: "unreviewed_invariant".to_string(),
                severity: "medium".to_string(),
                status: "needs_review".to_string(),
                text: format!(
                    "Invariant {} ({}) is unreviewed",
                    invariant.id, invariant.invariant_type
                ),
                source_entry_ids: invariant.provenance.source_entry_ids.clone(),
                affected_cell_ids: invariant.location_cell_ids.clone(),
                obstruction_ids: Vec::new(),
                invariant_ids: vec![invariant.id.clone()],
                completion_candidate_ids: Vec::new(),
                projection_ids: Vec::new(),
                review_status: invariant.provenance.review_status.clone(),
            });
        }
    }

    if check_enabled(&checks, "unreviewed_completion_candidate") {
        for candidate in view
            .completion_candidates
            .iter()
            .filter(|candidate| candidate.provenance.review_status == "unreviewed")
        {
            findings.push(StructuralCheckFinding {
                id: format!(
                    "structural_check:unreviewed_completion_candidate:{}",
                    candidate.id
                ),
                check: "unreviewed_completion_candidate".to_string(),
                severity: "low".to_string(),
                status: "needs_review".to_string(),
                text: format!(
                    "Completion candidate {} ({}) is unreviewed",
                    candidate.id, candidate.candidate_type
                ),
                source_entry_ids: candidate.provenance.source_entry_ids.clone(),
                affected_cell_ids: candidate.location_cell_ids.clone(),
                obstruction_ids: Vec::new(),
                invariant_ids: Vec::new(),
                completion_candidate_ids: vec![candidate.id.clone()],
                projection_ids: Vec::new(),
                review_status: candidate.provenance.review_status.clone(),
            });
        }
    }

    if check_enabled(&checks, "projection_loss") {
        for projection in view
            .projections
            .iter()
            .filter(|projection| !projection.information_loss.is_empty())
        {
            findings.push(StructuralCheckFinding {
                id: format!("structural_check:projection_loss:{}", projection.id),
                check: "projection_loss".to_string(),
                severity: "info".to_string(),
                status: "declared".to_string(),
                text: format!(
                    "Projection {} declares {} information-loss item(s)",
                    projection.id,
                    projection.information_loss.len()
                ),
                source_entry_ids: projection.source_entry_ids.clone(),
                affected_cell_ids: Vec::new(),
                obstruction_ids: Vec::new(),
                invariant_ids: Vec::new(),
                completion_candidate_ids: Vec::new(),
                projection_ids: vec![projection.id.clone()],
                review_status: "declared".to_string(),
            });
        }
    }

    if check_enabled(&checks, "highergraphen_acyclicity") {
        findings.extend(highergraphen_acyclicity_findings(&view));
    }

    if check_enabled(&checks, "highergraphen_graph_analytics") {
        findings.extend(highergraphen_graph_analytics_findings(&view));
    }

    let summary = StructuralCheckSummary {
        finding_count: findings.len(),
        obstruction_count: findings
            .iter()
            .filter(|finding| finding.check == "obstruction_presence")
            .count(),
        dangling_incidence_count: findings
            .iter()
            .filter(|finding| finding.check == "dangling_incidence")
            .count(),
        unreviewed_invariant_count: findings
            .iter()
            .filter(|finding| finding.check == "unreviewed_invariant")
            .count(),
        unreviewed_completion_candidate_count: findings
            .iter()
            .filter(|finding| finding.check == "unreviewed_completion_candidate")
            .count(),
        projection_loss_count: findings
            .iter()
            .filter(|finding| finding.check == "projection_loss")
            .count(),
        highergraphen_acyclicity_count: findings
            .iter()
            .filter(|finding| finding.check == "highergraphen_acyclicity")
            .count(),
        highergraphen_graph_analytics_count: findings
            .iter()
            .filter(|finding| finding.check == "highergraphen_graph_analytics")
            .count(),
        blocking_count: findings
            .iter()
            .filter(|finding| finding.status == "blocked")
            .count(),
    };

    StructuralCheckReport {
        schema: STRUCTURAL_CHECK_REPORT_SCHEMA.to_string(),
        view_schema: view.schema,
        space_id: view.space.id,
        summary,
        findings,
    }
}

fn normalize_check_set(checks: &[String]) -> BTreeSet<String> {
    if checks.is_empty() {
        return [
            "obstruction_presence",
            "dangling_incidence",
            "unreviewed_invariant",
            "unreviewed_completion_candidate",
            "highergraphen_acyclicity",
        ]
        .into_iter()
        .map(ToOwned::to_owned)
        .collect();
    }

    checks
        .iter()
        .map(|check| match check.trim() {
            "obstruction" | "obstructions" => "obstruction_presence",
            "dangling" | "dangling_citation" | "dangling_incidence" => "dangling_incidence",
            "invariant" | "invariants" => "unreviewed_invariant",
            "completion_candidate" | "completion_candidates" => "unreviewed_completion_candidate",
            "projection" | "projection_loss" => "projection_loss",
            "acyclicity" | "citation_acyclicity" | "hg_acyclicity" | "highergraphen_acyclicity" => {
                "highergraphen_acyclicity"
            }
            "graph_analytics"
            | "hg_graph_analytics"
            | "highergraphen_graph_analytics"
            | "centrality"
            | "central_cells"
            | "dominators"
            | "cut_sets"
            | "impact_cone" => "highergraphen_graph_analytics",
            other => other,
        })
        .filter(|check| !check.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn check_enabled(checks: &BTreeSet<String>, check: &str) -> bool {
    checks.contains("all") || checks.contains(check)
}

struct HigherGraphenLift {
    space_id: HgId,
    store: InMemorySpaceStore,
}

fn highergraphen_impact_cones(
    space_id: &str,
    cells: &[StructuralCell],
    incidences: &[StructuralIncidence],
    obstructions: &[StructuralObstruction],
    projection_id: &str,
) -> Option<Vec<StructuralImpactCone>> {
    let lift = build_highergraphen_space(space_id, cells, incidences).ok()?;
    let obstruction_reverse = obstruction_reverse_index(obstructions);
    let mut impact_cones = Vec::new();

    for cell in cells {
        let seed = hg_id(&cell.id).ok()?;
        let input = GraphAnalyticsInput::new(lift.space_id.clone())
            .with_seed_cell_ids([seed])
            .in_direction(TraversalDirection::Incoming)
            .with_relation_type("citation")
            .ok()?;
        let report = lift.store.analyze_graph(&input).ok()?;
        let citation_impact_cell_ids = report
            .impact_cone_cell_ids
            .iter()
            .map(hg_id_string)
            .filter(|id| id != &cell.id)
            .collect::<Vec<_>>();
        let obstruction_impact_ids = obstruction_reverse
            .get(cell.id.as_str())
            .cloned()
            .unwrap_or_default();
        let projection_impact_ids =
            if citation_impact_cell_ids.is_empty() && obstruction_impact_ids.is_empty() {
                Vec::new()
            } else {
                vec![projection_id.to_string()]
            };

        impact_cones.push(StructuralImpactCone {
            source_cell_id: cell.id.clone(),
            citation_impact_cell_ids,
            obstruction_impact_ids,
            projection_impact_ids,
        });
    }

    Some(impact_cones)
}

fn local_impact_cones(
    included_entries: &[&Entry],
    obstructions: &[StructuralObstruction],
    projection_id: &str,
) -> Vec<StructuralImpactCone> {
    let citation_reverse = citation_reverse_index(included_entries);
    let obstruction_reverse = obstruction_reverse_index(obstructions);

    included_entries
        .iter()
        .map(|entry| {
            let impacted_entries = downstream_entries(&entry.id, &citation_reverse);
            let citation_impact_cell_ids = impacted_entries
                .iter()
                .map(|id| cell_id(id))
                .collect::<Vec<_>>();
            let obstruction_impact_ids = obstruction_reverse
                .get(cell_id(&entry.id).as_str())
                .cloned()
                .unwrap_or_default();
            let projection_impact_ids =
                if citation_impact_cell_ids.is_empty() && obstruction_impact_ids.is_empty() {
                    Vec::new()
                } else {
                    vec![projection_id.to_string()]
                };

            StructuralImpactCone {
                source_cell_id: cell_id(&entry.id),
                citation_impact_cell_ids,
                obstruction_impact_ids,
                projection_impact_ids,
            }
        })
        .collect()
}

fn highergraphen_acyclicity_findings(view: &StructuralView) -> Vec<StructuralCheckFinding> {
    let lift = match build_highergraphen_space(&view.space.id, &view.cells, &view.incidences) {
        Ok(lift) => lift,
        Err(error) => {
            return vec![highergraphen_error_finding(
                "highergraphen_acyclicity",
                error,
            )];
        }
    };

    let invariant_id = match hg_id("invariant:tracefield:citation_acyclicity") {
        Ok(id) => id,
        Err(error) => {
            return vec![highergraphen_error_finding(
                "highergraphen_acyclicity",
                error.to_string(),
            )];
        }
    };
    let kernel = EvaluatorKernel::new().with_rule(EvaluatorRule::invariant(
        invariant_id,
        HgSeverity::High,
        EvaluatorCheck::Acyclicity(AcyclicityCheck::new().with_relation_type("citation")),
    ));
    let check_input = CheckInput::new(lift.space_id.clone());
    let context = EvaluatorContext::new(&check_input, &lift.store);
    let report = match kernel.evaluate(&context) {
        Ok(report) => report,
        Err(error) => {
            return vec![highergraphen_error_finding(
                "highergraphen_acyclicity",
                error.to_string(),
            )];
        }
    };

    report
        .results
        .iter()
        .filter_map(|result| {
            let violation = result.violation()?;
            let affected_cell_ids = hg_ids_to_strings(&violation.location_cell_ids);
            let severity = violation.severity.as_str().to_string();
            Some(StructuralCheckFinding {
                id: format!(
                    "structural_check:highergraphen_acyclicity:{}",
                    result.target_id()
                ),
                check: "highergraphen_acyclicity".to_string(),
                severity: severity.clone(),
                status: if matches!(severity.as_str(), "high" | "critical") {
                    "blocked".to_string()
                } else {
                    "needs_review".to_string()
                },
                text: format!(
                    "HigherGraphen evaluator found a citation acyclicity violation: {}",
                    violation.message
                ),
                source_entry_ids: entry_ids_from_cell_ids(&affected_cell_ids),
                affected_cell_ids,
                obstruction_ids: Vec::new(),
                invariant_ids: vec![result.target_id().as_str().to_string()],
                completion_candidate_ids: Vec::new(),
                projection_ids: Vec::new(),
                review_status: "unreviewed".to_string(),
            })
        })
        .collect()
}

fn highergraphen_graph_analytics_findings(view: &StructuralView) -> Vec<StructuralCheckFinding> {
    let lift = match build_highergraphen_space(&view.space.id, &view.cells, &view.incidences) {
        Ok(lift) => lift,
        Err(error) => {
            return vec![highergraphen_error_finding(
                "highergraphen_graph_analytics",
                error,
            )];
        }
    };
    let input = match GraphAnalyticsInput::new(lift.space_id.clone())
        .in_direction(TraversalDirection::Incoming)
        .with_relation_type("citation")
    {
        Ok(input) => input,
        Err(error) => {
            return vec![highergraphen_error_finding(
                "highergraphen_graph_analytics",
                error.to_string(),
            )];
        }
    };
    let report = match lift.store.analyze_graph(&input) {
        Ok(report) => report,
        Err(error) => {
            return vec![highergraphen_error_finding(
                "highergraphen_graph_analytics",
                error.to_string(),
            )];
        }
    };

    let mut findings = Vec::new();
    for score in report
        .centrality_scores
        .iter()
        .filter(|score| score.outgoing_degree > 0)
        .take(3)
    {
        let cell_id = score.cell_id.as_str().to_string();
        findings.push(StructuralCheckFinding {
            id: format!("structural_check:highergraphen_graph_analytics:centrality:{cell_id}"),
            check: "highergraphen_graph_analytics".to_string(),
            severity: "info".to_string(),
            status: "informational".to_string(),
            text: format!(
                "HigherGraphen graph analytics ranks {cell_id} as a central downstream-impact cell with {} selected outgoing neighbor(s)",
                score.outgoing_degree
            ),
            source_entry_ids: entry_ids_from_cell_ids(std::slice::from_ref(&cell_id)),
            affected_cell_ids: vec![cell_id],
            obstruction_ids: Vec::new(),
            invariant_ids: Vec::new(),
            completion_candidate_ids: Vec::new(),
            projection_ids: Vec::new(),
            review_status: "computed".to_string(),
        });
    }

    for cut_cell_id in report.cut_cell_candidate_ids.iter().take(5) {
        let cell_id = cut_cell_id.as_str().to_string();
        findings.push(StructuralCheckFinding {
            id: format!("structural_check:highergraphen_graph_analytics:cut_cell:{cell_id}"),
            check: "highergraphen_graph_analytics".to_string(),
            severity: "medium".to_string(),
            status: "needs_review".to_string(),
            text: format!(
                "HigherGraphen graph analytics marks {cell_id} as a cut-cell candidate in the citation impact graph"
            ),
            source_entry_ids: entry_ids_from_cell_ids(std::slice::from_ref(&cell_id)),
            affected_cell_ids: vec![cell_id],
            obstruction_ids: Vec::new(),
            invariant_ids: Vec::new(),
            completion_candidate_ids: Vec::new(),
            projection_ids: Vec::new(),
            review_status: "computed".to_string(),
        });
    }

    findings.extend(highergraphen_dominator_findings(&lift, &view.cells));
    findings
}

fn highergraphen_dominator_findings(
    lift: &HigherGraphenLift,
    cells: &[StructuralCell],
) -> Vec<StructuralCheckFinding> {
    let mut findings = Vec::new();
    for cell in cells {
        let Ok(seed) = hg_id(&cell.id) else {
            continue;
        };
        let Ok(input) = GraphAnalyticsInput::new(lift.space_id.clone())
            .with_seed_cell_ids([seed])
            .in_direction(TraversalDirection::Incoming)
            .with_relation_type("citation")
        else {
            continue;
        };
        let Ok(report) = lift.store.analyze_graph(&input) else {
            continue;
        };
        for candidate in report
            .dominator_candidates
            .iter()
            .filter(|candidate| candidate.dominated_cell_ids.len() >= 2)
            .take(1)
        {
            let dominator_id = candidate.dominator_cell_id.as_str().to_string();
            let dominated_cell_ids = hg_ids_to_strings(&candidate.dominated_cell_ids);
            let mut affected_cell_ids = vec![dominator_id.clone()];
            affected_cell_ids.extend(dominated_cell_ids.clone());
            affected_cell_ids.sort();
            affected_cell_ids.dedup();
            findings.push(StructuralCheckFinding {
                id: format!(
                    "structural_check:highergraphen_graph_analytics:dominator:{}:{}",
                    cell.id, dominator_id
                ),
                check: "highergraphen_graph_analytics".to_string(),
                severity: "medium".to_string(),
                status: "needs_review".to_string(),
                text: format!(
                    "HigherGraphen graph analytics finds {dominator_id} dominates {} downstream cell(s) in the impact cone from {}",
                    dominated_cell_ids.len(),
                    cell.id
                ),
                source_entry_ids: entry_ids_from_cell_ids(&affected_cell_ids),
                affected_cell_ids,
                obstruction_ids: Vec::new(),
                invariant_ids: Vec::new(),
                completion_candidate_ids: Vec::new(),
                projection_ids: Vec::new(),
                review_status: "computed".to_string(),
            });
        }
        if findings.len() >= 5 {
            break;
        }
    }
    findings
}

fn build_highergraphen_space(
    space_id: &str,
    cells: &[StructuralCell],
    incidences: &[StructuralIncidence],
) -> std::result::Result<HigherGraphenLift, String> {
    let space_id = hg_id(space_id).map_err(|error| error.to_string())?;
    let mut store = InMemorySpaceStore::new();
    store
        .insert_space(HgSpace::new(
            space_id.clone(),
            "tracefield materialized structural view",
        ))
        .map_err(|error| error.to_string())?;

    for cell in cells {
        let hg_cell = HgCell::new(
            hg_id(&cell.id).map_err(|error| error.to_string())?,
            space_id.clone(),
            0,
            cell.cell_type.clone(),
        )
        .with_label(cell.source_entry_id.clone())
        .with_provenance(hg_provenance(cell));
        store
            .insert_cell(hg_cell)
            .map_err(|error| error.to_string())?;
    }

    for incidence in incidences
        .iter()
        .filter(|incidence| incidence.target_present)
    {
        let hg_incidence = HgIncidence::new(
            hg_id(&incidence.id).map_err(|error| error.to_string())?,
            space_id.clone(),
            hg_id(&incidence.source_cell_id).map_err(|error| error.to_string())?,
            hg_id(&incidence.target_cell_id).map_err(|error| error.to_string())?,
            incidence.relation_type.clone(),
            IncidenceOrientation::Directed,
        );
        store
            .insert_incidence(hg_incidence)
            .map_err(|error| error.to_string())?;
    }

    Ok(HigherGraphenLift { space_id, store })
}

fn hg_provenance(cell: &StructuralCell) -> HgProvenance {
    let source = SourceRef::new(SourceKind::Ai)
        .with_source_local_id(cell.source_entry_id.clone())
        .unwrap_or_else(|_| SourceRef::new(SourceKind::Ai));
    let confidence = cell
        .meta
        .get("confidence")
        .and_then(Value::as_f64)
        .unwrap_or(1.0)
        .clamp(0.0, 1.0);
    HgProvenance::new(
        source,
        Confidence::new(confidence).expect("clamped confidence is valid"),
    )
}

fn hg_id(value: &str) -> higher_graphen_core::Result<HgId> {
    HgId::new(value)
}

fn hg_id_string(id: &HgId) -> String {
    id.as_str().to_string()
}

fn hg_ids_to_strings(ids: &[HgId]) -> Vec<String> {
    ids.iter().map(hg_id_string).collect()
}

fn entry_ids_from_cell_ids(cell_ids: &[String]) -> Vec<String> {
    let mut entry_ids = cell_ids
        .iter()
        .map(|cell_id| entry_id_from_cell_id(cell_id))
        .collect::<Vec<_>>();
    entry_ids.sort();
    entry_ids.dedup();
    entry_ids
}

fn highergraphen_error_finding(check: &str, error: impl Into<String>) -> StructuralCheckFinding {
    StructuralCheckFinding {
        id: format!("structural_check:{check}:engine_error"),
        check: check.to_string(),
        severity: "high".to_string(),
        status: "blocked".to_string(),
        text: format!(
            "HigherGraphen core algorithm could not run: {}",
            error.into()
        ),
        source_entry_ids: Vec::new(),
        affected_cell_ids: Vec::new(),
        obstruction_ids: Vec::new(),
        invariant_ids: Vec::new(),
        completion_candidate_ids: Vec::new(),
        projection_ids: Vec::new(),
        review_status: "unreviewed".to_string(),
    }
}

fn entry_id_from_cell_id(cell_id: &str) -> String {
    cell_id.strip_prefix("cell:").unwrap_or(cell_id).to_string()
}

fn cell_id(entry_id: &str) -> String {
    if entry_id.starts_with("cell:") {
        entry_id.to_string()
    } else {
        format!("cell:{entry_id}")
    }
}

fn entry_type_label(entry_type: &EntryType) -> &'static str {
    match entry_type {
        EntryType::Belief => "belief",
        EntryType::Hypothesis => "hypothesis",
        EntryType::Observation => "observation",
        EntryType::Stance => "stance",
        EntryType::Decision => "decision",
        EntryType::Question => "question",
        EntryType::Requirement => "requirement",
        EntryType::Answer => "answer",
        EntryType::Change => "change",
        EntryType::Verdict => "verdict",
        EntryType::Chunk => "chunk",
        EntryType::CorpusChunk => "corpus_chunk",
        EntryType::Procedure => "procedure",
        EntryType::Claim => "claim",
        EntryType::Synthesis => "synthesis",
        EntryType::Audit => "audit",
    }
}

fn cell_type_label(entry_type: &EntryType) -> &'static str {
    match entry_type {
        EntryType::Claim => "claim_cell",
        EntryType::Observation => "observation_cell",
        EntryType::Decision => "decision_cell",
        EntryType::Verdict => "verdict_cell",
        EntryType::Requirement => "requirement_cell",
        EntryType::Change => "change_cell",
        EntryType::Question => "question_cell",
        EntryType::Procedure => "procedure_cell",
        EntryType::CorpusChunk | EntryType::Chunk => "source_cell",
        _ => "entry_cell",
    }
}

fn status_label(status: &EntryStatus) -> &'static str {
    match status {
        EntryStatus::Active => "active",
        EntryStatus::Retracted => "retracted",
        EntryStatus::Superseded => "superseded",
    }
}

fn string_field(meta: &Map<String, Value>, key: &str) -> Option<String> {
    meta.get(key).and_then(Value::as_str).map(ToOwned::to_owned)
}

fn string_field_any(meta: &Map<String, Value>, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| string_field(meta, key))
}

fn string_array_field(meta: &Map<String, Value>, key: &str) -> Vec<String> {
    meta.get(key)
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn string_array_field_any(meta: &Map<String, Value>, keys: &[&str]) -> Vec<String> {
    keys.iter()
        .flat_map(|key| string_array_field(meta, key))
        .collect()
}

fn confidence(meta: &Map<String, Value>) -> Option<f64> {
    meta.get("confidence").and_then(Value::as_f64)
}

fn review_status(meta: &Map<String, Value>) -> String {
    string_field(meta, "review_status").unwrap_or_else(|| "unreviewed".to_string())
}

fn has_structural_kind(meta: &Map<String, Value>, expected: &str) -> bool {
    ["kind", "structural_kind"]
        .iter()
        .filter_map(|key| meta.get(*key).and_then(Value::as_str))
        .any(|value| value == expected)
}

fn refutes_targets(meta: &Map<String, Value>) -> Vec<String> {
    match meta.get("refutes") {
        Some(Value::Array(values)) => values
            .iter()
            .filter_map(Value::as_str)
            .map(ToOwned::to_owned)
            .collect(),
        Some(Value::String(id)) => vec![id.clone()],
        _ => Vec::new(),
    }
}

fn cell_refs_from_meta(meta: &Map<String, Value>) -> Vec<String> {
    [
        "location_cell_ids",
        "location_cells",
        "target_cell_ids",
        "target_entries",
    ]
    .iter()
    .flat_map(|key| string_array_field(meta, key))
    .map(|id| cell_id(&id))
    .collect()
}

fn provenance(entry: &Entry, source_entry_ids: Vec<String>) -> StructuralProvenance {
    StructuralProvenance {
        lens_id: entry.author.clone(),
        source_entry_ids,
        confidence: confidence(&entry.meta),
        review_status: review_status(&entry.meta),
    }
}

fn obstruction_from_refutes(entry: &Entry, target: &str) -> StructuralObstruction {
    StructuralObstruction {
        id: format!("obstruction:{}:refutes:{target}", entry.id),
        obstruction_type: "refutation".to_string(),
        location_cell_ids: vec![cell_id(target)],
        witness_cell_ids: vec![cell_id(&entry.id)],
        related_contexts: string_array_field(&entry.meta, "related_contexts"),
        severity: string_field(&entry.meta, "severity"),
        required_resolution: string_field(&entry.meta, "required_resolution"),
        provenance: provenance(entry, vec![entry.id.clone(), target.to_string()]),
    }
}

fn obstruction_from_meta(entry: &Entry, sequence: usize) -> StructuralObstruction {
    let location_cell_ids = {
        let explicit = cell_refs_from_meta(&entry.meta);
        if explicit.is_empty() {
            entry
                .citations
                .iter()
                .map(|citation| cell_id(citation))
                .collect()
        } else {
            explicit
        }
    };
    let obstruction_type = string_field_any(&entry.meta, &["obstruction_type", "type"])
        .unwrap_or_else(|| {
            if has_structural_kind(&entry.meta, "obstruction") {
                "obstruction".to_string()
            } else {
                "unknown".to_string()
            }
        });

    StructuralObstruction {
        id: string_field(&entry.meta, "id")
            .unwrap_or_else(|| format!("obstruction:{}:{sequence}", entry.id)),
        obstruction_type,
        location_cell_ids,
        witness_cell_ids: vec![cell_id(&entry.id)],
        related_contexts: string_array_field(&entry.meta, "related_contexts"),
        severity: string_field(&entry.meta, "severity"),
        required_resolution: string_field(&entry.meta, "required_resolution"),
        provenance: provenance(entry, vec![entry.id.clone()]),
    }
}

fn completion_candidate_from_meta(entry: &Entry) -> StructuralCompletionCandidate {
    StructuralCompletionCandidate {
        id: string_field(&entry.meta, "id")
            .unwrap_or_else(|| format!("completion_candidate:{}", entry.id)),
        candidate_type: string_field_any(&entry.meta, &["candidate_type", "type"])
            .unwrap_or_else(|| "completion_candidate".to_string()),
        location_cell_ids: cell_refs_from_meta(&entry.meta),
        text: entry.text.clone(),
        provenance: provenance(entry, vec![entry.id.clone()]),
    }
}

fn invariant_from_meta(entry: &Entry) -> StructuralInvariant {
    StructuralInvariant {
        id: string_field(&entry.meta, "id").unwrap_or_else(|| format!("invariant:{}", entry.id)),
        invariant_type: string_field_any(&entry.meta, &["invariant_type", "type"])
            .unwrap_or_else(|| "invariant".to_string()),
        location_cell_ids: cell_refs_from_meta(&entry.meta),
        text: entry.text.clone(),
        provenance: provenance(entry, vec![entry.id.clone()]),
    }
}

fn morphism_from_meta(entry: &Entry) -> StructuralMorphism {
    let from_cell_ids = {
        let explicit = string_array_field_any(
            &entry.meta,
            &["from_cell_ids", "source_cell_ids", "source_cells"],
        );
        if explicit.is_empty() {
            entry
                .citations
                .iter()
                .map(|citation| cell_id(citation))
                .collect()
        } else {
            explicit.into_iter().map(|id| cell_id(&id)).collect()
        }
    };
    let to_cell_ids = {
        let explicit = string_array_field_any(
            &entry.meta,
            &["to_cell_ids", "target_cell_ids", "target_cells"],
        );
        if explicit.is_empty() {
            vec![cell_id(&entry.id)]
        } else {
            explicit.into_iter().map(|id| cell_id(&id)).collect()
        }
    };

    StructuralMorphism {
        id: string_field(&entry.meta, "id").unwrap_or_else(|| format!("morphism:{}", entry.id)),
        morphism_type: string_field_any(&entry.meta, &["morphism_type", "type"])
            .unwrap_or_else(|| "morphism".to_string()),
        from_cell_ids,
        to_cell_ids,
        provenance_entry_ids: vec![entry.id.clone()],
        stage: string_field(&entry.meta, "stage"),
        preserved_invariants: string_array_field(&entry.meta, "preserved_invariants"),
        lost_structure: string_array_field(&entry.meta, "lost_structure"),
        distortion: string_array_field(&entry.meta, "distortion"),
        review_status: review_status(&entry.meta),
    }
}

fn lift_morphism(entry: &Entry) -> StructuralMorphism {
    StructuralMorphism {
        id: format!("morphism:lift:{}", entry.id),
        morphism_type: "tracefield_entry_lift".to_string(),
        from_cell_ids: Vec::new(),
        to_cell_ids: vec![cell_id(&entry.id)],
        provenance_entry_ids: vec![entry.id.clone()],
        stage: string_field(&entry.meta, "stage"),
        preserved_invariants: vec![
            "entry_id".to_string(),
            "entry_type".to_string(),
            "entry_status".to_string(),
            "citations".to_string(),
            "raw_text".to_string(),
            "metadata".to_string(),
        ],
        lost_structure: vec![
            "domain semantics not present in typed metadata remain uninterpreted".to_string(),
        ],
        distortion: Vec::new(),
        review_status: review_status(&entry.meta),
    }
}

fn derivation_morphism(entry: &Entry) -> StructuralMorphism {
    StructuralMorphism {
        id: format!("morphism:derive:{}", entry.id),
        morphism_type: "citation_derivation".to_string(),
        from_cell_ids: entry.citations.iter().map(|id| cell_id(id)).collect(),
        to_cell_ids: vec![cell_id(&entry.id)],
        provenance_entry_ids: vec![entry.id.clone()],
        stage: string_field(&entry.meta, "stage"),
        preserved_invariants: vec!["declared_citation_dependency".to_string()],
        lost_structure: vec!["citation role is not inferred beyond dependency".to_string()],
        distortion: Vec::new(),
        review_status: review_status(&entry.meta),
    }
}

fn citation_reverse_index(entries: &[&Entry]) -> BTreeMap<String, Vec<String>> {
    let mut reverse = BTreeMap::<String, Vec<String>>::new();
    for entry in entries {
        for citation in &entry.citations {
            reverse
                .entry(citation.clone())
                .or_default()
                .push(entry.id.clone());
        }
    }
    for children in reverse.values_mut() {
        children.sort();
    }
    reverse
}

fn downstream_entries(source_id: &str, reverse: &BTreeMap<String, Vec<String>>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut queue = VecDeque::from([source_id.to_string()]);

    while let Some(current) = queue.pop_front() {
        if let Some(children) = reverse.get(&current) {
            for child in children {
                if seen.insert(child.clone()) {
                    queue.push_back(child.clone());
                }
            }
        }
    }

    seen.into_iter().collect()
}

fn obstruction_reverse_index(
    obstructions: &[StructuralObstruction],
) -> BTreeMap<String, Vec<String>> {
    let mut reverse = BTreeMap::<String, Vec<String>>::new();
    for obstruction in obstructions {
        for cell_id in obstruction
            .location_cell_ids
            .iter()
            .chain(obstruction.witness_cell_ids.iter())
        {
            reverse
                .entry(cell_id.clone())
                .or_default()
                .push(obstruction.id.clone());
        }
    }
    for ids in reverse.values_mut() {
        ids.sort();
        ids.dedup();
    }
    reverse
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::NewEntry;
    use serde_json::json;

    #[test]
    fn materializes_entries_as_cells_incidences_and_obstructions() {
        let mut store = ReferenceStore::new();
        let claim = store.push(
            NewEntry::new(EntryType::Claim, "risk", "base claim"),
            "risk",
        );
        let refutation = store.push(
            NewEntry::new(EntryType::Observation, "legal", "consent scope mismatch")
                .with_citations(vec![claim.id.clone()])
                .with_meta("stage", json!("analysis"))
                .with_meta("refutes", json!(claim.id.clone()))
                .with_meta("severity", json!("high")),
            "legal",
        );

        let view = materialize_structural_view(&store, StructuralViewOptions::default());

        assert_eq!(view.schema, STRUCTURAL_VIEW_SCHEMA);
        assert_eq!(view.cells.len(), 2);
        assert_eq!(view.incidences.len(), 2);
        assert!(view.incidences.iter().any(|incidence| {
            incidence.relation_type == "citation"
                && incidence.source_cell_id == cell_id(&refutation.id)
                && incidence.target_cell_id == cell_id(&claim.id)
        }));
        assert_eq!(view.obstructions.len(), 1);
        assert_eq!(
            view.obstructions[0].location_cell_ids,
            vec![cell_id(&claim.id)]
        );
        assert_eq!(view.obstructions[0].severity.as_deref(), Some("high"));

        let claim_cone = view
            .impact_cones
            .iter()
            .find(|cone| cone.source_cell_id == cell_id(&claim.id))
            .unwrap();
        assert_eq!(
            claim_cone.citation_impact_cell_ids,
            vec![cell_id(&refutation.id)]
        );
        assert_eq!(
            claim_cone.obstruction_impact_ids,
            vec![format!(
                "obstruction:{}:refutes:{}",
                refutation.id, claim.id
            )]
        );
    }

    #[test]
    fn active_only_view_excludes_terminal_cells_without_mutating_canonical_count() {
        let mut store = ReferenceStore::new();
        let source = store.push(NewEntry::new(EntryType::Claim, "a", "source"), "a");
        let active = store.push(
            NewEntry::new(EntryType::Observation, "b", "active").with_citations(vec![]),
            "b",
        );
        store.retract(&source.id, "operator").unwrap();

        let view = materialize_structural_view(
            &store,
            StructuralViewOptions {
                space_id: Some("space:test".to_string()),
                active_only: true,
            },
        );

        assert_eq!(view.space.id, "space:test");
        assert_eq!(view.space.canonical_entry_count, 2);
        assert_eq!(view.cells.len(), 1);
        assert_eq!(view.cells[0].source_entry_id, active.id);
        assert_eq!(view.projections[0].input_selector, "active_entries");
    }

    #[test]
    fn structural_checks_surface_blocking_obstructions() {
        let mut store = ReferenceStore::new();
        let source = store.push(NewEntry::new(EntryType::Claim, "a", "source"), "a");
        store.push(
            NewEntry::new(EntryType::Audit, "risk", "obstruction")
                .with_citations(vec![source.id.clone()])
                .with_meta("kind", json!("obstruction"))
                .with_meta("obstruction_type", json!("consent_scope_mismatch"))
                .with_meta("location_cell_ids", json!([source.id.clone()]))
                .with_meta("severity", json!("high"))
                .with_meta("required_resolution", json!("clarify consent")),
            "risk",
        );

        let report = run_structural_checks(
            &store,
            StructuralCheckOptions {
                checks: vec!["obstruction_presence".to_string()],
                ..StructuralCheckOptions::default()
            },
        );

        assert_eq!(report.schema, STRUCTURAL_CHECK_REPORT_SCHEMA);
        assert_eq!(report.summary.finding_count, 1);
        assert_eq!(report.summary.blocking_count, 1);
        assert_eq!(report.findings[0].status, "blocked");
        assert_eq!(
            report.findings[0].affected_cell_ids,
            vec![cell_id(&source.id)]
        );
    }

    #[test]
    fn highergraphen_evaluator_detects_citation_cycles() {
        let mut store = ReferenceStore::new();
        store.push(
            NewEntry::new(EntryType::Claim, "a", "first").with_citations(vec!["e2".to_string()]),
            "a",
        );
        store.push(
            NewEntry::new(EntryType::Claim, "b", "second").with_citations(vec!["e1".to_string()]),
            "b",
        );

        let report = run_structural_checks(
            &store,
            StructuralCheckOptions {
                checks: vec!["hg_acyclicity".to_string()],
                ..StructuralCheckOptions::default()
            },
        );

        assert_eq!(report.summary.finding_count, 1);
        assert_eq!(report.summary.highergraphen_acyclicity_count, 1);
        assert_eq!(report.summary.blocking_count, 1);
        assert_eq!(report.findings[0].check, "highergraphen_acyclicity");
        assert!(report.findings[0].text.contains("HigherGraphen evaluator"));
        assert_eq!(
            report.findings[0].invariant_ids,
            vec!["invariant:tracefield:citation_acyclicity"]
        );
    }

    #[test]
    fn highergraphen_graph_analytics_drives_impact_and_dominator_findings() {
        let mut store = ReferenceStore::new();
        let root = store.push(NewEntry::new(EntryType::Claim, "root", "root"), "root");
        let bridge = store.push(
            NewEntry::new(EntryType::Claim, "bridge", "bridge")
                .with_citations(vec![root.id.clone()]),
            "bridge",
        );
        let leaf_a = store.push(
            NewEntry::new(EntryType::Claim, "leaf-a", "leaf a")
                .with_citations(vec![bridge.id.clone()]),
            "leaf-a",
        );
        let leaf_b = store.push(
            NewEntry::new(EntryType::Claim, "leaf-b", "leaf b")
                .with_citations(vec![bridge.id.clone()]),
            "leaf-b",
        );

        let view = materialize_structural_view(&store, StructuralViewOptions::default());
        let root_cone = view
            .impact_cones
            .iter()
            .find(|cone| cone.source_cell_id == cell_id(&root.id))
            .unwrap();
        assert_eq!(
            root_cone.citation_impact_cell_ids,
            vec![
                cell_id(&bridge.id),
                cell_id(&leaf_a.id),
                cell_id(&leaf_b.id)
            ]
        );

        let report = run_structural_checks(
            &store,
            StructuralCheckOptions {
                checks: vec!["hg_graph_analytics".to_string()],
                ..StructuralCheckOptions::default()
            },
        );

        assert!(report.summary.highergraphen_graph_analytics_count >= 1);
        assert!(report.findings.iter().any(|finding| {
            finding.check == "highergraphen_graph_analytics"
                && finding.text.contains("dominates 2 downstream cell")
        }));
    }
}

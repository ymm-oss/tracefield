# Impl brief — machine-grounded reading: per-stage `grounded` + on-disk evidence-quote resolution

> Goal: complete tracefield's hallucination-suppression method for **reading code and documents**.
> The engine already has a proven anti-hallucination check (machine-verified `meta.evidence_quote`
> must be a literal substring of the cited source — the mechanism that drove citation precision
> 0.40→1.00 in `findings-citation-precision.md`). Two things stop it from covering reading tasks:
>
> 1. **Unreachable on the canonical reading stages.** The check runs only when
>    `is_source_grounded_stage()` (`flow.rs:2772`) returns true — a brittle name heuristic
>    (`source_`/`web`/`data` in stage id/organ/role). The canonical `analysis → verify →
>    adjudication` code-reading stages — and **every** `fsl-codespec` stage — don't match it,
>    so their claims get citation-validity scrubbing but **no substring check**.
> 2. **Cannot verify code read off disk.** `evidence_quote_found_in_citations()` (`flow.rs:2812`)
>    checks the quote against the *cited store entry's text*. In code-reading scenarios the cited
>    entry is a **pointer** (`scenarios/fsl-codespec/inputs/region-*.md`: `path:`+`lines:`), and the
>    real code lives on disk; the actor re-opens it. So the quote is never in the cited entry and
>    the check can't apply.
>
> The fix is **one unified gate**: make grounding a per-stage opt-in, and let the quote resolve
> against the cited store entry **or** an on-disk source the claim names. In-store and on-disk
> grounding are the same substring-against-source logic differing only in where the source
> resolves — so they MUST be one consolidated check, not two mechanisms.

Scope: **`crates/tracefield-core/src/flow.rs` only.** No new dependencies. Do not touch the read
path / selectors / aggregate. Keep the existing name heuristic working (existing scenarios rely
on it) — only ADD the explicit flag and the on-disk source resolution.

## Change 1 — per-stage `grounded` flag

- Add field to `StageConfig` (struct at `flow.rs:162`, after `retract_overturned` at `:177`):
  ```rust
  /// Opt in to source-grounding discipline (evidence-quote contract + machine verification)
  /// regardless of stage/organ/role naming. See is_source_grounded_stage.
  pub grounded: bool,
  ```
- Parse it where stages are built (`flow.rs:698`, alongside `retract_overturned` at `:709`):
  ```rust
  grounded: bool_value(&values, "grounded").unwrap_or(false),
  ```
- Set `grounded: false` in every other `StageConfig { .. }` literal so it compiles:
  `process_stage_config` (`flow.rs:1350`) and the test literals (`flow.rs:5194`, `:6467`, and any
  others the compiler flags).
- In `is_source_grounded_stage` (`flow.rs:2772`) add at the very top:
  ```rust
  if stage.grounded {
      return true;
  }
  ```

That alone makes the **in-store** evidence-quote contract + check reachable on any stage (covers
**document** reading where sources are seeded as store chunks).

## Change 2 — on-disk source resolution (covers code read off disk)

When the in-store quote check fails, also try the on-disk source the claim names.

- Thread the scenario directory into the gate. Change `apply_core_gates` signature
  (`flow.rs:2629`) to add `scenario_dir: &Path`. Update the 6 production call sites
  (`flow.rs:921, 954, 1051, 1073, 1215, 1322`) to pass `&scenario.dir` (each is inside `run_stage`,
  which has `scenario` in scope — see `flow.rs:3234` `scenario.dir`). Update the test call sites
  (`flow.rs:6280, 6341, 6939, 7001, 7070`) to pass a `Path` (e.g. a `tempfile::tempdir()` path, or
  the existing test `scenario_dir`).
- Add ONE consolidated grounding check and route both existing call sites (`flow.rs:2698, 2713`)
  and `repair_evidence_quote`'s check (`flow.rs:2843`) through it:
  ```rust
  /// Quote is grounded if it appears in a cited store entry OR in the on-disk source the
  /// claim names via meta.source_path (+ optional meta.source_line). One substring rule, two
  /// source resolutions.
  fn quote_grounded(
      store: &ReferenceStore,
      scenario_dir: &Path,
      citations: &[String],
      meta: &Map<String, Value>,
      quote: &str,
  ) -> bool {
      evidence_quote_found_in_citations(store, citations, quote)
          || quote_found_on_disk(scenario_dir, meta, quote)
  }

  fn quote_found_on_disk(scenario_dir: &Path, meta: &Map<String, Value>, quote: &str) -> bool {
      let Some(rel) = meta.get("source_path").and_then(Value::as_str) else {
          return false;
      };
      let parts = evidence_quote_parts(quote);
      if parts.is_empty() {
          return false;
      }
      let path = scenario_dir.join(rel);
      // read-only substring check; never copy file content into the store.
      let Ok(meta_fs) = std::fs::metadata(&path) else {
          return false;
      };
      if !meta_fs.is_file() {
          return false;
      }
      let Ok(content) = std::fs::read_to_string(&path) else {
          return false;
      };
      // Optional: if meta.source_line is present, restrict to a +/-40-line window around it
      // before normalizing; otherwise scan the whole file. (A window reduces false positives
      // from the quote appearing elsewhere; out-of-range line -> whole file.)
      let haystack = normalize_evidence_text(&window_around(&content, line_of(meta)));
      parts
          .iter()
          .all(|part| haystack.contains(&normalize_evidence_text(part)))
  }
  ```
  Helpers `window_around(content, Option<usize>)` (return the ±40-line slice, or the whole file
  when `None`/out of range) and `line_of(meta)` (read `meta.source_line` as usize) are small and
  local. Reuse the existing `evidence_quote_parts` and `normalize_evidence_text`.
- In `apply_core_gates`, replace the two `evidence_quote_found_in_citations(store, &entry.citations, ..)`
  calls (`:2698`, `:2713`) with `quote_grounded(store, scenario_dir, &entry.citations, &entry.meta, ..)`.
  In `repair_evidence_quote` (`:2833`) the post-repair check at `:2843` should likewise accept
  on-disk grounding (thread `scenario_dir` + `&entry.meta` in, or inline the same OR).
- When grounded specifically via disk, stamp `entry.meta["evidence_grounded"] = json!("on_disk")`
  (purely informational provenance; do not stamp when grounded in-store — preserve current
  behavior/tests there).

**Safety:** the engine reads only a file the read-only agent already re-opened; resolve relative
to `scenario_dir`, read regular files only, and **never** store file content (the only output is
the existing boolean → warning). An unreadable / nonexistent / non-file `source_path` → treated as
not-grounded (warning), never an error that stops the run.

## Change 3 — contract text

In `SOURCE_GROUNDING_CONTRACT` (`flow.rs:4036`) append one sentence so grounded code-reading
actors emit the locator (harmless for in-store document stages, which simply omit it):

> "If the claim is grounded in a file you re-opened rather than in inline CONTEXT text, also set
> meta.source_path to that file's path relative to the scenario directory and meta.source_line to
> the line number, and copy meta.evidence_quote verbatim from that file."

## Tests (add to the existing gate test module ~`flow.rs:6900-7110`)

1. `grounded_flag_enables_evidence_quote_gate` — a stage with `id="analysis"` (does NOT match the
   name heuristic) + `grounded: true`: an entry with a fabricated `evidence_quote` not present in
   its cited entry gets `data_quality_warnings` containing `evidence_quote_not_found`. With
   `grounded: false` the same entry gets no such warning (proves the flag is what enables it).
2. `on_disk_evidence_quote_grounds_claim` — `tempdir()` with a file `src.rs` containing a known
   prose/code line; an entry (citing nothing useful in-store) with `meta.source_path="src.rs"`,
   `meta.source_line=<n>`, and `meta.evidence_quote` = a verbatim substring of that line → **no**
   `evidence_quote_not_found` warning and `meta.evidence_grounded=="on_disk"`. A fabricated quote
   not in the file → `evidence_quote_not_found`.
3. `on_disk_missing_source_path_does_not_panic` — `source_path` pointing at a nonexistent file →
   treated as not-grounded (warning), run does not error.

## Verify

```sh
cargo fmt
cargo clippy -p tracefield-core
cargo test -p tracefield-core
```

All existing tests must stay green (the name-heuristic path and in-store check are unchanged;
the flag and on-disk path are additive). Report the new test names + pass/fail.

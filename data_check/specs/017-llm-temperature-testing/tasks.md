# Tasks: LLM Temperature Stability Testing (017)

**Input**: Design documents from `specs/017-llm-temperature-testing/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓

**Tests**: No test tasks — not requested in the feature specification.

**Organization**: Tasks are grouped by user story. Phases A–B are foundational (blocking all stories).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (independent files/concerns)
- **[Story]**: User story label (US1–US4)

---

## Phase 1: Setup

**Purpose**: `.gitignore` update and file stubs so subsequent phases have targets to write into.

- [x] T001 Add `data_check/sweep_results/` to `.gitignore` at `/Volumes/Models/dev/metacheck-datacheck/.gitignore`
- [x] T002 [P] Create empty stub `data_check/run_sweep.R` with file header comment and `main()` stub
- [x] T003 [P] Create empty stub `data_check/report_sweep.R` with file header comment and `main()` stub

---

## Phase 2: Foundational — Pipeline Modifications (Blocking Prerequisites)

**Purpose**: Thread temperature and output_dir through the existing pipeline. Must complete before any sweep can run.

**⚠️ CRITICAL**: All US1–US4 phases depend on this phase being complete.

- [x] T004 Modify `llm_batch()` in `data_check/helper.R` — before `raw <- llm(...)` call, add: `llm_params <- if (!is.null(getOption("llm_temperature"))) list(temperature = getOption("llm_temperature")) else list()`; pass `params = llm_params` to `llm()`; no change to function signature
- [x] T005 Modify the three standalone `llm()` calls inside `run_codebook_label()` in `data_check/2_codebook_label.R` (label merge prompt ~line 728, column match prompt ~line 790, codebook parse loop ~line 584) — add same `llm_params` pattern before each call and pass `params = llm_params`
- [x] T006 Add `output_dir = NULL` parameter to `run_index()` in `data_check/0_index.R` — at top of function body add: `eff_dir <- if (!is.null(output_dir)) { dir.create(output_dir, recursive = TRUE, showWarnings = FALSE); output_dir } else paper_output_dir(paper_id)`; replace every `paper_output_dir(paper_id)` call inside `run_index()` with `eff_dir`
- [x] T007 Add `output_dir = NULL` parameter to `run_codebook_label()` in `data_check/2_codebook_label.R` — same `eff_dir` pattern as T006; replace every `paper_output_dir(paper_id)` call inside `run_codebook_label()` with `eff_dir`

**Checkpoint**: Call `run_index(paper_id = "0956797615620784", output_dir = "/tmp/test_sweep_out")` and confirm outputs land in `/tmp/test_sweep_out/`, not in `outputs/`.

---

## Phase 3: User Story 1 — Temperature Sweep Runner (Priority: P1) 🎯 MVP

**Goal**: Run a full sweep for one paper at N temperatures × R repeats, saving isolated outputs and a crash-resilient log.

**Independent Test**: `Rscript run_sweep.R --paper-id 0956797615620784 --temperatures 0.0,0.3 --repeats 2 --sweep-dir /tmp/test_sweep` → 4 run directories created under `/tmp/test_sweep/0956797615620784/`, `sweep_log.csv` has 4 rows, all with `status == "ok"`.

- [x] T008 [US1] Implement `parse_sweep_args()` in `data_check/run_sweep.R` — parse `--paper-id` (required, character), `--temperatures` (comma-sep numerics, default `"0.0,0.3,0.7,1.0"`), `--repeats` (integer ≥ 1, default `3`), `--sweep-dir` (path, default `"./sweep_results"`); validate temperatures in [0, 2] and reject with error if any out of range
- [x] T009 [US1] Implement `load_or_create_sweep_log(log_path)` in `data_check/run_sweep.R` — if file exists, read with `colClasses = c(paper_id = "character")`; if not, return empty data frame with columns: `paper_id, temperature, repeat_num, output_dir, status, error, elapsed_ms, run_timestamp`
- [x] T010 [US1] Implement `sweep_run_done(log_df, paper_id, temperature, repeat_num)` helper in `data_check/run_sweep.R` — returns TRUE if matching row exists in log_df
- [x] T011 [US1] Implement `run_one(paper_id, temperature, repeat_num, sweep_base_dir)` in `data_check/run_sweep.R`:
  - Build run_dir: `file.path(sweep_base_dir, paper_id, sprintf("temp_%.1f", temperature), sprintf("rep_%d", repeat_num))`
  - `dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)`
  - `options(llm_temperature = temperature)`
  - Call `run_index(paper_id, output_dir = run_dir)` inside `tryCatch`
  - If index succeeded: call `run_codebook_label(paper_id, output_dir = run_dir)` inside `tryCatch`
  - `options(llm_temperature = NULL)`
  - Return list with `status`, `error`, `elapsed_ms`, `run_timestamp`, `output_dir`
- [x] T012 [US1] Implement `append_sweep_log(log_path, row)` in `data_check/run_sweep.R` — appends one row to `sweep_log.csv`; creates file with header if absent; uses `write.table(..., append = TRUE, col.names = !file.exists(log_path))`
- [x] T013 [US1] Implement `main()` in `data_check/run_sweep.R` — orchestrate: parse args → source pipeline scripts → for each (temperature, repeat): skip if done, call `run_one`, append log, print progress `[T=X rep Y/R] status (Zs)`; print final summary
- [x] T014 [US1] Verify resume behaviour in `data_check/run_sweep.R` — add a comment/note confirming that re-running with same args skips all completed combinations (verified by `sweep_run_done()` check)

**Checkpoint**: 2 temps × 2 repeats sweep runs end-to-end on a known paper; `sweep_log.csv` has 4 rows; re-running produces no new rows.

---

## Phase 4: User Story 2 — Stability Report (Priority: P2)

**Goal**: Compute and display pairwise label-agreement rates across repeats per temperature.

**Independent Test**: `Rscript report_sweep.R --sweep-dir /tmp/test_sweep/0956797615620784 --sections stability` → table showing col_type agreement per temperature; T=0.0 shows 100% (or near-100%) agreement.

- [x] T015 [US2] Implement `parse_report_args()` in `data_check/report_sweep.R` — parse `--sweep-dir` (required), `--stability-weight` (numeric 0–1, default `0.5`), `--sections` (comma-sep: `overview,stability,quality,recommendation,all`, default `all`)
- [x] T016 [US2] Implement `load_run_columns(run_dir)` in `data_check/report_sweep.R` — reads `columns.csv` from a run directory; returns data frame with `column_name, source_file, col_type`; returns NULL if file absent
- [x] T017 [US2] Implement `load_run_labels(run_dir)` in `data_check/report_sweep.R` — reads `labels.csv` from run directory; returns data frame with `column_name, label`; returns NULL if absent
- [x] T018 [US2] Implement `pairwise_agreement(df_a, df_b, label_col)` in `data_check/report_sweep.R` — joins two data frames on `(column_name, source_file)`, computes fraction of rows where `label_col` matches; columns in one but not the other count as disagreement (add NA partner rows before joining); returns numeric 0–1
- [x] T019 [US2] Implement `compute_stability(sweep_log_df, sweep_dir)` in `data_check/report_sweep.R` — for each temperature: load all ok-repeat column and label files; compute all pairwise `col_type` agreement rates and mean them; same for `label` if labels present; return data frame with columns `temperature, col_type_agreement, label_agreement, n_pairs, n_columns_compared`; warn and return NA stability if <2 repeats
- [x] T020 [US2] Implement `section_stability(stability_df)` in `data_check/report_sweep.R` — print formatted table sorted by `col_type_agreement` descending; warn if any temperature had <2 ok repeats

**Checkpoint**: Stability section prints correctly from a completed sweep directory.

---

## Phase 5: User Story 3 — Quality Comparison (Priority: P3)

**Goal**: Compute and display per-temperature quality proxy metrics (known-type rate, codebook coverage, non-empty label rate).

**Independent Test**: `Rscript report_sweep.R --sweep-dir /tmp/test_sweep/0956797615620784 --sections quality` → table with three proxy metrics per temperature; no crash if codebook absent (shows N/A).

- [x] T021 [US3] Implement `load_run_coverage(run_dir)` in `data_check/report_sweep.R` — reads `codebook_coverage.csv`; returns data frame or NULL (absent = N/A, not 0%)
- [x] T022 [US3] Implement `compute_quality(sweep_log_df, sweep_dir)` in `data_check/report_sweep.R` — for each temperature: over ok-repeats, compute mean of (1) known-type rate from `columns.csv`, (2) coverage rate from `codebook_coverage.csv` (NA if absent), (3) non-empty label rate from `labels.csv` (NA if absent); return data frame with `temperature, known_type_rate, codebook_coverage_rate, nonempty_label_rate, n_repeats_used`
- [x] T023 [US3] Implement `section_quality(quality_df)` in `data_check/report_sweep.R` — print formatted table; display N/A for missing metrics

**Checkpoint**: Quality section prints correctly; papers without codebook show N/A, not 0%.

---

## Phase 6: User Story 4 — Recommendation (Priority: P4)

**Goal**: Produce a single recommended temperature from the combined stability + quality score.

**Independent Test**: `Rscript report_sweep.R --sweep-dir /tmp/test_sweep/0956797615620784 --sections recommendation` → names a single temperature (or tied list) with score breakdown.

- [x] T024 [US4] Implement `compute_recommendation(stability_df, quality_df, w_stab)` in `data_check/report_sweep.R`:
  - Normalise `col_type_agreement` to [0,1] (already is); use as stability component
  - Normalise quality metrics: mean of available non-NA proxy metrics per temperature → [0,1] quality score; if all proxies NA, quality = NA
  - `combined = w_stab * stability + (1 - w_stab) * quality`; if quality is NA, use stability only with a warning
  - Return data frame sorted by `combined` descending; flag ties (temperatures within 0.001 of top score)
- [x] T025 [US4] Implement `section_recommendation(rec_df, w_stab)` in `data_check/report_sweep.R` — print winner (or tied list); print score breakdown table; note if <2 temperatures tested

**Checkpoint**: Recommendation names the correct temperature when comparing 4 known temperatures with synthetic data.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Wire all report sections, add mandatory .md output, sweep overview section, end-to-end validation.

- [x] T026 Implement `section_sweep_overview(sweep_log_df)` in `data_check/report_sweep.R` — print run counts per temperature (attempted/succeeded/failed), total elapsed time, resume status
- [x] T027 Implement `main()` in `data_check/report_sweep.R` — parse args → load sweep_log.csv → call sections per `active_sections` → capture output + write `sweep_report_YYYY-MM-DD.md` to `--sweep-dir` (same pattern as `report_quality.R`)
- [x] T028 [P] Verify all CSV reads in `run_sweep.R` and `report_sweep.R` use `colClasses = c(paper_id = "character")` — constitution Principle II audit
- [x] T029 [P] Verify `options(llm_temperature = NULL)` is always cleared after each run in `run_sweep.R` — including in error/exception paths (use `on.exit(options(llm_temperature = NULL))`)
- [ ] T030 Run a 2-temperature × 2-repeat sweep on paper `0956797615620784` end-to-end; run `report_sweep.R`; confirm `sweep_report_YYYY-MM-DD.md` is created with all four sections

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies
- **Foundational (Phase 2)**: Requires Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Requires Phase 2 — sweep runner needs modified pipeline
- **US2–US4 (Phases 4–6)**: Require Phase 3 (need a completed sweep directory to read from); can be developed independently of each other using any existing sweep output
- **Polish (Phase 7)**: Requires all story phases complete

### User Story Dependencies

- **US1**: Depends on Phases 1 + 2 only
- **US2, US3, US4**: Each depends only on Phase 3 (a sweep directory); they are independent of each other and can be developed in parallel

### Within Each Phase

- T002 and T003 (Phase 1) are parallel — different files
- T004–T007 (Phase 2) must be sequential — T004 before T005 (both in helper/codebook), T006 before T007 (different files but T007 needs T006's pattern as reference)
- T015–T020 (Phase 4): T015 first (parse args), then T016–T018 can be parallel (different helpers), then T019 (uses them), then T020

---

## Parallel Opportunities

```r
# Phase 1: stubs are independent files
T002: create run_sweep.R stub
T003: create report_sweep.R stub

# Phase 2: helper.R and 0_index.R changes are independent
T004 (helper.R llm_batch)  ← independent
T006 (0_index.R output_dir) ← independent

# Phase 4: loader helpers are independent
T016: load_run_columns    ← independent
T017: load_run_labels     ← independent
T021: load_run_coverage   ← independent (belongs to Phase 5 but can be written alongside T016/T017)

# Phase 7: T028 and T029 are independent audits
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1: Setup stubs + .gitignore (T001–T003)
2. Phase 2: Pipeline modifications (T004–T007) — verify with checkpoint
3. Phase 3: Sweep runner (T008–T014) — verify end-to-end
4. **STOP and VALIDATE**: `run_sweep.R` produces 4 isolated output directories with correct data
5. Add reporting (Phases 4–6) incrementally

### Incremental Delivery

1. Phases 1–2 → pipeline accepts temperature + isolated output_dir
2. Phase 3 → sweep runner works → MVP
3. Phase 4 → stability report added
4. Phase 5 → quality report added
5. Phase 6 → recommendation added
6. Phase 7 → full report wired, .md output, end-to-end validated

---

## Notes

- Two new files: `data_check/run_sweep.R`, `data_check/report_sweep.R`
- Three modified files: `data_check/helper.R`, `data_check/0_index.R`, `data_check/2_codebook_label.R`
- `paper_id` MUST be character everywhere — constitution Principle II
- `options(llm_temperature)` MUST be cleared via `on.exit()` — T029
- `sweep_results/` MUST be in `.gitignore` — T001
- No new R packages; `ellmer::params(temperature = X)` is already available via metacheck dependency

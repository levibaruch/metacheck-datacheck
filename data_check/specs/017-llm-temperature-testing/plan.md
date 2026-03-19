# Implementation Plan: LLM Temperature Stability Testing

**Branch**: `017-llm-temperature-testing` | **Date**: 2026-03-19 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/017-llm-temperature-testing/spec.md`

## Summary

A sweep toolkit that runs one paper through the full pipeline (index + codebook labelling) N times at each of M temperatures, isolates outputs per (temperature, repeat), and then reports stability (pairwise label agreement), quality proxies (known-type rate, coverage, label completeness), and a weighted recommendation. Requires minimal modifications to existing pipeline entry points (`run_index`, `run_codebook_label`, `llm_batch`) and adds two new scripts (`run_sweep.R`, `report_sweep.R`).

## Technical Context

**Language/Version**: R (base R only — no new packages)
**Primary Dependencies**: `metacheck` (`llm()`), `ellmer` (temperature via `params`) — both already installed; `haven`, `readxl`, `jsonlite` — already present
**Storage**: CSV files on local filesystem — `sweep_results/<paper_id>/sweep_log.csv` + per-run output directories
**Testing**: Manual end-to-end run on one paper (2 temperatures × 2 repeats = 4 runs); spot-check stability at T=0.0
**Target Platform**: macOS/Linux (same as existing pipeline); run from `data_check/` directory
**Project Type**: CLI scripts (`Rscript run_sweep.R`, `Rscript report_sweep.R`)
**Performance Goals**: 4-run sweep (2 temps × 2 repeats) completes without manual intervention
**Constraints**: Base R only; no contamination of `outputs/` directory; crash-resilient (Principle I); paper_id always character (Principle II)
**Scale/Scope**: Designed for 1 paper × 4 temperatures × 3 repeats = 12 runs as primary use case

## Constitution Check

| Principle | Status | Notes |
|---|---|---|
| I. Crash Resilience | ✅ Required | `sweep_log.csv` appended after each run; resume skips completed combinations |
| II. Paper ID Preservation | ✅ Required | `paper_id` as character throughout; `colClasses` on all CSV reads |
| III. Resource Limits | ✅ Inherited | `run_index()` already enforces all limits; sweep inherits them per run |
| IV. Centralised Shared Helpers | ✅ Compliant | Temperature option check added to `llm_batch()` in `helper.R`; no duplication |
| V. Structured Error Codes | ✅ Compliant | Failed sweep runs use existing error codes from `run_index()`; recorded in `sweep_log.csv` |

**Gate result**: PASS. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/017-llm-temperature-testing/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code

```text
data_check/
├── helper.R                  # MODIFIED — add temperature option to llm_batch()
├── 0_index.R                 # MODIFIED — add output_dir param to run_index()
├── 2_codebook_label.R        # MODIFIED — add output_dir param + temperature option
├── run_sweep.R               # NEW — sweep runner
└── report_sweep.R            # NEW — stability/quality/recommendation report

sweep_results/                # Created at runtime, gitignored
  <paper_id>/
    sweep_log.csv
    temp_0.0/rep_1/
    temp_0.0/rep_2/
    temp_0.3/rep_1/
    ...
```

**Structure Decision**: Two new entry-point scripts at repo root. Shared modifications to `helper.R` and the two pipeline scripts only. `sweep_results/` added to `.gitignore`.

## Implementation Phases

### Phase A: Pipeline modifications (foundational)

**A1 — helper.R `llm_batch()`**: Before `raw <- llm(...)`, read `getOption("llm_temperature")`. Pass `params = list(temperature = getOption("llm_temperature"))` to `llm()` when non-NULL, otherwise `params = list()`.

**A2 — 2_codebook_label.R standalone `llm()` calls**: Apply same temperature option check to the three `llm()` calls in `run_codebook_label()`. Pattern: `params_arg <- if (!is.null(getOption("llm_temperature"))) list(temperature = getOption("llm_temperature")) else list()`.

**A3 — 0_index.R `run_index()`**: Add `output_dir = NULL` param. Derive `eff_dir` at top of body: `if (!is.null(output_dir)) { dir.create(output_dir, recursive = TRUE, showWarnings = FALSE); output_dir } else paper_output_dir(paper_id)`. Replace all `paper_output_dir(paper_id)` calls inside `run_index()` with `eff_dir`.

**A4 — 2_codebook_label.R `run_codebook_label()`**: Add `output_dir = NULL` param. Same `eff_dir` pattern. Replace `paper_output_dir(paper_id)` inside this function with `eff_dir`.

---

### Phase B: run_sweep.R

CLI: `Rscript run_sweep.R --paper-id <ID> [--temperatures 0.0,0.3,0.7,1.0] [--repeats 3] [--sweep-dir ./sweep_results]`

1. Parse and validate args (temperatures numeric 0–2; repeats ≥ 1; paper_id non-empty character)
2. Source `helper.R`, `0_index.R`, `2_codebook_label.R`
3. Load or create `sweep_log.csv`; deduplicate on (paper_id, temperature, repeat_num)
4. For each (temperature, repeat): skip if in log; set option; run index + codebook; clear option; append log row
5. Directory naming: temperature `0.3` → directory `temp_0.3`, repeat 2 → `rep_2`

---

### Phase C: report_sweep.R

CLI: `Rscript report_sweep.R --sweep-dir ./sweep_results/<paper_id> [--stability-weight 0.5]`

Always writes `sweep_report_YYYY-MM-DD.md` to `--sweep-dir`.

- Section 1: Sweep overview (run counts per temperature, failures)
- Section 2: Stability (pairwise col_type + label agreement per temperature, sorted descending)
- Section 3: Quality proxies (known-type rate, codebook coverage, non-empty label rate per temperature)
- Section 4: Recommendation (combined score, winner or tied list, score breakdown)

---

## Complexity Tracking

No constitution violations.

# Data Model: LLM Temperature Stability Testing (017)

**Date**: 2026-03-19
**Branch**: `017-llm-temperature-testing`

---

## Modified Entities (existing pipeline)

### run_index() — modified signature

`run_index(paper_id, download = TRUE, output_dir = NULL)`

- New `output_dir` parameter: when non-NULL, all output files written to this path instead of `paper_output_dir(paper_id)`. Caller is responsible for creating the directory.
- All existing call sites pass no `output_dir` argument → NULL → unchanged behaviour.

### run_codebook_label() — modified signature

`run_codebook_label(paper_id, output_dir = NULL)`

- New `output_dir` parameter: same semantics as `run_index()`.
- Reads `structure.csv` and `columns.csv` from `output_dir` when provided; writes `labels.csv` and `codebook_coverage.csv` there.

### llm_batch() in helper.R — modified behaviour

- Reads `getOption("llm_temperature")` before each `llm()` call; if non-NULL, passes `params = list(temperature = getOption("llm_temperature"))` to `llm()`.
- Standalone `llm()` calls in `2_codebook_label.R` updated with the same option check.

---

## New Entities

### SweepLog (sweep_log.csv)

**Location**: `sweep_results/<paper_id>/sweep_log.csv`

One row per attempted (paper_id, temperature, repeat) combination. Written incrementally after each run (crash-resilient — Principle I).

| Field | Type | Notes |
|---|---|---|
| `paper_id` | character | Always character (Principle II) |
| `temperature` | numeric | The temperature value used |
| `repeat_num` | integer | Repeat index (1-based) |
| `output_dir` | character | Relative path to this run's output directory |
| `status` | character | `"ok"` or `"failed"` |
| `error` | character or NA | Error message if `status == "failed"` |
| `elapsed_ms` | integer | Total wall time for this run |
| `run_timestamp` | character | ISO datetime of run start |

**Validation rules**:
- `paper_id` MUST be read with `colClasses = c(paper_id = "character")`
- `temperature` encoded in directory name as `temp_<T>` (e.g. `temp_0.3`)
- Resume check: if a row exists for (paper_id, temperature, repeat_num), skip that combination

---

### SweepRunDir

**Location**: `sweep_results/<paper_id>/temp_<T>/rep_<R>/`

One directory per (temperature, repeat) run. Contains the standard pipeline outputs:

| File | Source | Used for |
|---|---|---|
| `columns.csv` | `run_index()` | Stability (col_type) + quality (known-type rate) |
| `codebook_coverage.csv` | `run_codebook_label()` | Quality (codebook coverage rate); absent = N/A |
| `labels.csv` | `run_codebook_label()` | Quality (non-empty label rate) |
| `structure.csv` | `run_index()` | Not used in reporting; present for completeness |

---

### StabilityResult

Computed in-memory by `report_sweep.R` from pairwise comparison of `columns.csv` files.

| Field | Type | Notes |
|---|---|---|
| `temperature` | numeric | The temperature being scored |
| `col_type_agreement` | numeric | Mean pairwise col_type agreement rate (0–1) |
| `label_agreement` | numeric or NA | Mean pairwise codebook label agreement rate; NA if no codebook |
| `n_pairs` | integer | Number of repeat pairs compared |
| `n_columns_compared` | integer | Total columns matched across all pairs |

**Pairwise matching**: columns matched by `(column_name, source_file)` pair. Columns in one run but not the other count as disagreement.

---

### QualityResult

Computed in-memory by `report_sweep.R` per temperature.

| Field | Type | Notes |
|---|---|---|
| `temperature` | numeric | The temperature being scored |
| `known_type_rate` | numeric | Mean across repeats of (non-unknown cols / total cols) |
| `codebook_coverage_rate` | numeric or NA | Mean across repeats; NA if no codebook for this paper |
| `nonempty_label_rate` | numeric or NA | Mean across repeats; NA if no codebook |
| `n_repeats_used` | integer | Repeats with `status == "ok"` |

---

### SweepRecommendation

| Field | Type | Notes |
|---|---|---|
| `temperature` | numeric | Recommended temperature(s) |
| `combined_score` | numeric | `w_stab * stability + w_qual * quality` (0–1) |
| `stability_score` | numeric | Weighted component |
| `quality_score` | numeric | Weighted component |
| `is_tied` | logical | TRUE if multiple temperatures share top score |

---

## Processing Order

```
run_sweep.R:
  1. Parse args (paper_id, temperatures, repeats, output base dir)
  2. Validate temperature values (numeric, 0 ≤ T ≤ 2)
  3. Load or create sweep_log.csv; deduplicate existing entries
  4. For each (temperature, repeat):
     a. Skip if already in sweep_log
     b. Set options(llm_temperature = temperature)
     c. Create run output directory: sweep_results/<paper_id>/temp_<T>/rep_<R>/
     d. Call run_index(paper_id, output_dir = run_dir)
     e. If run_index succeeded: call run_codebook_label(paper_id, output_dir = run_dir)
     f. Clear options(llm_temperature = NULL)
     g. Append row to sweep_log.csv
  5. Print summary on completion

report_sweep.R:
  1. Parse args (sweep_dir, stability-weight)
  2. Load sweep_log.csv
  3. For each temperature: load all ok-status repeat outputs
  4. Compute StabilityResult per temperature
  5. Compute QualityResult per temperature
  6. Compute SweepRecommendation
  7. Print all sections to console
  8. Write sweep_report_YYYY-MM-DD.md to sweep_dir
```

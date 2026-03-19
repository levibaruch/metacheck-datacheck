# Research: LLM Temperature Stability Testing (017)

**Date**: 2026-03-19
**Branch**: `017-llm-temperature-testing`

---

## Decision 1: How to pass temperature to the LLM

**Decision**: Use `options(llm_temperature = X)` as a process-level setting before each pipeline run, and read it inside `llm_batch()` (and standalone `llm()` calls in `2_codebook_label.R`). Clear the option after each run.

**Rationale**: `llm()` (from metacheck) accepts `params = list(temperature = X)` which is forwarded to `ellmer::params(temperature = X)`. `llm_batch()` in `helper.R` currently calls `llm()` without `params`. The option approach requires changing only `llm_batch()` and the two standalone `llm()` calls in `2_codebook_label.R` — no parameter threading through `run_index()` or `run_codebook_label()`. Verified: `ellmer::params` signature includes `temperature = NULL`.

**Alternatives considered**:
- Thread `temperature` as a parameter through `run_index()` → `llm_batch()` → `llm()` — requires touching every llm_batch call site across both scripts; higher blast radius
- Set temperature globally via `llm_model()` — no global temperature setter in the current API; not feasible without deeper metacheck internals

---

## Decision 2: How to redirect output per sweep run

**Decision**: Add `output_dir = NULL` parameter to `run_index()` and `run_codebook_label()`. When non-NULL, use the provided path directly instead of `paper_output_dir(paper_id)`. Caller must ensure the directory exists.

**Rationale**: `paper_output_dir()` in `helper.R` is hardcoded to `./data_check/outputs/<paper_id>`. The sweep needs each (temperature, repeat) to write to an isolated location. Adding one `output_dir` parameter to both entry points is minimal and preserves all existing call sites (they pass `NULL`, falling through to the current behaviour).

**Alternatives considered**:
- Temporarily override `OUTPUT_DIR` global — fragile; not thread-safe; violates encapsulation
- Copy outputs after each run — wastes I/O; still pollutes `outputs/` with mixed data

---

## Decision 3: Sweep directory structure

**Decision**:
```
sweep_results/
  <paper_id>/
    sweep_log.csv              # one row per (temp, repeat); always appended
    temp_0.0/rep_1/            # outputs from run_index + run_codebook_label
      structure.csv
      columns.csv
      labels.csv
      codebook_coverage.csv
    temp_0.0/rep_2/
    temp_0.3/rep_1/
    ...
```

**Rationale**: Temperature values are encoded directly in the directory name for human readability. The `sweep_log.csv` is the single source of truth for what has run; its presence is what determines resume behaviour (same as `bulk_summary.csv` for the bulk runner — Principle I applied here).

**Alternatives considered**:
- Flat directory with encoded filenames (e.g. `columns_t0.0_r1.csv`) — harder to use existing pipeline functions that expect a directory
- Database/JSON log — over-engineered; CSV is consistent with the rest of the pipeline

---

## Decision 4: Resume behaviour

**Decision**: Before starting each (temperature, repeat) combination, check `sweep_log.csv` for an existing row with matching `paper_id`, `temperature`, and `repeat_num`. If found (any status), skip that combination. Researcher must manually delete rows from `sweep_log.csv` to force a re-run.

**Rationale**: Matches the bulk runner's resume pattern (constitution Principle I). Checking for an existing row is simpler and more reliable than checking for file existence in the output directory.

**Alternatives considered**:
- Only skip on success status — allows auto-retry of failures, but adds complexity and can loop infinitely on systematic failures
- Check output directory existence — fragile; a partial run may have created the directory without completing it

---

## Decision 5: Stability metric (pairwise agreement)

**Decision**: For each pair of repeats at the same temperature, compute fraction of columns where both assigned the same label (exact string match). Mean over all pairs = stability score for that temperature. Computed separately for `col_type` and `codebook_label`.

**Rationale**: Pairwise agreement is the simplest and most interpretable stability metric. Consistent with the spec's definition: "fraction of columns where both runs assigned the same label". For R repeats, there are R*(R-1)/2 pairs.

**Column matching**: Match by `column_name` + `source_file` (since the same column name may appear in multiple data files). Only columns present in both runs are compared; columns unique to one run count as disagreement.

**Alternatives considered**:
- Entropy-based stability — more sophisticated but harder to interpret without ground truth
- Agreement with the mode across all repeats — more stable for R>3 but less intuitive

---

## Decision 6: Quality proxy metrics

**Decision**: Three proxy metrics per temperature (mean over all repeats):
1. **Known-type rate**: `sum(col_type != "unknown") / n_cols` per repeat → mean across repeats
2. **Codebook coverage rate**: from `codebook_coverage.csv`: `n_matched / n_total` → mean across repeats; if no codebook file, mark as NA for all repeats and exclude from recommendation weighting
3. **Non-empty label rate**: `sum(!is.na(label) & nchar(label) > 0) / n_labelled` from `labels.csv`

**Rationale**: These three proxies are already computed by the existing pipeline outputs and require no new LLM calls. They measure completeness, not correctness — a reasonable proxy when ground truth is unavailable.

---

## Decision 7: Recommendation weighting

**Decision**: Combined score = `w_stab * stability_score + w_qual * quality_score` where quality_score = mean of available quality proxies (0–1 scale). Default weights: `w_stab = 0.5, w_qual = 0.5`. Configurable via `--stability-weight` argument (quality weight = 1 - stability_weight).

**Rationale**: Equal default weighting because stability and quality are both important and the researcher can tune via the CLI arg. If codebook is absent, quality_score = known-type rate only (codebook and label metrics excluded).

---

## Decision 8: Two scripts vs. one

**Decision**: Two separate scripts: `run_sweep.R` (sweep runner) and `report_sweep.R` (reporting).

**Rationale**: Consistent with the existing pipeline pattern (`run_index_bulk.R` and `report_quality.R` are separate). The sweep can be run once and the report re-run multiple times with different weights without re-running the sweep.

---

## Resolved unknowns

All NEEDS CLARIFICATION items from spec resolved. Temperature passthrough uses `options()`; output isolation uses `output_dir` param; sweep uses `sweep_log.csv` for crash-resilient resume.

# Implementation Plan: Qualtrics Triple-Header Detection and Skip

**Branch**: `003-qualtrics-header-skip` | **Date**: 2026-03-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/003-qualtrics-header-skip/spec.md`

---

## Summary

Inside `extract_column_info()` in `0_index.R`, after the data frame is loaded, detect whether the file is a Qualtrics export by checking for `{"ImportId":` in the first data row. If detected, strip rows 1–2 (the label row and the ImportId row), then proceed with normal sample value extraction, column classification, and statistics — now operating on participant response data. A boolean `is_qualtrics` field is added to every column record to record data provenance.

---

## Technical Context

**Language/Version**: R (no version constraint beyond existing project requirements)
**Primary Dependencies**: None new — operates on an already-loaded data frame; uses only base R
**Storage**: CSV files in `data_check/structure/` — additive schema change (one new column)
**Testing**: Manual regression test against a known Qualtrics CSV in the corpus; non-Qualtrics paper must produce identical output
**Target Platform**: macOS/Linux (same as existing pipeline)
**Project Type**: Data pipeline script — single function modification
**Performance Goals**: Detection adds one `grepl()` call per data file — negligible overhead
**Constraints**: Must not affect `is_raw` detection, auto-named-column guard, or column classification for non-Qualtrics files
**Scale/Scope**: Triggered only for Qualtrics files; rest of pipeline unchanged

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Crash Resilience | ✅ PASS | Detection returns NULL gracefully for zero-row case; does not crash. Incremental write pattern unchanged. |
| II. Paper ID Preservation | ✅ PASS | No changes to paper ID handling; `is_qualtrics` is a column-level attribute. |
| III. Conservative Resource Limits | ✅ PASS | No LLM calls added. Detection is a pure in-memory operation. |
| IV. Centralised Shared Helpers | ✅ PASS | Detection logic is pipeline-specific (3 lines) and not reused elsewhere. Stays in `0_index.R`. No `helper.R` changes required. |
| V. Structured Error Classification | ✅ PASS | No new error codes required. Zero-row Qualtrics files return NULL (like unreadable files) — not a pipeline error. |

**Post-design re-check**: All gates pass. No violations.

---

## Project Structure

### Documentation (this feature)

```text
specs/003-qualtrics-header-skip/
├── plan.md              # This file
├── research.md          # Phase 0 decisions
├── data-model.md        # Phase 1 output schema (extended from 002)
├── contracts/
│   └── is_qualtrics_field.md  # is_qualtrics field contract
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (affected files)

```text
data_check/
└── 0_index.R            # MODIFY: extract_column_info() — add Qualtrics detection
                         #         block, add is_qualtrics to output data.frame()
```

**Structure Decision**: Single-file modification. No new files, no `helper.R` changes. The change is a small, self-contained addition inside one function.

---

## Implementation

### Phase A: Qualtrics Detection Block in `extract_column_info()`

**Goal**: Detect Qualtrics exports by inspecting the first data row and, if found, strip the two header meta-rows before any further processing.

**Insertion point**: After the auto-named-columns guard (`if (mean(auto_named) > 0.5) ...`), before `sample_vals` computation.

**Code to insert**:

```r
# ── Qualtrics triple-header detection ──────────────────────────────────────
# Qualtrics exports inject a human-readable label row (row 1) and an
# ImportId JSON row (row 2) before actual participant responses.
# Detect by checking if any cell in the first data row contains {"ImportId":
is_qualtrics <- nrow(df) > 1 &&
  any(grepl('{"ImportId":', as.character(df[2, ]), fixed = TRUE))

if (is_qualtrics) {
  if (nrow(df) <= 2) {
    message("  skipping (Qualtrics export with no participant data rows): ",
            basename(path))
    return(NULL)
  }
  df <- df[-c(1, 2), , drop = FALSE]
  rownames(df) <- NULL
  message("  Qualtrics export detected — stripped 2 header rows: ", basename(path))
}
```

**Notes**:
- `nrow(df) > 1` guard makes detection safe for data frames with fewer than 2 rows (FR-008: degrade gracefully).
- After stripping, `rownames(df) <- NULL` resets row indices to prevent off-by-one issues in downstream code.
- The `<= 2` check handles files with exactly 2 rows (both meta, 0 participant rows) — returns NULL.

---

### Phase B: Add `is_qualtrics` to Output Data Frame

**Goal**: Record the `is_qualtrics` flag in every column record row for this file.

**Change**: In the `data.frame()` constructor inside `extract_column_info()`, insert `is_qualtrics = is_qualtrics` between `group` and `column_name`.

**Before**:
```r
list(
  columns = data.frame(
    paper_id             = paper_id,
    source_file          = rel_path,
    filename             = basename(path),
    group                = group,
    column_name          = names(df),
    ...
  ),
  is_raw = file_is_raw
)
```

**After**:
```r
list(
  columns = data.frame(
    paper_id             = paper_id,
    source_file          = rel_path,
    filename             = basename(path),
    group                = group,
    is_qualtrics         = is_qualtrics,   # NEW
    column_name          = names(df),
    ...
  ),
  is_raw = file_is_raw
)
```

`is_qualtrics` is a scalar logical — R recycles it to fill all `nrow(df)` column rows automatically.

---

## Data Model

See [data-model.md](data-model.md) for the updated column record schema (23 columns).

---

## Contracts

See [contracts/is_qualtrics_field.md](contracts/is_qualtrics_field.md) for the `is_qualtrics` field contract.

---

## Key Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Detection pattern | `{"ImportId":` fixed-string match on `df[1, ]` | Stable Qualtrics marker; no regex needed |
| Rows to drop | Exactly rows 1 and 2 (R indices) | Qualtrics always has label+ImportId as a pair |
| Zero-row guard | Return NULL + message | Consistent with existing guards; no empty records written |
| `is_qualtrics` type | logical (`TRUE`/`FALSE`) | Directly filterable in R; no re-parsing needed |
| `is_qualtrics` position | After `group`, before `column_name` | Groups with file-level metadata (per FR-006) |
| Implementation scope | Only `0_index.R` | Single-use logic; no `helper.R` changes needed |
| Guard order | After auto-named check, before sample_vals | FR-007: does not affect prior guards |

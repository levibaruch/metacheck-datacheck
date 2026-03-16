# Research: Qualtrics Triple-Header Detection and Skip

**Feature**: `003-qualtrics-header-skip`
**Date**: 2026-03-16

---

## Decision 1: Detection Pattern

**Decision**: Use a fixed-string match `{"ImportId":` on the second data row (`df[2, ]` — the ImportId JSON row). Row 1 of the data frame is the human-readable label row; row 2 is the ImportId JSON row.

**Rationale**: The Qualtrics platform injects `{"ImportId":"QID<N>_<TYPE>"}` into the second row of every CSV export. The prefix `{"ImportId":` is stable across all Qualtrics versions and export formats in the corpus (~2014–2024). A fixed-string match (no regex) is faster, less fragile, and unambiguous for this well-known marker. A partial match (≥ 1 column) is sufficient — Qualtrics always populates every column's ImportId, so any file where the pattern appears in *some* cells is unambiguously a Qualtrics export.

**Alternatives considered**:
- Regex pattern matching (e.g., `\\{"ImportId":"QID\\d+"\\}`) — more precise but unnecessary complexity; fixed-string covers all observed variants.
- Matching row 1 instead of row 2 — row 1 of the data frame is the human-readable label row, not the ImportId row. The ImportId row is row 2 of the data frame (row 3 of the file). Detection must target `df[2, ]`.

**Implementation**:
```r
is_qualtrics <- nrow(df) > 1 &&
  any(grepl('{"ImportId":', as.character(df[2, ]), fixed = TRUE))
```

---

## Decision 2: Rows to Drop

**Decision**: Drop exactly rows 1 and 2 of the in-memory data frame (R 1-based indices) when Qualtrics is detected.

**Rationale**: The Qualtrics triple-header structure is fixed: row 1 (data frame) = human-readable question labels, row 2 (data frame) = ImportId JSON. These are always present as a pair. Dropping exactly two rows is correct for all valid Qualtrics exports in the corpus.

**Alternatives considered**:
- Dropping only row 1 (ImportId row) — but row 1 is the label row, not the ImportId row. Both are non-data and must be removed.
- Dropping rows until the pattern is absent — overly complex; the structure is deterministic.

**Implementation**:
```r
df <- df[-c(1, 2), , drop = FALSE]
rownames(df) <- NULL
```

---

## Decision 3: Zero-Row Guard

**Decision**: If dropping rows 1–2 leaves a data frame with 0 rows, return NULL from `extract_column_info()` with an informative message (no crash, no empty column records written).

**Rationale**: A file with exactly 2 rows after reading (both header meta-rows, no participant data) produces a 0-row data frame after stripping. Writing column records with 0 observations would produce misleading statistics. Returning NULL is consistent with the existing guards in `extract_column_info()` (unreadable files, all-auto-named headers).

**Alternatives considered**:
- Returning empty column records — incorrect; would produce columns with NA stats that look like empty columns rather than a missing-data file.

---

## Decision 4: `is_qualtrics` Field Positioning

**Decision**: Insert `is_qualtrics` (logical) immediately after `group` and before `column_name` in the column record, making it column 5 in the output schema.

**Rationale**: `is_qualtrics` is a file-level provenance flag (like `group` and `filename`), not a column-level measurement. Grouping it with other file-level metadata (`paper_id`, `source_file`, `filename`, `group`) makes it easy to identify and filter by data source. FR-006 in the spec requires this exact placement.

**Schema change**: `group` (col 4) → `is_qualtrics` (col 5 NEW) → `column_name` (col 6, was 5) → ...

---

## Decision 5: `is_qualtrics` as Logical vs. Character

**Decision**: Use `logical` (`TRUE`/`FALSE`) not character (`"TRUE"/"FALSE"` or `"yes"/"no"`).

**Rationale**: R writes logicals to CSV as `TRUE`/`FALSE`. This is directly filterable with `df[df$is_qualtrics, ]` without re-parsing. Consistent with R convention. The field is always populated (no NA values).

---

## Decision 6: Guard Order Within `extract_column_info()`

**Decision**: Insert Qualtrics detection *after* `read_data_head()` succeeds and `df` is non-null/non-empty, *after* the auto-named-columns guard, and *before* `sample_values` computation.

**Rationale**: The auto-named check exits early for files with >50% auto-named columns — those are already skipped. Qualtrics files may or may not have well-named columns, but they should always pass the auto-named check (Qualtrics exports use proper machine-readable names as the R header). Inserting after both early guards ensures we only attempt Qualtrics detection on files that have passed basic readability checks. FR-007 requires that Qualtrics detection does not affect the `is_raw` or auto-named guards.

---

## Decision 7: No Changes to `read_data_head()` or `helper.R`

**Decision**: Qualtrics detection and stripping logic stays entirely within `extract_column_info()` in `0_index.R`. No new helpers added to `helper.R`.

**Rationale**: The detection is a single pipeline-specific guard, not a reusable utility. It operates on an already-loaded data frame, not a file path. Adding it to `helper.R` would violate the "shared utilities only" principle for that file (Constitution Principle IV). The detection logic is three lines and does not warrant extraction.

**Alternatives considered**:
- Adding a `detect_qualtrics_header(df)` helper to `helper.R` — adds complexity without benefit; not reused anywhere else.

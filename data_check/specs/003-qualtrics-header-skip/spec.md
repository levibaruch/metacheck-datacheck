# Feature Specification: Qualtrics Triple-Header Detection and Skip

**Feature Branch**: `003-qualtrics-header-skip`
**Created**: 2026-03-16
**Status**: Draft
**Input**: User description: "Qualtrics exports use a 3-row header: row 1 = machine-readable column names (used as R header), row 2 = human-readable labels, row 3 = ImportId JSON (e.g. {"ImportId":"QID1_TEXT"}). When row 1 of the data (after reading) contains {"ImportId": strings, skip rows 1–2 so that actual participant responses are used as sample_values instead of label/ImportId strings. Location: extract_column_info() in 0_index.R. This should be part of the column definitions since its a standardized input structure seen quite often."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Correct Sample Values and Statistics for Qualtrics Exports (Priority: P1)

A researcher running the pipeline on a psychology study that collected data via Qualtrics expects the `*_columns.csv` output to show actual participant responses (e.g., `"Strongly agree | Disagree | Neutral"`) in `sample_values`, not the meta-rows Qualtrics injects (`"What is your age? | {"ImportId":"QID3_TEXT"}`). They also expect numeric stats (mean, sd, etc.) to be computed from participant responses rather than silently absent because the column appeared to be text.

**Why this priority**: Qualtrics is the dominant survey platform in psychology research. Nearly every paper using an online survey exports a Qualtrics CSV. Without this fix, all Qualtrics data files produce misleading or empty statistics, and `col_type` is systematically mis-classified as `"text"` for every column. This is the single most impactful data-quality fix for the corpus.

**Independent Test**: Identify a paper whose data folder contains a Qualtrics CSV export. Run `run_index()`. Verify that: (1) `sample_values` for each column shows participant response values, not question-text labels or ImportId JSON strings; (2) numeric columns (e.g., age, Likert scale scores) have populated `mean`, `sd`, `median` etc.; (3) a `is_qualtrics` flag or equivalent is recorded in the output.

**Acceptance Scenarios**:

1. **Given** a CSV file whose second data row (row 3 of the file, i.e., after R consumes row 1 as header and row 2 as human-readable labels) contains `{"ImportId":` in at least one cell, **When** `run_index()` processes the file, **Then** rows 1 and 2 of the data frame are dropped before any sample values, statistics, or column type classification are computed.
2. **Given** a Qualtrics file with a numeric column (e.g., `"Age"` coded as integer), **When** rows 1–2 are stripped, **Then** the remaining values are parsed as numbers and summary statistics are computed correctly.
3. **Given** a standard non-Qualtrics CSV, **When** `run_index()` processes it, **Then** no rows are dropped and behaviour is identical to the current pipeline.
4. **Given** a Qualtrics file where stripping rows 1–2 leaves zero data rows, **When** `run_index()` processes it, **Then** the file is skipped (returns NULL for that file) with an informative message, and no empty column records are written.
5. **Given** a Qualtrics file is detected, **When** the column record is written to `*_columns.csv`, **Then** a boolean `is_qualtrics` field is set to `TRUE` for every row from that file, so downstream consumers can distinguish Qualtrics-sourced columns from others.

---

### Edge Cases

- What if only some columns in row 1 contain `{"ImportId":`? → Any match (≥ 1 column) is sufficient to trigger detection; Qualtrics always injects ImportId for every column so a partial match indicates corruption, not ambiguity.
- What if the file has exactly 2 rows total (both are header meta-rows, no participant data)? → After stripping, 0 rows remain → skip file with message.
- What if the file has 3 rows total (2 meta + 1 participant)? → Valid; 1-row data frame is kept and processed normally.
- What if a non-Qualtrics file coincidentally has `{"ImportId":` in its first data row? → Extremely unlikely in psychology data; if it occurs the false positive is benign (2 rows dropped, file may shrink), and the `is_qualtrics = TRUE` flag makes it auditable.
- What if the Qualtrics file uses a semicolon delimiter (European locale)? → The existing `sniff_delimiter()` function already handles this; detection logic operates on the parsed data frame regardless of delimiter.
- What if the file is an Excel export from Qualtrics? → Same logic applies; detection operates on the in-memory data frame after `read_data_head()`, independent of file format.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Inside `extract_column_info()`, after the data file is read into a data frame, the pipeline MUST check whether the second data row (`df[2, ]`) contains at least one cell matching the pattern `{"ImportId":`. Row 1 is the human-readable label row; row 2 is the ImportId JSON row.
- **FR-002**: If the Qualtrics pattern is detected, rows 1 and 2 of the data frame MUST be dropped before any further processing (sample values, classification, statistics).
- **FR-003**: If dropping rows 1–2 leaves a data frame with zero rows, the function MUST return NULL (skip the file) and emit an informative message identifying the file as a Qualtrics export with no participant data.
- **FR-004**: Detection MUST be format-agnostic — it operates on the in-memory data frame after reading, regardless of whether the source is CSV, TSV, or Excel.
- **FR-005**: A boolean field `is_qualtrics` MUST be added to the column record output. It MUST be `TRUE` for every column row originating from a detected Qualtrics file and `FALSE` for all other files.
- **FR-006**: The `is_qualtrics` field MUST be positioned immediately after `filename` and `group` in the output schema (i.e., before `column_name`), so it groups with other file-level metadata.
- **FR-007**: Detection and stripping MUST NOT affect the `is_raw` detection logic, the auto-named-columns skip check, or any other pre-existing guard in `extract_column_info()`.
- **FR-008**: The Qualtrics detection check MUST degrade gracefully — if the first row cannot be inspected (e.g., the data frame has 0 rows before stripping), it MUST return NULL with a message, not error.

### Key Entities

- **Qualtrics Export**: A tabular data file whose first data row (row index 1 after R reads the header) contains ImportId JSON strings injected by the Qualtrics platform. The two non-data rows are the human-readable question labels (row 1) and the ImportId JSON row (row 2).
- **Column Record**: Extended by `is_qualtrics` boolean to identify the data provenance of each column.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For every Qualtrics CSV in the corpus, `sample_values` contains participant response values, not question-label strings or ImportId JSON.
- **SC-002**: Numeric columns in Qualtrics files (e.g., age, Likert scores entered as integers) have populated summary statistics after the fix; zero such columns had populated statistics before the fix.
- **SC-003**: The `is_qualtrics` field is present and correctly set (`TRUE`/`FALSE`) in 100% of column rows in newly generated `*_columns.csv` files.
- **SC-004**: No non-Qualtrics file has rows dropped — `run_index()` produces identical output for all previously-processed non-Qualtrics papers.
- **SC-005**: `run_index()` returns `success = TRUE` for all papers that previously succeeded, confirming no regressions.

## Assumptions

- The `{"ImportId":` string in the first data row is a reliable, unique Qualtrics signature; no other file type in this corpus produces this pattern.
- Row 2 (human-readable labels) is always present when row 1 (ImportId row) is present; they always appear as a pair. Dropping exactly 2 rows is always correct for valid Qualtrics exports.
- The Qualtrics header structure is consistent across Qualtrics versions and export formats (CSV and Excel); the ImportId pattern has not changed across the dataset's publication range (~2014–2024).
- `is_qualtrics` is a file-level property — all columns from the same file share the same value.

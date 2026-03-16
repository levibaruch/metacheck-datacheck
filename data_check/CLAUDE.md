# Metacheck Datacheck — Development Guidelines

Auto-generated from feature plans. Last updated: 2026-03-16

## Project Overview

R pipeline that downloads psychology research data repositories from OSF, classifies files via LLM, and extracts column-level statistics. Output is per-paper `*_structure.csv` and `*_columns.csv` files written to `data_check/structure/`.

## Active Technologies
- R (base + metacheck, jsonlite, readxl, haven, e1071)
- LLM backend: `ollama/gpt-oss:20b-cloud` via `llm_batch()` — batch size 20
- No other languages in the pipeline core

## Key Files

```text
data_check/
├── 0_index.R          # Main pipeline: run_index(paper_id)
├── helper.R           # Shared helpers: read_data_head(), unpack_archive(),
│                      #   llm_batch(), classify_by_rules(), classify_col_type_rules()
├── run_index_bulk.R   # Bulk runner — appends to bulk_summary.csv, auto-resumes
├── structure/         # Output: <paper_id>_structure.csv, <paper_id>_columns.csv
└── specs/             # Feature specifications and implementation plans
```

## Commands

```r
# Run the pipeline for a single paper
source("./data_check/0_index.R")
result <- run_index("0956797615569001")

# Run in bulk (auto-resumes from last completed paper)
source("./data_check/run_index_bulk.R")
```

## Architecture Notes

- **Paper IDs are character strings** — never numeric. Always use `colClasses = c(paper_id = "character")` when reading CSVs containing paper IDs.
- **Resource limits** (do not bypass): 10 GB max download, 500 MB max file size, 10 LLM calls max per paper for file classification, 5 LLM calls for column type classification.
- **LLM budget is split**: file classification uses `MAX_LLM_CALLS = 10`; column type classification uses `MAX_COL_TYPE_LLM_CALLS = 5L` — separate counters.
- **Shared helpers live in `helper.R`** — do not duplicate `read_data_head()`, `unpack_archive()`, `llm_batch()`, or `classify_by_rules()` in other files.
- **Standalone `.gz`/`.bz2`/`.xz` files** are NOT tar archives — use `gzfile()`/`bzfile()`/`xzfile()`, not `untar()`.

## Output Schema (`*_columns.csv`)

| Column | Notes |
|--------|-------|
| paper_id | Character string — leading zeros preserved |
| source_file | Relative path within downloaded repo |
| filename | `basename(source_file)` |
| group | `ex1`, `ex2`, `pilot1`, `other`, `na` |
| is_qualtrics | `TRUE` if Qualtrics export (rows 1–2 stripped before processing) |
| column_name | Raw header from data file |
| sample_values | First 5 non-NA values joined by ` \| ` |
| col_type | Controlled vocabulary — see below |
| n_coerced | Values coerced to NA during normalization (comma-decimal types only) |
| n, n_missing | Row counts |
| mean, sd, se, median, min, max, range, p25, p75, iqr, skewness, kurtosis | Numeric stats — populated only for continuous types |

**`col_type` vocabulary**: `continuous`, `binary`, `categorical`, `ordinal`, `date`, `id`, `text`, `continuous_comma_decimal`, `continuous_outliers_excluded`, `empty`, `unknown`

## Error Codes (written to bulk_summary.csv)

| Code | Meaning |
|------|---------|
| `no_links` | Paper has no OSF data links |
| `download_failed` | Network or OSF API error |
| `empty_repo` | Downloaded repo has no usable files |
| `too_large` | Exceeded a resource limit |

## Recent Features

- `003-qualtrics-header-skip`: Detect Qualtrics triple-header CSV exports; strip rows 1–2 before processing; add `is_qualtrics` boolean to column records
- `002-column-type-classification`: Add `col_type` label + `n_coerced` to column records; rule-based fast path + LLM for ambiguous numeric columns; comma-decimal normalization
- `001-column-type-classification`: (initial feature numbering)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->

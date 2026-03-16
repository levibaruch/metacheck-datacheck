# Data Model: Qualtrics Triple-Header Detection and Skip

**Feature**: `003-qualtrics-header-skip`
**Date**: 2026-03-16

---

## Extended Column Record Schema

The `*_columns.csv` file gains one new column: `is_qualtrics` (inserted after `group` and before `column_name`). This extends the schema established by feature `002-column-type-classification`.

### Full Column Order (after feature 003)

| # | Column | Type | Always Present | Notes |
|---|--------|------|---------------|-------|
| 1 | `paper_id` | character | yes | Leading-zero-safe; stored as string |
| 2 | `source_file` | character | yes | Relative path within downloaded repo |
| 3 | `filename` | character | yes | `basename(source_file)` |
| 4 | `group` | character | yes | `ex1`, `ex2`, `pilot1`, `other`, `na` |
| 5 | `is_qualtrics` | logical | **NEW** | `TRUE` if file is a Qualtrics export; `FALSE` otherwise |
| 6 | `column_name` | character | yes | Raw column header from the data file |
| 7 | `sample_values` | character | yes | First 5 non-NA values (from participant data rows only for Qualtrics files) |
| 8 | `col_type` | character | yes | Controlled vocabulary label (see `002-column-type-classification`) |
| 9 | `n_coerced` | integer | conditional | Values coerced to NA during normalization; NA for non-normalized types |
| 10 | `n` | integer | conditional | Count of non-NA values; NA for `empty` |
| 11 | `n_missing` | integer | conditional | Count of NA values; NA for `empty` |
| 12 | `mean` | numeric | conditional | Only for numeric `col_type` values |
| 13 | `sd` | numeric | conditional | Only for numeric `col_type` values |
| 14 | `se` | numeric | conditional | Only for numeric `col_type` values |
| 15 | `median` | numeric | conditional | Only for numeric `col_type` values |
| 16 | `min` | numeric | conditional | Only for numeric `col_type` values |
| 17 | `max` | numeric | conditional | Only for numeric `col_type` values |
| 18 | `range` | numeric | conditional | Only for numeric `col_type` values |
| 19 | `p25` | numeric | conditional | Only for numeric `col_type` values |
| 20 | `p75` | numeric | conditional | Only for numeric `col_type` values |
| 21 | `iqr` | numeric | conditional | Only for numeric `col_type` values |
| 22 | `skewness` | numeric | conditional | Only for numeric `col_type` values |
| 23 | `kurtosis` | numeric | conditional | Only for numeric `col_type` values |

---

## `is_qualtrics` Field Semantics

| Value | Meaning |
|-------|---------|
| `TRUE` | The source file was detected as a Qualtrics export (ImportId pattern found in first data row). Rows 1–2 of the data frame were stripped before any statistics were computed. |
| `FALSE` | Standard data file. No rows were dropped. |

**File-level property**: All column rows originating from the same source file share the same `is_qualtrics` value.

**Never NA**: The field is always `TRUE` or `FALSE`; it is set before `sample_values` are computed and before column classification runs.

---

## Schema Change Summary (relative to feature 002)

| Change | Details |
|--------|---------|
| New column | `is_qualtrics` at position 5 |
| Columns shifted | `column_name` moves from position 5 → 6; `sample_values` from 6 → 7; all subsequent columns shift by +1 |
| Sample values semantics | For Qualtrics files, `sample_values` now reflects participant response values (after stripping header meta-rows), not Qualtrics label/ImportId strings |

---

## Backward Compatibility

- Columns 1–4 and 6–23 are unchanged in name and semantics (positions 6–23 shift by +1).
- `is_qualtrics` (column 5) is a **new additive field**.
- Existing `*_columns.csv` files in `structure/` do NOT have this column; only newly generated files will include it.
- Downstream scripts reading existing files must handle the optional presence of `is_qualtrics`.

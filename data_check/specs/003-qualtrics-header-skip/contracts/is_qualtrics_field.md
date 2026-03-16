# Contract: `is_qualtrics` Field

**Feature**: `003-qualtrics-header-skip`
**Version**: 1.0
**Date**: 2026-03-16

---

## Purpose

This document defines the contract for the `is_qualtrics` field added to `*_columns.csv` output files. It specifies the detection trigger, field semantics, valid values, and guarantees for downstream consumers.

---

## Detection Trigger

A data file is classified as a Qualtrics export when **at least one cell** in the second data row (row index 2 in the in-memory data frame — the ImportId row) contains the fixed string `{"ImportId":`. Row 1 is the human-readable label row; row 2 is the ImportId JSON row.

```
Trigger condition: nrow(df) > 1 && any(grepl('{"ImportId":', as.character(df[2, ]), fixed = TRUE))
```

This check is applied after the file is fully loaded into memory, regardless of file format (CSV, TSV, Excel). It is format-agnostic.

---

## Field Contract

| Property | Value |
|----------|-------|
| Column name | `is_qualtrics` |
| Type | logical (`TRUE` / `FALSE`) |
| CSV representation | `TRUE` or `FALSE` (R default logical serialization) |
| Never NA | Yes — always set to `TRUE` or `FALSE` for every row |
| Scope | File-level: all rows from the same `source_file` share the same value |
| Position | Column 5, immediately after `group`, before `column_name` |

---

## Behavioral Guarantees

1. **When `is_qualtrics = TRUE`**: The `sample_values`, `col_type`, and all statistics in that row were computed from participant response data only (rows 3+ of the original file). The Qualtrics label row (human-readable question text) and ImportId row were stripped before any processing.

2. **When `is_qualtrics = FALSE`**: Processing was identical to pre-feature-003 behavior. No rows were dropped.

3. **Zero-row skip**: If stripping the two Qualtrics header rows leaves a file with no participant data rows, the file produces no rows in `*_columns.csv` at all (NULL return, file skipped). This means `is_qualtrics = TRUE` in the output always implies at least one participant data row existed.

4. **Non-Qualtrics files unaffected**: Files that do not trigger the detection condition are processed identically to pre-feature behavior. `run_index()` produces identical output for all non-Qualtrics papers (SC-004 from spec).

---

## Stability Commitment

`is_qualtrics` is a stable field. Downstream scripts may safely filter on `is_qualtrics == TRUE` to identify Qualtrics-sourced columns. The detection trigger (`{"ImportId":`) will not be changed without a version bump to this contract.

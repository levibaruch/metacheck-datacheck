---
description: "Task list for 003-qualtrics-header-skip"
---

# Tasks: Qualtrics Triple-Header Detection and Skip

**Input**: Design documents from `/specs/003-qualtrics-header-skip/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/is_qualtrics_field.md ✓

**Tests**: Not requested — no test tasks included.

**Organization**: Single user story (P1). Single-file modification to `data_check/0_index.R`.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

**Purpose**: Confirm current `extract_column_info()` structure before modifying it.

- [X] T001 Read `data_check/0_index.R` to locate `extract_column_info()` and identify exact insertion point (after auto-named guard, before `sample_vals`) and the `data.frame()` output constructor where `is_qualtrics` field must be inserted

---

## Phase 2: Foundational

No shared infrastructure changes required. This feature modifies a single existing function. Proceed directly to User Story 1 after T001.

---

## Phase 3: User Story 1 — Correct Sample Values and Statistics for Qualtrics Exports (Priority: P1) 🎯 MVP

**Goal**: Detect Qualtrics triple-header exports inside `extract_column_info()`, strip rows 1–2, add `is_qualtrics` boolean to every column record.

**Independent Test**: Run `run_index()` on a Qualtrics paper. Verify `is_qualtrics = TRUE`, `sample_values` shows participant responses, numeric columns have populated stats. Run `run_index()` on a non-Qualtrics paper and confirm identical output to pre-feature behavior.

### Implementation for User Story 1

- [X] T002 [US1] Add Qualtrics detection block (`is_qualtrics` assignment + strip + zero-row guard) to `extract_column_info()` in `data_check/0_index.R` after the auto-named-columns guard and before `sample_vals` computation (exact code specified in plan.md Phase A)
- [X] T003 [US1] Add `is_qualtrics = is_qualtrics` field to the `data.frame()` output constructor in `extract_column_info()` in `data_check/0_index.R`, positioned after `group` and before `column_name` (exact change specified in plan.md Phase B)

**Checkpoint**: `extract_column_info()` now detects Qualtrics exports, strips 2 header rows, and emits `is_qualtrics` in every column record.

---

## Phase 4: Polish & Cross-Cutting Concerns

- [X] T004 Verify `data_check/CLAUDE.md` output schema table already includes `is_qualtrics` at position 5 (between `group` and `column_name`); update if missing

---

## Dependencies & Execution Order

- **T001** → **T002** → **T003** (sequential: must read before editing, detection block before field insertion)
- **T004** can run after T003 (verification only)

---

## Implementation Strategy

### MVP (only user story — complete all phases)

1. T001: Read `0_index.R`, locate insertion points
2. T002: Insert Qualtrics detection block
3. T003: Insert `is_qualtrics` field in output
4. T004: Verify CLAUDE.md schema

---

## Notes

- All changes confined to `data_check/0_index.R` — no `helper.R` or other file changes
- Detection pattern: `nrow(df) > 1 && any(grepl('{"ImportId":', as.character(df[2, ]), fixed = TRUE))`
- Strip: `df <- df[-c(1, 2), , drop = FALSE]; rownames(df) <- NULL`
- Zero-row guard: if `nrow(df) <= 2` after detection → `return(NULL)` with message
- `is_qualtrics` is always `TRUE` or `FALSE` (logical); never NA

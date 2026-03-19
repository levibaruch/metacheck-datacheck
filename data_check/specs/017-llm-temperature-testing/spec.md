# Feature Specification: LLM Temperature Stability Testing

**Feature Branch**: `017-llm-temperature-testing`
**Created**: 2026-03-19
**Status**: Draft
**Input**: User description: "Implement a testing toolkit that runs the same paper through the pipeline multiple times at different LLM temperatures and measures output stability (label consistency across runs) and relative quality (which temperature produces more coherent or complete outputs). This is a controlled experiment to tune the LLM temperature hyperparameter and validate that the pipeline produces reproducible results."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run Temperature Sweep on a Single Paper (Priority: P1)

The researcher selects one paper and runs the temperature sweep tool, specifying a list of temperatures (e.g. 0.0, 0.3, 0.7, 1.0) and a number of repeat runs per temperature (e.g. 3 repeats). The tool runs the full pipeline for each (temperature, repeat) combination and saves the outputs to an isolated location, then reports which temperature produced the most consistent and most complete results.

**Why this priority**: This is the core capability — without the ability to run the sweep and collect outputs, nothing else in this feature is possible.

**Independent Test**: Can be fully tested on a single paper with a small temperature list (e.g. 2 temperatures × 2 repeats = 4 runs) and confirms that separate output files are produced for each run.

**Acceptance Scenarios**:

1. **Given** a valid paper ID and a list of temperatures, **When** the sweep is run, **Then** each (temperature, repeat) combination produces a separate set of output files stored under an identifiable path.
2. **Given** N temperatures × R repeats, **When** the sweep completes, **Then** exactly N × R output sets exist (or failures are recorded for any that did not complete).
3. **Given** a temperature of 0.0 (deterministic), **When** run R times, **Then** all R outputs for that temperature are identical (column labels match 100%).

---

### User Story 2 - Stability Report Across Temperatures (Priority: P2)

After running the sweep, the researcher wants to see a stability report: for each temperature, how often do repeated runs produce the same column-type classifications and the same codebook labels? The tool computes pairwise agreement across repeats and reports the mean agreement rate per temperature.

**Why this priority**: Stability (reproducibility) is the primary quality signal when there is no ground truth. A temperature with high agreement is preferable to one with high variance.

**Independent Test**: Can be tested independently by pointing the report at an existing sweep output directory and verifying agreement rates are computed correctly for each temperature.

**Acceptance Scenarios**:

1. **Given** a completed sweep directory, **When** the stability report is run, **Then** it outputs a table showing mean pairwise label-agreement rate per temperature, sorted from most to least stable.
2. **Given** a temperature where all repeats produced identical outputs, **When** the report is run, **Then** that temperature shows 100% agreement.
3. **Given** a temperature where repeats differed on every column, **When** the report is run, **Then** that temperature shows 0% agreement.
4. **Given** only 1 repeat per temperature, **When** the report is run, **Then** it warns that stability cannot be computed with a single repeat and skips stability metrics.

---

### User Story 3 - Quality Comparison Across Temperatures (Priority: P3)

The researcher wants to compare relative output quality across temperatures, without ground truth. Proxy quality metrics include: proportion of columns that received a non-`unknown` type, codebook coverage rate (fraction of columns with a label), and the number of labels that are non-empty. The report shows these metrics per temperature to help identify which temperature produces the most complete outputs.

**Why this priority**: Stability alone is insufficient — a temperature could be stably wrong. Quality proxies help distinguish a temperature that is consistently complete from one that is consistently empty.

**Independent Test**: Can be tested independently by pointing the quality report at a sweep output directory and confirming the proxy metrics are computed per temperature.

**Acceptance Scenarios**:

1. **Given** a completed sweep directory, **When** the quality report is run, **Then** it shows per-temperature mean values for: known-type rate, codebook coverage rate, and non-empty label rate.
2. **Given** a temperature that consistently produces all-`unknown` types, **When** the report is run, **Then** that temperature shows 0% known-type rate.
3. **Given** a paper with no codebook, **When** the report is run, **Then** codebook coverage is reported as N/A (not 0%) to distinguish "no codebook" from "poor matching".

---

### User Story 4 - Recommended Temperature Output (Priority: P4)

After the sweep, the researcher wants a single recommended temperature — the one that best balances stability and quality. The tool computes a combined score (weighted stability + quality proxies) and prints a recommendation with the score breakdown.

**Why this priority**: Synthesising the results into a single actionable recommendation reduces cognitive load. The researcher should not need to interpret a multi-column table to decide which temperature to use.

**Independent Test**: Can be tested by verifying the recommended temperature is the one with the highest combined score in a known sweep result.

**Acceptance Scenarios**:

1. **Given** a completed sweep with stability and quality data, **When** the recommendation is requested, **Then** it names the single temperature with the highest combined score and shows the score breakdown.
2. **Given** a tie between two temperatures, **When** the recommendation is requested, **Then** both are listed as tied and the researcher is prompted to choose based on the detailed report.
3. **Given** insufficient data (e.g. only 1 temperature tested), **When** the recommendation is requested, **Then** it states that comparison requires at least 2 temperatures.

---

### Edge Cases

- What happens if the pipeline fails for a (temperature, repeat) combination? → Record the failure in the sweep log; do not abort the remaining combinations.
- What happens if the paper has no codebook? → Codebook coverage metrics are marked as N/A for all temperatures; stability is computed on column-type labels only.
- What happens if a paper is too large (`too_large` error) at any temperature? → Report the failure and exclude the paper from quality/stability metrics.
- What happens if temperatures are provided out of range (e.g. negative or >2)? → Validate inputs before starting; reject invalid values with a clear error message.
- What happens if the sweep is interrupted mid-run? → Already-completed (temperature, repeat) combinations are preserved; the sweep can be resumed by re-running and skipping existing outputs.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The sweep tool MUST accept a paper ID, a list of temperatures, and a repeat count as inputs.
- **FR-002**: For each (temperature, repeat) combination, the sweep tool MUST run the full pipeline (index + codebook labelling) and save all outputs to a distinct, identifiable location under a sweep results directory.
- **FR-003**: The sweep tool MUST record metadata for each run: temperature, repeat number, paper ID, run timestamp, success/failure status, and elapsed time.
- **FR-004**: The sweep tool MUST skip already-completed (temperature, repeat) combinations when re-run, enabling resume after interruption.
- **FR-005**: The stability report MUST compute pairwise label-agreement rate across repeats for each temperature, for both column-type labels and codebook labels separately.
- **FR-006**: The quality report MUST compute per-temperature mean values for: known-type rate (non-`unknown` columns / total columns), codebook coverage rate, and non-empty codebook label rate.
- **FR-007**: The recommendation MUST combine stability and quality proxy scores into a single ranked output; the weighting between stability and quality MUST be configurable (default: equal weight).
- **FR-008**: The sweep MUST treat `paper_id` as a character string at all times.
- **FR-009**: Individual run failures MUST be logged and not abort the remaining sweep combinations.
- **FR-010**: All sweep outputs MUST be stored in a dedicated directory (e.g. `sweep_results/<paper_id>/`) separate from the main `outputs/` directory to avoid contaminating production outputs.
- **FR-011**: The tool MUST validate temperature inputs (must be numeric, within an accepted range) before starting and reject invalid values with a descriptive error.

### Key Entities

- **SweepRun**: One record per (paper_id, temperature, repeat); contains metadata (timestamp, status, elapsed time) and a pointer to the output directory for that run.
- **LabelSet**: The set of column-type and codebook labels produced by one pipeline run; the unit of comparison for stability and quality metrics.
- **StabilityScore**: Per-temperature mean pairwise agreement rate across repeats, computed separately for column-type labels and codebook labels.
- **QualityScore**: Per-temperature mean values for known-type rate, codebook coverage rate, and non-empty label rate.
- **SweepRecommendation**: The combined score and recommended temperature, with breakdown by stability and quality components.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A sweep of 1 paper × 4 temperatures × 3 repeats (12 runs) completes without manual intervention and produces 12 distinct output sets.
- **SC-002**: At temperature = 0.0, all repeats for a given paper produce identical column-type label sets (100% pairwise agreement).
- **SC-003**: The stability report correctly ranks temperatures by reproducibility — confirmed by manually inspecting 2 temperatures and verifying the higher-agreement one ranks first.
- **SC-004**: The sweep correctly resumes after interruption — re-running a partially complete sweep adds only the missing combinations without re-running completed ones.
- **SC-005**: Quality proxy metrics (known-type rate, codebook coverage) match values computed manually from the same output files.
- **SC-006**: The recommendation output names a single temperature (or a documented tie) and provides a score breakdown that the researcher can verify by hand.

## Assumptions

- The pipeline's LLM temperature can be set per-run via an existing or new parameter; if the current pipeline hardcodes temperature, a thin wrapper or parameter pass-through will be needed.
- No new R packages are required; base R plus packages already present are sufficient.
- A "repeat" means a fully independent pipeline run (not just re-reading cached outputs); the pipeline does not cache LLM responses between runs.
- Sweep outputs are stored locally on disk and are not automatically cleaned up.
- The recommended default temperature list is [0.0, 0.3, 0.7, 1.0] and default repeat count is 3, but both are overridable.
- Pairwise agreement is computed as the fraction of columns where both runs assigned the same label (exact string match).

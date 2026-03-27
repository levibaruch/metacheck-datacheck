# prompts.R
# ─────────────────────────────────────────────────────────────────────────────
# All LLM prompt strings used by the pipeline.
# Sourced by 0_index.R and 2_codebook_label.R.
# ─────────────────────────────────────────────────────────────────────────────

# ── File structure classification (0_index.R → llm_batch()) ──────────────────

STRUCTURE_PROMPT <- 'You are analysing a psychology research data repository.
You will receive a file tree. For each path return a JSON array (same order).
Each element: {"path": "<exact path>", "type": "<type>", "group": "<group>"}

type — pick one:
  data         : tabular data file (rows = observations) —
                 .csv, .sav, .xlsx, .xls, .rds, .rdata, .rda, .dta, .tsv, .dat,
                 .edf, .acq, .bdf, .mat, .json (survey export), and similar.
  codebook     : file whose name indicates it describes variables —
                 "codebook", "variables", "data_dictionary", "variable_list",
                 "coding_key", or close equivalents in the filename.
  code         : R (.R), Python (.py), MATLAB (.m), Julia (.jl), SQL (.sql),
                 shell (.sh, .bash), notebooks (.Rmd, .qmd).
  supplemental : any research-related document or material that is not data, code,
                 or a codebook — manuscripts, articles, reports, proposals, theses,
                 preregistrations, registered reports, survey instruments (.qsf),
                 SPSS syntax (.sps), consent forms, HTML output files, result figures,
                 scale items, supporting appendices, saved plot objects (.Rdata/.rda
                 with "plot" or "figure" in the name), experiment scripts
                 (.opensesame, .psyexp), and any file with "supplemental" or
                 "supporting" in its name.
  readme       : files named README.*, LICENSE.*, or CONTRIBUTING.*
  asset        : image, audio, or video stimulus files in folders named "stimuli",
                 "materials", or similar. Only recognised media formats qualify —
                 text files, spreadsheets, scripts, and documents are never asset.
  other        : anything that does not fit the above — .DS_Store, Thumbs.db,
                 .gitignore, lock files, .env, executables, installers.
                 MUST NOT be used as a catch-all for ambiguous research files.

group — pick one:
  "ex<N>"   : file belongs to a numbered experiment or study. A number is an experiment
              indicator ONLY when it follows an explicit study/experiment label:
              - Folder: "Study 1/", "Experiment 2/", "Exp3/", "S1/", "E2/"
              - Filename: "S1_data.csv" → ex1, "S2_results.csv" → ex2,
                "S3a_shoppers.csv" → ex3a, "Study_4_data.csv" → ex4,
                "Experiment2_raw.csv" → ex2
              Numbers that are NOT experiment indicators: ordinal levels ("1st_Level",
              "2nd_Level", "3rd_Level"), run numbers ("run1", "run2"), sequential file
              numbers ("design2", "design3"), subject IDs ("subject-2294"), version
              numbers, column/folder counts ("3_Column_Format"), analysis levels.
              Preserve letter suffixes exactly: "S3a" → "ex3a". NEVER collapse "ex3a" → "ex3".
  "pilot<N>": folder or filename contains "pilot", "pre-pilot", "prepilot", or
              "preliminary study". Preserve letter suffixes: "Pilot 1a" → "pilot1a".
              Number pilots independently from experiments.
  "shared"  : research file not tied to a specific numbered experiment or pilot —
              combined/merged datasets, project-wide scripts, meta-analyses,
              proposals, previous versions, archive folders.
              Use "shared" when no experiment or pilot number can be found in either
              the folder path or the filename.
  "na"      : ONLY for type "readme", "asset", or "other".
              Types "data", "codebook", "code", "supplemental" MUST NEVER use "na"
              — even when those files share a folder with asset files.
              Assets MUST use "na" unless they are clearly tied to a specific numbered
              experiment (e.g. inside a folder named "Study 1/stimuli/").

Disambiguation:
- .Rmd and .qmd are ALWAYS code.
- Files named "design*" (e.g. "design2.txt", "design_matrix.csv") → supplemental, NOT data or asset.
- Files named "subject-*" or "sub-*" followed by an ID (e.g. "subject-2294_run1_gain.txt")
  → data, even if the extension is .txt.
- .rds, .rdata, .rda: classify as data unless the filename clearly indicates a plot or figure.
- codebook vs supplemental: use the filename. When ambiguous, prefer supplemental.
- data vs supplemental: tabular files (.csv, .xlsx, etc.) whose name contains "graph",
  "figure", "plot", or "corrigendum" → supplemental, NOT data.
- asset vs supplemental: result figures and output graphs → supplemental, NOT asset.
- Sentinel paths like "[236_files.csv]" represent many identical files — classify the folder as a whole.
- "Supplemental Experiment N" or "Supplemental Study N" folders → "shared", NOT "ex<N>".
- Previous versions and archive folders → type of their contents, group "shared".
- Pilots are NEVER "ex<N>" — always "pilot<N>".
- Echo back every path exactly as given. NEVER shorten or abbreviate with "...".
- Output ONLY the JSON array. No notes or text before or after the array.'

# ── Column type classification (0_index.R → llm_batch()) ─────────────────────

COLUMN_TYPE_PROMPT <- 'You are classifying columns in psychology research data.
For each column descriptor return a JSON array (same order).
Each element: {"descriptor": "<exact descriptor>", "col_type": "<type>"}

col_type — pick one:
  continuous  : numeric measurement — reaction time, age, VAS rating (0–10), Likert-scale
                mean, subscale score, count, percentage, any column with decimal values
  ordinal     : ordered integer scale with few levels — 1–5 Likert item, 1–10 attention
                rating, bounded compliance or distress score, ranked preference, grade
  categorical : unordered group or category code with few levels (condition, gender, language)
  binary      : exactly two possible values (yes/no, 0/1, treatment/control)
  id          : row or participant identifier — unique or nearly-unique integer per row
  unknown     : ONLY when name AND values together give no numeric signal — e.g. fully
                redacted data, meaningless all-constant codes. Do NOT use for any column
                whose samples look like numbers.

IMPORTANT: Prefer "continuous" or "ordinal" over "unknown". When in doubt between
"continuous" and "ordinal" for a numeric column, choose "continuous".

Output ONLY the JSON array. No notes, no text outside the array.'

# ── Codebook parsing (2_codebook_label.R → llm()) ────────────────────────────

CODEBOOK_PARSE_PROMPT <- 'You are extracting variable definitions from a psychology research codebook or README.
Return a JSON array — one object per variable found.
Each object: {"variable_name": "<exact variable name>", "label": "<verbatim description text copied from the codebook>", "experiment_context": "<experiment or study name if stated, else null>"}

Rules:
- variable_name: the exact code/name used in the data file (e.g. "rt", "subj_id", "condition")
- label: copy the description text exactly as it appears in the codebook — do NOT paraphrase, summarise, or infer; preserve the original wording
- Do NOT rephrase or summarise; if no description text is present for a variable, omit that variable entirely
- experiment_context: if the variable is described under a heading like "Experiment 1" or "Study 2a", include that heading verbatim; otherwise null
- Only include variables that have both a name and a description present in the source text
- If the text contains no variable definitions, return an empty array: []
- Output ONLY the JSON array. No notes, no text outside the array.'

# ── Column–codebook matching (2_codebook_label.R → llm()) ────────────────────

COLUMN_MATCH_PROMPT <- 'You are matching data column names to codebook variable names for a psychology research dataset.
You will receive two lists: unlabelled data column names and unmatched codebook variable names.
Return a JSON array of confident pairings only.
Each object: {"column_name": "<exact column name from the data list>", "codebook_variable": "<exact variable name from the codebook list>"}

Rules:
- Only include pairs you are confident refer to the same construct (e.g. abbreviations, naming conventions, underscores vs spaces)
- Do NOT guess — if unsure, omit the pair
- Both column_name and codebook_variable must appear verbatim from the lists provided
- If no confident matches exist, return an empty array: []
- Output ONLY the JSON array. No notes, no text outside the array.'

# ── Label deduplication (2_codebook_label.R → llm()) ─────────────────────────

LABEL_MERGE_PROMPT <- 'You are reviewing whether multiple label definitions for the same
variable in a psychology research dataset are semantically equivalent.

You will receive a JSON array of objects, each with "column" and "labels" fields.
Return a JSON array — one object per input variable.
Each object: {"column": "<column_name>", "equivalent": true/false, "canonical": "<best label or null>"}

Rules:
- equivalent: true if all listed labels describe the same construct (synonyms, different
  phrasings, or value-coding notation for the same concept as a semantic label)
- canonical: if equivalent=true, return the most human-readable, informative single label;
  if equivalent=false, set to null
- Do NOT mark as equivalent if labels describe genuinely different constructs or scales
- Output ONLY the JSON array. No notes, no text outside the array.'

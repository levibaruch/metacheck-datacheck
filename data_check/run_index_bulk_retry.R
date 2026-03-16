# run_index_bulk_retry.R
# ─────────────────────────────────────────────────────────────────────────────
# Retry all failed papers from a prior bulk run
# Reads bulk_summary.csv, extracts papers where success=FALSE, reruns them
# Results written to bulk_summary_retry.csv
# ─────────────────────────────────────────────────────────────────────────────

source("./data_check/0_index.R")

# ── Config ────────────────────────────────────────────────────────────────────

PRIOR_SUMMARY_CSV <- "./data_check/bulk_summary.csv"
RETRY_SUMMARY_CSV <- "./data_check/bulk_summary_retry.csv"

# ── Load prior results ───────────────────────────────────────────────────────

if (!file.exists(PRIOR_SUMMARY_CSV)) {
  stop("Prior summary file not found: ", PRIOR_SUMMARY_CSV)
}

prior_df <- read.csv(PRIOR_SUMMARY_CSV, stringsAsFactors = FALSE,
                     colClasses = c(paper_id = "character"))

if (!"success" %in% names(prior_df)) {
  stop("prior summary missing 'success' column")
}

# ── Extract failed papers ──────────────────────────────────────────────────

failed_ids <- prior_df$paper_id[!prior_df$success]
failed_ids <- unique(failed_ids)

if (length(failed_ids) == 0) {
  message("No failed papers to retry.")
  q(save = "no")
}

message("── Found ", length(failed_ids), " failed paper(s) to retry")

# ── Load prior progress from retry file ──────────────────────────────────────

retry_done_ids <- character(0)
if (file.exists(RETRY_SUMMARY_CSV)) {
  retry_prior <- tryCatch(
    read.csv(RETRY_SUMMARY_CSV, stringsAsFactors = FALSE,
             colClasses = c(paper_id = "character")),
    error = function(e) NULL
  )
  if (!is.null(retry_prior) && "paper_id" %in% names(retry_prior)) {
    retry_done_ids <- unique(as.character(retry_prior$paper_id))
    message("── Resuming: ", length(retry_done_ids), " retry(s) already done")
  }
}

# ── Determine papers to retry ────────────────────────────────────────────────

to_retry <- setdiff(failed_ids, retry_done_ids)

if (length(to_retry) == 0) {
  message("── All failed papers already retried.")
  q(save = "no")
}

message("── Will retry ", length(to_retry), " paper(s)")

# ── Helper: append one row to the summary CSV ────────────────────────────────

na_fallback <- function(x, na = NA) if (is.null(x) || length(x) == 0) na else x

append_summary_row <- function(r) {
  row <- data.frame(
    paper_id     = na_fallback(r$paper_id, NA_character_),
    success      = r$success,
    error        = na_fallback(r$error, NA_character_),
    elapsed_ms   = round(na_fallback(r$elapsed_sec, NA_real_) * 1000),
    download_ms  = round(na_fallback(r$download_sec, NA_real_) * 1000),
    llm_ms       = round(na_fallback(r$llm_sec, NA_real_) * 1000),
    column_ms    = round(na_fallback(r$column_sec, NA_real_) * 1000),
    n_files      = na_fallback(r$n_files, NA_integer_),
    n_data_files = na_fallback(r$n_data_files, NA_integer_),
    n_agg_dirs   = na_fallback(r$n_agg_dirs, NA_integer_),
    n_raw        = na_fallback(r$n_raw, NA_integer_),
    n_nonraw     = na_fallback(r$n_nonraw, NA_integer_),
    n_columns    = na_fallback(r$n_columns, NA_integer_),
    n_src_files  = na_fallback(r$n_source_files, NA_integer_),
    stringsAsFactors = FALSE
  )
  write_header <- !file.exists(RETRY_SUMMARY_CSV)
  write.table(row, RETRY_SUMMARY_CSV, append = TRUE, sep = ",",
              row.names = FALSE, col.names = write_header)
}

# ── Run ──────────────────────────────────────────────────────────────────────

for (i in seq_along(to_retry)) {
  pid <- to_retry[i]

  # Double-check: in case CSV was updated externally
  if (file.exists(RETRY_SUMMARY_CSV)) {
    already <- tryCatch(
      read.csv(RETRY_SUMMARY_CSV, stringsAsFactors = FALSE,
               colClasses = c(paper_id = "character")),
      error = function(e) NULL
    )
    if (!is.null(already) && pid %in% already$paper_id) {
      message("  skipping (already retried): ", pid)
      next
    }
  }

  cat("\n══════════════════════════════════════════════════════════════════════\n")
  cat(sprintf("  Retry %d / %d  —  %s\n", i, length(to_retry), pid))
  cat("══════════════════════════════════════════════════════════════════════\n")

  result <- tryCatch(
    run_index(paper_id = pid),
    error = function(e) {
      message("  FAILED: ", conditionMessage(e))
      list(
        paper_id       = pid,
        success        = FALSE,
        error          = conditionMessage(e),
        elapsed_sec    = NA_real_,
        n_files        = NA_integer_,
        n_data_files   = NA_integer_,
        n_agg_dirs     = NA_integer_,
        n_raw          = NA_integer_,
        n_nonraw       = NA_integer_,
        n_columns      = NA_integer_,
        n_source_files = NA_integer_
      )
    }
  )

  append_summary_row(result)
}

# ── Print summary ────────────────────────────────────────────────────────────

retry_df <- read.csv(RETRY_SUMMARY_CSV, stringsAsFactors = FALSE,
                     colClasses = c(paper_id = "character"))

cat("\n\n")
cat("╔══════════════════════════════════════════════════════════════════════╗\n")
cat("║                    BULK RETRY SUMMARY                               ║\n")
cat("╚══════════════════════════════════════════════════════════════════════╝\n\n")

cat("── Retry results ──────────────────────────────────────────────────────\n")
print(retry_df[, setdiff(names(retry_df), "error")], row.names = FALSE)

n_ok   <- sum(retry_df$success)
n_fail <- nrow(retry_df) - n_ok

cat(sprintf("\n── Success rate: %d / %d  (%.0f%%)\n",
            n_ok, nrow(retry_df), 100 * n_ok / nrow(retry_df)))

if (n_fail > 0) {
  cat("\n── Still failing:\n")
  fails <- retry_df[!retry_df$success, ]
  for (j in seq_len(nrow(fails))) {
    cat(sprintf("   %s — %s\n", fails$paper_id[j], fails$error[j]))
  }
}

if (n_ok > 0) {
  ok_times <- retry_df$elapsed_ms[retry_df$success] / 1000
  cat(sprintf(
    "\n── Elapsed time (successful retries):\n   mean=%.1fs  median=%.1fs  min=%.1fs  max=%.1fs\n",
    mean(ok_times), median(ok_times), min(ok_times), max(ok_times)
  ))

  ok_rows <- retry_df[retry_df$success, ]
  cat("\n── Coverage (successful retries):\n")
  cat(sprintf("   Files per paper      — mean=%.1f  median=%.1f  range=[%d,%d]\n",
              mean(ok_rows$n_files),      median(ok_rows$n_files),
              min(ok_rows$n_files),       max(ok_rows$n_files)))
  cat(sprintf("   Data files per paper — mean=%.1f  median=%.1f  range=[%d,%d]\n",
              mean(ok_rows$n_data_files), median(ok_rows$n_data_files),
              min(ok_rows$n_data_files),  max(ok_rows$n_data_files)))
  cat(sprintf("   Columns extracted    — mean=%.1f  median=%.1f  range=[%d,%d]\n",
              mean(ok_rows$n_columns),    median(ok_rows$n_columns),
              min(ok_rows$n_columns),     max(ok_rows$n_columns)))
}

cat("\n── Results saved to: ", RETRY_SUMMARY_CSV, "\n")

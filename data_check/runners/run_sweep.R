# run_sweep.R
# ─────────────────────────────────────────────────────────────────────────────
# Temperature sweep runner: runs a single paper through the full pipeline
# (index + codebook labelling) N times at each of M temperatures.
#
# Usage:
#   Rscript run_sweep.R --paper-id <ID> \
#     [--temperatures 0.0,0.3,0.7,1.0] [--repeats 3] \
#     [--sweep-dir ./sweep_results]
#
# Outputs per (temperature, repeat):
#   sweep_results/<paper_id>/temp_<T>/rep_<R>/  — isolated pipeline outputs
#   sweep_results/<paper_id>/sweep_log.csv       — crash-resilient run log
# ─────────────────────────────────────────────────────────────────────────────

# ── Argument parsing ──────────────────────────────────────────────────────────

parse_sweep_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  paper_id    <- NULL
  temperatures <- c(0.0, 0.3, 0.7, 1.0)
  repeats     <- 3L
  sweep_dir   <- "./sweep_results"

  i <- 1L
  while (i <= length(args)) {
    switch(args[i],
      "--paper-id" = {
        i <- i + 1L
        paper_id <- as.character(args[i])
      },
      "--temperatures" = {
        i <- i + 1L
        temperatures <- as.numeric(strsplit(args[i], ",")[[1]])
      },
      "--repeats" = {
        i <- i + 1L
        repeats <- as.integer(args[i])
      },
      "--sweep-dir" = {
        i <- i + 1L
        sweep_dir <- args[i]
      }
    )
    i <- i + 1L
  }

  if (is.null(paper_id) || !nzchar(paper_id))
    stop("--paper-id is required")
  if (any(is.na(temperatures)) || any(temperatures < 0) || any(temperatures > 2))
    stop("All temperatures must be numeric values in [0, 2]. Got: ",
         paste(temperatures, collapse = ", "))
  if (is.na(repeats) || repeats < 1L)
    stop("--repeats must be an integer >= 1")

  list(
    paper_id     = paper_id,
    temperatures = temperatures,
    repeats      = repeats,
    sweep_dir    = sweep_dir
  )
}

# ── Sweep log helpers ─────────────────────────────────────────────────────────

load_or_create_sweep_log <- function(log_path) {
  if (file.exists(log_path)) {
    read.csv(log_path, stringsAsFactors = FALSE,
             colClasses = c(paper_id = "character"))
  } else {
    data.frame(
      paper_id      = character(0),
      temperature   = numeric(0),
      repeat_num    = integer(0),
      output_dir    = character(0),
      status        = character(0),
      error         = character(0),
      elapsed_ms    = integer(0),
      run_timestamp = character(0),
      stringsAsFactors = FALSE
    )
  }
}

sweep_run_done <- function(log_df, paper_id, temperature, repeat_num) {
  if (nrow(log_df) == 0) return(FALSE)
  any(log_df$paper_id == paper_id &
      log_df$temperature == temperature &
      log_df$repeat_num == repeat_num)
}

append_sweep_log <- function(log_path, row) {
  write.table(
    row,
    file      = log_path,
    sep       = ",",
    append    = TRUE,
    col.names = !file.exists(log_path),
    row.names = FALSE,
    quote     = TRUE
  )
}

# ── Single run ────────────────────────────────────────────────────────────────

run_one <- function(paper_id, temperature, repeat_num, sweep_base_dir) {
  run_dir <- file.path(sweep_base_dir, paper_id,
                       sprintf("temp_%.1f", temperature),
                       sprintf("rep_%d", repeat_num))
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)

  t_start <- proc.time()[["elapsed"]]
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

  on.exit(options(llm_temperature = NULL))
  options(llm_temperature = temperature)

  index_ok  <- FALSE
  err_msg   <- NA_character_

  tryCatch({
    run_index(paper_id, output_dir = run_dir)
    index_ok <- TRUE
  }, error = function(e) {
    err_msg <<- conditionMessage(e)
  })

  if (index_ok) {
    tryCatch({
      run_codebook_label(paper_id, output_dir = run_dir)
    }, error = function(e) {
      err_msg <<- conditionMessage(e)
    })
  }

  elapsed_ms <- as.integer(round((proc.time()[["elapsed"]] - t_start) * 1000))
  status     <- if (is.na(err_msg)) "ok" else "failed"

  list(
    status        = status,
    error         = err_msg,
    elapsed_ms    = elapsed_ms,
    run_timestamp = timestamp,
    output_dir    = run_dir
  )
}

# ── Main ──────────────────────────────────────────────────────────────────────

main <- function() {
  args <- parse_sweep_args()

  cat("── Temperature sweep ────────────────────────────────────────────────────\n")
  cat("   paper_id    :", args$paper_id, "\n")
  cat("   temperatures:", paste(args$temperatures, collapse = ", "), "\n")
  cat("   repeats     :", args$repeats, "\n")
  cat("   sweep_dir   :", args$sweep_dir, "\n\n")

  source("./data_check/helper.R")
  source("./data_check/0_index.R")
  source("./data_check/2_codebook_label.R")

  paper_sweep_dir <- file.path(args$sweep_dir, args$paper_id)
  dir.create(paper_sweep_dir, recursive = TRUE, showWarnings = FALSE)
  log_path <- file.path(paper_sweep_dir, "sweep_log.csv")

  log_df <- load_or_create_sweep_log(log_path)

  n_total  <- length(args$temperatures) * args$repeats
  n_done   <- 0L
  n_ok     <- 0L
  n_failed <- 0L

  for (temp in args$temperatures) {
    for (rep in seq_len(args$repeats)) {

      if (sweep_run_done(log_df, args$paper_id, temp, rep)) {
        cat(sprintf("[T=%.1f rep %d/%d] skipped (already done)\n",
                    temp, rep, args$repeats))
        n_done <- n_done + 1L
        next
      }

      cat(sprintf("[T=%.1f rep %d/%d] running...\n", temp, rep, args$repeats))
      result <- run_one(args$paper_id, temp, rep, args$sweep_dir)

      new_row <- data.frame(
        paper_id      = args$paper_id,
        temperature   = temp,
        repeat_num    = rep,
        output_dir    = result$output_dir,
        status        = result$status,
        error         = ifelse(is.na(result$error), "", result$error),
        elapsed_ms    = result$elapsed_ms,
        run_timestamp = result$run_timestamp,
        stringsAsFactors = FALSE
      )
      append_sweep_log(log_path, new_row)
      log_df <- rbind(log_df, new_row)

      elapsed_s <- round(result$elapsed_ms / 1000)
      cat(sprintf("[T=%.1f rep %d/%d] %s (%ds)\n",
                  temp, rep, args$repeats, result$status, elapsed_s))

      n_done <- n_done + 1L
      if (result$status == "ok") n_ok <- n_ok + 1L else n_failed <- n_failed + 1L
    }
  }

  cat("\n── Sweep complete ───────────────────────────────────────────────────────\n")
  cat(sprintf("   %d/%d runs completed  |  %d ok  |  %d failed\n",
              n_done, n_total, n_ok, n_failed))
  cat("   Log:", log_path, "\n")
}

# ── Resume behaviour note ─────────────────────────────────────────────────────
# Re-running with the same args skips all completed (paper_id, temperature,
# repeat_num) combinations that already exist in sweep_log.csv, verified by
# sweep_run_done(). No re-runs occur unless rows are manually deleted from the
# log (same pattern as run_index_bulk.R / Principle I).

if (!interactive()) main()

# app.R  —  Validation GUI
# Human ground-truth labelling tool for pipeline structure.csv outputs.
#
# Launch from data_check/:  shiny::runApp("tools/validation_gui")
# Launch from repo root:    shiny::runApp("data_check/tools/validation_gui")

library(shiny)
library(bslib)

# ── Locate data_check root ────────────────────────────────────────────────────

local({
  # Shiny sets CWD to the app directory (tools/validation_gui/) when running.
  # DC root is two levels up from there.
  root <- normalizePath(file.path(getwd(), "../.."))
  if (!dir.exists(file.path(root, "outputs"))) {
    stop("Cannot locate outputs/ directory. Expected at: ", file.path(root, "outputs"))
  }
  options(dc_root = root)
})

source(file.path(getOption("dc_root"), "tools", "validation_gui", "gt_store.R"))
source(file.path(getOption("dc_root"), "tools", "validation_gui", "preview.R"))

# ── Constants ─────────────────────────────────────────────────────────────────

TYPE_MAP <- c(
  "1" = "data", "2" = "code",   "3" = "codebook", "4" = "supplemental",
  "5" = "doc",  "6" = "readme", "7" = "asset",    "8" = "other"
)
VALID_TYPES <- unname(TYPE_MAP)

# ── JavaScript ────────────────────────────────────────────────────────────────

KB_JS <- '
document.addEventListener("DOMContentLoaded", function() {

  // Custom message: focus the group text input
  Shiny.addCustomMessageHandler("focus_group", function(msg) {
    var el = document.getElementById("group_val");
    if (el) { el.focus(); el.select(); }
  });

  // ── XML search: client-side highlight (no Shiny round-trip) ──────────────
  window.xmlHighlight = function(query) {
    var el = document.getElementById("xml_text_content");
    var ctr = document.getElementById("xml_hit_count");
    if (!el) return;

    // Cache raw text on first call or after a paper switch
    if (!el._rawText) el._rawText = el.textContent;
    var raw = el._rawText;

    if (!query || query.length < 1) {
      el.textContent = raw;
      if (ctr) ctr.textContent = "";
      return;
    }

    // HTML-escape raw text, then wrap matches in <mark>
    var esc = raw.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
    var qEsc = query.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
    var qRe  = new RegExp(qEsc.replace(/[.*+?^${}()|[\\]\\\\]/g,"\\\\$&"), "gi");
    var hits = 0;
    var html = esc.replace(qRe, function(m) {
      hits++;
      return "<mark style=\\"background:#ffe066;padding:0;\\">" + m + "</mark>";
    });
    el.innerHTML = html;
    if (ctr) ctr.textContent = hits > 0
      ? hits + " match" + (hits === 1 ? "" : "es")
      : "no matches";
  };

  // Reset cached raw text when a new paper is loaded (xml panel re-renders)
  var xmlObs = new MutationObserver(function() {
    var el = document.getElementById("xml_text_content");
    if (el) el._rawText = null;
  });
  xmlObs.observe(document.body, { childList: true, subtree: true });

  // Custom message: enable/disable the is_raw checkbox
  Shiny.addCustomMessageHandler("set_is_raw_disabled", function(msg) {
    var el = document.getElementById("is_raw_val");
    if (!el) return;
    el.disabled = msg.disabled;
    var wrap = el.closest(".form-check") || el.parentElement;
    if (wrap) wrap.style.opacity = msg.disabled ? "0.45" : "1";
  });

  // Track whether a text input has keyboard focus
  document.addEventListener("focusin", function(e) {
    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") {
      Shiny.setInputValue("text_focused", true, {priority: "event"});
    }
  });
  document.addEventListener("focusout", function(e) {
    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") {
      Shiny.setInputValue("text_focused", false, {priority: "event"});
    }
  });

  // Global keydown handler
  document.addEventListener("keydown", function(e) {
    // Cmd+Enter, Cmd+[, Cmd+/ work everywhere (even in text inputs)
    if (e.metaKey && e.key === "Enter") {
      e.preventDefault();
      Shiny.setInputValue("key_press", {key: "cmd_enter",   ts: Date.now()}, {priority: "event"});
      return;
    }
    if (e.metaKey && e.key === "[") {
      e.preventDefault();
      Shiny.setInputValue("key_press", {key: "cmd_bracket", ts: Date.now()}, {priority: "event"});
      return;
    }
    if (e.metaKey && e.key === "/") {
      e.preventDefault();
      Shiny.setInputValue("key_press", {key: "cmd_slash",   ts: Date.now()}, {priority: "event"});
      return;
    }

    // All remaining shortcuts are suppressed when a text input is focused
    var inText = document.activeElement &&
      (document.activeElement.tagName === "INPUT" ||
       document.activeElement.tagName === "TEXTAREA");
    if (inText) return;

    if (e.key === "Tab") {
      e.preventDefault();
      Shiny.setInputValue("key_press", {key: "tab", ts: Date.now()}, {priority: "event"});
      return;
    }

    var k = e.key.toLowerCase();
    if (["1","2","3","4","5","6","7","8","r","g"].indexOf(k) !== -1) {
      e.preventDefault();
      Shiny.setInputValue("key_press", {key: k, ts: Date.now()}, {priority: "event"});
    }
  });
});
'

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- page_sidebar(
  title    = "Validation GUI",
  theme    = bs_theme(bootswatch = "flatly"),
  fillable = TRUE,
  tags$head(
    tags$script(HTML(KB_JS)),
    tags$style(HTML("
      html, body { height: 100%; overflow: hidden; }
      .bslib-sidebar-layout { height: 100vh; }
      .bslib-sidebar-layout > .main { height: 100%; overflow: hidden; }
      #file_list_ui .file-row { padding: 5px 8px; border-radius: 4px;
        cursor: pointer; margin-bottom: 2px; font-size: 0.84em;
        border-left: 3px solid transparent; }
      #file_list_ui .file-row.is-unvisited { background: transparent; }
      #file_list_ui .file-row.is-validated {
        background: #d4edda; border-left-color: #28a745; }
      #file_list_ui .file-row.is-skipped {
        background: #fff3cd; border-left-color: #ffc107; color: #5a5a00; }
      #file_list_ui .file-row.is-current {
        background: #e65c00 !important; color: #fff !important;
        border-left-color: #b34500 !important; font-weight: 700; }
    "))
  ),

  sidebar = sidebar(
    width    = 300,
    fillable = TRUE,
    selectInput("paper_id", "Paper", choices = character(0)),
    tags$div(class = "fw-bold text-primary", style = "font-size:0.9em;",
             textOutput("progress_counter")),
    tags$hr(style = "margin:5px 0;"),
    div(style = "overflow-y:auto; flex:1; min-height:0;",
        uiOutput("file_list_ui"))
  ),

  # ── Main panel — flex column, footer always visible ──────────────────────────
  div(
    style = "display:flex; flex-direction:column; height:100%; overflow:hidden;",

    # Context area (takes all remaining space, scrolls internally)
    div(
      style = "flex:1; min-height:0; overflow-y:auto; padding:14px 18px;",
      uiOutput("context_header_ui"),
      uiOutput("xml_panel_ui"),
      tags$details(
        style = "margin-top:6px;",
        tags$summary(tags$small(tags$strong("Repository tree"))),
        uiOutput("folder_tree_ui")
      ),
      tags$hr(style = "margin:8px 0;"),
      uiOutput("preview_ui")
    ),

    # Label controls — flex-shrink:0 keeps it anchored at the bottom
    div(
      style = paste(
        "flex-shrink:0; padding:10px 16px 12px; background:#f8f9fa;",
        "border-top:2px solid #dee2e6;"
      ),
      uiOutput("type_buttons_ui"),
      uiOutput("prediction_note_ui"),
      div(
        style = "display:flex; align-items:flex-end; gap:12px; margin-top:6px;",
        div(style = "flex:1; min-width:120px; max-width:220px;",
            textInput("group_val", tags$small("Group"), value = "",
                      placeholder = "ex1, other, na …")),
        div(style = "padding-bottom:7px;",
            checkboxInput("is_raw_val", tags$small("is_raw"), value = FALSE)),
        div(
          style = "margin-left:auto; display:flex; gap:6px; padding-bottom:4px;",
          actionButton("btn_back", "← Prev",      class = "btn-sm btn-outline-secondary"),
          actionButton("btn_skip", "Skip",          class = "btn-sm btn-outline-secondary"),
          actionButton("btn_save", "Save & Next →", class = "btn-sm btn-primary")
        )
      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  rv <- reactiveValues(
    annotator     = "",
    papers        = character(0),  # full ordered list of discovered papers
    paper_id      = NULL,
    structure     = NULL,
    gt            = empty_gt(),
    current_idx   = 1L,
    status        = character(0),  # named: "unvisited"/"validated"/"skipped"
    selected_type = NA_character_,
    is_raw_val    = FALSE,
    skipped       = integer(0),    # in-memory only, not persisted
    xml           = NULL           # list(title, abstract, body) or NULL
  )

  # ── T019: Startup annotator dialog ──────────────────────────────────────────

  showModal(modalDialog(
    title      = "Who is annotating?",
    textInput("annotator_input", "Your name or initials", placeholder = "e.g. LB"),
    footer     = actionButton("btn_start", "Start →", class = "btn-primary"),
    easyClose  = FALSE
  ))

  observeEvent(input$btn_start, {
    name <- trimws(input$annotator_input)
    if (nchar(name) == 0) {
      showNotification("Please enter your name or initials.", type = "error")
      return()
    }
    rv$annotator <- name
    removeModal()
    papers <- discover_papers()
    rv$papers <- papers
    updateSelectInput(session, "paper_id",
                      choices  = papers,
                      selected = if (length(papers) > 0) papers[1] else NULL)
  })

  # ── T008: Paper selection ────────────────────────────────────────────────────

  observeEvent(input$paper_id, {
    req(nchar(trimws(input$paper_id)) > 0)
    pid <- input$paper_id
    struct <- tryCatch(load_structure(pid), error = function(e) {
      showNotification(paste("Failed to load structure.csv:", conditionMessage(e)),
                       type = "error")
      NULL
    })
    req(!is.null(struct))

    rv$paper_id  <- pid
    rv$structure <- struct
    rv$xml       <- load_paper_xml(pid)

    # T016: load GT and build status vector
    gt <- read_gt(pid)
    rv$gt <- gt

    n  <- nrow(struct)
    st <- setNames(rep("unvisited", n), struct$rel_path)
    st[names(st) %in% gt$rel_path] <- "validated"
    rv$status  <- st
    rv$skipped <- integer(0)

    # T018: position on first unvalidated file
    first_uv <- which(st != "validated")
    rv$current_idx <- if (length(first_uv) > 0) first_uv[1] else 1L

    load_file(rv$current_idx)
  })

  # ── T017: Load file into controls ───────────────────────────────────────────

  load_file <- function(idx) {
    req(!is.null(rv$structure))
    if (idx < 1L || idx > nrow(rv$structure)) return()
    row     <- rv$structure[idx, ]
    gt_row  <- rv$gt[rv$gt$rel_path == row$rel_path, ]
    if (nrow(gt_row) > 0) {
      rv$selected_type <- gt_row$type_gt[1]
      rv$is_raw_val    <- isTRUE(gt_row$is_raw_gt[1])
      updateTextInput(session,   "group_val",   value = gt_row$group_gt[1])
      updateCheckboxInput(session, "is_raw_val", value = rv$is_raw_val)
    } else {
      rv$selected_type <- if (!is.na(row$type)) row$type else "other"
      rv$is_raw_val    <- isTRUE(row$is_raw)
      updateTextInput(session,   "group_val",   value = row$group)
      updateCheckboxInput(session, "is_raw_val", value = rv$is_raw_val)
    }
  }

  # ── T012: is_raw sync + disable for non-data types ──────────────────────────

  observeEvent(input$is_raw_val, {
    rv$is_raw_val <- input$is_raw_val
  })

  observe({
    sel     <- isolate(rv$selected_type)
    is_data <- !is.na(sel) && sel == "data"
    if (!is_data && isTRUE(isolate(rv$is_raw_val))) {
      rv$is_raw_val <- FALSE
      updateCheckboxInput(session, "is_raw_val", value = FALSE)
    }
    session$sendCustomMessage("set_is_raw_disabled", list(disabled = !is_data))
  }) |> bindEvent(rv$selected_type, ignoreInit = FALSE)

  # ── T009/T010: File list click + type button clicks ──────────────────────────

  observeEvent(input$file_click, {
    req(!is.null(rv$structure))
    idx <- suppressWarnings(as.integer(input$file_click))
    if (!is.na(idx) && idx >= 1L && idx <= nrow(rv$structure)) {
      rv$current_idx <- idx
      load_file(idx)
    }
  })

  for (.i in seq_along(TYPE_MAP)) {
    local({
      type_val <- TYPE_MAP[[.i]]
      btn_id   <- paste0("type_btn_", type_val)
      observeEvent(input[[btn_id]], {
        rv$selected_type <- type_val
      }, ignoreInit = TRUE)
    })
  }

  # ── T021/T022: Keyboard dispatch ─────────────────────────────────────────────

  observeEvent(input$key_press, {
    k <- input$key_press$key
    switch(k,
      "1" = { rv$selected_type <- "data" },
      "2" = { rv$selected_type <- "code" },
      "3" = { rv$selected_type <- "codebook" },
      "4" = { rv$selected_type <- "supplemental" },
      "5" = { rv$selected_type <- "doc" },
      "6" = { rv$selected_type <- "readme" },
      "7" = { rv$selected_type <- "asset" },
      "8" = { rv$selected_type <- "other" },
      "r" = {
        if (!is.na(rv$selected_type) && rv$selected_type == "data") {
          new_val <- !rv$is_raw_val
          rv$is_raw_val <- new_val
          updateCheckboxInput(session, "is_raw_val", value = new_val)
        }
      },
      "g"           = { session$sendCustomMessage("focus_group", list()) },
      "tab"         = { do_skip() },
      "cmd_enter"   = { do_save() },
      "cmd_bracket" = { do_back() },
      "cmd_slash"   = { show_kb_help() }
    )
  })

  # ── T013: Save action ────────────────────────────────────────────────────────

  do_save <- function() {
    req(!is.null(rv$structure), !is.na(rv$selected_type), nchar(rv$annotator) > 0)
    idx <- rv$current_idx
    if (idx < 1L || idx > nrow(rv$structure)) return()
    row <- rv$structure[idx, ]

    is_raw_save <- if (rv$selected_type == "data") rv$is_raw_val else FALSE

    new_row <- data.frame(
      paper_id     = rv$paper_id,
      rel_path     = row$rel_path,
      type_gt      = rv$selected_type,
      group_gt     = trimws(input$group_val),
      is_raw_gt    = is_raw_save,
      validated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      annotator    = rv$annotator,
      stringsAsFactors = FALSE
    )

    rv$gt <- upsert_gt(rv$gt, new_row)
    write_gt(rv$paper_id, rv$gt)

    rv$status[row$rel_path] <- "validated"
    rv$skipped <- rv$skipped[rv$skipped != idx]

    advance_to_next()
  }

  observeEvent(input$btn_save, { do_save() })

  # ── T014: Skip action ────────────────────────────────────────────────────────

  do_skip <- function() {
    req(!is.null(rv$structure))
    idx <- rv$current_idx
    if (idx >= 1L && idx <= nrow(rv$structure)) {
      rp <- rv$structure$rel_path[idx]
      if (rv$status[rp] != "validated") rv$status[rp] <- "skipped"
      rv$skipped <- unique(c(rv$skipped, idx))
    }
    advance_to_next()
  }

  observeEvent(input$btn_skip, { do_skip() })

  # ── T014: Back action ────────────────────────────────────────────────────────

  do_back <- function() {
    req(!is.null(rv$structure))
    new_idx <- max(1L, rv$current_idx - 1L)
    rv$current_idx <- new_idx
    load_file(new_idx)
  }

  observeEvent(input$btn_back, { do_back() })

  # ── Advance to next unvalidated file (or next paper when done) ───────────────

  advance_to_next <- function() {
    req(!is.null(rv$structure))
    idx        <- rv$current_idx
    candidates <- which(rv$status != "validated")
    forward    <- candidates[candidates > idx]

    if (length(forward) > 0) {
      # Normal case: more unvalidated files ahead
      rv$current_idx <- forward[1]
      load_file(forward[1])
    } else if (length(candidates) > 0) {
      # Wrap: unvalidated files exist but all are before current position
      rv$current_idx <- candidates[1]
      load_file(candidates[1])
    } else {
      # All files validated — advance to next paper
      papers     <- rv$papers
      cur_paper  <- rv$paper_id
      cur_pos    <- match(cur_paper, papers)
      next_paper <- if (!is.na(cur_pos) && cur_pos < length(papers))
        papers[cur_pos + 1L] else NULL

      if (!is.null(next_paper)) {
        showNotification(
          paste0("Paper complete! Moving to ", next_paper),
          type = "message", duration = 3
        )
        updateSelectInput(session, "paper_id", selected = next_paper)
      } else {
        showNotification("All papers complete!", type = "message", duration = 5)
      }
    }
  }

  # ── T023: Keyboard help modal ────────────────────────────────────────────────

  show_kb_help <- function() {
    showModal(modalDialog(
      title     = "Keyboard shortcuts",
      size      = "l",
      easyClose = TRUE,
      tags$table(
        class = "table table-sm table-bordered",
        tags$thead(tags$tr(tags$th("Key"), tags$th("Action"))),
        tags$tbody(
          tags$tr(tags$td(HTML("<kbd>1</kbd>–<kbd>8</kbd>")),
                  tags$td("Select type: data / code / codebook / supplemental / doc / readme / asset / other")),
          tags$tr(tags$td(HTML("<kbd>R</kbd>")),
                  tags$td("Toggle is_raw (active only when type = data)")),
          tags$tr(tags$td(HTML("<kbd>G</kbd>")),
                  tags$td("Move focus to the group text input")),
          tags$tr(tags$td(HTML("<kbd>⌘↩</kbd>")),
                  tags$td("Save labels and advance to next unvalidated file")),
          tags$tr(tags$td(HTML("<kbd>Tab</kbd>")),
                  tags$td("Skip current file (no save)")),
          tags$tr(tags$td(HTML("<kbd>⌘[</kbd>")),
                  tags$td("Go back to previous file")),
          tags$tr(tags$td(HTML("<kbd>⌘/</kbd>")),
                  tags$td("Show this keyboard reference"))
        )
      ),
      footer = modalButton("Close")
    ))
  }

  # ── Rendered outputs ──────────────────────────────────────────────────────────

  # T015: Progress counter
  output$progress_counter <- renderText({
    req(!is.null(rv$structure))
    n_v <- sum(rv$status == "validated")
    n_t <- length(rv$status)
    sprintf("Validated: %d / %d", n_v, n_t)
  })

  # T009: File list
  output$file_list_ui <- renderUI({
    req(!is.null(rv$structure))
    cur <- rv$current_idx
    rows <- lapply(seq_len(nrow(rv$structure)), function(i) {
      row    <- rv$structure[i, ]
      stat   <- rv$status[row$rel_path]
      is_cur <- identical(i, cur)

      # CSS class drives all visual states (see tags$style in UI)
      css_class <- paste(
        "file-row",
        if (is_cur)                    "is-current",
        if (stat == "validated")       "is-validated",
        if (stat == "skipped")         "is-skipped",
        if (stat == "unvisited")       "is-unvisited"
      )

      icon <- switch(stat,
        "validated" = if (is_cur) "✓ " else "✓ ",
        "skipped"   = "– ",
        ""
      )

      tags$div(
        class   = css_class,
        onclick = sprintf("Shiny.setInputValue('file_click',%d,{priority:'event'})", i),
        paste0(icon, row$filename)
      )
    })
    do.call(tagList, rows)
  })

  # T010: Type buttons
  output$type_buttons_ui <- renderUI({
    sel  <- rv$selected_type
    btns <- lapply(seq_along(TYPE_MAP), function(i) {
      val <- TYPE_MAP[[i]]
      is_active <- !is.na(sel) && sel == val
      actionButton(
        inputId = paste0("type_btn_", val),
        label   = paste0("[", i, "] ", val),
        class   = paste(
          "btn btn-sm me-1 mb-1",
          if (is_active) "btn-primary" else "btn-outline-secondary"
        )
      )
    })
    do.call(tagList, btns)
  })

  # T034: Prediction mismatch note
  output$prediction_note_ui <- renderUI({
    req(!is.null(rv$structure))
    idx <- rv$current_idx
    if (idx < 1L || idx > nrow(rv$structure)) return(NULL)
    machine <- rv$structure$type[idx]
    sel     <- rv$selected_type
    if (!is.na(sel) && !is.na(machine) && sel != machine) {
      tags$small(class = "text-muted", paste("LLM predicted:", machine))
    }
  })

  # T031: Context header
  output$context_header_ui <- renderUI({
    req(!is.null(rv$structure))
    idx <- rv$current_idx
    if (idx < 1L || idx > nrow(rv$structure)) return(NULL)
    row  <- rv$structure[idx, ]
    path <- row$path

    fsize <- tryCatch({
      s <- file.info(path)$size
      if (is.na(s) || is.null(s)) "? (not on disk)"
      else if (s >= 1e9) sprintf("%.1f GB", s / 1e9)
      else if (s >= 1e6) sprintf("%.1f MB", s / 1e6)
      else if (s >= 1e3) sprintf("%.1f KB", s / 1e3)
      else paste0(as.integer(s), " B")
    }, error = function(e) "?")

    sentinel_note <- if (isTRUE(row$is_sentinel)) {
      tags$div(
        class = "alert alert-warning py-1 px-2 mb-2",
        style = "font-size:0.85em;",
        tags$strong("Aggregate folder"),
        " — this row represents a collapsed folder of 50+ files.",
        " Labels apply to the folder as a whole."
      )
    }

    tagList(
      sentinel_note,
      tags$div(
        class = "d-flex align-items-baseline gap-2 flex-wrap mb-1",
        tags$h5(class = "mb-0 text-break", row$filename),
        tags$small(class = "text-muted", row$rel_path)
      ),
      tags$div(
        class = "d-flex align-items-center gap-2 flex-wrap",
        tags$span(class = "text-muted", style = "font-size:0.82em;",
                  sprintf("ext: %s  •  %s  •  file %d / %d",
                          row$ext, fsize, idx, nrow(rv$structure))),
        tags$span(class = "badge bg-primary",            row$type),
        tags$span(class = "badge bg-secondary",          paste("group:", row$group)),
        if (isTRUE(row$is_raw))
          tags$span(class = "badge bg-warning text-dark", "raw")
      )
    )
  })

  # T033: Folder tree
  output$folder_tree_ui <- renderUI({
    req(!is.null(rv$structure))
    cur_rp <- if (rv$current_idx >= 1L && rv$current_idx <= nrow(rv$structure))
      rv$structure$rel_path[rv$current_idx] else ""

    lines <- mapply(function(rp, fn, tp, grp) {
      depth  <- length(strsplit(rp, "/", fixed = TRUE)[[1]]) - 1L
      indent <- paste(rep("  ", max(0L, depth)), collapse = "")
      marker <- if (rp == cur_rp) "●" else " "
      sprintf("%s%s %-28s  [%s/%s]", indent, marker,
              substr(fn, 1, 28), tp, grp)
    }, rv$structure$rel_path, rv$structure$filename,
       rv$structure$type,     rv$structure$group,
       SIMPLIFY = TRUE)

    tags$pre(
      style = "font-size:0.72em; max-height:220px; overflow-y:auto; margin:0;",
      paste(lines, collapse = "\n")
    )
  })

  # T032+T033: File preview + sibling list
  output$preview_ui <- renderUI({
    req(!is.null(rv$structure))
    idx <- rv$current_idx
    if (idx < 1L || idx > nrow(rv$structure)) return(NULL)
    row    <- rv$structure[idx, ]
    parent <- dirname(row$rel_path)

    # Sibling files
    sibs <- rv$structure[dirname(rv$structure$rel_path) == parent, ]
    sib_lines <- sprintf(
      "  %s%s  [%s]",
      sibs$filename,
      ifelse(sibs$rel_path == row$rel_path, "  ← current", ""),
      sibs$type
    )
    sib_block <- tags$div(
      tags$small(tags$strong(sprintf("Siblings in %s/", parent))),
      tags$pre(
        style = "font-size:0.75em; max-height:120px; overflow-y:auto; margin-bottom:4px;",
        paste(sib_lines, collapse = "\n")
      )
    )

    # File preview (T036: guard for missing file)
    preview_block <- tags$div(
      style = "max-height:380px; overflow-y:auto; border:1px solid #dee2e6; border-radius:4px; padding:8px;",
      render_preview(row$path, row$ext)
    )

    tagList(sib_block, tags$hr(style = "margin:6px 0;"), preview_block)
  })

  # ── Paper XML preview (searchable) ──────────────────────────────────────────

  output$xml_panel_ui <- renderUI({
    xml <- rv$xml
    if (is.null(xml)) return(NULL)

    query <- trimws(if (!is.null(input$xml_search)) input$xml_search else "")

    # Highlight query matches inside already-escaped HTML
    hl <- function(txt) {
      if (nchar(txt) == 0) return("")
      esc <- htmltools::htmlEscape(txt)
      if (nchar(query) == 0) return(esc)
      q_esc <- htmltools::htmlEscape(query)
      gsub(q_esc,
           paste0("<mark style='background:#ffe066; padding:0;'>", q_esc, "</mark>"),
           esc, ignore.case = TRUE, fixed = FALSE)
    }

    parts <- character(0)
    if (nchar(xml$title) > 0)
      parts <- c(parts, paste0("<strong style='font-size:1.02em;'>",
                               htmltools::htmlEscape(xml$title), "</strong>"))
    if (nchar(xml$abstract) > 0)
      parts <- c(parts, paste0(
        "<span style='color:#555; font-size:0.78em; font-weight:600;'>ABSTRACT</span><br>",
        hl(xml$abstract)))
    if (nchar(xml$body) > 0)
      parts <- c(parts, paste0(
        "<span style='color:#555; font-size:0.78em; font-weight:600;'>BODY</span><br>",
        hl(xml$body)))

    content_html <- paste(
      parts,
      collapse = "<hr style='margin:5px 0; border-color:#ddd;'>"
    )

    n_hits <- if (nchar(query) > 0)
      lengths(regmatches(content_html,
                         gregexpr(htmltools::htmlEscape(query), content_html,
                                  ignore.case = TRUE)))
    else 0L
    hit_label <- if (nchar(query) > 0 && n_hits > 0)
      tags$small(class = "text-success ms-2", sprintf("%d match%s", n_hits,
                                                       if (n_hits == 1) "" else "es"))
    else if (nchar(query) > 0)
      tags$small(class = "text-muted ms-2", "no matches")
    else NULL

    tags$details(
      open  = "",
      style = "margin-top:10px; margin-bottom:4px;",
      tags$summary(
        style = "cursor:pointer;",
        tags$small(tags$strong("Paper text")),
        hit_label
      ),
      div(
        style = "padding:6px 0 2px;",
        div(
          style = "display:flex; align-items:center; gap:6px; margin-bottom:6px;",
          tags$input(
            id          = "xml_search",
            type        = "text",
            class       = "form-control form-control-sm",
            placeholder = "Search paper text…",
            value       = query,
            oninput     = paste0(
              "Shiny.setInputValue('xml_search', this.value, {priority:'event'})"
            ),
            style       = "max-width:320px;"
          )
        ),
        div(
          style = paste(
            "max-height:280px; overflow-y:auto; font-size:0.77em;",
            "white-space:pre-wrap; word-break:break-word;",
            "border:1px solid #dee2e6; border-radius:4px;",
            "padding:8px; background:#fafafa; line-height:1.55;"
          ),
          HTML(content_html)
        )
      )
    )
  })

  # ── T037: Session summary on exit ────────────────────────────────────────────

  onStop(function() {
    pid       <- isolate(rv$paper_id)
    struct    <- isolate(rv$structure)
    if (is.null(pid) || is.null(struct)) return()
    status    <- isolate(rv$status)
    gt        <- isolate(rv$gt)
    annotator <- isolate(rv$annotator)
    n_v  <- sum(status == "validated")
    n_t  <- length(status)
    corr <- 0L
    if (nrow(gt) > 0) {
      m <- merge(gt,
                 struct[, c("rel_path", "type", "group", "is_raw")],
                 by = "rel_path", all.x = TRUE)
      corr <- sum(!is.na(m$type_gt) & !is.na(m$type) & m$type_gt != m$type,
                  na.rm = TRUE)
    }
    gt_path <- file.path(getOption("dc_root", "."), "ground_truth",
                         paste0(pid, ".csv"))
    cat("\n=== Validation session complete ===\n")
    cat(sprintf("  Annotator:   %s\n",  annotator))
    cat(sprintf("  Paper:       %s\n",  pid))
    cat(sprintf("  Validated:   %d / %d files\n", n_v, n_t))
    cat(sprintf("  Corrections: %d  (type differs from LLM prediction)\n", corr))
    cat(sprintf("  Saved to:    %s\n",  gt_path))
    cat("===================================\n\n")
  })
}

shinyApp(ui, server)

# Scenario Economic Model dashboard (Shiny).
#
# Replaces the React + Express frontend. It requires only R: the intended
# users have R installed but not Node.js. Run it by double-clicking
# start_dashboard.cmd, or from R: shiny::runApp("dashboard").
#
# Tabs:
#   - Headlines: the central forecast for the key aggregates, history and
#     forecast on one chart.
#   - All variables: every model variable (outputs/model_results_flat.xlsx)
#     over the full historical and forecast span, with level and annual-growth
#     views and CSV download.
#   - Scenario library: lists runs in scenario-runs/ and overlays any
#     completed scenario on the central forecast.
#   - Build a scenario: applies adjustments to the shock file and runs
#     R/run_scenario.R in the background, exactly as the previous API did.
#
# Dependencies: shiny, jsonlite, openxlsx (all used by the model project).

suppressPackageStartupMessages({
  library(shiny)
  library(jsonlite)
  library(openxlsx)
})

# ---- locate the repository root --------------------------------------------------
# shiny runs the app with the working directory set to this folder, so the
# root is one level up; fall back to the current directory for launch styles
# that keep the repo root as the working directory.
find_root <- function() {
  parent <- normalizePath(file.path(getwd(), ".."), winslash = "/")
  here <- normalizePath(getwd(), winslash = "/")
  if (file.exists(file.path(parent, "outputs", "model_results_flat.xlsx"))) {
    return(parent)
  }
  if (file.exists(file.path(here, "outputs", "model_results_flat.xlsx"))) {
    return(here)
  }
  stop("Run the dashboard from the SEM repository (start_dashboard.cmd or ",
       "shiny::runApp(\"dashboard\") from the project root).")
}

root <- find_root()
flat_path <- file.path(root, "outputs", "model_results_flat.xlsx")
runs_root <- file.path(root, "scenario-runs")
baseline_shocks_path <- file.path(root, "data-raw", "shocks.csv")
baseline_exogenous_path <- file.path(root, "data-raw", "exogenous_forecast.csv")
run_scenario_path <- file.path(root, "R", "run_scenario.R")

source("labels.R", local = TRUE)

if (!file.exists(flat_path)) {
  stop("Model outputs are missing (", flat_path, "). Run Rscript run_model.R first.")
}
flat <- read.xlsx(flat_path, sheet = "Data", detectDates = TRUE)
flat$date <- as.Date(flat$date)
flat <- flat[order(flat$date), ]
variable_names <- setdiff(names(flat), c("date", "period"))
forecast_origin <- min(flat$date[flat$period == "Forecast"])
forecast_horizon <- max(flat$date)
data_end <- max(flat$date[flat$period == "Actual"])
first_year_end <- format(seq(forecast_origin, by = "quarter", length.out = 4)[4])
forecast_quarters <- seq(forecast_origin, forecast_horizon, by = "quarter")

# The shockable variables are exactly the columns of the baseline shock file.
shock_variables <- setdiff(names(read.csv(baseline_shocks_path, nrows = 1)), "date")

labelled_choices <- function(variables) {
  labels <- vapply(variables, function(v) {
    lab <- if (v %in% names(variable_labels)) unname(variable_labels[[v]]) else v
    paste0(v, " – ", lab)
  }, character(1))
  setNames(variables, labels)
}

quarter_year <- function(dates) as.integer(format(dates, "%Y"))
quarter_n <- function(dates) (as.integer(format(dates, "%m")) + 2) %/% 3
quarter_label <- function(date) paste0(quarter_year(date), "Q", quarter_n(date))

# ---- shock conventions (see README "Run directly") ------------------------------
additive_equation <- c("LavhMkt", "Lpar", "Rmort", "Whh", "GovDebt", "R90d", "R10y")
additive_exogenous <- c("IvtFar", "Fr10yUs", "Fr10yJp", "Fr10yDe", "Fr10yUk")
ratio_equation <- "Ynli"

shock_unit <- function(variable) {
  if (variable %in% c(additive_equation, additive_exogenous)) "additive" else
  if (variable %in% ratio_equation) "ratio" else "log"
}

shock_hint <- function(variable) {
  switch(shock_unit(variable),
    additive = paste0("Additive in model units. Decimal rates (R90d, R10y, Rmort, ",
                      "Lpar) take pp / 100: enter 0.01 for +1pp. LavhMkt is hours; ",
                      "Whh and GovDebt are $m levels."),
    ratio = "Additive to the modelled non-labour household income ratio.",
    "Log innovation: enter a percentage change; 20 applies +20%."
  )
}

default_unit_mode <- function(variable) {
  if (shock_unit(variable) == "log") "percent" else "units"
}

# ---- plotting helpers --------------------------------------------------------------
plot_series <- function(dates, values, period, origin, title, ylab, log_y = FALSE) {
  values <- as.numeric(values)
  keep <- is.finite(values)
  dates <- dates[keep]; values <- values[keep]; period <- period[keep]
  par(mar = c(4.2, 4.5, 2.5, 1))
  ylim <- range(values, na.rm = TRUE)
  if (log_y && all(values > 0)) {
    plot(NA, xlim = range(dates), ylim = ylim, log = "y",
         xlab = "", ylab = ylab, main = title)
  } else {
    plot(NA, xlim = range(dates), ylim = ylim, xlab = "", ylab = ylab, main = title)
  }
  actual <- period == "Actual"
  if (any(actual)) lines(dates[actual], values[actual], col = "#1f4e79", lwd = 2)
  forecast <- period == "Forecast"
  if (any(forecast)) lines(dates[forecast], values[forecast], col = "#c0392b", lwd = 2, lty = 2)
  abline(v = origin, col = "grey40", lty = 3)
  box()
}

fmt_value <- function(x, digits = 2) {
  if (length(x) < 1 || is.na(x)) return("-")
  if (abs(x) >= 1000) formatC(x, big.mark = ",", format = "d") else
    formatC(x, format = "f", digits = digits)
}

fmt_pct <- function(x, digits = 2) {
  if (length(x) < 1 || is.na(x)) return("-")
  formatC(100 * x, format = "f", digits = digits)
}

lag4 <- function(x) {
  out <- rep(NA_real_, length(x))
  if (length(x) > 4) out[5:length(x)] <- as.numeric(x)[1:(length(x) - 4)]
  out
}

annual_growth <- function(x) 100 * (as.numeric(x) / lag4(x) - 1)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

run_status_of <- function(run_dir, meta) {
  status_file <- file.path(run_dir, "status.txt")
  if (file.exists(status_file)) {
    return(trimws(readLines(status_file, warn = FALSE)[1]))
  }
  if (file.exists(file.path(run_dir, "forecast.csv"))) return("completed")
  meta$status %||% "running"
}

# ---- ui ------------------------------------------------------------------------------
adj_choices <- labelled_choices(unique(c(
  c("Fpoil", "Lnom", "Cgov", "R90d"), shock_variables
)))

ui <- navbarPage(
  "Scenario Economic Model",
  tabPanel(
    "Headlines",
    fluidRow(
      column(3, wellPanel(h4("Real GDP, $m"), verbatimTextOutput("card_ygdp"))),
      column(3, wellPanel(h4("CPI index"), verbatimTextOutput("card_pcpi"))),
      column(3, wellPanel(h4("Unemployment rate, %"), verbatimTextOutput("card_lur"))),
      column(3, wellPanel(h4("Cash rate, %"), verbatimTextOutput("card_r90d")))
    ),
    fluidRow(
      column(6, plotOutput("plot_ygdp", height = "260px")),
      column(6, plotOutput("plot_pcpi", height = "260px"))
    ),
    fluidRow(
      column(6, plotOutput("plot_lur", height = "260px")),
      column(6, plotOutput("plot_r90d", height = "260px"))
    ),
    wellPanel(helpText(HTML(paste0(
      "Actuals to <b>", quarter_label(data_end), "</b>; central forecast <b>",
      quarter_label(forecast_origin), "</b> to <b>", quarter_label(forecast_horizon),
      "</b> from <code>outputs/model_results_flat.xlsx</code>. ",
      "Re-run <code>Rscript run_model.R</code> to refresh the data."
    ))))
  ),
  tabPanel(
    "All variables",
    sidebarLayout(
      sidebarPanel(
        selectizeInput("var_pick", "Variable", labelled_choices(variable_names),
                       selected = "Ygdp"),
        selectInput("var_transform", "Transform",
                    c("Level" = "level", "Annual growth (%)" = "growth")),
        sliderInput("var_years", "Years shown",
                    min = quarter_year(min(flat$date)),
                    max = quarter_year(forecast_horizon),
                    value = c(1990, quarter_year(forecast_horizon)),
                    sep = ""),
        checkboxInput("var_log", "Log scale", FALSE),
        downloadButton("var_download", "Download CSV")
      ),
      mainPanel(
        plotOutput("var_plot", height = "420px"),
        tableOutput("var_table")
      )
    )
  ),
  tabPanel(
    "Scenario library",
    sidebarLayout(
      sidebarPanel(
        uiOutput("library_status"),
        selectizeInput("scen_pick", "Scenario",
                       choices = c("(none)" = ""), selected = ""),
        selectizeInput("scen_var", "Variable", labelled_choices(variable_names),
                       selected = "Ygdp"),
        downloadButton("scen_download", "Download overlay CSV")
      ),
      mainPanel(
        verbatimTextOutput("scen_summary"),
        plotOutput("scen_plot", height = "420px")
      )
    )
  ),
  tabPanel(
    "Build a scenario",
    sidebarLayout(
      sidebarPanel(
        width = 4,
        textInput("scen_name", "Scenario name", ""),
        textInput("scen_notes", "Notes (optional)", ""),
        hr(),
        h5("Add adjustment"),
        selectizeInput("adj_variable", "Variable", adj_choices, selected = "Fpoil"),
        helpText(textOutput("adj_hint")),
        numericInput("adj_value", "Value", value = 0, step = 0.5),
        selectInput("adj_unit_mode", "Entered as",
                    c("Percentage change (log shocks)" = "percent",
                      "Model units (additive shocks)" = "units")),
        selectInput("adj_start", "Start quarter",
                    choices = setNames(format(forecast_quarters),
                                       vapply(forecast_quarters, quarter_label, ""))),
        selectInput("adj_end", "End quarter",
                    choices = setNames(format(forecast_quarters),
                                       vapply(forecast_quarters, quarter_label, "")),
                    selected = first_year_end),
        actionButton("adj_add", "Add adjustment", class = "btn-default"),
        hr(),
        uiOutput("adj_list"),
        actionButton("scen_run", "Run scenario", class = "btn-primary"),
        textOutput("run_status")
      ),
      mainPanel(
        helpText(HTML(paste0(
          "Adjustments are applied to <code>data-raw/shocks.csv</code> for the ",
          "chosen quarters and the model runs in the background via ",
          "<code>R/run_scenario.R</code>. Completed runs appear in the ",
          "<b>Scenario library</b> tab. Ustar (NAIRU) is no longer a scenario ",
          "input; see <code>data-raw/VARIABLE_CHANGES.md</code> for shock units."
        ))),
        verbatimTextOutput("run_log")
      )
    )
  )
)

# ---- server -------------------------------------------------------------------------
server <- function(input, output, session) {

  # -- all variables tab ---------------------------------------------------------
  var_window <- reactive({
    years <- as.integer(format(flat$date, "%Y"))
    flat[years >= input$var_years[1] & years <= input$var_years[2], , drop = FALSE]
  })

  output$var_plot <- renderPlot({
    d <- var_window()
    values <- if (input$var_transform == "growth") {
      annual_growth(d[[input$var_pick]])
    } else {
      as.numeric(d[[input$var_pick]])
    }
    plot_series(d$date, values, d$period, forecast_origin,
                variable_label(input$var_pick),
                if (input$var_transform == "growth") "%" else input$var_pick,
                log_y = input$var_log)
  })

  output$var_table <- renderTable({
    d <- var_window()
    data.frame(
      quarter = vapply(d$date, quarter_label, ""),
      period = d$period,
      value = round(as.numeric(d[[input$var_pick]]), 4)
    )
  })

  output$var_download <- downloadHandler(
    filename = function() paste0("sem_", input$var_pick, ".csv"),
    content = function(file) {
      d <- var_window()
      out <- data.frame(date = format(d$date), period = d$period)
      out[[input$var_pick]] <- as.numeric(d[[input$var_pick]])
      utils::write.csv(out, file, row.names = FALSE, na = "")
    }
  )

  # -- headlines tab ----------------------------------------------------------------
  forecast_rows <- flat[flat$period == "Forecast", ]
  make_card <- function(variable, scale = 1, digits = 2) {
    renderText({
      paste0(
        quarter_label(forecast_origin), ": ",
        fmt_value(scale * forecast_rows[[variable]][1], digits), "\n",
        quarter_label(forecast_horizon), ": ",
        fmt_value(scale * tail(forecast_rows[[variable]], 1), digits)
      )
    })
  }
  output$card_ygdp <- make_card("Ygdp")
  output$card_pcpi <- make_card("Pcpi")
  output$card_lur <- make_card("Lur", scale = 100)
  output$card_r90d <- make_card("R90d", scale = 100)

  output$plot_ygdp <- renderPlot(
    plot_series(flat$date, annual_growth(flat$Ygdp), flat$period, forecast_origin,
                "Real GDP, annual growth", "%")
  )
  output$plot_pcpi <- renderPlot(
    plot_series(flat$date, annual_growth(flat$Pcpi), flat$period, forecast_origin,
                "CPI, annual inflation", "%")
  )
  output$plot_lur <- renderPlot(
    plot_series(flat$date, 100 * flat$Lur, flat$period, forecast_origin,
                "Unemployment rate", "%")
  )
  output$plot_r90d <- renderPlot(
    plot_series(flat$date, 100 * flat$R90d, flat$period, forecast_origin,
                "Cash rate (90-day)", "%")
  )

  # -- scenario library ----------------------------------------------------------------
  scenarios <- reactivePoll(
    intervalMillis = 2000,
    session,
    checkFunc = function() {
      if (!dir.exists(runs_root)) return(0)
      dirs <- list.dirs(runs_root, recursive = FALSE)
      max(file.mtime(dirs), 0)
    },
    valueFunc = function() {
      if (!dir.exists(runs_root)) return(NULL)
      dirs <- list.dirs(runs_root, recursive = FALSE)
      if (!length(dirs)) return(NULL)
      rows <- lapply(dirs, function(d) {
        meta_path <- file.path(d, "scenario.json")
        if (!file.exists(meta_path)) return(NULL)
        meta <- tryCatch(
          jsonlite::fromJSON(meta_path, simplifyVector = FALSE),
          error = function(e) NULL
        )
        if (is.null(meta)) return(NULL)
        data.frame(
          dir = d,
          id = meta$id %||% basename(d),
          name = meta$name %||% basename(d),
          status = run_status_of(d, meta),
          created = meta$createdAt %||% "",
          forecast = file.exists(file.path(d, "forecast.csv")),
          stringsAsFactors = FALSE
        )
      })
      rows <- rows[!vapply(rows, is.null, logical(1))]
      if (!length(rows)) return(NULL)
      out <- do.call(rbind, rows)
      out[order(out$created, decreasing = TRUE), , drop = FALSE]
    }
  )

  scen_choices <- reactiveVal(character(0))

  observe({
    s <- scenarios()
    if (is.null(s) || !any(s$forecast)) return()
    done <- s[s$forecast, , drop = FALSE]
    choices <- setNames(done$dir, paste0(done$name, " (", done$id, ")"))
    if (!identical(sort(names(choices)), sort(scen_choices()))) {
      scen_choices(names(choices))
      updateSelectizeInput(session, "scen_pick", choices = choices,
                           selected = if (input$scen_pick %in% choices) input$scen_pick
                                     else "")
    }
  })

  output$library_status <- renderUI({
    s <- scenarios()
    if (is.null(s) || nrow(s) == 0) {
      helpText("No scenario runs found in scenario-runs/. Build one on the next tab.")
    } else {
      helpText(paste0(nrow(s), " run(s): ",
                      paste(sprintf("%s (%s)", s$name, s$status), collapse = ", ")))
    }
  })

  selected_scenario <- reactive({
    d <- input$scen_pick
    if (is.null(d) || !nzchar(d)) return(NULL)
    forecast_path <- file.path(d, "forecast.csv")
    if (!file.exists(forecast_path)) return(NULL)
    list(
      meta = jsonlite::fromJSON(file.path(d, "scenario.json"), simplifyVector = FALSE),
      forecast = utils::read.csv(forecast_path, check.names = FALSE)
    )
  })

  output$scen_summary <- renderText({
    sc <- selected_scenario()
    if (is.null(sc)) {
      return("Select a completed scenario to compare it with the central forecast.")
    }
    paste0(
      sc$meta$name, " - status: ", run_status_of(d <- input$scen_pick, sc$meta), "\n",
      "Created: ", sc$meta$createdAt %||% "-", "\n",
      "Adjustments: ", length(sc$meta$adjustments %||% list())
    )
  })

  output$scen_plot <- renderPlot({
    central <- flat[flat$period == "Forecast", ]
    var <- input$scen_var
    dates <- central$date
    values <- as.numeric(central[[var]])
    sc <- selected_scenario()
    if (is.null(sc)) {
      plot_series(dates, values, rep("Forecast", length(dates)), forecast_origin,
                  paste(variable_label(var), "- central forecast"), var)
      return()
    }
    sf <- sc$forecast
    sf_dates <- as.Date(sf$date)
    sf_values <- as.numeric(sf[[var]])
    par(mar = c(4.2, 4.5, 2.5, 1))
    ylim <- range(c(values, sf_values), na.rm = TRUE)
    plot(NA, xlim = range(c(dates, sf_dates)), ylim = ylim,
         xlab = "", ylab = var, main = paste("Central vs", sc$meta$name))
    lines(dates, values, col = "#1f4e79", lwd = 2)
    lines(sf_dates, sf_values, col = "#c0392b", lwd = 2, lty = 2)
    legend("topleft", lty = c(1, 2), col = c("#1f4e79", "#c0392b"),
           legend = c("Central forecast", sc$meta$name), bty = "n")
    box()
  })

  output$scen_download <- downloadHandler(
    filename = function() "scenario_overlay.csv",
    content = function(file) {
      sc <- selected_scenario()
      if (is.null(sc)) return(NULL)
      central <- flat[flat$period == "Forecast", ]
      out <- data.frame(date = format(central$date))
      out$central <- as.numeric(central[[input$scen_var]])
      sf <- sc$forecast
      out$scenario <- as.numeric(sf[match(format(as.Date(sf$date)), out$date),
                                   input$scen_var])
      out$difference <- out$scenario - out$central
      utils::write.csv(out, file, row.names = FALSE, na = "")
    }
  )

  # -- build scenario -------------------------------------------------------------------
  adjustments <- reactiveVal(list())

  output$adj_hint <- renderText(shock_hint(input$adj_variable))

  observeEvent(input$adj_variable, {
    updateSelectInput(session, "adj_unit_mode",
                      selected = default_unit_mode(input$adj_variable))
  })

  observeEvent(input$adj_add, {
    if (!is.finite(input$adj_value)) return()
    entry <- list(
      variable = input$adj_variable,
      value = input$adj_value,
      unit_mode = input$adj_unit_mode,
      start = input$adj_start,
      end = input$adj_end
    )
    adjustments(c(adjustments(), list(entry)))
  })

  output$adj_list <- renderUI({
    entries <- adjustments()
    if (!length(entries)) return(helpText("No adjustments yet."))
    rows <- vapply(seq_along(entries), function(i) {
      e <- entries[[i]]
      paste0(i, ". ", e$variable, ": ", e$value, " (", e$unit_mode, "), ",
             quarter_label(as.Date(e$start)), " to ", quarter_label(as.Date(e$end)))
    }, character(1))
    tagList(
      h5("Adjustments"),
      lapply(rows, helpText),
      actionButton("adj_clear", "Clear all")
    )
  })

  observeEvent(input$adj_clear, adjustments(list()))

  latest_run <- reactiveVal(NULL)

  observeEvent(input$scen_run, {
    if (!nzchar(trimws(input$scen_name))) {
      showNotification("Enter a scenario name first.", type = "error")
      return()
    }
    entries <- adjustments()
    if (!length(entries)) {
      showNotification("Add at least one adjustment.", type = "error")
      return()
    }
    shocks <- utils::read.csv(baseline_shocks_path, check.names = FALSE)
    shock_dates <- as.Date(shocks$date)
    for (e in entries) {
      if (!e$variable %in% names(shocks)) {
        showNotification(paste("Unknown shock variable:", e$variable), type = "error")
        return()
      }
      window <- shock_dates >= as.Date(e$start) & shock_dates <= as.Date(e$end)
      value <- if (e$unit_mode == "percent") log(1 + e$value / 100) else e$value
      shocks[window, e$variable] <- value
    }
    run_id <- paste0("SCN-", format(Sys.time(), "%Y%m%d"), "-",
                     paste0(sample(c(LETTERS, 0:9), 6), collapse = ""))
    run_dir <- file.path(runs_root, run_id)
    dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
    exo_copy <- file.path(run_dir, "exogenous_forecast.csv")
    shocks_path <- file.path(run_dir, "shocks.csv")
    file.copy(baseline_exogenous_path, exo_copy, overwrite = TRUE)
    utils::write.csv(shocks, shocks_path, row.names = FALSE, na = "")
    meta <- list(
      id = run_id,
      name = trimws(input$scen_name),
      notes = trimws(input$scen_notes),
      createdAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      adjustments = lapply(entries, function(e) {
        list(variable = e$variable, value = e$value, unit = e$unit_mode,
             start = e$start, end = e$end)
      })
    )
    jsonlite::write_json(meta, file.path(run_dir, "scenario.json"),
                         auto_unbox = TRUE, pretty = TRUE)
    # Run the model in the background. The runner wrapper is spawned with
    # system2 (CreateProcess on Windows): a shell command line would mangle
    # the quoted arguments on Windows, and the wrapper also records
    # completion in status.txt.
    file.copy(file.path(root, "dashboard", "runner_template.R"),
              file.path(run_dir, "runner.R"), overwrite = TRUE)
    system2(file.path(R.home("bin"), "Rscript"),
            c(shQuote(file.path(run_dir, "runner.R")), shQuote(run_dir),
              shQuote(run_scenario_path), shQuote(root), shQuote(exo_copy),
              shQuote(shocks_path)),
            wait = FALSE)
    latest_run(run_dir)
    showNotification(paste("Scenario", run_id,
                           "started. It appears in the library when complete."))
  })

  output$run_status <- renderText({
    invalidateLater(3000, session)
    d <- latest_run()
    if (is.null(d)) return(NULL)
    paste0("Status: ", run_status_of(d, list()))
  })

  output$run_log <- renderText({
    invalidateLater(3000, session)
    d <- latest_run()
    if (is.null(d)) return("Run a scenario to see its progress here.")
    log_path <- file.path(d, "stdout.log")
    if (!file.exists(log_path)) return("Waiting for output...")
    tail(readLines(log_path, warn = FALSE), 10)
  })
}

shinyApp(ui = ui, server = server)

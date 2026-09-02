# Scenario Economic Model dashboard (Shiny).
#
# The only frontend: it requires just R (shiny, jsonlite, openxlsx; installed
# by start_dashboard.cmd if missing). Run it by double-clicking
# start_dashboard.cmd, or from R: shiny::runApp("dashboard").
#
# Styling follows the Deloitte analytical design system (DESIGN.md): white
# working surfaces on a light neutral canvas, hairline rules, Deloitte green
# reserved for actions and status, and an ABS statistical-publication chart
# language - teal for the primary series, dashed continuation for the
# forecast, hairline horizontal gridlines, end-of-line value labels.
#
# Tabs:
#   - Headlines: key aggregates, KPI strip, history and forecast on one chart.
#   - All variables: every model variable (outputs/model_results_flat.xlsx)
#     over the full span, level and annual-growth views, CSV download.
#   - Scenario library: lists runs in scenario-runs/ and overlays any
#     completed scenario on the central forecast.
#   - Build a scenario: applies adjustments to the shock file and runs
#     R/run_scenario.R in the background.
#
# Tabs are deep-linkable: append ?tab=headlines|all-variables|library|build.

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
flat_updated <- format(file.mtime(flat_path), "%d %b %Y")

# The shockable variables are exactly the columns of the baseline shock file.
shock_variables <- setdiff(names(read.csv(baseline_shocks_path, nrows = 1)), "date")

labelled_choices <- function(variables) {
  labels <- vapply(variables, function(v) {
    lab <- if (v %in% names(variable_labels)) unname(variable_labels[[v]]) else v
    paste0(v, " - ", lab)
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

# ---- chart theme (ABS statistical-publication language) ---------------------------
# Teal carries the primary series, with the forecast drawn as a dashed
# continuation of the same series; the central forecast in a comparison is a
# dashed ink reference. Horizontal hairline gridlines only, no plot box,
# clean-number axes, and a selective end-of-line value label in ink.

chart_col <- list(
  ink = "#242424", muted = "#626262", grid = "#e7e7e2", baseline = "#c5c5c0",
  teal = "#008a83", origin = "#d8d8d4", empty = "#8a8a85"
)

chart_family <- local({
  fam <- NULL
  function() {
    if (is.null(fam)) {
      fam <<- if (.Platform$OS.type == "windows") {
        tryCatch({
          windowsFonts(SEMsans = windowsFont("Segoe UI"))
          "SEMsans"
        }, error = function(e) "")
      } else ""
    }
    fam
  }
})

chart_par <- function() {
  par(
    mar = c(3.6, 5.4, 0.4, 2.6), mgp = c(2.6, 0.55, 0), tck = 0,
    las = 1, bty = "n", xpd = NA, ps = 11,
    col.axis = chart_col$muted, col.lab = chart_col$muted,
    fg = chart_col$baseline, family = chart_family()
  )
}

# One-, two- or three-decimal axis formatting, thousands-comma'd above 1000.
make_y_fmt <- function(values) {
  top <- max(abs(values[is.finite(values)]))
  if (top < 10) function(x) sprintf("%.2f", x) else
  if (top < 1000) function(x) formatC(x, format = "f", digits = 1) else
  function(x) formatC(x, big.mark = ",", format = "d")
}

# Year ticks at a step that keeps the label count readable.
date_axis <- function(dates, max_labels = 9) {
  yrs <- as.integer(format(min(dates), "%Y")):as.integer(format(max(dates), "%Y"))
  step <- if (length(yrs) <= max_labels) 1 else
          if (length(yrs) <= 2 * max_labels) 2 else
          if (length(yrs) <= 5 * max_labels) 5 else 10
  at <- as.Date(sprintf("%d-01-01", yrs[yrs %% step == 0]))
  at <- at[at >= min(dates)]
  list(at = at, lab = format(at, "%Y"))
}

# Split a series at the forecast origin: actuals solid, forecast dashed,
# joined at the boundary so the line reads as one series.
split_segments <- function(dates, values, period, col, lwd, label_last = TRUE) {
  keep <- is.finite(values)
  dates <- dates[keep]; values <- values[keep]; period <- period[keep]
  if (!length(dates)) return(list())
  a <- which(period == "Actual")
  f <- which(period == "Forecast")
  segs <- list()
  if (length(a)) segs[[length(segs) + 1]] <-
    list(x = dates[a], y = values[a], col = col, lwd = lwd, lty = 1,
         label = FALSE)
  if (length(f)) {
    if (length(a)) f <- c(a[length(a)], f)  # join at the boundary
    segs[[length(segs) + 1]] <-
      list(x = dates[f], y = values[f], col = col, lwd = lwd, lty = 2,
           label = label_last)
  }
  if (!length(a) && !length(f))
    segs[[1]] <- list(x = dates, y = values, col = col, lwd = lwd, lty = 1,
                      label = label_last)
  segs
}

# The core renderer: hairline grid, baseline rule, forecast-origin rule,
# clean axes, series segments, selective end label. `segments` is a list of
# segment lists as built by split_segments (or hand-built for comparisons).
sem_chart <- function(segments, origin = NULL, log_y = FALSE, y_fmt = NULL,
                      end_label = TRUE) {
  segments <- segments[vapply(segments, function(s) length(s$x) > 1, logical(1))]
  if (!length(segments)) {
    chart_par()
    plot(NA, xlim = 0:1, ylim = 0:1, axes = FALSE, ann = FALSE)
    text(0.5, 0.5, "No data available for this selection.",
         col = chart_col$empty, cex = 0.85)
    return(invisible())
  }
  xs <- do.call(c, lapply(segments, function(s) range(s$x)))
  ys <- do.call(c, lapply(segments, function(s) s$y))
  all_vals <- ys[is.finite(ys)]
  if (log_y && all(all_vals > 0)) {
    ticks <- 10^pretty(log10(all_vals), n = 5)
  } else {
    ticks <- pretty(all_vals, n = 5)
    log_y <- FALSE
  }
  if (is.null(y_fmt)) y_fmt <- make_y_fmt(all_vals)
  lim <- range(ticks)
  pad <- 0.04 * (lim[2] - lim[1])
  span <- as.numeric(diff(range(xs)))
  xlim <- c(xs[1], xs[2] + if (end_label) 0.04 * span else 0)
  chart_par()
  plot(NA, xlim = xlim, ylim = c(lim[1] - pad, lim[2] + pad),
       log = if (log_y) "y" else "", axes = FALSE, ann = FALSE)
  abline(h = ticks, col = chart_col$grid, lwd = 1)
  usr <- par("usr")
  segments(usr[1], usr[3], usr[2], usr[3], col = chart_col$baseline, lwd = 1)
  if (!is.null(origin) && origin >= xlim[1] && origin <= xlim[2]) {
    abline(v = origin, col = chart_col$origin, lwd = 1, lty = "18")
    text(origin, usr[4] - 0.07 * (usr[4] - usr[3]), "Forecast",
         pos = 4, offset = 0.25, cex = 0.6, col = chart_col$empty)
  }
  ax <- date_axis(c(min(xs), max(xs)))
  axis(1, at = ax$at, labels = ax$lab, tck = -0.012, col = NA,
       col.axis = chart_col$muted, cex.axis = 0.66, gap.axis = 0.08)
  axis(2, at = ticks, labels = vapply(ticks, y_fmt, ""),
       col = NA, col.axis = chart_col$muted, cex.axis = 0.7, gap.axis = 0.06)
  for (s in segments) {
    lines(s$x, s$y, col = s$col, lwd = s$lwd, lty = s$lty,
          ljoin = "round", lend = "round")
  }
  if (end_label) {
    for (s in segments) {
      if (isTRUE(s$label)) {
        text(s$x[length(s$x)], s$y[length(s$y)], y_fmt(s$y[length(s$y)]),
             pos = 4, offset = 0.35, font = 2, cex = 0.72, col = chart_col$ink)
      }
    }
  }
  invisible()
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

fmt_timestamp <- function(ts) {
  if (!nzchar(ts)) return("-")
  tryCatch(format(as.POSIXct(ts, tz = "UTC", origin = "1970-01-01"),
                  "%d %b %Y %H:%M", tz = Sys.timezone()),
           error = function(e) ts)
}

# ---- headline data (computed once, shared by ui and server) -----------------------
# Growth is computed on the full span first so the window's leading quarters
# have valid year-on-year rates.
gdp_growth <- annual_growth(flat$Ygdp)
cpi_growth <- annual_growth(flat$Pcpi)
last_i <- nrow(flat)
origin_i <- which(flat$date == forecast_origin)
headline_start <- forecast_horizon - 20 * 365.25
headline_rows <- flat$date >= headline_start

fmt_1p <- function(x) paste0(formatC(x, format = "f", digits = 1), "%")
fmt_2p <- function(x) paste0(formatC(x, format = "f", digits = 2), "%")

kpi_tile <- function(label, value, sub) {
  div(class = "kpi",
      span(class = "kpi-label", label),
      div(class = "kpi-value", value),
      div(class = "kpi-sub", HTML(sub)))
}

# ---- ui helpers -------------------------------------------------------------------
svg_icon <- function(...) {
  tags$svg(width = 16, height = 16, viewBox = "0 0 24 24", fill = "none",
           stroke = "currentColor", `stroke-width` = 1.8,
           `stroke-linecap` = "round", `stroke-linejoin` = "round",
           `aria-hidden` = "true", ...)
}

nav_icons <- list(
  Headlines = svg_icon(
    tags$path(d = "M3 3v16a2 2 0 0 0 2 2h16"),
    tags$path(d = "m19 9-5 5-4-4-3 3")),
  `All variables` = svg_icon(
    tags$path(d = "M8 6h13"), tags$path(d = "M8 12h13"), tags$path(d = "M8 18h13"),
    tags$path(d = "M3 6h.01"), tags$path(d = "M3 12h.01"), tags$path(d = "M3 18h.01")),
  `Scenario library` = svg_icon(
    tags$ellipse(cx = 12, cy = 5, rx = 9, ry = 3),
    tags$path(d = "M3 5v14a9 3 0 0 0 18 0V5"),
    tags$path(d = "M3 12a9 3 0 0 0 18 0")),
  `Build a scenario` = svg_icon(tags$polygon(points = "6 3 20 12 6 21 6 3"))
)

tab_titles <- c("Headlines", "All variables", "Scenario library",
                "Build a scenario")

legend_chip <- function(label, style) {
  tags$span(tags$i(class = style), label)
}

chart_panel <- function(output_id, title, subtitle, height = "290px",
                       legend = NULL) {
  div(class = "panel",
      div(class = "panel-head",
          div(h3(title), p(class = "panel-sub", subtitle))),
      if (!is.null(legend)) div(class = "chart-legend", legend),
      plotOutput(output_id, height = height))
}

sem_legend <- c(
  legend_chip("Actual", ""),
  legend_chip("Forecast", "dashed-teal")
)

ref_row <- function(term, text) {
  div(class = "ref-row", strong(term), p(text))
}

# ---- ui ----------------------------------------------------------------------------

ui <- fluidPage(
  tags$head(
    includeCSS("www/styles.css"),
    tags$meta(name = "viewport",
              content = "width=device-width, initial-scale=1")
  ),
  div(class = "app-shell",
    uiOutput("sidebar"),
    div(class = "sem-main",
      div(class = "sem-topbar",
        div(
          h1("Scenario Economic Model"),
          p(class = "sub", "Australian economy - Quarterly model")
        ),
        div(class = "sem-topbar-chips",
          span(class = "data-chip", tags$i(),
               HTML(paste0("Actuals to <b>", quarter_label(data_end), "</b>"))),
          span(class = "data-chip", tags$i(class = "dashed"),
               HTML(paste0("Forecast to <b>",
                           quarter_label(forecast_horizon), "</b>")))
        )
      ),
      tabsetPanel(id = "tabs", type = "hidden",

        # ---- Headlines ---------------------------------------------------
        tabPanel("Headlines",
          div(class = "page",
            div(class = "page-head",
              h2("Headlines"),
              p(paste0("Key aggregates over the past 20 years, with the ",
                       "central forecast from ", quarter_label(forecast_origin),
                       " to ", quarter_label(forecast_horizon), "."))
            ),
            div(class = "kpi-strip",
              kpi_tile("Real GDP, annual growth",
                      fmt_1p(gdp_growth[last_i]),
                      sprintf("From %s in %s", fmt_1p(gdp_growth[origin_i]),
                              quarter_label(forecast_origin))),
              kpi_tile("CPI, annual inflation",
                      fmt_1p(cpi_growth[last_i]),
                      sprintf("From %s in %s", fmt_1p(cpi_growth[origin_i]),
                              quarter_label(forecast_origin))),
              kpi_tile("Unemployment rate",
                      fmt_1p(100 * flat$Lur[last_i]),
                      sprintf("From %s in %s",
                              fmt_1p(100 * flat$Lur[origin_i]),
                              quarter_label(forecast_origin))),
              kpi_tile("Cash rate",
                      fmt_2p(100 * flat$R90d[last_i]),
                      sprintf("From %s in %s",
                              fmt_2p(100 * flat$R90d[origin_i]),
                              quarter_label(forecast_origin)))
            ),
            div(class = "page-grid grid-2",
              chart_panel("plot_ygdp", "Real GDP, annual growth",
                          "Per cent, quarterly",
                          legend = sem_legend),
              chart_panel("plot_pcpi", "CPI, annual inflation",
                          "Per cent, quarterly",
                          legend = sem_legend),
              chart_panel("plot_lur", "Unemployment rate",
                          "Per cent, quarterly",
                          legend = sem_legend),
              chart_panel("plot_r90d", "Cash rate (90-day)",
                          "Per cent, quarterly",
                          legend = sem_legend)
            ),
            div(class = "page-foot",
              HTML(paste0(
                "Source: Deloitte Access Economics macro scenario model. ",
                "Central forecast from <code>outputs/model_results_flat.xlsx</code> ",
                "(updated ", flat_updated, "). Re-run ",
                "<code>Rscript run_model.R</code> to refresh the data."))
            )
          )
        ),

        # ---- All variables ------------------------------------------------
        tabPanel("All variables",
          div(class = "page",
            div(class = "page-head",
              h2("All variables"),
              p(paste0("Every model variable over the full historical and ",
                       "forecast span, as a level or annual growth."))
            ),
            div(class = "filter-bar",
              div(class = "field grow",
                  tags$span(class = "lbl", "Variable"),
                  selectizeInput("var_pick", NULL, labelled_choices(variable_names),
                                 selected = "Ygdp", width = "100%")),
              div(class = "field",
                  tags$span(class = "lbl", "Transform"),
                  selectInput("var_transform", NULL,
                              c("Level" = "level",
                                "Annual growth (%)" = "growth"))),
              div(class = "field slider-field",
                  tags$span(class = "lbl", "Years shown"),
                  sliderInput("var_years", NULL,
                              min = quarter_year(min(flat$date)),
                              max = quarter_year(forecast_horizon),
                              value = c(1990, quarter_year(forecast_horizon)),
                              sep = "", width = "100%")),
              div(class = "field checkbox-field",
                  checkboxInput("var_log", "Log scale", FALSE)),
              downloadButton("var_download", "Download CSV",
                             class = "btn btn-compact")
            ),
            div(class = "panel",
              uiOutput("var_panel_head"),
              plotOutput("var_plot", height = "430px")
            ),
            div(class = "panel",
              div(class = "panel-head",
                div(h3("Recent quarters"),
                    p(class = "panel-sub",
                      "Last 16 quarters of the selected window")),
              tableOutput("var_table"),
              div(class = "panel-foot",
                  "Download the CSV for the full window.")
            )
          )
        ),

        # ---- Scenario library ----------------------------------------------
        tabPanel("Scenario library",
          div(class = "page",
            div(class = "page-head",
              h2("Scenario library"),
              p(paste0("Select a stored run to overlay it on the central ",
                       "forecast for any variable. Runs appear here ",
                       "automatically as they complete."))
            ),
            uiOutput("library_summary"),
            div(class = "library-grid",
              div(class = "panel",
                div(class = "panel-head",
                  div(h3("Stored runs"),
                      p(class = "panel-sub",
                        "Click a run to compare it with the central forecast"))),
                uiOutput("scen_list")
              ),
              div(class = "panel",
                div(class = "filter-bar",
                  div(class = "field grow",
                      tags$span(class = "lbl", "Variable"),
                      selectizeInput("scen_var", NULL,
                                     labelled_choices(variable_names),
                                     selected = "Ygdp", width = "100%")),
                  downloadButton("scen_download", "Overlay CSV",
                                 class = "btn btn-compact")
                ),
                uiOutput("scen_panel_head"),
                plotOutput("scen_plot", height = "430px"),
                uiOutput("scen_foot")
              )
            )
          )
        ),

        # ---- Build a scenario ------------------------------------------------
        tabPanel("Build a scenario",
          div(class = "page",
            div(class = "page-head",
              h2("Build a scenario"),
              p(paste0("Adjustments are applied to the shock file for the ",
                       "chosen quarters and the model runs in the background ",
                       "via R/run_scenario.R. Completed runs appear in the ",
                       "Scenario library."))
            ),
            div(class = "build-grid",

              div(class = "page-grid",
                div(class = "panel",
                  div(class = "panel-body",
                    div(class = "field",
                        tags$span(class = "lbl", "Scenario name"),
                        textInput("scen_name", NULL, "",
                                  placeholder = "e.g. Higher oil prices")),
                    div(class = "field",
                        tags$span(class = "lbl", "Notes (optional)"),
                        textAreaInput("scen_notes", NULL, "", rows = 2,
                                      placeholder = "Purpose or key assumptions")),
                    hr(class = "divider"),
                    div(class = "rule-heading",
                        h3("Add adjustment"),
                        p("Each adjustment applies from its start quarter to its end quarter, inclusive.")),
                    div(class = "field",
                        tags$span(class = "lbl", "Variable"),
                        selectizeInput("adj_variable", NULL, adj_choices,
                                       selected = "Fpoil", width = "100%")),
                    div(class = "hint", textOutput("adj_hint")),
                    div(class = "two-col",
                      div(class = "field",
                          tags$span(class = "lbl", "Value"),
                          numericInput("adj_value", NULL, value = 0, step = 0.5,
                                       width = "100%")),
                      div(class = "field",
                          tags$span(class = "lbl", "Entered as"),
                          selectInput("adj_unit_mode", NULL,
                                      c("Percentage change (log shocks)" = "percent",
                                        "Model units (additive shocks)" = "units")))
                    ),
                    div(class = "two-col",
                      div(class = "field",
                          tags$span(class = "lbl", "Start quarter"),
                          selectInput("adj_start", NULL,
                                      choices = setNames(format(forecast_quarters),
                                                         vapply(forecast_quarters,
                                                                quarter_label, "")),
                                      width = "100%")),
                      div(class = "field",
                          tags$span(class = "lbl", "End quarter"),
                          selectInput("adj_end", NULL,
                                      choices = setNames(format(forecast_quarters),
                                                         vapply(forecast_quarters,
                                                                quarter_label, "")),
                                      selected = first_year_end, width = "100%"))
                    ),
                    actionButton("adj_add", "Add adjustment",
                                 class = "btn btn-primary")
                  )
                ),
                div(class = "panel",
                  div(class = "panel-head",
                    div(h3("Shock units"),
                        p(class = "panel-sub",
                          "How the entered value is interpreted, by variable"))),
                  div(class = "panel-body",
                    ref_row("Percentage change (log shocks)",
                            shock_hint("Fpoil")),
                    ref_row("Model units (additive shocks)",
                            shock_hint("R90d")),
                    ref_row("Ratio (Ynli)",
                            shock_hint("Ynli")),
                    p(class = "hint",
                      paste0("Ustar (NAIRU) is no longer a scenario input; ",
                             "see data-raw/VARIABLE_CHANGES.md."))
                  )
                )
              ),

              div(class = "page-grid",
                div(class = "panel",
                  div(class = "panel-head",
                    div(h3("Adjustments"), uiOutput("adj_count")),
                    actionButton("adj_clear", "Clear all", class = "btn btn-compact")
                  ),
                  uiOutput("adj_list"),
                  div(class = "panel-foot",
                      paste0("The scenario run applies these adjustments to a ",
                             "copy of data-raw/shocks.csv for the chosen ",
                             "quarters."))
                ),
                div(class = "panel",
                  div(class = "panel-body",
                    actionButton("scen_run", "Run scenario", class = "btn-primary"),
                    uiOutput("run_status"),
                    p(class = "hint",
                      paste0("The model runs in the background; a run takes a ",
                             "few minutes. It gets a unique run ID and a ",
                             "complete input snapshot."))
                  )
                ),
                div(class = "panel",
                  div(class = "panel-head",
                    div(h3("Run log"), p(class = "panel-sub",
                                         "Latest output from the run"))),
                  tags$pre(id = "run_log", class = "shiny-text-output log-console")
                )
              )
            )
          )
        )
      )
    )
  )
)

# adj_choices is used by the ui builder; define it before ui renders.
adj_choices <- labelled_choices(unique(c(
  c("Fpoil", "Lnom", "Cgov", "R90d"), shock_variables
)))

# ---- server -------------------------------------------------------------------------

server <- function(input, output, session) {

  switch_tab <- function(title) {
    active_nav(title)
    updateTabsetPanel(session, "tabs", title)
  }

  # -- app shell -------------------------------------------------------------------
  active_nav <- reactiveVal("Headlines")

  output$sidebar <- renderUI({
    div(class = "sem-sidebar",
      div(class = "sem-brand", "Deloitte", span(class = "sem-brand-dot")),
      div(class = "sem-nav",
        lapply(seq_along(tab_titles), function(i) {
          title <- tab_titles[[i]]
          actionButton(
            paste0("nav_", i), label = tagList(nav_icons[[title]], title),
            class = paste("nav-item",
                         if (identical(active_nav(), title)) "active"))
        })
      ),
      div(class = "sem-sidebar-foot",
        tags$span(class = "status completed", tags$i(), "Model ready"),
        span(class = "sub", paste0("Central forecast ", flat_updated))
      )
    )
  })

  observe({
    q <- isolate(parseQueryString(session$clientData$url_search))
    if (!is.null(q$tab) && q$tab %in% c("headlines", "all-variables",
                                        "library", "build")) {
      title <- switch(q$tab,
        "headlines" = "Headlines", "all-variables" = "All variables",
        "library" = "Scenario library", "build" = "Build a scenario")
      switch_tab(title)
    }
  })

  lapply(seq_along(tab_titles), function(i) {
    observeEvent(input[[paste0("nav_", i)]], switch_tab(tab_titles[[i]]))
  })

  # -- all variables tab -------------------------------------------------------------
  var_window <- reactive({
    years <- as.integer(format(flat$date, "%Y"))
    flat[years >= input$var_years[1] & years <= input$var_years[2], ,
         drop = FALSE]
  })

  var_values <- reactive({
    d <- var_window()
    if (input$var_transform == "growth") {
      # compute growth on the full span, then window it, so the window's
      # leading quarters have valid year-on-year rates
      growth <- annual_growth(flat[[input$var_pick]])
      growth[flat$date %in% d$date]
    } else {
      as.numeric(d[[input$var_pick]])
    }
  })

  output$var_panel_head <- renderUI({
    v <- input$var_pick
    lab <- variable_label(v)
    unit <- if (input$var_transform == "growth")
      "Annual growth, per cent, quarterly" else "Level, model units, quarterly"
    div(class = "panel-head",
        div(h3(lab %||% v),
            p(class = "panel-sub",
              HTML(paste0("<code>", v, "</code> - ", unit, " - ",
                          input$var_years[1], " to ",
                          input$var_years[2])))))
  })

  output$var_plot <- renderPlot({
    d <- var_window()
    sem_chart(
      split_segments(d$date, var_values(), d$period,
                     col = chart_col$teal, lwd = 2.2),
      origin = forecast_origin, log_y = input$var_log
    )
  }, res = 110)

  output$var_table <- renderTable({
    d <- utils::tail(var_window(), 16)
    data.frame(
      Quarter = vapply(d$date, quarter_label, ""),
      Period = d$period,
      Value = round(as.numeric(d[[input$var_pick]]), 4)
    )
  }, align = "llr", digits = 4, spacing = "xs")

  output$var_download <- downloadHandler(
    filename = function() paste0("sem_", input$var_pick, ".csv"),
    content = function(file) {
      d <- var_window()
      out <- data.frame(date = format(d$date), period = d$period)
      out[[input$var_pick]] <- as.numeric(d[[input$var_pick]])
      utils::write.csv(out, file, row.names = FALSE, na = "")
    }
  )

  # -- headlines tab ------------------------------------------------------------------
  output$plot_ygdp <- renderPlot(
    sem_chart(split_segments(flat$date[headline_rows], gdp_growth[headline_rows],
                             flat$period[headline_rows],
                             col = chart_col$teal, lwd = 2.2),
              origin = forecast_origin),
    res = 110)

  output$plot_pcpi <- renderPlot(
    sem_chart(split_segments(flat$date[headline_rows], cpi_growth[headline_rows],
                             flat$period[headline_rows],
                             col = chart_col$teal, lwd = 2.2),
              origin = forecast_origin),
    res = 110)

  output$plot_lur <- renderPlot(
    sem_chart(split_segments(flat$date[headline_rows],
                             100 * flat$Lur[headline_rows],
                             flat$period[headline_rows],
                             col = chart_col$teal, lwd = 2.2),
              origin = forecast_origin),
    res = 110)

  output$plot_r90d <- renderPlot(
    sem_chart(split_segments(flat$date[headline_rows],
                             100 * flat$R90d[headline_rows],
                             flat$period[headline_rows],
                             col = chart_col$teal, lwd = 2.2),
              origin = forecast_origin),
    res = 110)

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
          n_adjust = length(meta$adjustments %||% list()),
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

  # Radio rows need the current choice set to detect changes without
  # re-rendering (and resetting selection) on every poll.
  scen_choice_set <- reactiveVal(character(0))
  auto_follow <- reactiveVal(NULL)

  run_row <- function(s) {
    HTML(paste0(
      '<span class="scen-name">', htmlEscape(s$name),
      '<small>', s$n_adjust,
      if (s$n_adjust == 1) ' adjustment</small>' else ' adjustments</small>',
      '</span>',
      '<span class="scen-id">', htmlEscape(s$id), '</span>',
      '<span class="scen-date">', htmlEscape(fmt_timestamp(s$created)), '</span>',
      '<span class="status ', s$status, '"><i></i>', s$status, '</span>'
    ))
  }

  output$scen_list <- renderUI({
    s <- scenarios()
    choice_names <- list(
      HTML('<span class="scen-name">Central forecast only',
           '<small>No overlay - central shown alone</small></span>',
           '<span class="scen-id">-</span>',
           '<span class="scen-date">current</span>',
           '<span class="status completed"><i></i>ready</span>')
    )
    choice_values <- "central"
    if (!is.null(s)) {
      choice_names <- c(choice_names, lapply(seq_len(nrow(s)), function(i)
        run_row(s[i, ])))
      choice_values <- c(choice_values, s$dir)
    }
    if (!identical(sort(choice_values), sort(scen_choice_set()))) {
      scen_choice_set(choice_values)
      selected <- if (input$scen_pick %in% choice_values) input$scen_pick
                 else "central"
      updateRadioButtons(session, "scen_pick",
                         choiceNames = choice_names,
                         choiceValues = choice_values,
                         selected = selected)
    }
    div(class = "scen-list",
        radioButtons("scen_pick", NULL,
                     choiceNames = choice_names,
                     choiceValues = choice_values,
                     selected = isolate(input$scen_pick) %||%
                       "central"))
  })

  # When a run started from the Build tab completes, select it here.
  observe({
    s <- scenarios()
    follow <- auto_follow()
    if (is.null(s) || is.null(follow)) return()
    if (follow %in% s$dir[s$forecast]) {
      auto_follow(NULL)
      updateRadioButtons(session, "scen_pick", selected = follow)
    }
  })

  output$library_summary <- renderUI({
    s <- scenarios()
    n_runs <- if (is.null(s)) 0 else nrow(s)
    n_done <- if (is.null(s)) 0 else sum(s$forecast)
    div(class = "summary-strip",
      div(strong(n_runs), "stored runs"),
      div(strong(n_done), "completed"),
      div(strong(quarter_label(forecast_origin)), "forecast origin"),
      div(strong(quarter_label(forecast_horizon)), "forecast horizon")
    )
  })

  selected_scenario <- reactive({
    d <- input$scen_pick
    if (is.null(d) || identical(d, "central")) return(NULL)
    forecast_path <- file.path(d, "forecast.csv")
    if (!file.exists(forecast_path)) return(NULL)
    list(
      meta = jsonlite::fromJSON(file.path(d, "scenario.json"),
                                simplifyVector = FALSE),
      status = run_status_of(d, list()),
      forecast = utils::read.csv(forecast_path, check.names = FALSE)
    )
  })

  output$scen_panel_head <- renderUI({
    sc <- selected_scenario()
    title <- variable_label(input$scen_var) %||% input$scen_var
    if (is.null(sc)) {
      legend <- div(class = "chart-legend",
                    legend_chip("Central forecast", "solid-ink"))
      sub <- paste0(input$scen_var, " - central forecast, quarterly")
    } else {
      legend <- div(class = "chart-legend",
                    legend_chip(sc$meta$name, ""),
                    legend_chip("Central forecast", "dashed-ink"))
      sub <- paste0(input$scen_var, " - central vs scenario, quarterly")
    }
    tagList(
      div(class = "panel-head",
        div(h3(title), p(class = "panel-sub", HTML(
          paste0("<code>", input$scen_var, "</code> - ",
                 "central forecast", if (!is.null(sc))
                   paste0(" vs ", htmlEscape(sc$meta$name)),
                 " - ", quarter_label(forecast_origin), " to ",
                 quarter_label(forecast_horizon))))),
      legend
    )
  })

  output$scen_plot <- renderPlot({
    central <- flat[flat$period == "Forecast", ]
    var <- input$scen_var
    sc <- selected_scenario()
    segments <- list(list(
      x = central$date, y = as.numeric(central[[var]]),
      col = chart_col$ink, lwd = 1.8,
      lty = if (is.null(sc)) 1 else 2,
      label = is.null(sc)
    ))
    if (!is.null(sc)) {
      sf <- sc$forecast
      segments[[2]] <- list(
        x = as.Date(sf$date), y = as.numeric(sf[[var]]),
        col = chart_col$teal, lwd = 2.3, lty = 1, label = TRUE
      )
    }
    sem_chart(segments)
  }, res = 110)

  output$scen_foot <- renderUI({
    sc <- selected_scenario()
    if (is.null(sc)) {
      d <- input$scen_pick
      if (!is.null(d) && !identical(d, "central")) {
        return(div(class = "panel-foot",
                   paste0("This run has no forecast yet (status: ",
                          run_status_of(d, list()),
                          "). The overlay appears once it completes.")))
      }
      return(div(class = "panel-foot",
                 "Select a stored run to overlay it on the central forecast."))
    }
    div(class = "panel-foot", HTML(paste0(
      "<b>", htmlEscape(sc$meta$name), "</b> - ",
      "run <code>", htmlEscape(sc$meta$id %||% basename(input$scen_pick)),
      "</code>, created ", fmt_timestamp(sc$meta$createdAt %||% ""),
      " - ", length(sc$meta$adjustments %||% list()), " adjustment(s)",
      " - status: ", sc$status
    )))
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
  entry_counter <- new.env()
  entry_counter$n <- 0

  output$adj_hint <- renderText(shock_hint(input$adj_variable))

  observeEvent(input$adj_variable, {
    updateSelectInput(session, "adj_unit_mode",
                      selected = default_unit_mode(input$adj_variable))
  })

  output$adj_count <- renderUI(
    p(class = "panel-sub", paste(length(adjustments()), "applied")))

  output$adj_list <- renderUI({
    entries <- adjustments()
    if (!length(entries)) {
      return(div(class = "panel-body",
                 div(class = "empty-note",
                     strong("No adjustments yet"),
                     p(paste0("Add an adjustment on the left. A scenario ",
                              "needs at least one adjustment.")))))
    }
    rows <- lapply(entries, function(e) {
      div(class = "ledger-row",
        div(class = "ledger-name", e$label,
            small(e$variable)),
        div(class = "ledger-value",
            if (e$unit_mode == "percent")
              paste0(if (e$value >= 0) "+" else "", format(e$value), "%")
            else paste0(format(e$value), " units")),
        div(class = "ledger-period",
            paste0(quarter_label(as.Date(e$start)), " to ",
                   quarter_label(as.Date(e$end)))),
        actionButton(paste0("adj_del_", e$id), "Remove", class = "btn-remove")
      )
    })
    div(class = "panel-body", rows)
  })

  # Per-entry removal; observers are scoped to the render cycle that
  # created their buttons.
  observe({
    entries <- adjustments()
    for (e in entries) {
      local({
        id <- paste0("adj_del_", e$id)
        observeEvent(input[[id]], {
          current <- adjustments()
          kept <- Filter(function(x) x$id != e$id, current)
          adjustments(kept)
        })
      })
    }
  })

  observeEvent(input$adj_add, {
    if (!is.finite(input$adj_value)) return()
    entry_counter$n <- entry_counter$n + 1
    entry <- list(
      id = paste0("e", entry_counter$n),
      variable = input$adj_variable,
      label = variable_label(input$adj_variable) %||% input$adj_variable,
      value = input$adj_value,
      unit_mode = input$adj_unit_mode,
      start = input$adj_start,
      end = input$adj_end
    )
    adjustments(c(adjustments(), list(entry)))
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
        showNotification(paste("Unknown shock variable:", e$variable),
                         type = "error")
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
    auto_follow(run_dir)
    showNotification(paste("Scenario", run_id,
                           "started. It appears in the library when complete."))
  })

  output$run_status <- renderUI({
    invalidateLater(3000, session)
    d <- latest_run()
    if (is.null(d)) return(NULL)
    status <- run_status_of(d, list())
    div(class = "run-status",
        tags$span(class = paste0("status ", status), tags$i(), status),
        span(class = "scen-id", basename(d)))
  })

  output$run_log <- renderText({
    invalidateLater(3000, session)
    d <- latest_run()
    if (is.null(d)) return("Run a scenario to see its progress here.")
    out <- character(0)
    log_stdout <- file.path(d, "stdout.log")
    log_stderr <- file.path(d, "stderr.log")
    if (file.exists(log_stdout))
      out <- c(out, tail(readLines(log_stdout, warn = FALSE), 12))
    if (file.exists(log_stderr))
      out <- c(out, "stderr:", tail(readLines(log_stderr, warn = FALSE), 6))
    if (!length(out)) return("Waiting for output...")
    paste(out, collapse = "\n")
  })
}

shinyApp(ui = ui, server = server)

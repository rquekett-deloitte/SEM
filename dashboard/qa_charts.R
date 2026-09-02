# QA harness: renders the dashboard chart functions at deployment-like sizes.
# Not part of the running app; used to review the chart language on its own.
# Run from the repository root: Rscript dashboard/qa_charts.R

setwd("dashboard")

qa_env <- new.env(parent = globalenv())
sys.source("app.R", envir = qa_env)

dir.create("../temp_qa", showWarnings = FALSE)

qa_png <- function(name, css_w, css_h) {
  png(file.path("..", "temp_qa", name),
      width = round(css_w * 110 / 72), height = round(css_h * 110 / 72),
      res = 110)
}

with(qa_env, {
  # Headlines: GDP growth, ~677 x 290 CSS px (half-width panel)
  qa_png("qa_ygdp.png", 677, 290)
  sem_chart(
    split_segments(flat$date[headline_rows], gdp_growth[headline_rows],
                   flat$period[headline_rows], col = chart_col$teal, lwd = 2.2),
    origin = forecast_origin)
  dev.off()

  # Headlines: unemployment, full-panel view
  qa_png("qa_lur.png", 677, 290)
  sem_chart(
    split_segments(flat$date[headline_rows], 100 * flat$Lur[headline_rows],
                   flat$period[headline_rows], col = chart_col$teal, lwd = 2.2),
    origin = forecast_origin)
  dev.off()

  # All variables: Ygdp level, full span, wide panel ~1372 x 430
  qa_png("qa_ygdp_level.png", 1372, 430)
  sem_chart(
    split_segments(flat$date, as.numeric(flat$Ygdp), flat$period,
                   col = chart_col$teal, lwd = 2.2),
    origin = forecast_origin)
  dev.off()

  # All variables: growth view
  qa_png("qa_ygdp_growth.png", 1372, 430)
  sem_chart(
    split_segments(flat$date, gdp_growth, flat$period,
                   col = chart_col$teal, lwd = 2.2),
    origin = forecast_origin)
  dev.off()

  # Scenario overlay: central (ink dashed) vs a stored run (teal solid)
  run_dirs <- list.dirs("scenario-runs", recursive = FALSE)
  if (length(run_dirs)) {
    sf <- read.csv(file.path(run_dirs[1], "forecast.csv"), check.names = FALSE)
    central <- flat[flat$period == "Forecast", ]
    segments <- list(
      list(x = central$date, y = as.numeric(central$Ygdp),
           col = chart_col$ink, lwd = 1.8, lty = 2, label = FALSE),
      list(x = as.Date(sf$date), y = as.numeric(sf$Ygdp),
           col = chart_col$teal, lwd = 2.3, lty = 1, label = TRUE)
    )
    qa_png("qa_overlay.png", 779, 430)
    sem_chart(segments)
    dev.off()
  }

  # Central-only view (nothing selected in the library)
  central <- flat[flat$period == "Forecast", ]
  qa_png("qa_central.png", 779, 430)
  sem_chart(list(list(x = central$date, y = as.numeric(central$Ygdp),
                      col = chart_col$ink, lwd = 1.8, lty = 1, label = TRUE)))
  dev.off()
})

cat("QA charts written to temp_qa/\n")

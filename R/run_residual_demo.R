# Residual carry-forward demonstration.
#
# Runs the saved model twice from the same conditioning quarter:
#   1. carry_forward = TRUE  - the exported final-quarter residuals enter the
#      first forecast quarter and fade geometrically (the default);
#   2. carry_forward = FALSE - the residuals are set to zero, so every
#      boundary path is identically zero.
# and writes the paths plus a headline-variable comparison to
# outputs/residual_demo/ for the carry-forward discussion. Never writes to
# baseline inputs or the standard outputs.
#
# Run from the project root:  Rscript R/run_residual_demo.R

required_packages <- c("bimets", "lubridate", "readr", "tidyverse")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop(
    "Install the required packages before running the demo: ",
    paste(missing_packages, collapse = ", ")
  )
}

suppressPackageStartupMessages(library(tidyverse))
# Keeps the standalone block in R/calculate_residuals.R dormant.
SEM_PIPELINE_SOURCING <- TRUE
source("R/model_constants.R")
source("R/forecast_model.R")
source("R/calculate_residuals.R")
source("R/model_outputs.R")

model_data <- readRDS("data/model_data.rds")
model <- load_saved_model(model_data, "outputs/coefficients.csv")
origin <- forecast_origin(model_data)
horizon <- as.Date("2036-12-01")
exogenous <- parse_exogenous_csv(origin = origin, horizon = horizon)
shocks <- parse_shocks_csv("data-raw/shocks.csv", origin, horizon)
residuals <- read_residuals_csv("outputs/residuals.csv")

cat("Carry-forward demonstration, conditioning quarter",
    format(residuals$conditioning_date[[1]]), "\n")
cat("Residuals being carried (carry-forward ON):\n")
print(dplyr::select(residuals, equation, residual, persistence))

run_case <- function(carry_forward, label) {
  message("BIMETS: running carry-forward ", label)
  simulation <- run_bimets_forecast(
    model_data,
    model,
    exogenous,
    shocks,
    origin = origin,
    horizon = horizon,
    residuals_path = "outputs/residuals.csv",
    carry_forward = carry_forward,
    show_progress = FALSE
  )
  forecast <- extract_forecast(simulation, origin, horizon)
  validate_forecast(forecast, model_data)
  forecast
}

forecast_on <- run_case(TRUE, "ON")
forecast_off <- run_case(FALSE, "OFF (residuals zero)")

output_dir <- file.path("outputs", "residual_demo")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
readr::write_csv(forecast_on,
                 file.path(output_dir, "forecast_carryforward_on.csv"), na = "")
readr::write_csv(forecast_off,
                 file.path(output_dir, "forecast_carryforward_off.csv"), na = "")

headline <- c(
  "Ygdp", "YgdpAnnualGrowth", "YgdpNom", "Pcpi", "PcpiAnnualGrowth",
  "Ppcd", "PcpiRent", "Lur", "Lemp", "Lhrs", "Lpar", "R90d", "R10y",
  "Rmort", "PhouseSa", "Cpr", "Idwell", "Inonmin", "Yhdi", "Mtot"
)
common <- intersect(headline, names(forecast_on))
on_values <- forecast_on %>% dplyr::select(date, dplyr::all_of(common))
off_values <- forecast_off %>% dplyr::select(date, dplyr::all_of(common))
comparison <- dplyr::full_join(
  on_values, off_values,
  by = "date", suffix = c("_on", "_off")
)
for (nm in common) {
  comparison[[paste0(nm, "_diff")]] <-
    comparison[[paste0(nm, "_on")]] - comparison[[paste0(nm, "_off")]]
}
readr::write_csv(comparison,
                 file.path(output_dir, "residual_carryforward_comparison.csv"),
                 na = "")

summary_rows <- purrr::map_dfr(common, function(nm) {
  diff <- comparison[[paste0(nm, "_diff")]]
  on <- comparison[[paste0(nm, "_on")]]
  tibble::tibble(
    variable = nm,
    first_quarter_diff = diff[[1]],
    first_year_max_abs_diff = max(abs(diff[1:4])),
    mean_abs_diff = mean(abs(diff)),
    horizon_diff = dplyr::last(diff),
    horizon_pct_diff = 100 * (dplyr::last(diff) / dplyr::last(on))
  )
}) %>% dplyr::arrange(dplyr::desc(mean_abs_diff))
readr::write_csv(summary_rows,
                 file.path(output_dir, "residual_carryforward_summary.csv"),
                 na = "")

cat(
  "Demonstration complete.\n",
  "Paths: outputs/residual_demo/forecast_carryforward_on.csv",
  " and ..._off.csv\n",
  "Comparison: outputs/residual_demo/residual_carryforward_comparison.csv\n",
  "Summary: outputs/residual_demo/residual_carryforward_summary.csv\n",
  sep = ""
)
print(as.data.frame(summary_rows), digits = 4)

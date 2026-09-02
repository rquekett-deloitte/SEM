# Macro scenario model - single orchestration script.
# Run from the project root:  Rscript run_model.R

required_packages <- c(
  "bimets", "lubridate", "openxlsx", "readxl", "seasonal", "tidyverse"
)
model_settings <- list(
  refresh_model_data = TRUE,
  run_estimation = TRUE,
  show_bimets_progress = TRUE,
  carry_forward_residuals = TRUE,
  model_data_path = "data/model_data.rds",
  coefficients_path = "outputs/coefficients.csv",
  residuals_path = "outputs/residuals.csv",
  shocks_path = "data-raw/shocks.csv",
  flat_output_path = "outputs/model_results_flat.xlsx"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop(
    "Install the required packages before running the model: ",
    paste(missing_packages, collapse = ", ")
  )
}

suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(seasonal))

# Keeps the standalone block in R/calculate_residuals.R dormant while the
# pipeline sources it as a module.
SEM_PIPELINE_SOURCING <- TRUE
source("R/calculate_estimation_data.R")
source("R/model_constants.R")
source("R/estimation.R")
source("R/forecast_model.R")
source("R/calculate_residuals.R")
source("R/model_outputs.R")
source("R/workbook_output.R")

model_data <- if (model_settings$refresh_model_data) {
  prepared_data <- calculate_estimation_data()
  dir.create(dirname(model_settings$model_data_path), showWarnings = FALSE)
  saveRDS(prepared_data, model_settings$model_data_path)
  prepared_data
} else {
  if (!file.exists(model_settings$model_data_path)) {
    stop("Prepared model data not found: ", model_settings$model_data_path)
  }
  readRDS(model_settings$model_data_path)
}

model <- if (model_settings$run_estimation) {
  estimate_model(model_data)
} else {
  load_saved_model(model_data, model_settings$coefficients_path)
}
coefficients <- extract_coefficients(model)

horizon <- as.Date("2036-12-01")
origin <- forecast_origin(model_data)
exogenous <- parse_exogenous_csv(origin = origin, horizon = horizon)
shocks <- parse_shocks_csv(model_settings$shocks_path, origin, horizon)

# Standalone residual step: calculate the final-quarter equation residuals
# and export them, then the simulation reads the exported CSV.
residuals <- calculate_equation_residuals(model_data, model, origin)
invisible(export_residuals(residuals, model_settings$residuals_path))

forecast_model <- run_bimets_forecast(
  model_data,
  model,
  exogenous,
  shocks,
  origin = origin,
  horizon = horizon,
  residuals_path = model_settings$residuals_path,
  carry_forward = model_settings$carry_forward_residuals,
  show_progress = model_settings$show_bimets_progress
)
forecast <- extract_forecast(forecast_model, origin, horizon)
validate_forecast(forecast, model_data)

dir.create("outputs", showWarnings = FALSE)

output_tables <- list(
  coefficients = coefficients,
  forecast = forecast
)
purrr::iwalk(
  output_tables,
  ~ readr::write_csv(.x, file.path("outputs", paste0(.y, ".csv")), na = "")
)
coefficient_comparison <- compare_coefficients(coefficients)
workbook_path <- build_results_workbook(
  forecast, model_data, coefficients
)
flat_path <- build_flat_output(
  forecast, model_data, origin, model_settings$flat_output_path
)

sign_changes <- if (!is.null(coefficient_comparison)) {
  sum(coefficient_comparison$sign_change, na.rm = TRUE)
} else {
  NA_integer_
}
cat(
  "Model run complete:", length(model$fits), "equations",
  if (model_settings$run_estimation) {
    "estimated to the most recent historical period.\n"
  } else {
    "loaded from saved coefficients.\n"
  },
  "Model data:",
  if (model_settings$refresh_model_data) {
    "prepared from Data.xlsx.\n"
  } else {
    paste("loaded from", model_settings$model_data_path, ".\n")
  },
  "Forecast:", paste0(lubridate::year(origin), "-Q", lubridate::quarter(origin)),
  "to 2036-Q4;", nrow(forecast), "quarters.\n",
  "Residuals exported to", model_settings$residuals_path,
  "; carry-forward", if (model_settings$carry_forward_residuals) "ON.\n" else "OFF (residuals zero).\n",
  "Coefficient sense-check:", ifelse(is.na(sign_changes),
    "no baseline found.",
    paste0(sum(!is.na(coefficient_comparison$abs_change)), " coefficients compared, ",
           sign_changes, " sign changes (outputs/coefficient_comparison.csv).")),
  "\n",
  "Outputs written to outputs/, including", workbook_path, "and", flat_path, ".\n"
)

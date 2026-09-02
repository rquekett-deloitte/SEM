# Macro scenario model - single orchestration script.
# Run from the project root:  Rscript run_model.R

required_packages <- c(
  "bimets", "lubridate", "openxlsx", "readxl", "seasonal", "tidyverse"
)
model_settings <- list(
  refresh_data = TRUE,        # refresh official sources, then rebuild history
  refresh_prepared = TRUE,    # re-prepare estimation data from the sourced RDS
  run_estimation = TRUE,
  show_bimets_progress = TRUE,
  carry_forward_residuals = TRUE,
  coredata_export = TRUE,
  sourced_data_path = "data/sourced_data.rds",
  model_data_path = "data/model_data.rds",
  coefficients_path = "outputs/coefficients.csv",
  residuals_path = "outputs/residuals.csv",
  shocks_path = "data-raw/shocks.csv",
  flat_output_path = "outputs/model_results_flat.xlsx",
  coredata_output_path = "outputs/sem_coredata.xlsx"
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
source("R/prepare_model_data.R")
source("R/model_constants.R")
source("R/estimation.R")
source("R/forecast_model.R")
source("R/calculate_residuals.R")
source("R/model_outputs.R")
source("R/workbook_output.R")
source("R/coredata_export.R")

# The data pipeline: R/download_data.R downloads raw series; R/prepare_model_data.R
# is the single transformation home (raw -> sourced history -> estimation data).
# refresh_data re-runs both stages; otherwise the prepared cache is re-used.
if (model_settings$refresh_data) {
  cat("Downloading raw data (R/download_data.R)...\n")
  system2(file.path(R.home("bin"), "Rscript"), "R/download_data.R")
}

model_data <- if (model_settings$refresh_data || model_settings$refresh_prepared ||
                  !file.exists(model_settings$model_data_path)) {
  prepare_model_data(refresh = model_settings$refresh_data)
} else {
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
conditioning_data <- extend_exogenous_conditioning(model_data, exogenous, origin)
align_baseline_shocks(model_settings$shocks_path, origin, horizon)
shocks <- parse_shocks_csv(model_settings$shocks_path, origin, horizon)

# Standalone residual step: calculate the final-quarter equation residuals
# and export them, then the simulation reads the exported CSV.
residuals <- calculate_equation_residuals(conditioning_data, model, origin)
invisible(export_residuals(residuals, model_settings$residuals_path))

forecast_model <- run_bimets_forecast(
  conditioning_data,
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
invisible(audit_variable_usage(model_data))
invisible(write_exogenous_assumptions(exogenous, origin))
workbook_path <- build_results_workbook(
  forecast, model_data, coefficients
)
flat_table <- build_flat_table(forecast, model_data, origin)
flat_path <- write_flat_output(flat_table, model_settings$flat_output_path)
coredata_written <- model_settings$coredata_export &&
  file.exists("data-raw/sem_to_coredata.csv")
if (coredata_written) {
  invisible(build_coredata_export(
    flat_table,
    path = model_settings$coredata_output_path
  ))
} else {
  message("No Coredata mapping found; skipping the Coredata export.")
}

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
  if (model_settings$refresh_data) {
    paste0("re-sourced and prepared from ", model_settings$sourced_data_path,
           ".\n")
  } else if (model_settings$refresh_prepared) {
    paste0("prepared from ", model_settings$sourced_data_path, ".\n")
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
  "Outputs written to outputs/, including", workbook_path, ",",
  flat_path,
  if (coredata_written) paste("and", model_settings$coredata_output_path) else "",
  ".\n"
)

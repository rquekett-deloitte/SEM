# Macro scenario model - single orchestration script.
# Run from the project root:  Rscript run_model.R

required_packages <- c(
  "bimets", "lubridate", "openxlsx", "readxl", "seasonal", "tidyverse"
)
model_settings <- list(
  refresh_model_data = TRUE,
  run_estimation = TRUE,
  show_bimets_progress = TRUE,
  model_data_path = "data/model_data.rds",
  coefficients_path = "outputs/coefficients.csv",
  shocks_path = "data-raw/shocks.csv"
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

source("R/calculate_estimation_data.R")
source("R/estimation.R")
source("R/forecast_model.R")
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
forecast_model <- run_bimets_forecast(
  model_data,
  model,
  exogenous,
  shocks,
  origin = origin,
  horizon = horizon,
  show_progress = model_settings$show_bimets_progress
)
forecast <- extract_forecast(forecast_model, origin, horizon)

dir.create("outputs", showWarnings = FALSE)

output_tables <- list(
  coefficients = coefficients,
  forecast = forecast
)
purrr::iwalk(
  output_tables,
  ~ readr::write_csv(.x, file.path("outputs", paste0(.y, ".csv")), na = "")
)
workbook_path <- build_results_workbook(
  forecast, model_data, coefficients
)

cat(
  "Model run complete:", length(model$fits), "equations",
  if (model_settings$run_estimation) {
    "estimated.\n"
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
  "Outputs written to outputs/, including", workbook_path, ".\n"
)

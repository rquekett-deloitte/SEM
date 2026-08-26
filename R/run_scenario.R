# Isolated scenario runner. Never writes to baseline inputs or outputs.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
  stop("Usage: Rscript R/run_scenario.R <project-root> <exogenous.csv> <shocks.csv> <output-dir>")
}

project_root <- normalizePath(args[[1]], mustWork = TRUE)
exogenous_path <- normalizePath(args[[2]], mustWork = TRUE)
shocks_path <- normalizePath(args[[3]], mustWork = TRUE)
output_dir <- normalizePath(args[[4]], mustWork = TRUE)
setwd(project_root)

required_packages <- c("bimets", "lubridate", "readr", "tibble", "dplyr", "purrr", "tidyverse")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop("Install the required packages before running a scenario: ", paste(missing_packages, collapse = ", "))
}

suppressPackageStartupMessages(library(tidyverse))
source(file.path(project_root, "R", "forecast_model.R"))
source(file.path(project_root, "R", "model_outputs.R"))

model_data <- readRDS(file.path(project_root, "data", "model_data.rds"))
model <- load_saved_model(model_data, file.path(project_root, "outputs", "coefficients.csv"))
origin <- forecast_origin(model_data)
horizon <- as.Date("2036-12-01")
exogenous <- parse_exogenous_csv(exogenous_path, origin, horizon)
shocks <- parse_shocks_csv(shocks_path, origin, horizon)

simulation <- run_bimets_forecast(
  model_data,
  model,
  exogenous,
  shocks,
  origin = origin,
  horizon = horizon,
  show_progress = FALSE
)
forecast <- extract_forecast(simulation, origin, horizon)
readr::write_csv(forecast, file.path(output_dir, "forecast.csv"), na = "")
cat("Scenario complete:", nrow(forecast), "quarters\n")

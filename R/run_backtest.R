# Historical tracking simulation.
#
# Re-simulates the model over an observed stretch of history (2010 Q1 to the
# final data quarter by default) driven by the actual exogenous paths, the
# observed COVID correction terms (ShockGst, DumTsfTot) and residuals carried
# from the conditioning quarter, then compares every endogenous path with the
# actuals. This is a within-sample tracking exercise: the coefficients are
# the current full-sample estimates, so it tests the simulation dynamics and
# calibration, not out-of-sample forecast ability. (A pre-2010 re-estimation
# is not possible without spec changes: several equations carry COVID-dummy
# regressors that are all zero on earlier samples and are unidentified there.)
#
# Run from the project root:  Rscript R/run_backtest.R [YYYYQn e.g. 2010Q1]

required_packages <- c("bimets", "lubridate", "readr", "tidyverse")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop("Install the required packages before running the backtest: ",
       paste(missing_packages, collapse = ", "))
}

suppressPackageStartupMessages(library(tidyverse))
SEM_PIPELINE_SOURCING <- TRUE
source("R/model_constants.R")
source("R/forecast_model.R")
source("R/calculate_residuals.R")
source("R/model_outputs.R")

args <- commandArgs(trailingOnly = TRUE)
start_label <- if (length(args) >= 1) args[[1]] else "2010Q1"
parse_quarter <- function(label) {
  parts <- regmatches(label, regexec("^([0-9]{4})Q([1-4])$", label))[[1]]
  if (length(parts) != 3) stop("Start quarter must look like 2010Q1")
  # Model quarters are dated by their end month: Q1 is March, ..., Q4 December.
  as.Date(sprintf("%s-%02d-01", parts[2], as.integer(parts[3]) * 3))
}
origin <- parse_quarter(start_label)

model_data <- readRDS("data/model_data.rds")
model <- load_saved_model(model_data, "outputs/coefficients.csv")
data_dates <- as.Date(model_data$date)
horizon <- max(data_dates)
if (!(origin %in% data_dates) ||
    !all(seq(origin, horizon, by = "quarter") %in% data_dates)) {
  stop("The backtest window must lie inside the observed history")
}
output_dir <- file.path("outputs", paste0("backtest_", start_label))
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Actual exogenous paths for the simulation window, from the observed history.
contract <- mdl_exogenous_contract()
window <- model_data %>%
  dplyr::filter(date >= !!origin, date <= !!horizon)
# Lpop15Plus is not a model_data column; build_ts_database derives it from
# Lsup/Lpar for history, so the observed path is built the same way here.
source_columns <- setdiff(contract$forecast_column, "Lpop15Plus")
exo <- window %>% dplyr::select(date, dplyr::all_of(source_columns))
exo$Lpop15Plus <- window$Lsup / window$Lpar
if (anyNA(exo[, setdiff(names(exo), "date")])) {
  stop("Observed exogenous paths are incomplete over the backtest window")
}

# Observed correction terms for the simulation window (see build_ts_database).
observed <- window %>% dplyr::select(date, dplyr::any_of(c("ShockGst", "DumTsfTot")))

# Zero shocks across the window, matching the production shock contract.
shock_variables <- mdl_shock_contract()$variable
shock_dates <- seq(as.Date(origin), as.Date(horizon), by = "quarter")
shocks <- cbind(
  tibble::tibble(date = shock_dates),
  matrix(0, nrow = length(shock_dates), ncol = length(shock_variables),
         dimnames = list(NULL, shock_variables)) %>%
    tibble::as_tibble()
)

# Residuals carried from the conditioning quarter (the last history row).
residuals <- calculate_equation_residuals(model_data, model, origin)
invisible(export_residuals(residuals, file.path(output_dir, "residuals.csv")))

message("BIMETS: tracking simulation ", start_label, " to ",
        paste0(lubridate::year(horizon), "Q", lubridate::quarter(horizon)))
simulation <- run_bimets_forecast(
  model_data, model, exo, shocks,
  origin = origin, horizon = horizon,
  residuals_path = file.path(output_dir, "residuals.csv"),
  carry_forward = TRUE, observed = observed,
  show_progress = TRUE
)
simulated <- extract_forecast(simulation, origin, horizon)
readr::write_csv(simulated, file.path(output_dir, "simulated.csv"), na = "")

headline <- c(
  "Ygdp", "YgdpNom", "Cpr", "Cgov", "Idwell", "Imin", "Inonmin",
  "IvtNonfarm", "Xmin", "Xoth", "Xsvc", "Mtot", "Tpit", "Tcit", "Tgst",
  "Tprl", "Ytsf", "Lwge", "Lpar", "Lemp", "Lhrs", "LavhMkt", "Pcpi", "Ppcd",
  "PhouseSa", "R90d", "R10y", "Rmort", "PcpiRent", "Yhdi", "Whh", "Peq"
)
actual <- model_data %>% dplyr::filter(date >= !!origin, date <= !!horizon)
common <- intersect(headline, names(simulated))

comparison <- purrr::map_dfr(common, function(nm) {
  sim <- simulated[[nm]]
  act <- as.numeric(actual[[nm]])
  ok <- is.finite(sim) & is.finite(act)
  pct <- dplyr::if_else(abs(act[ok]) > 1e-9,
                        100 * (sim[ok] - act[ok]) / abs(act[ok]), NA_real_)
  tibble::tibble(
    variable = nm,
    mean_abs_error = mean(abs(sim[ok] - act[ok])),
    mean_abs_pct_error = mean(abs(pct), na.rm = TRUE),
    max_abs_pct_error = suppressWarnings(max(abs(pct), na.rm = TRUE)),
    max_abs_pct_error_quarter = actual$date[ok][which.max(abs(pct))],
    rmse = sqrt(mean((sim[ok] - act[ok])^2))
  )
}) %>% dplyr::arrange(dplyr::desc(mean_abs_pct_error))
readr::write_csv(comparison, file.path(output_dir, "summary.csv"), na = "")

# Growth comparison for the key aggregates the notes ask for.
growth_check <- purrr::map_dfr(c("Ygdp", "Pcpi"), function(nm) {
  idx <- match(as.Date(simulated$date), data_dates)
  act_level <- as.numeric(model_data[[nm]])[idx]
  act_growth <- 100 * (act_level / as.numeric(model_data[[nm]])[idx - 4] - 1)
  sim_growth <- simulated[[paste0(nm, "AnnualGrowth")]]
  ok <- is.finite(sim_growth) & is.finite(act_growth)
  tibble::tibble(
    variable = paste0(nm, " annual growth"),
    mean_abs_error_pp = mean(abs(sim_growth[ok] - act_growth[ok])),
    max_abs_error_pp = max(abs(sim_growth[ok] - act_growth[ok])),
    max_error_quarter = actual$date[ok][which.max(abs(sim_growth[ok] - act_growth[ok]))]
  )
})
print(as.data.frame(growth_check), digits = 4)

long <- purrr::map_dfr(common, function(nm) {
  tibble::tibble(
    date = as.Date(simulated$date),
    variable = nm,
    actual = as.numeric(actual[[nm]])[match(as.Date(simulated$date), actual$date)],
    simulated = simulated[[nm]]
  )
})
readr::write_csv(long, file.path(output_dir, "comparison.csv"), na = "")

cat(
  "Backtest complete:", start_label, "to",
  paste0(lubridate::year(horizon), "Q", lubridate::quarter(horizon)), "\n",
  "Within-sample tracking run: coefficients estimated on the full sample;\n",
  "simulated dynamics driven by actual exogenous paths and corrections.\n",
  "Outputs in", output_dir, "(simulated, comparison, summary, residuals).\n",
  sep = ""
)
print(as.data.frame(head(comparison, 15)), row.names = FALSE, digits = 4)

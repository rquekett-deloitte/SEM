# Standalone equation-residual calculation for the forecast boundary terms.
#
# The residuals carried into each forecast were previously computed inline in
# build_ts_database() while the simulation database was being built. They are
# now calculated here and exported to a CSV that the simulation reads, so the
# residual step can be run, reviewed and versioned independently of the
# forecast, and the simulation can switch the residual carry-forward on or
# off (see build_ts_database()).

RESIDUAL_EQUATIONS <- tibble::tribble(
  ~equation,  ~boundary_variable,
  "Pcpi",     "PcpiBoundary",
  "PcpiRent", "PcpiRentBoundary",
  "Rcash",    "RcashBoundary",
  "Lhrs",     "LhrsBoundary"
)

RESIDUAL_PERSISTENCE <- 0.9

# Final-quarter equation residuals at the forecast conditioning quarter.
# `data` is the prepared model data; `origin` is the forecast origin, so the
# conditioning quarter is the last historical row before it. Requires the
# estimated model (coefficients and the Rcash state-space variances).
calculate_equation_residuals <- function(data, model, origin,
                                         persistence = RESIDUAL_PERSISTENCE) {
  history <- data[as.Date(data$date) < as.Date(origin), , drop = FALSE]
  i <- nrow(history)
  if (i < 2L) {
    stop("Residual calculation requires at least two historical quarters")
  }
  params <- mdl_parameters(model)
  aux <- aux_regressors(model, history)

  pcpi_fitted <- params$Pcpi_c1 +
    params$Pcpi_c2 * (log(history$Pcpi[i - 1] / 100) - log(history$Ppcd[i - 1]) -
                        params$Pcpi_c3 * history$trend[i - 1]) +
    params$Pcpi_c4 * (log(history$Ppcd[i]) - log(history$Ppcd[i - 1]))
  pcpi_residual <- log(history$Pcpi[i] / history$Pcpi[i - 1]) - pcpi_fitted

  rent_fitted <- params$PcpiRent_c1 +
    params$PcpiRent_c2 * (log(history$PcpiRent[i - 1]) -
      log(history$PhouseHpf[i - 1]) - params$PcpiRent_c4 * history$RmortRealHpf[i - 1]) +
    params$PcpiRent_c5 * history$Lnom[i] / 1000 +
    params$PcpiRent_c6 * (log(history$Lwge[i]) - log(history$Lwge[i - 1])) +
    params$PcpiRent_c7 * (log(history$Lwge[i - 1]) - log(history$Lwge[i - 2])) +
    params$PcpiRent_c8 * (log(history$PcpiRent[i - 1]) - log(history$PcpiRent[i - 2]))
  rent_residual <- log(history$PcpiRent[i] / history$PcpiRent[i - 1]) - rent_fitted

  inflation <- history$Pcpi[i] / history$Pcpi[i - 4] - 1
  rcash_fitted <- RCASH_IMPOSED[["c1"]] *
    (aux$RcashA[i] + inflation + RCASH_IMPOSED[["c2"]] *
       (history$Lur[i] - history$LurHpf[i]) + RCASH_IMPOSED[["c3"]] * history$d93[i] *
       (inflation - 0.025) - history$R90d[i - 1]) +
    RCASH_IMPOSED[["c4"]] * (history$Lur[i] - history$Lur[i - 1])
  rcash_residual <- history$R90d[i] - history$R90d[i - 1] - rcash_fitted

  z_lhrs <- log(history$Lhrs) - log(dplyr::lag(history$KTotal))
  lhrs_observed <- z_lhrs - dplyr::lag(z_lhrs)
  lhrs_fitted <- params$Lhrs_c1 *
    (params$Lhrs_c2 + log(history$Ygdp) - log(dplyr::lag(history$KTotal)) +
       params$Lhrs_c4 * history$trend +
       params$Lhrs_c5 * (history$Ygdp - history$YgdpHpf) / history$YgdpHpf +
       params$Lhrs_c6 * (log(history$Lwge) - log(history$Pgdp)) +
       params$Lhrs_c7 * (log(dplyr::lag(history$Lwge)) -
                           log(dplyr::lag(history$Pgdp))) -
       (log(dplyr::lag(history$Lhrs)) - log(dplyr::lag(history$KTotal, 2)))) +
    params$Lhrs_c8 * history$dum_2020q2 + params$Lhrs_c9 * history$dum_2020q3
  lhrs_residual <- lhrs_observed[i] - lhrs_fitted[i]

  tibble::tibble(
    equation = RESIDUAL_EQUATIONS$equation,
    boundary_variable = RESIDUAL_EQUATIONS$boundary_variable,
    residual = c(pcpi_residual, rent_residual, rcash_residual, lhrs_residual),
    conditioning_date = rep(as.Date(history$date[i]), nrow(RESIDUAL_EQUATIONS)),
    persistence = persistence
  )
}

export_residuals <- function(residuals, path = "outputs/residuals.csv") {
  readr::write_csv(residuals, path, na = "")
  path
}

read_residuals_csv <- function(path = "outputs/residuals.csv") {
  if (!file.exists(path)) {
    stop(
      "Residuals file not found at ", path,
      ". Run Rscript R/calculate_residuals.R (or the full pipeline run_model.R)",
      " to produce it."
    )
  }
  x <- readr::read_csv(path, show_col_types = FALSE)
  required <- c("equation", "boundary_variable", "residual", "conditioning_date")
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop("Residuals CSV is missing columns: ", paste(missing, collapse = ", "))
  }
  if (!setequal(x$equation, RESIDUAL_EQUATIONS$equation)) {
    stop("Residuals CSV must cover exactly: ",
         paste(RESIDUAL_EQUATIONS$equation, collapse = ", "))
  }
  if (any(!is.finite(x$residual))) {
    stop("Residuals CSV contains non-finite residuals")
  }
  if (!hasName(x, "persistence") || any(!is.finite(x$persistence))) {
    x$persistence <- RESIDUAL_PERSISTENCE
  }
  x
}

# Standalone execution: Rscript R/calculate_residuals.R refreshes the exported
# residual CSV from the saved model data and the saved coefficients, without
# re-running estimation. run_model.R and run_scenario.R set
# SEM_PIPELINE_SOURCING before source()ing this file, which keeps this block
# dormant inside the pipeline.
if (!exists("SEM_PIPELINE_SOURCING") || !isTRUE(SEM_PIPELINE_SOURCING)) {
  suppressPackageStartupMessages(library(tidyverse))
  source("R/model_constants.R")
  source("R/forecast_model.R")
  source("R/model_outputs.R")
  model_data <- readRDS("data/model_data.rds")
  model <- load_saved_model(model_data, "outputs/coefficients.csv")
  origin <- forecast_origin(model_data)
  residuals <- calculate_equation_residuals(model_data, model, origin)
  path <- export_residuals(residuals, "outputs/residuals.csv")
  cat(
    "Residuals exported to", path, "\n",
    "Conditioning quarter:", format(residuals$conditioning_date[[1]]), "\n",
    sep = ""
  )
  print(residuals)
}

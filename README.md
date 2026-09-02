# Macro Scenario Model

## Start the dashboard (Shiny)

Double-click `start_dashboard.cmd`. The dashboard requires only R — the
intended users have R installed but not Node.js. The launcher checks for
`Rscript`, installs missing packages (`shiny`, `jsonlite`, `openxlsx`), starts
the app and opens the browser. From R: `shiny::runApp("dashboard")`.

The tabs:

- **Headlines** — the central forecast for GDP, CPI, unemployment and the
  cash rate, history and forecast on one chart.
- **All variables** — every model variable from
  `outputs/model_results_flat.xlsx` over the full historical and forecast
  span, with level and annual-growth views and a CSV download.
- **Scenario library** — lists the runs in `scenario-runs/` and overlays any
  completed scenario on the central forecast for a chosen variable.
- **Build a scenario** — applies adjustments to the shock file and runs
  `R/run_scenario.R` in the background; completion is recorded in
  `scenario-runs/<id>/status.txt` and the run appears in the library when
  done. `Ustar` (NAIRU) is no longer a scenario input; the adjustment units
  follow the shock conventions documented under "Run directly".

Scenario runs are stored under `scenario-runs/<run-id>/` with input snapshots,
metadata, logs and forecast output. This directory is ignored by Git. Each
run has its own copies of the exogenous forecast and shocks, so it does not
modify the checked-in baseline inputs.

## Model data and forecast

The model has two production inputs:

- `data-raw/Data.xlsx`
- `data-raw/exogenous_forecast.csv`
- `data-raw/shocks.csv`

`Data.xlsx` supplies the complete estimation and conditioning history.
`run_model.R` estimates each equation once, reads the exogenous forecast, runs
the simulation and writes the model outputs.

The forecast implementation is in `R/forecast_model.R`. The forecast origin is
derived from the data: it starts one quarter after the final observed quarter
in `Data.xlsx`, currently 2025-03-01 (2025Q1), after the 2024Q4 conditioning
observation. It uses the explicit scenario contract in
`data-raw/exogenous_forecast.csv`, and runs a simultaneous dynamic forecast
through 2036Q4. The scenario CSV is an immutable model input and is not
generated or modified by production code. Supporting source metadata remains
in `data-raw/exogenous_sources.csv` for reference but is not read by the model.
Its nonlinear
feedback block uses a 10 per cent damped Gauss-Seidel update, which changes the
iteration path but not the fixed-point equations. Forecast closures, units and
scenario-provenance handling are documented in `VARIABLES.md`.

`Data.xlsx` currently ends in 2024Q4, so the forecast begins in 2025Q1.
Estimation windows, the forecast origin and the residual conditioning quarter
all follow the data end, so extending `Data.xlsx` re-estimates the equations to
the new quarter and re-forecasts from the following quarter without code
changes. No observed data beyond the final `Data.xlsx` quarter enter
estimation, conditioning, filtering or simulation.

## Run directly

From the project root:

```r
source("run_model.R")
```

or from a terminal:

```text
Rscript run_model.R
```

Preparation and estimation are controlled by `model_settings` at the top of
`run_model.R`:

```r
model_settings <- list(
  refresh_model_data = TRUE,
  run_estimation = TRUE,
  show_bimets_progress = TRUE,
  carry_forward_residuals = TRUE,
  coredata_export = TRUE,
  model_data_path = "data/model_data.rds",
  coefficients_path = "outputs/coefficients.csv",
  residuals_path = "outputs/residuals.csv",
  shocks_path = "data-raw/shocks.csv",
  flat_output_path = "outputs/model_results_flat.xlsx",
  coredata_output_path = "outputs/sem_coredata.xlsx"
)
```

- Set `refresh_model_data = FALSE` to load the prepared-data cache instead of
  recalculating it from `Data.xlsx`.
- Set `run_estimation = FALSE` to load saved coefficients instead of estimating
  the equations.
- Set `show_bimets_progress = FALSE` to suppress BIMETS loading and simulation
  progress messages.
- Set `shocks_path` to a scenario-specific shocks file. The file must contain
  one row per forecast quarter and columns for all behavioural equations and
  exogenous model variables. The checked-in file is an all-zero baseline.
  Enter values only in the variables and quarters to be shocked.
- Set `carry_forward_residuals = FALSE` to run the forecast with the exported
  residuals set to zero instead of carried into the first forecast quarter and
  faded geometrically.
- A normal run with both settings `TRUE` refreshes both saved files for later
  fast runs.

Shock units follow each equation or exogenous series specification. Most
columns are log innovations, so `log(1.20)` applies a 20 per cent increase. The
behavioural columns `LavhMkt`, `Lpar`, `Rmort`, `Whh`, `GovDebt`, `R90d` and
`R10y` are additive in their model units, and `Ynli` is additive to its modelled
income ratio. The exogenous columns `IvtFar`, `Fr10yUs`, `Fr10yJp`, `Fr10yDe`
and `Fr10yUk` are also additive; other exogenous columns,
including `Fpoil`, are log shocks. Shocks feed through the dynamic simultaneous
model and can therefore persist beyond the quarter in which they are entered.

Skip modes validate that the required cache and coefficient files exist. The
saved coefficient file must cover every model equation.

The root runner reads the checked-in quarterly exogenous scenario, then
executes data preparation, estimation and forecasting. It writes:

- `outputs/coefficients.csv`
- `outputs/forecast.csv`
- `outputs/residuals.csv` (final-quarter equation residuals, calculated by the
  standalone `R/calculate_residuals.R` step and read by the simulation)
- `outputs/coefficient_comparison.csv` (sense-check of the current estimates
  against `original_estimated_coefficients.csv`)
- `outputs/variable_audit.csv` (where every prepared-data column is used)
- `outputs/exogenous_assumptions.csv` (effective endpoints and sources of the
  scenario columns, joined with `data-raw/exogenous_sources.csv`)
- `outputs/model_results.xlsx` (dashboard, actual/forecast comparison, full
  forecast and coefficients)
- `outputs/model_results_flat.xlsx` (one flat sheet: every model variable,
  historical and forecast, one row per quarter)
- `outputs/sem_coredata.xlsx` (the model data in the national Coredata
  naming conventions, one row per Coredata variable with quarters across
  columns; the mapping is `data-raw/sem_to_coredata.csv` and is included in
  the workbook's Mapping sheet with per-variable review statuses)

## Optional runs

- `Rscript R/calculate_residuals.R` re-exports the residual CSV from the
  saved model data and coefficients without re-running estimation.
- `Rscript R/run_residual_demo.R` runs the forecast with residual
  carry-forward on and off (residuals zero) and writes the comparison to
  `outputs/residual_demo/`.
- `Rscript R/run_backtest.R [start quarter, e.g. 2010Q1]` re-simulates an
  observed stretch of history driven by the actual exogenous paths and
  compares every headline path with the actuals in
  `outputs/backtest_<start>/`. Within-sample tracking: the coefficients are
  the current full-sample estimates.
- `Rscript R/coredata_export.R` rebuilds the Coredata workbook from the
  current flat output without re-running the model.
- `Rscript R/update_data.R` downloads the latest observations for every
  workbook variable with a directly downloadable source - ABS series IDs
  resolve through the ABS Time Series Directory to the current release's
  time series tables, and RBA series come from the statistical-table CSVs -
  applies the transformation noted in the workbook's `Variables` sheet
  (quarterly as published; monthly series take a three-month average, with
  the noted divide-by-100) and writes `outputs/data_download_validation.csv`
  (the source-correctness check: every downloaded series compared with the
  existing history and graded, with the new quarters counted) plus
  `data-raw/Data_updated.xlsx`, a candidate workbook with the new quarters
  appended. Existing history is never rewritten by the script; revisions
  are quantified in the validation report for a separate decision. Review
  the candidate, then promote it by replacing `data-raw/Data.xlsx` and
  re-running the model. Downloaded tables are cached under
  `data-raw/downloads/` (git-ignored). Variables without a directly
  downloadable series ID (the Masterdata-sourced series, internal
  calibrations and the annual interpolations) are listed in the report with
  the reason.

## Residual carry-forward

The final-quarter equation residuals carried into each forecast are
calculated and exported independently of the simulation: `run_model.R` runs
the standalone step each time, and `Rscript R/calculate_residuals.R` re-exports
`outputs/residuals.csv` from the saved model data and coefficients without
re-running estimation. The simulation reads that file; with
`carry_forward_residuals = TRUE` each residual enters the first forecast
quarter and fades geometrically (persistence 0.9), and with `FALSE` the
residuals are set to zero. `Rscript R/run_residual_demo.R` runs both cases and
writes the comparison to `outputs/residual_demo/`.

The workbook is populated from `templates/model_results_template.xlsx`. Edit
that template to change workbook formatting, formulas, layout or native Excel
charts; the next model run preserves those changes while replacing the data.
The template is loaded and saved directly in R with `openxlsx`.

Prepared estimation data is passed directly to estimation and forecasting in
memory and is not exported.

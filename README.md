# Macro Scenario Model

## Scenario Economic Model frontend

Double-click `start_sem.cmd` to start the local API and React frontend,
then open the Scenario Economic Model at `http://localhost:5173`. The launcher installs Node
dependencies on first use and checks that both Node.js and R are available.

Scenario runs are stored under `scenario-runs/<run-id>/` with their input
snapshots, metadata, logs and forecast output. This directory is ignored by
Git.

The model has two production inputs:

- `data-raw/Data.xlsx`
- `data-raw/exogenous_forecast.csv`
- `data-raw/shocks.csv`

`Data.xlsx` supplies the complete estimation and conditioning history.
`run_model.R` estimates each equation once, reads the exogenous forecast, runs
the simulation and writes the model outputs.

The forecast implementation is in `R/forecast_model.R`. It starts on
2025-03-01 (2025Q1), after the 2024Q4 conditioning observation, uses the
explicit scenario contract in
`data-raw/exogenous_forecast.csv`, and runs a simultaneous dynamic forecast
through 2036Q4. The scenario CSV is an immutable model input and is not
generated or modified by production code. Supporting source metadata remains
in `data-raw/exogenous_sources.csv` for reference but is not read by the model.
Its nonlinear
feedback block uses a 10 per cent damped Gauss-Seidel update, which changes the
iteration path but not the fixed-point equations. Forecast closures, units and
scenario-provenance handling are documented in `VARIABLES.md`.

`Data.xlsx` ends in 2024Q4, so the forecast begins in 2025Q1. No later observed
data enter estimation, conditioning, filtering or simulation.

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
  model_data_path = "data/model_data.rds",
  coefficients_path = "outputs/coefficients.csv",
  shocks_path = "data-raw/shocks.csv"
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
- `outputs/model_results.xlsx` (dashboard, actual/forecast comparison, full
  forecast and coefficients)

The workbook is populated from `templates/model_results_template.xlsx`. Edit
that template to change workbook formatting, formulas, layout or native Excel
charts; the next model run preserves those changes while replacing the data.
The template is loaded and saved directly in R with `openxlsx`.

Prepared estimation data is passed directly to estimation and forecasting in
memory and is not exported.

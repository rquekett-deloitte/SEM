# Macro Scenario Model

## Scenario Economic Model frontend

The project includes a local React interface for creating and comparing macroeconomic scenarios. It runs alongside a local Express API, which starts the R scenario model and keeps a complete record of each run.

### Requirements

- Node.js, available on `PATH`
- R with `Rscript`, available on `PATH`
- The R packages required by the model, including the packages used by `run_model.R`

### Start the application

For the simplest local start-up, double-click `start_sem.cmd`. The launcher verifies that Node.js and R are available, installs Node dependencies if `node_modules/` is absent, starts the API and frontend, then opens the application at `http://localhost:5173`.

Alternatively, from the project root run:

```text
npm install
npm run dev
```

`npm run dev` starts both services:

- React and Vite frontend: `http://localhost:5173`
- Express scenario API: `http://localhost:4174`

Vite proxies `/api` requests from the frontend to the local API. To run either service separately, use `npm run dev:web` or `npm run dev:api`.

### Use the frontend

The **Results** view compares the selected scenario with the central forecast for real GDP, unemployment, CPI inflation and the short-term interest rate. Use **Build a scenario** to name a scenario, add one or more adjustments, select their inclusive forecast-quarter range, and run the model.

The available adjustments are:

- World oil price
- Net overseas migration
- Government consumption
- Short-term interest rate
- NAIRU

Oil, migration and government consumption adjustments are entered as percentage changes and converted to log innovations. Interest-rate adjustments are percentage points and NAIRU adjustments use percentage units. See the Model guide in the application and `VARIABLES.md` for model definitions and shock conventions.

The **Scenario library** lists stored runs and their status. A completed scenario can be reopened to compare it with the central forecast. Runs execute asynchronously; the frontend polls the API until a run completes or fails.

### Frontend development

The React application is in `src/`, with `src/App.tsx` providing the scenario workspace and `src/api.ts` providing the API client. The local API is implemented in `server/index.mjs`. Run the following checks before shipping frontend changes:

```text
npm run lint
npm run build
```

Scenario runs are stored under `scenario-runs/<run-id>/` with input snapshots, metadata, stdout and stderr logs, and forecast output. This directory is ignored by Git. Each run has its own copies of the exogenous forecast and shocks, so it does not modify the checked-in baseline inputs.

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
  model_data_path = "data/model_data.rds",
  coefficients_path = "outputs/coefficients.csv",
  residuals_path = "outputs/residuals.csv",
  shocks_path = "data-raw/shocks.csv",
  flat_output_path = "outputs/model_results_flat.xlsx"
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
- `outputs/model_results.xlsx` (dashboard, actual/forecast comparison, full
  forecast and coefficients)
- `outputs/model_results_flat.xlsx` (one flat sheet: every model variable,
  historical and forecast, one row per quarter)

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

# SEM update priorities

Last updated: Wednesday 2 September 2026. Dates in this note are absolute.

People: SS = Steve. AC and AB — full names to be added.

## Model code

| Task | Priority | Status | Notes |
|---|---|---|---|
| Update input data to the most recent period and simulate the model from that point | High | Satisfied and re-verified 2026-09-02 | `R/download_data.R` now refreshes current source files by default and its two ABS readers preserve physical worksheet row numbers, fixing the prior loss of every newest observation. The current raw store includes the ABS June 2026 national accounts released 2 September (GDP A2304402X = 699,461); the ragged sourced history reaches 2026Q3. Equation-specific estimation uses later observations where available. The latest complete conditioning quarter is 2025Q4, so the production forecast is 44 quarters from 2026Q1 to 2036Q4. `outputs/data_download_validation.csv`, `outputs/forecast.csv` and the regenerated workbooks are the review artifacts. No production path reads `Data.xlsx`. |
| Remove the residual calculation and carry-forward logic from the simulation code; create a standalone R script that calculates residuals and exports them to CSV; the simulation reads the exported residuals and keeps a switch to turn carry-forward on or off | High | Satisfied and re-verified 2026-09-02 | `R/calculate_residuals.R` independently exported four 2025Q4 boundary residuals to `outputs/residuals.csv`; `run_model.R` controls the simulation with `carry_forward_residuals`, and the forecast reads the CSV with conditioning-date validation. |
| Show Steve what happens when residuals are set to zero and discuss the residual carry-forward options | High | Satisfied; current demo outputs ready | `Rscript R/run_residual_demo.R` was rerun after the latest production model. `outputs/residual_demo/` contains current on/off paths, a comparison and summary; first-quarter carry-forward effects include GDP +2,506, CPI −0.132 index points, unemployment −0.0076 and R90d +0.0068 in model units. |
| Redesign the Excel output file to include the full set of variables, with both historical and forecast data | High | Satisfied and re-verified 2026-09-02 | See the "Excel output file" section below. |
| Test a historical simulation from 2010 Q1 and compare the results with actual values | Medium | Satisfied and re-verified 2026-09-02 | `Rscript R/run_backtest.R 2010Q1` now selects the latest complete observed exogenous horizon and writes `outputs/backtest_2010Q1/`. The current within-sample 2010Q1–2024Q4 comparison reports mean absolute errors of 3.02% for the GDP level, 1.31pp for annual GDP growth, 0.87pp for annual CPI growth and 0.52pp for unemployment (`headline_summary.csv`). This is a tracking exercise using full-sample coefficients, not a true out-of-sample estimate; pre-2020 re-estimation remains unidentified for equations with COVID regressors. |
| Estimate all equations to the most recent historical period by default and sense-check the outputs against previous outputs | High | Satisfied and re-verified 2026-09-02 | The production run estimated all 46 equations with the latest finite observations available to each equation, including June 2026 source observations where usable. `outputs/coefficient_comparison.csv` compares 291 coefficients with `original_estimated_coefficients.csv` and records four sign changes: Idwell c5, imposed Rcash c3, Rtwi c5 and R10y c1. These material changes require economist review before policy use. |
| Automate the process for updating data inputs, including ensuring that variables currently taken from MasterData are sourced directly in SEM | Medium | Partially satisfied; one external-source gap remains | The runtime dependency on `Data.xlsx` and MasterData has been removed. `VARIABLES.md` drives the source catalog; `R/download_data.R` refreshes raw official files; `R/prepare_model_data.R` is the single transformation path; and the real pipeline currently records 88 downloaded, 21 derived and 12 scenario-maintained variables in `outputs/data_download_validation.csv`. Former gaps including LavhMkt, Lhh, Rbiz, KdepRate, EqEarn, GovDef and GovDebt now have explicit direct/derived rules. **PeRatio remains not satisfied**: its historical source is proprietary LSEG/Refinitiv and the current pipeline explicitly holds the last sourced value; no authoritative replacement or credentials are present. Per the project integrity rule, this is not presented as complete and requires a data-owner-supplied LSEG schedule or an approved source substitution. |
| Add a variable-name conversion mapping SEM variables to the national Coredata naming conventions, and output the updated data as a Coredata file | Medium | Satisfied and re-verified 2026-09-02 | `data-raw/sem_to_coredata.csv` contains 50 registry rows; `outputs/sem_coredata.xlsx` contains 32 exported variables over 226 quarters from 1980Q3 to 2036Q4 plus the complete Mapping sheet. The production runner regenerated it from the same flat table used by the dashboard. |

## Excel output file

| Task | Priority | Status | Notes |
|---|---|---|---|
| Redesign the Excel output to include the full set of variables, historical and forecast, in one flat file | High | Satisfied and re-verified 2026-09-02 | `outputs/model_results_flat.xlsx` has one "Data" sheet with 250 non-duplicated quarterly rows and 186 columns: 206 Actual rows from 1974Q3 through 2025Q4 and 44 Forecast rows from 2026Q1 through 2036Q4. It contains every substantive estimation/forecast variable; deterministic estimation scaffolding is intentionally excluded. The template-based `model_results.xlsx` remains available. |

## Dashboard

| Task | Priority | Status | Notes |
|---|---|---|---|
| Replace the existing frontend with an R Shiny frontend | High | Satisfied and re-verified 2026-09-02 | `dashboard/` launched successfully against the regenerated flat workbook and rendered the R-only Headlines interface. `start_dashboard.cmd` remains the local launcher; the application code provides Headlines, all-variable explorer, scenario library and scenario building. Ustar (NAIRU) is not a scenario adjustment. |
| Ensure the dashboard can display the full set of variables for the historical and forecast periods | High | Satisfied and re-verified 2026-09-02 | The live application loaded `outputs/model_results_flat.xlsx`; the all-variables tab is driven from all workbook columns over 1974Q3–2036Q4, with level/annual-growth views and CSV download. All 142 forecast columns are finite in the 44 forecast rows; history-only source series remain blank where the model has no forecast concept. |
| Provide AC, AB and SS with access to the dashboard | High | Not verified; handoff package is ready | `start_dashboard.cmd` needs only R with `shiny`, `jsonlite` and `openxlsx` (auto-installed if missing). There is no evidence in the repository that AC, AB or SS received the repository/launcher, and no external distribution or deployment was authorised in this task. |

Delivery status at 2026-09-02: the model, output and dashboard artifacts are
ready within the one-to-two-week expectation. Full closure still requires the
authoritative `PeRatio` source and confirmed handoff to AC, AB and SS.

## Thursday 3 September 2026 deliverables

By end of Thursday, aim to:

1. update the data inputs to the latest period. **Satisfied**: official files were refreshed on 2 September 2026; the June national accounts are included and the ragged store reaches 2026Q3. No `Data.xlsx` dependency remains.
2. re-estimate all equations on the updated historical data, sense-check the results against the saved baseline (`original_estimated_coefficients.csv`), and run the model from the most recent period with the re-estimated coefficients. **Satisfied**: 46 equations re-estimated; the 2026Q1–2036Q4 production forecast and coefficient comparison were regenerated.
3. produce an Excel output file containing historical and forecast quarterly values for all variables from the updated model run, in one flat file. **Satisfied**: `outputs/model_results_flat.xlsx`.
4. use the standalone residual script and its exported CSV to test the updated model with residual carry-forward switched on and off, and demonstrate what happens when residuals are set to zero, for the discussion with Steve. **Satisfied**: current-vintage outputs are in `outputs/residual_demo/`.

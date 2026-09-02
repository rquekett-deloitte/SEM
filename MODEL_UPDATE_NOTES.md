# SEM update priorities

Last updated: Wednesday 2 September 2026. Dates in this note are absolute.

People: SS = Steve. AC and AB — full names to be added.

## Model code

| Task | Priority | Status | Notes |
|---|---|---|---|
| Update input data to the most recent period and simulate the model from that point | High | Blocked on source data; pipeline update-ready | `Data.xlsx` ends 2024 Q4 and contains no later actuals, so the update needs new ABS/LSEG data in `Data.xlsx`. The forecast origin and estimation windows now derive from the data end, so an updated `Data.xlsx` flows through in one `Rscript run_model.R`. |
| Remove the residual calculation and carry-forward logic from the simulation code; create a standalone R script that calculates residuals and exports them to CSV; the simulation reads the exported residuals and keeps a switch to turn carry-forward on or off | High | Done 2026-09-02 | `R/calculate_residuals.R` exports `outputs/residuals.csv`; the simulation reads it (stale-residual guard included) with `carry_forward_residuals` in `run_model.R` as the on/off switch. A regression run confirmed the refactor reproduces the previous forecast exactly. |
| Show Steve what happens when residuals are set to zero and discuss the residual carry-forward options | High | Demo outputs ready | `Rscript R/run_residual_demo.R` produces on/off (residuals zero) runs and comparisons in `outputs/residual_demo/`. Discussion points: the effect of zero residuals, why residual carry-forward should be automated, and why model adjustments should be a separate process. |
| Redesign the Excel output file to include the full set of variables, with both historical and forecast data | High | Done 2026-09-02 | See the "Excel output file" section below. |
| Test a historical simulation from 2010 Q1 and compare the results with actual values | Medium | Done 2026-09-02 | `Rscript R/run_backtest.R` → `outputs/backtest_2010Q1/`. Within-sample tracking (full-sample coefficients, actual exogenous paths and COVID corrections): GDP level tracks within ~3% mean (worst 6.7% in COVID); annual GDP growth mean error 1.3pp; CPI annual growth mean error 0.9pp; unemployment mean error 0.6pp. The frozen-trend closures (LurHpf, Rstar at their 2009Q4 values) drive most of the drift in rates and unemployment. A true out-of-sample version is blocked: several equations carry COVID-dummy regressors that are unidentified on pre-2020 samples. |
| Estimate all equations to the most recent historical period by default and sense-check the outputs against previous outputs | High | Done to 2024 Q4 (2026-09-02) | 15 equations had windows pinned before the data end (Rtwi at 2019 Q4, Lwge/R10y at 2023 Q3, Inonmin at 2024 Q3, etc.); all now estimate to the data end by default. Sense-check in `outputs/coefficient_comparison.csv` (vs the saved baseline, with the equation rename mapped) and `outputs/coefficient_comparison_window_extension.csv` (isolating this change): one sign change, Rtwi c5 (+0.056 to -0.073) from extending through COVID; the labour-hours block moved most (Lavh c2, Lhrs c2). Forecast level effects: GDP ~1–3%, unemployment ~0.5 pp by the 2030s — review before use. Extending past 2024 Q4 awaits new data. |
| Automate the process for updating data inputs, including ensuring that variables currently taken from MasterData are sourced directly in SEM | Medium | Origin, estimation windows and residual conditioning automated; MasterData sourcing needs a data-owner decision | The pipeline now derives the forecast origin, estimation windows and residual conditioning from the data end, so updating `Data.xlsx` is the only manual data step. The MasterData-sourced variables (PeRatio, EqEarn, LavhMkt, Ustar, DumTsfTot — see `VARIABLES.md`) are already columns in `Data.xlsx`; sourcing them "directly in SEM" means maintaining those columns from LSEG/ABS rather than via the external `Temp/Masterdata.xlsx`, which is a data-workflow decision that needs the external workbook. |
| Add a variable-name conversion mapping SEM variables to the national Coredata naming conventions, and output the updated data as a Coredata file | Medium | Done 2026-09-02 | Mapping in `data-raw/sem_to_coredata.csv` (50 Coredata variables: 28 exported, 4 flagged needs-review, 18 with no SEM counterpart); `Rscript R/coredata_export.R` writes `outputs/sem_coredata.xlsx` (32 variables, 1980Q3 to 2036Q4, Coredata RAW orientation with a Mapping sheet). Also wired into `run_model.R` (`coredata_export` setting). Units verified against the Coredata KEY sheet: rates and ratios are decimals in both conventions. |

## Excel output file

| Task | Priority | Status | Notes |
|---|---|---|---|
| Redesign the Excel output to include the full set of variables, historical and forecast, in one flat file | High | Done 2026-09-02 | `outputs/model_results_flat.xlsx`: one "Data" sheet, 250 quarterly rows (2024Q4 history back to 1974 Q3 plus the forecast through 2036 Q4), all model variables with a period column marking Actual/Forecast. Deterministic estimation scaffolding (trends, dummies) is excluded; the template-based `model_results.xlsx` is unchanged. |

## Dashboard

| Task | Priority | Status | Notes |
|---|---|---|---|
| Replace the existing frontend with an R Shiny frontend | High | Done 2026-09-02 | Raised to high priority 2026-09-02. `dashboard/` (run via `start_dashboard.cmd`) needs only R: the users have R but not Node.js, and the previous React and Express frontend was removed on 2026-09-02. Headlines, all-variable explorer, scenario library and scenario building all work; the scenario-spawn mechanism was verified end to end (oil +20% run: GDP +0.24% by 2027). Ustar (NAIRU) is no longer an adjustment (no longer a scenario input). |
| Ensure the dashboard can display the full set of variables for the historical and forecast periods | High | Done 2026-09-02 | The all-variables tab serves every variable from `outputs/model_results_flat.xlsx` (1974Q3 to 2036Q4) with level and annual-growth views and CSV download. |
| Provide AC, AB and SS with access to the dashboard | High | Ready | `start_dashboard.cmd` needs only R with `shiny`, `jsonlite` and `openxlsx` (auto-installed if missing). Give each user the repository (or a copy with `data-raw/`, `R/`, `outputs/` and `dashboard/`) and the launcher. |

Delivery timeframe: delivered 2026-09-02, within the one-to-two-week expectation.

## Thursday 3 September 2026 deliverables

By end of Thursday, aim to:

1. update the data inputs to the latest period. **Blocked**: `Data.xlsx` has no actuals beyond 2024 Q4; the update needs new source data. The pipeline is now update-ready, so the updated workbook flows through in one run.
2. re-estimate all equations on the updated historical data, sense-check the results against the saved baseline (`original_estimated_coefficients.csv`), and run the model from the most recent period with the re-estimated coefficients. **Done to the 2024 Q4 data end** (15 windows extended); sense-check outputs written and summarised in the model-code table above.
3. produce an Excel output file containing historical and forecast quarterly values for all variables from the updated model run, in one flat file. **Done**: `outputs/model_results_flat.xlsx`.
4. use the standalone residual script and its exported CSV to test the updated model with residual carry-forward switched on and off, and demonstrate what happens when residuals are set to zero, for the discussion with Steve. **Done**: `outputs/residual_demo/`.

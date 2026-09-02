# SEM handoff — data pipeline and sourcing

**Date:** 2 September 2026
**Context:** The model has been through a full architectural overhaul today. This handoff covers the current state, the one remaining problem, and what to do next.

---

## Current architecture

### Data flow

```
R/download_data.R          R/prepare_model_data.R                run_model.R
     |                          |                                     |
     v                          v                                     v
data/raw_series.rds  ->  data/sourced_data.rds  ->  data/model_data.rds  ->  outputs/
     (raw, untransformed)   (quarterly history)      (estimation dataset)
```

- **`R/download_data.R`** downloads raw observations only — no transformation. ABS tables (via the Time Series Directory), RBA statistical CSVs, Yahoo Finance. Saves every series keyed by its published series ID to `data/raw_series.rds`. Uses `data-raw/downloads/` as a cache (git-ignored).

- **`R/prepare_model_data.R`** is the single transformation home. Stage 1 aligns raw series to model quarters, validates against the previous history, and merges. Stage 2 prepares the estimation dataset (deflators, trends, X-13 seasonal adjustment, deterministic terms). Saves `data/sourced_data.rds` (the quarterly history) and `data/model_data.rds`.

- **`run_model.R`** has a `refresh_data` flag: `TRUE` runs download_data.R then the full prepare pipeline; `FALSE` reuses the prepared cache. Exogenous scenario paths are in `data-raw/exogenous_forecast.csv` (unchanged, by design).

- **`data-raw/Data.xlsx`** is a read-only bootstrap seed, no longer the model's data input. It exists only because some variables' history is not yet reproducible from downloads.

### Model state

- Forecast: 2025Q4–2036Q4 (45 quarters), conditioned at 2025Q3 (bound by the publication lags of quarterly NOM and labour-account hours — advances automatically as releases land)
- 46 equations estimated to each equation's latest available data
- 3 coefficient sign changes vs the original baseline (Rcash c3, Phouse c4, Rtwi c5 — all pre-existing model changes, not data issues)
- Forecast-vs-observed check at 2026Q1: GDP +0.9%, CPI −0.2%

### Data sourcing status

84 of 122 workbook columns are auto-sourced from official/free endpoints. The sourcing map is printed by every `prepare_model_data` run and written to `outputs/data_download_validation.csv`:

- **Sourced (84):** ABS national accounts, CPI, labour force, population, BOP, capital stocks, finance & wealth, household income; RBA rates; Yahoo All Ordinaries (Peq); ABS 5302.0 nominal exports; Phouse (transfer-weighted median derivation from Total Value of Dwellings Table 2, validated 0.000% over 92 quarters); Lnom (ABS 3101.0 ÷1000)
- **Derived (4):** KNbiz, KOther, EqEarn — exact internal derivations from sourced parents
- **Exogenous (12):** world/foreign drivers, IvtFar, IntStu — scenario-maintained via `exogenous_forecast.csv`
- **Open (9):** see below

### Shiny dashboard

`start_dashboard.cmd` launches the R-only frontend (Headlines, All variables, Scenario library, Build a scenario). The React/Express frontend was removed. The dashboard reads `outputs/model_results_flat.xlsx`.

---

## The problem: 9 variables with no active source

These variables exist in the model only because they were bootstrapped from `Data.xlsx`. They carry forward their last observed value (2024Q4) and are never updated. **This must not continue** — no silent carry-forward or NA extension at any stage.

| Variable | Last observed | Where the data actually comes from | What's needed to source it |
|---|---|---|---|
| **PeRatio** | 2024Q4 (17.42) | LSEG/Refinitiv subscription — "Calculated P/E Ratio" for the All Ordinaries, fed via `Temp/Masterdata.xlsx` sheet 'PEratio' | LSEG export, or an alternative free P/E source. Tested and rejected: Yahoo (no index P/E), FRED (different index), ASX website (only index/market cap), marketindex.com.au (Cloudflare-gated), RBA (discontinued 2011) |
| **EqEarn** | 2024Q4 (503.2) | Same LSEG feed — derives exactly as Peq ÷ PeRatio (validated 0.000%) | Resolves automatically once PeRatio is sourced |
| **LavhMkt** | 2024Q4 (417.1) | ABS 6291.0.55.001 Detailed Labour Force, aggregated to "market sector" (all industries minus public admin, education, health) on Masterdata sheet 'Average HW' | The ABS publishes industry-level hours and employment; the aggregation formula exists only in Masterdata. The model's own Lhrs/LempMkt reproduces it to 4.7% (different survey basis) |
| **PcpiExGst** | 2024Q4 (1.348) | AEM internal splice — CPI adjusted for the 2000 GST introduction. Not an ABS-published series | The GST adjustment factors are DAE-internal. The ratio to Pcpi drifts (0.0095–0.0102), so it's not a simple transform of CPI |
| **ShockGst** | 2024Q4 (2.15) | Owner's judgment — how COVID tax changes affected the GST base quarter by quarter. Entirely model-internal | Not published anywhere. The values ARE the source. Zero in the forecast is correct |
| **GovDef** | 2024Q4 (14.14) | Annual fiscal balance (GFS net lending) interpolated quarterly by an undocumented kernel. Annual sums: 2022 ≈ 80.6, 2023 ≈ 28.2, 2024 ≈ 45.8 $b | The quarterly interpolation kernel is the owner's. GFS quarterly net lending exists but has a different pattern |
| **GovDebt** | 2024Q4 (825.6) | Linear interpolation between June-quarter annual net debt levels. Validated exactly: +26.9/quarter from 661.7 (Jun-2023) to 769.3 (Jun-2024) | Current GFS annual net debt (783.8/846.6/954.9) doesn't match the workbook's vintage. Need the owner's annual source |
| **Lhh** | 2024Q4 (10.77m) | ABS 6224.0.55.001 annual household estimates, interpolated quarterly. The series ceased — only 2023–25 experimental estimates remain | The June 2025 experimental estimate (10.9m) extends it to 2025Q2 only. Pre-2023 history came from the old ceased series |
| **Rbiz** | 2024Q4 (5.96%) | RBA D8 (DBLWAT) to 2019Q3, then a weighted average of RBA F7 business lending rates | D8 was discontinued. No single F7 series matches the continuation (tested: small/medium/large, simple averages — all 12–63% off). The weighting formula is the owner's |

**KdepRate** is a special case: the formula is identified — (non-financial corporations COFC less mining) ÷ (business stock less mining stock) — and it reproduces recent years to 0.3–1.2%, but the early history differs (owner's data vintage). It needs approval before wiring.

**All of these trace back to `Temp/Masterdata.xlsx`** — the DAE-maintained external workbook. That is the actual source for every one of them. Getting the derivation formulas from whoever maintains Masterdata closes all 9 gaps.

---

## What to do next

### 1. Remove all carry-forward and NA extension

This is the immediate priority. In `R/prepare_model_data.R`:
- Delete the `carry_trend` and `carry_hold` lists and their merge logic
- Delete the `derive_after_merge` entries that depend on carried parents (EqEarn needs PeRatio, which is stale)
- Remove the BIMETS database's `mk()` function in `forecast_model.R` that carries the last observed value through NAs
- Variables that stop at 2024Q4 stop there. The estimation equations already NA-drop to their available data. The forecast needs explicit values for every variable it uses — see (2)

### 2. Make every forecast input explicit

After (1), variables that stop at 2024Q4 won't have values in the forecast. Each needs either:
- **A real source** that extends (the preferred answer for all 9)
- **An explicit exogenous path** in `data-raw/exogenous_forecast.csv` — but only for things genuinely meant to be exogenous (the user's rule). TcorpRate (a legislated 0.30) belongs in the scenario file as an explicit 0.30 path, not "carried". KdepRate is a calibration, not data. GovDef and GovDebt are endogenous (model-computed in the forecast) — they need real historical data only for estimation, not for the forecast path

### 3. Get the Masterdata derivations

The single conversation that closes the most gaps: whoever maintains `Temp/Masterdata.xlsx` can supply:
- The PeRatio values (or an LSEG export schedule)
- The LavhMkt aggregation formula (or the aggregated series itself)
- The PcpiExGst adjustment factors
- The GovDef interpolation kernel
- The GovDebt annual source/vintage
- The Rbiz F7 weighting

### 4. K stocks need proper interpolation, not extrapolation

The K stocks (KMin, KBiz, KDwell, KTotal) are annual June benchmarks. The workbook interpolated between benchmarks and extrapolated past the last one. Proper treatment: interpolate between published benchmarks only. Past the last benchmark, the values should be absent (the model's identities can compute them from investment flows). This is already how the model's forecast treats them — the carry-trend was a data-pipeline workaround, not a model need.

### 5. Consider whether the Data.xlsx seed can be retired

Once the 9 open variables are sourced (or the model is re-specified without them), the bootstrap seed is no longer needed and `data-raw/Data.xlsx` can be archived. The model then runs entirely from downloads.

---

## Key files

| File | Role |
|---|---|
| `R/download_data.R` | Downloads raw series (no transformation) |
| `R/prepare_model_data.R` | Single transformation: raw → sourced history → estimation data |
| `R/forecast_model.R` | BIMETS model equations, identities, simulation, exogenous contract |
| `R/estimation.R` | 46 behavioural equations, estimated to each equation's data end |
| `R/calculate_residuals.R` | Standalone residual calculation for the carry-forward boundary |
| `R/run_residual_demo.R` | Carry-forward on/off demonstration |
| `R/run_backtest.R` | Historical tracking simulation |
| `R/coredata_export.R` | Coredata naming convention export |
| `R/workbook_output.R` | Template workbook + flat output |
| `R/model_outputs.R` | Forecast extraction, validation, coefficient comparison, audits |
| `R/run_scenario.R` | Isolated scenario runner (used by the dashboard) |
| `dashboard/app.R` | Shiny frontend |
| `data/sourced_data.rds` | The model's quarterly history (the data input) |
| `data/raw_series.rds` | Raw downloaded observations |
| `data-raw/Data.xlsx` | Bootstrap seed (read-only; to be retired) |
| `data-raw/exogenous_forecast.csv` | Exogenous scenario paths |
| `data-raw/exogenous_sources.csv` | Source map for the 18 scenario columns |
| `outputs/data_download_validation.csv` | Sourcing map: every variable, verdict, worst quarter |

## Repository state

Last commit: `13c1568` (2 September 2026). Clean working tree. All model outputs regenerated. Dashboard styling work in progress (unstaged).

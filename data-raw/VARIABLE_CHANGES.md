# Variable cleanup — change log (2026-08-17)

Applied to `data-raw/Data.xlsx` (backup: `data-raw/Data_backup.xlsx`), the
model scripts and `data-raw/exogenous_forecast.csv`. Verified by the
coefficient regression gate: all 291 benchmark coefficients in
`original_estimated_coefficients.csv` reproduced (max relative drift 5e-5,
from xlsx serialisation of the last bits on a few long-decimal columns —
immaterial), plus four new rows for the previously unfitted Whh equation.

## Data fixes

- **Ustar restored to per cent** (the column had drifted to decimal fractions
  after the benchmark was exported). With the broken units the Lavh gap was
  constant (~0.99) and c1/c2 were unidentified (c1 = 2109 vs the true 453).
  Now consistent with `exogenous_forecast.csv` (4.5202) and the Lavh equation
  reproduces the benchmark exactly.
- Header `Name` → `date`.
- Frequency conversion moved out of the model script and into the data:
  `IntStu`, `GovDebt`, `GovDef` (annual FY, deficit sign flipped to
  deficit-positive), and the capital stocks (June benchmarks, log-linearly
  interpolated, components `KNbiz` and `KOther` added) are quarterly series in
  the workbook under a single name. The model script no longer interpolates.

## Removed workbook columns (20 — unused by any equation or identity)

`Bcab`, `Bpri`, `Bsec`, `CtExpMin`, `IbsTot`, `Inbr`, `LPmkt`, `Lpop04`,
`Lpop14`, `Lpop64`, `Lpop65`, `LpubDef`, `Tsec`, `Tsecnon`, `Yfdd`, `Ygdppc`,
`Ygos_ratio`, `Ysd`, `Peqi`, `Wgov`

(`Peqi` and `Wgov` remain as equation names — `fits$Peq` uses `Peq`,
`fits$GovDebt` uses `GovDebt`; only the dead input columns were removed.)

## Removed prep-created variables (21 — computed but never used)

`Bntf`, `Btbr`, `BtbZ`, `CTEXPSER`, `CTIMPTOT`, `dum_1999q4`, `dum_2001q4`,
`dum_2022q1`, `dum_oly`, `IbsDR`, `IcapSimple`, `InbrSp`, `Ipri`, `Lavh`,
`LavhQ`, `LhrsK`, `LPmkt_q`, `LwgeR_cycle`, `sb_2020`, `Ygne_hpf`,
`LhrsNMraw` (inlined). `Ipri` was also mis-specified (`Imin / Inonmin`, a
ratio, where `Imin + Inonmin` was intended) — removed as unused.

## Duplicate definitions resolved

- `dum_gst` defined twice in the prep script (date-based, silently
  overwritten by `as.numeric(DumGst)`): the effective definition is kept once.
- `PCNH` and `Pcnh` (the same ex-rent deflector computed twice under different
  case) consolidated into one series.

## Rename map (applied everywhere: workbook, scripts, exogenous csv)

| Old | New | Reason |
|---|---|---|
| `Ttsf` | `Ytsf` | transfers are income, not taxes |
| `PgneDef` | `Pgne` | GNE deflector, matches `Pgdp` |
| `Kdep` | `KdepRate` | a rate, matching `KMinDepRate` |
| `IbsL/IbsB/IbsE` | `BizLns/BizBnd/BizEq` | meaningful business-finance names |
| `IbsGear` | `BizGear` | follows the Biz family |
| `NOM` | `Lnom` | labour/population domain |
| `Fc_gdp/Fc_ppp` | `FcGdp/FcPpp` | CamelCase |
| `Fpoil_usd/Fpagr_usd` | `Fpoil/Fpagr` | all foreign prices are USD |
| `Fr10y_us/jp/de/uk` | `Fr10yUs/Jp/De/Uk` | CamelCase |
| `PubNetDbt/PubDef` | `GovDebt/GovDef` | Gov family; no collision with the P price prefix |
| `PubNetDbtQ/PubDefQ` | `GovDebt/GovDef` | quarterly series takes the canonical name |
| `PeqiAsx` | `Peq` | the equity price |
| `EqiEarn` | `EqEarn` | equity earnings |
| `Rpe/Rpey` | `PeRatio/EqYield` | ratio and yield, not rates |
| `Icap` | `CostCap` | user cost of capital |
| `Kdepa` | `KdepAllow` | depreciation allowance |
| `Cgg/Igg/Ipe` | `Cgov/Igov/Ipubent` | government/public-enterprise demand |
| `Gfdd` | `GovDem` | public demand |
| `Idw/Ire` | `Idwell/Iotc` | dwellings / ownership transfer costs |
| `IvtNF` | `IvtNonfarm` | spelled out |
| `CprRent/CprRentZ` | `CconsRent/CconsRentNom` | rent consumption |
| `Pceren` | `PconsRent` | rent deflator |
| `Pcnh` | `PconsExrent` | ex-rent deflator |
| `Prent` | `PcpiRent` | CPI rents index |
| `Pgc` | `Pgov` | government consumption deflator |
| `Pidw` | `Pidwell` | dwelling investment deflator |
| `LavhMar` (AvHrsMar) | `LavhMkt` | market-sector average hours |
| `LempM/LempNM` | `LempMkt/LempNonmkt` | market/non-market |
| `LempPA/LempE/LempHE` | `LempPub/LempEdu/LempHlt` | non-market industries |
| `LhrsPB/LhrsED/LhrsHE` | `LhrsPub/LhrsEdu/LhrsHlt` | non-market hours |
| `LhrsTot` | `LhrsAll` | all-industry hours |
| `KBus/KNmin/KDwe/KTot/KOth` | `KBiz/KNbiz/KDwell/KTotal/KOther` | spelled consistently |
| `KMinDepRte` etc | `KMinDepRate` etc | "Rate" spelled out |
| `ULCBS/ULCBSX` | `UlcDom/UlcExp` | what they mean |
| `*Z` | `*Nom` | nominal counterpart (symmetric with `Real`) |
| `Rr90d/Rmortr/Rbizr/Frr10y/Rr10y` | `R90dReal/RmortReal/RbizReal/Fr10yReal/R10yReal` | explicit `Real` |
| `RmortrExGst` | `RmortRealExgst` | follows `Real` |
| `PhouseR` | `PhouseReal` | real house price |
| `*_hpf`, `Phouse_sa` | `*Hpf`, `PhouseSa` | CamelCase series |
| `Lur_star` | `LurHpf` | it is an HP filter; `_star` suffix retired |
| `UstarR` | — (eliminated) | the Lavh gap uses `Ustar/100` inline |
| `PinfE` | `InflExp` | inflation expectations |
| `Wnsav` | `SavHh` | a flow, not a wealth position |

## Equation names

Renamed with their variables: `Ttsf→Ytsf`, `Wgov→GovDebt`, `Idw→Idwell`,
`IvtNF→IvtNonfarm`, `Pcnh→PconsExrent`, `Peqi→Peq`, `Prent→PcpiRent`,
`EqiEarn→EqEarn`, `LempNM→LempNonmkt`, `Pidw→Pidwell`, `Pgc→Pgov`.
The benchmark comparison applies this map; all estimates are unchanged.

## Documentation sheets

The stale `Variables` and `Calculations` sheets were regenerated from the
running code (the old sheets documented `Toth` with `Taxcit`, the superseded
`Tpit = Tsec + Tsecnon` definition, a prose placeholder for `Pxoth`, `Gfdd`
without `Cgov`, pre-adjustment `Lhrs`/`PhouseReal`, `Rtwi` with `Pcpi`
instead of `PcpiExGst`, old RBA series codes, and a different ULC
construction).

## Known dual concept (documented, deliberately unchanged)

Two unemployment-gap concepts are in service: `LurHpf` (HP filter) in the
Tprl/Ytsf/Lpar/Lwge/PconsExrent/Rcash equations and the explicit `Ustar`
NAIRU in Lavh. Standardising would change estimation results, so both are
retained and documented.

This treatment was superseded on 2026-08-26: `LurHpf` is now the NAIRU in
both estimation and forecast equations, and `Ustar` is no longer a scenario
input.

## Forecast integration fixes (2026-08-17)

- `DumGst` was renamed `ShockGst`; it is a continuous COVID tax correction,
  not a binary dummy, and is zero after the actual-data end.
- The scenario-file source column `GovDef` was renamed
  `GovDefAnnualBalance` because it carries an annual surplus-positive balance.
  The simulation converts it to canonical quarterly deficit-positive `GovDef`
  at the database boundary.
  This treatment was superseded on 2026-08-26 by the endogenous fiscal-flow
  identity documented in `VARIABLES.md`.
- The forecast is fixed at 2025Q1 after the 2024Q4 conditioning observation.
  Later rows reproduce the binding coefficient vintage and support historical
  comparison, but are excluded from forecast latent states, residuals,
  calibration ratios, trends and solver seeds.
- Generic recent-residual add-factors were removed. They were fitted in mixed
  log-growth, ratio and level units but appended uniformly to simulated levels.
- `Pgne` now uses its index scale (`100 * nominal / real`) and the matching GNE
  nominal aggregate. `Rbiz` is linked to `R90d` by a calibrated lending spread,
  and `Iotc` uses a documented calibrated ratio to `Idwell`.
- The root runner now enforces the 291-row coefficient constraint and writes
  the quarterly forecast, exogenous assumptions and current variable audit.
- `XsvcNom` now divides the `Pxsvc` index by 100 and the nominal-export
  residual is calibrated after services are included. The former unit mismatch
  inflated nominal exports and destabilised the simultaneous forecast.
- HP-filtered level closures now recurse at their trailing eight-quarter
  observed trend rates; HP-filtered rate closures are held at their final
  observed values, removing artificial current-quarter trend feedback.
- The eight-variable feedback block uses damped Gauss-Seidel and log-domain
  guards. These preserve the positive fixed-point equations while preventing
  invalid intermediate iterates.
- Forecast exogenous values are never silently invented. Historical populated
  scenario rows must agree with `Data.xlsx`.
  `data-raw/exogenous_forecast.csv` is an immutable model input; production code
  reads it but does not generate or modify it. Official-source snapshots are
  retained under `data-raw/sources/`, while exact URLs, publication horizons,
  conversions and terminal model rules are in
  `data-raw/exogenous_sources.csv`. The output audit preserves that distinction
  rather than labelling a post-horizon assumption as published data.

## Estimation and residual process changes (2026-09-02)

- Estimation windows now follow the data end by default (`estimation_end`
  argument of `estimate_model()`); pass a date to pin a vintage. Fourteen
  equations previously stopped before the 2024Q4 data end — Rtwi at 2019Q4,
  Xmin at 2024Q2, Pidwell at 2023Q2, Lavh/Lwge/Piret/Pxagr/Pmgs/R10y/Ppcd/
  PconsExrent at 2023Q3, LempNonmkt/Rmort/Whh at 2023Q4 and Inonmin at 2024Q3 —
  and now estimate to the final observed quarter. Review point for the model
  owner: the Rtwi window now includes COVID and post-COVID quarters and its
  c5 coefficient flips sign (+0.056 to -0.073); re-pin that window if the
  2019Q4 endpoint was a deliberate structural choice.
- The coefficient regression gate is superseded by a written sense-check:
  `outputs/coefficient_comparison.csv` compares each run against
  `original_estimated_coefficients.csv` (old equation names mapped:
  Idw→Idwell, IvtNF→IvtNonfarm, Ttsf→Ytsf, LempNM→LempNonmkt, Peqi→Peq,
  Pgc→Pgov, Pidw→Pidwell, Wgov→GovDebt, Prent→PcpiRent, EqiEarn→EqEarn,
  Pcnh→PconsExrent), and the pre-change snapshot is compared separately in
  `outputs/coefficient_comparison_window_extension.csv` to isolate the effect
  of extending the windows. Largest movers: Lavh c2 (-19.5 to -17.8),
  Lhrs c2 (9.32 to 9.90), the Rtwi block.
- The forecast origin and the residual conditioning quarter now derive from
  the final `Data.xlsx` quarter instead of hardcoded dates (currently 2024Q4
  → origin 2025Q1), so an extended workbook re-estimates and re-forecasts from
  the new quarter in one run.
- Final-quarter equation residuals moved out of the simulation:
  `R/calculate_residuals.R` calculates the Pcpi/PcpiRent/Rcash/Lhrs residuals
  at the conditioning quarter and exports `outputs/residuals.csv`, which the
  simulation reads (stale-conditioning guard included).
  `carry_forward_residuals` in `run_model.R` switches the carry-forward on
  (each residual enters 2025Q1 and fades at persistence 0.9) or off
  (residuals set to zero). A regression run with the pre-change coefficients
  reproduced the previous forecast exactly (max difference 1e-7).
- New outputs: `outputs/residuals.csv`,
  `outputs/model_results_flat.xlsx` (one flat sheet, every model variable,
  1974Q3 to 2036Q4, period-marked Actual/Forecast) and the coefficient
  comparisons above. `Rscript R/run_residual_demo.R` writes the carry-forward
  on/off comparison to `outputs/residual_demo/`.

## Backtest, Shiny dashboard and Coredata export (2026-09-02, later)

- `R/run_backtest.R`: within-sample historical tracking (default 2010Q1 to
  the final data quarter) driven by the actual exogenous paths, with the
  observed COVID corrections (ShockGst, DumTsfTot) applied inside the
  simulation window via the new `observed` argument of
  `build_ts_database()`/`run_bimets_forecast()`. Outputs in
  `outputs/backtest_2010Q1/`. Full-sample coefficients (a pre-2020
  re-estimation is blocked: COVID-dummy regressors are unidentified on
  earlier samples); the frozen-trend closures drive most of the rate and
  unemployment drift.
- The React + Express frontend, `start_sem.cmd` and the npm toolchain were
  removed; `dashboard/` (Shiny) is the only frontend. The intended users have
  R but not Node.js. Launch with `start_dashboard.cmd`. Scenario metadata now
  carries completion in `scenario-runs/<id>/status.txt` (the runner wrapper
  writes it; cmd.exe mangles quoted multi-argument shell command lines, so
  the spawn uses system2/`runner_template.R` instead of shell chaining).
  `Ustar` is no longer offered as an adjustment because it is no longer a
  scenario input.
- `R/coredata_export.R` maps SEM variables onto the national Coredata naming
  conventions (`data-raw/sem_to_coredata.csv`; 50 Coredata variables covered:
  28 exported, 4 flagged for review, 18 with no SEM counterpart) and writes
  `outputs/sem_coredata.xlsx` in the Coredata RAW orientation. Rates and
  ratios are decimal fractions in both conventions. A variable registry
  extracted from the reference workbook is in
  `outputs/coredata_variable_registry.csv`.

## Data download pipeline and restored audits (2026-09-02, later)

- `R/update_data.R` downloads the latest observations for every workbook
  variable with a directly downloadable source: ABS series IDs resolve
  through the ABS Time Series Directory to the current release's time
  series tables, RBA series come from the statistical-table CSVs. The
  transformation noted in the Variables sheet is applied (quarterly as
  published; monthly series take a three-month average with the noted
  divide-by-100; ABS quarterly observations are dated at the first month
  of their quarter and are mapped onto the workbook's end-month quarter
  convention). Every series is validated against the existing history
  (outputs/data_download_validation.csv; median percentage difference,
  power-of-ten unit rescaling with a note, worst quarter) and
  data-raw/Data_updated.xlsx is written with new quarters appended -
  existing history is never rewritten. Findings from the first run:
  the workbook's Yhdi 1975Q2 cell holds 5 against a downloaded 13,989
  (data-entry error; untouched pending review); LhrsPub has been
  rebenchmarked by the ABS (4% median difference, worst 1996Q3); Wfor
  carries recent revisions; household net worth now publishes in $bn and
  is rescaled x1000 to the workbook's $m.
- `data-raw/exogenous_sources.csv` restored (the source-to-variable map for
  the 18 scenario columns, from the official-release snapshots under
  data-raw/sources/). `outputs/variable_audit.csv` (where every
  prepared-data column is used) and `outputs/exogenous_assumptions.csv`
  (effective endpoints joined to the sources map) are written by
  run_model.R again, closing the gap between VARIABLES.md and the repo.

## Conditioning, derived sources and origin advance (2026-09-02, final)

- The forecast origin now derives from data completeness instead of the
  workbook's date end: the conditioning quarter is the last quarter in
  which every residual-calibration input is observed
  (CONDITIONING_INPUTS in R/forecast_model.R). The workbook is ragged
  after a download run, and observations beyond the conditioning quarter
  feed estimation and comparison only. The all-zero shocks baseline
  realigns itself to the forecast window; a baseline with scenario
  values is never rewritten.
- Three former blockers resolved as documented pipeline conventions,
  each validated against the workbook history: Phouse is the
  transfer-weighted median of the 30 median-price series in the ABS
  Total Value of Dwellings Table 2 (continues the 6432.0 Table 2
  derivation, which ceased in 2021; 92 quarters reproduced with zero
  drift); Lnom is ABS 3101.0 series A2060785W divided by 1000; the
  capital stocks continue their final quarterly increment past the last
  5204.0 benchmark (the workbook's own past-benchmark convention; no new
  benchmark exists in the current release). Variables-sheet sources
  updated accordingly, and Whh's stale multiplied-by-100 note corrected
  to multiplied by 1000 (the release now publishes $bn).
- update_data.R merges under explicit per-variable policies (fill /
  adopt / carry-trend / carry-hold): official values fill missing cells
  only, rebenchmarked series are adopted over the span (LhrsPub, Wfor),
  and carriers extend from the last finite row. Direct write to
  Data.xlsx - git diff is the review, the validation CSV the artifact.
- The forecast advanced from 2025Q1 to 2025Q4 (conditioning 2025Q3,
  residual carry-forward re-exported). It is now bound only by the
  publication lags of quarterly NOM and the labour-account hours, and
  advances automatically as releases land. Forecast-versus-observed
  check at 2026Q1: GDP +0.9%, CPI -0.2%.
- Rbiz investigated: the documented D8/F7 splice matches no published
  RBA series and needs the original derivation; skipped with that
  finding recorded.

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

## Forecast integration fixes (2026-08-17)

- `DumGst` was renamed `ShockGst`; it is a continuous COVID tax correction,
  not a binary dummy, and is zero after the actual-data end.
- The scenario-file source column `GovDef` was renamed
  `GovDefAnnualBalance` because it carries an annual surplus-positive balance.
  The simulation converts it to canonical quarterly deficit-positive `GovDef`
  at the database boundary.
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

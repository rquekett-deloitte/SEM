# Variable dictionary

Single source of truth for variable names and definitions. The workbook
(`data-raw/Data.xlsx`) carries the same content in its `Variables` and
`Calculations` sheets; `outputs/variable_audit.csv` records usage. Rename
history is documented in `data-raw/VARIABLE_CHANGES.md`.

## Conventions

- UpperCamelCase for all series. Deterministic terms are lowercase with
  underscores (`trend_98`, `dum_2020q2`, `q3`, `d93`, `sb_2001`).
- Domain prefixes: `C` consumption, `I` investment, `Ivt` inventories,
  `X` exports, `M` imports, `Y` income and aggregates, `P` prices/deflators,
  `L` labour and population, `T` taxes, `F` foreign, `W` wealth positions,
  `K` capital stocks, `Biz` business finance, `Gov` public sector, `R` rates
  (interest, exchange, returns).
- `Nom` = current-price counterpart of a volume series (`CprNom`); `Real` =
  real counterpart of a nominal rate (`R90dReal`). The pair is symmetric.
- `Hpf` = HP-filtered trend (`YgdpHpf`). Equilibrium levels carry no suffix:
  `Ustar` (NAIRU, in per cent), `Rstar` (neutral rate).
- Frequency conversion (annual/monthly to quarterly) happens at the documented
  workbook-normalisation boundary; the model receives quarterly series under a
  single name (`GovDebt`, `IntStu`, the `K` stocks).
- `UlcDom` / `UlcExp`: Balassa-Samuelson unit labour costs (domestic and
  traded-sector concepts).

## Workbook inputs (122 series)

The cleaned conditioning workbook is quarterly from 1974Q3 through 2024Q4.
The documented pre-cleanup backup supplies the later estimation-vintage rows
through 2026Q1 (some series are shorter). `date` is the quarter index.

| Name | Definition | Source |
|---|---|---|
| Lune | Unemployed total ;  Persons ; (Seasonally Adjusted, Thousands) | ABS 6202.0 (A84423046K) |
| Lhh | All households ; | 6224.0.55.001 Labour Force Status of Families, June 2025 |
| Lpar | Participation rate ;  Persons ; (Seasonally Adjusted, Percent) | ABS 6202.0 (A84423051C) |
| Pcpi | Index Numbers ;  All groups CPI, seasonally adjusted ;  Australia ; | ABS 6401.0 (A3604506F), backfilled 1974Q3-1986Q3 from validated AEM PceCpi splice |
| Ygdp | GROSS DOMESTIC PRODUCT ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304402X) |
| YgdpNom | GROSS DOMESTIC PRODUCT ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304418T) |
| SavHh | Households ;  Net saving ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2302837X) |
| Cpr | Households ;  Final consumption expenditure ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304081W) |
| Idwell | Private ;  Gross fixed capital formation - Dwellings - Total ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304098T) |
| Iotc | Private ;  Gross fixed capital formation - Ownership transfer costs ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304099V) |
| Ygne | Gross national expenditure ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304113C) |
| Xtot | Exports of goods and services ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304114F) |
| Mtot | Imports of goods and services ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304115J) |
| CprNom | Households ;  Final consumption expenditure ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304037L) |
| XtotNom | Exports of goods and services ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2303824F) |
| MtotNom | Imports of goods and services ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2303825J) |
| Ywss | Compensation of employees ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2303359K) |
| Yhdi | GROSS DISPOSABLE INCOME ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2302939L) |
| Lwge | Average compensation per employee: Current prices ; (Seasonally Adjusted, Dollars) | ABS 5206.0 (A2302606R) |
| Pulc | Unit labour cost - Nominal - Non-farm ; (Seasonally Adjusted, Index Numbers) | ABS 5206.0 (A2433074L) |
| Tprl | Payroll taxes ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2302778K) |
| Tgst | Goods and services tax | ABS 5206.0 (A2302784F) |
| Ttot | TOTAL TAXES ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2302794K) |
| Imin | Gross fixed capital formation - Mining private business investment: Chain volume measures ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A85222698X) |
| IminNom | Gross fixed capital formation - Mining private business investment: Current prices ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A85125298V) |
| Inonmin | Gross fixed capital formation - Non-mining private business investment: Chain volume measures ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A85222699A) |
| InonminNom | Gross fixed capital formation - Non-mining private business investment: Current prices ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A85125299W) |
| Xmet | Chain Volume Measures ;  Metal ores and minerals ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535047K) |
| Xccb | Chain Volume Measures ;  Coal, coke and briquettes ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535048L) |
| Xomf | Chain Volume Measures ;  Other mineral fuels ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535049R) |
| Xagr | Chain Volume Measures ;  Rural goods ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535041W) |
| XagrNom | Current Prices ;  Rural goods ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535191C) |
| Wfor | Position at end of period ;  NET INTERNATIONAL INVESTMENT POSITION ; (Original, $ Millions) | ABS 5302.0 (A3484240C) |
| KMin | Mining sector net capital stock (real), annual end-June benchmark | ABS 5204.0 (A3347284T) |
| KBiz | Total business net capital stock (real), annual end-June benchmark | ABS 5204.0 (A2422581A) |
| KDwell | Dwellings net capital stock (real), annual end-June benchmark | ABS 5204.0 (A2422532F) |
| PcpiRent | Index Numbers ;  Rents ;  Australia ; (Original) | ABS 6401.0 (A2331876F) |
| Xsvc | Chain Volume Measures ;  Services credits ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535093X) |
| Pxsvc | Implicit Price Deflators ;  Services credits ; (Seasonally Adjusted, Index Numbers) | ABS 5302.0 (A3534945V) |
| Xmex | Chain Volume Measures ;  Metals (excl. non-monetary gold) ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535050X) |
| Xmac | Chain Volume Measures ;  Machinery ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535051A) |
| Xtrn | Chain Volume Measures ;  Transport equipment ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535052C) |
| Xotm | Chain Volume Measures ;  Other manufactures ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535053F) |
| Xonr | Chain Volume Measures ;  Other non-rural (incl. sugar and beverages) ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535054J) |
| Xgpr | Chain Volume Measures ;  Goods procured in ports by carriers ; (Seasonally Adjusted, $ Millions) | ABS 5302.0 (A3535058T) |
| R10y | Australian Government 10 year bond (Per cent per annum) | RBA (FCMYGBAG10) |
| R90d | 3-month BABs/NCDs (Percent) | RBA (FIRMMBAB90) |
| Rusd | A$1=USD | RBA (FXRUSD) |
| RtwiNom | Trade-weighted Index May 1970 = 100 (Index Numbers) | RBA (FXRTWI) |
| R10yReal | Australian Government Indexed Bond (Per cent per annum) | RBA (FCMYGBAGI) |
| Rmort | Lending rates; Housing loans; Banks; Variable; Standard; Owner-occupier (Per cent per annum) | RBA (FILRHLBVS) |
| Whh | Houshousehold net worth; (Original, $ Millions) | ABS 5232.0 (A83722648X) |
| IdwellNom | Private ;  Gross fixed capital formation - Dwellings - Total ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304054R) |
| IotcNom | Private ;  Gross fixed capital formation - Ownership transfer costs ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304055T) |
| Cgov | General government ;  Final consumption expenditure ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304080V) |
| CgovNom | General government ;  Final consumption expenditure ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304036K) |
| Ygoa | All sectors ;  Gross operating surplus ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2303375K) |
| Lsup | Labour force total ;  Persons ; (Seasonally Adjusted, Thousands) | ABS 6202.0 (A84423047L) |
| Lpop | Estimated Resident Population (ERP) ;  Australia ; (Original, Thousands) | ABS 3101.0 (A2133251W) |
| IvtNonfarm | Private non-farm inventory levels: Chain volume measures ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2302597X) |
| Tcit | Corporate income tax | ABS 5206.0 (A2323407R + A2323360T) |
| Ytsf | General government ;  Total personal benefits payments ; (Original, $ Millions) | ABS 5206.0 (A2301976F) |
| Ygdw | Dwellings owned by persons ;  Gross operating surplus ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2303373F) |
| LempPub | Public Administration and Safety ;  Employed total ; (Seasonally Adjusted, Thousands) | ABS 6291.0.55.001 (A84090242C) |
| LempEdu | Education and Training ;  Employed total ; (Seasonally Adjusted, Thousands) | ABS 6291.0.55.001 (A84090231W) |
| LempHlt | Health Care and Social Assistance ;  Employed total ; (Seasonally Adjusted, Thousands) | ABS 6291.0.55.001 (A84090235F) |
| BizLns |  |  |
| BizBnd |  |  |
| Ygmi |  |  |
| YprpR |  |  |
| YprpP |  |  |
| Lemp | Employed total ;  Persons ; (Seasonally Adjusted, Thousands) | ABS 6202.0 (A84423043C) |
| LhrsAll | Volume; Labour Account hours actually worked in all jobs ;  Australia ;  Total all industries ; (Seasonally Adjusted, 000 Hours) | 6150.0.55.003 (A85389483J) |
| LhrsPub | Volume; Labour Account hours actually worked in all jobs ;  Australia ;  Public administration and safety (O) ; (Seasonally Adjusted, 000 Hours) | 6150.0.55.003 (A85392872W) |
| LhrsEdu | Volume; Labour Account hours actually worked in all jobs ;  Australia ;  Education and training (P)  ; (Seasonally Adjusted, 000 Hours) | 6150.0.55.003 (A85393092A) |
| LhrsHlt | Volume; Labour Account hours actually worked in all jobs ;  Australia ;  Health care and social assistance (Q)  ; (Seasonally Adjusted, 000 Hours) | 6150.0.55.003 (A85393382X) |
| Igov | General government ;  Gross fixed capital formation ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304108K) |
| Ipubent | Public corporations ;  Gross fixed capital formation ; (Seasonally Adjusted, $ Millions) | ABS 5206.0 (A2304103X) |
| Pgne | Gross national expenditure implicit price deflator, index (base 100) | ABS 5206.0 |
| Phouse | Median price of established dwelling transfers, transfer-weighted ; (Original, $'000) | ABS 6432.0 (Table 2, derived from Median Price & Number of Transfers series) |
| IvtFar | Farm inventories | Exogenous |
| Fpcpi | World consumer prices | Exogenous |
| Fpoil | World oil price, USD | Exogenous scenario series |
| Fpcom | World commodity price index (real) | Exogenous |
| Fpagr | World agricultural commodity price index, USD | Exogenous scenario series |
| Fr10yUs | United States 10-year government bond yield, decimal annual rate | Exogenous scenario series |
| Fr10yJp | Japan 10-year government bond yield, decimal annual rate | Exogenous scenario series |
| Fr10yDe | Germany 10-year government bond yield, decimal annual rate | Exogenous scenario series |
| Fr10yUk | United Kingdom 10-year government bond yield, decimal annual rate | Exogenous scenario series |
| FcGdp | China real GDP | Exogenous scenario series |
| FcPpp | China implied PPP conversion rate | Exogenous scenario series |
| KTotal | Total economy net capital stock (real), annual end-June benchmark | ABS 5204.0 (A2422574C) |
| PeRatio | ASX All Ordinaries P/E ratio (Calculated PE Ratio) | LSEG / Refinitiv (via Temp/Masterdata.xlsx sheet 'PEratio') |
| EqEarn | Listed-company earnings (ASX 200 earnings) | LSEG / Refinitiv (via Temp/Masterdata.xlsx sheet 'Master(SEM)') |
| Lnom | Net overseas migration, thousands of persons per quarter | ABS / exogenous scenario series |
| XmetNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| XccbNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| XomfNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| XmexNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| XmacNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| XtrnNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| XotmNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| XonrNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| XgprNom | Nominal exports component, $m (identity input) | ABS 5206.0 |
| CconsRentNom | Nominal household consumption of rent, $m | ABS 5206.0 |
| CconsRent | Real household consumption of rent, $m | ABS 5206.0 |
| GovDef | Public-sector deficit, quarterly $bn, deficit positive | Derived from annual fiscal balance |
| GovDebt | Public-sector net debt, $bn | Public-sector fiscal data |
| Rbiz | Bank lending to business; weighted-average interest rate on credit outstanding; total (Per cent per annum) | RBA D8 (DBLWAT) to 2019Q3; RBA F7 weighted average thereafter |
| BizEq |  |  |
| TcorpRate | Statutory company income tax rate | ATO |
| KdepRate | Non-mining capital depreciation rate | Capital-stock calibration |
| DumTsfTot | Transfers equation COVID correction (EViews DUMMY_TSFTOT) | Scenario model residuals (Temp/Masterdata.xlsx sheet Master(SEM)) |
| Peq |  |  |
| LavhMkt | Market-sector average hours actually worked per quarter, per employed person (hours) | ABS 6291.0.55.001 detailed labour force, market-sector aggregate, via Temp/Masterdata.xlsx sheet 'Master(SEM)' column AvHrsMar (built on sheet 'Average HW' from the industry hours and 'Employment - market'); this is the AVHRSMAR variable of the EViews SEM |
| Ustar | Non-accelerating-inflation rate of unemployment (NAIRU), per cent | Deloitte Access Economics SEM, via Temp/Masterdata.xlsx sheet 'Master(SEM)' column Ustar - this is the LUR_STAR variable of the EViews SEM |
| Tpit | Personal income tax | ABS 5206.0 (A2302733F + A2302779L) |
| IntStu | International student enrolments, new to Australia | Department of Education, International students.xlsx |
| PcpiExGst | CPI excluding GST effects | AEM PCPIUX via validated reference workbook |
| ShockGst | GST/other-tax COVID correction; zero outside the historical shock period | Scenario model correction series |
| KNbiz |  |  |
| KOther | Residual non-business, non-dwelling net capital stock (real) | ABS 5204.0, derived residual |

## Calculated in data preparation (R/calculate_estimation_data.R)

| Name | Calculation |
|---|---|
| BizGear | (BizLns + BizBnd) / (BizLns + BizBnd + BizEq) (debt share of business finance) |
| CostCap | (RbizReal * BizGear + EqYield * (1 - BizGear) + KdepRate) * (1 - KdepAllow * TcorpRate) (Jorgensonian user cost of capital) |
| CprHpf | hp_filter(Cpr) |
| d93 | 1 from 1993Q1 (inflation-targeting regime) |
| EqYield | 1 / PeRatio (equity earnings yield) |
| Fr10y | (3/5) Fr10yUs + (1/6) Fr10yJp + (3/20) Fr10yDe + (1/12) Fr10yUk |
| Fr10yReal | Fr10y - average of two 4-quarter world CPI inflation rates (lags 2-6 and 6-10) |
| GovDem | Igov + Ipubent + Cgov (public demand) |
| InflExp | hp_filter(log(Pcpi / lag(Pcpi, 4))) (HP-filtered annual CPI inflation; expectations proxy) |
| Ivt | IvtFar + IvtNonfarm |
| KdepAllow | (KdepRate * (1 + R10y)) * (R10y + KdepRate) (depreciation allowance) |
| KDwellDepRate | 1 - (KDwell - lag(Idwell)) / lag(KDwell) |
| KMinDepRate | 1 - (KMin - lag(Imin)) / lag(KMin) |
| KNbizDepRate | 1 - (KNbiz - lag(Inonmin)) / lag(KNbiz) |
| LempMkt | Lemp - LempNonmkt |
| LempNonmkt | LempPub + LempEdu + LempHlt |
| Lhrs | LhrsAllSa - LhrsNonmkt (market-sector hours) |
| LhrsAllSa | X-13ARIMA-SEATS seasonal adjustment of LhrsAll |
| LhrsNonmkt | X-13ARIMA-SEATS seasonal adjustment of (LhrsPub + LhrsEdu + LhrsHlt) |
| LparHpf | hp_filter(Lpar) |
| Lur | Lune / Lsup |
| LurHpf | hp_filter(Lur) |
| PconsExrent | (CprNom - CconsRentNom) / (Cpr - CconsRent) (ex-rent implicit deflator) |
| PconsRent | CconsRentNom / CconsRent (rent implicit price deflator) |
| Pgdp | YgdpNom / Ygdp |
| Pgov | CgovNom / Cgov |
| PhouseHpf | hp_filter(Phouse) |
| PhouseReal | PhouseSa / Pcpi |
| PhouseSa | X-13ARIMA-SEATS seasonal adjustment of Phouse |
| Pidwell | IdwellNom / Idwell |
| Pimin | IminNom / Imin |
| Pinonmin | InonminNom / Inonmin |
| Piret | IotcNom / Iotc |
| Pmgs | MtotNom / Mtot |
| Ppcd | CprNom / Cpr |
| PpcdHpf | hp_filter(Ppcd) |
| Ptot | 100 * Pxtot / Pmgs (terms of trade) |
| Pxagr | XagrNom / Xagr |
| Pxmin | XminNom / Xmin |
| Pxoth | XothNom / Xoth (composite implicit price deflator) |
| Pxtot | XtotNom / Xtot |
| q3 | September-quarter indicator |
| R90dReal | R90d - (Pcpi / lag(Pcpi, 4) - 1) |
| RbizReal | (1 - TcorpRate) * Rbiz / (PconsExrent / lag(PconsExrent, 4)) (real after-tax business lending rate) |
| Rdif10y | R10yReal - Fr10yReal (real 10-year rate differential) |
| RmortReal | Rmort - (Pcpi / lag(Pcpi, 4) - 1) |
| RmortRealExgst | Rmort - (PcpiExGst / lag(PcpiExGst, 4) - 1) |
| RmortRealHpf | hp_filter(RmortReal) |
| Rtwi | RtwiNom * lag(PcpiExGst) / lag(Fpcpi) (real TWI) |
| sb_2001 | 1 from 2002Q1 (structural break, other goods exports) |
| Toth | Ttot - Tpit - Tcit - Tgst - Tprl (residual other taxes) |
| trend | row_number() - 1 (deterministic trend, 1974Q3 = 0) |
| trend_98 | cumsum(date >= 1998Q1); trend_01 and trend_08 analogous |
| trend_piret | trend + 8 (legacy trend origin shift for the Piret equation) |
| UlcDom | log(Pulc) + 0.002764 * ((1 - c2) / c2) * trend; c2 estimated jointly in the Ppcd Balassa-Samuelson signal equation |
| UlcExp | log(Pulc) - 0.002764 * trend |
| Xmin | Xmet + Xccb + Xomf |
| XminNom | XmetNom + XccbNom + XomfNom |
| Xoth | Xmex + Xmac + Xtrn + Xotm + Xonr + Xgpr |
| XothNom | XmexNom + XmacNom + XtrnNom + XotmNom + XonrNom + XgprNom |
| YgdpHpf | hp_filter(Ygdp) |
| Ynli | Ygmi + YprpR - YprpP (non-labour household income) |

`Rstar` (RTS-smoothed neutral rate) is calculated in R/estimation.R for the
estimation equations. At the 2025Q1 forecast boundary it is refiltered using
only data through 2024Q4, preventing post-origin outcomes from entering the
forecast state. Dummy variables `dum_*` are deterministic event indicators
defined with the trends in R/calculate_estimation_data.R.

## Forecast input contract

`R/forecast_model.R::mdl_exogenous_contract()` is the executable forecast-input
contract. The permitted scenario columns are:

`Lpop`, `Lpop15Plus`, `Ustar`, `Cgov`, `Igov`, `Ipubent`,
`GovDefAnnualBalance`, `IvtFar`, `Lnom`, `IntStu`, `Fpcpi`, `Fpoil`, `Fpcom`,
`Fpagr`, `FcGdp`, `FcPpp`, `Fr10yUs`, `Fr10yJp`, `Fr10yDe`, and `Fr10yUk`.

Missing columns, unexpected columns, invalid dates, non-consecutive quarters,
non-numeric cells, and blank forecast-quarter cells are errors.
`GovDefAnnualBalance` is an annual $bn balance with surplus positive; it is
converted once at the database boundary to canonical `GovDef` (quarterly $bn,
deficit positive). There is no implicit last-actual carry in the production
forecast path.

The forecast origin is fixed at `2025-03-01`. The simulation database admits
actual observations only through `2024-12-01`; later observations remain
available solely for coefficient-vintage reproduction and forecast-versus-
actual reporting.

`data-raw/exogenous_forecast.csv` is the authoritative quarterly scenario input
and is not generated or modified by model code. The supporting official-source
snapshots are retained in `data-raw/sources/`. The source-to-variable map,
publication horizon, temporal conversion and terminal rule for every column
are explicit in `data-raw/exogenous_sources.csv`. In particular:

- Australian public demand uses the 2026-27 Budget aggregate forecast through
  2027-28, applied proportionally to `Cgov`, `Igov` and `Ipubent`; those real
  components grow with population thereafter, keeping real per-capita levels
  constant.
- `Lpop` and `Lnom` use the latest Budget NOM through 2029-30 and Centre for
  Population components thereafter. Annual population levels are interpolated
  quarterly; annual NOM is divided by four.
- `Lpop15Plus` applies the Centre for Population's published 15+ population
  share to the latest `Lpop` path. This supplies the age-appropriate labour-
  force denominator while retaining the newer Budget NOM assumptions.
- `GovDefAnnualBalance` uses the Budget accrual fiscal balance through 2029-30,
  then an explicitly labelled convergence to zero by 2034-35.
- `IvtFar = 0` is a neutral forecast closure informed by Treasury's zero total
  inventory contribution, not a claimed farm-inventory observation.
- `IntStu` applies the Department of Education's published 6 per cent
  year-to-date decline in new students to the 2025 annual observation. The
  295,000 planning level is retained only as a policy ceiling and is not
  represented as an enrolment forecast.
- IMF WEO paths drive foreign inflation, oil, commodities, China GDP and China
  PPP through their published horizons; OECD supplies long-run China growth
  and the four foreign 10-year rates.

`outputs/exogenous_assumptions.csv` records effective endpoints, historical
agreement with `Data.xlsx`, source names and URLs, published horizons, and the
distinction between official values and documented model extensions. No
post-horizon extension is presented as published data.

## Forecast closures

Accounting identities retain their definitions above. Variables without an
estimated equation use the following explicit forecast closures:

- `Iotc = RatioIotc * Idwell`, with `RatioIotc` calibrated from the latest
  eight common observations.
- `Pxsvc` is an index around 100, unlike the ratio-form export deflators, so
  services exports are valued as `XsvcNom = (Pxsvc / 100) * Xsvc`. The nominal
  export residual is calibrated after including that component.
- `Rbiz = R90d + SpreadRbiz`, with `SpreadRbiz` equal to the latest eight-
  quarter mean business-lending spread.
- `Pgne` is `100 * nominal GNE / real GNE` plus the last common chain-volume
  additivity residual.
- Government/private aggregate shares, income ratios, depreciation rates and
  chain-volume additivity residuals are calibrated from the latest common
  observations and then held fixed. They are calibration constants, not
  exogenous scenario series.
- `Lsup = Lpop15Plus * Lpar`. Historical `Lpop15Plus` is the observed labour
  force divided by the participation rate; its forecast path uses the Centre
  for Population's official single-year age projections rather than a fixed
  last-actual denominator or a constant total-population share.
- `KOther` is held at its final observed level because no matching investment
  series exists in the authoritative inputs.
- Historical `*Hpf` names retain the two-sided HP-filter definition. In the
  forecast, level trends `YgdpHpf`, `CprHpf`, `PhouseHpf` and `PpcdHpf` grow
  recursively at their trailing eight-quarter observed trend rates. Rate
  trends `LparHpf`, `LurHpf`, `RmortRealHpf` and `InflExp` are held at their
  final observed values. `Ustar` remains a separate NAIRU concept used only by
  the `LavhMkt` unemployment gap.
- Historical event dummies and `ShockGst` are zero after the actual-data end.
- The eight-variable simultaneous feedback block is solved by damped
  Gauss-Seidel with a 10 per cent update weight. At convergence the damped
  equation is algebraically identical to the original SEM equation. Log
  arguments use `ABS()` only as an iteration-domain guard; it is identical on
  the model's positive admissible solution.

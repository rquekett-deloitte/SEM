# Exogenous forecast source snapshots

These CSV files contain the published values supporting
`data-raw/exogenous_forecast.csv`. They were extracted from the following
official releases on 17 August 2026. They are provenance snapshots, not fitted
or synthetic observations.

| Snapshot | Official release | Exact location used |
|---|---|---|
| `centre_population_2025.csv` | [Centre for Population projections](https://population.gov.au/data-and-forecasts/projections) | `Population Statement: National Population Projections, 2024-25 to 2035-36`, workbook `PROJECTIONS` sheet: natural increase, NOM and population at end of year. |
| `centre_population_age_15_plus_2025.csv` | [Centre for Population projections](https://population.gov.au/data-and-forecasts/projections) | `Population Statement: National Population Projections by Age and Sex, 2024-25 to 2035-36`, workbook `PROJECTIONS` sheet: `Persons` ages 15 through 100 summed for each financial year; total population and the resulting 15+ share are retained for audit. |
| `budget_2026_27.csv` | [Australian Budget 2026-27, Budget Paper No. 1](https://budget.gov.au/content/bp1/index.htm) | Statement 2 Table 2.2: 2024-25 outcome and forecasts for public final demand and NOM; Statement 3 Table 3.7: 2024-25 outcome and forecasts for fiscal balance. The Table 2.2 footnote supplies NOM for 2028-29 and 2029-30. |
| `imf_weo_april_2026.csv` | [IMF World Economic Outlook database](https://data.imf.org/Datasets/WEO) | April 2026 entire-dataset workbook: 2024 base observations and forecasts from `Country Groups` G7 CPI, `Commodity Prices` APSP oil/all commodities/agricultural raw materials, and `Countries` China real GDP growth and implied PPP conversion rate. |
| `oecd_eo_june_2026_rates.csv` | [OECD Economic Outlook Statistical Annex](https://www.oecd.org/en/topics/sub-issues/economic-outlook/oecd-economic-outlook-statistical-annex.html) | June 2026 statistical-annex workbook, `Long_term_Interest_Rates` sheet, 2025 observations and 2026-27 forecasts for the United States, Japan, Germany and United Kingdom. |
| `oecd_lts_2025_china.csv` | [OECD global long-run economic scenarios: 2025 update](https://www.oecd.org/en/topics/sub-issues/economic-outlook/long-run-economic-scenarios-2025-update.html) | Published `LTS-2025-potential-real-gdp-growth.csv`, China, Business as usual 1 (BAU1), potential-output growth. |
| `international_students_npl.csv` | [Department of Education year-to-date data](https://www.education.gov.au/international-education-data-and-research/resources/international-student-data-yeardate-ytd) and [managed system](https://www.education.gov.au/managed-system-international-education) | December 2025 actual new-student total; May 2026 new-student count and published 6% year-to-date decline; 295,000 New Overseas Student Commencements planning ceiling for 2026 and 2027. The observed decline is extrapolated; the ceiling is not treated as a forecast. |

The mapping, temporal conversion and every post-publication-horizon rule are in
`data-raw/exogenous_sources.csv`. The quarterly values in
`data-raw/exogenous_forecast.csv` are a maintained input and are not generated
or modified by model code.

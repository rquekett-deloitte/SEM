# Raw data

The production model does not read `Data.xlsx`. Historical observations are
persisted in `data/sourced_data.rds`, refreshed from the source catalog in
`VARIABLES.md` by `R/download_data.R` and `R/prepare_model_data.R`, and prepared
for estimation in `data/model_data.rds`. The former workbook is retired; it is
not an input to sourcing, estimation, conditioning, forecasting or output.

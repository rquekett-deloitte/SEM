# Fixed coefficients used by the Rcash state-space equation.
RCASH_IMPOSED <- c(c1 = 0.3, c2 = -2, c3 = 1, c4 = -1)

# The residual-calibration inputs that must be observed at the conditioning
# quarter (shared by data preparation and the forecast database so both
# assert completeness against the same list).
CONDITIONING_INPUTS <- c(
  "Pcpi", "Ppcd", "PcpiRent", "PhouseHpf", "RmortRealHpf", "Lnom", "Lwge",
  "R90d", "Lur", "LurHpf", "d93", "Lhrs", "KTotal", "Ygdp", "YgdpHpf",
  "Pgdp", "trend"
)

# Model variables supplied by the explicit exogenous forecast contract. These
# may bridge missing observations before the dynamic origin, so they must not
# determine the last complete observed conditioning quarter.
FORECAST_EXOGENOUS_INPUTS <- c(
  "Lpop", "Cgov", "Igov", "Ipubent", "IvtFar", "Lnom", "IntStu",
  "Fpcpi", "Fpoil", "Fpcom", "Fpagr", "FcGdp", "FcPpp",
  "Fr10yUs", "Fr10yJp", "Fr10yDe", "Fr10yUk"
)
# Runtime source catalog. VARIABLES.md is the maintained variable/source map;
# the retired Data.xlsx workbook is not a production dependency.
read_variable_catalog <- function(path = "VARIABLES.md") {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  table_lines <- lines[grepl("^\\|[^-]", lines)]
  rows <- lapply(table_lines, function(line) {
    fields <- trimws(strsplit(line, "\\|", fixed = FALSE)[[1]])
    if (length(fields) < 4L) return(NULL)
    data.frame(variable = fields[[2]], source = fields[[4]],
               stringsAsFactors = FALSE)
  })
  out <- dplyr::bind_rows(rows)
  out <- out[out$variable != "Name" & nzchar(out$variable), , drop = FALSE]
  # VARIABLES.md documents Lnom as ABS/exogenous; the historical ABS series
  # identifier and unit conversion are recorded in VARIABLE_CHANGES.md.
  out$source[out$variable == "Lnom"] <-
    paste(out$source[out$variable == "Lnom"], "A2060785W")
  out$transformation <- NA_character_
  out$transformation[out$variable == "Lnom"] <- "divided by 1000"
  out
}

# Every non-scenario column the simulation database needs at the conditioning
# quarter. The forecast database checks this after filling the explicit
# pre-origin bridge from data-raw/exogenous_forecast.csv and recomputing the
# identities that depend on it. The estimation data remains observation-only.
MODEL_DATA_INPUTS <- c(
  CONDITIONING_INPUTS,
  "Yhdi", "Whh", "R90dReal", "CprNom", "Lemp", "LempMkt", "LempNonmkt",
  "GovDem", "Ygoa", "YgdpNom", "Ywss", "Ygdw", "CprHpf", "PhouseReal",
  "PhouseSa", "Pidwell", "PpcdHpf", "RmortRealExgst", "Pxoth",
  "Pxsvc", "Pgne", "Ynli", "EqYield", "Rusd", "InflExp",
  "R10yReal", "Rdif10y", "RtwiNom", "Wfor", "BizGear", "Rbiz", "RbizReal",
  "CostCap", "KdepRate", "TcorpRate", "KMin", "KBiz", "KNbiz", "KDwell",
  "KOther", "Peq", "PeRatio", "EqEarn", "LavhMkt", "PcpiExGst", "ShockGst",
  "DumTsfTot", "GovDef", "GovDebt", "Lhh", "PconsRent", "CconsRent",
  "CconsRentNom", "PconsExrent", "Mtot", "Xtot", "Xmin", "Xagr",
  "Xoth", "Xsvc", "Imin", "Inonmin", "IvtNonfarm", "Ivt", "Iotc", "Idwell",
  "Cpr", "Cgov", "Igov", "Ipubent", "Tpit", "Tcit", "Tgst", "Tprl", "Toth",
  "Ytsf", "Lpop", "Lnom", "Lpar", "Lwge", "Pulc", "UlcDom", "UlcExp",
  "Piret"
)

# Only these fields may be supplied or recomputed by the explicit exogenous
# bridge before the forecast origin.  Every other model input must be finite
# in the selected conditioning quarter.  This keeps a newly released subset
# of a ragged data vintage from advancing the model beyond its usable state.
FORECAST_BRIDGE_INPUTS <- c(
  FORECAST_EXOGENOUS_INPUTS,
  "Lhh",       # fixed households/population ratio, using scenario Lpop
  "Ivt",       # IvtFar plus observed IvtNonfarm change
  "Rdif10y"    # observed R10yReal less scenario-derived Fr10yReal
)
OBSERVED_CONDITIONING_INPUTS <- setdiff(
  unique(MODEL_DATA_INPUTS), unique(FORECAST_BRIDGE_INPUTS)
)

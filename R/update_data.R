# Data update pipeline: download, transform, validate, extend.
#
# Downloads the latest data for every workbook variable with a directly
# downloadable source:
#   - ABS: the series IDs in the Variables sheet resolve, via the ABS Time
#     Series Directory (TSSearchServlet), to the current release's time
#     series table downloads.
#   - RBA: the statistical-table CSVs (f1.1, f2.1, f5, f11 monthly).
# The transformation noted in the workbook's Variables sheet is applied
# (quarterly as published; monthly series take a three-month average, with
# the noted divide-by-100; multiple-series sources are summed). Every series
# is validated against the existing history - the source-correctness check -
# and Data.xlsx is updated in place with the new quarters appended. Existing
# history is extended, never rewritten, except for the documented rebench-
# marked series in ADOPT_CURRENT_VINTAGE; routine revisions are quantified
# in the validation report, not adopted. Git is the review and revert
# mechanism; outputs/data_download_validation.csv is the review artifact.
#
# Run from the project root:  Rscript R/update_data.R
# Outputs: data-raw/Data.xlsx (updated in place; git diff is the review,
#          outputs/data_download_validation.csv,
#          data-raw/downloads/ (table cache, git-ignored).

required_packages <- c("jsonlite", "openxlsx", "readr", "tidyverse")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop("Install the required packages first: ",
       paste(missing_packages, collapse = ", "))
}

suppressPackageStartupMessages({
  library(openxlsx)
  library(tidyverse)
})

options(timeout = 300)
download_dir <- file.path("data-raw", "downloads")
dir.create(download_dir, showWarnings = FALSE, recursive = TRUE)
WORKBOOK <- "data-raw/Data.xlsx"
# The pipeline writes Data.xlsx directly: git is the review and revert
# mechanism, and outputs/data_download_validation.csv is the review artifact.
CANDIDATE <- "data-raw/Data.xlsx"
UA <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

variables_sheet <- read.xlsx(WORKBOOK, sheet = "Variables")
data_sheet <- read.xlsx(WORKBOOK, sheet = "Data", detectDates = TRUE)
data_sheet$date <- as.Date(data_sheet$date)
existing_end <- max(data_sheet$date)
data_columns <- setdiff(names(data_sheet), "date")

# ---- source routing --------------------------------------------------------------

ABS_ID <- "A[0-9]{7,8}[A-Z]"
RBA_TABLES <- c(
  FIRMMBAB90 = "f1.1", FCMYGBAG10 = "f2.1", FCMYGBAGI = "f2.1",
  FXRUSD = "f11", FXRTWI = "f11", FILRHLBVS = "f5"
)

# Series the statistical agency has rebenchmarked since the workbook's
# vintage. The workbook's values are superseded, so the candidate workbook
# ADOPTS the current official series over the whole overlapping span instead
# of extending only. Everything else stays extend-only: routine revisions
# are quantified in the validation report, not adopted.
ADOPT_CURRENT_VINTAGE <- c("LhrsPub", "Wfor")

# Documented derivation conventions. Phouse is the transfer-weighted median
# of the 30 median-price series (established houses and attached dwellings,
# eight capitals and seven rest-of-state) in the ABS Total Value of
# Dwellings Table 2 - the continuation of the ceased 6432.0 Table 2
# derivation, validated to reproduce the workbook history exactly
# (92 quarters, zero drift). The capital stocks have no new 5204.0
# benchmark in the current release, so beyond the last observation their
# final quarterly increment continues (KOther's level holds) - the same
# convention the workbook itself used past its final benchmark.
DERIVED_PHOUSE_URL <- paste0(
  "https://www.abs.gov.au/statistics/economy/",
  "price-indexes-and-inflation/total-value-dwellings/",
  "latest-release/643202.xlsx")
CARRY_TREND <- c("KMin", "KBiz", "KDwell", "KTotal")
CARRY_HOLD <- c("TcorpRate", "KdepRate", "DumTsfTot")

fetch_phouse <- function() {
  dest <- file.path(download_dir, basename(DERIVED_PHOUSE_URL))
  if (!file.exists(dest)) {
    ok <- tryCatch({
      download.file(DERIVED_PHOUSE_URL, dest, quiet = TRUE, mode = "wb")
      TRUE
    }, error = function(e) FALSE)
    if (!ok) return(NULL)
  }
  sheets <- getSheetNames(dest)
  data_sheet <- grep("^Data", sheets, value = TRUE)[1]
  n <- nrow(read.xlsx(dest, sheet = data_sheet, colNames = FALSE, cols = 1))
  head <- read.xlsx(dest, sheet = data_sheet, colNames = FALSE,
                    rows = seq_len(min(14, n)))
  id_row <- which(apply(head, 1, function(r)
    any(grepl("Series ID", r, fixed = TRUE))))[1]
  ids <- as.character(unlist(head[id_row, ]))
  descs <- as.character(unlist(head[1, ]))
  body <- read.xlsx(dest, sheet = data_sheet, colNames = FALSE,
                    rows = (id_row + 1):n, detectDates = FALSE)
  dates <- as.Date(as.numeric(body[[1]]), origin = "1899-12-30")
  median_cols <- which(!is.na(ids) &
    grepl("Median Price of", descs, fixed = TRUE))
  transfer_cols <- which(!is.na(ids) &
    grepl("Number of", descs, fixed = TRUE))
  if (length(median_cols) == 0 || length(transfer_cols) != length(median_cols)) {
    stop("Unexpected Total Value of Dwellings table structure")
  }
  num <- rep(0, length(dates))
  den <- rep(0, length(dates))
  for (k in seq_along(median_cols)) {
    med <- as.numeric(body[[median_cols[k]]])
    tr <- as.numeric(body[[transfer_cols[k]]])
    ok <- is.finite(med) & is.finite(tr)
    num[ok] <- num[ok] + med[ok] * tr[ok]
    den[ok] <- den[ok] + tr[ok]
  }
  tibble(date = repo_quarter(dates),
         value = ifelse(den > 0, num / den, NA_real_))
}
DERIVED_SOURCES <- list(Phouse = fetch_phouse)

# Peq: the ASX All Ordinaries index (points), end-of-quarter close, via the
# Yahoo Finance chart API (free, undocumented - browser user agent
# required). Validated: 34 quarters reproduced with 0.000% median
# difference. The FRED SPASTT01AUQ661N series is a differently-based OECD
# index and does not track it (correlation 0.63).
fetch_peq <- function() {
  url <- paste0("https://query1.finance.yahoo.com/v8/finance/chart/%5EAORD",
               "?range=10y&interval=1d")
  dest <- file.path(download_dir, "yahoo_aord.json")
  ok <- tryCatch({
    download.file(url, dest, quiet = TRUE, mode = "wb", headers = c(
      "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"))
    TRUE
  }, error = function(e) FALSE)
  if (!ok) return(NULL)
  raw_bytes <- readBin(dest, "raw", file.size(dest))
  raw <- jsonlite::fromJSON(
    rawToChar(raw_bytes[raw_bytes != as.raw(0)]), simplifyVector = TRUE)
  res <- raw$chart$result
  dates <- as.Date(as.POSIXct(res$timestamp[[1]], origin = "1970-01-01",
                              tz = "UTC"))
  close <- as.numeric(res$indicators$quote[[1]]$close[[1]])
  frame <- data.frame(date = dates, close = close)
  frame <- frame[is.finite(frame$close), ]
  frame$qdate <- repo_quarter(frame$date)
  ends <- vapply(split(frame[order(frame$date), ], frame$qdate[order(frame$date)]),
                 function(g) utils::tail(g$close, 1), numeric(1))
  tibble(date = as.Date(names(ends)), value = as.numeric(ends))
}
DERIVED_SOURCES$Peq <- fetch_peq

# Business finance (BizLns, BizBnd, BizEq): the workbook holds the
# old-definition private non-financial corporations sector ($bn) - the sum
# of today's "other private non-financial corporations" and "private
# non-financial investment funds" sectors in ABS 5232.0 Table 1 ($m),
# divided by 1000. Validated: bonds and equity reproduce the workbook
# exactly; loans to 0.7% (classification drift between vintages).
FW_TABLE_URL <- paste0(
  "https://www.abs.gov.au/statistics/economy/national-accounts/",
  "australian-national-accounts-finance-and-wealth/latest-release/5232001.xlsx")

read_fw_table <- function() {
  dest <- file.path(download_dir, "5232001.xlsx")
  if (!file.exists(dest)) {
    ok <- tryCatch({
      download.file(FW_TABLE_URL, dest, quiet = TRUE, mode = "wb")
      TRUE
    }, error = function(e) FALSE)
    if (!ok) return(NULL)
  }
  sheets <- getSheetNames(dest)
  data_sheet <- grep("^Data", sheets, value = TRUE)[1]
  n <- nrow(read.xlsx(dest, sheet = data_sheet, colNames = FALSE, cols = 1))
  head <- read.xlsx(dest, sheet = data_sheet, colNames = FALSE,
                    rows = seq_len(min(14, n)))
  id_row <- which(apply(head, 1, function(r)
    any(grepl("Series ID", r, fixed = TRUE))))[1]
  ids <- as.character(unlist(head[id_row, ]))
  descs <- as.character(unlist(head[1, ]))
  body <- read.xlsx(dest, sheet = data_sheet, colNames = FALSE,
                    rows = (id_row + 1):n, detectDates = FALSE)
  dates <- as.Date(as.numeric(body[[1]]), origin = "1899-12-30")
  list(ids = ids, descs = descs, body = body, dates = dates)
}

fetch_biz <- function(instrument) {
  tbl <- read_fw_table()
  if (is.null(tbl)) return(NULL)
  cols <- vapply(
    c("Other private non-financial corporations",
      "Private non-financial investment funds"),
    function(sector) {
      j <- which(grepl(paste0(sector, " ;  ", instrument, " ;  Total"),
                       tbl$descs, fixed = TRUE) &
                   grepl("Total (Counterparty sectors)", tbl$descs,
                         fixed = TRUE))
      if (length(j)) j[1] else NA_integer_
    }, integer(1))
  if (any(is.na(cols))) {
    message("FW: could not find ", instrument, " series")
    return(NULL)
  }
  total <- rep(NA_real_, length(tbl$dates))
  for (j in cols) {
    v <- as.numeric(tbl$body[[j]])
    total[is.finite(v)] <- rowSums(cbind(total[is.finite(v)], v[is.finite(v)]),
                                   na.rm = TRUE)
  }
  tibble(date = repo_quarter(tbl$dates), value = total / 1000)
}
DERIVED_SOURCES$BizLns <- function() fetch_biz("Loans and placements borrowed from:")
DERIVED_SOURCES$BizBnd <- function() fetch_biz("Bonds, etc. held by:")
DERIVED_SOURCES$BizEq <- function() fetch_biz("Shares and other equity held by:")

# Post-merge internal derivations, applied to the merged columns (exact
# over the whole history by construction).
POSTMERGE_DERIVED <- list(
  KNbiz = function(updated) updated$KBiz - updated$KMin,
  KOther = function(updated) updated$KTotal - updated$KBiz - updated$KDwell,
  # EqEarn = Peq / PeRatio exactly (the model's EqYield identity, verified
  # at 0.000% over 82 quarters); fills automatically once PeRatio extends.
  EqEarn = function(updated) updated$Peq / updated$PeRatio
)

abs_series_ids <- function(source) {
  unique(unlist(regmatches(source, gregexpr(ABS_ID, source))))
}
rba_series_ids <- function(source) {
  names(RBA_TABLES)[vapply(names(RBA_TABLES), function(id)
    grepl(id, source, fixed = TRUE), logical(1))]
}

# The scenario-maintained series: exogenous by design (world drivers, the
# farm-inventory neutral closure and the policy-capped student series).
# This mirrors mdl_exogenous_contract() in R/forecast_model.R; the contract
# is the authoritative list. Everything else in the workbook is data that
# must be sourced.
EXOGENOUS_MAINTAINED <- c(
  "Fpcpi", "Fpoil", "Fpcom", "Fpagr", "FcGdp", "FcPpp",
  "Fr10yUs", "Fr10yJp", "Fr10yDe", "Fr10yUk", "IvtFar", "IntStu"
)

route <- variables_sheet %>%
  transmute(
    variable = Name,
    source = Source,
    transformation = Transformation,
    abs_ids = map(source, abs_series_ids),
    rba_ids = map(source, rba_series_ids)
  ) %>%
  filter(variable %in% data_columns) %>%
  mutate(
    category = if_else(variable %in% EXOGENOUS_MAINTAINED,
                       "exogenous", "sourced"),
    skip_reason = case_when(
      category == "exogenous" ~
        "exogenous by design - maintained via exogenous_forecast.csv",
      variable %in% CARRY_HOLD ~
        "constant - held at its final level (see source note)",
      variable %in% names(POSTMERGE_DERIVED) ~
        "derived - computed from its parents after the merge",
      variable == "Rbiz" ~
        paste0("sourcing open: the documented D8/F7 splice matches no ",
               "published RBA series - F5's weighted-average business rates ",
               "ended with D8 and no F7 series reproduces the workbook's ",
               "continuation; the original derivation is needed"),
      variable %in% c("PeRatio", "EqEarn", "LavhMkt", "PcpiExGst", "ShockGst",
                      "GovDef", "GovDebt", "Lhh", "KdepRate") ~
        paste0("sourcing open: owner derivation required - see the source ",
               "note for what was tested"),
      map_int(abs_ids, length) + map_int(rba_ids, length) == 0 &
        !variable %in% names(DERIVED_SOURCES) &
        is.na(source) | !nzchar(source) ~ "sourcing open: no documented source",
      TRUE ~ ""
    )
  )

# ---- ABS: resolve series IDs to table downloads -----------------------------------

tss_block <- function(series_id) {
  path <- file.path(download_dir, paste0("tss_", series_id, ".xml"))
  if (!file.exists(path)) {
    url <- paste0("https://www.abs.gov.au/servlet/TSSearchServlet?sid=",
                  series_id)
    ok <- tryCatch({
      download.file(url, path, quiet = TRUE, mode = "wb")
      TRUE
    }, error = function(e) FALSE)
    if (!ok) return(NULL)
  }
  xml <- paste(readLines(path, warn = FALSE), collapse = "\n")
  blocks <- regmatches(xml, gregexpr("<Series>.*?</Series>", xml))[[1]]
  if (!length(blocks)) return(NULL)
  first <- blocks[[1]]
  pick <- function(tag) {
    pattern <- paste0("<", tag, ">(.*?)</", tag, ">")
    m <- regexec(pattern, first)
    if (m[[1]][1] == -1) {
      # tags may be spread across lines; try the whitespace-tolerant join
      m <- regexec(pattern, gsub("\\s+", " ", first))
    }
    if (m[[1]][1] == -1) return(NA_character_)
    got <- regmatches(first, m)[[1]]
    trimws(got[2])
  }
  list(
    table_url = pick("TableURL"),
    frequency = pick("Frequency"),
    series_end = pick("SeriesEnd"),
    product = pick("ProductNumber"),
    description = pick("Description")
  )
}

tss_table_cache <- new.env(parent = emptyenv())

download_tss_table <- function(url) {
  if (!grepl("^https?://", url)) return(NULL)
  path <- file.path(download_dir, basename(url))
  if (!file.exists(path)) {
    ok <- tryCatch({
      download.file(url, path, quiet = TRUE, mode = "wb")
      TRUE
    }, error = function(e) FALSE)
    if (!ok) return(NULL)
  }
  path
}

read_tss_table <- function(table_path) {
  sheets <- getSheetNames(table_path)
  data_sheet_name <- grep("^Data", sheets, value = TRUE)[1]
  if (is.na(data_sheet_name)) stop("No Data sheet in ", table_path)
  n <- nrow(read.xlsx(table_path, sheet = data_sheet_name,
                      colNames = FALSE, cols = 1))
  head <- read.xlsx(table_path, sheet = data_sheet_name, colNames = FALSE,
                    rows = seq_len(min(12, n)))
  id_row <- which(apply(head, 1, function(r)
    any(grepl("Series ID", r, fixed = TRUE))))[1]
  if (is.na(id_row)) stop("No Series ID row in ", table_path)
  ids <- as.character(unlist(head[id_row, ]))
  body <- read.xlsx(table_path, sheet = data_sheet_name, colNames = FALSE,
                   rows = (id_row + 1):n, detectDates = FALSE)
  dates_raw <- body[[1]]
  dates <- if (inherits(dates_raw, c("Date", "POSIXct"))) {
    as.Date(dates_raw)
  } else {
    as.Date(as.numeric(dates_raw), origin = "1899-12-30")
  }
  out <- list(date = dates)
  for (j in seq_along(ids)[-1]) {
    if (j > ncol(body)) break
    if (!is.na(ids[j]) && nzchar(ids[j])) out[[ids[j]]] <- as.numeric(body[[j]])
  }
  as_tibble(out)
}

tss_tables <- new.env(parent = emptyenv())
tss_meta <- new.env(parent = emptyenv())

abs_series <- function(series_id) {
  if (!is.null(tss_meta[[series_id]])) return(tss_meta[[series_id]])
  meta <- tss_block(series_id)
  if (is.null(meta) || is.na(meta$table_url)) {
    message("TSS: could not resolve ", series_id)
    tss_meta[[series_id]] <- NULL
    return(NULL)
  }
  table_path <- download_tss_table(meta$table_url)
  if (is.null(table_path)) {
    message("TSS: could not download ", meta$table_url)
    tss_meta[[series_id]] <- NULL
    return(NULL)
  }
  key <- basename(meta$table_url)
  if (is.null(tss_tables[[key]])) {
    tss_tables[[key]] <- tryCatch(
      read_tss_table(table_path),
      error = function(e) {
        message("TSS: could not read ", basename(table_path), ": ",
                conditionMessage(e))
        NULL
      }
    )
  }
  if (is.null(tss_tables[[key]])) {
    tss_meta[[series_id]] <- NULL
    return(NULL)
  }
  result <- list(meta = meta, table = tss_tables[[key]])
  tss_meta[[series_id]] <- result
  result
}

# ---- RBA ---------------------------------------------------------------------------

RBA_MONTHS <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
                "Oct", "Nov", "Dec")

parse_rba_date <- function(x) {
  # RBA tables use both "30-Jun-1969" and "30/06/1969".
  x <- trimws(x)
  out <- as.Date(rep(NA_character_, length(x)))
  alpha <- grepl("^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}$", x)
  if (any(alpha)) {
    p <- do.call(rbind, strsplit(x[alpha], "-"))
    out[alpha] <- as.Date(sprintf("%s-%02d-%s", p[, 3],
                                  match(p[, 2], RBA_MONTHS), p[, 1]))
  }
  slash <- grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", x)
  if (any(slash)) {
    p <- do.call(rbind, strsplit(x[slash], "/"))
    out[slash] <- as.Date(sprintf("%s-%s-%s", p[, 3], p[, 2], p[, 1]))
  }
  out
}

rba_tables <- new.env(parent = emptyenv())

read_rba_table <- function(table_code) {
  if (!is.null(rba_tables[[table_code]])) return(rba_tables[[table_code]])
  path <- file.path(download_dir, paste0(table_code, "-data.csv"))
  if (!file.exists(path)) {
    url <- paste0("https://www.rba.gov.au/statistics/tables/csv/",
                  table_code, "-data.csv")
    ok <- tryCatch({
      download.file(url, path, quiet = TRUE, mode = "wb")
      TRUE
    }, error = function(e) FALSE)
    if (!ok) return(NULL)
  }
  raw <- readLines(path, warn = FALSE)
  raw <- raw[nzchar(trimws(raw))]
  id_line <- grep("^Series ID,", raw)
  if (!length(id_line)) return(NULL)
  ids_row <- raw[id_line[1]]
  ids_df <- utils::read.csv(text = ids_row, header = FALSE,
                           check.names = FALSE, na.strings = "")
  ids <- as.character(ids_df[1, ])
  # col.names pins the column count to the Series ID row: without it,
  # read.csv infers the width from the first data row and silently
  # truncates later series.
  body <- utils::read.csv(path, skip = id_line[1], header = FALSE,
                          check.names = FALSE, na.strings = c("", "NA"),
                          colClasses = "character", fill = TRUE,
                          col.names = paste0("V", seq_along(ids)))
  parsed <- parse_rba_date(as.character(body[[1]]))
  keep <- is.finite(parsed)
  body <- body[keep, , drop = FALSE]
  out <- list(date = parsed[keep])
  for (j in seq_along(ids)[-1]) {
    if (j > ncol(body)) break
    code <- ids[j]
    if (!is.na(code) && nzchar(code)) {
      out[[code]] <- suppressWarnings(as.numeric(trimws(body[[j]])))
    }
  }
  result <- as_tibble(out)
  rba_tables[[table_code]] <- result
  result
}

# ---- transformations ----------------------------------------------------------------

# The workbook dates quarters by their end month (Q1 = March, ..., Q4 =
# December); ABS time series tables date an observation at the first month
# of its quarter and monthly series need a three-month average. Both are
# handled by mapping every month to the end month of its quarter.
repo_quarter <- function(d) {
  as.Date(sprintf("%d-%02d-01", as.integer(format(d, "%Y")),
                  3 * ((as.integer(format(d, "%m")) + 2) %/% 3)))
}

apply_transform <- function(series, frequency, transformation) {
  if (is.null(series)) return(NULL)
  if (grepl("Month", frequency, fixed = TRUE)) {
    series <- series %>%
      mutate(quarter = repo_quarter(date)) %>%
      group_by(quarter) %>%
      summarise(value = mean(value[is.finite(value)]), .groups = "drop") %>%
      transmute(date = quarter, value)
  } else {
    # Quarterly and annual series: snap the observation date onto the
    # workbook's quarter-end-month convention (annual end-June benchmarks
    # land on the June quarter).
    series <- series %>%
      transmute(date = repo_quarter(date), value)
  }
  if (grepl("divided by ", transformation, fixed = TRUE)) {
    divisor <- as.numeric(sub(".*divided by ([0-9]+).*", "\\1",
                              transformation))
    if (is.finite(divisor) && divisor > 0) {
      series <- series %>% mutate(value = value / divisor)
    }
  }
  series
}

fetch_abs_variable <- function(ids, transformation) {
  parts <- lapply(ids, function(id) {
    res <- abs_series(id)
    if (is.null(res)) return(NULL)
    tibble(date = res$table$date,
           value = as.numeric(res$table[[id]]),
           frequency = res$meta$frequency)
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (!length(parts)) return(NULL)
  frequency <- parts[[1]]$frequency[1]
  transformed <- lapply(parts, function(p)
    apply_transform(p[, c("date", "value")], frequency, transformation))
  if (length(transformed) == 1) return(transformed[[1]])
  # multi-part sources (e.g. two tax components): sum on the common dates
  out <- transformed[[1]]
  for (k in 2:length(transformed)) {
    out <- out %>%
      full_join(transformed[[k]], by = "date", suffix = c("", "_k")) %>%
      mutate(value = coalesce(value, 0) + coalesce(value_k, 0)) %>%
      select(date, value)
  }
  out
}

fetch_rba_variable <- function(ids, transformation) {
  parts <- lapply(ids, function(id) {
    tbl <- read_rba_table(RBA_TABLES[[id]])
    if (is.null(tbl) || !(id %in% names(tbl))) return(NULL)
    tibble(date = tbl$date, value = tbl[[id]])
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (!length(parts)) return(NULL)
  transformed <- lapply(parts, function(p)
    apply_transform(p, "Month", transformation))
  if (length(transformed) == 1) return(transformed[[1]])
  out <- transformed[[1]]
  for (k in 2:length(transformed)) {
    out <- out %>%
      full_join(transformed[[k]], by = "date", suffix = c("", "_k")) %>%
      mutate(value = value + coalesce(value_k, 0)) %>%
      select(date, value)
  }
  out
}

# ---- run the pipeline -----------------------------------------------------------------

cat("Existing history:", length(unique(data_sheet$date)), "quarters, ending",
    format(existing_end), "\n")
cat("Downloading ABS and RBA series for variables with a clear source...\n\n")

series_cache <- new.env(parent = emptyenv())

process_variable <- function(variable, source, transformation,
                              abs_ids, rba_ids, skip_reason, category) {
  # Route list-columns arrive as lists; normalise to plain (possibly empty)
  # character vectors.
  abs_ids <- unlist(abs_ids)
  rba_ids <- unlist(rba_ids)
  empty <- tibble(variable = variable, category = category, status = "x",
                  note = "",
                  n_overlap = NA_integer_, median_abs_pct_diff = NA_real_,
                  mean_abs_pct_diff = NA_real_, max_abs_pct_diff = NA_real_,
                  worst_quarter = "", verdict = "n/a",
                  n_new = NA_integer_, new_end = "")
  if (nzchar(skip_reason)) {
    return(empty %>% mutate(status = "skipped", note = skip_reason))
  }
  series <- NULL
  if (variable %in% names(DERIVED_SOURCES)) {
    series <- tryCatch(DERIVED_SOURCES[[variable]](),
                       error = function(e) {
                         message("Derived source failed for ", variable, ": ",
                                 conditionMessage(e))
                         NULL
                       })
  }
  if (is.null(series) && length(abs_ids)) {
    series <- fetch_abs_variable(abs_ids, transformation)
  }
  if (is.null(series) && length(rba_ids)) {
    series <- fetch_rba_variable(rba_ids, transformation)
  }
  if (is.null(series)) {
    return(empty %>% mutate(status = "failed",
                            note = "download or transform failed"))
  }
  existing <- data_sheet[, c("date", variable)]
  overlap <- inner_join(existing, series, by = "date") %>%
    filter(is.finite(.data[[variable]]), is.finite(value))
  # Unit check: the workbook is the unit reference. If the downloaded series
  # differs by a power of ten (the current ABS release may publish in a
  # different unit than the vintage the workbook was built from), rescale
  # it and record that in the report.
  scale_note <- ""
  if (nrow(overlap)) {
    ratio <- stats::median(overlap$value / overlap[[variable]], na.rm = TRUE)
    if (is.finite(ratio) && ratio > 0 &&
        abs(log10(ratio) - round(log10(ratio))) < 0.02 &&
        round(log10(ratio)) != 0) {
      factor <- 10^(-round(log10(ratio)))
      series <- series %>% mutate(value = value * factor)
      overlap <- overlap %>% mutate(value = value * factor)
      scale_note <- paste0("rescaled x", format(factor),
                           " to workbook units; ")
    }
  }
  scale <- function(a, b) ifelse(abs(b) > 1e-9, 100 * abs(a - b) / abs(b), NA)
  pct <- scale(overlap$value, overlap[[variable]])
  median_diff <- stats::median(abs(pct), na.rm = TRUE)
  mean_diff <- suppressWarnings(mean(abs(pct), na.rm = TRUE))
  max_diff <- suppressWarnings(max(abs(pct), na.rm = TRUE))
  worst <- if (nrow(overlap) && any(is.finite(pct))) {
    format(overlap$date[which.max(abs(pct))])
  } else ""
  # The workbook is ragged after a partial update: "new" means any finite
  # official value for a cell that is currently missing - beyond the
  # workbook end or inside a not-yet-filled column - never an overwrite.
  cell_values <- data_sheet[[variable]][match(series$date, data_sheet$date)]
  new_data <- series %>%
    mutate(cell = cell_values) %>%
    filter(is.finite(value), is.na(cell))
  verdict <- case_when(
    !is.finite(median_diff) ~ "no comparable overlap",
    median_diff < 0.5 ~ "source confirmed",
    median_diff < 2 ~ "revisions - review",
    TRUE ~ "MISMATCH - check source"
  )
  # Cache the fully transformed series for the extension step.
  series_cache[[variable]] <- series
  if (variable %in% ADOPT_CURRENT_VINTAGE) {
    verdict <- "current official vintage adopted (rebenchmarked series)"
  }
  result <- tibble(
    variable = variable,
    category = category,
    status = "downloaded",
    note = paste0(scale_note, length(c(abs_ids, rba_ids)),
                  " series; overlap ends ",
                  if (nrow(overlap)) format(max(overlap$date)) else "none"),
    n_overlap = nrow(overlap),
    median_abs_pct_diff = round(median_diff, 3),
    mean_abs_pct_diff = round(mean_diff, 3),
    max_abs_pct_diff = round(max_diff, 3),
    worst_quarter = worst,
    verdict = verdict,
    n_new = nrow(new_data),
    new_end = if (nrow(new_data)) format(max(new_data$date)) else ""
  )
  if (variable %in% c(CARRY_TREND, CARRY_HOLD)) {
    result$note <- paste0(result$note,
                          "; no new benchmark - extended by the carry ",
                          "convention")
  }
  result
}

fail_row <- function(variable, message) {
  tibble(variable = variable, category = "sourced", status = "failed",
         note = paste0("error: ", substr(message, 1, 160)),
         n_overlap = NA_integer_, median_abs_pct_diff = NA_real_,
         mean_abs_pct_diff = NA_real_, max_abs_pct_diff = NA_real_,
         worst_quarter = "", verdict = "n/a",
         n_new = NA_integer_, new_end = "")
}

results <- lapply(seq_len(nrow(route)), function(i) {
  args <- as.list(route[i, ])
  tryCatch(do.call(process_variable, args),
           error = function(e) {
             cat("ERROR on", route$variable[i], ":", conditionMessage(e), "\n")
             fail_row(route$variable[i], conditionMessage(e))
           })
})
results <- bind_rows(results)

# ---- extend the workbook ----------------------------------------------------------------

new_quarters <- sort(unique(unlist(results$new_end[
  results$status == "downloaded" & results$n_new > 0 &
    nzchar(results$new_end)])))
if (length(new_quarters)) {
  quarter_ends <- as.Date(new_quarters)
  from <- seq(existing_end, by = "quarter", length.out = 2)[2]
  # The date column only grows when a series extends beyond the current
  # workbook end; ragged fills inside the span need no new rows.
  extended_dates <- if (max(quarter_ends) >= from) {
    seq(from, max(quarter_ends), by = "quarter")
  } else {
    NULL
  }
} else {
  extended_dates <- NULL
}

# Merge one column under an explicit policy:
#   "fill"        - write official values into missing cells only
#   "adopt"       - the official series replaces the whole overlapping span
#   "carry-trend" - continue the final observed quarterly increment
#   "carry-hold"  - hold the final observed level
merge_column <- function(existing, all_dates, series, policy) {
  col <- as.numeric(existing)
  if (policy %in% c("fill", "adopt")) {
    idx <- match(series$date, all_dates)
    hit <- !is.na(idx) & is.finite(series$value)
    if (policy == "adopt") {
      col[idx[hit]] <- series$value[hit]
    } else {
      write <- hit & is.na(col[idx])
      col[idx[write]] <- series$value[write]
    }
  } else {
    finite <- which(is.finite(col))
    last <- if (length(finite)) finite[length(finite)] else NA
    if (!is.na(last) && last < length(col)) {
      if (policy == "carry-trend") {
        step <- if (last > 1 && is.finite(col[last - 1])) {
          col[last] - col[last - 1]
        } else 0
        for (k in (last + 1):length(col)) col[k] <- col[k - 1] + step
      } else {
        for (k in (last + 1):length(col)) col[k] <- col[last]
      }
    }
  }
  col
}

merge_policy <- function(variable) {
  if (variable %in% ADOPT_CURRENT_VINTAGE) "adopt" else
  if (variable %in% CARRY_TREND) "carry-trend" else
  if (variable %in% CARRY_HOLD) "carry-hold" else "fill"
}

anything_downloaded <- any(results$status == "downloaded")
if (anything_downloaded) {
  updated <- data_sheet
  for (d in extended_dates) updated[nrow(updated) + 1, "date"] <- d
  all_dates <- updated$date
  for (i in seq_len(nrow(results))) {
    r <- results[i, ]
    variable <- r$variable
    if (r$status != "downloaded") next
    if (r$n_new == 0 && !(variable %in% c(CARRY_TREND, CARRY_HOLD)) &&
        !(variable %in% ADOPT_CURRENT_VINTAGE)) next
    series <- series_cache[[variable]]
    if (is.null(series)) next
    updated[[variable]] <- merge_column(updated[[variable]], all_dates,
                                        series, merge_policy(variable))
  }
  # Held constants extend by level regardless of download status.
  for (variable in CARRY_HOLD) {
    updated[[variable]] <- merge_column(updated[[variable]], all_dates,
                                        tibble(date = as.Date(NA), value = NA),
                                        "carry-hold")
  }
  for (nm in intersect(names(POSTMERGE_DERIVED), names(updated))) {
    updated[[nm]] <- POSTMERGE_DERIVED[[nm]](updated)
  }
  wb <- loadWorkbook(WORKBOOK)
  removeWorksheet(wb, "Data")
  addWorksheet(wb, "Data")
  writeData(wb, "Data", updated, startRow = 1)
  # keep the Data sheet first
  order <- wb$sheet_names
  worksheetOrder(wb) <- match(c("Data",
                                setdiff(order, "Data")), order)
  saveWorkbook(wb, CANDIDATE, overwrite = TRUE)
  cat("\nWorkbook updated:", CANDIDATE,
      if (length(extended_dates)) {
        paste0(" - date column extended to ",
               format(max(extended_dates)))
      } else {
        " - ragged columns filled within the existing span"
      }, "\n")
} else {
  cat("\nNo downloadable series produced data; workbook not touched.\n")
}

dir.create("outputs", showWarnings = FALSE)
write_csv(results, "outputs/data_download_validation.csv")

cat("\n=== Sourcing map ===\n")
print(count(results, category), n = Inf)
cat("\n=== Sourced detail ===\n")
print(count(results[results$category == "sourced", ], verdict), n = Inf)
cat("\n=== Exogenous (maintained via the scenario file) ===\n")
print(results$variable[results$category == "exogenous"])
cat("\n=== Sourcing still open (owner derivation required) ===\n")
open_items <- results[grepl("^sourcing open", results$note),
                      c("variable", "note")]
print(as.data.frame(open_items), row.names = FALSE)
cat("\nFull report: outputs/data_download_validation.csv\n")

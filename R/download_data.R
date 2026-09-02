# Downloads the raw data. Downloads only - no transformation, no merging.
#
# Fetches the tables listed in VARIABLES.md (ABS series via
# the Time Series Directory, RBA statistical CSVs) plus the special tables
# (Yahoo All Ordinaries, ABS Finance & Wealth, Total Value of Dwellings) and
# the open-variable source tables (RBA F7 business lending rates, ABS 6291
# industry hours, ABS 6224 experimental households, GFS fiscal aggregates,
# annual capital-stock tables). Every series is written to
# data/raw_series.rds, keyed by its published series id with description and
# frequency metadata. Transformation into model data happens in one place:
# R/prepare_model_data.R.
#
# Run: Rscript R/download_data.R

required_packages <- c("jsonlite", "openxlsx", "readxl", "tidyverse")
missing <- required_packages[!vapply(required_packages, requireNamespace,
                                     logical(1), quietly = TRUE)]
if (length(missing)) stop("Install first: ", paste(missing, collapse = ", "))

suppressPackageStartupMessages({
  library(openxlsx)
  library(readxl)
  library(tidyverse)
})
source("R/model_constants.R")

abs_detailed_url <- paste0("https://www.abs.gov.au/statistics/labour/",
                           "employment-and-unemployment/",
                           "labour-force-australia-detailed/latest-release/")

options(timeout = 300)
dir.create("data-raw/downloads", showWarnings = FALSE, recursive = TRUE)

# A data refresh must consult the current upstream files.  The download
# directory is a fallback/cache for transient network failures, not a reason
# to keep an older release indefinitely.  Set SEM_USE_DOWNLOAD_CACHE=1 only
# for an intentional offline/reproducibility run.
refresh_download_cache <- !tolower(Sys.getenv("SEM_USE_DOWNLOAD_CACHE")) %in%
  c("1", "true", "yes")

download_cache_file <- function(url, path) {
  tmp <- tempfile(pattern = "sem-download-", tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  ok <- tryCatch({
    download.file(url, tmp, quiet = TRUE, mode = "wb")
    file.info(tmp)$size > 0 && file.copy(tmp, path, overwrite = TRUE)
  }, error = function(e) FALSE, warning = function(w) FALSE)
  isTRUE(ok)
}

abs_id_pattern <- "A[0-9]{7,8}[A-Z]"

# ---- fetchers ----------------------------------------------------------------

cache_get <- function(url, filename = basename(url)) {
  path <- file.path("data-raw/downloads", filename)
  if (refresh_download_cache || !file.exists(path)) {
    download_cache_file(url, path)
  }
  if (file.exists(path)) path
}

# An ABS time series table: Data sheet parsed to (series_id, date, value)
# with description and frequency metadata.
abs_table <- function(url) {
  path <- cache_get(url)
  if (is.null(path)) return(NULL)
  sheet <- grep("^Data", getSheetNames(path), value = TRUE)[1]
  # Keep physical row numbers intact.  The ABS data sheets have a blank cell
  # in column A on the description row; openxlsx's default empty-row removal
  # makes a column-A row count one shorter than the worksheet and therefore
  # drops the newest observation when that count is reused in `rows=` below.
  n_rows <- nrow(read.xlsx(
    path, sheet = sheet, colNames = FALSE,
    skipEmptyRows = FALSE, skipEmptyCols = FALSE
  ))
  header <- read.xlsx(path, sheet = sheet, colNames = FALSE,
                      rows = seq_len(min(12, n_rows)))
  id_row <- which(apply(header, 1, function(r)
    any(grepl("Series ID", r, fixed = TRUE))))[1]
  ids <- as.character(unlist(header[id_row, ]))
  descs <- as.character(unlist(header[1, ]))
  body <- read.xlsx(path, sheet = sheet, colNames = FALSE,
                    rows = (id_row + 1):n_rows, detectDates = FALSE)
  dates_raw <- body[[1]]
  dates <- if (inherits(dates_raw, c("Date", "POSIXct"))) {
    as.Date(dates_raw)
  } else {
    as.Date(as.numeric(dates_raw), origin = "1899-12-30")
  }
  # Frequency is metadata only; a binary or placeholder-corrupted cache read
  # must degrade to NA rather than abort the whole download.
  frequency <- tryCatch({
    xml <- paste(readLines(path, warn = FALSE), collapse = "\n")
    m <- regmatches(xml, regexec("<Frequency>(.*?)</Frequency>", xml))
    if (length(m[[1]])) m[[1]][2] else NA_character_
  }, error = function(e) NA_character_)
  map_dfr(setdiff(intersect(which(!is.na(ids) & nzchar(ids)), seq_len(ncol(body))), 1),
          function(j) {
    tibble(series_id = ids[j], description = descs[j], frequency = frequency,
           date = dates, value = suppressWarnings(as.numeric(body[[j]])))
  }) %>%
    filter(is.finite(value))
}

abs_series_url <- function(series_id) {
  path <- file.path("data-raw/downloads", paste0("tss_", series_id, ".xml"))
  url <- paste0("https://www.abs.gov.au/servlet/TSSearchServlet?sid=",
               series_id)
  if (refresh_download_cache || !file.exists(path)) {
    download_cache_file(url, path)
  }
  if (!file.exists(path)) return(NA_character_)
  xml <- paste(readLines(path, warn = FALSE), collapse = "\n")
  match <- regmatches(xml, regexec("<TableURL>(.*?)</TableURL>", xml))[[1]]
  if (length(match) < 2) NA_character_ else match[2]
}

months <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
            "Oct", "Nov", "Dec")

parse_rba_date <- function(x) {
  x <- trimws(x)
  ok_alpha <- grepl("^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}$", x)
  ok_slash <- grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", x)
  out <- as.Date(rep(NA_character_, length(x)))
  if (any(ok_alpha)) {
    p <- strcapture("([0-9]{2})-([A-Za-z]{3})-([0-9]{4})", x[ok_alpha],
                    proto = list(d = "", m = "", y = ""))
    out[ok_alpha] <- as.Date(sprintf("%s-%02d-%s", p$y,
                                     match(p$m, months), p$d))
  }
  if (any(ok_slash)) {
    p <- strcapture("([0-9]{2})/([0-9]{2})/([0-9]{4})", x[ok_slash],
                    proto = list(d = "", m = "", y = ""))
    out[ok_slash] <- as.Date(sprintf("%s-%s-%s", p$y, p$m, p$d))
  }
  out
}

rba_table <- function(code) {
  path <- cache_get(paste0("https://www.rba.gov.au/statistics/tables/csv/",
                           code, "-data.csv"))
  if (is.null(path)) return(NULL)
  raw <- readBin(path, "raw", file.size(path))
  text <- rawToChar(raw[raw != as.raw(0)])
  lines <- strsplit(text, "\n")[[1]]
  id_line <- grep("^Series ID,", lines)[1]
  if (is.na(id_line)) return(NULL)
  ids_row <- read.csv(textConnection(lines[id_line]), header = FALSE,
                      check.names = FALSE, na.strings = "")[1, ]
  body <- read.csv(textConnection(text), skip = id_line, header = FALSE,
                   check.names = FALSE,
                   na.strings = c("", "NA"), colClasses = "character",
                   fill = TRUE,
                   col.names = paste0("V", seq_along(ids_row)))
  body <- body[grepl("^[0-9]{2}[-/]", trimws(body[[1]])), ]
  if (nrow(body) == 0) return(NULL)
  dates <- parse_rba_date(trimws(body[[1]]))
  # Iterate by explicit column position: purrr's imap would hand the column
  # NAME to j on a named frame and break the series-id lookup.
  out <- vector("list", ncol(body) - 1)
  for (j in seq_len(ncol(body) - 1)) {
    sid <- as.character(ids_row[[j + 1]])
    if (is.na(sid) || !nzchar(sid)) next
    out[[j]] <- tibble(series_id = sid, frequency = "Month",
                       date = dates,
                       value = suppressWarnings(as.numeric(trimws(body[[j + 1]]))))
  }
  bind_rows(out) %>% filter(is.finite(date), is.finite(value))
}

yahoo_aord <- function() {
  path <- file.path("data-raw/downloads", "yahoo_aord.json")
  url <- paste0("https://query1.finance.yahoo.com/v8/finance/chart/%5EAORD",
               "?range=10y&interval=1d")
  if (refresh_download_cache || !file.exists(path)) {
    download_cache_file(url, path)
  }
  if (!file.exists(path)) return(NULL)
  raw <- readBin(path, "raw", file.size(path))
  chart <- jsonlite::fromJSON(rawToChar(raw[raw != as.raw(0)]),
                              simplifyVector = TRUE)$chart$result
  tibble(
    series_id = "YAHOO.AORD",
    description = "S&P/ASX All Ordinaries index, daily close",
    frequency = "Daily",
    date = as.Date(as.POSIXct(chart$timestamp[[1]],
                              origin = "1970-01-01", tz = "UTC")),
    value = as.numeric(chart$indicators$quote[[1]]$close[[1]])
  ) %>%
    filter(is.finite(value))
}

# ABS 5232.0 Table 1: finance stocks used to reconstruct the old-definition
# private non-financial corporations loans, bonds and equity aggregates.
finance_wealth_table <- function() {
  abs_table(paste0(
    "https://www.abs.gov.au/statistics/economy/national-accounts/",
    "australian-national-accounts-finance-and-wealth/latest-release/",
    "5232001.xlsx"
  ))
}

# ABS Total Value of Dwellings Table 2: median prices and transfer counts used
# for the transfer-weighted established/attached dwelling price measure.
dwelling_transfers_table <- function() {
  abs_table(paste0(
    "https://www.abs.gov.au/statistics/economy/price-indexes-and-inflation/",
    "total-value-dwellings/latest-release/643202.xlsx"
  ))
}

# ---- open-variable source tables ------------------------------------------------
# These tables close the variables the bootstrap workbook left frozen at
# 2024Q4. Each handler stores raw observations only; every transformation
# lives in R/prepare_model_data.R.

# ABS data-cube time-series workbook that spans several Data sheets
# (e.g. 6291.0.55.001 Table 11). Same cell layout as abs_table(), read
# across all Data1..DataN sheets and combined by series id.
abs_cube <- function(url, filename = basename(url)) {
  path <- cache_get(url, filename)
  if (is.null(path)) return(NULL)
  sheets <- grep("^Data", getSheetNames(path), value = TRUE)
  suppressWarnings({
    rows <- purrr::map_dfr(sheets, function(sheet) {
      # As in abs_table(), preserve worksheet row numbers so the final
      # (newest) observation is included.
      n_rows <- nrow(read.xlsx(
        path, sheet = sheet, colNames = FALSE,
        skipEmptyRows = FALSE, skipEmptyCols = FALSE
      ))
      header <- read.xlsx(path, sheet = sheet, colNames = FALSE,
                          rows = seq_len(min(12, n_rows)))
      id_row <- which(apply(header, 1, function(r)
        any(grepl("Series ID", r, fixed = TRUE))))[1]
      if (is.na(id_row)) return(NULL)
      ids <- as.character(unlist(header[id_row, ]))
      descs <- as.character(unlist(header[1, ]))
      body <- read.xlsx(path, sheet = sheet, colNames = FALSE,
                        rows = (id_row + 1):n_rows, detectDates = FALSE)
      dates_raw <- body[[1]]
      dates <- if (inherits(dates_raw, c("Date", "POSIXct"))) {
        as.Date(dates_raw)
      } else {
        as.Date(as.numeric(dates_raw), origin = "1899-12-30")
      }
      purrr::map_dfr(which(!is.na(ids) & nzchar(ids))[-1], function(j) {
        tibble(series_id = ids[j], description = descs[j],
               frequency = "Quarter", date = dates,
               value = suppressWarnings(as.numeric(body[[j]])))
      }) %>% filter(is.finite(value))
    })
  })
  rows
}

# ABS 6291.0.55.001 Table 11: employed persons AND hours actually worked by
# industry division (original), quarterly - the LavhMkt inputs.
lm_industry_hours <- function() {
  abs_cube(paste0(abs_detailed_url, "6291011.xlsx"), "6291011.xlsx")
}

# ABS 6291.0.55.001 Table 04: employed persons by industry division
# (trend/SA/original), quarterly - cross-check for the LavhMkt denominator.
lm_industry_employed <- function() {
  abs_cube(paste0(abs_detailed_url, "6291004.xlsx"), "6291004.xlsx")
}

# ABS 6224.0.55.001 Table H.1: experimental household estimates, long format
# (Month | State | Jobless status | Household type | '000). The Australia /
# All households / Total households row is the Lhh continuation.
households_experimental <- function() {
  url <- paste0("https://www.abs.gov.au/statistics/labour/",
                "employment-and-unemployment/",
                "labour-force-status-families-australia/latest-release/",
                "62240_TableH1.xlsx")
  path <- cache_get(url, "62240_TableH1.xlsx")
  if (is.null(path)) return(NULL)
  sheet <- grep("^Data", getSheetNames(path), value = TRUE)[1]
  d <- readxl::read_excel(path, sheet = sheet, col_names = FALSE)
  names(d) <- paste0("c", seq_len(ncol(d)))
  d %>%
    transmute(
      serial = suppressWarnings(as.numeric(c1)),
      state = as.character(c2),
      jobless = as.character(c3),
      htype = as.character(c4),
      value = suppressWarnings(as.numeric(c5))
    ) %>%
    filter(state == "Australia", jobless == "All households",
           htype == "Total households", is.finite(serial), is.finite(value)) %>%
    transmute(series_id = "ABS.62240.H1.TOTALHH",
              description = "Households, Australia (experimental estimates)",
              frequency = "Month",
              date = as.Date(serial, origin = "1899-12-30"),
              value)
}

# ABS Government Finance Statistics (quarterly, cat. 5519.0.2). Extracts the
# raw fiscal anchor: all-levels-of-government general-government net lending
# (quarterly $m) from Table 15 (the key-measures table, which carries the
# longer history; the Table 1 operating statement holds only recent
# quarters). Annual net debt is not carried far enough in this release to
# anchor GovDebt, which is instead extended by the model's own accumulation
# identity in R/prepare_model_data.R.
gfs_quarterly <- function() {
  url <- paste0("https://www.abs.gov.au/statistics/economy/",
                "government-finance-statistics/",
                "government-finance-statistics-quarterly/latest-release/",
                "gfs_jun2026.xlsx")
  path <- cache_get(url, "gfs_jun2026.xlsx")
  if (is.null(path)) return(NULL)

  d <- readxl::read_excel(path, sheet = "Table 15", col_names = FALSE)
  periods <- as.character(unlist(d[6, -1]))
  body <- d[-(1:6), ]
  labels <- as.character(unlist(body[, 1]))
  m <- suppressWarnings(as.matrix(body[, -1]))
  storage.mode(m) <- "numeric"
  nl <- which(trimws(labels) == "Net Lending (+)/Borrowing (-)")[1]
  if (is.na(nl)) return(NULL)
  tibble(
    series_id = "ABS.GFS.ALLGG.NETLENDING",
    description = paste("GFS net lending(+)/borrowing(-), all levels of",
                        "government, general government sector, quarterly $m"),
    frequency = "Quarter",
    date = as.Date(rep(NA, length(periods))),
    value = as.numeric(m[nl, ])
  ) %>%
    mutate(date = as.Date(periods_to_dates(periods))) %>%
    filter(is.finite(date), is.finite(value))
}

# ABS GFS period labels ("Jun Qtr 2026", "Sep Qtr 2023") to quarter dates.
periods_to_dates <- function(periods) {
  p <- trimws(periods)
  ok <- grepl("^[A-Za-z]{3} Qtr [0-9]{4}$", p)
  out <- rep(as.Date(NA), length(p))
  if (any(ok)) {
    parts <- strcapture("([A-Za-z]{3}) Qtr ([0-9]{4})", p[ok],
                        proto = list(m = "", y = ""))
    out[ok] <- as.Date(sprintf("%s-%02d-01", parts$y,
                               match(parts$m, month.abb)))
  }
  out
}

# ABS annual capital-stock tables: sector table (5204057) and industry table
# (5204058) carry the K benchmarks and the KdepRate formula inputs (net
# stock and consumption of fixed capital).
capital_stock_tables <- function() {
  base <- paste0("https://www.abs.gov.au/statistics/economy/",
                 "national-accounts/australian-system-of-national-accounts/",
                 "latest-release/")
  purrr::map_dfr(list(
    list(file = "5204057_capital_stock_by_sector.xlsx", sheet = "Data1"),
    list(file = "fresh_5204058_capital_stock_by_industry.xlsx",
         sheet = "Data1")
  ), function(spec) {
    path <- cache_get(paste0(base, spec$file), spec$file)
    if (is.null(path)) return(NULL)
    d <- readxl::read_excel(path, sheet = spec$sheet, col_names = FALSE)
    n_hdr <- 10
    descs <- as.character(unlist(d[1, ]))
    ids <- as.character(unlist(d[10, ]))
    dates <- suppressWarnings(
      as.Date(as.numeric(d[[1]][-(1:n_hdr)]), origin = "1899-12-30"))
    purrr::map_dfr(which(grepl("^A[0-9]{7,8}[A-Z]$", trimws(coalesce(ids, "")))),
                   function(j) {
      tibble(series_id = trimws(ids[j]),
             description = trimws(coalesce(descs[j], "")),
             frequency = "Annual",
             date = dates,
             value = suppressWarnings(as.numeric(unlist(d[[j]][-(1:n_hdr)]))))
    }) %>% filter(is.finite(date), is.finite(value))
  })
}

# ---- run ---------------------------------------------------------------------

variables <- read_variable_catalog()
series_ids <- variables$source %>%
  str_extract_all(abs_id_pattern) %>%
  unlist() %>%
  unique()
abs_urls <- map_chr(series_ids, abs_series_url) %>%
  keep(~ !is.na(.x)) %>%
  unique()
cat("ABS tables:", length(abs_urls), "\n")

raw_abs <- map(abs_urls, possibly(abs_table, NULL)) %>%
  compact() %>% bind_rows()
raw_rba <- c("f1.1", "f2.1", "f5", "f7", "f11") %>%
  map(rba_table) %>% compact() %>% bind_rows()
raw_yahoo <- yahoo_aord()
raw_finance <- finance_wealth_table()
raw_dwellings <- dwelling_transfers_table()
raw_lm_hours <- lm_industry_hours()
raw_lm_employed <- lm_industry_employed()
raw_households <- households_experimental()
raw_gfs <- gfs_quarterly()
raw_capital <- capital_stock_tables()

raw <- bind_rows(raw_capital, raw_gfs, raw_households, raw_finance,
                 raw_dwellings, raw_lm_hours,
                 raw_lm_employed, raw_rba, raw_yahoo, raw_abs) %>%
  # Some special-purpose cubes are also reached through the generic ABS
  # directory. Prefer the explicitly parsed current cube above and keep one
  # observation per published series/date.
  distinct(series_id, date, .keep_all = TRUE) %>%
  arrange(series_id, date)
attr(raw, "downloaded_at") <- Sys.time()
saveRDS(raw, "data/raw_series.rds")
cat("Raw series saved: data/raw_series.rds -",
    n_distinct(raw$series_id), "series,", nrow(raw), "observations\n")

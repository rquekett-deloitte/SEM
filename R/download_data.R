# Downloads the raw data. Downloads only - no transformation, no merging.
#
# Fetches the tables listed in the workbook's Variables sheet (ABS series via
# the Time Series Directory, RBA statistical CSVs) plus the special tables
# (Yahoo All Ordinaries, ABS Finance & Wealth, Total Value of Dwellings) and
# writes every series they contain to data/raw_series.rds, keyed by its
# published series id with description and frequency metadata. Transformation
# into model data happens in one place: R/transform_data.R.
#
# Run: Rscript R/update_data.R

required_packages <- c("jsonlite", "openxlsx", "tidyverse")
missing <- required_packages[!vapply(required_packages, requireNamespace,
                                     logical(1), quietly = TRUE)]
if (length(missing)) stop("Install first: ", paste(missing, collapse = ", "))

suppressPackageStartupMessages({
  library(openxlsx)
  library(tidyverse)
})

options(timeout = 300)
dir.create("data-raw/downloads", showWarnings = FALSE, recursive = TRUE)

abs_id_pattern <- "A[0-9]{7,8}[A-Z]"

# ---- fetchers ----------------------------------------------------------------

cache_get <- function(url, filename = basename(url)) {
  path <- file.path("data-raw/downloads", filename)
  if (!file.exists(path)) {
    tryCatch(download.file(url, path, quiet = TRUE, mode = "wb"),
             error = function(e) NULL)
  }
  if (file.exists(path)) path
}

# An ABS time series table: Data sheet parsed to (series_id, date, value)
# with description and frequency metadata.
abs_table <- function(url) {
  path <- cache_get(url)
  if (is.null(path)) return(NULL)
  sheet <- grep("^Data", getSheetNames(path), value = TRUE)[1]
  n_rows <- nrow(read.xlsx(path, sheet = sheet, colNames = FALSE, cols = 1))
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
  xml <- paste(readLines(path, warn = FALSE), collapse = "\n")
  frequency <- regmatches(xml, regexec("<Frequency>(.*?)</Frequency>", xml))
  frequency <- if (length(frequency[[1]])) frequency[[1]][2] else NA
  map_dfr(which(!is.na(ids) & nzchar(ids))[-1], function(j) {
    tibble(series_id = ids[j], description = descs[j], frequency = frequency,
           date = dates, value = as.numeric(body[[j]]))
  }) %>%
    filter(is.finite(value))
}

abs_series_url <- function(series_id) {
  path <- file.path("data-raw/downloads", paste0("tss_", series_id, ".xml"))
  url <- paste0("https://www.abs.gov.au/servlet/TSSearchServlet?sid=",
               series_id)
  if (!file.exists(path)) {
    tryCatch(download.file(url, path, quiet = TRUE, mode = "wb"),
             error = function(e) NULL)
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
  lines <- lines[nzchar(trimws(lines))]
  id_line <- grep("^Series ID,", lines)[1]
  if (is.na(id_line)) return(NULL)
  ids_row <- read.csv(text = lines[id_line], header = FALSE,
                      check.names = FALSE, na.strings = "")[1, ]
  body <- read.csv(text = text, skip = id_line, header = FALSE,
                   check.names = FALSE,
                   na.strings = c("", "NA"), colClasses = "character",
                   fill = TRUE,
                   col.names = paste0("V", seq_along(ids_row)))
  body <- body[grepl("^[0-9]{2}[-/]", trimws(body[[1]])), ]
  dates <- parse_rba_date(trimws(body[[1]]))
  imap_dfr(body[, -1, drop = FALSE], function(values, j) {
    if (j >= length(ids_row) || is.na(ids_row[j + 1]) ||
        !nzchar(ids_row[j + 1])) return(NULL)
    tibble(series_id = ids_row[j + 1], frequency = "Month",
           date = dates, value = as.numeric(trimws(values)))
  }) %>%
    filter(is.finite(date), is.finite(value))
}

yahoo_aord <- function() {
  path <- file.path("data-raw/downloads", "yahoo_aord.json")
  url <- paste0("https://query1.finance.yahoo.com/v8/finance/chart/%5EAORD",
               "?range=10y&interval=1d")
  if (!file.exists(path)) {
    tryCatch({
      download.file(url, path, quiet = TRUE, mode = "wb")
    }, error = function(e) NULL)
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

# ---- run ---------------------------------------------------------------------

variables <- read.xlsx("data-raw/Data.xlsx", sheet = "Variables")
series_ids <- variables$Source %>%
  str_extract_all(abs_id_pattern) %>%
  unlist() %>%
  unique()
abs_urls <- map_chr(series_ids, abs_series_url) %>%
  keep(~ !is.na(.x)) %>%
  unique()
cat("ABS tables:", length(abs_urls), "\n")

raw_abs <- map(abs_urls, abs_table) %>% compact() %>% bind_rows()
raw_rba <- c("f1.1", "f2.1", "f5", "f11") %>%
  map(rba_table) %>% compact() %>% bind_rows()
raw_yahoo <- yahoo_aord()

raw <- bind_rows(raw_abs, raw_rba, raw_yahoo) %>%
  arrange(series_id, date)
attr(raw, "downloaded_at") <- Sys.time()
saveRDS(raw, "data/raw_series.rds")
cat("Raw series saved: data/raw_series.rds -",
    n_distinct(raw$series_id), "series,", nrow(raw), "observations\n")
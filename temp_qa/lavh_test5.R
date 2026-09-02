# Reconstruct LavhMkt from 6291.0.55.001 Table 11 across Data1..Data5.
# Market sector = all industries except public admin, education, health.
suppressMessages(library(readxl))
suppressMessages(library(tidyverse))

path <- "data-raw/downloads/6291011.xlsx"
sheets <- grep("^Data", excel_sheets(path), value = TRUE)

read_block <- function(sh) {
  d <- read_excel(path, sheet = sh, col_names = FALSE)
  n_hdr <- 10
  descs <- trimws(coalesce(as.character(unlist(d[1, ])), ""))
  stype <- trimws(coalesce(as.character(unlist(d[3, ])), ""))
  sid   <- trimws(coalesce(as.character(unlist(d[10, ])), ""))
  dates <- suppressWarnings(as.Date(as.numeric(d[[1]][-(1:n_hdr)]),
                                    origin = "1899-12-30"))
  keep <- which(grepl("^A[0-9]{7,8}[A-Z]$", sid))
  map_dfr(keep, function(j) {
    v <- suppressWarnings(as.numeric(unlist(d[[j]][-(1:n_hdr)])))
    tibble(sid = sid[j], desc = descs[j], type = stype[j], date = dates,
           value = v)
  })
}

all_series <- map_dfr(sheets, read_block) %>% filter(is.finite(value))

industries <- c(
  "Agriculture, Forestry and Fishing ;", "Mining ;", "Manufacturing ;",
  "Electricity, Gas, Water and Waste Services ;", "Construction ;",
  "Wholesale Trade ;", "Retail Trade ;", "Accommodation and Food Services ;",
  "Transport, Postal and Warehousing ;", "Information Media and Telecommunications ;",
  "Financial and Insurance Services ;", "Rental, Hiring and Real Estate Services ;",
  "Professional, Scientific and Technical Services ;",
  "Administrative and Support Services ;", "Public Administration and Safety ;",
  "Education and Training ;", "Health Care and Social Assistance ;",
  "Arts and Recreation Services ;", "Other Services ;")
nonmarket <- c("Public Administration and Safety ;", "Education and Training ;",
               "Health Care and Social Assistance ;")
market <- setdiff(industries, nonmarket)

grab <- function(desc, type) {
  all_series %>%
    filter(desc == !!desc, type == !!type) %>%
    select(date, value)
}

for (type in unique(all_series$type)) {
  hrs <- map(market, function(ind)
    grab(paste0(ind, "  Worked 1 hour or more ;  Number of hours actually worked in all jobs ;"), type)) %>%
    reduce(full_join, by = "date") %>%
    mutate(value = rowSums(across(where(is.numeric)), na.rm = TRUE)) %>%
    select(date, value)
  emp <- map(market, function(ind)
    grab(paste0(ind, "  Worked 1 hour or more ;  Employed total ;"), type)) %>%
    reduce(full_join, by = "date") %>%
    mutate(value = rowSums(across(where(is.numeric)), na.rm = TRUE)) %>%
    select(date, value)
  lavh <- inner_join(hrs, emp, by = "date", suffix = c("_h", "_e")) %>%
    mutate(quarter = as.Date(sprintf("%d-%02d-01", lubridate::year(date),
                                     3 * ((lubridate::month(date) + 2) %/% 3)))) %>%
    group_by(quarter) %>%
    summarise(value = mean(value_h / value_e), .groups = "drop")

  seed <- read_excel("data-raw/Data.xlsx", sheet = "Data") %>%
    transmute(quarter = as.Date(date), LavhMkt = as.numeric(LavhMkt))
  j <- inner_join(lavh, seed, by = "quarter") %>% filter(is.finite(LavhMkt))
  if (nrow(j) < 8) { cat("\n", type, ": overlap", nrow(j), "- skip\n"); next }
  r <- j$value / j$LavhMkt
  k <- median(r)
  cat(sprintf("\n%s: overlap %d quarters (%s to %s)\n", type, nrow(j),
              format(min(j$quarter)), format(max(j$quarter))))
  cat(sprintf("  ratio new/seed: median %.4f  range %.4f-%.4f\n", k, min(r), max(r)))
  cat(sprintf("  scale-adjusted median abs pct diff: %.3f%%\n",
              median(abs(100 * (j$value / k / j$LavhMkt - 1)))))
  t3 <- tail(j, 3)
  cat("  last 3:", paste(sprintf("%s new=%.2f seed=%.2f", format(t3$quarter),
                                 t3$value / k, t3$LavhMkt), collapse = " | "), "\n")
}

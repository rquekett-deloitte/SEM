# Reconstruct LavhMkt from 6291.0.55.001 Table 11 (quarterly, by industry):
# market sector = all industries except public admin, education, health.
library(readxl)
library(tidyverse)

path <- "data-raw/downloads/6291011.xlsx"
d <- read_excel(path, sheet = "Data1", col_names = FALSE)
n_hdr <- 10
descs <- as.character(unlist(d[1, ]))
hdr_txt <- apply(as.data.frame(d[2:n_hdr, ]), 2, as.character)
find_row <- function(key) {
  which(apply(hdr_txt, 1, function(r)
    any(trimws(r) == key, na.rm = TRUE)))[1] + 1
}
stype <- as.character(unlist(d[find_row("Series Type"), ]))
sid <- as.character(unlist(d[find_row("Series ID"), ]))
body_dates_raw <- d[[1]][-(1:n_hdr)]
dates <- if (inherits(body_dates_raw, c("Date", "POSIXct"))) {
  as.Date(body_dates_raw)
} else as.Date(as.numeric(body_dates_raw), origin = "1899-12-30")

cols <- tibble(desc = trimws(coalesce(descs, "")),
               type = trimws(coalesce(stype, "")),
               sid = trimws(coalesce(sid, "")),
               col = seq_along(descs)) %>%
  filter(sid != "", grepl("^A[0-9]{7,8}[A-Z]$", sid))

colnum <- function(desc, type) {
  hit <- cols %>% filter(desc == !!desc, type == !!type)
  if (nrow(hit) != 1) NA_integer_ else hit$col
}
values <- function(cn) {
  if (is.na(cn)) return(rep(NA_real_, length(dates)))
  suppressWarnings(as.numeric(unlist(d[cn][[1]][-(1:n_hdr)])))
}

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

seed <- readxl::read_excel("data-raw/Data.xlsx", sheet = "Data") %>%
  transmute(date = as.Date(date), LavhMkt = as.numeric(LavhMkt))

for (type in c("Original")) {
  hrs <- Reduce(`+`, lapply(market, function(ind)
    values(colnum(paste0(ind, "  Number of hours actually worked in all jobs ;"), type))))
  emp <- Reduce(`+`, lapply(market, function(ind)
    values(colnum(paste0(ind, "  Employed total ;"), type))))
  lavh <- tibble(date = dates, value = hrs / emp) %>% filter(is.finite(value))
  j <- inner_join(lavh, seed, by = "date")
  r <- j$value / j$LavhMkt
  cat(sprintf("\n%s: overlap %d quarters (%s to %s)\n", type, nrow(j),
              format(min(j$date)), format(max(j$date))))
  cat(sprintf("  ratio new/seed: median %.4f  range %.4f-%.4f\n",
              median(r), min(r), max(r)))
  k <- median(r)
  cat(sprintf("  scale-adjusted median abs pct diff: %.3f%%\n",
              median(abs(100 * (j$value / k / j$LavhMkt - 1)))))
  t3 <- tail(j, 3)
  cat("  last 3:", paste(sprintf("%s new=%.2f seed=%.2f", format(t3$date),
                                 t3$value / k, t3$LavhMkt), collapse = " | "), "\n")
}

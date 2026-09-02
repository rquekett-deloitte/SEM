# LavhMkt: numerator = Table 11 original market hours; test denominators from
# Table 04 (Trend / Seasonally adjusted / Original market employment) vs
# Table 11's own employed total. Look for the variant with a tight ratio.
suppressMessages(library(readxl))
suppressMessages(library(tidyverse))

read_block <- function(path, sh, desc_row = 1, type_row = 3, sid_row = 10) {
  d <- read_excel(path, sheet = sh, col_names = FALSE)
  n_hdr <- 10
  descs <- trimws(coalesce(as.character(unlist(d[desc_row, ])), ""))
  stype <- trimws(coalesce(as.character(unlist(d[type_row, ])), ""))
  sid   <- trimws(coalesce(as.character(unlist(d[sid_row, ])), ""))
  dates <- suppressWarnings(as.Date(as.numeric(d[[1]][-(1:n_hdr)]),
                                    origin = "1899-12-30"))
  keep <- which(grepl("^A[0-9]{7,8}[A-Z]$", sid))
  map_dfr(keep, function(j) {
    v <- suppressWarnings(as.numeric(unlist(d[[j]][-(1:n_hdr)])))
    tibble(sid = sid[j], desc = descs[j], type = stype[j], date = dates, value = v)
  })
}

nonmarket <- c("Public Administration and Safety ;", "Education and Training ;",
               "Health Care and Social Assistance ;")
industries <- c(
  "Agriculture, Forestry and Fishing ;", "Mining ;", "Manufacturing ;",
  "Electricity, Gas, Water and Waste Services ;", "Construction ;",
  "Wholesale Trade ;", "Retail Trade ;", "Accommodation and Food Services ;",
  "Transport, Postal and Warehousing ;", "Information Media and Telecommunications ;",
  "Financial and Insurance Services ;", "Rental, Hiring and Real Estate Services ;",
  "Professional, Scientific and Technical Services ;",
  "Administrative and Support Services ;", "Arts and Recreation Services ;",
  "Other Services ;")
market <- industries

agg <- function(series, type, item) {
  parts <- map(market, function(ind)
    series %>% filter(type == !!type, desc == paste0(ind, "  ", item)) %>%
      select(date, value))
  reduce(parts, full_join, by = "date") %>%
    mutate(value = rowSums(across(where(is.numeric)), na.rm = TRUE)) %>%
    select(date, value)
}

p11 <- "data-raw/downloads/6291011.xlsx"
s11 <- map_dfr(grep("^Data", excel_sheets(p11), value = TRUE),
               function(sh) read_block(p11, sh))
p04 <- "data-raw/downloads/6291004.xlsx"
s04 <- read_block(p04, "Data1")

hrs <- agg(s11, "Original", "Number of hours actually worked in all jobs ;")

q <- function(df) df %>%
  mutate(quarter = as.Date(sprintf("%d-%02d-01", lubridate::year(date),
                                   3 * ((lubridate::month(date) + 2) %/% 3)))) %>%
  group_by(quarter) %>% summarise(value = mean(value), .groups = "drop")

seed <- read_excel("data-raw/Data.xlsx", sheet = "Data") %>%
  transmute(quarter = as.Date(date), LavhMkt = as.numeric(LavhMkt))

test <- function(emp, label) {
  lavh <- inner_join(q(hrs), q(emp), by = "quarter", suffix = c("_h", "_e")) %>%
    mutate(value = value_h / value_e) %>% select(quarter, value)
  j <- inner_join(lavh, seed, by = "quarter") %>% filter(is.finite(LavhMkt))
  r <- j$value / j$LavhMkt; k <- median(r)
  cat(sprintf("%-34s overlap %3d  scale %.4f  ratio range %.4f-%.4f  med abs diff %.3f%%\n",
              label, nrow(j), 1 / k, min(r), max(r),
              median(abs(100 * (j$value / k / j$LavhMkt - 1)))))
}
test(agg(s11, "Original", "Employed total ;"), "T11 emp (original)")
for (ty in c("Trend", "Seasonally Adjusted", "Original"))
  test(agg(s04, ty, "Employed total ;"), paste("T04 emp", ty))

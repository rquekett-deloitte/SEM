# KdepRate = (non-financial corporations COFC less mining) /
#            (business stock less mining stock), annual June data.
# Validate against the seed's KdepRate at June quarters.
suppressMessages({library(readxl); library(tidyverse)})

read_cube <- function(path) {
  sheets <- grep("^Data", excel_sheets(path), value = TRUE)
  map_dfr(sheets, function(sh) {
    d <- read_excel(path, sheet = sh, col_names = FALSE)
    descs <- trimws(coalesce(as.character(unlist(d[1, ])), ""))
    sid <- trimws(coalesce(as.character(unlist(d[10, ])), ""))
    dates <- suppressWarnings(as.Date(as.numeric(d[[1]][-(1:10)]),
                                      origin = "1899-12-30"))
    keep <- which(grepl("^A[0-9]{7,8}[A-Z]$", sid))
    map_dfr(keep, function(j) {
      v <- suppressWarnings(as.numeric(unlist(d[[j]][-(1:10)])))
      tibble(desc = descs[j], date = dates, value = v)
    })
  }) %>% filter(is.finite(value))
}

s57 <- read_cube("data-raw/downloads/5204057_capital_stock_by_sector.xlsx")
s58 <- read_cube("data-raw/downloads/fresh_5204058_capital_stock_by_industry.xlsx")

pick <- function(s, desc) s %>% filter(desc == !!desc) %>% select(date, value)

cofc_nfc <- pick(s57, "Non-financial corporations ;  Consumption of fixed capital: Current prices ;")
cofc_min <- pick(s58, "Mining ;  Consumption of fixed capital: Current prices ;")
stk_nfc_cp <- pick(s57, "Non-financial corporations ;  End-year net capital stock: Current prices ;")
stk_nfc_cv <- pick(s57, "Non-financial corporations ;  End-year net capital stock: Chain volume measures ;")
stk_min_cp <- pick(s58, "Mining ;  Net capital stock: Current prices ;")
stk_min_cv <- pick(s58, "Mining ;  Net capital stock: Chain volume measures ;")

seed <- read_excel("data-raw/Data.xlsx", sheet = "Data") %>%
  transmute(date = as.Date(date), KdepRate = as.numeric(KdepRate))
jun <- seed %>% filter(is.finite(KdepRate), month(date) == 6)

for (basis in c("current", "chain")) {
  stk_biz <- if (basis == "current") stk_nfc_cp else stk_nfc_cv
  stk_m <- if (basis == "current") stk_min_cp else stk_min_cv
  m <- coape <- NULL
  num <- inner_join(cofc_nfc, cofc_min, by = "date", suffix = c("_n", "_m")) %>%
    mutate(num = value_n - value_m) %>% select(date, num)
  den <- inner_join(stk_biz, stk_m, by = "date", suffix = c("_b", "_m")) %>%
    mutate(den = value_b - value_m) %>% select(date, den)
  kd <- inner_join(num, den, by = "date") %>%
    mutate(kdep = num / den) %>%
    inner_join(jun, by = "date") %>% filter(is.finite(KdepRate))
  j <- tail(kd, 22)
  cat(sprintf("\n%s-price denominator: overlap %d years (%s-%s)\n", basis,
              nrow(kd), format(min(kd$date)), format(max(kd$date))))
  cat(sprintf("  ratio formula/seed: median %.4f  range %.4f-%.4f\n",
              median(j$kdep / j$KdepRate), min(j$kdep / j$KdepRate),
              max(j$kdep / j$KdepRate)))
  cat(sprintf("  median abs pct diff: %.2f%%\n",
              median(abs(100 * (j$kdep / j$KdepRate - 1)))))
  cat("  recent:", paste(sprintf("%s %.4f/%.4f", format(tail(j$date, 6)),
                                 tail(j$kdep, 6), tail(j$KdepRate, 6)),
                         collapse = " | "), "\n")
}

# Compute GFS net debt from T13 (Commonwealth GG) + T14 (Total State GG)
# balance-sheet components and compare to the workbook GovDebt benchmarks.
library(readxl)
library(tidyverse)

path <- "data-raw/downloads/gfs_jun2026.xlsx"

net_debt_series <- function(sheet) {
  d <- read_excel(path, sheet = sheet, col_names = FALSE)
  periods <- as.character(unlist(d[6, -1]))
  body <- d[-(1:6), ]
  labels <- as.character(unlist(body[, 1]))
  m <- suppressWarnings(as.matrix(body[, -1]))
  storage.mode(m) <- "numeric"
  if (ncol(m) != length(periods)) stop("shape mismatch in ", sheet)

  split_at <- which(trimws(labels) == "less")
  if (length(split_at) < 1) stop("no assets/liabilities divider in ", sheet)
  a_idx <- seq_len(split_at[1] - 1)
  l_idx <- split_at[1]:length(labels)

  block_sum <- function(idx, wanted) {
    hit <- idx[trimws(labels[idx]) %in% wanted]
    if (length(hit) == 0) return(rep(NA_real_, ncol(m)))
    colSums(m[hit, , drop = FALSE], na.rm = TRUE)
  }
  comps <- c("Currency and deposits", "Advances",
             "Other loans and placements", "Debt securities")
  assets <- block_sum(a_idx, comps)
  liabs <- block_sum(l_idx, comps)
  tibble(period = periods, net_debt = (assets - liabs) / 1000)
}

cg <- net_debt_series("Table 13")
sl <- net_debt_series("Table 14")
both <- inner_join(cg, sl, by = "period", suffix = c("_cg", "_sl")) %>%
  mutate(total = net_debt_cg + net_debt_sl) %>%
  filter(grepl("^Jun", period))
cat("Net debt ($bn), June quarters:\n")
print(as.data.frame(both), row.names = FALSE)
cat("\nWorkbook benchmarks: Jun-2023 = 661.7, Jun-2024 = 769.3\n")

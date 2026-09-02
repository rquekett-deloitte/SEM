# Extract net debt / net lending rows from the quarterly GFS tables.
library(readxl)
library(tidyverse)

path <- "data-raw/downloads/gfs_jun2026.xlsx"

grab <- function(sheet) {
  d <- read_excel(path, sheet = sheet, col_names = FALSE)
  periods <- as.character(unlist(d[6, ]))
  d <- d[-(1:6), ]
  names(d) <- paste0("c", seq_len(ncol(d)))
  d$label <- as.character(unlist(d[, 1]))
  rows <- d %>% filter(!is.na(label), nzchar(trimws(label)))
  list(rows = rows, periods = periods)
}

for (sheet in c("Table 15", "Table 13", "Table 14", "Table 1", "Table 2")) {
  g <- grab(sheet)
  t <- g$rows
  periods <- g$periods
  cat("\n=====", sheet, "=====\n")
  keep <- t %>% filter(grepl("Net debt|Net lending|Net borrowing|deficit|surplus",
                             label, ignore.case = TRUE))
  if (nrow(keep) == 0) {
    cat("(no matching rows; labels:)\n")
    print(head(t$label, 25))
  } else {
    for (i in seq_len(nrow(keep))) {
      vals <- suppressWarnings(as.numeric(unlist(keep[i, -1])))
      idx <- which(is.finite(vals))
      show <- tail(idx, 12)
      cat(sprintf("%-42s", substr(keep$label[i], 1, 42)))
      cat(paste(sprintf("%s=%s", periods[show + 1], vals[show]), collapse = " "), "\n")
    }
  }
}

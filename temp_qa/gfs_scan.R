# Scan the cached ABS GFS annual workbook for the net-debt / net-lending
# levels that match the workbook's GovDebt and GovDef history.
library(readxl)
library(tidyverse)

path <- "data-raw/downloads/gfs_jun2026.xlsx"
sheets <- excel_sheets(path)
sheets <- setdiff(sheets, c("Contents", "Explanatory Notes"))

# Targets: GovDebt seed benchmarks (June quarters, $bn) and annual GovDef sums
targets <- c(661.7, 769.3, 783.8, 846.6, 954.9)

hits <- list()
for (sh in sheets) {
  d <- read_excel(path, sheet = sh, col_names = FALSE)
  for (i in seq_len(nrow(d))) {
    rowvals <- suppressWarnings(as.numeric(unlist(d[i, ])))
    for (j in seq_along(rowvals)) {
      v <- rowvals[j]
      if (is.finite(v)) {
        for (t in targets) {
          if (abs(v - t) < 0.15) {
            label <- paste0(sh, " r", i, " c", j)
            hits[[label]] <- c(sheet = sh, row = i, col = j,
                               value = v, target = t)
          }
        }
      }
    }
  }
}
if (length(hits)) {
  h <- do.call(rbind, lapply(hits, function(x)
    data.frame(sheet = x[["sheet"]], row = as.integer(x[["row"]]),
               col = as.integer(x[["col"]]), value = as.numeric(x[["value"]]),
               target = as.numeric(x[["target"]]))))
  h <- h[!duplicated(h[, c("sheet", "row")]), ]
  print(as_tibble(h), n = 60)
} else {
  cat("no exact matches; printing sheet inventory instead\n")
  for (sh in sheets) {
    d <- read_excel(path, sheet = sh, col_names = FALSE, n_max = 6)
    cat("\n===", sh, "===\n")
    print(as_tibble(d[, 1:min(4, ncol(d))]))
  }
}

# Rbiz continuation: 3-series solve (Small/Medium/Large outstanding totals only)
library(tidyverse)

seed <- readxl::read_excel("data-raw/Data.xlsx", sheet = "Data")
rbiz <- seed %>%
  transmute(date = as.Date(date), Rbiz = as.numeric(Rbiz) * 100) %>%
  filter(date >= as.Date("2019-10-01"), !is.na(Rbiz))

lines <- readLines("data-raw/downloads/f7-data.csv", warn = FALSE)
lines <- lines[nzchar(lines)]
sid_row <- which(startsWith(lines, "Series ID,"))
sid <- strsplit(lines[sid_row], ",")[[1]]
dat <- lines[(sid_row + 1):length(lines)]
f7 <- map_dfr(dat, function(ln) {
  parts <- strsplit(ln, ",")[[1]]
  tibble(date = as.Date(parts[1], "%d/%m/%Y"),
         !!!setNames(as.numeric(parts[-1]), sid[-1]))
})
q <- f7 %>%
  mutate(quarter = as.Date(sprintf("%d-%02d-01",
                                   lubridate::year(date),
                                   3 * ((lubridate::month(date) + 2) %/% 3)))) %>%
  group_by(quarter) %>%
  summarise(across(where(is.numeric), ~ mean(.x, na.rm = TRUE)), .groups = "drop")

cand <- c("FLRBFOSBT", "FLRBFOMBT", "FLRBFOLBT")
X <- q %>% filter(quarter %in% rbiz$date) %>% select(all_of(cand)) %>% as.matrix()
y <- rbiz$Rbiz[match(q$quarter[q$quarter %in% rbiz$date], rbiz$date)]

solve_softmax <- function(X, y) {
  sse <- function(theta) { w <- exp(theta) / sum(exp(theta)); sum((X %*% w - y)^2) }
  best <- NULL
  for (rep in 1:30) {
    fit <- optim(rnorm(ncol(X), 0, 0.5), sse, method = "BFGS")
    if (is.null(best) || fit$value < best$value) best <- fit
  }
  exp(best$par) / sum(exp(best$par))
}
w <- solve_softmax(X, y)
res <- y - as.numeric(X %*% w)
cat("3-series solve (Small/Medium/Large totals):\n")
for (i in seq_along(cand)) cat(sprintf("  %-12s %.4f\n", cand[i], w[i]))
cat(sprintf("sum(w) = %.4f  max abs residual = %.4f pp  RMSE = %.4f pp\n",
            sum(w), max(abs(res)), sqrt(mean(res^2))))
cat("\nquarterly residuals (pp):\n")
print(round(setNames(as.numeric(res), format(rbiz$date)), 3))

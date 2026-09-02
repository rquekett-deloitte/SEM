# Reverse-engineer the F7 weighting behind Rbiz's post-D8 continuation.
# Seed Rbiz 2019Q4-2024Q4 (21 quarters) should be a weighted average of
# RBA F7 outstanding business lending rates. Solve weights >= 0, sum = 1
# by softmax-parameterised least squares (no extra packages needed).

library(tidyverse)

seed <- readxl::read_excel("data-raw/Data.xlsx", sheet = "Data")
rbiz <- seed %>%
  transmute(date = as.Date(date), Rbiz = as.numeric(Rbiz) * 100) %>%  # per cent
  filter(date >= as.Date("2019-10-01"), !is.na(Rbiz))

lines <- readLines("data-raw/downloads/f7-data.csv", warn = FALSE)
lines <- lines[nzchar(lines)]
sid_row <- which(startsWith(lines, "Series ID,"))
hdr <- strsplit(lines[1], ",")[[1]]                 # Title row
sid <- strsplit(lines[sid_row], ",")[[1]]           # Series ID row
dat <- lines[(sid_row + 1):length(lines)]

f7 <- map_dfr(dat, function(ln) {
  parts <- strsplit(ln, ",")[[1]]
  tibble(date = as.Date(parts[1], "%d/%m/%Y"),
         !!!setNames(as.numeric(parts[-1]), sid[-1]))
})
cat("F7 months:", nrow(f7), "from", format(min(f7$date)), "to", format(max(f7$date)), "\n\n")

# quarterly means
q <- f7 %>%
  mutate(quarter = as.Date(sprintf("%d-%02d-01",
                                   lubridate::year(date),
                                   3 * ((lubridate::month(date) + 2) %/% 3)))) %>%
  group_by(quarter) %>%
  summarise(across(where(is.numeric), mean, na.rm = TRUE), .groups = "drop")

# candidate regressors: all OUTSTANDING series (FLRBFO*)
cand <- sid[-1][startsWith(sid[-1], "FLRBFO")]
cat("outstanding candidates:", length(cand), "\n")
for (s in cand) {
  ttl <- hdr[which(sid == s)]
  cat(sprintf("  %-12s %s\n", s, ttl))
}

X <- q %>%
  filter(quarter %in% rbiz$date) %>%
  select(all_of(cand)) %>%
  as.matrix()
y <- rbiz$Rbiz[match(q$quarter[q$quarter %in% rbiz$date], rbiz$date)]
stopifnot(nrow(X) == length(y), !anyNA(X))

solve_softmax <- function(X, y) {
  sse <- function(theta) {
    w <- exp(theta) / sum(exp(theta))
    sum((X %*% w - y)^2)
  }
  best <- NULL
  for (rep in 1:20) {
    fit <- optim(rnorm(ncol(X), 0, 0.5), sse, method = "BFGS")
    if (is.null(best) || fit$value < best$value) best <- fit
  }
  w <- exp(best$par) / sum(exp(best$par))
  list(w = w, sse = best$value)
}
sol <- solve_softmax(X, y)
fitvals <- as.numeric(X %*% sol$w)
res <- y - fitvals
cat("\n--- weighted-average fit (all", length(cand), "outstanding series) ---\n")
cat("weights:\n")
for (i in seq_along(cand)) {
  if (sol$w[i] > 0.005)
    cat(sprintf("  %-12s %.4f  %s\n", cand[i], sol$w[i], hdr[which(sid == cand[i])]))
}
cat(sprintf("sum(w) = %.4f  max abs residual = %.4f pp  RMSE = %.4f pp  mean Rbiz = %.2f\n",
            sum(sol$w), max(abs(res)), sqrt(mean(res^2)), mean(y)))

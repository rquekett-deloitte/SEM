# Solve the ShockGst value implied by the estimated Tgst equation each quarter
# (the value that zeroes the equation's residual) and compare to the seed.
library(tidyverse)

co <- read.csv("outputs/coefficients.csv")
C <- function(term) co$estimate[co$equation == "Tgst" & co$term == term]

d <- read.csv("data/sourced_data.csv", check.names = FALSE) %>%
  transmute(date = as.Date(date),
            Tgst = as.numeric(Tgst), CprNom = as.numeric(CprNom)) %>%
  filter(is.finite(Tgst), is.finite(CprNom)) %>%
  arrange(date)
seed <- readxl::read_excel("data-raw/Data.xlsx", sheet = "Data") %>%
  transmute(date = as.Date(date), ShockGst = coalesce(as.numeric(ShockGst), 0))
d <- d %>% left_join(seed, by = "date")

d <- d %>%
  mutate(
    dl_tgst   = log(Tgst) - log(lag(Tgst, 1)),
    gap       = log(lag(Tgst, 1)) - log(lag(CprNom, 1)),
    dl_cpr    = log(CprNom) - log(lag(CprNom, 1)),
    dl_cpr1   = log(lag(CprNom, 1)) - log(lag(CprNom, 2)),
    dl_cpr2   = log(lag(CprNom, 2)) - log(lag(CprNom, 3)),
    dl_cpr3   = log(lag(CprNom, 3)) - log(lag(CprNom, 4)),
    dl_cpr4   = log(lag(CprNom, 4)) - log(lag(CprNom, 5)),
    trend     = dplyr::row_number() - 1
  )

d <- d %>%
  mutate(
    base = C("c1") + C("c2") * gap - C("c2") * C("c4") * trend +
           C("c5") * dl_cpr + C("c6") * dl_cpr1 + C("c7") * dl_cpr2 +
           C("c8") * dl_cpr3 + C("c9") * dl_cpr4,
    # dl_tgst = base - c2*c3*ShockGst  =>  ShockGst = (base - dl_tgst) / (c2*c3)
    implied = (base - dl_tgst) / (C("c2") * C("c3"))
  )

x <- d %>% filter(date >= as.Date("2018-01-01"), date <= as.Date("2026-06-01"))
cat("date        implied  seed\n")
for (i in seq_len(nrow(x)))
  cat(sprintf("%s  %+7.3f  %+6.3f\n", format(x$date[i]), x$implied[i], x$ShockGst[i]))

y <- x %>% filter(date >= as.Date("2020-01-01"), date <= as.Date("2024-12-01"))
cat(sprintf("\n2020-24: corr = %.3f, mean abs diff = %.3f, seed mean = %.3f\n",
            cor(y$implied, y$ShockGst), mean(abs(y$implied - y$ShockGst)),
            mean(y$ShockGst)))

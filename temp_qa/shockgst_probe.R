# ShockGst reverse-engineering: is it the GST-collections-vs-consumption-base
# coverage wedge?  Test coverage = Tgst / (0.10 * CprNom) against the seed's
# ShockGst, 2015-2024.
library(tidyverse)

d <- read.csv("data/sourced_data.csv", check.names = FALSE) %>%
  transmute(date = as.Date(date),
            Tgst = as.numeric(Tgst), CprNom = as.numeric(CprNom)) %>%
  filter(is.finite(Tgst), is.finite(CprNom))

seed <- readxl::read_excel("data-raw/Data.xlsx", sheet = "Data") %>%
  transmute(date = as.Date(date), ShockGst = as.numeric(ShockGst))

d <- d %>% left_join(seed, by = "date") %>%
  mutate(ShockGst = coalesce(ShockGst, 0))

pre <- d %>% filter(date >= as.Date("2015-01-01"), date < as.Date("2020-01-01"))
base_cov <- mean(pre$Tgst / (0.10 * pre$CprNom))
cat(sprintf("pre-COVID mean coverage Tgst/(0.10*CprNom) = %.4f\n", base_cov))

x <- d %>% filter(date >= as.Date("2018-01-01")) %>%
  mutate(cov = Tgst / (0.10 * CprNom),
         cov_dev = cov - base_cov,
         cov_dev_pct = 100 * (cov / base_cov - 1),
         inv_cov_pct = -cov_dev_pct,
         shock = ShockGst)
cat("\nquarter | coverage | cov_dev% | -dev% | ShockGst\n")
for (i in seq_len(nrow(x))) {
  cat(sprintf("%s  %.4f   %+6.2f  %+6.2f  %+6.3f\n", format(x$date[i]),
              x$cov[i], x$cov_dev_pct[i], x$inv_cov_pct[i], x$shock[i]))
}
cat("\nscale check: ShockGst / (-cov_dev_pct) over 2020-2024:\n")
y <- x %>% filter(date >= as.Date("2020-01-01"), date <= as.Date("2024-12-01"))
print(round(y$shock / y$inv_cov_pct, 3))

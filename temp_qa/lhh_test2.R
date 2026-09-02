# Lhh: extract the experimental monthly household estimates (Table H.1),
# compare with the seed's quarterly Lhh path, and design the splice.
suppressMessages({library(readxl); library(tidyverse)})

d <- read_excel("data-raw/downloads/62240_TableH1.xlsx", sheet = "Data H.1",
                col_names = FALSE)
names(d) <- paste0("c", seq_len(ncol(d)))
hh <- d %>%
  transmute(serial = as.numeric(c1),
            state = as.character(c2),
            jobless = as.character(c3),
            htype = as.character(c4),
            value = suppressWarnings(as.numeric(c5))) %>%
  filter(state == "Australia", jobless == "All households")
cat("household types:\n")
print(table(hh$htype))

au <- hh %>%
  filter(htype == "Total households") %>%
  transmute(date = as.Date(serial, origin = "1899-12-30"), value) %>%
  filter(is.finite(date), is.finite(value))
cat("\nAll-households monthly:", nrow(au), "rows,",
    format(min(au$date)), "to", format(max(au$date)), "\n")
print(tail(au, 6), row.names = FALSE)

q <- au %>%
  mutate(quarter = as.Date(sprintf("%d-%02d-01", year(date),
                                   3 * ((month(date) + 2) %/% 3)))) %>%
  group_by(quarter) %>% summarise(value = mean(value), .groups = "drop")

seed <- read_excel("data-raw/Data.xlsx", sheet = "Data") %>%
  transmute(quarter = as.Date(date), Lhh = as.numeric(Lhh))
j <- inner_join(q, seed, by = "quarter") %>% filter(is.finite(Lhh))
cat("\noverlap:", nrow(j), "quarters:", format(min(j$quarter)),
    "to", format(max(j$quarter)), "\n")
r <- j$value * 1000 / j$Lhh
cat("ratio (new*1000)/seed: median", round(median(r), 4),
    "range", round(min(r), 4), "-", round(max(r), 4), "\n")
cat("\nquarterly comparison (selected):\n")
sel <- j %>% filter(quarter >= as.Date("2022-01-01"))
print(sel %>% mutate(value = round(value * 1000, 1), Lhh = round(Lhh, 1)),
      row.names = FALSE, n = 30)
cat("\nseed Lhh last 6:\n")
print(tail(seed %>% filter(is.finite(Lhh)), 6), row.names = FALSE)

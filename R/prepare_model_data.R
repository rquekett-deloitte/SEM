# Prepares the model's data. The single home of all data transformation.
#
# Stage 1 - source:  raw downloaded series (data/raw_series.rds, produced by
#   R/download_data.R) are aligned to model quarters, derived where needed,
#   validated against the previous history and merged into it, producing
#   data/sourced_data.rds (quarterly history) and
#   outputs/data_download_validation.csv (the sourcing map).
# Stage 2 - prepare: the sourced history becomes the estimation dataset
#   (data/model_data.rds) - deflators, trends, seasonal adjustment and the
#   deterministic terms the equations use.
#
# prepare_model_data(refresh = TRUE) runs both stages; with refresh = FALSE
# stage 1 is skipped and the existing sourced history is only re-prepared.
# The bootstrap for stage 1's merge base is data-raw/Data.xlsx (read-only;
# the workbook is no longer the model's data input). Exogenous scenario
# paths stay in data-raw/exogenous_forecast.csv.

library(tidyverse)
library(readxl)
library(seasonal)

# Quarter convention: model quarters end in March, June, September, December.
model_quarter <- function(dates) {
  month <- as.integer(format(dates, "%m"))
  year <- as.integer(format(dates, "%Y"))
  as.Date(sprintf("%d-%02d-01", year, 3 * ((month + 2) %/% 3)))
}

monthly_to_quarterly <- function(series) {
  series %>%
    mutate(quarter = model_quarter(date)) %>%
    group_by(quarter) %>%
    summarise(value = mean(value[is.finite(value)]), .groups = "drop") %>%
    transmute(date = quarter, value)
}

# ---- stage 1: raw series to sourced history -----------------------------------

abs_id_pattern <- "A[0-9]{7,8}[A-Z]"
rba_ids <- c("FIRMMBAB90", "FCMYGBAG10", "FCMYGBAGI", "FXRUSD", "FXRTWI",
             "FILRHLBVS")
adopt_series <- c("LhrsPub", "Wfor")         # rebenchmarked: replace the span
carry_trend  <- c("KMin", "KBiz", "KDwell", "KTotal")
carry_hold   <- c("TcorpRate", "KdepRate", "DumTsfTot")
exogenous_maintained <- c(
  "Fpcpi", "Fpoil", "Fpcom", "Fpagr", "FcGdp", "FcPpp",
  "Fr10yUs", "Fr10yJp", "Fr10yDe", "Fr10yUk", "IvtFar", "IntStu"
)
derive_after_merge <- list(
  KNbiz  = function(d) d$KBiz - d$KMin,
  KOther = function(d) d$KTotal - d$KBiz - d$KDwell,
  EqEarn = function(d) d$Peq / d$PeRatio
)

pct_diff <- function(new, old) {
  if_else(abs(old) > 1e-9, 100 * abs(new - old) / abs(old), NA_real_)
}

divisor_from_note <- function(note) {
  if (is.na(note)) return(NA_real_)
  match <- regmatches(note, regexec("divided by ([0-9]+)", note))[[1]]
  if (length(match) < 2) NA_real_ else as.numeric(match[2])
}

# Align one raw series to the model quarter grid. Monthly series take a
# three-month average; daily series take the quarter's last value; quarterly
# and annual series snap to their quarter. The noted divisor is applied.
to_model_quarters <- function(series) {
  value <- series$value
  if (identical(series$frequency[[1]], "Month")) {
    value <- NULL
    out <- monthly_to_quarterly(transmute(series, date, value))
  } else if (identical(series$frequency[[1]], "Daily")) {
    out <- series %>%
      mutate(quarter = model_quarter(date)) %>%
      group_by(quarter) %>%
      slice_tail(n = 1) %>%
      ungroup() %>%
      transmute(date = quarter, value)
  } else {
    out <- transmute(series, date = model_quarter(date), value)
  }
  divisor <- divisor_from_note(series$transformation[[1]])
  if (is.finite(divisor)) out <- mutate(out, value = value / divisor)
  out
}

# Variables composed of several published series, summed on common dates.
sum_series <- function(parts) {
  reduce(parts, full_join, by = "date", suffix = c("", "_y")) %>%
    mutate(value = coalesce(value, 0) + coalesce(value_y, 0)) %>%
    select(date, value)
}

# Phouse: transfer-weighted median of the Total Value of Dwellings Table 2
# median-price series (established houses and attached dwellings, capitals
# and rest-of-state).
phouse_from_raw <- function(raw) {
  medians <- raw %>%
    filter(str_detect(description, fixed("Median Price of"))) %>%
    select(date, median = value, series_id) %>%
    arrange(series_id, date)
  transfers <- raw %>%
    filter(str_detect(description, fixed("Number of"))) %>%
    select(date, trades = value, series_id) %>%
    arrange(series_id, date)
  if (nrow(medians) == 0 || nrow(transfers) == 0) return(NULL)
  inner_join(medians, transfers, by = c("series_id", "date")) %>%
    filter(is.finite(median), is.finite(trades)) %>%
    group_by(date) %>%
    summarise(value = sum(median * trades) / sum(trades), .groups = "drop") %>%
    transmute(date = model_quarter(date), value) %>%
    group_by(date) %>%
    summarise(value = mean(value), .groups = "drop")
}

# Business finance: the old-definition private non-financial corporations
# sector - other PNC plus investment funds - summed and converted to $bn.
biz_from_raw <- function(raw, instrument) {
  sectors <- c("Other private non-financial corporations",
               "Private non-financial investment funds")
  parts <- map(sectors, function(sector) {
    hit <- raw %>%
      filter(str_detect(description,
                        fixed(paste(sector, ";", instrument, ";", "Total"))),
             str_detect(description, fixed("Total (Counterparty sectors)")))
    if (nrow(hit) == 0) return(NULL)
    transmute(hit, date = model_quarter(date), value) %>%
      group_by(date) %>%
      summarise(value = mean(value), .groups = "drop")
  }) %>% compact()
  if (length(parts) < 2) return(NULL)
  sum_series(parts) %>% mutate(value = value / 1000)
}

source_history <- function(raw, variables, history) {
  frequency_of <- function(id) raw$frequency[match(id, raw$series_id)][[1]]

  one_variable <- function(row) {
    variable <- row$variable
    if (variable == "Phouse") return(phouse_from_raw(raw))
    if (variable == "Peq") {
      return(to_model_quarters(filter(raw, series_id == "YAHOO.AORD")))
    }
    if (variable %in% c("BizLns", "BizBnd", "BizEq")) {
      instrument <- switch(variable,
        BizLns = "Loans and placements borrowed from:",
        BizBnd = "Bonds, etc. held by:",
        BizEq  = "Shares and other equity held by:")
      return(biz_from_raw(raw, instrument))
    }
    ids <- row$abs_ids
    if (!length(ids)) ids <- row$rba_ids
    if (!length(ids)) return(NULL)
    parts <- map(ids, function(id) {
      series <- raw %>% filter(series_id == id) %>% list()
      series$transformation <- row$transformation
      series$frequency <- frequency_of(id)
      to_model_quarters(series)
    })
    if (length(parts) == 1) parts[[1]] else sum_series(parts)
  }

  validate <- function(variable, category, series) {
    joined <- history %>%
      select(date, current = all_of(variable)) %>%
      inner_join(series, by = "date") %>%
      filter(is.finite(current), is.finite(value))
    ratio <- suppressWarnings(median(joined$value / joined$current,
                                     na.rm = TRUE))
    scale_note <- ""
    if (is.finite(ratio) && ratio > 0 &&
        abs(log10(ratio) - round(log10(ratio))) < 0.02 &&
        round(log10(ratio)) != 0) {
      factor <- 10^-round(log10(ratio))
      series <<- mutate(series, value = value * factor)
      scale_note <- paste0("rescaled x", format(factor), "; ")
      joined <- history %>%
        select(date, current = all_of(variable)) %>%
        inner_join(series, by = "date") %>%
        filter(is.finite(current), is.finite(value))
    }
    diffs <- pct_diff(joined$value, joined$current)
    fills <- series %>%
      anti_join(filter(history, !is.na(all_of(variable))), by = "date") %>%
      filter(is.finite(value))
    median_diff <- suppressWarnings(median(diffs, na.rm = TRUE))
    tibble(
      variable = variable,
      category = category,
      status = "downloaded",
      note = paste0(scale_note, nrow(joined), "-quarter overlap"),
      n_overlap = nrow(joined),
      median_abs_pct_diff = round(median_diff, 3),
      mean_abs_pct_diff = round(mean(diffs, na.rm = TRUE), 3),
      max_abs_pct_diff = round(max(diffs, na.rm = TRUE), 3),
      worst_quarter = if (nrow(joined)) {
        format(joined$date[which.max(diffs)])
      } else "",
      verdict = case_when(
        variable %in% adopt_series ~ "current official vintage adopted",
        !is.finite(median_diff) ~ "no comparable overlap",
        median_diff < 0.5 ~ "source confirmed",
        median_diff < 2 ~ "revisions - review",
        TRUE ~ "MISMATCH - check source"
      ),
      n_new = nrow(fills),
      new_end = if (nrow(fills)) format(max(fills$date)) else ""
    )
  }

  skipped <- function(variable, category) {
    reason <- case_when(
      category == "exogenous" ~
        "exogenous by design - maintained via exogenous_forecast.csv",
      variable %in% carry_hold ~ "constant - held at its final level",
      variable %in% names(derive_after_merge) ~
        "derived - computed from its parents after the merge",
      variable == "Rbiz" ~
        "sourcing open: the D8/F7 splice matches no published RBA series",
      variable %in% c("PeRatio", "EqEarn", "LavhMkt", "PcpiExGst", "ShockGst",
                      "GovDef", "GovDebt", "Lhh", "KdepRate") ~
        "sourcing open: owner derivation required - see the source note",
      TRUE ~ "sourcing open: no documented source"
    )
    tibble(variable = variable, category = category, status = "skipped",
           note = reason, n_overlap = NA_integer_,
           median_abs_pct_diff = NA_real_, mean_abs_pct_diff = NA_real_,
           max_abs_pct_diff = NA_real_, worst_quarter = "", verdict = "n/a",
           n_new = NA_integer_, new_end = "")
  }

  series_by_variable <- list()
  results <- pmap_dfr(variables, function(variable, source, transformation,
                                           abs_ids, rba_ids, category, ...) {
    eligible <- length(abs_ids) + length(rba_ids) > 0 |
      variable %in% c("Phouse", "Peq", "BizLns", "BizBnd", "BizEq")
    if (category == "exogenous" || !eligible) {
      return(skipped(variable, category))
    }
    row <- list(variable = variable, transformation = transformation,
                abs_ids = abs_ids, rba_ids = rba_ids)
    series <- tryCatch(one_variable(row), error = function(e) NULL)
    if (is.null(series) || nrow(series) == 0) {
      out <- skipped(variable, category)
      out$status <- if (grepl("^sourcing open", out$note)) "skipped" else "failed"
      return(out)
    }
    series_by_variable[[variable]] <<- series
    validate(variable, category, series)
  })

  merge_fill <- function(column, dates, series) {
    idx <- match(series$date, dates)
    hit <- !is.na(idx) & is.finite(series$value)
    write <- hit & is.na(column[idx])
    column[idx[write]] <- series$value[write]
    column
  }
  merge_adopt <- function(column, dates, series) {
    idx <- match(series$date, dates)
    hit <- !is.na(idx) & is.finite(series$value)
    column[idx[hit]] <- series$value[hit]
    column
  }
  carry <- function(column, trend = TRUE) {
    finite <- which(is.finite(column))
    last <- finite[length(finite)]
    if (!length(finite) || last == length(column)) return(column)
    step <- if (trend && last > 1 && is.finite(column[last - 1])) {
      column[last] - column[last - 1]
    } else 0
    for (k in (last + 1):length(column)) column[k] <- column[k - 1] + step
    column
  }

  updated <- history
  new_ends <- results$new_end[results$n_new > 0 & !is.na(results$new_end)]
  if (length(new_ends)) {
    span <- seq(seq(max(updated$date), by = "quarter", length.out = 2)[2],
                max(as.Date(new_ends)), by = "quarter")
    updated <- bind_rows(updated, tibble(date = span))
  }
  all_dates <- updated$date
  for (variable in intersect(names(series_by_variable), names(updated))) {
    updated[[variable]] <- merge_fill(updated[[variable]], all_dates,
                                      series_by_variable[[variable]])
    if (variable %in% adopt_series) {
      updated[[variable]] <- merge_adopt(updated[[variable]], all_dates,
                                         series_by_variable[[variable]])
    }
  }
  for (variable in carry_trend) {
    updated[[variable]] <- carry(updated[[variable]], trend = TRUE)
  }
  for (variable in carry_hold) {
    updated[[variable]] <- carry(updated[[variable]], trend = FALSE)
  }
  for (variable in intersect(names(derive_after_merge), names(updated))) {
    updated[[variable]] <- derive_after_merge[[variable]](updated)
  }

  list(history = updated, results = results)
}

# ---- stage 2: sourced history to estimation data ------------------------------

hp_filter <- function(x, lambda = 1600) {
  ok <- which(is.finite(x))
  n <- length(ok)
  if (n < 3L) return(rep(NA_real_, length(x)))
  D <- diff(diag(n), differences = 2)
  out <- rep(NA_real_, length(x))
  out[ok] <- solve(diag(n) + lambda * crossprod(D), x[ok])
  out
}

sa_series <- function(x, dates) {
  ok <- which(!is.na(x))
  if (length(ok) < 16) return(x)
  span <- ok[1]:ok[length(ok)]
  xt <- ts(x[span],
           start = c(lubridate::year(dates[span[1]]),
                     lubridate::quarter(dates[span[1]])),
           frequency = 4)
  adj <- tryCatch(as.numeric(final(seas(xt))), error = function(e) NULL)
  if (is.null(adj) || length(adj) != length(span)) {
    warning("seasonal adjustment failed; series left unadjusted")
    return(x)
  }
  out <- rep(NA_real_, length(x))
  out[span] <- adj
  out
}

# Transforms the quarterly history into the estimation dataset. Naming
# conventions are documented in VARIABLES.md.
prepare_estimation_data <- function(data) {
  data <- data %>%
    filter(!is.na(date)) %>%
    mutate(date = as.Date(date))

  # World CPI: remove the spurious 2009 level break (an un-chain-linked
  # rebasing in the source, smeared across a year).
  fp_brk <- which(data$date >= as.Date("2009-03-01") &
                    data$date <= as.Date("2009-12-01"))
  fp_g <- c(NA, diff(log(data$Fpcpi)))
  fp_ref <- which((data$date >= as.Date("2007-03-01") &
                     data$date <= as.Date("2008-12-01")) |
                    (data$date >= as.Date("2010-03-01") &
                       data$date <= as.Date("2011-12-01")))
  fp_norm <- mean(fp_g[fp_ref], na.rm = TRUE)
  fp_exc <- sum(fp_g[fp_brk], na.rm = TRUE) - fp_norm * length(fp_brk)
  if (length(fp_brk) == 4 && fp_exc > 0.1) {
    fp_pre <- which(data$date < data$date[fp_brk[1]])
    data$Fpcpi[fp_pre] <- data$Fpcpi[fp_pre] * exp(fp_exc)
    fp_anchor <- data$Fpcpi[fp_brk[1] - 1]
    data$Fpcpi[fp_brk] <- fp_anchor * exp(fp_norm * seq_along(fp_brk))
  }

  data <- data %>%
    mutate(
      KMinDepRate   = 1 - (KMin   - lag(Imin))    / lag(KMin),
      KNbizDepRate  = 1 - (KNbiz  - lag(Inonmin)) / lag(KNbiz),
      KDwellDepRate = 1 - (KDwell - lag(Idwell))  / lag(KDwell)
    )

  data <- data %>%
    mutate(
      Ivt      = IvtFar + IvtNonfarm - lag(IvtNonfarm),
      Xmin     = Xmet + Xccb + Xomf,
      XminNom  = XmetNom + XccbNom + XomfNom,
      Xoth     = Xmex + Xmac + Xtrn + Xotm + Xonr + Xgpr,
      XothNom  = XmexNom + XmacNom + XtrnNom + XotmNom + XonrNom + XgprNom,
      Toth     = Ttot - Tpit - Tcit - Tgst - Tprl,
      Pxoth    = XothNom / Xoth,
      Ppcd     = CprNom / Cpr,
      Pgdp     = YgdpNom / Ygdp,
      Pmgs     = MtotNom / Mtot,
      Pidwell  = IdwellNom / Idwell,
      Piret    = IotcNom / Iotc,
      Pxtot    = XtotNom / Xtot,
      Pxagr    = XagrNom / Xagr,
      Pxmin    = XminNom / Xmin,
      Pgov     = CgovNom / Cgov,
      Pimin    = IminNom / Imin,
      Pinonmin = InonminNom / Inonmin,
      PconsRent    = CconsRentNom / CconsRent,
      PconsExrent  = (CprNom - CconsRentNom) / (Cpr - CconsRent),
      Lur      = Lune / Lsup,
      LempNonmkt = LempPub + LempEdu + LempHlt,
      LempMkt    = Lemp - LempNonmkt,
      LhrsNonmkt = sa_series(LhrsPub + LhrsEdu + LhrsHlt, date),
      LhrsAllSa  = sa_series(LhrsAll, date),
      Lhrs       = LhrsAllSa - LhrsNonmkt,
      EqYield   = 1 / PeRatio,
      BizGear   = (BizLns + BizBnd) / (BizLns + BizBnd + BizEq),
      RbizReal  = (1 - TcorpRate) * Rbiz / (PconsExrent / lag(PconsExrent, 4)),
      KdepAllow = (KdepRate * (1 + R10y)) * (R10y + KdepRate),
      CostCap   = (RbizReal * BizGear + EqYield * (1 - BizGear) + KdepRate) *
                    (1 - KdepAllow * TcorpRate),
      Ynli      = Ygmi + YprpR - YprpP,
      GovDem    = Igov + Ipubent + Cgov,
      PhouseSa  = sa_series(Phouse, date),
      PhouseReal = PhouseSa / Pcpi,
      Rtwi      = RtwiNom * lag(PcpiExGst) / lag(Fpcpi),
      R90dReal  = R90d - (Pcpi / lag(Pcpi, 4) - 1),
      Fr10y     = (3 / 5) * Fr10yUs + (1 / 6) * Fr10yJp +
                  (3 / 20) * Fr10yDe + (1 / 12) * Fr10yUk,
      Fr10yReal = Fr10y - ((lag(Fpcpi, 2) / lag(Fpcpi, 6) - 1) +
                            (lag(Fpcpi, 6) / lag(Fpcpi, 10) - 1)) / 2,
      Rdif10y   = R10yReal - Fr10yReal,
      RmortReal = Rmort - (Pcpi / lag(Pcpi, 4) - 1),
      RmortRealExgst = Rmort - (PcpiExGst / lag(PcpiExGst, 4) - 1),
      InflExp   = hp_filter(log(Pcpi / lag(Pcpi, 4))),
      CprHpf    = hp_filter(Cpr),
      PhouseHpf = hp_filter(PhouseSa),
      LurHpf    = hp_filter(Lur),
      YgdpHpf   = hp_filter(Ygdp),
      RmortRealHpf = hp_filter(RmortReal),
      Ptot      = 100 * Pxtot / Pmgs
    )

  data <- data %>%
    mutate(
      trend        = row_number() - 1,
      trend_piret  = trend + 8,
      trend_98     = cumsum(date >= "1998-03-01"),
      trend_01     = cumsum(date >= "2001-03-01"),
      trend_08     = cumsum(date >= "2008-03-01"),
      d93          = as.numeric(date >= "1993-03-01"),
      q3           = as.numeric(month(date) == 9),
      ShockGst     = as.numeric(ShockGst),
      dum_1975q3   = as.numeric(date == "1975-09-01"),
      dum_1976q4   = as.numeric(date == "1976-12-01"),
      dum_2009q1   = as.numeric(date == "2009-03-01"),
      dum_2020q1   = as.numeric(date == "2020-03-01"),
      dum_2020q2   = as.numeric(date == "2020-06-01"),
      dum_2020q3   = as.numeric(date == "2020-09-01"),
      dum_2020q4   = as.numeric(date == "2020-12-01"),
      dum_2021q1   = as.numeric(date == "2021-03-01"),
      dum_2000q3   = as.numeric(date == "2000-09-01"),
      dum_2000q4   = as.numeric(date == "2000-12-01"),
      dum_2012q4   = as.numeric(date == "2012-12-01"),
      dum_2022q1   = as.numeric(date == "2022-03-01"),
      dum_2022     = as.numeric(year(date) == 2022),
      dum_2023     = as.numeric(year(date) == 2023),
      sb_2001      = as.numeric(date >= "2002-03-01"),
      dum_covid_cpr = as.numeric(between(date, as.Date("2020-03-01"),
                                         as.Date("2022-03-01"))),
      dum_covid_avh = as.numeric(between(date, as.Date("2020-03-01"),
                                         as.Date("2022-09-01"))),
      LparHpf      = hp_filter(Lpar),
      PpcdHpf      = hp_filter(Ppcd)
    )

  # Balassa-Samuelson unit labour costs: the signal equation is estimated
  # jointly with c2, then the two sector concepts are formed.
  BS_PARAM <- 0.002764
  bs_dat <- data %>%
    transmute(lp = log(Ppcd), lu = log(Pulc), lm = log(Pmgs), tr = trend) %>%
    filter(if_all(everything(), is.finite))
  bs_fit <- nls(
    lp ~ c1 + c2 * lu + BS_PARAM * (1 - c2) * tr + (1 - c2) * lm,
    data = bs_dat, start = list(c1 = 0, c2 = 0.65)
  )
  bs_c2 <- coef(bs_fit)[["c2"]]
  data$UlcDom <- log(data$Pulc) + BS_PARAM * ((1 - bs_c2) / bs_c2) * data$trend
  data$UlcExp <- log(data$Pulc) - BS_PARAM * data$trend
  attr(data, "bs_c2") <- bs_c2
  message(sprintf("Balassa-Samuelson signal equation: c(2) = %.4f", bs_c2))

  data
}

# ---- orchestration -------------------------------------------------------------

prepare_model_data <- function(refresh = FALSE,
                               raw_path = "data/raw_series.rds",
                               history_path = "data/sourced_data.rds",
                               seed_path = "data-raw/Data.xlsx",
                               model_data_path = "data/model_data.rds") {
  history <- if (file.exists(history_path)) {
    readRDS(history_path)
  } else {
    read.xlsx(seed_path, sheet = "Data", detectDates = TRUE)
  }
  history <- history %>% mutate(date = as.Date(date))

  if (refresh && file.exists(raw_path)) {
    raw <- readRDS(raw_path)
    variables <- read.xlsx(seed_path, sheet = "Variables") %>%
      transmute(
        variable = Name,
        source = Source,
        transformation = Transformation,
        abs_ids = str_extract_all(Source, abs_id_pattern),
        rba_ids = map(Source, function(s) {
          unname(rba_ids[str_detect(s, fixed(rba_ids))])
        }),
        category = if_else(Name %in% exogenous_maintained,
                           "exogenous", "sourced")
      ) %>%
      filter(variable %in% names(history), variable != "date")
    sourced <- source_history(raw, variables, history)
    history <- sourced$history
    attr(history, "sourced_at") <- Sys.time()
    saveRDS(history, history_path)
    readr::write_csv(history, "data/sourced_data.csv", na = "")
    readr::write_csv(sourced$results, "outputs/data_download_validation.csv")
    cat("Sourced history:", nrow(history), "quarters -",
        n_distinct(sourced$results$variable[sourced$results$status ==
                                               "downloaded"]),
        "series refreshed\n")
    print(count(sourced$results, category), n = Inf)
  }

  model_data <- prepare_estimation_data(history)
  dir.create(dirname(model_data_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(model_data, model_data_path)
  model_data
}
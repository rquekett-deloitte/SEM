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
# Stage 1 extends data/sourced_data.rds in place from the raw store. The
# retired Data.xlsx workbook is not read. Exogenous scenario paths stay in
# data-raw/exogenous_forecast.csv.

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
exogenous_maintained <- c(
  "Fpcpi", "Fpoil", "Fpcom", "Fpagr", "FcGdp", "FcPpp",
  "Fr10yUs", "Fr10yJp", "Fr10yDe", "Fr10yUk", "IvtFar", "IntStu"
)

# ---- open-variable derivations --------------------------------------------------
# The variables the bootstrap workbook left frozen at 2024Q4 are extended
# from the source tables downloaded by R/download_data.R. Each rule below is
# either a published series (LavhMkt, Lhh, Rbiz, KdepRate), the model's own
# identity applied to history (PcpiExGst, K stocks, GovDebt, the rent
# repairs), or an explicit documented assumption (PeRatio - deferred, see the
# sourcing map). Nothing is ever carried forward silently: extensions fill
# only NA cells after the last observation, and each one reports its fit
# against the workbook history it replaces.

# Market sector for LavhMkt: every industry except the three non-market ones.
NONMARKET_INDUSTRIES <- c(
  "Public Administration and Safety ;", "Education and Training ;",
  "Health Care and Social Assistance ;")
MARKET_INDUSTRIES <- c(
  "Agriculture, Forestry and Fishing ;", "Mining ;", "Manufacturing ;",
  "Electricity, Gas, Water and Waste Services ;", "Construction ;",
  "Wholesale Trade ;", "Retail Trade ;", "Accommodation and Food Services ;",
  "Transport, Postal and Warehousing ;",
  "Information Media and Telecommunications ;",
  "Financial and Insurance Services ;", "Rental, Hiring and Real Estate Services ;",
  "Professional, Scientific and Technical Services ;",
  "Administrative and Support Services ;", "Arts and Recreation Services ;",
  "Other Services ;")

# Rbiz continuation (from 2019Q4, when RBA table D8 was discontinued):
# credit-share-weighted average of the F7 outstanding business lending rates.
# Weights recovered by constrained least squares against the workbook's
# 2019Q4-2024Q4 continuation: max residual 0.035 pp, RMSE 0.017 pp.
RBIZ_F7_WEIGHTS <- c(
  FLRBFOSBT = 0.2293,   # small business, outstanding, total
  FLRBFOMBT = 0.1052,   # medium business, outstanding, total
  FLRBFOLBT = 0.6655    # large business, outstanding, total
)

# LavhMkt: ABS 6291.0.55.001 Table 11 (original), market-sector aggregate
# hours actually worked divided by market-sector employed persons.
lavh_from_raw <- function(raw) {
  series_item <- function(item) {
    descs <- paste0(MARKET_INDUSTRIES, "  ", item)
    parts <- map(descs, function(dd) {
      hit <- raw %>% filter(description == dd)
      if (nrow(hit) == 0) return(NULL)
      hit %>% transmute(date = model_quarter(date), value) %>%
        group_by(date) %>% summarise(value = mean(value), .groups = "drop")
    }) %>% compact()
    if (length(parts) < length(MARKET_INDUSTRIES)) return(NULL)
    reduce(parts, function(a, b)
      full_join(a, b, by = "date", suffix = c("", "_y")) %>%
      mutate(value = coalesce(value, 0) + coalesce(value_y, 0)) %>%
      select(date, value))
  }
  hrs <- series_item("Number of hours actually worked in all jobs ;")
  emp <- series_item("Employed total ;")
  if (is.null(hrs) || is.null(emp)) return(NULL)
  inner_join(hrs, emp, by = "date", suffix = c("_h", "_e")) %>%
    transmute(date, value = value_h / value_e) %>% filter(is.finite(value))
}

# Lhh: ABS 6224.0.55.001 Table H.1 experimental household estimates.
# Reproduces the workbook series exactly at every common quarter.
interpolate_quarters <- function(series) {
  series <- series %>%
    filter(is.finite(value), !is.na(date)) %>%
    group_by(date) %>%
    summarise(value = mean(value), .groups = "drop") %>%
    arrange(date)
  if (nrow(series) < 2L) return(series)
  dates <- seq(min(series$date), max(series$date), by = "quarter")
  q_index <- function(x) year(x) * 4L + quarter(x)
  tibble(
    date = dates,
    value = approx(q_index(series$date), series$value,
                   xout = q_index(dates), rule = 1)$y
  ) %>% filter(is.finite(value))
}

lhh_from_raw <- function(raw) {
  hit <- raw %>% filter(series_id == "ABS.62240.H1.TOTALHH")
  if (nrow(hit) == 0) return(NULL)
  hit %>% transmute(date = model_quarter(date), value) %>%
    group_by(date) %>%
    summarise(value = mean(value) * 1000, .groups = "drop") %>%
    interpolate_quarters()
}

# Rbiz: weighted F7 composite, per cent per annum -> decimal.
rbiz_from_raw <- function(raw) {
  parts <- map(names(RBIZ_F7_WEIGHTS), function(id) {
    hit <- raw %>% filter(series_id == id)
    if (nrow(hit) == 0) return(NULL)
    hit %>% transmute(date = model_quarter(date), value) %>%
      group_by(date) %>% summarise(value = mean(value), .groups = "drop")
  }) %>% compact()
  if (length(parts) != length(RBIZ_F7_WEIGHTS)) return(NULL)
  idx <- seq_along(parts)
  out <- parts[[1]] %>% transmute(date, value = RBIZ_F7_WEIGHTS[idx[1]] * value)
  for (k in idx[-1]) {
    out <- inner_join(out, parts[[k]], by = "date", suffix = c("", "_y")) %>%
      mutate(value = value + RBIZ_F7_WEIGHTS[idx[k]] * value_y) %>%
      select(date, value)
  }
  out %>% mutate(value = value / 100) %>% filter(is.finite(value))
}

# KdepRate: (non-financial corporations consumption of fixed capital less
# mining) / (non-financial corporations net stock less mining net stock),
# both current prices, annual June years from the capital-stock tables.
kdep_from_raw <- function(raw) {
  pick_id <- function(id) {
    hit <- raw %>% filter(series_id == id)
    if (nrow(hit) == 0) return(NULL)
    conflicts <- hit %>%
      group_by(date) %>%
      summarise(n_value = n_distinct(value), .groups = "drop") %>%
      filter(n_value > 1L)
    if (nrow(conflicts)) {
      stop("Conflicting observations for capital-stock series ", id)
    }
    hit %>%
      group_by(date) %>%
      summarise(value = mean(value), .groups = "drop")
  }
  num_parts <- list(
    pick_id("A2422579R"), # non-financial corporations COFC, current prices
    pick_id("A3348034V")) # mining COFC, current prices
  den_parts <- list(
    pick_id("A2422578L"), # non-financial corporations stock, current prices
    pick_id("A3348056J")) # mining stock, current prices
  if (any(map_lgl(c(num_parts, den_parts), is.null))) return(NULL)
  num <- inner_join(num_parts[[1]], num_parts[[2]], by = "date",
                    suffix = c("_a", "_b")) %>%
    mutate(value = value_a - value_b) %>% select(date, value)
  den <- inner_join(den_parts[[1]], den_parts[[2]], by = "date",
                    suffix = c("_a", "_b")) %>%
    mutate(value = value_a - value_b) %>% select(date, value)
  inner_join(num, den, by = "date", suffix = c("_n", "_d")) %>%
    transmute(date, value = value_n / value_d) %>%
    filter(is.finite(value)) %>%
    interpolate_quarters()
}

# GovDef: quarterly path is linear between June-quarter anchors, and each
# financial year's sum ties to published GFS net lending through
# FY = 1.5 * anchor(t-1) + 2.5 * anchor(t). New anchors therefore solve as
# anchor(t) = (FY_deficit(t) - 1.5 * anchor(t-1)) / 2.5.
gfs_fy_deficits <- function(raw) {
  nl <- raw %>% filter(series_id == "ABS.GFS.ALLGG.NETLENDING")
  if (nrow(nl) == 0) return(NULL)
  nl %>%
    mutate(fy = ifelse(month(date) >= 7, year(date) + 1L, year(date))) %>%
    group_by(fy) %>%
    filter(n() == 4L) %>%               # complete financial years only
    summarise(deficit = -sum(value) / 1000, .groups = "drop")
}

# Fill a column's trailing NA cells with values from a splice-anchored
# reconstruction: the reconstruction is rescaled so it meets the last
# observed value exactly, then extended.
splice_extend <- function(column, dates, series, anchor_date = NULL) {
  idx <- match(series$date, dates)
  hit <- !is.na(idx) & is.finite(series$value)
  last_obs <- max(which(is.finite(column)))
  if (is.null(anchor_date)) anchor_date <- dates[last_obs]
  anchor_idx <- match(anchor_date, dates)
  recon_at_anchor <- series$value[match(anchor_date, series$date)]
  if (is.na(anchor_idx) || is.na(recon_at_anchor)) return(column)
  scale <- column[anchor_idx] / recon_at_anchor
  for (k in which(hit)) {
    if (is.na(column[idx[k]]) && idx[k] > last_obs)
      column[idx[k]] <- series$value[k] * scale
  }
  column
}

# Simple trailing-gap fills for the documented-assumption variables.
hold_extend <- function(column) {
  finite <- which(is.finite(column))
  if (!length(finite)) return(column)
  if (finite[length(finite)] < length(column))
    column[(finite[length(finite)] + 1):length(column)] <-
      column[finite[length(finite)]]
  column
}
decay_extend <- function(column, window = 8L) {
  finite <- which(is.finite(column))
  if (!length(finite)) return(column)
  tail_idx <- tail(finite, window)
  slope <- if (length(tail_idx) >= 2)
    coef(lm(column[tail_idx] ~ seq_along(tail_idx)))[[2]] else 0
  last <- finite[length(finite)]
  if (last >= length(column)) return(column)
  v <- column[last]
  for (k in (last + 1):length(column)) {
    if (!is.na(column[k])) next
    v <- max(0, v + slope)
    column[k] <- v
  }
  column
}

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
  transformation <- if ("transformation" %in% names(series)) {
    series$transformation[[1]]
  } else {
    NA_character_
  }
  divisor <- divisor_from_note(transformation)
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
    mutate(
      dwelling = case_when(
        str_detect(description, fixed("Established House")) ~ "house",
        str_detect(description, fixed("Attached Dwelling")) ~ "attached",
        TRUE ~ NA_character_
      ),
      location = trimws(str_split_fixed(description, ";", 3)[, 2])
    ) %>%
    filter(!is.na(dwelling), nzchar(location)) %>%
    select(date, dwelling, location, median = value)
  transfers <- raw %>%
    filter(str_detect(description, fixed("Number of")),
           str_detect(description, fixed("Transfers"))) %>%
    mutate(
      dwelling = case_when(
        str_detect(description, fixed("Established House")) ~ "house",
        str_detect(description, fixed("Attached Dwelling")) ~ "attached",
        TRUE ~ NA_character_
      ),
      location = trimws(str_split_fixed(description, ";", 3)[, 2])
    ) %>%
    filter(!is.na(dwelling), nzchar(location)) %>%
    select(date, dwelling, location, trades = value)
  if (nrow(medians) == 0 || nrow(transfers) == 0) return(NULL)
  inner_join(medians, transfers, by = c("date", "dwelling", "location")) %>%
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
      filter(str_detect(description, fixed(sector)),
             str_detect(description, fixed(instrument)),
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
  frequency_of <- function(id) {
    hit <- raw %>% filter(series_id == id) %>% arrange(date)
    published <- hit$frequency[!is.na(hit$frequency) & nzchar(hit$frequency)]
    if (length(published)) return(published[[1]])
    dates <- sort(unique(as.Date(hit$date)))
    if (length(dates) < 2L) return(NA_character_)
    spacing <- median(as.numeric(diff(dates)), na.rm = TRUE)
    if (spacing <= 7) "Daily" else if (spacing <= 45) "Month" else if (
      spacing <= 120) "Quarter" else "Annual"
  }

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
      series <- raw %>% filter(series_id == id)
      if (nrow(series) == 0) return(NULL)
      series$transformation <- row$transformation
      series$frequency <- frequency_of(id)
      to_model_quarters(series)
    }) %>% compact()
    if (!length(parts)) return(NULL)
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
      series <- mutate(series, value = value * factor)
      scale_note <- paste0("rescaled x", format(factor), "; ")
      joined <- history %>%
        select(date, current = all_of(variable)) %>%
        inner_join(series, by = "date") %>%
        filter(is.finite(current), is.finite(value))
    }
    diffs <- pct_diff(joined$value, joined$current)
    history_span <- history %>%
      dplyr::select(date, current = dplyr::all_of(variable))
    fills <- series %>%
      dplyr::left_join(history_span, by = "date") %>%
      dplyr::filter(
        date >= min(history$date),
        is.finite(value),
        date > max(history$date) | !is.finite(as.numeric(current))
      )
    median_diff <- suppressWarnings(median(diffs, na.rm = TRUE))
    result <- tibble(
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
    list(result = result, series = series)
  }

  skipped <- function(variable, category) {
    reason <- case_when(
      category == "exogenous" ~
        "exogenous by design - maintained via exogenous_forecast.csv",
      variable %in% c("KNbiz", "KOther", "EqEarn") ~
        "derived - computed from its parents after the merge",
      variable %in% c("PeRatio", "EqEarn", "LavhMkt", "PcpiExGst", "ShockGst",
                      "GovDef", "GovDebt", "Lhh", "Rbiz", "KdepRate",
                      "TcorpRate", "DumTsfTot") ~
        "extended by the open-variable derivation after the merge",
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
    validation <- validate(variable, category, series)
    series_by_variable[[variable]] <<- validation$series
    validation$result
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

  updated <- history
  new_ends <- as.Date(results$new_end[!is.na(results$n_new) &
                                        results$n_new > 0])
  if (anyNA(new_ends)) {
    stop("A downloaded series reported an unparseable new-quarter date")
  }
  if (length(new_ends) && max(new_ends) > max(updated$date)) {
    span <- seq(seq(max(updated$date), by = "quarter", length.out = 2)[2],
                max(new_ends), by = "quarter")
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

  list(history = updated, results = results)
}

# ---- open-variable extension ----------------------------------------------------
# Extends the variables the workbook left at 2024Q4 using the source tables
# in the raw store. Every rule fills only trailing NA cells; history is never
# overwritten (the K stocks are the deliberate exception: the workbook's own
# post-benchmark extrapolation is replaced by the model's perpetual-inventory
# identity). Returns the updated history plus validation rows for the
# sourcing map.
derive_open_variables <- function(updated, raw, prior) {
  dates <- updated$date
  notes <- list()

  note_row <- function(variable, note, series = NULL) {
    overlap <- 0L
    med <- NA_real_
    if (!is.null(series) && variable %in% names(prior)) {
      joined <- tibble(date = dates,
                       current = as.numeric(prior[[variable]])) %>%
        inner_join(series, by = "date") %>%
        filter(is.finite(current), is.finite(value))
      overlap <- nrow(joined)
      if (overlap) {
        k <- median(joined$value / joined$current)
        med <- median(abs(100 * (joined$value / k / joined$current - 1)))
        note <- paste0(note, sprintf("; overlap fit %.3f%% over %d q",
                                     med, overlap))
      }
    }
    tibble(variable = variable, category = "sourced", status = "derived",
           note = note, n_overlap = overlap,
           median_abs_pct_diff = round(med, 3), mean_abs_pct_diff = NA_real_,
           max_abs_pct_diff = NA_real_, worst_quarter = "",
           verdict = if (overlap && med < 0.5) "source confirmed" else "derived",
           n_new = NA_integer_, new_end = "")
  }

  # 1. Published-series extensions, splice-anchored at the last observation.
  lavh <- lavh_from_raw(raw)
  if (!is.null(lavh) && "LavhMkt" %in% names(updated)) {
    updated$LavhMkt <- splice_extend(updated$LavhMkt, dates, lavh)
    notes$LavhMkt <- note_row(
      "LavhMkt",
      "ABS 6291.0.55.001 T11: market-sector hours / market-sector employed",
      lavh)
  }
  lhh <- lhh_from_raw(raw)
  if (!is.null(lhh) && "Lhh" %in% names(updated)) {
    updated$Lhh <- splice_extend(updated$Lhh, dates, lhh)
    published_end <- max(lhh$date)
    endpoint <- match(published_end, dates)
    if (!is.na(endpoint) && is.finite(updated$Lhh[endpoint]) &&
        "Lpop" %in% names(updated) && is.finite(updated$Lpop[endpoint])) {
      ratio <- updated$Lhh[endpoint] / updated$Lpop[endpoint]
      fill <- is.na(updated$Lhh) & dates > published_end &
        is.finite(updated$Lpop)
      updated$Lhh[fill] <- ratio * updated$Lpop[fill]
    }
    notes$Lhh <- note_row(
      "Lhh", paste("ABS 6224.0.55.001 T H.1 households, interpolated between",
                   "published benchmarks; after the final benchmark uses the",
                   "forecast closure's fixed households/population ratio"),
      lhh)
  }
  rbiz <- rbiz_from_raw(raw)
  if (!is.null(rbiz) && "Rbiz" %in% names(updated)) {
    updated$Rbiz <- splice_extend(updated$Rbiz, dates, rbiz)
    notes$Rbiz <- note_row(
      "Rbiz", "RBA F7 credit-share-weighted outstanding business lending",
      rbiz)
  }
  kdep <- kdep_from_raw(raw)
  if (!is.null(kdep) && "KdepRate" %in% names(updated)) {
    updated$KdepRate <- splice_extend(updated$KdepRate, dates, kdep)
    updated$KdepRate <- hold_extend(updated$KdepRate)
    notes$KdepRate <- note_row(
      "KdepRate", paste("quarterly interpolation of (PNFC COFC less mining)",
                        "/ (PNFC stock less mining); terminal calibration",
                        "held after the final published benchmark"),
      kdep)
  }

  # 2. Documented assumptions and identity-consistent rules.
  if ("PeRatio" %in% names(updated)) {
    updated$PeRatio <- hold_extend(updated$PeRatio)
    notes$PeRatio <- note_row(
      "PeRatio",
      paste("DEFERRED: no automatable free source (LSEG subscription",
            "ceased; S&P DJI factsheet is PDF-only, bot-walled, no history",
            "and runs ~1.25x the LSEG level); held at final observed"))
  }
  if ("TcorpRate" %in% names(updated)) {
    updated$TcorpRate <- hold_extend(updated$TcorpRate)
    notes$TcorpRate <- note_row(
      "TcorpRate", "legislated company tax rate; 0.30 held (ATO)")
  }
  if ("DumTsfTot" %in% names(updated)) {
    updated$DumTsfTot <- hold_extend(updated$DumTsfTot)
    notes$DumTsfTot <- note_row(
      "DumTsfTot", "COVID transfer dummy; zero after the episode")
  }
  if ("ShockGst" %in% names(updated)) {
    updated$ShockGst <- decay_extend(updated$ShockGst)
    notes$ShockGst <- note_row(
      "ShockGst",
      paste("owner COVID GST-base correction (non-zero 2020Q1-2024Q4",
            "only; coverage-wedge and equation-implied reconstructions",
            "both tested and rejected); terminal linear decay to zero"))
  }
  if (all(c("PcpiExGst", "Pcpi") %in% names(updated))) {
    k <- updated$PcpiExGst / updated$Pcpi
    last_k <- tail(k[is.finite(k)], 1)
    fill <- is.na(updated$PcpiExGst) & is.finite(updated$Pcpi)
    updated$PcpiExGst[fill] <- updated$Pcpi[fill] * last_k
    notes$PcpiExGst <- note_row(
      "PcpiExGst",
      paste0("Pcpi x k, k held at final observed ", sprintf("%.6f", last_k),
             " (GST step 2000Q3); matches the forecast identity"))
  }
  if (all(c("EqEarn", "Peq", "PeRatio") %in% names(updated))) {
    fill <- is.na(updated$EqEarn) & is.finite(updated$Peq) &
      is.finite(updated$PeRatio)
    updated$EqEarn[fill] <- updated$Peq[fill] / updated$PeRatio[fill]
    notes$EqEarn <- note_row("EqEarn", "Peq / PeRatio (exact identity)")
  }

  # 3. GovDef: linear between June anchors; new anchors solve the
  #    FY = 1.5*a(t-1) + 2.5*a(t) identity against GFS net lending.
  fy <- gfs_fy_deficits(raw)
  if (!is.null(fy) && "GovDef" %in% names(updated)) {
    gd <- as.numeric(updated$GovDef)
    observed <- which(is.finite(gd))
    last_anchor <- observed[length(observed)]
    a <- gd[last_anchor]
    first_fy <- if (month(dates[last_anchor]) > 6L) {
      year(dates[last_anchor]) + 1L
    } else {
      year(dates[last_anchor])
    }
    new_anchors <- fy %>% filter(fy >= first_fy) %>% arrange(fy)
    for (r in seq_len(nrow(new_anchors))) {
      idx <- which(dates == as.Date(sprintf("%d-06-01", new_anchors$fy[r])))
      if (length(idx) != 1L || idx <= last_anchor) next
      bridge <- seq.int(last_anchor + 1L, idx)
      missing_bridge <- bridge[is.na(gd[bridge])]
      if (!length(missing_bridge)) {
        last_anchor <- idx
        a <- gd[idx]
        next
      }
      fy_cells <- which(year(dates) + as.integer(month(dates) > 6L) ==
                          new_anchors$fy[r])
      known_sum <- sum(gd[fy_cells], na.rm = TRUE)
      fractions <- (missing_bridge - last_anchor) / (idx - last_anchor)
      fixed_part <- a * sum(1 - fractions)
      a_next <- (new_anchors$deficit[r] - known_sum - fixed_part) /
        sum(fractions)
      gd[missing_bridge] <- a + (a_next - a) * fractions
      last_anchor <- idx
      a <- a_next
    }
    updated$GovDef <- gd
    notes$GovDef <- note_row(
      "GovDef",
      paste("observed history preserved; missing quarters linear to June",
            "anchors whose financial-year sums tie to GFS net lending"))
  }

  # 4. GovDebt: extend with the model's own accumulation identity
  #    GovDebt(t) = GovDebt(t-1) + GovDef(t) + x * R10y(t-5) * GovDebt(t-1),
  #    x re-estimated on the observed history before extending.
  if (all(c("GovDebt", "GovDef", "R10y") %in% names(updated))) {
    debt <- as.numeric(updated$GovDebt)
    df <- tibble(date = dates, debt, def = as.numeric(updated$GovDef),
                 r5 = lag(as.numeric(updated$R10y), 5),
                 debt_l = lag(debt)) %>%
      filter(date >= as.Date("2004-09-01"),
             is.finite(debt), is.finite(def), is.finite(r5), is.finite(debt_l))
    x <- if (nrow(df) > 8) coef(lm(I(debt - debt_l - def) ~ 0 + I(r5 * debt_l),
                                   data = df))[[1]] else 0
    for (k in which(is.na(debt))) {
      if (k < 2 || !is.finite(debt[k - 1])) next
      def_k <- as.numeric(updated$GovDef[k])
      r5_k <- dplyr::lag(as.numeric(updated$R10y), 5)[k]
      if (!is.finite(def_k) || !is.finite(r5_k)) next
      debt[k] <- debt[k - 1] + def_k + x * r5_k * debt[k - 1]
    }
    updated$GovDebt <- debt
    notes$GovDebt <- note_row(
      "GovDebt",
      paste0("accumulation identity extension (x = ", sprintf("%.5f", x),
             "; GFS net debt vintages do not match the workbook measure)"))
  }

  # 5. K stocks: truncate the workbook's post-benchmark extrapolation and
  #    re-extend with the model's perpetual-inventory identity, using the
  #    same mean-8 depreciation rates the forecast calibrates.
  stock_raw <- raw %>%
    filter(description ==
             "Non-financial corporations ;  End-year net capital stock: Current prices ;")
  benchmark_end <- if (nrow(stock_raw)) max(model_quarter(stock_raw$date))
                  else as.Date(NA)
  if (is.finite(benchmark_end) &&
      all(c("KMin", "KNbiz", "KDwell") %in% names(updated))) {
    post <- which(dates > benchmark_end)
    for (v in c("KMin", "KNbiz", "KBiz", "KDwell", "KTotal", "KOther"))
      updated[[v]][post] <- NA_real_
    mean8 <- function(x) { xf <- x[is.finite(x)]; mean(tail(xf, 8)) }
    dep_rate <- function(k, inv) {
      lag_k <- lag(as.numeric(updated[[k]]))
      lag_i <- lag(as.numeric(updated[[inv]]))
      mean8(1 - (as.numeric(updated[[k]]) - lag_i) / lag_k)
    }
    rate_min <- dep_rate("KMin", "Imin")
    rate_nbz <- dep_rate("KNbiz", "Inonmin")
    rate_dwl <- dep_rate("KDwell", "Idwell")
    piv <- function(k, inv, rate) {
      x <- as.numeric(updated[[k]])
      i <- as.numeric(updated[[inv]])
      for (t in which(is.na(x))) {
        if (t < 2 || !is.finite(x[t - 1]) || !is.finite(i[t - 1])) next
        x[t] <- (1 - rate) * x[t - 1] + i[t - 1]
      }
      x
    }
    updated$KMin <- piv("KMin", "Imin", rate_min)
    updated$KNbiz <- piv("KNbiz", "Inonmin", rate_nbz)
    updated$KDwell <- piv("KDwell", "Idwell", rate_dwl)
    updated$KOther <- hold_extend(as.numeric(updated$KOther))
    updated$KBiz <- updated$KMin + updated$KNbiz
    updated$KTotal <- updated$KBiz + updated$KDwell + updated$KOther
    notes$KMin <- note_row(
      "KMin",
      sprintf("benchmarks to %s then perpetual-inventory identity",
              format(benchmark_end)))
    notes$KBiz <- note_row(
      "KBiz", "KMin + KNbiz; benchmarks then perpetual-inventory identity")
    notes$KDwell <- note_row(
      "KDwell",
      sprintf("benchmarks to %s then perpetual-inventory identity",
              format(benchmark_end)))
    notes$KTotal <- note_row(
      "KTotal", "KBiz + KDwell + KOther (KOther held; forecast treatment)")
    notes$KNbiz <- note_row(
      "KNbiz", "KBiz - KMin; benchmarks then perpetual-inventory identity")
    notes$KOther <- note_row(
      "KOther", "KTotal - KBiz - KDwell history, then held")
  }

  # 6. Repairs for the failed downloads, from downloaded parents via the
  #    model's own identity formulas.
  if (all(c("Pgne", "YgdpNom", "MtotNom", "XtotNom", "Ygne") %in%
          names(updated))) {
    gne_nom <- as.numeric(updated$YgdpNom) + as.numeric(updated$MtotNom) -
      as.numeric(updated$XtotNom)
    fill <- is.na(updated$Pgne) & is.finite(gne_nom) &
      is.finite(as.numeric(updated$Ygne))
    updated$Pgne[fill] <- 100 * gne_nom[fill] / as.numeric(updated$Ygne)[fill]
    notes$Pgne <- note_row(
      "Pgne", "100 * GNE nominal / GNE real from downloaded parents")
  }
  for (pair in list(c("CconsRentNom", "CprNom"), c("CconsRent", "Cpr"))) {
    if (all(pair %in% names(updated))) {
      num <- as.numeric(updated[[pair[1]]])
      den <- as.numeric(updated[[pair[2]]])
      ratio <- tail((num / den)[is.finite(num) & is.finite(den)], 1)
      fill <- is.na(num) & is.finite(den)
      num[fill] <- den[fill] * ratio
      updated[[pair[1]]] <- num
      notes[[pair[1]]] <- note_row(
        pair[1], "consumption share held; model's own closure")
    }
  }

  list(history = updated, results = bind_rows(notes))
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
                               model_data_path = "data/model_data.rds") {
  if (!file.exists(history_path)) {
    stop("Sourced history not found: ", history_path)
  }
  history <- readRDS(history_path)
  history <- history %>% mutate(date = as.Date(date))

  if (refresh && file.exists(raw_path)) {
    raw <- readRDS(raw_path)
    if (!exists("read_variable_catalog")) {
      source("R/model_constants.R", local = TRUE)
    }
    variables <- read_variable_catalog() %>%
      transmute(
        variable,
        source,
        transformation,
        abs_ids = str_extract_all(source, abs_id_pattern),
        rba_ids = map(source, function(s) {
          unname(rba_ids[str_detect(s, fixed(rba_ids))])
        }),
        category = if_else(variable %in% exogenous_maintained,
                           "exogenous", "sourced")
      ) %>%
      filter(variable %in% names(history), variable != "date")
    sourced <- source_history(raw, variables, history)
    derived <- derive_open_variables(sourced$history, raw, prior = history)
    history <- derived$history
    results <- bind_rows(sourced$results, derived$results) %>%
      filter(!(variable %in% unique(derived$results$variable) &
                 status != "derived"))
    attr(history, "sourced_at") <- Sys.time()
    saveRDS(history, history_path)
    readr::write_csv(history, "data/sourced_data.csv", na = "")
    readr::write_csv(results, "outputs/data_download_validation.csv")
    cat("Sourced history:", nrow(history), "quarters -",
        n_distinct(results$variable[results$status == "downloaded"]),
        "series refreshed,", nrow(derived$results),
        "open-variable extensions applied\n")
    print(count(results, status), n = Inf)
  }

  model_data <- prepare_estimation_data(history)
  assert_model_data_complete(model_data)
  dir.create(dirname(model_data_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(model_data, model_data_path)
  model_data
}

# Verify the observation-only conditioning frontier. Scenario-maintained
# columns and identities that depend on them remain ragged here; the forecast
# database fills their pre-origin bridge from the explicit scenario contract.
assert_model_data_complete <- function(data) {
  if (!exists("MODEL_DATA_INPUTS")) {
    source("R/model_constants.R", local = TRUE)
  }
  dates <- as.Date(data$date)
  cond <- intersect(OBSERVED_CONDITIONING_INPUTS, names(data))
  complete <- Reduce(`&`, lapply(data[cond],
                                 function(x) is.finite(as.numeric(x))))
  if (!any(complete)) stop("No quarter has complete conditioning inputs")
  frontier <- max(dates[complete])
  message("Observed conditioning inputs complete through: ",
          format(frontier))
  invisible(frontier)
}

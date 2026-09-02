model_lhs <- function(equations) {
  trimws(sub("\\s*=.*$", "", equations))
}

extract_coefficients <- function(model) {
  purrr::imap_dfr(model$fits, function(fit, equation) {
    if (inherits(fit, c("lm", "nls"))) {
      estimates <- stats::coef(fit)
      standard_errors <- sqrt(diag(stats::vcov(fit)))
    } else if (is.list(fit) && !is.null(fit$par)) {
      estimates <- fit$par
      standard_errors <- stats::setNames(fit$std_error, names(estimates))
    } else {
      stop("Unsupported fitted-model class for ", equation)
    }

    terms <- names(estimates)
    terms[terms == "(Intercept)"] <- "c1"
    tibble::tibble(
      equation,
      term = terms,
      estimate = as.numeric(estimates),
      std_error = as.numeric(standard_errors[names(estimates)])
    )
  })
}

load_saved_model <- function(
    model_data,
    path = "outputs/coefficients.csv") {
  required <- c("equation", "term", "estimate", "std_error")
  coefficients <- readr::read_csv(path, show_col_types = FALSE)
  if (!identical(names(coefficients), required)) {
    stop("Saved coefficients must contain exactly: ", paste(required, collapse = ", "))
  }
  if (any(!is.finite(coefficients$estimate))) {
    stop("Saved coefficients contain non-finite estimates")
  }

  expected_equations <- names(mdl_prefix)
  if (!setequal(unique(coefficients$equation), expected_equations)) {
    stop("Saved coefficients do not cover the model equations exactly")
  }

  equation_text <- paste(mdl_equations(), collapse = " ")
  equations <- unique(coefficients$equation)
  fits <- equations %>%
    stats::setNames(equations) %>%
    purrr::map(function(equation) {
      rows <- coefficients %>% dplyr::filter(.data$equation == !!equation)
      terms <- rows$term
      has_intercept <- stringr::str_detect(
        equation_text,
        stringr::fixed(paste0(mdl_prefix[[equation]], "_Int"))
      )
      if (has_intercept) terms[terms == "c1"] <- "(Intercept)"
      structure(
        list(
          par = stats::setNames(rows$estimate, terms),
          std_error = stats::setNames(rows$std_error, terms)
        ),
        class = "saved_model_fit"
      )
    })
  list(
    fits = fits,
    data = model_data,
    bs_c2 = attr(model_data, "bs_c2")
  )
}

extract_forecast <- function(simulated_model, origin, horizon) {
  dates <- seq(as.Date(origin), as.Date(horizon), by = "quarter")
  simulation <- simulated_model$simulation
  database <- simulated_model$modelData
  if (is.null(simulation) || is.null(database)) {
    stop("Simulated BIMETS model does not contain simulation and modelData")
  }

  find_series <- function(container, variable) {
    hit <- which(tolower(names(container)) == tolower(variable))
    if (length(hit) != 1L) stop("Expected one model series for ", variable)
    container[[hit]]
  }
  extract_window <- function(series, variable) {
    values <- as.numeric(stats::window(
      series,
      start = c(lubridate::year(origin), lubridate::quarter(origin)),
      end = c(lubridate::year(horizon), lubridate::quarter(horizon))
    ))
    if (length(values) != length(dates)) {
      stop("Forecast series has the wrong length: ", variable)
    }
    if (any(!is.finite(values))) stop("Non-finite forecast value in ", variable)
    values
  }

  endogenous <- unique(c(model_lhs(mdl_equations()), model_lhs(mdl_identities())))
  scenario <- unique(mdl_exogenous_contract()$model_variable)
  realtime_hpf <- unique(mdl_realtime_hpf_contract()$model_variable)
  variables <- unique(c(endogenous, scenario, realtime_hpf))
  values <- variables %>%
    purrr::map(function(variable) {
      source <- if (variable %in% endogenous) simulation else database
      extract_window(find_series(source, variable), variable)
    }) %>%
    stats::setNames(variables)
  annual_growth <- function(variable) {
    series <- find_series(simulation, variable)
    current <- extract_window(series, variable)
    previous <- as.numeric(stats::window(
      series,
      start = c(lubridate::year(origin) - 1L, lubridate::quarter(origin)),
      end = c(lubridate::year(horizon) - 1L, lubridate::quarter(horizon))
    ))
    if (length(previous) != length(dates) || any(!is.finite(previous))) {
      stop("Annual growth comparison has the wrong history: ", variable)
    }
    100 * (current / previous - 1)
  }
  values$YgdpAnnualGrowth <- annual_growth("Ygdp")
  values$PcpiAnnualGrowth <- annual_growth("Pcpi")
  tibble::as_tibble(c(list(date = dates), values))
}

validate_forecast <- function(forecast, history, tolerance = 1e-6) {
  required <- c(
    "Ygdp", "Cpr", "Cgov", "Idwell", "Iotc", "Imin", "Inonmin",
    "Igov", "Ipubent", "Ivt", "IvtFar", "IvtNonfarm", "Xtot", "Mtot",
    "YgdpAnnualGrowth", "PcpiAnnualGrowth"
  )
  missing <- setdiff(required, names(forecast))
  if (length(missing) > 0) {
    stop("Forecast is missing validation fields: ", paste(missing, collapse = ", "))
  }
  if (nrow(forecast) == 0 || any(!is.finite(as.matrix(forecast[required])))) {
    stop("Forecast validation fields must be finite and non-empty")
  }

  previous_stock <- c(
    tail(history$IvtNonfarm[is.finite(history$IvtNonfarm)], 1),
    head(forecast$IvtNonfarm, -1)
  )
  expected_inventory_flow <- forecast$IvtFar + forecast$IvtNonfarm - previous_stock
  inventory_error <- max(abs(forecast$Ivt - expected_inventory_flow))
  inventory_scale <- max(1, abs(expected_inventory_flow))
  if (inventory_error > tolerance * inventory_scale) {
    stop("Inventory flow identity failed; maximum error = ", inventory_error)
  }

  expenditure <- with(
    forecast,
    Cpr + Cgov + Idwell + Iotc + Imin + Inonmin + Igov + Ipubent +
      Ivt + Xtot - Mtot
  )
  accounting_residual <- forecast$Ygdp - expenditure
  residual_drift <- max(abs(accounting_residual - accounting_residual[[1]]))
  residual_scale <- max(1, abs(forecast$Ygdp))
  if (residual_drift > tolerance * residual_scale) {
    stop("Real GDP accounting residual is not constant; maximum drift = ", residual_drift)
  }

  invisible(forecast)
}

# Sense-check the current estimates against a saved coefficient vintage
# (default: the baseline original_estimated_coefficients.csv). The baseline
# predates an equation rename, so old names are mapped onto current ones
# before joining; anything still unmatched (renamed away, added or removed
# equations) is reported rather than silently dropped. Writes the full
# comparison, sorted by the size of the absolute change.
BASELINE_EQUATION_NAMES <- c(
  Idw = "Idwell", IvtNF = "IvtNonfarm", Ttsf = "Ytsf",
  LempNM = "LempNonmkt", Peqi = "Peq", Pgc = "Pgov",
  Pidw = "Pidwell", Wgov = "GovDebt", Prent = "PcpiRent",
  EqiEarn = "EqEarn", Pcnh = "PconsExrent"
)

compare_coefficients <- function(coefficients,
                                  baseline_path = "original_estimated_coefficients.csv",
                                  path = "outputs/coefficient_comparison.csv") {
  if (!file.exists(baseline_path)) {
    message("No coefficient baseline found at ", baseline_path,
            "; skipping the coefficient comparison.")
    return(invisible(NULL))
  }
  baseline <- readr::read_csv(baseline_path, show_col_types = FALSE)
  if (!all(c("equation", "term", "estimate") %in% names(baseline))) {
    stop("Coefficient baseline must contain equation, term and estimate columns")
  }
  comparison <- coefficients %>%
    dplyr::transmute(
      equation, term,
      current_estimate = estimate,
      std_error = std_error
    ) %>%
    dplyr::full_join(
      baseline %>%
        dplyr::mutate(
          baseline_equation_name = equation,
          equation = dplyr::coalesce(
            BASELINE_EQUATION_NAMES[equation], dplyr::if_else(equation %in% names(BASELINE_EQUATION_NAMES), NA_character_, equation)
          )
        ) %>%
        dplyr::filter(!is.na(equation)) %>%
        dplyr::transmute(
          equation, term, baseline_estimate = estimate,
          baseline_equation_name
        ),
      by = c("equation", "term")
    ) %>%
    dplyr::mutate(
      abs_change = current_estimate - baseline_estimate,
      pct_change = dplyr::if_else(
        abs(baseline_estimate) > 1e-12,
        100 * (current_estimate / baseline_estimate - 1),
        NA_real_
      ),
      sign_change = !is.na(current_estimate) & !is.na(baseline_estimate) &
        sign(current_estimate) != sign(baseline_estimate)
    ) %>%
    dplyr::arrange(dplyr::desc(abs(abs_change)))
  readr::write_csv(comparison, path, na = "")
  invisible(comparison)
}

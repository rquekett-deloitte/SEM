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
  tibble::as_tibble(c(list(date = dates), values))
}

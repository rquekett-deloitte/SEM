build_results_workbook <- function(
    forecast,
    history,
    coefficients,
    template_path = "templates/model_results_template.xlsx",
    path = "outputs/model_results.xlsx") {
  variables <- c(
    "Ygdp", "Cpr", "Pcpi", "Lemp", "Lhrs", "Lur", "Lpar",
    "R90d", "R10y"
  )
  comparison <- dplyr::bind_rows(
    history %>%
      dplyr::select(date, dplyr::all_of(variables)) %>%
      dplyr::mutate(period = "Actual"),
    forecast %>%
      dplyr::select(date, dplyr::all_of(variables)) %>%
      dplyr::mutate(period = "Forecast")
  ) %>%
    dplyr::arrange(date) %>%
    dplyr::filter(date >= as.Date("2015-03-01"))

  workbook <- openxlsx::loadWorkbook(template_path)
  required_sheets <- c("Dashboard", "Comparison", "Forecast", "Coefficients")
  if (!all(required_sheets %in% names(workbook))) {
    stop("Workbook template is missing required sheets")
  }

  capacities <- c(Comparison = 200L, Forecast = 50L, Coefficients = 300L)
  data_tables <- list(
    Comparison = comparison,
    Forecast = forecast,
    Coefficients = coefficients
  )
  purrr::iwalk(data_tables, function(data, sheet) {
    capacity <- capacities[[sheet]]
    if (nrow(data) > capacity) {
      stop(sheet, " data exceeds the workbook template capacity of ", capacity)
    }
    openxlsx::deleteData(
      workbook,
      sheet,
      cols = seq_len(ncol(data)),
      rows = 2:(capacity + 1),
      gridExpand = TRUE
    )
    openxlsx::writeData(
      workbook,
      sheet,
      data,
      startRow = 2,
      startCol = 1,
      colNames = FALSE,
      keepNA = FALSE
    )
  })

  summary_values <- list(
    min(forecast$date),
    max(forecast$date),
    forecast$Lur[[1]],
    forecast$R90d[[1]],
    dplyr::last(forecast$Lur),
    dplyr::last(forecast$R90d)
  )
  purrr::iwalk(summary_values, function(value, index) {
    openxlsx::writeData(
      workbook,
      "Dashboard",
      value,
      startRow = 4L + as.integer(index),
      startCol = 2,
      colNames = FALSE
    )
  })

  openxlsx::saveWorkbook(workbook, path, overwrite = TRUE)
  path
}

# One flat sheet: every model variable, historical and forecast, one row per
# quarter. Deterministic estimation scaffolding (trends, dummies, indicators)
# is excluded; every other variable in the estimation data and the forecast
# is preserved. History is marked "Actual" up to the conditioning quarter
# and "Forecast" from the origin.
build_flat_output <- function(forecast, history, origin,
                              path = "outputs/model_results_flat.xlsx") {
  deterministic <- c(
    "trend", "trend_piret", "trend_98", "trend_01", "trend_08",
    "d93", "q3", "sb_2001",
    "dum_1975q3", "dum_1976q4", "dum_2000q3", "dum_2000q4",
    "dum_2009q1", "dum_2012q4", "dum_2020q1", "dum_2020q2",
    "dum_2020q3", "dum_2020q4", "dum_2021q1", "dum_2022q1",
    "dum_2022", "dum_2023", "dum_covid_cpr", "dum_covid_avh"
  )
  history_part <- history %>%
    dplyr::select(-dplyr::any_of(deterministic)) %>%
    dplyr::mutate(
      period = "Actual",
      GapAvh = (Lur - LurHpf) / Lur,
      FiscalCovered = CgovNom + Pinonmin * (Igov + Ipubent) + Ytsf - Ttot,
      XsvcNom = XtotNom - XminNom - XagrNom - XothNom,
      YgovIvtNom = YgdpNom + MtotNom - CprNom - CgovNom - IdwellNom -
        IotcNom - IminNom - InonminNom - XtotNom,
      YgdpAnnualGrowth = 100 * (Ygdp / dplyr::lag(Ygdp, 4) - 1),
      PcpiAnnualGrowth = 100 * (Pcpi / dplyr::lag(Pcpi, 4) - 1)
    ) %>%
    dplyr::filter(date < as.Date(origin))
  forecast_part <- forecast %>%
    dplyr::mutate(period = "Forecast")
  flat <- dplyr::bind_rows(
    dplyr::select(history_part, date, period, dplyr::everything()),
    dplyr::select(forecast_part, date, period, dplyr::everything())
  )

  workbook <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(workbook, "Data")
  openxlsx::writeData(workbook, "Data", flat)
  openxlsx::freezePane(workbook, "Data", firstRow = TRUE, firstActiveCol = 3)
  openxlsx::saveWorkbook(workbook, path, overwrite = TRUE)
  path
}

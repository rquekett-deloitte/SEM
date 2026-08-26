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

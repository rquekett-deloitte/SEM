# SEM to national Coredata name conversion and export.
#
# Maps SEM model variables onto the national Coredata naming conventions and
# writes the model's data (history plus forecast) as a Coredata-format
# workbook: one row per Coredata variable with its description and
# endogenous/exogenous classification, and one column per quarter - the same
# orientation as the "Coredata RAW" sheet of National Coredata.xlsx. The
# mapping lives in data-raw/sem_to_coredata.csv so it can be reviewed and
# extended; its status column separates direct mappings, derived ratios,
# items flagged for review, and Coredata variables with no SEM counterpart
# (which are listed for completeness but not exported).

read_coredata_mapping <- function(path = "data-raw/sem_to_coredata.csv") {
  mapping <- readr::read_csv(path, show_col_types = FALSE,
                             col_types = readr::cols(.default = "character"))
  required <- c("coredata_code", "description", "kind",
                "sem_expression", "status", "note")
  missing <- setdiff(required, names(mapping))
  if (length(missing)) {
    stop("Coredata mapping is missing columns: ", paste(missing, collapse = ", "))
  }
  if (anyDuplicated(mapping$coredata_code)) {
    stop("Coredata mapping has duplicate codes")
  }
  mapping
}

coredata_evaluate <- function(expression, flat) {
  if (!nzchar(expression)) return(NULL)
  if (expression %in% names(flat)) return(as.numeric(flat[[expression]]))
  # list2env with a base enclosure so arithmetic operators resolve.
  e <- list2env(as.list(flat), parent = baseenv())
  as.numeric(eval(parse(text = expression), envir = e))
}

# flat: the quarterly history-plus-forecast table (the same content the
# dashboard uses, including the period column). start_date follows the
# national Coredata convention (1980Q3); set it earlier to include the full
# SEM history from 1974Q3.
build_coredata_export <- function(flat,
                                   mapping = read_coredata_mapping(),
                                   path = "outputs/sem_coredata.xlsx",
                                   start_date = as.Date("1980-09-01")) {
  flat$date <- as.Date(flat$date)
  quarters <- sort(unique(flat$date[flat$date >= as.Date(start_date)]))
  flat <- flat[match(quarters, flat$date), , drop = FALSE]
  if (!nrow(flat)) stop("No data at or after the requested start date")

  exported <- mapping[mapping$status %in%
                        c("mapped", "derived", "needs-review"), , drop = FALSE]
  values <- lapply(seq_len(nrow(exported)), function(i) {
    series <- coredata_evaluate(exported$sem_expression[[i]], flat)
    if (is.null(series) || length(series) != nrow(flat)) {
      stop("Cannot evaluate the mapping for ", exported$coredata_code[[i]],
           ": ", exported$sem_expression[[i]])
    }
    series
  })
  names(values) <- exported$coredata_code

  coredata_sheet <- data.frame(
    variable_name = exported$coredata_code,
    description = exported$description,
    kind = exported$kind,
    check.names = FALSE
  )
  # Values come back as quarters x variables; the sheet layout is one row per
  # Coredata variable with the quarters across columns.
  value_block <- do.call(cbind, values)
  stopifnot(nrow(value_block) == nrow(flat), ncol(value_block) == nrow(exported))
  coredata_sheet <- cbind(coredata_sheet, t(value_block))
  names(coredata_sheet)[-(1:3)] <- format(quarters)

  workbook <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(workbook, "Coredata")
  openxlsx::writeData(workbook, "Coredata", coredata_sheet)
  openxlsx::freezePane(workbook, "Coredata", firstRow = TRUE, firstActiveCol = 4)
  openxlsx::addWorksheet(workbook, "Mapping")
  openxlsx::writeData(workbook, "Mapping", as.data.frame(mapping))
  openxlsx::saveWorkbook(workbook, path, overwrite = TRUE)

  cat("Coredata export written to", path, "-",
      nrow(exported), "variables,", length(quarters), "quarters",
      "(", format(quarters[1]), "to", format(quarters[length(quarters)]), ")\n" )
  invisible(path)
}

# Standalone execution: Rscript R/coredata_export.R rebuilds the Coredata
# workbook from the current flat output. run_model.R sets
# SEM_PIPELINE_SOURCING before source()ing this file, which keeps this block
# dormant inside the pipeline.
if (!exists("SEM_PIPELINE_SOURCING") || !isTRUE(SEM_PIPELINE_SOURCING)) {
  flat <- openxlsx::read.xlsx("outputs/model_results_flat.xlsx",
                              sheet = "Data", detectDates = TRUE)
  flat$date <- as.Date(flat$date)
  invisible(build_coredata_export(flat))
}

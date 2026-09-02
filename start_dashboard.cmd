@echo off
setlocal
title Scenario Economic Model Dashboard
pushd "%~dp0"

where Rscript >nul 2>nul
if errorlevel 1 (
  echo Rscript is required but was not found on PATH.
  echo Install R or add Rscript to PATH, then run this launcher again.
  pause
  exit /b 1
)

Rscript -e "options(repos = getOption('repos')); if (is.null(getOption('repos')) || length(getOption('repos')) < 1) options(repos = c(CRAN = 'https://cloud.r-project.org')); for (p in c('shiny', 'jsonlite', 'openxlsx')) if (!requireNamespace(p, quietly = TRUE)) install.packages(p); shiny::runApp('dashboard', launch.browser = TRUE)"

if errorlevel 1 (
  echo The dashboard failed to start. Check that the model outputs exist
  echo ^(run run_model.R first^) and see the message above.
  pause
)

popd
endlocal

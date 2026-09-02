# Scenario run wrapper, copied into each run directory by the dashboard.
# The dashboard spawns this with system2() (CreateProcess on Windows), which
# passes arguments correctly where a shell command line would mangle the
# quotes; this wrapper then runs the model run and records completion.
#
# Usage: Rscript runner.R <run_dir> <run_scenario.R> <root> <exogenous.csv> <shocks.csv>

args <- commandArgs(TRUE)
run_dir <- args[[1]]
run_scenario <- args[[2]]
root <- args[[3]]
exo <- args[[4]]
shocks <- args[[5]]

code <- tryCatch({
  system2(
    file.path(R.home("bin"), "Rscript"),
    c(shQuote(run_scenario), shQuote(root), shQuote(exo),
      shQuote(shocks), shQuote(run_dir)),
    stdout = file.path(run_dir, "stdout.log"),
    stderr = file.path(run_dir, "stderr.log")
  )
}, error = function(e) {
  writeLines(as.character(e), file.path(run_dir, "stderr.log"))
  1L
})

writeLines(if (isTRUE(code == 0)) "completed" else "failed",
           file.path(run_dir, "status.txt"))

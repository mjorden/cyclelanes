# Run cl_check_source() for every built-in source and write a Markdown
# report. Exit status 1 when any source has unmapped class values, so the
# check-sources workflow can open an issue. Usage:
#
#   Rscript inst/scripts/check-sources.R [report.md]

args <- commandArgs(trailingOnly = TRUE)
report <- if (length(args)) args[1] else "check-sources-report.md"

suppressPackageStartupMessages(library(cyclelanes))

cities <- cl_sources()$city
lines <- c(sprintf("Crosswalk check on %s UTC", format(Sys.time(), "%Y-%m-%d %H:%M", tz = "UTC")), "")
bad <- character()

for (city in cities) {
  res <- tryCatch(cl_check_source(city), error = function(e) e)
  if (inherits(res, "error")) {
    lines <- c(lines, sprintf("## %s: check failed", city), "", "```", conditionMessage(res), "```", "")
    bad <- c(bad, city)
    next
  }
  un <- res[res$status == "unmapped", , drop = FALSE]
  st <- res[res$status == "stale", , drop = FALSE]
  if (nrow(un)) {
    bad <- c(bad, city)
    lines <- c(lines, sprintf("## %s: %d unmapped class value%s", city, nrow(un), if (nrow(un) == 1) "" else "s"), "",
               "| value | features |", "|---|---|",
               sprintf("| %s | %s |", un$value, ifelse(is.na(un$n), "?", un$n)), "")
  } else {
    lines <- c(lines, sprintf("## %s: ok (%d classes mapped)", city, sum(res$status == "mapped")), "")
  }
  if (nrow(st)) {
    lines <- c(lines, sprintf("Stale crosswalk keys (no longer in the data): %s", paste(st$value, collapse = ", ")), "")
  }
}

writeLines(lines, report)
cat(paste(lines, collapse = "\n"), "\n")
if (length(bad)) {
  cat(sprintf("\nDRIFT in: %s\n", paste(bad, collapse = ", ")))
  quit(status = 1)
}

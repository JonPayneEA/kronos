#' Create a new kronos time recording project
#'
#' Called by RStudio when the user selects the kronos project template.
#' Writes the folder structure, a starter kronos.yml, a starter categories.csv,
#' and a weekly run script.
#'
#' @param path The path to the new project directory (supplied by RStudio)
#' @param ... Additional arguments from the RStudio template form (unused)
#' @noRd
kronos_project <- function(path, ...) {

  # Ensure the project directory exists
  dir.create(path, recursive = TRUE, showWarnings = FALSE)

  # Sub-folders
  dir.create(file.path(path, 'OTLs'),      showWarnings = FALSE)
  dir.create(file.path(path, 'Calendar'),  showWarnings = FALSE)
  dir.create(file.path(path, 'Config'),    showWarnings = FALSE)

  # Starter kronos.yml
  yml <- c(
    '# kronos configuration',
    '# Edit the paths below then run source("run_weekly.R")',
    '',
    paste0('categories: ', file.path(path, 'Config', 'categories.csv')),
    paste0('outCal:     ', file.path(path, 'Calendar', 'Calendar.xlsx')),
    paste0('pathOTL:    ', file.path(path, 'OTLs')),
    '',
    'split:',
    '  - Cap Skills',
    '  - FFIDP',
    '  - Reactive Forecasting',
    '',
    'weight:',
    '  - 1',
    '  - 2',
    '  - 1',
    '',
    '# contracted_hours: 7.4'
  )
  writeLines(yml, file.path(path, 'kronos.yml'))

  # Starter categories.csv
  kronos::createCatagsFile(path = file.path(path, 'Config'))

  # Weekly run script
  run_script <- c(
    'library(kronos)',
    '',
    '# Standard weekly run -- no arguments needed once kronos.yml is configured',
    'run_kronos()',
    '',
    '# To run for a specific week:',
    '# run_kronos(week_start = "2024-05-13")',
    '',
    '# To preview without exporting:',
    '# run_kronos(export = FALSE)',
    '',
    '# Flexi tracking:',
    '# otl  <- mergeOTL(folderOTL = "OTLs", category = "Config/categories.csv")',
    '# dts  <- read_daytypes("OTLs")',
    '# flex <- calculate_flexi(otl, dts)',
    '# plot_flexi(flex)'
  )
  writeLines(run_script, file.path(path, 'run_weekly.R'))

  # README
  readme <- c(
    '# kronos time recording project',
    '',
    '## Setup',
    '',
    '1. Edit `kronos.yml` with your file paths.',
    '2. Edit `Config/categories.csv` with your Oracle project codes.',
    '3. Ensure Power Automate is saving your weekly calendar export to `Calendar/Calendar.xlsx`.',
    '',
    '## Weekly workflow',
    '',
    '```r',
    'source("run_weekly.R")',
    '```',
    '',
    'That is all. The OTL form is written to the `OTLs/` folder.',
    '',
    '## Flexi tracking',
    '',
    'After several weeks of exports:',
    '',
    '```r',
    'library(kronos)',
    'otl  <- mergeOTL("OTLs", "Config/categories.csv")',
    'dts  <- read_daytypes("OTLs")',
    'flex <- calculate_flexi(otl, dts)',
    'plot_flexi(flex)',
    '```'
  )
  writeLines(readme, file.path(path, 'README.md'))

  invisible(path)
}

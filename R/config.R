# kronos: configuration file support
#
# run_kronos() is the single entry point for the standard weekly case.
# It reads all configuration from kronos.yml in the working directory
# and calls createTC() with no manual arguments needed.
#
# Exported functions:
#   run_kronos()       -- weekly runner from config file
#   write_kronos_yml() -- write a blank config file to the working directory


# ---- .read_config ----------------------------------------------------------

#' Read and validate a kronos.yml config file
#'
#' @param path Path to the yml file. Default: kronos.yml in getwd().
#' @return A named list of config values
#' @noRd
.read_config <- function(path = file.path(getwd(), 'kronos.yml')) {

  if (!file.exists(path)) {
    stop('kronos.yml not found at: ', path, '\n',
         '  Run write_kronos_yml() to create a starter config file, ',
         'then edit it with your paths and settings.')
  }

  cfg <- yaml::read_yaml(path)

  required_keys <- c('categories', 'outCal', 'split', 'weight', 'pathOTL')
  missing_keys  <- setdiff(required_keys, names(cfg))

  if (length(missing_keys) > 0L) {
    stop('kronos.yml is missing required keys: ',
         paste(missing_keys, collapse = ', '), '\n',
         '  Check your config file matches the expected format.\n',
         '  Run write_kronos_yml() to see a fresh example.')
  }

  if (length(cfg$split) != length(cfg$weight)) {
    stop('kronos.yml: split and weight must have the same number of entries.\n',
         '  split has ', length(cfg$split), ' entries; ',
         'weight has ', length(cfg$weight), '.')
  }

  cfg
}


# ---- run_kronos ------------------------------------------------------------

#' Run the weekly kronos pipeline from a config file
#'
#' Reads all configuration from \code{kronos.yml} in the working directory
#' and calls \code{createTC()}. This is the standard entry point for the
#' weekly time card workflow.
#'
#' To get started:
#' \enumerate{
#'   \item Run \code{write_kronos_yml()} to create a starter config file.
#'   \item Edit \code{kronos.yml} with your file paths and settings.
#'   \item Run \code{run_kronos()} each week.
#' }
#'
#' @param week_start The week of interest as "YYYY-MM-DD". Must be a Monday.
#'   If NULL (default), the most recently completed working week is used.
#' @param config     Path to the config file. Default: \code{kronos.yml} in
#'   the working directory.
#' @param export     If TRUE (default), writes the OTL CSV to the pathOTL
#'   specified in the config file.
#'
#' @return A data.table time card, invisibly
#' @export
#'
#' @importFrom yaml read_yaml
#'
#' @examples
#' \dontrun{
#' # Standard weekly run — no arguments needed
#' run_kronos()
#'
#' # Run for a specific week
#' run_kronos(week_start = '2024-05-13')
#'
#' # Preview without exporting
#' run_kronos(export = FALSE)
#' }
run_kronos <- function(week_start = NULL,
                       config     = file.path(getwd(), 'kronos.yml'),
                       export     = TRUE) {

  message('kronos: reading config from ', config)
  cfg <- .read_config(config)

  ts <- createTC(
    categories       = cfg$categories,
    outCal           = cfg$outCal,
    week_start       = week_start,
    split            = cfg$split,
    weight           = as.numeric(cfg$weight),
    pathOTL          = cfg$pathOTL,
    export           = export,
    contracted_hours = cfg$contracted_hours  # NULL if not set; uses default
  )

  invisible(ts)
}


# ---- write_kronos_yml ------------------------------------------------------

#' Write a starter kronos.yml config file
#'
#' Creates a \code{kronos.yml} template in the supplied folder. Edit the
#' resulting file with your actual file paths before running
#' \code{run_kronos()}.
#'
#' @param path Folder where the file should be written. Default: working
#'   directory.
#'
#' @return Invisibly returns the path to the written file
#' @export
#'
#' @examples
#' \dontrun{
#' write_kronos_yml()
#' # Then edit kronos.yml and run:
#' run_kronos()
#' }
write_kronos_yml <- function(path = getwd()) {

  if (!dir.exists(path)) {
    stop('Folder does not exist: ', path)
  }

  out_file <- file.path(path, 'kronos.yml')

  if (file.exists(out_file)) {
    stop('kronos.yml already exists at: ', out_file, '\n',
         '  Delete or rename it to create a fresh config.')
  }

  template <- c(
    '# kronos configuration file',
    '# Edit the paths and settings below, then run run_kronos() each week.',
    '',
    '# Path to your categories CSV file',
    'categories: C:/Users/yourname/Time/categories.csv',
    '',
    '# Path to the Power Automate calendar export (updated weekly)',
    'outCal: C:/Users/yourname/Time/Calendar.xlsx',
    '',
    '# Folder where OTL exports are saved',
    'pathOTL: C:/Users/yourname/Time/OTLs',
    '',
    '# Categories to distribute unallocated time across',
    'split:',
    '  - Cap Skills',
    '  - FFIDP',
    '  - Reactive Forecasting',
    '',
    '# Weights for each split category (same order as split)',
    '# Higher weight = larger share of unallocated time',
    'weight:',
    '  - 1',
    '  - 2',
    '  - 1',
    '',
    '# Contracted hours per day (default 7.4 if not set)',
    '# contracted_hours: 7.4'
  )

  writeLines(template, out_file)

  message('kronos: config file written to ', out_file)
  message('kronos: edit the file with your paths and settings, ',
          'then run run_kronos()')

  invisible(out_file)
}

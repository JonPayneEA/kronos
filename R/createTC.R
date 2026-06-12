#' @title Create time card
#'
#' @description Links a Power Automate Outlook calendar export to produce
#'   an Oracle OTL time card. The daily hours spreadsheet is optional:
#'   when omitted, a standard working day (07:48-15:12, 7.4 hours) is used
#'   as the default for each day, with overrides from all-day calendar events
#'   for leave, sick, flexi, and bank holidays.
#'
#' @param categories Path to the categories CSV file
#' @param outCal     Path to the Power Automate calendar export (xlsx)
#' @param week_start The week of interest as "YYYY-MM-DD". Must be a Monday.
#'   If NULL, the most recently completed working week is used.
#' @param split      Character vector of category names to distribute
#'   unallocated time across
#' @param weight     Numeric vector of weights for each split category,
#'   the same length as \code{split}
#' @param pathOTL    Folder path for OTL export. Required when export = TRUE.
#' @param export     If TRUE, writes the OTL CSV to pathOTL
#' @param daily      Deprecated. Path to the daily hours xlsx. When supplied,
#'   the spreadsheet is used as before. When NULL (default), the work week
#'   is generated from the calendar using standard-day defaults.
#' @param contracted_hours Standard contracted hours per day. Default 7.4.
#'   Overrides STANDARD_DAY_HRS when supplied.
#'
#' @return A data.table time card with one row per Code/Task/Type combination
#'   and one column per day of the week
#' @export
#'
#' @importFrom data.table as.data.table data.table fread setnames copy
#' @importFrom data.table rbindlist dcast setcolorder
#' @importFrom lubridate hms period_to_seconds
#' @importFrom readxl read_excel
#' @importFrom tools file_ext
#'
#' @examples
#' \dontrun{
#' # Calendar-driven (recommended — no daily hours spreadsheet needed)
#' tc <- createTC(
#'   categories = 'C:/Time/categories.csv',
#'   outCal     = 'C:/Time/Calendar.xlsx',
#'   week_start = '2023-05-22',
#'   split      = c('Cap Skills', 'FFIDP', 'Reactive Forecasting'),
#'   weight     = c(1, 2, 1),
#'   export     = FALSE
#' )
#'
#' # Legacy: daily hours spreadsheet supplied explicitly
#' tc <- createTC(
#'   categories = 'C:/Time/categories.csv',
#'   outCal     = 'C:/Time/Calendar.xlsx',
#'   week_start = '2023-05-22',
#'   split      = c('Cap Skills', 'FFIDP', 'Reactive Forecasting'),
#'   weight     = c(1, 2, 1),
#'   daily      = 'C:/Time/Daily_hours.xlsx',
#'   export     = FALSE
#' )
#' }
createTC <- function(categories      = NULL,
                     outCal          = NULL,
                     week_start      = NULL,
                     split           = NULL,
                     weight          = NULL,
                     pathOTL         = NULL,
                     export          = TRUE,
                     daily           = NULL,
                     contracted_hours = NULL) {

  # ---- Validate inputs ------------------------------------------------------

  if (is.null(categories)) stop('categories path must be supplied.')
  if (is.null(outCal))     stop('calendar export path (outCal) must be supplied.')
  if (is.null(split))      stop('split categories must be supplied.')
  if (is.null(weight))     stop('split weights must be supplied.')
  if (length(split) != length(weight)) {
    stop('split and weight must be the same length. ',
         'split has ', length(split), ' elements; ',
         'weight has ', length(weight), '.')
  }

  # Honour contracted_hours override
  if (!is.null(contracted_hours)) {
    if (!is.numeric(contracted_hours) || contracted_hours <= 0) {
      stop('contracted_hours must be a positive number.')
    }
    # Override the package constant for this run
    STANDARD_DAY_HRS <<- contracted_hours
    HALF_DAY_HRS     <<- contracted_hours / 2
    on.exit({
      STANDARD_DAY_HRS <<- 7.4
      HALF_DAY_HRS     <<- 3.7
    }, add = TRUE)
  }

  # Deprecation notice for daily parameter
  if (!is.null(daily)) {
    message('kronos: the `daily` parameter is deprecated and will be removed ',
            'in a future version.\n',
            '  Leave `daily` unset to use calendar-driven work week generation.')
  }

  # ---- Stage 1: resolve week ------------------------------------------------

  message('kronos: resolving week...')
  week_start <- .resolve_week(week_start)

  # ---- Stage 2: load inputs -------------------------------------------------

  message('kronos: loading categories...')
  catags <- .load_categories(categories)

  missing_tasks <- split[!split %in% catags$Categories]
  if (length(missing_tasks) > 0L) {
    stop('Tasks not found in categories file: ',
         paste0("'", missing_tasks, "'", collapse = ', '),
         '\nCheck that names match the Categories column exactly.')
  }
  message('kronos: all split tasks found in categories file')

  message('kronos: loading calendar...')
  cal <- .load_calendar(outCal, week_start)

  # ---- Stage 3: build / load work week -------------------------------------

  if (!is.null(daily)) {
    # Legacy path: daily hours spreadsheet supplied
    message('kronos: loading daily hours from spreadsheet...')
    daily_hours <- .load_daily_hours(daily)
    work_week   <- .process_work_week(daily_hours, week_start)

  } else {
    # Phase 5 path: generate work week from calendar + bank holiday feed
    message('kronos: generating work week from calendar...')
    bank_hols <- tryCatch(
      .fetch_bank_holidays(),
      error = function(e) {
        warning('Bank holiday fetch failed; continuing without automatic ',
                'bank holiday detection.\n',
                '  Add "Bank Holiday" all-day events to your calendar manually.')
        as.Date(character())
      }
    )
    # Load the full calendar (not just the week) for all-day event detection
    # .load_calendar already filtered to the week, so we use cal directly
    work_week <- .generate_work_week(cal, week_start, bank_hols)
  }

  # ---- Stage 4: sick and leave rows ----------------------------------------

  message('kronos: processing sick/leave...')
  sl_tc <- .process_sick_leave(work_week, catags)

  # ---- Stage 5: join all data -----------------------------------------------

  message('kronos: joining pipeline tables...')
  combined <- .join_pipeline(work_week, cal, catags, sl_tc)

  # ---- Stage 6: distribute all-day hours ------------------------------------

  message('kronos: distributing all-day hours...')
  combined <- .distribute_allday(combined, work_week)

  # ---- Stage 7: distribute excess hours ------------------------------------

  message('kronos: distributing excess hours...')
  combined <- .distribute_excess(combined, work_week, catags, split, weight)

  # ---- Stage 8: build time card --------------------------------------------

  message('kronos: building time card...')
  ts <- .build_timecard(combined)

  # ---- Stage 9: export OTL form --------------------------------------------

  .build_otl(ts, week_start, work_week, pathOTL, export)

  message('kronos: done')
  ts
}

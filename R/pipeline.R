# kronos: internal pipeline stage functions
#
# These functions are not exported. createTC() calls them in sequence.
# Each accepts and returns a data.table so stages are independently testable.


# ---- .resolve_week ---------------------------------------------------------

#' Resolve week_start to a validated Monday Date
#'
#' If week_start is NULL, derives the most recent completed working week.
#' Stops with a clear message if the supplied value is not a Monday.
#'
#' @param week_start Date, character "YYYY-MM-DD", or NULL
#' @return A single Date
#' @noRd
.resolve_week <- function(week_start) {

  if (is.null(week_start)) {
    recMons    <- rev(getRecentMondays())
    posit      <- which(Sys.Date() - recMons > 7)[1]
    week_start <- if (Sys.Date() - recMons[1] < 7) recMons[posit] else recMons[1]
    message('kronos: week_start not supplied -- using week commencing ',
            as.character(week_start))
  }

  week_start <- tryCatch(
    as.Date(week_start),
    error = function(e) {
      stop('week_start could not be parsed as a date. ',
           'Supply a Date object or a character string in "YYYY-MM-DD" format. ',
           'Received: ', week_start)
    }
  )

  if (weekdays(week_start) != 'Monday') {
    stop('week_start must be a Monday.\n',
         '  Supplied:  ', week_start, ' (', weekdays(week_start), ')\n',
         '  Tip: check your date or leave week_start = NULL to use last week.')
  }

  week_start
}


# ---- .load_categories ------------------------------------------------------

#' Load and validate the categories YAML file
#'
#' Reads a categories.yaml file and coerces it to a data.table.
#' Each entry under the top-level `categories` key becomes one row.
#' The `name` field maps to the `Categories` column.
#'
#' @param path Path to the categories YAML file
#' @return A data.table with columns Categories, Code, Task, Type, Description
#' @noRd
.load_categories <- function(path) {

  if (!file.exists(path)) {
    stop('Categories file not found.\n',
         '  Path supplied: ', path, '\n',
         '  Run createCatagsFile() to create a starter file.')
  }

  ext <- tools::file_ext(path)
  if (!ext %in% c('yaml', 'yml')) {
    stop('Categories file must be a YAML file (.yaml or .yml).\n',
         '  Supplied: ', path, '\n',
         '  Run createCatagsFile() to generate categories.yaml,\n',
         '  or rename your existing CSV to categories.yaml and convert\n',
         '  it to YAML format first.')
  }

  raw <- yaml::read_yaml(path)

  if (is.null(raw$categories)) {
    stop('Categories YAML file must have a top-level "categories:" key.\n',
         '  Path: ', path)
  }

  if (length(raw$categories) == 0L) {
    stop('Categories file contains no entries: ', path)
  }

  # Coerce list of entries to data.table
  # The YAML `name` field maps to the `Categories` column used throughout
  catags <- data.table::rbindlist(
    lapply(raw$categories, function(entry) {
      data.table::data.table(
        Categories  = as.character(entry$name        %||% NA),
        Description = as.character(entry$description %||% NA),
        Code        = as.character(entry$code        %||% NA),
        Task        = as.character(entry$task        %||% NA),
        Type        = as.character(entry$type        %||% NA),
        target_hours = as.numeric(entry$target_hours %||% NA)
      )
    }),
    fill = TRUE
  )

  required <- c('Categories', 'Code', 'Task', 'Type')
  missing  <- setdiff(required, colnames(catags))
  if (length(missing) > 0L) {
    stop('Categories YAML is missing required fields: ',
         paste(missing, collapse = ', '), '\n',
         '  Each entry must have: name, code, task, type')
  }

  if (nrow(catags) == 0L) {
    stop('Categories file contains no entries: ', path)
  }

  catags
}

# Null coalescing helper used in .load_categories
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x


# ---- .load_daily_hours -----------------------------------------------------

#' Load and parse the daily hours spreadsheet
#'
#' Reads the Excel file, coerces date and time columns, and drops unused
#' columns. Returns a data.table with one row per calendar day.
#'
#' @param path Path to the daily hours xlsx
#' @return A data.table with columns Day, Date, Type, Start, End, Lunch, Total
#' @noRd
.load_daily_hours <- function(path) {

  if (!file.exists(path)) {
    stop('Daily hours file not found.\n',
         '  Path supplied: ', path)
  }

  if (tools::file_ext(path) != 'xlsx') {
    stop('Daily hours file must be an xlsx spreadsheet.\n',
         '  Supplied: ', path)
  }

  # readxl is reliably noisy about column type coercion; suppress only here
  raw <- suppressMessages(
    suppressWarnings(readxl::read_excel(path))
  )

  required <- c('Day', 'Date', 'Type', 'Start', 'End', 'Lunch', 'Total')
  missing  <- setdiff(required, colnames(raw))
  if (length(missing) > 0L) {
    stop('Daily hours file is missing required columns: ',
         paste(missing, collapse = ', '), '\n',
         '  Found columns: ', paste(colnames(raw), collapse = ', '), '\n',
         '  Check the spreadsheet matches the expected format.')
  }

  if (nrow(raw) == 0L) {
    stop('Daily hours file contains no data rows: ', path)
  }

  dt <- data.table::as.data.table(raw)

  dt[, Date  := as.Date(Date)]
  dt[, Start := fixTimes(Date, Start)]
  dt[, End   := fixTimes(Date, End)]
  dt[, Lunch := toHours(toHMS(Lunch))]
  dt[, Total := toHours(toHMS(Total))]

  drop_cols <- intersect(c('Expected', 'Flexi'), colnames(dt))
  if (length(drop_cols) > 0L) dt[, (drop_cols) := NULL]

  dt
}


# ---- .load_calendar --------------------------------------------------------

#' Load and parse the Power Automate calendar export
#'
#' Reads the xlsx export, coerces datetime columns, calculates appointment
#' lengths, and unnests multi-category appointments into separate rows.
#'
#' @param path      Path to the calendar xlsx
#' @param week_start A Date; filters to the 7-day window from this date
#' @return A data.table with columns Date, Subject, Categories, StartDT,
#'   EndDT, Length, allDay
#' @noRd
.load_calendar <- function(path, week_start) {

  if (!file.exists(path)) {
    stop('Calendar file not found.\n',
         '  Path supplied: ', path, '\n',
         '  Check the Power Automate export ran successfully this week.')
  }

  if (tools::file_ext(path) != 'xlsx') {
    stop('Calendar file must be an xlsx from the Power Automate export.\n',
         '  Supplied: ', path, '\n',
         '  Raw Outlook .csv exports do not include correct timestamps ',
         'for recurring appointments.')
  }

  # readxl suppressed specifically for datetime column coercion noise
  raw <- suppressMessages(readxl::read_excel(path))
  cal <- data.table::as.data.table(raw)

  required_cal <- c('Start Time', 'End Time', 'Event', 'Categories', 'allDay')
  missing_cal  <- setdiff(required_cal, colnames(cal))
  if (length(missing_cal) > 0L) {
    stop('Calendar file is missing expected columns: ',
         paste(missing_cal, collapse = ', '), '\n',
         '  Found columns: ', paste(colnames(cal), collapse = ', '), '\n',
         '  Verify the Power Automate flow is exporting all required fields.')
  }

  cal[, Date    := as.Date(`Start Time`)]
  cal[, StartDT := as.POSIXct(`Start Time`, tz = 'Europe/London',
                               format = '%Y-%m-%dT%H:%M:%OS')]
  cal[, EndDT   := as.POSIXct(`End Time`, tz = 'Europe/London',
                               format = '%Y-%m-%dT%H:%M:%OS')]

  # Check datetime parsing succeeded
  n_bad_start <- sum(is.na(cal$StartDT))
  if (n_bad_start > 0L) {
    warning(n_bad_start, ' calendar event(s) have unparseable start times ',
            'and will be dropped. Check the Power Automate export format.')
    cal <- cal[!is.na(StartDT)]
  }

  # Freshness check: the file is an append log, so the most recent event
  # date tells us whether this week's data has landed. Checking the event
  # dates rather than the file modification time is more reliable --
  # OneDrive sync touches the modification timestamp independently.
  latest_event <- max(cal$Date, na.rm = TRUE)
  days_since   <- as.integer(Sys.Date() - latest_event)

  if (days_since > 14L) {
    warning('The most recent event in the calendar file is ',
            days_since, ' days old (', format(latest_event, '%d %b %Y'), ').\n',
            '  The Power Automate flow may not have appended this week.\n',
            '  Check the flow is active at: ',
            'https://make.powerautomate.com\n',
            '  Path: ', path)
  } else {
    message('kronos: calendar file is current -- latest event ',
            format(latest_event, '%d %b %Y'))
  }

  cal <- cal[StartDT >= week_start & StartDT < as.Date(week_start) + 7L]

  if (nrow(cal) == 0L) {
    message('kronos: no calendar events found for week commencing ', week_start,
            '\n  Check the Power Automate export covers this week.')
    return(data.table::data.table(
      Date       = as.Date(character()),
      Subject    = character(),
      Categories = character(),
      StartDT    = as.POSIXct(character()),
      EndDT      = as.POSIXct(character()),
      Length     = numeric(),
      allDay     = logical()
    ))
  }

  cal[, Length := as.numeric(difftime(EndDT, StartDT, units = 'secs')) / 3600]

  # Split multi-category appointments (comma-delimited in export)
  cal[, Categories := lapply(strsplit(Categories, ','), trimws)]
  cal[, n_cats     := lengths(Categories)]
  cal[, Length     := Length / n_cats]

  # Unnest: one row per category per appointment
  cal <- cal[, .(
    Date,
    Subject    = Event,
    Categories = unlist(Categories),
    StartDT,
    EndDT,
    Length,
    allDay
  ), by = seq_len(nrow(cal))][, seq_len := NULL]

  # Remove excluded categories and NAs
  n_before <- nrow(cal)
  cal <- cal[!Categories %in% EXCLUDED_CATEGORIES & !is.na(Categories)]
  n_excluded <- n_before - nrow(cal)
  if (n_excluded > 0L) {
    message('kronos: ', n_excluded,
            ' calendar row(s) excluded (Ignore & Leave / Duty / Holiday / NA)')
  }

  cal[]
}


# ---- .process_work_week ----------------------------------------------------

#' Filter daily hours to the working week and validate
#'
#' @param daily_hours data.table from .load_daily_hours()
#' @param week_start  A validated Monday Date
#' @return A data.table of 5-7 rows covering the working week
#' @noRd
.process_work_week <- function(daily_hours, week_start) {

  row <- which(daily_hours$Date == week_start & daily_hours$Day == 'Mon')

  if (is.integer0(row)) {
    available <- format(daily_hours$Date[daily_hours$Day == 'Mon'], '%Y-%m-%d')
    stop('week_start ', week_start, ' not found in daily hours spreadsheet.\n',
         '  Available Mondays in your file: ',
         paste(tail(available, 5L), collapse = ', '), '\n',
         '  Add this week to your daily hours spreadsheet, or choose ',
         'a different week_start.')
  }

  work_week <- daily_hours[Date >= week_start & Date <= as.Date(week_start) + 6L]

  message('kronos: ', nrow(work_week), ' day(s) found in working week')
  work_week
}


# ---- .process_sick_leave ---------------------------------------------------

#' Build the sick/leave time card rows
#'
#' Calculates correct hours for half-days and creates rows for leave, sick,
#' bank holidays, and other non-standard day types.
#'
#' @param work_week data.table from .process_work_week()
#' @param catags    data.table from .load_categories()
#' @return A data.table of sick/leave rows in the pipeline shape, or NULL
#' @noRd
.process_sick_leave <- function(work_week, catags) {

  sl_types <- c('Leave', 'Sick', 'Leave Half', 'Sick Half', 'Bank Holiday', 'Other')

  if (!any(work_week$Type %in% sl_types)) {
    message('kronos: no sick/leave days this week')
    return(NULL)
  }

  sleave <- data.table::copy(work_week)
  sleave[, Length := Total]

  half_rows <- which(sleave$Type %in% c('Leave Half', 'Sick Half'))

  for (i in half_rows) {
    actual_hrs <- as.numeric(
      difftime(sleave$End[i], sleave$Start[i], units = 'secs')
    ) / 3600

    sleave[i, Length := data.table::fcase(
      actual_hrs > HALF_DAY_HRS & actual_hrs < STANDARD_DAY_HRS,
        Total - actual_hrs,
      actual_hrs < HALF_DAY_HRS,
        Total - HALF_DAY_HRS,
      default = NA_real_
    )]

    if (is.na(sleave$Length[i])) {
      warning('Half-day hours on ', format(sleave$Date[i], '%Y-%m-%d'),
              ' could not be calculated from clock times ',
              '(', round(actual_hrs, 2), ' hrs recorded).\n',
              '  Expected between 0 and ', STANDARD_DAY_HRS, ' hours.\n',
              '  Check Start/End times in your daily hours spreadsheet.')
    }
  }

  sleave_tc <- sleave[Type %in% sl_types]
  sleave_tc[, allDay     := Length == STANDARD_DAY_HRS | Length == 0]
  sleave_tc[, dayType    := Type]
  sleave_tc[, Subject    := Type]
  sleave_tc[, Categories := Type]

  # Check all sick/leave types have matching categories
  unmatched <- setdiff(unique(sleave_tc$Categories), catags$Categories)
  if (length(unmatched) > 0L) {
    warning('The following day types have no matching entry in your ',
            'categories file and will have no OTL code assigned: ',
            paste0("'", unmatched, "'", collapse = ', '), '\n',
            '  Add these to your categories file to resolve.')
  }

  result <- catags[sleave_tc, on = c('Categories' = 'dayType'), nomatch = NA]

  keep <- c('Day', 'Date', 'dayType', 'Subject', 'Categories',
            'Total', 'Length', 'allDay', 'Code', 'Task', 'Type')
  result <- result[, intersect(keep, colnames(result)), with = FALSE]

  n_sl <- nrow(result)
  message('kronos: ', n_sl, ' sick/leave row(s) processed')
  result[]
}


# ---- .join_pipeline --------------------------------------------------------

#' Join the calendar, work week, and sick/leave tables
#'
#' Full-joins the work week to calendar events by date, then appends the
#' sick/leave rows and removes calendar entries that fall on full
#' leave/sick days.
#'
#' @param work_week  data.table from .process_work_week()
#' @param cal        data.table from .load_calendar()
#' @param catags     data.table from .load_categories()
#' @param sl_tc      data.table from .process_sick_leave(), or NULL
#' @return A combined data.table in the pipeline shape
#' @noRd
.join_pipeline <- function(work_week, cal, catags, sl_tc) {

  # Join calendar to time codes
  # Warn on unmatched categories so the user knows before submission
  if (nrow(cal) > 0L) {
    unmatched_cats <- setdiff(unique(cal$Categories), catags$Categories)
    if (length(unmatched_cats) > 0L) {
      warning('The following calendar categories have no match in your ',
              'categories file and will be dropped from the time card:\n',
              paste0('  - ', unmatched_cats, collapse = '\n'), '\n',
              '  Check that Outlook colour category names match the ',
              'Categories column in your categories file exactly ',
              '(case and spacing matter).')
    }
  }

  cal_codes <- catags[cal, on = 'Categories', nomatch = NA]

  ww <- data.table::copy(work_week)
  data.table::setnames(ww, 'Type', 'dayType')

  all <- merge(ww, cal_codes, by = 'Date', all = TRUE)

  keep <- c('Day', 'Date', 'dayType', 'Subject', 'Categories',
            'Total', 'Length', 'allDay', 'Code', 'Task', 'Type')
  all  <- all[, intersect(keep, colnames(all)), with = FALSE]

  combined <- if (!is.null(sl_tc)) {
    data.table::rbindlist(list(all, sl_tc), fill = TRUE)
  } else {
    all
  }

  # Remove calendar entries on full sick/leave/bank holiday days
  sl_rows <- which(
    combined$allDay == TRUE &
    ((combined$dayType == 'Sick'         & combined$Subject == 'Sick')         |
     (combined$dayType == 'Leave'        & combined$Subject == 'Leave')        |
     (combined$dayType == 'Other'        & combined$Subject == 'Other')        |
     (combined$dayType == 'Bank Holiday' & combined$Subject == 'Bank Holiday'))
  )

  if (!is.integer0(sl_rows)) {
    sl_dates <- combined$Date[sl_rows]
    n_removed <- sum(combined$Date %in% sl_dates) - length(sl_rows)
    if (n_removed > 0L) {
      message('kronos: ', n_removed,
              ' calendar appointment(s) removed on sick/leave day(s)')
    }
    combined <- data.table::rbindlist(list(
      combined[!Date %in% sl_dates],
      combined[sl_rows]
    ), fill = TRUE)
  }

  combined[]
}


# ---- .distribute_allday ----------------------------------------------------

#' Distribute all-day appointment hours across the working day
#'
#' All-day events in the calendar have no fixed hour count. This function
#' calculates the hours not covered by timed appointments on each day and
#' assigns that remainder to all-day events, split equally when multiple
#' all-day events fall on the same day.
#'
#' @param combined   data.table from .join_pipeline()
#' @param work_week  data.table from .process_work_week()
#' @return A data.table with all-day rows replaced by hour-assigned rows
#' @noRd
.distribute_allday <- function(combined, work_week) {

  ad_rows <- which(combined$allDay == TRUE & combined$dayType == 'Standard')

  if (is.integer0(ad_rows)) {
    message('kronos: no all-day appointments to distribute')
    return(combined)
  }

  message('kronos: distributing ', length(ad_rows), ' all-day appointment(s)')

  cal_hours <- combined[-ad_rows][
    , .(calHours = sum(Length, na.rm = TRUE)), by = .(Day, Date)
  ]

  ad     <- combined[ad_rows]
  multi  <- ad[, .(n = .N), by = .(Day, Date)]

  ww_summary <- data.table::copy(work_week)
  data.table::setnames(ww_summary, 'Type', 'dayType')
  ww_summary <- ww_summary[, .(Day, Date, dayType, Total)]

  ww_summary <- cal_hours[ww_summary, on = c('Day', 'Date')]
  ww_summary[is.na(calHours), calHours := 0]
  ww_summary[, Excess := Total - calHours]
  ww_summary[, Total  := NULL]

  ad_cor <- multi[ad, on = c('Day', 'Date')]
  ad_cor <- ww_summary[ad_cor, on = c('Day', 'Date', 'dayType')]
  ad_cor[, Length              := Excess / n]
  ad_cor[, c('n', 'calHours', 'Excess') := NULL]

  result <- data.table::rbindlist(
    list(combined[-ad_rows], ad_cor),
    fill = TRUE
  )

  result[]
}


# ---- .distribute_excess ----------------------------------------------------

#' Distribute unallocated hours across split categories
#'
#' Any hours not covered by calendar appointments are distributed across the
#' user-supplied split categories in proportion to their weights.
#' The allocation is deterministic: weights are normalised, hours rounded to
#' 0.1, and any rounding residual is added to the largest bucket.
#'
#' @param combined   data.table from .distribute_allday()
#' @param work_week  data.table from .process_work_week()
#' @param catags     data.table from .load_categories()
#' @param split      Character vector of category names
#' @param weight     Numeric vector of weights, same length as split
#' @return A data.table with padding rows appended
#' @noRd
.distribute_excess <- function(combined, work_week, catags, split, weight) {

  na_rows <- which(
    combined$dayType == 'Standard' &
    is.na(combined$Categories) &
    is.na(combined$Length)
  )
  if (!is.integer0(na_rows)) combined[na_rows, Length := 0]

  final_sum <- combined[
    , .(Hours = mean(Total, na.rm = TRUE), calTotal = sum(Length, na.rm = TRUE)),
    by = .(Day, Date, dayType)
  ]
  final_sum[, Excess := Hours - calTotal]
  final_sum <- final_sum[Excess > 0.001]

  if (nrow(final_sum) == 0L) {
    message('kronos: calendar fills all contracted hours -- no excess to distribute')
    return(combined)
  }

  total_excess <- round(sum(final_sum$Excess), 2)
  message('kronos: distributing ', total_excess,
          ' excess hour(s) across ', length(split), ' split categorie(s)')

  props   <- weight / sum(weight)
  padding_rows <- vector('list', nrow(final_sum))

  for (i in seq_len(nrow(final_sum))) {
    excess  <- final_sum$Excess[i]
    lengths <- round(props * excess, 1)
    diff    <- round(excess - sum(lengths), 1)
    lengths[which.max(lengths)] <- lengths[which.max(lengths)] + diff

    padding_rows[[i]] <- data.table::data.table(
      Day        = final_sum$Day[i],
      Date       = final_sum$Date[i],
      dayType    = final_sum$dayType[i],
      Subject    = split,
      Categories = split,
      Total      = final_sum$Hours[i],
      Length     = lengths,
      allDay     = FALSE
    )
  }

  padding <- data.table::rbindlist(padding_rows)
  cat_pad <- catags[padding, on = 'Categories', nomatch = NA]
  if ('Description' %in% colnames(cat_pad)) cat_pad[, Description := NULL]

  data.table::rbindlist(list(combined, cat_pad), fill = TRUE)[]
}


# ---- .build_timecard -------------------------------------------------------

#' Pivot the combined table into the OTL wide format
#'
#' @param combined data.table from .distribute_excess()
#' @return A data.table with one row per Code/Task/Type and day columns
#' @noRd
.build_timecard <- function(combined) {

  combined[, hoursType := '']

  day_order <- c('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')

  ts <- data.table::dcast(
    combined[!is.na(Code)],
    Code + Task + Type + hoursType ~ Day,
    value.var     = 'Length',
    fun.aggregate = sum,
    fill          = 0
  )

  missing_days <- setdiff(day_order, colnames(ts))
  if (length(missing_days) > 0L) ts[, (missing_days) := 0]

  fixed_cols <- c('Code', 'Task', 'Type', 'hoursType')
  day_cols   <- intersect(day_order, colnames(ts))
  data.table::setcolorder(ts, c(fixed_cols, day_cols))

  ts <- stats::na.omit(ts)

  message('kronos: time card has ', nrow(ts), ' row(s)')
  ts[]
}


# ---- .build_otl ------------------------------------------------------------

#' Build the Oracle OTL matrix and optionally write to disk
#'
#' Writes two files when export = TRUE:
#'   OTL_wc_YYYY_MM_DD.csv            -- the Oracle time card
#'   OTL_wc_YYYY_MM_DD_daytypes.csv   -- companion day-type file for flexi tracking
#'
#' @param ts         data.table from .build_timecard()
#' @param week_start A Date
#' @param work_week  data.table from .generate_work_week() or .process_work_week()
#' @param pathOTL    Output folder path
#' @param export     Logical; if TRUE writes both CSV files
#' @return Invisibly returns the OTL output path if export is TRUE, else NULL
#' @noRd
.build_otl <- function(ts, week_start, work_week, pathOTL, export) {

  if (!export) return(invisible(NULL))

  if (is.null(pathOTL)) {
    stop('pathOTL must be supplied when export = TRUE.')
  }
  if (!dir.exists(pathOTL)) {
    stop('pathOTL folder does not exist: ', pathOTL, '\n',
         '  Create the folder first, or supply a different path.')
  }

  neo <- matrix(data = '', nrow = OTL_MATRIX_ROWS, ncol = OTL_MATRIX_COLS)

  # ---- Pre-submission validation report ------------------------------------
  #
  # Printed before writing so the user can verify before the file lands.
  # Does not stop execution — surfacing issues is the goal, not blocking.

  day_order   <- c('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')
  day_cols    <- intersect(day_order, colnames(ts))
  day_totals  <- colSums(ts[, day_cols, with = FALSE])

  contracted  <- STANDARD_DAY_HRS
  ww_std      <- work_week[!Type %in% NEUTRAL_DAY_TYPES & Type != 'Weekend']

  cat('\n', strrep('-', 52), '\n', sep = '')
  cat(' kronos: pre-submission validation\n')
  cat(' Week commencing: ', format(week_start, '%d %B %Y'), '\n', sep = '')
  cat(strrep('-', 52), '\n\n', sep = '')

  # Hours by day
  cat(sprintf(' %-4s  %-14s  %7s  %s\n', 'Day', 'Type', 'Hours', 'Status'))
  cat(' ', strrep('-', 48), '\n', sep = '')

  for (i in seq_along(day_order)) {
    day   <- day_order[i]
    hrs   <- if (day %in% names(day_totals)) day_totals[[day]] else 0
    dtype <- work_week[Day == day, Type]
    if (length(dtype) == 0L) dtype <- '-'

    status <- if (dtype %in% c('Weekend')) {
      ''
    } else if (dtype %in% NEUTRAL_DAY_TYPES) {
      dtype
    } else if (abs(hrs - contracted) <= 0.05) {
      'OK'
    } else if (hrs > contracted) {
      paste0('LONG (+', round(hrs - contracted, 1), ' hrs)')
    } else {
      paste0('SHORT (', round(hrs - contracted, 1), ' hrs)')
    }

    cat(sprintf(' %-4s  %-14s  %7.1f  %s\n', day, dtype, hrs, status))
  }

  # Unmatched categories
  ts_cats   <- ts$Code
  na_rows   <- sum(is.na(ts_cats) | ts_cats == '')
  if (na_rows > 0L) {
    cat('\n WARNING:', na_rows,
        'row(s) have no OTL code and will be excluded from the export.\n')
    cat('  Check that all Outlook colour categories appear in categories.csv.\n')
  }

  total_hrs <- sum(day_totals[!names(day_totals) %in% c('Sat', 'Sun')])
  cat('\n Total working hours recorded: ', round(total_hrs, 1), '\n', sep = '')
  cat(strrep('-', 52), '\n\n', sep = '')

  neo[OTL_ROW_TITLE,           1] <- 'ORACLE TIME & LABOR'
  neo[OTL_ROW_TEMPLATE_NAME,   2] <- 'Template Name : ABC'

  neo[OTL_ROWS_HEADER_INSTRUCT, 2] <- c(
    'In the START_HEADER - STOP_HEADER section you can:',
    ' 1. Select an overriding approver from the POSSIBLE VALUES list.',
    ' 2. Enter comments being careful not to use a comma - enclose all details containing comma within double quotes.'
  )

  neo[OTL_ROW_TEMPLATE_INSTRUCT, 1] <- 'In the START_TEMPLATE - STOP_TEMPLATE section you can:'

  neo[OTL_ROWS_TEMPLATE_INSTRUCT, 2] <- c(
    ' 1. Delete an entire timecard line entry. Use the delete line function in the spreadsheet.',
    ' 2. Modify/Edit an hours entered.  Make your entry in the appropriate cell.',
    ' 3. Insert a new entry - above the STOP_TEMPLATE (reserved line).  ',
    '    Use the insert line function in the spreadsheet.',
    ' 4. Select POSSIBLE VALUES corresponding to the appropriate column headings.',
    ' 5. Enter comments being careful not to use a comma - enclose all details containing comma within double quotes.'
  )

  neo[OTL_ROWS_DONOT, 2] <- c(
    ' DO NOT Make entries outside of the START_HEADER - STOP_HEADER or ',
    ' START_TEMPLATE - STOP_TEMPLATE section.',
    ' DO NOT delete/edit the ORACLE RESERVED section.'
  )

  neo[OTL_ROW_START_HEADER,   1] <- 'START_HEADER'
  neo[OTL_ROW_STOP_HEADER,    1] <- 'STOP_HEADER'
  neo[OTL_ROW_START_TEMPLATE, 1] <- 'START_TEMPLATE'

  neo[OTL_ROW_COL_HEADERS, 1:12] <- c(
    'Project/ABC Code', 'Task', 'Type', 'Hours Type',
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    'END_COLUMN'
  )

  ts_mat   <- as.matrix(ts)
  n_rows   <- nrow(ts_mat)
  data_end <- OTL_ROW_DATA_START + n_rows - 1L

  neo[OTL_ROW_DATA_START:data_end, 1:11] <- ts_mat
  neo[OTL_ROW_COL_HEADERS, 12] <- 'END_COLUMN'

  stop_row <- data_end + 2L
  neo[stop_row, 1] <- 'STOP_TEMPLATE'
  neo[(stop_row + 2L):(stop_row + 10L), 1] <- OTL_RESERVED_LINES
  neo[(stop_row + 10L), 2] <- 'END'

  week_str <- gsub('-', '_', week_start)
  out_path <- file.path(pathOTL, paste0('OTL_wc_', week_str, '.csv'))

  write.table(neo,
              file      = out_path,
              row.names = FALSE,
              col.names = FALSE,
              sep       = ',')

  message('kronos: OTL form written to ', out_path)

  # Write companion day-type file for flexi tracking
  daytypes_path <- file.path(
    pathOTL,
    paste0('OTL_wc_', week_str, DAYTYPES_SUFFIX)
  )

  day_type_tbl <- work_week[, .(Date, DayType = Type)]
  data.table::fwrite(day_type_tbl, daytypes_path)
  message('kronos: day-type companion file written to ', daytypes_path)

  invisible(out_path)
}


# ---- .fetch_bank_holidays --------------------------------------------------

#' Fetch UK bank holidays from the Cabinet Office JSON feed
#'
#' Downloads the England bank holiday list once per year and caches it
#' locally in the user's kronos cache directory. Subsequent calls within
#' the same calendar year use the cache.
#'
#' @param force_refresh If TRUE, ignores the cache and re-downloads.
#' @return A Date vector of England bank holidays
#' @noRd
.fetch_bank_holidays <- function(force_refresh = FALSE) {

  use_cache <- !force_refresh &&
    file.exists(BANK_HOLIDAY_CACHE) &&
    as.integer(format(file.mtime(BANK_HOLIDAY_CACHE), '%Y')) ==
      as.integer(format(Sys.Date(), '%Y'))

  if (use_cache) {
    cached <- readRDS(BANK_HOLIDAY_CACHE)
    message('kronos: using cached bank holidays (',
            length(cached), ' dates)')
    return(cached)
  }

  message('kronos: fetching bank holidays from ', BANK_HOLIDAY_URL, '...')

  bh <- tryCatch({
    raw   <- readLines(BANK_HOLIDAY_URL, warn = FALSE)
    data  <- jsonlite::fromJSON(paste(raw, collapse = ''))
    dates <- as.Date(data[['england-and-wales']][['events']][['date']])
    dates
  }, error = function(e) {
    warning('Could not fetch bank holidays: ', conditionMessage(e), '\n',
            '  Bank holidays will not be automatically detected this run.\n',
            '  Add "Bank Holiday" as an all-day calendar event to handle ',
            'them manually.')
    return(as.Date(character()))
  })

  if (length(bh) > 0L) {
    cache_dir <- dirname(BANK_HOLIDAY_CACHE)
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
    saveRDS(bh, BANK_HOLIDAY_CACHE)
    message('kronos: cached ', length(bh), ' bank holiday dates')
  }

  bh
}


# ---- .generate_work_week ---------------------------------------------------

#' Generate the work-week table from the calendar alone
#'
#' Builds a 7-row table (Mon-Sun) using standard-day defaults.
#' All-day calendar events override the day type and hours for leave, sick,
#' flexi, and bank holidays. Bank holidays from the Cabinet Office feed are
#' also applied automatically.
#'
#' This replaces .load_daily_hours() + .process_work_week() when the
#' \code{daily} parameter is not supplied to createTC().
#'
#' Default working day:
#'   Start: 07:48, End: 15:12, Lunch: 37 min, Net: 7.4 hours
#'
#' @param cal        data.table from .load_calendar() (full calendar, not
#'                   filtered — all-day events may span days)
#' @param week_start A validated Monday Date
#' @param bank_hols  Date vector of bank holidays (from .fetch_bank_holidays())
#' @return A data.table in the same shape as .load_daily_hours() output:
#'   Day, Date, Type, Start, End, Lunch, Total
#' @noRd
.generate_work_week <- function(cal, week_start, bank_hols = as.Date(character())) {

  days     <- c('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')
  dates    <- week_start + 0:6
  weekend  <- c(6L, 7L)  # Sat, Sun positions (1-indexed)

  # Build skeleton with standard-day defaults
  ww <- data.table::data.table(
    Day   = days,
    Date  = dates,
    Type  = 'Standard',
    Start = as.POSIXct(paste(dates, DEFAULT_START), tz = 'Europe/London'),
    End   = as.POSIXct(paste(dates, DEFAULT_END),   tz = 'Europe/London'),
    Lunch = DEFAULT_LUNCH_HRS,
    Total = STANDARD_DAY_HRS
  )

  # Weekend rows: zero everything
  ww[Day %in% c('Sat', 'Sun'),
     `:=`(Type  = 'Weekend',
          Start = NA_POSIXct_,
          End   = NA_POSIXct_,
          Lunch = 0,
          Total = 0)]

  # Bank holidays from feed: override before calendar (calendar takes final
  # precedence if both apply)
  bh_in_week <- bank_hols[bank_hols %in% dates]
  if (length(bh_in_week) > 0L) {
    ww[Date %in% bh_in_week,
       `:=`(Type  = 'Bank Holiday',
            Start = NA_POSIXct_,
            End   = NA_POSIXct_,
            Lunch = 0,
            Total = 0)]
    message('kronos: ', length(bh_in_week),
            ' bank holiday(s) applied from Cabinet Office feed')
  }

  # All-day calendar events override day type
  if (nrow(cal) > 0L) {
    allday_cal <- cal[allDay == TRUE & Date %in% dates]

    if (nrow(allday_cal) > 0L) {
      for (i in seq_len(nrow(allday_cal))) {
        cat_name <- allday_cal$Categories[i]
        event_dt <- allday_cal$Date[i]

        override <- ALLDAY_TYPE_MAP[[cat_name]]

        if (!is.null(override)) {
          ww[Date == event_dt,
             `:=`(Type  = override$type,
                  Start = NA_POSIXct_,
                  End   = NA_POSIXct_,
                  Lunch = 0,
                  Total = override$hours)]
          message('kronos: ', format(event_dt, '%a %d %b'),
                  ' set to ', override$type,
                  ' (', override$hours, ' hrs) from calendar')
        }
      }
    }
  }

  # Long-day override: if timed appointments on a standard day sum to
  # more than contracted hours, use the actual calendar total
  if (nrow(cal) > 0L) {
    timed_cal <- cal[allDay == FALSE & Date %in% dates]
    if (nrow(timed_cal) > 0L) {
      day_totals <- timed_cal[, .(calTotal = sum(Length)), by = Date]
      for (i in seq_len(nrow(day_totals))) {
        dt       <- day_totals$Date[i]
        cal_hrs  <- day_totals$calTotal[i]
        day_type <- ww[Date == dt, Type]
        if (day_type == 'Standard' && cal_hrs > STANDARD_DAY_HRS) {
          ww[Date == dt, Total := round(cal_hrs, 1)]
          message('kronos: ', format(dt, '%a %d %b'),
                  ' extended to ', round(cal_hrs, 1),
                  ' hrs (calendar exceeds contracted hours)')
        }
      }
    }
  }

  ww[]
}

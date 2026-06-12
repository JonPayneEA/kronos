# kronos: package-level constants
#
# All magic numbers and fixed strings are defined here.
# Any change to contracted hours, the Oracle template layout, or
# the standard working day defaults should be made in this file.

# ---- Working day defaults --------------------------------------------------

#' Standard contracted hours per day
#' @noRd
STANDARD_DAY_HRS <- 7.4

#' Half-day hours
#' @noRd
HALF_DAY_HRS <- 3.7

#' Default start time for a standard working day
#' @noRd
DEFAULT_START <- "07:48:00"

#' Default end time for a standard working day
#' @noRd
DEFAULT_END <- "15:12:00"

#' Default lunch duration in hours
#' @noRd
DEFAULT_LUNCH_HRS <- 37 / 60


# ---- Oracle OTL template ---------------------------------------------------
#
# Row positions and boilerplate strings for the Oracle Time & Labour CSV
# format. Extracted here so .build_otl() contains no magic numbers.

#' Number of rows in the OTL matrix
#' @noRd
OTL_MATRIX_ROWS <- 100L

#' Number of columns in the OTL matrix
#' @noRd
OTL_MATRIX_COLS <- 12L

#' Row index of the OTL header title
#' @noRd
OTL_ROW_TITLE <- 1L

#' Row index of the template name line
#' @noRd
OTL_ROW_TEMPLATE_NAME <- 3L

#' Row range for header instructions
#' @noRd
OTL_ROWS_HEADER_INSTRUCT <- 5:7

#' Row index for template instructions header
#' @noRd
OTL_ROW_TEMPLATE_INSTRUCT <- 9L

#' Row range for template instructions body
#' @noRd
OTL_ROWS_TEMPLATE_INSTRUCT <- 10:15

#' Row range for DO NOT instructions
#' @noRd
OTL_ROWS_DONOT <- 17:19

#' Row index of START_HEADER marker
#' @noRd
OTL_ROW_START_HEADER <- 22L

#' Row index of STOP_HEADER marker
#' @noRd
OTL_ROW_STOP_HEADER <- 25L

#' Row index of START_TEMPLATE marker
#' @noRd
OTL_ROW_START_TEMPLATE <- 28L

#' Row index of the column header row
#' @noRd
OTL_ROW_COL_HEADERS <- 29L

#' Row index where data rows begin
#' @noRd
OTL_ROW_DATA_START <- 30L

#' Oracle reserved section lines (9 lines starting at STOP_TEMPLATE + 2)
#' @noRd
OTL_RESERVED_LINES <- c(
  '###############################',
  'ORACLE RESERVED SECTION',
  '###############################',
  '',
  'START_ORACLE',
  'A|PROJECTS|Attribute1|A|PROJECTS|Attribute2|A|PROJECTS|Attribute3|A|OTL_ALIAS_1|Attribute1|D|D|D|D|D|D|D|',
  '321070',
  'NO_HEADER',
  'STOP_ORACLE'
)

#' Day types that produce zero OTL hours
#' @noRd
ZERO_HOUR_DAY_TYPES <- c('Leave', 'Sick', 'Bank Holiday', 'Flexi',
                          'Leave Half', 'Sick Half', 'Flexi Half', 'Weekend')

#' Categories to exclude from calendar processing
#' @noRd
EXCLUDED_CATEGORIES <- c('Ignore & Leave', 'Duty', 'Holiday')


# ---- Phase 5: calendar-as-source-of-truth ----------------------------------

#' Day type lookup: all-day calendar category -> day type and hours
#'
#' Named list; each entry has `type` (day type string) and `hours` (numeric).
#' Half-day entries use HALF_DAY_HRS; zero-hour entries use 0.
#' @noRd
ALLDAY_TYPE_MAP <- list(
  'Annual Leave'  = list(type = 'Leave',       hours = 0),
  'Leave'         = list(type = 'Leave',       hours = 0),
  'Leave Half'    = list(type = 'Leave Half',  hours = HALF_DAY_HRS),
  'Leave Half AM' = list(type = 'Leave Half',  hours = HALF_DAY_HRS),
  'Leave Half PM' = list(type = 'Leave Half',  hours = HALF_DAY_HRS),
  'Flexi'         = list(type = 'Flexi',       hours = 0),
  'Flexi Half'    = list(type = 'Flexi Half',  hours = HALF_DAY_HRS),
  'Flexi Half AM' = list(type = 'Flexi Half',  hours = HALF_DAY_HRS),
  'Flexi Half PM' = list(type = 'Flexi Half',  hours = HALF_DAY_HRS),
  'Sick'          = list(type = 'Sick',        hours = 0),
  'Sick Half'     = list(type = 'Sick Half',   hours = HALF_DAY_HRS),
  'Bank Holiday'  = list(type = 'Bank Holiday',hours = 0)
)

#' URL for the Cabinet Office bank holiday JSON feed
#' @noRd
BANK_HOLIDAY_URL <- 'https://www.gov.uk/bank-holidays.json'

#' Local cache path for bank holiday data
#' @noRd
BANK_HOLIDAY_CACHE <- file.path(
  tools::R_user_dir('kronos', which = 'cache'),
  'bank_holidays.rds'
)


# ---- Phase 6: flexi tracking -----------------------------------------------

#' Day types that count as zero contracted hours (no flexi delta)
#' @noRd
NEUTRAL_DAY_TYPES <- c('Leave', 'Leave Half', 'Sick', 'Sick Half',
                        'Bank Holiday', 'Flexi', 'Flexi Half', 'Weekend')

#' Companion day-type file suffix (sits alongside each OTL export)
#' @noRd
DAYTYPES_SUFFIX <- '_daytypes.csv'

#' EA flexi carry-forward limits in hours
#' @noRd
FLEXI_MAX_CARRY  <-  10.0
FLEXI_MIN_CARRY  <- -10.0

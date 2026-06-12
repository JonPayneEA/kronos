# kronos: flexi tracking
#
# Three public functions:
#   calculate_flexi()  -- calculates daily flexi deltas and running balance
#   plot_flexi()       -- plots the running balance over time
#   read_daytypes()    -- reads all companion day-type files from an OTL folder


# ---- read_daytypes ---------------------------------------------------------

#' Read companion day-type files from an OTL folder
#'
#' Each week's OTL export is accompanied by a `_daytypes.csv` file written
#' by createTC(). This function reads all of them from the supplied folder
#' and returns a single data.table.
#'
#' @param folderOTL Folder containing OTL exports and companion files
#' @return A data.table with columns Date (Date) and DayType (character)
#' @export
#'
#' @examples
#' \dontrun{
#' dt <- read_daytypes('C:/Users/jpayne05/Time/OTLs')
#' }
read_daytypes <- function(folderOTL) {

  if (!dir.exists(folderOTL)) {
    stop('Folder not found: ', folderOTL)
  }

  files <- list.files(folderOTL,
                      pattern    = paste0(DAYTYPES_SUFFIX, '$'),
                      full.names = TRUE)

  if (length(files) == 0L) {
    stop('No day-type companion files found in: ', folderOTL, '\n',
         '  These are written automatically by createTC() from kronos 0.4.0.',
         '\n  Older OTL exports will not have them.')
  }

  message('kronos: reading ', length(files), ' day-type file(s)')

  dt_list <- lapply(files, function(f) {
    dt <- data.table::fread(f, showProgress = FALSE)
    dt[, Date := as.Date(Date)]
    dt
  })

  result <- data.table::rbindlist(dt_list)
  data.table::setkeyv(result, 'Date')

  result[]
}


# ---- calculate_flexi -------------------------------------------------------

#' Calculate flexi balance from merged OTL data
#'
#' Sums recorded hours per day from a merged OTL table, joins to day types,
#' and calculates the daily flexi delta (actual hours minus contracted hours).
#' Days typed as Leave, Sick, Bank Holiday, Flexi taken, or Weekend
#' contribute zero delta.
#'
#' The running cumulative balance is returned in the `FlexiBalance` column.
#'
#' @param merged_otl  A data.table as returned by mergeOTL() with
#'                    aggregate = FALSE
#' @param day_types   A data.table as returned by read_daytypes(), with
#'                    columns Date and DayType. If NULL, all days are treated
#'                    as Standard.
#' @param contracted  Contracted hours per day. Default 7.4.
#'
#' @return A data.table with columns:
#'   Date, DayType, ActualHours, ContractedHours, FlexiDelta, FlexiBalance
#' @export
#'
#' @examples
#' \dontrun{
#' otl  <- mergeOTL(folderOTL = 'C:/Time/OTLs',
#'                  category  = 'C:/Time/categories.csv')
#' dts  <- read_daytypes('C:/Time/OTLs')
#' flex <- calculate_flexi(otl, dts)
#' flex
#' }
calculate_flexi <- function(merged_otl,
                             day_types  = NULL,
                             contracted = STANDARD_DAY_HRS) {

  if (!inherits(merged_otl, 'data.table')) {
    merged_otl <- data.table::as.data.table(merged_otl)
  }

  required <- c('Date', 'Hours')
  missing  <- setdiff(required, colnames(merged_otl))
  if (length(missing) > 0L) {
    stop('merged_otl is missing required columns: ',
         paste(missing, collapse = ', '), '\n',
         '  Pass the output of mergeOTL(aggregate = FALSE).')
  }

  if (!inherits(contracted, 'numeric') || contracted <= 0) {
    stop('contracted must be a positive number. Received: ', contracted)
  }

  # Sum all recorded hours per day
  daily <- merged_otl[, .(ActualHours = sum(Hours, na.rm = TRUE)), by = Date]
  data.table::setkeyv(daily, 'Date')

  # Join day types; default to Standard if not supplied or date not found
  if (!is.null(day_types)) {
    if (!inherits(day_types, 'data.table')) {
      day_types <- data.table::as.data.table(day_types)
    }
    missing_dt <- setdiff(c('Date', 'DayType'), colnames(day_types))
    if (length(missing_dt) > 0L) {
      stop('day_types is missing required columns: ',
           paste(missing_dt, collapse = ', '))
    }
    daily <- day_types[daily, on = 'Date']
    daily[is.na(DayType), DayType := 'Standard']
  } else {
    daily[, DayType := 'Standard']
    message('kronos: no day_types supplied -- all days treated as Standard')
  }

  # Calculate flexi delta
  # Neutral days contribute zero delta regardless of recorded hours
  daily[, ContractedHours := data.table::fifelse(
    DayType %in% NEUTRAL_DAY_TYPES,
    0,
    contracted
  )]

  daily[, FlexiDelta := ActualHours - ContractedHours]

  # Running balance
  data.table::setorder(daily, Date)
  daily[, FlexiBalance := cumsum(FlexiDelta)]

  # Warn if balance ever exceeds EA carry-forward limits
  max_bal <- max(daily$FlexiBalance)
  min_bal <- min(daily$FlexiBalance)

  if (max_bal > FLEXI_MAX_CARRY) {
    warning('Flexi balance exceeds maximum carry-forward (+', FLEXI_MAX_CARRY,
            ' hrs) on ', sum(daily$FlexiBalance > FLEXI_MAX_CARRY), ' day(s).\n',
            '  Peak balance: +', round(max_bal, 1), ' hrs.\n',
            '  Consider booking Flexi days to reduce the balance.')
  }
  if (min_bal < FLEXI_MIN_CARRY) {
    warning('Flexi balance falls below minimum carry-forward (',
            FLEXI_MIN_CARRY, ' hrs) on ',
            sum(daily$FlexiBalance < FLEXI_MIN_CARRY), ' day(s).\n',
            '  Lowest balance: ', round(min_bal, 1), ' hrs.')
  }

  message('kronos: flexi calculated for ', nrow(daily), ' day(s)')
  message('kronos: current balance: ',
          round(daily$FlexiBalance[nrow(daily)], 1), ' hrs')

  class(daily) <- c('flexiData', class(daily))
  daily[]
}


# ---- plot_flexi ------------------------------------------------------------

#' Plot the flexi balance over time
#'
#' Produces a line chart of the cumulative flexi balance with:
#'   - A reference line at zero
#'   - Optional dashed lines at the EA carry-forward limits (+/-10 hrs)
#'   - Colour fill above/below zero
#'
#' @param flexi_data  A data.table as returned by calculate_flexi()
#' @param limits      If TRUE, draws dashed lines at FLEXI_MAX_CARRY and
#'                    FLEXI_MIN_CARRY. Default TRUE.
#' @param title       Plot title. Default "Flexi balance".
#'
#' @return A ggplot2 object
#' @export
#'
#' @importFrom ggplot2 ggplot aes geom_line geom_ribbon geom_hline
#' @importFrom ggplot2 scale_colour_manual labs theme_minimal theme
#' @importFrom ggplot2 element_text element_blank
#'
#' @examples
#' \dontrun{
#' flex <- calculate_flexi(otl, dts)
#' plot_flexi(flex)
#' }
plot_flexi <- function(flexi_data,
                       limits = TRUE,
                       title  = 'Flexi balance') {

  if (!inherits(flexi_data, 'data.table')) {
    flexi_data <- data.table::as.data.table(flexi_data)
  }

  required <- c('Date', 'FlexiBalance')
  missing  <- setdiff(required, colnames(flexi_data))
  if (length(missing) > 0L) {
    stop('flexi_data is missing required columns: ',
         paste(missing, collapse = ', '), '\n',
         '  Pass the output of calculate_flexi().')
  }

  current_balance <- round(flexi_data$FlexiBalance[nrow(flexi_data)], 1)
  subtitle <- paste0('Current balance: ',
                     ifelse(current_balance >= 0,
                            paste0('+', current_balance),
                            as.character(current_balance)),
                     ' hrs')

  p <- ggplot2::ggplot(
    flexi_data,
    ggplot2::aes(x = Date, y = FlexiBalance)
  ) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = pmin(FlexiBalance, 0), ymax = 0),
      fill  = '#d73027',
      alpha = 0.15
    ) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = 0, ymax = pmax(FlexiBalance, 0)),
      fill  = '#4575b4',
      alpha = 0.15
    ) +
    ggplot2::geom_line(colour = '#2c3e50', linewidth = 0.8) +
    ggplot2::geom_hline(
      yintercept = 0,
      colour     = '#555555',
      linewidth  = 0.4
    )

  if (limits) {
    p <- p +
      ggplot2::geom_hline(
        yintercept = FLEXI_MAX_CARRY,
        linetype   = 'dashed',
        colour     = '#d73027',
        linewidth  = 0.4
      ) +
      ggplot2::geom_hline(
        yintercept = FLEXI_MIN_CARRY,
        linetype   = 'dashed',
        colour     = '#d73027',
        linewidth  = 0.4
      )
  }

  p +
    ggplot2::labs(
      title    = title,
      subtitle = subtitle,
      x        = NULL,
      y        = 'Hours'
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title    = ggplot2::element_text(face = 'bold'),
      plot.subtitle = ggplot2::element_text(colour = '#555555'),
      panel.grid.minor = ggplot2::element_blank()
    )
}

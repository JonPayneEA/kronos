# kronos: analysis functions
#
# Two exported functions beyond the base plot methods:
#   plot_timeseries()    -- hours per category over time (weekly or monthly)
#   compare_objectives() -- actuals vs target hours from categories file


# ---- plot_timeseries -------------------------------------------------------

#' Plot hours per category over time
#'
#' Produces a stacked area or bar chart of hours per category aggregated
#' by week or month. Useful for seeing how time allocation has shifted across
#' a quarter or year.
#'
#' @param merged_otl  A data.table as returned by \code{mergeOTL()}
#'                    with \code{aggregate = FALSE}
#' @param by          Aggregation period: \code{"week"} or \code{"month"}.
#'                    Default \code{"week"}.
#' @param type        Chart type: \code{"area"} or \code{"bar"}.
#'                    Default \code{"area"}.
#' @param title       Plot title. Default "Hours by category over time".
#'
#' @return A ggplot2 object
#' @export
#'
#' @importFrom ggplot2 ggplot aes geom_area geom_col scale_x_date labs
#' @importFrom ggplot2 theme_minimal theme element_text element_blank
#' @importFrom ggplot2 scale_fill_brewer guide_legend
#' @importFrom data.table copy
#'
#' @examples
#' \dontrun{
#' otl <- mergeOTL(folderOTL = 'C:/Time/OTLs',
#'                 category  = 'C:/Time/categories.csv')
#' plot_timeseries(otl)
#' plot_timeseries(otl, by = 'month', type = 'bar')
#' }
plot_timeseries <- function(merged_otl,
                             by    = c('week', 'month'),
                             type  = c('area', 'bar'),
                             title = 'Hours by category over time') {

  by   <- match.arg(by)
  type <- match.arg(type)

  if (!inherits(merged_otl, 'data.table')) {
    merged_otl <- data.table::as.data.table(merged_otl)
  }

  required <- c('Date', 'Hours', 'Categories')
  missing  <- setdiff(required, colnames(merged_otl))
  if (length(missing) > 0L) {
    stop('merged_otl is missing required columns: ',
         paste(missing, collapse = ', '), '\n',
         '  Pass the output of mergeOTL(aggregate = FALSE).')
  }

  dt <- data.table::copy(merged_otl)

  # Floor dates to period start
  if (by == 'week') {
    # ISO week: floor to preceding Monday
    dt[, Period := Date - (as.integer(format(Date, '%u')) - 1L)]
    x_label   <- 'Week commencing'
    date_fmt  <- '%d %b'
    date_brk  <- '4 weeks'
  } else {
    # Floor to first of month
    dt[, Period := as.Date(format(Date, '%Y-%m-01'))]
    x_label   <- NULL
    date_fmt  <- '%b %Y'
    date_brk  <- '1 month'
  }

  agg <- dt[, .(Hours = sum(Hours, na.rm = TRUE)), by = .(Period, Categories)]

  if (type == 'area') {
    geom_layer <- ggplot2::geom_area(alpha = 0.85, colour = NA)
  } else {
    geom_layer <- ggplot2::geom_col(width = if (by == 'week') 5 else 20)
  }

  ggplot2::ggplot(
    agg,
    ggplot2::aes(x = Period, y = Hours, fill = Categories)
  ) +
    geom_layer +
    ggplot2::scale_x_date(
      date_labels = date_fmt,
      date_breaks = date_brk
    ) +
    ggplot2::scale_fill_brewer(
      palette = 'Paired',
      guide   = ggplot2::guide_legend(ncol = 2)
    ) +
    ggplot2::labs(
      title = title,
      x     = x_label,
      y     = 'Hours',
      fill  = NULL
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title         = ggplot2::element_text(face = 'bold'),
      axis.text.x        = ggplot2::element_text(angle = 45, hjust = 1),
      legend.position    = 'bottom',
      panel.grid.minor   = ggplot2::element_blank()
    )
}


# ---- compare_objectives ----------------------------------------------------

#' Compare actual hours against quarterly targets
#'
#' Reads a \code{target_hours} column from the categories file and compares
#' it against actual hours recorded in a merged OTL table. Returns a
#' data.table and optionally plots a divergence chart.
#'
#' To use this function, add a \code{target_hours} column to your
#' \code{categories.csv} with the quarterly hour target for each category.
#' Leave it blank or set it to \code{NA} for categories without a target
#' (they will be excluded from the comparison).
#'
#' @param merged_otl   A data.table as returned by \code{mergeOTL()}
#'                     with \code{aggregate = FALSE}
#' @param categories   Path to the categories CSV file, which must contain
#'                     a \code{target_hours} column
#' @param plot         If TRUE, returns a ggplot2 divergence chart instead
#'                     of the data.table. Default FALSE.
#' @param title        Plot title when \code{plot = TRUE}.
#'
#' @return A data.table with columns:
#'   Categories, ActualHours, TargetHours, Delta, PctOfTarget
#'   Or a ggplot2 object when \code{plot = TRUE}.
#' @export
#'
#' @importFrom ggplot2 ggplot aes geom_col geom_hline coord_flip labs
#' @importFrom ggplot2 scale_fill_manual theme_minimal theme element_text
#' @importFrom ggplot2 element_blank geom_text
#'
#' @examples
#' \dontrun{
#' # Add target_hours to categories.csv first, then:
#' otl <- mergeOTL(folderOTL = 'C:/Time/OTLs',
#'                 category  = 'C:/Time/categories.csv',
#'                 quarterYear = 'current')
#' compare_objectives(otl, categories = 'C:/Time/categories.csv')
#' compare_objectives(otl, categories = 'C:/Time/categories.csv', plot = TRUE)
#' }
compare_objectives <- function(merged_otl,
                                categories,
                                plot  = FALSE,
                                title = 'Actual vs target hours') {

  if (!inherits(merged_otl, 'data.table')) {
    merged_otl <- data.table::as.data.table(merged_otl)
  }

  required <- c('Date', 'Hours', 'Categories')
  missing  <- setdiff(required, colnames(merged_otl))
  if (length(missing) > 0L) {
    stop('merged_otl is missing required columns: ',
         paste(missing, collapse = ', '))
  }

  # Load categories with target_hours field
  cats <- .load_categories(categories)

  # Only compare categories that have a target
  targets <- cats[!is.na(target_hours) & target_hours > 0,
                  .(Categories, TargetHours = as.numeric(target_hours))]

  if (nrow(targets) == 0L) {
    stop('No target_hours values found in the categories file.\n',
         '  Add a target_hours field to each entry in categories.yaml\n',
         '  with the quarterly hour target. Example:\n',
         '    - name: Cap Skills\n',
         '      target_hours: 20')
  }

  # Sum actual hours per category
  actuals <- merged_otl[, .(ActualHours = sum(Hours, na.rm = TRUE)),
                        by = Categories]

  # Join; categories with targets but no actuals get 0
  result <- targets[actuals, on = 'Categories', nomatch = NA]
  result[is.na(ActualHours), ActualHours := 0]
  result[, Delta      := ActualHours - TargetHours]
  result[, PctOfTarget := round(ActualHours / TargetHours * 100, 1)]

  data.table::setorder(result, Delta)

  n_over  <- sum(result$Delta > 0)
  n_under <- sum(result$Delta < 0)
  message('kronos: ', nrow(result), ' categories compared against targets')
  message('kronos: ', n_over,  ' over target, ',
          n_under, ' under target, ',
          nrow(result) - n_over - n_under, ' on target')

  if (!plot) return(result[])

  # Divergence bar chart
  result[, Colour := data.table::fifelse(Delta >= 0, 'Over', 'Under')]
  result[, Categories := factor(Categories, levels = Categories)]

  ggplot2::ggplot(
    result,
    ggplot2::aes(
      x    = Categories,
      y    = Delta,
      fill = Colour
    )
  ) +
    ggplot2::geom_col(width = 0.7, show.legend = FALSE) +
    ggplot2::geom_text(
      ggplot2::aes(
        label = paste0(ifelse(Delta >= 0, '+', ''), round(Delta, 1), ' hrs'),
        hjust = ifelse(Delta >= 0, -0.15, 1.15)
      ),
      size   = 3.2,
      colour = '#333333'
    ) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.4, colour = '#555555') +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(
      values = c('Over' = '#4575b4', 'Under' = '#d73027')
    ) +
    ggplot2::labs(
      title    = title,
      subtitle = paste0(n_over, ' over target  |  ',
                        n_under, ' under target'),
      x        = NULL,
      y        = 'Hours vs target'
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title         = ggplot2::element_text(face = 'bold'),
      plot.subtitle      = ggplot2::element_text(colour = '#555555'),
      panel.grid.minor   = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_blank()
    )
}

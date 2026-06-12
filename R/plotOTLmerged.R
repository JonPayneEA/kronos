#' @title Plot merged OTL data by day
#'
#' @details Produces a stacked bar chart of daily hours by category, for
#'   data of class \code{mergedOTLs} as returned by \code{mergeOTL()}.
#'   Each bar represents one working day; segments show the category split.
#'
#' @param x       A \code{mergedOTLs} data.table from \code{mergeOTL()}
#' @param title   Plot title. Default "Daily hours by category".
#' @param ...     Additional arguments passed to \code{ggplot2::theme()}
#'
#' @method plot mergedOTLs
#' @return A ggplot2 object
#' @export
#'
#' @importFrom ggplot2 ggplot aes geom_col labs scale_x_date
#' @importFrom ggplot2 theme_minimal theme element_text element_blank
#' @importFrom ggplot2 scale_fill_brewer guide_legend
#'
#' @examples
#' \dontrun{
#' otl <- mergeOTL(folderOTL = 'C:/Time/OTLs',
#'                 category  = 'C:/Time/categories.csv')
#' plot(otl)
#' }
plot.mergedOTLs <- function(x, title = 'Daily hours by category', ...) {

  p <- ggplot2::ggplot(
    x,
    ggplot2::aes(x = Date, y = Hours, fill = Categories)
  ) +
    ggplot2::geom_col(width = 0.8) +
    ggplot2::scale_x_date(date_labels = '%d %b', date_breaks = '1 week') +
    ggplot2::scale_fill_brewer(
      palette = 'Paired',
      guide   = ggplot2::guide_legend(ncol = 2)
    ) +
    ggplot2::labs(
      title = title,
      x     = NULL,
      y     = 'Hours',
      fill  = NULL
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(face = 'bold'),
      axis.text.x      = ggplot2::element_text(angle = 45, hjust = 1),
      legend.position  = 'bottom',
      panel.grid.minor = ggplot2::element_blank(),
      ...
    )

  p
}

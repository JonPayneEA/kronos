#' @title Plot total OTL hours by category
#'
#' @details Produces a horizontal bar chart of total hours per category,
#'   for data of class \code{totalOTLs} as returned by
#'   \code{mergeOTL(aggregate = TRUE)}.
#'   Categories are sorted by total hours descending.
#'
#' @param x       A \code{totalOTLs} data.table from
#'                \code{mergeOTL(aggregate = TRUE)}
#' @param title   Plot title. Default "Total hours by category".
#' @param ...     Additional arguments passed to \code{ggplot2::theme()}
#'
#' @method plot totalOTLs
#' @return A ggplot2 object
#' @export
#'
#' @importFrom ggplot2 ggplot aes geom_col coord_flip labs
#' @importFrom ggplot2 theme_minimal theme element_text element_blank
#' @importFrom ggplot2 scale_fill_brewer geom_text
#'
#' @examples
#' \dontrun{
#' totals <- mergeOTL(folderOTL = 'C:/Time/OTLs',
#'                    category  = 'C:/Time/categories.csv',
#'                    aggregate = TRUE)
#' plot(totals)
#' }
plot.totalOTLs <- function(x, title = 'Total hours by category', ...) {

  # Sort categories by descending total for a ranked view
  x <- x[order(Sum)]
  x[, Categories := factor(Categories, levels = Categories)]

  p <- ggplot2::ggplot(
    x,
    ggplot2::aes(x = Categories, y = Sum, fill = Categories)
  ) +
    ggplot2::geom_col(show.legend = FALSE, width = 0.7) +
    ggplot2::geom_text(
      ggplot2::aes(label = round(Sum, 1)),
      hjust  = -0.2,
      size   = 3.2,
      colour = '#333333'
    ) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_brewer(palette = 'Paired') +
    ggplot2::labs(
      title = title,
      x     = NULL,
      y     = 'Hours'
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(face = 'bold'),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_blank(),
      ...
    )

  p
}

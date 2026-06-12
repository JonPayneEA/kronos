#' @title Compile OTL data
#'
#' @param folderOTL The folder you have saved the OTL export files
#' @param category Filepath to the categories file
#' @param quarterYear Set to 'all', this compiles all OTLs. If you set to
#'   'current' it will compile all the OTLs that are in the same quarter as
#'   Sys.Date(). To specify a quarter set to the format of 'Qx yyyy' e.g.
#'   'Q1 2023'.
#' @param aggregate Set to FALSE. If TRUE it will sum all the hours spent on
#'   each category.
#'
#' @return All OTL files merged into one table
#' @export
#'
#' @importFrom data.table data.table
#' @importFrom data.table merge.data.table
#' @importFrom data.table rbindlist
#' @importFrom lubridate quarter
#' @importFrom lubridate year
#' @importFrom tools file_path_sans_ext
#'
#' @examples
#' \dontrun{
#' folder <- 'C:/Users/jpayne05/OneDrive - Defra/Time_Recording/OTLs'
#' cats <- 'C:/Users/jpayne05/OneDrive - Defra/Time_Recording/Categories/Categories_TCs.csv'
#' dt <- mergeOTL(folderOTL = folder, category = cats, quarterYear = 'all')
#' dt
#' dt1 <- mergeOTL(folderOTL = folder, category = cats, quarterYear = 'all',
#'                 aggregate = TRUE)
#' dt1
#' }
mergeOTL <- function(folderOTL, category, quarterYear = 'all', aggregate = FALSE) {

  # List OTL files
  # Fix 1.1a: was `folder` — correct parameter name is `folderOTL`
  files <- list.files(folderOTL, full.names = TRUE, pattern = 'OTL_wc_')

  # Exclude companion day-type files from the OTL file list
  files <- files[!grepl(DAYTYPES_SUFFIX, files)]

  if (length(files) == 0L) {
    stop('No OTL files found in: ', folderOTL, '\n',
         '  Files must be named OTL_wc_YYYY_MM_DD.csv')
  }

  message('kronos: found ', length(files), ' OTL file(s) to merge')

  # Load categories file (YAML)
  # Fix 1.1b: was `cats` -- correct parameter name is `category`
  # Uses .load_categories() so the YAML parsing is consistent across the package
  cats_full  <- .load_categories(category)
  categories <- cats_full[, .(Code, Task, Categories)]

  # Import OTL files
  otls <- list()
  for (i in seq_along(files)) {
    # Find end point for each table
    # Table starts on row 29, skip 28 rows
    dt <- data.table::fread(files[i], skip = 28)
    end <- which(dt[, 1] == 'STOP_TEMPLATE') - 3

    # Import specific table
    dt <- data.table::fread(files[i],
                            skip   = 28,
                            nrows  = end,
                            select = c(1, 2, 5:11))
    colnames(dt)[1] <- 'Code'

    # Get task rather than OTL codes
    catags <- data.table::merge.data.table(dt, categories, by = c('Code', 'Task'))

    # Change Mon-Sun to dates using the file name dates
    week_start <- basename(files[i]) |>
      tools::file_path_sans_ext() |>
      (\(x) gsub('OTL_wc_', '', x))() |>
      as.Date(format = "%Y_%m_%d")

    days <- as.character((0:6) + week_start)
    colnames(catags)[3:9] <- days

    # Reorder and melt
    dt <- data.table::data.table(catags[, 10], catags[, 3:9])
    dt <- data.table::melt(dt, id.vars = 'Categories')
    otls[[i]] <- dt
  }

  # Bind all weeks
  OTL <- data.table::rbindlist(otls)
  colnames(OTL)[2:3] <- c('Date', 'Hours')
  OTL$Date <- as.Date(OTL$Date)
  OTL <- OTL[Hours > 0, ]

  # Calculate quarter and year
  OTL$Quarter <- paste0('Q',
                        lubridate::quarter(OTL$Date, fiscal_start = 4),
                        ' ',
                        lubridate::year(OTL$Date))

  # Fix 1.1c: quarterYear == 'current' previously referenced OTL$Date before
  # OTL existed. Moved to here, after OTL is built.
  if (quarterYear == 'current') {
    quarterYear <- paste0('Q',
                          lubridate::quarter(Sys.Date(), fiscal_start = 4),
                          ' ',
                          lubridate::year(Sys.Date()))
  }

  if (!quarterYear %in% c('all', 'auto')) {
    if (!quarterYear %in% OTL$Quarter) {
      stop(paste0('quarterYear "', quarterYear, '" not found in data. ',
                  'Available quarters: ',
                  paste(sort(unique(OTL$Quarter)), collapse = ', ')))
    }
    OTL <- OTL[Quarter == quarterYear, ]
  }

  if (aggregate == TRUE) {
    totals <- OTL[, .(Sum = sum(Hours)), by = Categories]
    class(totals) <- c('totalOTLs', class(totals))
    return(totals)
  }

  class(OTL) <- c('mergedOTLs', class(OTL))
  return(OTL)
}

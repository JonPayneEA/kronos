#' @title Find whether data are integer(0)
#'
#' @param x Data of interest
#'
#' @return TRUE if x is an integer vector of length zero, FALSE otherwise
#' @export
#'
#' @examples
#' is.integer0(integer(0))  # TRUE
#' is.integer0(1L)          # FALSE
is.integer0 <- function(x) {
  is.integer(x) && length(x) == 0L
}


#' @title Convert Excel datetime string to time component
#'
#' @description Strips the date portion from an Excel datetime string,
#'   returning only the time component as a character string. Expects input
#'   in the form "YYYY-MM-DD HH:MM:SS" or similar; returns everything after
#'   the last space.
#'
#' @param x Character vector of datetime strings
#' @param na.rm Unused; retained for consistency
#'
#' @return Character vector of time strings
#' @export
#'
#' @examples
#' toTime("2023-05-15 08:30:00")  # "08:30:00"
toTime <- function(x, na.rm = FALSE) {
  as.character(gsub(".* ", "", x))
}


#' @title Convert time strings to hms
#'
#' @param x Character vector of time strings (HH:MM:SS)
#' @param na.rm Unused; retained for consistency
#'
#' @importFrom lubridate hms
#'
#' @return A Period vector
#' @export
#'
#' @examples
#' toHMS("08:30:00")
toHMS <- function(x, na.rm = FALSE) {
  lubridate::hms(toTime(x))
}


#' @title Convert hms Period to decimal hours
#'
#' @param x A Period vector as returned by toHMS()
#' @param na.rm Unused; retained for consistency
#'
#' @importFrom lubridate period_to_seconds
#'
#' @return Numeric vector of hours
#' @export
#'
#' @examples
#' toHours(toHMS("07:24:00"))  # 7.4
toHours <- function(x, na.rm = FALSE) {
  as.numeric(lubridate::period_to_seconds(x) / 3600)
}


#' @title Get recent Mondays
#'
#' @description Returns all Mondays in the past 70 days.
#'
#' @return A Date vector of Mondays
#' @export
#'
#' @examples
#' getRecentMondays()
getRecentMondays <- function() {
  daysR <- seq(Sys.Date() - 70, by = "day", length.out = 70)
  days  <- as.POSIXlt(daysR, format = '%Y-%j')
  mons  <- days[days$wday == 1]
  as.Date(mons[!is.na(mons)])
}


#' @title Fix Excel datetime columns
#'
#' @description Combines a date and a time string into a POSIXct value.
#'   Handles NAs cleanly.
#'
#' @param date A Date vector
#' @param endStart A character vector of time strings
#'
#' @return A POSIXct vector
#' @export
#'
#' @examples
#' fixTimes(Sys.Date(), '11:00:00')
fixTimes <- function(date, endStart) {
  time     <- toTime(endStart)
  dateTime <- ifelse(is.na(time), NA, paste(date, time))
  as.POSIXct(dateTime, origin = "1970-01-01")
}

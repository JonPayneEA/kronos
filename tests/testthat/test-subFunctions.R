test_that("is.integer0 returns TRUE for integer(0)", {
  expect_true(is.integer0(integer(0)))
})

test_that("is.integer0 returns FALSE for non-empty integer", {
  expect_false(is.integer0(1L))
  expect_false(is.integer0(c(1L, 2L)))
})

test_that("is.integer0 returns FALSE for numeric(0)", {
  # numeric(0) is not integer — function should return FALSE
  expect_false(is.integer0(numeric(0)))
})

test_that("is.integer0 returns FALSE for NULL", {
  expect_false(is.integer0(NULL))
})

# ---- toTime ----------------------------------------------------------------

test_that("toTime strips date prefix from datetime string", {
  expect_equal(toTime("2023-05-15 08:30:00"), "08:30:00")
})

test_that("toTime returns bare time string unchanged", {
  expect_equal(toTime("08:30:00"), "08:30:00")
})

test_that("toTime handles NA input", {
  expect_equal(toTime(NA_character_), "NA")
})

test_that("toTime is vectorised", {
  result <- toTime(c("2023-05-15 08:30:00", "2023-05-16 09:00:00"))
  expect_equal(result, c("08:30:00", "09:00:00"))
})

# ---- toHMS / toHours -------------------------------------------------------

test_that("toHours converts 07:24:00 to 7.4 hours", {
  expect_equal(toHours(toHMS("07:24:00")), 7.4)
})

test_that("toHours converts 03:42:00 to 3.7 hours", {
  expect_equal(toHours(toHMS("03:42:00")), 3.7)
})

test_that("toHours converts 00:37:00 to correct fractional hours", {
  expect_equal(round(toHours(toHMS("00:37:00")), 4), round(37 / 60, 4))
})

test_that("toHMS handles datetime prefix in input", {
  # toHMS calls toTime internally
  result <- toHours(toHMS("2023-05-15 07:24:00"))
  expect_equal(result, 7.4)
})

# ---- getRecentMondays ------------------------------------------------------

test_that("getRecentMondays returns only Mondays", {
  mons <- getRecentMondays()
  days <- weekdays(mons)
  expect_true(all(days == "Monday"))
})

test_that("getRecentMondays returns Date class", {
  expect_s3_class(getRecentMondays(), "Date")
})

test_that("getRecentMondays returns values within the past 70 days", {
  mons   <- getRecentMondays()
  oldest <- min(mons)
  expect_gte(as.numeric(Sys.Date() - oldest), 0)
  expect_lte(as.numeric(Sys.Date() - oldest), 77)  # up to 70 + 7 tolerance
})

test_that("getRecentMondays returns at least 9 Mondays", {
  expect_gte(length(getRecentMondays()), 9L)
})

# ---- fixTimes --------------------------------------------------------------

test_that("fixTimes returns POSIXct", {
  result <- fixTimes(as.Date("2024-05-13"), "08:00:00")
  expect_s3_class(result, "POSIXct")
})

test_that("fixTimes combines date and time correctly", {
  result <- fixTimes(as.Date("2024-05-13"), "09:30:00")
  expect_equal(format(result, "%H:%M:%S"), "09:30:00")
  expect_equal(as.Date(result), as.Date("2024-05-13"))
})

test_that("fixTimes returns NA for NA time input", {
  result <- fixTimes(as.Date("2024-05-13"), NA_character_)
  expect_true(is.na(result))
})

test_that("fixTimes handles datetime-formatted time strings", {
  result <- fixTimes(as.Date("2024-05-13"), "2024-05-13 08:00:00")
  expect_equal(format(result, "%H:%M:%S"), "08:00:00")
})

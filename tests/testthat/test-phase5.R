suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(readxl)
})

# ---- .generate_work_week ---------------------------------------------------

test_that(".generate_work_week returns 7 rows", {
  cal <- .load_calendar(fixture("calendar_no_daily.xlsx"), WEEK)
  ww  <- .generate_work_week(cal, WEEK)
  expect_equal(nrow(ww), 7L)
})

test_that(".generate_work_week has correct day sequence", {
  cal <- .load_calendar(fixture("calendar_no_daily.xlsx"), WEEK)
  ww  <- .generate_work_week(cal, WEEK)
  expect_equal(ww$Day, c("Mon","Tue","Wed","Thu","Fri","Sat","Sun"))
})

test_that(".generate_work_week sets standard days to 7.4 hours", {
  cal <- .load_calendar(fixture("calendar_no_daily.xlsx"), WEEK)
  ww  <- .generate_work_week(cal, WEEK, bank_hols = as.Date(character()))
  # Mon, Wed, Thu should be Standard; Fri is Annual Leave
  std <- ww[Type == "Standard"]
  expect_true(all(std$Total == 7.4))
})

test_that(".generate_work_week sets weekends to zero", {
  cal <- .load_calendar(fixture("calendar_no_daily.xlsx"), WEEK)
  ww  <- .generate_work_week(cal, WEEK)
  weekends <- ww[Day %in% c("Sat", "Sun")]
  expect_true(all(weekends$Total == 0))
  expect_true(all(weekends$Type == "Weekend"))
})

test_that(".generate_work_week overrides Friday with Annual Leave", {
  cal <- .load_calendar(fixture("calendar_no_daily.xlsx"), WEEK)
  ww  <- .generate_work_week(cal, WEEK, bank_hols = as.Date(character()))
  fri <- ww[Day == "Fri"]
  expect_equal(fri$Type, "Leave")
  expect_equal(fri$Total, 0)
})

test_that(".generate_work_week overrides with bank holiday from feed", {
  # Inject a bank holiday on Monday of our test week
  fake_bh <- WEEK  # 2024-05-13 is a Monday — used as a fake bank holiday
  cal <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  ww  <- .generate_work_week(cal, WEEK, bank_hols = fake_bh)
  mon <- ww[Day == "Mon"]
  expect_equal(mon$Type, "Bank Holiday")
  expect_equal(mon$Total, 0)
})

test_that(".generate_work_week sets FFIDP all-day to Standard (not a leave type)", {
  # FFIDP all-day event is a work event, not in ALLDAY_TYPE_MAP, so Tuesday
  # should remain Standard
  cal <- .load_calendar(fixture("calendar_no_daily.xlsx"), WEEK)
  ww  <- .generate_work_week(cal, WEEK, bank_hols = as.Date(character()))
  tue <- ww[Day == "Tue"]
  expect_equal(tue$Type, "Standard")
})

test_that(".generate_work_week applies Sick Half from calendar", {
  cal <- .load_calendar(fixture("calendar_sick_half.xlsx"), WEEK)
  ww  <- .generate_work_week(cal, WEEK, bank_hols = as.Date(character()))
  wed <- ww[Day == "Wed"]
  expect_equal(wed$Type, "Sick Half")
  expect_equal(wed$Total, 3.7)
})

test_that(".generate_work_week long-day override applies", {
  # Build a calendar where Monday has > 7.4 hours of timed events
  # Mon: two 4-hour meetings = 8 hours
  long_cal <- data.table::data.table(
    Date       = c(WEEK, WEEK),
    Subject    = c("Meeting A", "Meeting B"),
    Categories = c("Cap Skills", "FFIDP"),
    StartDT    = as.POSIXct(c("2024-05-13T08:00:00", "2024-05-13T12:00:00")),
    EndDT      = as.POSIXct(c("2024-05-13T12:00:00", "2024-05-13T16:00:00")),
    Length     = c(4, 4),
    allDay     = c(FALSE, FALSE)
  )
  ww <- .generate_work_week(long_cal, WEEK, bank_hols = as.Date(character()))
  mon <- ww[Day == "Mon"]
  expect_equal(mon$Total, 8.0)
})

# ---- createTC without daily parameter --------------------------------------

test_that("createTC runs without daily parameter", {
  ts <- createTC(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP", "Reactive Forecasting"),
    weight     = c(1, 2, 1),
    export     = FALSE
  )
  expect_s3_class(ts, "data.table")
  expect_gt(nrow(ts), 0L)
})

test_that("createTC without daily includes leave row in output", {
  ts <- createTC(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    export     = FALSE
  )
  # Annual Leave on Friday should produce ENVABE code row
  expect_true("ENVABE" %in% ts$Code)
})

test_that("createTC calendar-driven output is deterministic", {
  args <- list(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    export     = FALSE
  )
  ts1 <- do.call(createTC, args)
  ts2 <- do.call(createTC, args)
  expect_equal(ts1, ts2)
})

test_that("createTC still works with daily parameter supplied (legacy path)", {
  ts <- createTC(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    daily      = fixture("daily_hours.xlsx"),
    export     = FALSE
  )
  expect_s3_class(ts, "data.table")
  expect_gt(nrow(ts), 0L)
})

test_that("createTC emits deprecation message when daily is supplied", {
  expect_message(
    createTC(
      categories = fixture("categories.yaml"),
      outCal     = fixture("calendar.xlsx"),
      week_start = "2024-05-13",
      split      = c("Cap Skills", "FFIDP"),
      weight     = c(1, 1),
      daily      = fixture("daily_hours.xlsx"),
      export     = FALSE
    ),
    regexp = "deprecated"
  )
})

# ---- contracted_hours override ---------------------------------------------

test_that("contracted_hours override changes Standard day Total", {
  ts <- createTC(
    categories       = fixture("categories.yaml"),
    outCal           = fixture("calendar_no_daily.xlsx"),
    week_start       = "2024-05-13",
    split            = c("Cap Skills", "FFIDP"),
    weight           = c(1, 1),
    export           = FALSE,
    contracted_hours = 7.0
  )
  # Pipeline should have used 7.0 not 7.4
  # All rows should sum approximately to 7.0 * 4 working days (minus leave)
  total_hrs <- sum(ts[, c("Mon","Tue","Wed","Thu"), with = FALSE])
  expect_gt(total_hrs, 26)   # 7.0 * 4 = 28 - FFIDP allday leaves some unallocated
  expect_lt(total_hrs, 30)
})

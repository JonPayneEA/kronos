suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(readxl)
})

# ---- .load_categories ------------------------------------------------------

test_that(".load_categories reads fixture and returns required columns", {
  cats <- .load_categories(fixture("categories.yaml"))
  expect_s3_class(cats, "data.table")
  expect_true(all(c("Categories", "Code", "Task", "Type") %in% colnames(cats)))
  expect_gt(nrow(cats), 0L)
})

test_that(".load_categories stops on missing file", {
  expect_error(
    .load_categories("/nonexistent/path/cats.csv"),
    regexp = "not found"
  )
})

test_that(".load_categories stops on missing fields", {
  tmp <- tempfile(fileext = ".yaml")
  writeLines("categories:\n  - name: Test\n    code: X", tmp)
  on.exit(unlink(tmp))
  # Missing task and type fields -- should still load but with NAs;
  # a completely wrong structure triggers the top-level key check
  bad <- tempfile(fileext = ".yaml")
  writeLines("wrong_key:\n  - x: 1", bad)
  on.exit(unlink(bad), add = TRUE)
  expect_error(.load_categories(bad), regexp = 'top-level "categories:"')
})

# ---- .load_daily_hours -----------------------------------------------------

test_that(".load_daily_hours reads fixture and returns correct shape", {
  dh <- .load_daily_hours(fixture("daily_hours.xlsx"))
  expect_s3_class(dh, "data.table")
  expect_true(all(c("Day", "Date", "Type", "Start", "End", "Lunch", "Total")
                  %in% colnames(dh)))
})

test_that(".load_daily_hours coerces Date column correctly", {
  dh <- .load_daily_hours(fixture("daily_hours.xlsx"))
  expect_s3_class(dh$Date, "Date")
})

test_that(".load_daily_hours coerces Total to numeric hours", {
  dh <- .load_daily_hours(fixture("daily_hours.xlsx"))
  expect_type(dh$Total, "double")
  # Standard days should be around 7.4 hours
  std_days <- dh[Type == "Standard"]
  expect_true(all(std_days$Total > 6 & std_days$Total < 9))
})

test_that(".load_daily_hours drops Expected and Flexi columns", {
  dh <- .load_daily_hours(fixture("daily_hours.xlsx"))
  expect_false("Expected" %in% colnames(dh))
  expect_false("Flexi" %in% colnames(dh))
})

test_that(".load_daily_hours stops on missing file", {
  expect_error(
    .load_daily_hours("/nonexistent/daily.xlsx"),
    regexp = "not found"
  )
})

# ---- .load_calendar --------------------------------------------------------

test_that(".load_calendar reads fixture and returns correct columns", {
  cal <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  expect_s3_class(cal, "data.table")
  expect_true(all(c("Date", "Subject", "Categories", "StartDT", "EndDT",
                    "Length", "allDay") %in% colnames(cal)))
})

test_that(".load_calendar filters to the correct week", {
  cal <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  expect_true(all(cal$Date >= WEEK))
  expect_true(all(cal$Date < WEEK + 7L))
})

test_that(".load_calendar splits multi-category appointments", {
  cal <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  # "Team Meeting,Admin" on Thu should produce two rows
  thu_rows <- cal[as.Date(StartDT) == as.Date("2024-05-16")]
  expect_equal(nrow(thu_rows), 2L)
  expect_setequal(thu_rows$Categories, c("Team Meeting", "Admin"))
})

test_that(".load_calendar halves length for multi-category appointments", {
  cal <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  thu_rows <- cal[as.Date(StartDT) == as.Date("2024-05-16")]
  # Original meeting is 1 hour; each category row should be 0.5 hours
  expect_equal(thu_rows$Length[1], 0.5)
  expect_equal(thu_rows$Length[2], 0.5)
})

test_that(".load_calendar returns empty data.table for wrong week", {
  cal <- .load_calendar(fixture("calendar.xlsx"), as.Date("2023-01-02"))
  expect_equal(nrow(cal), 0L)
})

test_that(".load_calendar stops on missing file", {
  expect_error(
    .load_calendar("/nonexistent/calendar.xlsx", WEEK),
    regexp = "not found"
  )
})

test_that(".load_calendar stops on non-xlsx file", {
  tmp <- tempfile(fileext = ".csv")
  writeLines("a,b", tmp)
  on.exit(unlink(tmp))
  expect_error(.load_calendar(tmp, WEEK), regexp = "must be an xlsx")
})

# ---- .process_work_week ----------------------------------------------------

test_that(".process_work_week returns 7 rows for a full week", {
  dh <- .load_daily_hours(fixture("daily_hours.xlsx"))
  ww <- .process_work_week(dh, WEEK)
  expect_equal(nrow(ww), 7L)
})

test_that(".process_work_week returns only the correct date range", {
  dh <- .load_daily_hours(fixture("daily_hours.xlsx"))
  ww <- .process_work_week(dh, WEEK)
  expect_equal(min(ww$Date), WEEK)
  expect_equal(max(ww$Date), WEEK + 6L)
})

test_that(".process_work_week stops when week_start not in data", {
  dh <- .load_daily_hours(fixture("daily_hours.xlsx"))
  expect_error(
    .process_work_week(dh, as.Date("2020-01-06")),
    regexp = "not found in daily hours"
  )
})

# ---- .process_sick_leave ---------------------------------------------------

test_that(".process_sick_leave returns NULL for a week with no sick/leave", {
  dh     <- .load_daily_hours(fixture("daily_hours.xlsx"))
  catags <- .load_categories(fixture("categories.yaml"))
  # Use only standard days
  std_week <- dh[Type == "Standard" | Type == "Weekend"]
  # Manufacture a standard-only week fixture
  std_week[, Date := WEEK + 0:6]
  std_week[, Day  := c("Mon","Tue","Wed","Thu","Fri","Sat","Sun")]
  std_week[Type == "Weekend", Total := 0]
  expect_null(.process_sick_leave(std_week, catags))
})

test_that(".process_sick_leave produces a row for Leave day", {
  dh     <- .load_daily_hours(fixture("daily_hours.xlsx"))
  catags <- .load_categories(fixture("categories.yaml"))
  ww     <- .process_work_week(dh, WEEK)
  sl     <- .process_sick_leave(ww, catags)
  expect_false(is.null(sl))
  expect_true("Leave" %in% sl$dayType)
})

test_that(".process_sick_leave assigns zero Length to full leave day", {
  dh     <- .load_daily_hours(fixture("daily_hours.xlsx"))
  catags <- .load_categories(fixture("categories.yaml"))
  ww     <- .process_work_week(dh, WEEK)
  sl     <- .process_sick_leave(ww, catags)
  leave_row <- sl[dayType == "Leave"]
  expect_equal(leave_row$Length, 0)
})

# ---- .distribute_excess ----------------------------------------------------

test_that(".distribute_excess returns same output given same inputs (deterministic)", {
  dh     <- .load_daily_hours(fixture("daily_hours.xlsx"))
  catags <- .load_categories(fixture("categories.yaml"))
  cal    <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  ww     <- .process_work_week(dh, WEEK)
  sl     <- .process_sick_leave(ww, catags)
  comb   <- .join_pipeline(ww, cal, catags, sl)
  comb   <- .distribute_allday(comb, ww)

  split  <- c("Cap Skills", "FFIDP", "Reactive Forecasting")
  weight <- c(1, 2, 1)

  result1 <- .distribute_excess(comb, ww, catags, split, weight)
  result2 <- .distribute_excess(comb, ww, catags, split, weight)

  # Identical output on repeated runs — no randomness
  expect_equal(result1$Length, result2$Length)
})

test_that(".distribute_excess total hours balance per day", {
  dh     <- .load_daily_hours(fixture("daily_hours.xlsx"))
  catags <- .load_categories(fixture("categories.yaml"))
  cal    <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  ww     <- .process_work_week(dh, WEEK)
  sl     <- .process_sick_leave(ww, catags)
  comb   <- .join_pipeline(ww, cal, catags, sl)
  comb   <- .distribute_allday(comb, ww)

  split  <- c("Cap Skills", "FFIDP", "Reactive Forecasting")
  result <- .distribute_excess(comb, ww, catags, split, c(1, 2, 1))

  # For each standard working day, hours should sum to approximately Total
  std_days <- ww[Type == "Standard"]
  for (i in seq_len(nrow(std_days))) {
    day_hrs   <- result[Date == std_days$Date[i] & !is.na(Code),
                        sum(Length, na.rm = TRUE)]
    contracted <- std_days$Total[i]
    expect_equal(round(day_hrs, 1), round(contracted, 1),
                 tolerance = 0.1,
                 label = paste("hours balance on", std_days$Date[i]))
  }
})

# ---- .build_timecard -------------------------------------------------------

test_that(".build_timecard returns expected columns", {
  dh     <- .load_daily_hours(fixture("daily_hours.xlsx"))
  catags <- .load_categories(fixture("categories.yaml"))
  cal    <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  ww     <- .process_work_week(dh, WEEK)
  sl     <- .process_sick_leave(ww, catags)
  comb   <- .join_pipeline(ww, cal, catags, sl)
  comb   <- .distribute_allday(comb, ww)
  comb   <- .distribute_excess(comb, ww, catags,
                                c("Cap Skills", "FFIDP"), c(1, 1))
  ts     <- .build_timecard(comb)

  expect_true(all(c("Code", "Task", "Type", "hoursType") %in% colnames(ts)))
  expect_true("Mon" %in% colnames(ts))
})

test_that(".build_timecard day columns are in Mon-Sun order", {
  dh     <- .load_daily_hours(fixture("daily_hours.xlsx"))
  catags <- .load_categories(fixture("categories.yaml"))
  cal    <- .load_calendar(fixture("calendar.xlsx"), WEEK)
  ww     <- .process_work_week(dh, WEEK)
  sl     <- .process_sick_leave(ww, catags)
  comb   <- .join_pipeline(ww, cal, catags, sl)
  comb   <- .distribute_allday(comb, ww)
  comb   <- .distribute_excess(comb, ww, catags, c("Cap Skills", "FFIDP"), c(1, 1))
  ts     <- .build_timecard(comb)

  day_cols   <- intersect(c("Mon","Tue","Wed","Thu","Fri","Sat","Sun"), colnames(ts))
  day_order  <- c("Mon","Tue","Wed","Thu","Fri","Sat","Sun")
  actual_pos <- match(day_cols, colnames(ts))
  expect_true(all(diff(actual_pos) > 0),
              label = "Day columns should be in Mon-Sun order")
})

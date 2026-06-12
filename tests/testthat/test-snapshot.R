suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(readxl)
})

# ---- Full pipeline snapshot ------------------------------------------------
#
# Given fixed inputs, createTC must produce identical output on every run.
# This is only possible because .distribute_excess() is deterministic.
# The snapshot is created on the first run and checked on every subsequent run.
#
# If the snapshot needs updating (e.g. after a deliberate logic change),
# delete tests/testthat/_snaps/test-snapshot.md and re-run.

test_that("createTC produces consistent output for standard week", {
  ts <- createTC(
    categories = fixture("categories.yaml"),
    daily      = fixture("daily_hours.xlsx"),
    outCal     = fixture("calendar.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP", "Reactive Forecasting"),
    weight     = c(1, 2, 1),
    export     = FALSE
  )

  expect_s3_class(ts, "data.table")
  expect_gt(nrow(ts), 0L)
  expect_true(all(c("Code", "Task", "Type") %in% colnames(ts)))

  # Snapshot: exact output must not change between runs
  expect_snapshot(as.data.frame(ts))
})

test_that("createTC handles leave day correctly", {
  ts <- createTC(
    categories = fixture("categories.yaml"),
    daily      = fixture("daily_hours.xlsx"),
    outCal     = fixture("calendar_leave.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    export     = FALSE
  )

  expect_s3_class(ts, "data.table")
  # Leave row should appear with ENVABE code
  expect_true("ENVABE" %in% ts$Code)
})

test_that("createTC export writes a file to disk", {
  tmp_dir <- tempdir()
  createTC(
    categories = fixture("categories.yaml"),
    daily      = fixture("daily_hours.xlsx"),
    outCal     = fixture("calendar.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    pathOTL    = tmp_dir,
    export     = TRUE
  )
  expected_file <- file.path(tmp_dir, "OTL_wc_2024_05_13.csv")
  expect_true(file.exists(expected_file))
})

test_that("createTC exported file contains Oracle markers", {
  tmp_dir <- tempdir()
  createTC(
    categories = fixture("categories.yaml"),
    daily      = fixture("daily_hours.xlsx"),
    outCal     = fixture("calendar.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    pathOTL    = tmp_dir,
    export     = TRUE
  )
  out_file <- file.path(tmp_dir, "OTL_wc_2024_05_13.csv")
  content  <- readLines(out_file)
  expect_true(any(grepl("ORACLE TIME & LABOR", content)))
  expect_true(any(grepl("START_TEMPLATE",      content)))
  expect_true(any(grepl("STOP_TEMPLATE",       content)))
  expect_true(any(grepl("START_ORACLE",        content)))
})

# ---- Input validation errors -----------------------------------------------

test_that("createTC stops when categories path is NULL", {
  expect_error(
    createTC(categories = NULL, daily = "x", outCal = "y",
             split = "z", weight = 1),
    regexp = "categories path"
  )
})

test_that("createTC stops when split and weight lengths differ", {
  expect_error(
    createTC(
      categories = fixture("categories.yaml"),
      daily      = fixture("daily_hours.xlsx"),
      outCal     = fixture("calendar.xlsx"),
      week_start = "2024-05-13",
      split      = c("Cap Skills", "FFIDP"),
      weight     = c(1),
      export     = FALSE
    ),
    regexp = "same length"
  )
})

test_that("createTC stops when split task not in categories", {
  expect_error(
    createTC(
      categories = fixture("categories.yaml"),
      daily      = fixture("daily_hours.xlsx"),
      outCal     = fixture("calendar.xlsx"),
      week_start = "2024-05-13",
      split      = c("Cap Skills", "NONEXISTENT TASK"),
      weight     = c(1, 1),
      export     = FALSE
    ),
    regexp = "Tasks not found"
  )
})

test_that("createTC stops on non-Monday week_start", {
  expect_error(
    createTC(
      categories = fixture("categories.yaml"),
      daily      = fixture("daily_hours.xlsx"),
      outCal     = fixture("calendar.xlsx"),
      week_start = "2024-05-14",  # Tuesday
      split      = c("Cap Skills"),
      weight     = c(1),
      export     = FALSE
    ),
    regexp = "must be a Monday"
  )
})

test_that("createTC stops when export TRUE but pathOTL missing", {
  expect_error(
    createTC(
      categories = fixture("categories.yaml"),
      daily      = fixture("daily_hours.xlsx"),
      outCal     = fixture("calendar.xlsx"),
      week_start = "2024-05-13",
      split      = c("Cap Skills"),
      weight     = c(1),
      pathOTL    = NULL,
      export     = TRUE
    ),
    regexp = "pathOTL must be supplied"
  )
})

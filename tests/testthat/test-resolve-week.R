test_that(".resolve_week accepts a valid Monday string", {
  result <- .resolve_week("2024-05-13")
  expect_equal(result, as.Date("2024-05-13"))
  expect_s3_class(result, "Date")
})

test_that(".resolve_week accepts a Date object", {
  result <- .resolve_week(as.Date("2024-05-13"))
  expect_equal(result, as.Date("2024-05-13"))
})

test_that(".resolve_week stops on a non-Monday", {
  expect_error(
    .resolve_week("2024-05-14"),  # Tuesday
    regexp = "must be a Monday"
  )
})

test_that(".resolve_week stops on an unparseable string", {
  expect_error(
    .resolve_week("not-a-date"),
    regexp = "could not be parsed"
  )
})

test_that(".resolve_week returns a Monday when week_start is NULL", {
  result <- .resolve_week(NULL)
  expect_equal(weekdays(result), "Monday")
  expect_s3_class(result, "Date")
})

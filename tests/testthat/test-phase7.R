suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

cats_targets <- function() fixture("categories_with_targets.yaml")
otl_folder   <- function() file.path(dirname(fixture("")), "otl_folder")

# ---- plot.mergedOTLs -------------------------------------------------------

test_that("plot.mergedOTLs returns a ggplot object", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- plot(otl)
  expect_s3_class(p, "ggplot")
})

test_that("plot.mergedOTLs uses Date on x axis", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- plot(otl)
  expect_equal(as.character(p$mapping$x), "~Date")
})

test_that("plot.mergedOTLs accepts custom title", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- plot(otl, title = "My chart")
  expect_equal(p$labels$title, "My chart")
})

# ---- plot.totalOTLs --------------------------------------------------------

test_that("plot.totalOTLs returns a ggplot object", {
  totals <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all",
                     aggregate = TRUE)
  p <- plot(totals)
  expect_s3_class(p, "ggplot")
})

test_that("plot.totalOTLs uses coord_flip", {
  totals <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all",
                     aggregate = TRUE)
  p <- plot(totals)
  # coord_flip present in coord class
  expect_true(inherits(p$coordinates, "CoordFlip"))
})

test_that("plot.totalOTLs categories are sorted by Sum", {
  totals <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all",
                     aggregate = TRUE)
  p <- plot(totals)
  # Categories column in plot data should be a factor ordered by Sum
  plot_data <- p$data
  expect_true(is.factor(plot_data$Categories))
  sums <- plot_data[order(plot_data$Categories), "Sum"]
  expect_true(all(diff(as.numeric(sums)) >= 0))
})

# ---- plot_timeseries -------------------------------------------------------

test_that("plot_timeseries returns a ggplot object", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- plot_timeseries(otl)
  expect_s3_class(p, "ggplot")
})

test_that("plot_timeseries works with by = 'month'", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- plot_timeseries(otl, by = "month")
  expect_s3_class(p, "ggplot")
})

test_that("plot_timeseries works with type = 'bar'", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- plot_timeseries(otl, type = "bar")
  expect_s3_class(p, "ggplot")
})

test_that("plot_timeseries aggregates by week correctly", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- plot_timeseries(otl, by = "week")
  # Period column should be Mondays only
  plot_data <- p$data
  expect_true(all(weekdays(plot_data$Period) == "Monday"))
})

test_that("plot_timeseries stops on missing required columns", {
  bad <- data.table::data.table(X = 1:3)
  expect_error(plot_timeseries(bad), regexp = "missing required columns")
})

test_that("plot_timeseries accepts custom title", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- plot_timeseries(otl, title = "Time series test")
  expect_equal(p$labels$title, "Time series test")
})

# ---- compare_objectives ----------------------------------------------------

test_that("compare_objectives returns data.table with required columns", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  result <- compare_objectives(otl, cats_targets())
  expect_s3_class(result, "data.table")
  expect_true(all(c("Categories", "ActualHours", "TargetHours",
                    "Delta", "PctOfTarget") %in% colnames(result)))
})

test_that("compare_objectives Delta is ActualHours - TargetHours", {
  otl    <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  result <- compare_objectives(otl, cats_targets())
  expect_equal(result$Delta, result$ActualHours - result$TargetHours)
})

test_that("compare_objectives PctOfTarget is correct", {
  otl    <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  result <- compare_objectives(otl, cats_targets())
  expected_pct <- round(result$ActualHours / result$TargetHours * 100, 1)
  expect_equal(result$PctOfTarget, expected_pct)
})

test_that("compare_objectives only includes categories with targets", {
  otl    <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  result <- compare_objectives(otl, cats_targets())
  # Ignore & Leave, Sick, Leave etc have no target; should not appear
  expect_false("Ignore & Leave" %in% result$Categories)
  expect_false("Leave" %in% result$Categories)
})

test_that("compare_objectives plot = TRUE returns ggplot", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- compare_objectives(otl, cats_targets(), plot = TRUE)
  expect_s3_class(p, "ggplot")
})

test_that("compare_objectives plot uses coord_flip", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  p   <- compare_objectives(otl, cats_targets(), plot = TRUE)
  expect_true(inherits(p$coordinates, "CoordFlip"))
})

test_that("compare_objectives stops when no target_hours values set", {
  otl <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  # categories.yaml has no target_hours fields -- should stop
  expect_error(
    compare_objectives(otl, fixture("categories.yaml")),
    regexp = "target_hours"
  )
})

test_that("compare_objectives stops on missing merged_otl columns", {
  bad <- data.table::data.table(X = 1:3)
  expect_error(compare_objectives(bad, cats_targets()),
               regexp = "missing required columns")
})

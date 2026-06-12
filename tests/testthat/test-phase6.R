suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

otl_folder <- function() file.path(dirname(fixture("")), "otl_folder")

# ---- read_daytypes ---------------------------------------------------------

test_that("read_daytypes reads companion files and returns correct shape", {
  dt <- read_daytypes(otl_folder())
  expect_s3_class(dt, "data.table")
  expect_true(all(c("Date", "DayType") %in% colnames(dt)))
  expect_s3_class(dt$Date, "Date")
})

test_that("read_daytypes returns 14 rows for two weeks", {
  dt <- read_daytypes(otl_folder())
  expect_equal(nrow(dt), 14L)
})

test_that("read_daytypes includes Leave day type from week 2", {
  dt <- read_daytypes(otl_folder())
  expect_true("Leave" %in% dt$DayType)
})

test_that("read_daytypes stops on missing folder", {
  expect_error(read_daytypes("/nonexistent/folder"), regexp = "not found")
})

test_that("read_daytypes stops when no companion files exist", {
  tmp <- tempdir()
  expect_error(read_daytypes(tmp), regexp = "No day-type companion files")
})

# ---- mergeOTL with companion files -----------------------------------------

test_that("mergeOTL excludes daytypes files from OTL parsing", {
  # If companion files are accidentally parsed as OTL files the function
  # would error on the unexpected structure. A clean return proves exclusion.
  otl <- mergeOTL(
    folderOTL   = otl_folder(),
    category    = fixture("categories.yaml"),
    quarterYear = 'all'
  )
  expect_s3_class(otl, "data.table")
  expect_gt(nrow(otl), 0L)
})

# ---- calculate_flexi -------------------------------------------------------

test_that("calculate_flexi returns required columns", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  dts  <- read_daytypes(otl_folder())
  flex <- calculate_flexi(otl, dts)
  expect_true(all(c("Date", "DayType", "ActualHours",
                    "ContractedHours", "FlexiDelta", "FlexiBalance")
                  %in% colnames(flex)))
})

test_that("calculate_flexi sets ContractedHours to 0 on Leave day", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  dts  <- read_daytypes(otl_folder())
  flex <- calculate_flexi(otl, dts)
  leave_rows <- flex[DayType == "Leave"]
  expect_true(all(leave_rows$ContractedHours == 0))
})

test_that("calculate_flexi sets ContractedHours to 0 on Weekend", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  dts  <- read_daytypes(otl_folder())
  flex <- calculate_flexi(otl, dts)
  weekend_rows <- flex[DayType == "Weekend"]
  expect_true(all(weekend_rows$ContractedHours == 0))
})

test_that("calculate_flexi sets ContractedHours to contracted on Standard day", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  dts  <- read_daytypes(otl_folder())
  flex <- calculate_flexi(otl, dts, contracted = 7.4)
  std_rows <- flex[DayType == "Standard"]
  expect_true(all(std_rows$ContractedHours == 7.4))
})

test_that("calculate_flexi FlexiBalance is cumulative sum of FlexiDelta", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  dts  <- read_daytypes(otl_folder())
  flex <- calculate_flexi(otl, dts)
  data.table::setorder(flex, Date)
  expect_equal(flex$FlexiBalance, cumsum(flex$FlexiDelta))
})

test_that("calculate_flexi works with no day_types supplied", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  expect_message(
    calculate_flexi(otl, day_types = NULL),
    regexp = "all days treated as Standard"
  )
})

test_that("calculate_flexi stops on missing columns in merged_otl", {
  bad <- data.table::data.table(X = 1:3)
  expect_error(calculate_flexi(bad), regexp = "missing required columns")
})

test_that("calculate_flexi returns flexiData class", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  dts  <- read_daytypes(otl_folder())
  flex <- calculate_flexi(otl, dts)
  expect_true(inherits(flex, "flexiData"))
})

# ---- plot_flexi ------------------------------------------------------------

test_that("plot_flexi returns a ggplot object", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  dts  <- read_daytypes(otl_folder())
  flex <- calculate_flexi(otl, dts)
  p    <- plot_flexi(flex)
  expect_s3_class(p, "ggplot")
})

test_that("plot_flexi works with limits = FALSE", {
  otl  <- mergeOTL(otl_folder(), fixture("categories.yaml"), "all")
  dts  <- read_daytypes(otl_folder())
  flex <- calculate_flexi(otl, dts)
  p    <- plot_flexi(flex, limits = FALSE)
  expect_s3_class(p, "ggplot")
})

test_that("plot_flexi stops on missing FlexiBalance column", {
  bad <- data.table::data.table(Date = Sys.Date(), X = 1)
  expect_error(plot_flexi(bad), regexp = "missing required columns")
})

# ---- companion file written by createTC ------------------------------------

test_that("createTC writes companion day-type file alongside OTL", {
  tmp <- tempdir()
  createTC(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    pathOTL    = tmp,
    export     = TRUE
  )
  expected <- file.path(tmp, "OTL_wc_2024_05_13_daytypes.csv")
  expect_true(file.exists(expected))
})

test_that("companion file has correct columns and row count", {
  tmp <- tempdir()
  createTC(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    pathOTL    = tmp,
    export     = TRUE
  )
  companion <- data.table::fread(
    file.path(tmp, "OTL_wc_2024_05_13_daytypes.csv")
  )
  expect_true(all(c("Date", "DayType") %in% colnames(companion)))
  expect_equal(nrow(companion), 7L)  # Mon-Sun
})

test_that("companion file flags Friday as Leave", {
  tmp <- tempdir()
  createTC(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    week_start = "2024-05-13",
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1),
    pathOTL    = tmp,
    export     = TRUE
  )
  companion <- data.table::fread(
    file.path(tmp, "OTL_wc_2024_05_13_daytypes.csv")
  )
  companion[, Date := as.Date(Date)]
  fri <- companion[Date == as.Date("2024-05-17")]
  expect_equal(fri$DayType, "Leave")
})

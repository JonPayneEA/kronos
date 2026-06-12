suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
})

# ---- write_kronos_yml ------------------------------------------------------

test_that("write_kronos_yml creates a file", {
  tmp <- tempdir()
  yml_path <- file.path(tmp, "kronos.yml")
  if (file.exists(yml_path)) file.remove(yml_path)

  result <- write_kronos_yml(tmp)
  expect_true(file.exists(result))
})

test_that("write_kronos_yml content is valid YAML", {
  tmp <- tempdir()
  yml_path <- file.path(tmp, "kronos.yml")
  if (file.exists(yml_path)) file.remove(yml_path)

  write_kronos_yml(tmp)
  cfg <- yaml::read_yaml(yml_path)
  expect_true(is.list(cfg))
  expect_true("split" %in% names(cfg))
  expect_true("weight" %in% names(cfg))
})

test_that("write_kronos_yml stops if file already exists", {
  tmp      <- tempdir()
  yml_path <- file.path(tmp, "kronos.yml")
  if (!file.exists(yml_path)) write_kronos_yml(tmp)

  expect_error(write_kronos_yml(tmp), regexp = "already exists")
})

test_that("write_kronos_yml stops on missing folder", {
  expect_error(
    write_kronos_yml("/nonexistent/path"),
    regexp = "does not exist"
  )
})

# ---- .read_config ----------------------------------------------------------

test_that(".read_config reads a valid yml and returns named list", {
  tmp <- tempdir()
  yml_path <- file.path(tmp, "test_cfg.yml")
  yaml::write_yaml(list(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    pathOTL    = tmp,
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1)
  ), yml_path)

  cfg <- .read_config(yml_path)
  expect_true(is.list(cfg))
  expect_equal(cfg$split, c("Cap Skills", "FFIDP"))
})

test_that(".read_config stops on missing required keys", {
  tmp      <- tempdir()
  yml_path <- file.path(tmp, "incomplete.yml")
  yaml::write_yaml(list(categories = "x"), yml_path)

  expect_error(.read_config(yml_path), regexp = "missing required keys")
})

test_that(".read_config stops when split and weight lengths differ", {
  tmp      <- tempdir()
  yml_path <- file.path(tmp, "bad_weights.yml")
  yaml::write_yaml(list(
    categories = "x", outCal = "y", pathOTL = "z",
    split = c("A", "B"), weight = c(1)
  ), yml_path)

  expect_error(.read_config(yml_path), regexp = "same number")
})

test_that(".read_config stops when kronos.yml not found", {
  expect_error(
    .read_config("/nonexistent/kronos.yml"),
    regexp = "not found"
  )
})

# ---- run_kronos ------------------------------------------------------------

test_that("run_kronos runs from a valid config file", {
  tmp      <- tempdir()
  yml_path <- file.path(tmp, "run_test.yml")
  yaml::write_yaml(list(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    pathOTL    = tmp,
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1)
  ), yml_path)

  ts <- run_kronos(
    week_start = "2024-05-13",
    config     = yml_path,
    export     = FALSE
  )
  expect_s3_class(ts, "data.table")
  expect_gt(nrow(ts), 0L)
})

test_that("run_kronos returns invisibly", {
  tmp      <- tempdir()
  yml_path <- file.path(tmp, "invisible_test.yml")
  yaml::write_yaml(list(
    categories = fixture("categories.yaml"),
    outCal     = fixture("calendar_no_daily.xlsx"),
    pathOTL    = tmp,
    split      = c("Cap Skills", "FFIDP"),
    weight     = c(1, 1)
  ), yml_path)

  # withVisible() checks invisibility
  result <- withVisible(run_kronos(
    week_start = "2024-05-13",
    config     = yml_path,
    export     = FALSE
  ))
  expect_false(result$visible)
})

# ---- Pre-submission validation report --------------------------------------

test_that("createTC validation report prints to console on export", {
  tmp <- tempdir()
  # Capture output — the report goes to stdout via cat()
  output <- capture.output(
    createTC(
      categories = fixture("categories.yaml"),
      outCal     = fixture("calendar_no_daily.xlsx"),
      week_start = "2024-05-13",
      split      = c("Cap Skills", "FFIDP"),
      weight     = c(1, 1),
      pathOTL    = tmp,
      export     = TRUE
    )
  )
  # Report header should appear
  expect_true(any(grepl("pre-submission validation", output)))
  expect_true(any(grepl("Week commencing", output)))
  expect_true(any(grepl("Total working hours", output)))
})

# ---- magrittr removed ------------------------------------------------------

test_that("utils-pipe.R no longer exists", {
  r_files <- list.files(
    file.path(dirname(dirname(getwd())), "R"),
    pattern = "\\.R$"
  )
  expect_false("utils-pipe.R" %in% r_files)
})

test_that("no %>% usage in pipeline.R or createTC.R", {
  pipeline_src <- readLines(
    file.path(dirname(dirname(getwd())), "R", "pipeline.R")
  )
  createtc_src <- readLines(
    file.path(dirname(dirname(getwd())), "R", "createTC.R")
  )
  expect_false(any(grepl("%>%", pipeline_src)))
  expect_false(any(grepl("%>%", createtc_src)))
})

# tests/testthat/helper.R
# Sourced automatically by testthat before every test file.
# Loads all R source files so tests run without installing the package.

pkg_r <- list.files(
  file.path(dirname(dirname(getwd())), "R"),
  pattern    = "\\.R$",
  full.names = TRUE
)

# constants.R must be sourced first so pipeline.R can reference them
priority <- grep("constants\\.R", pkg_r)
others   <- setdiff(seq_along(pkg_r), priority)
ordered  <- pkg_r[c(priority, others)]

invisible(lapply(ordered, source))

# Fixture path helper
fixture <- function(filename) {
  file.path(dirname(getwd()), "fixtures", filename)
}

WEEK <- as.Date("2024-05-13")  # The Monday used in all fixtures

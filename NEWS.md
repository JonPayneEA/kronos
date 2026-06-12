# kronos NEWS

## kronos 0.6.0 (Phase 8)

### New features
- `run_kronos()`: single-function weekly runner that reads all configuration
  from `kronos.yml`. No arguments needed for the standard weekly case.
- Pre-submission validation report printed to console before every OTL export.
  Shows hours by day, flags days where hours do not sum to contracted total,
  and lists any unmatched categories.
- RStudio project template (`kronos`) scaffolds the working folder, writes a
  blank `kronos.yml`, and drops in a starter `categories.csv` and weekly
  batch script.
- `kronos.yml` configuration file support. Stores paths, contracted hours,
  split categories, and weights. Eliminates the need to pass arguments
  to `createTC()` manually each week.

### Changes
- `utils-pipe.R` removed. `magrittr` dependency dropped entirely. The native
  R pipe (`|>`) is available from R 4.1; the package now requires R >= 4.1.
- NAMESPACE regenerated to remove stale `dplyr`, `readr`, `tibble`, `tidyr`,
  and `magrittr` imports carried over from `planThis`.

---

## kronos 0.5.0 (Phase 7)

### New features
- `plot_timeseries()`: stacked area or bar chart of hours per category over
  time, aggregated by week or month.
- `compare_objectives()`: compares actual OTL hours against quarterly targets
  read from a `target_hours` column in the categories file. Returns a
  data.table or a divergence plot.
- `plot.mergedOTLs()` rewritten: stacked bar chart with date axis, weekly
  breaks, formatted labels, and a two-column legend.
- `plot.totalOTLs()` rewritten: horizontal ranked bar chart with hour labels,
  `coord_flip()`, and categories sorted by total descending.

---

## kronos 0.4.0 (Phase 5 & 6)

### New features
- `run_kronos()` placeholder added to exports (full implementation in 0.6.0).
- Calendar-as-source-of-truth: `createTC()` no longer requires the `daily`
  hours spreadsheet. When `daily = NULL` (default), the work week is generated
  from the calendar using standard-day defaults (07:48-15:12, 7.4 hrs).
- All-day calendar events override day type and hours for Leave, Sick, Flexi,
  Bank Holiday, and half-day variants automatically.
- `contracted_hours` parameter added to `createTC()`.
- UK bank holidays fetched automatically from the Cabinet Office JSON feed
  and cached locally for the calendar year.
- `calculate_flexi()`: calculates daily flexi deltas and running balance from
  merged OTL data and companion day-type files.
- `plot_flexi()`: line chart of cumulative flexi balance with carry-forward
  limit markers.
- `read_daytypes()`: reads all companion day-type files from an OTL folder.
- `createTC()` now writes a companion `_daytypes.csv` file alongside each
  OTL export.
- `mergeOTL()` updated to exclude companion files from OTL parsing.

### Deprecations
- `daily` parameter in `createTC()` deprecated. Will be removed in a future
  version.

---

## kronos 0.3.0 (Phase 4)

### New features
- Full `testthat` test suite added: 94 tests across 6 files.
- Fixture files in `tests/fixtures/` covering standard weeks, leave weeks,
  sick half-days, and calendar exports.

---

## kronos 0.2.0 (Phase 2 & 3)

### New features
- `constants.R`: all magic numbers and Oracle template row positions extracted
  as named constants.
- `pipeline.R`: `createTC()` decomposed into 9 internal stage functions,
  each independently testable.
- Deterministic hour allocation replaces stochastic `rmultinom()`.
- All error messages rewritten to name the specific problem and suggest a fix.
- Progress messages added to every pipeline stage.
- Blanket `suppressMessages`/`suppressWarnings` replaced with targeted
  suppressions on specific `readxl` calls.
- `createCatagsFile()` migrated from `tibble` to `data.table`.

### Breaking changes
- `dplyr`, `tibble`, `magrittr`, `readr`, and `tidyr` removed from pipeline.
  All operations now use `data.table`.

---

## kronos 0.1.0 (Phase 1)

### Renamed from `planThis` (v0.0.6.9001)

### Bug fixes
- `mergeOTL()`: `folder` parameter reference corrected to `folderOTL`;
  `cats` corrected to `category`; `quarterYear == 'current'` block moved
  to after `OTL` is constructed.
- `createTC()`: `week_start` validation changed from `warning()` to `stop()`.
- `createTC()`: `filter(Date != slDates)` corrected to
  `filter(!Date %in% slDates)`.
- `createTC_v2.R` removed from repository.
- Typos in `subFunctions.R` documentation corrected.

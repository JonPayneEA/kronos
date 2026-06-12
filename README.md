# kronos

<img src="man/figures/logo.png" align="right" width="160" alt="kronos logo"/>

An R package for generating OTL time cards from
Outlook calendar data. Tracks flexi balance automatically, produces
historical time allocation analysis, and compares actual hours against
quarterly targets.

Renamed from `planThis` (v0.0.6.9001).

---

## Requirements

- R >= 4.1.0
- Outlook Classic with colour categories assigned to appointments
- Power Automate flow exporting the calendar weekly to an xlsx file

---

## Installation

The package is not on CRAN. Install from source:

```r
# Install devtools if needed
install.packages("devtools")

devtools::install_github("JonPayneEA/kronos")
```

---

## Quick start

**First time only:**

```r
library(kronos)

# 1. Create a project folder with scaffolded structure
#    (or use File > New Project > kronos in RStudio)
write_kronos_yml("C:/Users/yourname/Time")

# 2. Edit C:/Users/yourname/Time/kronos.yml with your paths
# 3. Edit Config/categories.yaml with your Oracle project codes
```

**Every week:**

```r
library(kronos)
run_kronos()
```

That is all. The OTL form lands in the `pathOTL` folder specified in
`kronos.yml`. A validation summary prints to the console before the
file is written.

---

## Configuration

`kronos.yml` stores all settings. A minimal example:

```yaml
categories: C:/Users/yourname/Time/Config/categories.yaml
outCal:     C:/Users/yourname/Time/Calendar/Calendar.xlsx
pathOTL:    C:/Users/yourname/Time/OTLs

split:
  - Cap Skills
  - FFIDP
  - Reactive Forecasting

weight:
  - 1
  - 2
  - 1

# contracted_hours: 7.4  # default; change if your hours differ
```

`split` is the list of categories that receive any hours not explicitly
covered by calendar appointments. `weight` controls the proportional
split between them.

---

## Calendar setup

kronos reads the calendar from a Power Automate xlsx export. The flow
appends one week of data to a single file each week. Set the flow to
write to the fixed path specified in `outCal` in `kronos.yml` and leave
it running. The file grows over time; kronos filters to the relevant
week on each run.

kronos checks the most recent event date in the file on every run. If
it is more than 14 days old, a warning is printed before submission to
flag that the flow may not have appended this week.

### Flow setup

The flow needs three steps:

1. **Recurrence trigger** — weekly, Monday 07:00 UK time
2. **Get calendar view of events** — Office 365 Outlook connector,
   previous Monday to Sunday. Use `Get calendar view of events` rather
   than `Get events`; it expands recurring meetings into individual
   instances.
3. **Add a row to a table** — Excel Online (Business) connector,
   appending to the fixed xlsx file on OneDrive

The date window for step 2 (calculated from the trigger time):

- Start: `addDays(startOfWeek(triggerBody()['timestamp'], 1), -7)`
- End: `startOfWeek(triggerBody()['timestamp'], 1)`

The flow must export these fields:

| Field | Description |
|---|---|
| `Event` | Appointment subject |
| `Start Time` | ISO 8601 datetime |
| `End Time` | ISO 8601 datetime |
| `Categories` | Outlook colour category name(s), comma-delimited |
| `allDay` | Boolean |

### Colour categories

Every appointment that should appear in the time card must have an
Outlook colour category assigned. The category name must match the
`Categories` column in your `categories.yaml` exactly, including case
and spacing.

Appointments with no category, or with `Ignore & Leave` assigned,
are excluded.

### Leave, sick, and bank holidays

Add leave and sick entries as all-day calendar events with the
appropriate colour category:

| Category name | Effect |
|---|---|
| `Annual Leave` or `Leave` | Full day leave, zero hours |
| `Leave Half AM` or `Leave Half PM` | Half day leave, 3.7 hours |
| `Sick` | Full day sick, zero hours |
| `Sick Half` | Half day sick, 3.7 hours |
| `Flexi` | Flexi day taken, zero hours |
| `Flexi Half` | Half flexi day, 3.7 hours |
| `Bank Holiday` | Bank holiday, zero hours |

UK bank holidays are also detected automatically from the Cabinet Office
JSON feed and cached locally for the calendar year. You do not need to
add them to the calendar manually.

---

## Standard working day defaults

When no daily hours spreadsheet is supplied (the default), kronos assumes:

- Start: 07:48
- End: 15:12
- Lunch: 37 minutes
- Net hours: 7.4

These defaults are overridden by all-day calendar events (see above) and
by the long-day rule: if timed appointments on a standard day sum to
more than 7.4 hours, the contracted total for that day is raised to
match.

The `contracted_hours` key in `kronos.yml` overrides the 7.4 default
for all standard days in every run.

---

## Flexi tracking

After several weeks of exports, the flexi balance is calculated from the
OTL data and companion day-type files written alongside each export:

```r
otl  <- mergeOTL(folderOTL = 'C:/Time/OTLs',
                 category  = 'C:/Time/Config/categories.yaml')
dts  <- read_daytypes('C:/Time/OTLs')
flex <- calculate_flexi(otl, dts)
plot_flexi(flex)
```

`calculate_flexi()` computes the daily delta (actual hours minus
contracted hours) and a cumulative running balance. Leave, sick, bank
holiday, and weekend days contribute zero delta. The plot shows the
balance over time with reference lines at the EA carry-forward limits
(±10 hours).

---

## Analysis

```r
# Aggregate all OTL data
otl <- mergeOTL(folderOTL = 'C:/Time/OTLs',
                category  = 'C:/Time/Config/categories.yaml',
                quarterYear = 'current')

# Hours per day stacked by category
plot(otl)

# Total hours by category (current quarter)
totals <- mergeOTL(..., aggregate = TRUE)
plot(totals)

# Time allocation over time
plot_timeseries(otl, by = 'week')
plot_timeseries(otl, by = 'month', type = 'bar')

# Actuals vs quarterly targets
# (requires target_hours column in categories.yaml)
compare_objectives(otl, categories = 'C:/Time/Config/categories.yaml')
compare_objectives(otl, categories = 'C:/Time/Config/categories.yaml',
                   plot = TRUE)
```

To use `compare_objectives()`, add a `target_hours` column to
`categories.yaml` with the quarterly hour target for each category.
Leave it blank for categories without a target.

---

## Categories file

The categories file maps Outlook colour category names to Oracle OTL
project codes. It is a CSV with these columns:

| Column | Description |
|---|---|
| `Categories` | Outlook colour category name |
| `Description` | Human-readable description (not used by the pipeline) |
| `Code` | Oracle project/ABC code |
| `Task` | Oracle task number |
| `Type` | Oracle hours type string |
| `target_hours` | Optional quarterly target for `compare_objectives()` |

Generate a starter file with:

```r
createCatagsFile(path = 'C:/Time/Config')
```

Then edit `Code` and `Task` to match your Oracle project codes.

---

## Legacy: daily hours spreadsheet

Older versions of `planThis` required a daily hours xlsx spreadsheet.
This is no longer needed. The `daily` parameter in `createTC()` is
retained for backwards compatibility but is deprecated and will be
removed in a future version.

If you have existing weekly batch scripts using the old interface, they
will continue to work. Migrate to `run_kronos()` when convenient.

---

## Function reference

| Function | Description |
|---|---|
| `run_kronos()` | Weekly runner from `kronos.yml` |
| `write_kronos_yml()` | Write a starter config file |
| `createTC()` | Build a time card (called by `run_kronos`) |
| `createCatagsFile()` | Write a starter categories YAML |
| `mergeOTL()` | Merge historical OTL exports |
| `read_daytypes()` | Read companion day-type files |
| `calculate_flexi()` | Calculate flexi balance |
| `plot_flexi()` | Plot cumulative flexi balance |
| `plot_timeseries()` | Hours by category over time |
| `compare_objectives()` | Actuals vs quarterly targets |
| `plot()` | Bar charts for `mergedOTLs` and `totalOTLs` objects |

---

## Development

```r
# Run the test suite
devtools::test()

# Rebuild documentation
devtools::document()
```

Tests are in `tests/testthat/`. Fixture files are in `tests/fixtures/`.
The snapshot test in `test-snapshot.R` locks the exact pipeline output
for a known week; delete `tests/testthat/_snaps/` to regenerate after
a deliberate logic change.

---

## Licence

GPL (>= 3)

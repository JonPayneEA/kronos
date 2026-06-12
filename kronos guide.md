# kronos: Complete User Guide

**Version 0.6.0**

-----

## Contents

1. [What kronos does](#1-what-kronos-does)
1. [Installation](#2-installation)
1. [First-time setup](#3-first-time-setup)
1. [The categories file](#4-the-categories-file)
1. [Power Automate calendar export](#5-power-automate-calendar-export)
1. [Configuration: kronos.yml](#6-configuration-kronosyml)
1. [The weekly workflow](#7-the-weekly-workflow)
1. [Calendar conventions](#8-calendar-conventions)
1. [How hours are allocated](#9-how-hours-are-allocated)
1. [The validation report](#10-the-validation-report)
1. [The OTL export](#11-the-otl-export)
1. [Flexi tracking](#12-flexi-tracking)
1. [Historical analysis](#13-historical-analysis)
1. [Objective comparison](#14-objective-comparison)
1. [Advanced usage](#15-advanced-usage)
1. [Function reference](#16-function-reference)
1. [Troubleshooting](#17-troubleshooting)

-----

## 1. What kronos does

kronos generates Oracle Time and Labour (OTL) time cards from an Outlook
calendar export. It reads a weekly calendar file produced by Power Automate,
determines how many hours were worked each day, maps appointments to Oracle
project codes, and writes a correctly formatted CSV that Oracle accepts.

It also tracks flexi balance over time, produces charts of historical time
allocation, and compares actual hours against quarterly targets.

The daily hours spreadsheet previously required by `planThis` is no longer
needed. kronos derives the working day from calendar data and standard
defaults, overriding those defaults when leave, sick, flexi, or bank holidays
appear as all-day calendar events.

-----

## 2. Installation

kronos is not on CRAN. Install from GitHub:

```r
install.packages("devtools")
devtools::install_github("JonPayneEA/kronos")
```

R >= 4.1.0 is required.

-----

## 3. First-time setup

Run this once to scaffold your working folder:

```r
library(kronos)
write_kronos_yml("C:/Users/yourname/Time")
```

This writes a starter `kronos.yml` to the folder. It also runs
`createCatagsFile()` to drop a starter `categories.yaml` into a `Config`
subfolder and creates a `run_weekly.R` script.

The resulting folder structure is:

```
C:/Users/yourname/Time/
  kronos.yml
  run_weekly.R
  Config/
    categories.yaml
  Calendar/       <- Power Automate writes here
  OTLs/           <- kronos writes here
```

Edit `kronos.yml` with your actual paths. Edit `Config/categories.yaml`
with your Oracle project codes. Once those two files are correct, the
weekly workflow is a single line.

If you use the RStudio project template (`File > New Project > New Directory

> kronos Time Recording Project`), this scaffolding happens automatically
> inside a new RStudio project.

-----

## 4. The categories file

The categories file is a YAML file that maps Outlook colour category names
to Oracle OTL project codes. Every category you assign to appointments in
Outlook must have a corresponding entry here.

### Structure

```yaml
categories:
  - name: Cap Skills
    description: Capital Training
    code: ENVHOABCPC120
    task: '03'
    type: STAFF Plain Time-Straight Time

  - name: Leave
    description: Leave
    code: ENVABE
    task: '02'
    type: STAFF Plain Time-Straight Time
```

### Required fields per entry

|Field |Description                                      |
|------|-------------------------------------------------|
|`name`|Outlook colour category name — must match exactly|
|`code`|Oracle project/ABC code                          |
|`task`|Oracle task number                               |
|`type`|Oracle hours type string                         |

### Optional fields

|Field         |Description                                      |
|--------------|-------------------------------------------------|
|`description` |Human-readable label (not used by the pipeline)  |
|`target_hours`|Quarterly target hours for `compare_objectives()`|

### Generating a starter file

```r
createCatagsFile(path = "C:/Users/yourname/Time/Config")
```

This writes a `categories.yaml` with the standard EA category set. Edit
the `code` and `task` fields to match your Oracle project codes before
using it.

### Name matching

The `name` field must match your Outlook colour category names exactly:
case, spacing, and punctuation all matter. If an appointment carries a
category called `Cap Skills` in Outlook but the file has `Cap skills`,
it will not match and those hours will be excluded from the time card
with a warning.

### Special categories

Two categories are treated specially and should always be present even
if they carry no Oracle code:

`Ignore & Leave` — any appointment tagged with this is excluded from the
time card entirely. Use it for personal appointments, declined meetings
that stayed in the calendar, or anything else you do not want recorded.

`Duty` — excluded from the time card by default. Change this if your
duty category maps to a billable code.

-----

## 5. Power Automate calendar export

kronos reads a single xlsx file that Power Automate appends to each week.
The file grows over time; kronos filters to the relevant week on each run.

### Flow setup

The flow has three steps:

**Step 1: Recurrence trigger**
Weekly, Monday 07:00 UK time.

**Step 2: Get calendar view of events**
Use the `Get calendar view of events` action from the Office 365 Outlook
connector — not `Get events`. The distinction matters: `Get calendar view`
expands recurring meetings into individual instances. `Get events` returns
the series master, which has the wrong date.

Set the date window using these expressions (calculated from the trigger
time):

- Start: `addDays(startOfWeek(triggerBody()['timestamp'], 1), -7)`
- End: `startOfWeek(triggerBody()['timestamp'], 1)`

**Step 3: Add rows to a table**
Excel Online (Business) connector, appending to the fixed xlsx file on
OneDrive. The file path must match `outCal` in `kronos.yml`.

### Required fields

The flow must export these columns:

|Field       |Description                                   |
|------------|----------------------------------------------|
|`Event`     |Appointment subject                           |
|`Start Time`|ISO 8601 datetime                             |
|`End Time`  |ISO 8601 datetime                             |
|`Categories`|Outlook colour category names, comma-delimited|
|`allDay`    |Boolean                                       |

### Freshness check

kronos checks the most recent event date in the file on every run. If it
is more than 14 days old, a warning is printed before submission. This
catches the case where the flow has stopped running silently.

-----

## 6. Configuration: kronos.yml

`kronos.yml` stores all settings. `run_kronos()` reads it; you do not
pass arguments manually each week.

### Full example

```yaml
# kronos configuration
# Edit the paths below then run run_kronos() each week.

# Path to your categories YAML file
categories: C:/Users/yourname/Time/Config/categories.yaml

# Path to the Power Automate calendar export (updated weekly)
outCal: C:/Users/yourname/Time/Calendar/Calendar.xlsx

# Folder where OTL exports are saved
pathOTL: C:/Users/yourname/Time/OTLs

# Categories to distribute unallocated time across
split:
  - Cap Skills
  - FFIDP
  - Reactive Forecasting

# Weights for each split category (same order as split)
# Higher weight = larger share of unallocated time
weight:
  - 1
  - 2
  - 1

# Contracted hours per day (default 7.4 if not set)
# contracted_hours: 7.4
```

### Keys

**`categories`** (required) — path to the categories YAML.

**`outCal`** (required) — path to the Power Automate xlsx export.

**`pathOTL`** (required) — folder where OTL CSV files are written.
One file is written per week: `OTL_wc_YYYY_MM_DD.yaml`. A companion
`OTL_wc_YYYY_MM_DD_daytypes.yaml` is also written alongside each OTL
file for flexi tracking.

**`split`** (required) — a list of category names that receive any
hours not covered by explicit calendar appointments. These must match
entries in the `Categories` column of your categories file.

**`weight`** (required) — a list of numbers, one per split category,
controlling the proportional allocation. A weight of `[1, 2, 1]` gives
the second category twice as many hours as the first and third. Weights
do not need to sum to any particular value.

**`contracted_hours`** (optional) — overrides the default of 7.4 hours
per standard working day. Uncomment and set if your contracted hours differ.

-----

## 7. The weekly workflow

### Standard run

```r
library(kronos)
run_kronos()
```

This reads `kronos.yml` from the working directory, determines the most
recently completed working week, processes the calendar, and writes the OTL
form. A validation summary prints to the console before the file is written.

### Specifying a week

```r
run_kronos(week_start = "2024-05-13")
```

`week_start` must be a Monday. If you supply a Tuesday or any other day,
the function stops immediately with a clear error.

### Previewing without exporting

```r
run_kronos(export = FALSE)
```

Runs the full pipeline and prints the validation report but does not write
any files. Useful for checking the output before committing.

### Using a different config file

```r
run_kronos(config = "C:/Projects/other_project/kronos.yml")
```

Useful if you maintain separate configurations for different roles or
secondments.

### Calling createTC() directly

`run_kronos()` is a thin wrapper over `createTC()`. You can call
`createTC()` directly if you need more control:

```r
tc <- createTC(
  categories = "C:/Time/Config/categories.yaml",
  outCal     = "C:/Time/Calendar/Calendar.xlsx",
  week_start = "2024-05-13",
  split      = c("Cap Skills", "FFIDP", "Reactive Forecasting"),
  weight     = c(1, 2, 1),
  pathOTL    = "C:/Time/OTLs",
  export     = TRUE
)
```

The return value is a data.table with one row per Oracle code/task/type
combination and one column per day of the week.

-----

## 8. Calendar conventions

### Colour categories

Every appointment that should appear in the time card needs an Outlook
colour category. Assign them in Outlook via the Categories button or
by right-clicking an appointment.

Appointments with no category are excluded. Appointments tagged
`Ignore & Leave` are excluded. Everything else is matched against the
categories file.

An appointment can carry more than one category. Separate them with
a comma in Outlook’s category field. kronos splits the appointment’s
hours equally between all assigned categories.

### Leave, sick, and bank holidays

Enter these as all-day calendar events with the appropriate colour
category. kronos detects them automatically and sets the day’s
contracted hours accordingly.

|Category name                     |Day type    |Hours allocated|
|----------------------------------|------------|---------------|
|`Annual Leave` or `Leave`         |Leave       |0              |
|`Leave Half AM` or `Leave Half PM`|Leave Half  |3.7            |
|`Sick`                            |Sick        |0              |
|`Sick Half`                       |Sick Half   |3.7            |
|`Flexi`                           |Flexi       |0              |
|`Flexi Half AM` or `Flexi Half PM`|Flexi Half  |3.7            |
|`Bank Holiday`                    |Bank Holiday|0              |

For half-days, `AM` and `PM` variants are both recognised. The
distinction does not affect hour allocation currently — both produce
3.7 hours — but it is preserved in the companion day-type file for
potential future use.

### Bank holidays

UK bank holidays for England are fetched automatically from the Cabinet
Office JSON feed at `https://www.gov.uk/bank-holidays.json` and cached
locally for the calendar year. Any date matching a bank holiday is set
to zero hours without needing a calendar entry.

The cache is stored in your R user cache directory. To force a refresh:

```r
kronos:::.fetch_bank_holidays(force_refresh = TRUE)
```

If the fetch fails (no network access, firewall), kronos warns and
continues. Add `Bank Holiday` as a calendar all-day event for that
week as a manual fallback.

### Long days

If timed appointments on a standard day sum to more than the contracted
hours (7.4 by default), kronos raises the day’s total to match the
calendar. The extra hours appear in the split categories. No manual
input is needed for occasional long days.

-----

## 9. How hours are allocated

Understanding the allocation logic helps when the time card looks
unexpected.

### Stage 1: Work week skeleton

kronos builds a 7-row table for the week. Each standard working day
starts with the default: 07:48 start, 15:12 end, 37-minute lunch,
7.4 hours net. Weekends are set to zero. All-day calendar events
override any day they fall on.

### Stage 2: Calendar appointments

Each timed appointment is assigned its duration in hours and joined
to the categories file to get the Oracle code. Multi-category
appointments have their duration divided equally.

### Stage 3: Sick and leave rows

Any day typed as Leave, Sick, or similar gets a corresponding row
in the time card with the relevant ENVABE code. Calendar appointments
on full sick or leave days are removed — you cannot record project
hours on a day you were not working.

### Stage 4: All-day work appointments

Some calendar events are booked as all-day (a full-day training
course, for example). These carry no intrinsic hour count. kronos
calculates the hours not covered by timed appointments on the same
day and assigns that remainder to the all-day events, split equally
if there are more than one.

### Stage 5: Excess hour distribution

After all calendar appointments are accounted for, any remaining
unallocated hours on standard days are distributed across the split
categories. The distribution is proportional to the weights supplied
in `kronos.yml` and is deterministic: the same inputs produce the
same output every time.

The weights are normalised, hours rounded to 0.1, and any rounding
residual is added to the largest bucket. The result always sums
exactly to the contracted hours for the day.

-----

## 10. The validation report

Before writing any file, kronos prints a summary to the console:

```
----------------------------------------------------
 kronos: pre-submission validation
 Week commencing: 13 May 2024
----------------------------------------------------

 Day   Type            Hours  Status
 ------------------------------------------------
 Mon   Standard          7.4  OK
 Tue   Standard          7.9  LONG (+0.5 hrs)
 Wed   Standard          7.4  OK
 Thu   Standard          7.4  OK
 Fri   Leave             0.0  Leave
 Sat   Weekend           0.0
 Sun   Weekend           0.0

 Total working hours recorded: 30.1
----------------------------------------------------
```

`OK` means the day’s recorded hours match contracted hours exactly.
`LONG` means the calendar ran long and the extra hours have been
absorbed into the split categories. `SHORT` means hours are below
contracted — this should not happen in normal operation; if it does,
check the calendar for gaps.

Any rows with no Oracle code are flagged here too. These are excluded
from the OTL export; the warning names the categories involved so you
can fix the categories file before resubmitting.

-----

## 11. The OTL export

Two files are written to `pathOTL` for each week:

**`OTL_wc_YYYY_MM_DD.yaml`** — the Oracle time card. Upload this to
Oracle Time and Labour. The format matches what Oracle expects: a
matrix with project codes and tasks on rows, days of the week on
columns, and the Oracle header and footer boilerplate in place.

**`OTL_wc_YYYY_MM_DD_daytypes.yaml`** — a companion file recording the
day type (Standard, Leave, Sick, etc.) for each of the seven days.
This feeds the flexi tracking calculation and should not be deleted.

Both files are written atomically: the validation report is printed
first, and the files are only written after that check completes. If
the pipeline errors before that point, no files are written.

-----

## 12. Flexi tracking

The flexi balance is calculated from the accumulated OTL data and the
companion day-type files.

### Calculating the balance

```r
library(kronos)

otl  <- mergeOTL(
  folderOTL   = "C:/Time/OTLs",
  category    = "C:/Time/Config/categories.yaml",
  quarterYear = "all"
)

dts  <- read_daytypes("C:/Time/OTLs")
flex <- calculate_flexi(otl, dts)
```

`calculate_flexi()` returns a data.table with one row per calendar day:

|Column           |Description                            |
|-----------------|---------------------------------------|
|`Date`           |Calendar date                          |
|`DayType`        |Standard, Leave, Sick, etc.            |
|`ActualHours`    |Hours recorded in the OTL              |
|`ContractedHours`|7.4 for standard days, 0 for all others|
|`FlexiDelta`     |ActualHours minus ContractedHours      |
|`FlexiBalance`   |Cumulative sum of FlexiDelta           |

The current balance is the `FlexiBalance` value on the last row.

### Plotting the balance

```r
plot_flexi(flex)
```

This produces a line chart of the cumulative balance over time, with
blue fill above zero and red fill below. Dashed lines mark the EA
carry-forward limits at ±10 hours. The subtitle shows the current
balance.

```r
# Without limit lines
plot_flexi(flex, limits = FALSE)

# Custom title
plot_flexi(flex, title = "My flexi balance Q1 2024")
```

### Carry-forward warnings

`calculate_flexi()` warns automatically if the balance exceeds +10 hours
or falls below -10 hours on any day, telling you how many days are
outside the permitted range and what the peak or trough value is.

### Using a different contracted hours figure

```r
flex <- calculate_flexi(otl, dts, contracted = 7.0)
```

-----

## 13. Historical analysis

### Merging all OTL exports

```r
# All time, all categories
otl_all <- mergeOTL(
  folderOTL   = "C:/Time/OTLs",
  category    = "C:/Time/Config/categories.yaml",
  quarterYear = "all"
)

# Current quarter only
otl_q   <- mergeOTL(
  folderOTL   = "C:/Time/OTLs",
  category    = "C:/Time/Config/categories.yaml",
  quarterYear = "current"
)

# A specific quarter
otl_q1  <- mergeOTL(
  folderOTL   = "C:/Time/OTLs",
  category    = "C:/Time/Config/categories.yaml",
  quarterYear = "Q1 2024"
)

# Aggregated totals
totals <- mergeOTL(
  folderOTL   = "C:/Time/OTLs",
  category    = "C:/Time/Config/categories.yaml",
  aggregate   = TRUE
)
```

`mergeOTL()` returns a data.table of class `mergedOTLs` with columns
`Categories`, `Date`, `Hours`, and `Quarter`. The `aggregate = TRUE`
variant returns a `totalOTLs` object with columns `Categories` and `Sum`.

### Daily hours chart

```r
plot(otl_q)
```

A stacked bar chart of daily hours by category for the period. Each bar
is one working day; segments show the category split. The x-axis has
weekly date breaks.

### Total hours chart

```r
plot(totals)
```

A horizontal bar chart of total hours per category, sorted descending.
Hour labels appear at the end of each bar.

### Time-series chart

```r
# Weekly stacked area
plot_timeseries(otl_all)

# Monthly stacked bar
plot_timeseries(otl_all, by = "month", type = "bar")
```

`by` controls the aggregation period: `"week"` or `"month"`.
`type` controls the geometry: `"area"` (default) or `"bar"`.

The weekly view floors each date to the preceding Monday. The monthly
view floors to the first of the month. Both use `scale_fill_brewer`
with the `Paired` palette; all charts are `ggplot2` objects and accept
further layers.

```r
# Add a custom theme
library(ggplot2)
plot_timeseries(otl_all) +
  theme(legend.position = "right")
```

-----

## 14. Objective comparison

`compare_objectives()` compares actual OTL hours against quarterly
targets you define in the categories file.

### Setting targets

Add a `target_hours` field to each entry in `categories.yaml` with the
quarterly hour target. Leave it out or set it to null for categories
without a target.

```yaml
categories:
  - name: Cap Skills
    code: ENVHOABCPC120
    task: '03'
    type: STAFF Plain Time-Straight Time
    target_hours: 20

  - name: FFIDP
    code: ENVFCPIM001086B00C
    task: EA001
    type: STAFF Plain Time-Straight Time
    target_hours: 40

  - name: Admin
    code: ENVEGM5.16
    task: '010'
    type: STAFF Plain Time-Straight Time
    # no target_hours — excluded from comparison
```

### Comparing actuals against targets

```r
# Tabular output
result <- compare_objectives(
  otl_q,
  categories = "C:/Time/Config/categories.yaml"
)
print(result)
```

Returns a data.table with columns `Categories`, `ActualHours`,
`TargetHours`, `Delta`, and `PctOfTarget`. Categories without a
target are excluded. Rows are ordered by `Delta` ascending — the
most under-target categories appear first.

```r
# Divergence chart
compare_objectives(
  otl_q,
  categories = "C:/Time/Config/categories.yaml",
  plot       = TRUE
)
```

A horizontal divergence bar chart. Bars to the right are over target
(blue); bars to the left are under target (red). The subtitle shows
the count in each direction.

### Running against the current quarter

The comparison is most useful against a filtered quarter rather than
all time:

```r
otl_q <- mergeOTL("C:/Time/OTLs", "C:/Time/Config/categories.yaml",
                  quarterYear = "current")
compare_objectives(otl_q, "C:/Time/Config/categories.yaml", plot = TRUE)
```

-----

## 15. Advanced usage

### Running a backfill week

If you missed a week and need to generate the OTL retroactively:

```r
run_kronos(week_start = "2024-04-15")
```

kronos filters the calendar file to that week. As long as Power Automate
has appended data that far back, the pipeline works identically to a
current-week run.

### Non-standard contracted hours

If your contracted hours differ from 7.4:

```r
# Via config file
# In kronos.yml: contracted_hours: 7.0

# Via createTC() directly
createTC(
  ...,
  contracted_hours = 7.0
)
```

The override applies for the duration of the call and restores the
default afterwards.

### Inspecting the pipeline output

`run_kronos()` returns the time card data.table invisibly. Capture it
to inspect before submitting:

```r
tc <- run_kronos(export = FALSE)
print(tc)
```

The time card has one row per Oracle code/task/type combination and
columns `Code`, `Task`, `Type`, `hoursType`, `Mon`, `Tue`, `Wed`,
`Thu`, `Fri`, `Sat`, `Sun`. Hours for each day are numeric.

### Merging a specific quarter

OTL quarters follow the EA financial year (April start):

```r
# Q1 2024/25 = April-June 2024
otl <- mergeOTL(..., quarterYear = "Q1 2024")

# Q4 2023/24 = January-March 2024
otl <- mergeOTL(..., quarterYear = "Q4 2023")
```

-----

## 16. Function reference

### Core pipeline

**`run_kronos(week_start, config, export)`**
Weekly runner. Reads `kronos.yml` and calls `createTC()`. The standard
entry point for normal weekly use.

**`createTC(categories, outCal, week_start, split, weight, pathOTL, export, daily, contracted_hours)`**
Builds the time card. Called by `run_kronos()`; also callable directly
for more control. Returns a data.table. The `daily` parameter is
deprecated.

**`write_kronos_yml(path)`**
Writes a starter `kronos.yml` to the supplied folder.

**`createCatagsFile(path)`**
Writes a starter `categories.yaml` to the supplied folder.

### OTL aggregation

**`mergeOTL(folderOTL, category, quarterYear, aggregate)`**
Reads all OTL CSV files from a folder and merges them. `quarterYear`
accepts `"all"`, `"current"`, or `"Qx YYYY"`. Returns a `mergedOTLs`
data.table, or a `totalOTLs` data.table when `aggregate = TRUE`.

**`read_daytypes(folderOTL)`**
Reads all companion `_daytypes.yaml` files from a folder and returns a
data.table with `Date` and `DayType` columns.

### Flexi tracking

**`calculate_flexi(merged_otl, day_types, contracted)`**
Calculates daily flexi deltas and running balance. Returns a `flexiData`
data.table. Warns if the balance breaches carry-forward limits.

**`plot_flexi(flexi_data, limits, title)`**
Line chart of the cumulative flexi balance. `limits = TRUE` draws
dashed lines at ±10 hours.

### Analysis

**`plot(x, title, ...)`**
S3 method for `mergedOTLs` and `totalOTLs` objects. Daily stacked bar
chart or total horizontal bar chart respectively.

**`plot_timeseries(merged_otl, by, type, title)`**
Hours per category over time. `by`: `"week"` or `"month"`.
`type`: `"area"` or `"bar"`.

**`compare_objectives(merged_otl, categories, plot, title)`**
Actuals vs quarterly targets from the categories file. Returns a
data.table or a ggplot2 divergence chart when `plot = TRUE`.

### Utilities

**`getRecentMondays()`**
Returns a Date vector of all Mondays in the past 70 days. Used
internally for automatic week resolution.

**`is.integer0(x)`**
Returns `TRUE` if `x` is `integer(0)`. Used internally.

**`toTime(x)`**, **`toHMS(x)`**, **`toHours(x)`**, **`fixTimes(date, endStart)`**
Time conversion utilities. Used internally by the daily hours parser.

-----

## 17. Troubleshooting

### “Tasks not found in categories file”

The split categories in `kronos.yml` do not match any row in the
`Categories` column of `categories.yaml`. Check for typos, extra spaces,
or capitalisation differences. The match is case-sensitive.

### “Calendar file is missing expected columns”

The Power Automate export does not contain one or more of `Event`,
`Start Time`, `End Time`, `Categories`, `allDay`. Check the flow is
mapping all required fields and has run at least once to create the
table structure.

### “week_start must be a Monday”

The date supplied to `week_start` is not a Monday. Either correct the
date or omit `week_start` entirely to let kronos pick the most recently
completed week automatically.

### “week_start not found in daily hours”

Only relevant when the deprecated `daily` parameter is supplied. The
date does not appear in the daily hours spreadsheet.

### Calendar events returning wrong hours

The most common cause is that Power Automate is using `Get events`
rather than `Get calendar view of events`. Recurring meetings return
the series master date rather than the instance date. Switch to
`Get calendar view of events` in the flow.

### Hours do not sum to contracted

Shown as `SHORT` in the validation report. Causes:

- Appointments are missing categories and being excluded.
- The calendar export did not capture all appointments for the week
  (check the date range in the Power Automate flow).
- An appointment is tagged with an unrecognised category that does not
  match the categories file.

Any excluded categories are named in the validation report.

### Bank holiday not detected

Either the Cabinet Office fetch failed or the date is not in the
England list (Scottish bank holidays differ). Add a `Bank Holiday`
all-day calendar event as a manual override.

### Flexi balance looks wrong

Check that companion `_daytypes.yaml` files exist for the weeks in
question. These are written by `createTC()` from version 0.4.0 onwards.
OTL exports from earlier versions of `planThis` do not have them.
For those older weeks, `calculate_flexi()` with no `day_types` argument
treats all days as Standard — which is correct for weeks with no
leave but will overcount the balance for leave weeks.

### The validation report shows a WARNING row

A row in the time card has no Oracle code. This means an appointment
category did not match the categories file. The warning names the
unmatched categories. Add them to `categories.yaml` with the correct
Oracle code and rerun.
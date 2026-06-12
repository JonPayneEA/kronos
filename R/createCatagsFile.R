#' @title Create a starter categories file
#'
#' @description Writes a starter categories YAML file to the supplied folder.
#'   This file maps Outlook colour category names to Oracle OTL time codes.
#'   Edit it to match your own project codes before using with createTC().
#'
#' @param path Folder path where the file should be saved
#'
#' @return Invisibly returns the full path to the written file
#' @export
#'
#' @importFrom yaml write_yaml
#'
#' @examples
#' \dontrun{
#' createCatagsFile(path = 'C:/Users/jpayne05/Time/Config')
#' }
createCatagsFile <- function(path = NULL) {

  if (is.null(path)) {
    stop('path must be supplied.\n',
         '  Example: createCatagsFile(path = "C:/Users/yourname/Time/Config")')
  }

  if (!dir.exists(path)) {
    stop('Folder does not exist: ', path, '\n',
         '  Create the folder first, then run createCatagsFile() again.')
  }

  out_file <- file.path(path, 'categories.yaml')

  if (file.exists(out_file)) {
    stop('categories.yaml already exists at: ', out_file, '\n',
         '  Delete or rename the existing file to create a fresh one.')
  }

  cats <- list(
    categories = list(
      list(name = 'Ignore & Leave', description = NA,
           code = NA,             task = NA,  type = NA),
      list(name = 'Admin',          description = 'Team Admin',
           code = 'ENVEGM5.16',   task = '010',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Business',       description = 'Business Team Meeting',
           code = 'ENVHOABCPC120', task = '990',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Cap Admin',
           description = 'Administration, support and development of the M&F Modelling programme',
           code = 'ENVHOABCPC120', task = '01',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Cap Skills',     description = 'Capital Training',
           code = 'ENVHOABCPC120', task = '03',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Team Meeting',   description = 'Attend General Team Meetings',
           code = 'ENVEGM5.1.1',   task = '990',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Objective Setting', description = 'Performance Appraisal and Development',
           code = 'ENVEGM4.6',     task = '990',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Sick',           description = 'Sick',
           code = 'ENVABE',        task = '01',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Leave',          description = 'Leave',
           code = 'ENVABE',        task = '02',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Sick Half',      description = 'Sick Half',
           code = 'ENVABE',        task = '01',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Leave Half',     description = 'Leave Half',
           code = 'ENVABE',        task = '02',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Bank Holiday',   description = 'Bank Holiday',
           code = 'ENVABE',        task = '01',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Duty',           description = NA,
           code = NA,              task = NA,  type = NA),
      list(name = 'Duty Training',  description = 'Flood Forecasting Duty',
           code = 'ENVHOABCPC076', task = '03',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Get Training',   description = 'Prep Training',
           code = 'ENVEGM4.3',     task = '902',
           type = 'STAFF Plain Time-Straight Time'),
      list(name = 'Give Training',  description = 'Prep Training',
           code = 'ENVEGM4.3',     task = '901',
           type = 'STAFF Plain Time-Straight Time')
    )
  )

  yaml::write_yaml(cats, out_file)

  message('kronos: starter categories file written to ', out_file)
  message('kronos: edit the code and task fields to match your project codes ',
          'before using with createTC()')

  invisible(out_file)
}
